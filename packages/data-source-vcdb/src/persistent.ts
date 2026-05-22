/**
 * @file Open existing `@vcdb.PersistentDB::init`-format directories as a
 * DataSource — no HTTP gateway, no CollectionManager registration. Used
 * by tools that talk to vcdb through the SDK's persistent FFI directly
 * (e.g. indexion's `orient-vcdb` cache) where the on-disk layout is
 * just `<baseDir>/data/<collection>.{data.bin,vwal}`.
 */

import {
  loadModule,
  PersistentDB,
  storageToCallbacks,
  type PersistentDBOptions,
} from "vcdb";
import { createNodeStorage } from "vcdb/storage/node";
import { StorageKind } from "vcdb/storage/types";
import {
  VECTOR_FIELD,
  type CollectionDescriptor,
  type DataRecord,
  type DataSource,
  type RecordId,
  type ScoredRecord,
} from "@vcdb/data-source";

/** Per-collection configuration the caller knows but the files don't carry. */
export type PersistentCollectionDefaults = {
  /** Vector dimension. Must match what wrote the data. */
  readonly dim: number;
  /** Capacity hint passed to PersistentDB.create; expanded on demand. */
  readonly capacity?: number;
  readonly metric?: PersistentDBOptions["metric"];
  readonly strategy?: PersistentDBOptions["strategy"];
};

export type PersistentDataSourceOptions = {
  /**
   * Base directory containing a `data/` subdir of PersistentDB-format
   * files. Matches the path you'd pass to `NodeStorage`'s baseDir or to
   * `vcdb-server --storage`.
   */
  readonly baseDir: string;
  /** Defaults applied to every collection unless overridden in perCollection. */
  readonly defaults: PersistentCollectionDefaults;
  /** Optional per-collection overrides keyed by collection name. */
  readonly perCollection?: Readonly<Record<string, PersistentCollectionDefaults>>;
};

const COLLECTION_FILE_RE = /^(.+?)\.(data\.bin|vwal)$/;

/**
 * Open a DataSource over an existing PersistentDB-format directory. The
 * MoonBit WASM module is loaded on first call.
 *
 * Discovery: every `<name>.data.bin` or `<name>.vwal` file under
 * `<baseDir>/data/` produces a collection named `<name>`. Collections
 * are opened lazily — the first read against a collection drives the
 * `PersistentDB.create` call which replays its WAL.
 */
export async function createPersistentDataSource(
  options: PersistentDataSourceOptions,
): Promise<DataSource> {
  await loadModule();
  const adapter = createNodeStorage({ baseDir: options.baseDir });
  // Indexion (and other PersistentDB callers) write both the WAL and the
  // snapshot under the Data kind; we wire the same callbacks to both
  // storage slots PersistentDB.create expects.
  const callbacks = storageToCallbacks(adapter, StorageKind.Data);
  const opened = new Map<string, PersistentDB>();

  function configFor(name: string): PersistentCollectionDefaults {
    return options.perCollection?.[name] ?? options.defaults;
  }

  async function discover(): Promise<string[]> {
    const files = await adapter.list(StorageKind.Data);
    const names = new Set<string>();
    for (const file of files) {
      const m = COLLECTION_FILE_RE.exec(file);
      if (m) names.add(m[1]);
    }
    return [...names].sort();
  }

  async function open(name: string): Promise<PersistentDB> {
    const cached = opened.get(name);
    if (cached) return cached;
    const cfg = configFor(name);
    // No `instanceId` here — `PersistentDB.create` is the SoT for that.
    const db = await PersistentDB.create({
      collectionName: name,
      basePath: "",
      dim: cfg.dim,
      capacity: cfg.capacity ?? 4096,
      metric: cfg.metric ?? "cosine",
      strategy: cfg.strategy ?? "hnsw",
      walStorage: callbacks,
      snapshotStorage: callbacks,
    });
    opened.set(name, db);
    return db;
  }

  function descriptorFor(name: string, db?: PersistentDB): CollectionDescriptor {
    const cfg = configFor(name);
    return {
      name,
      recordCount: db?.size() ?? 0,
      schema: {
        fields: [{ name: VECTOR_FIELD, kind: "vector", vectorDim: cfg.dim }],
      },
    };
  }

  return {
    health: async () => ({ ok: true }),

    listCollections: async () => {
      const names = await discover();
      return Promise.all(
        names.map(async (name) => descriptorFor(name, await open(name))),
      );
    },

    describeCollection: async (name) => descriptorFor(name, await open(name)),

    listRecords: async (name, opts) => {
      const db = await open(name);
      const limit = opts?.limit ?? 100;
      // PersistentDB.scroll takes the *last seen id* as offset, not a row
      // index. We can't translate `opts.offset: number` faithfully, so
      // first-page semantics: pass undefined and let consumers paginate
      // client-side (the dashboard's DataTable already does this).
      const entries = db.scroll(undefined, limit);
      return {
        records: entries.map((e) => ({
          id: bigintToRecordId(e.id),
          fields: payloadToFields(e.payload),
        })),
        total: db.size(),
      };
    },

    getRecord: async (name, id) => {
      const db = await open(name);
      const point = db.get(idToBigint(id));
      if (!point.found) return null;
      return {
        id,
        fields: {
          ...payloadToFields(point.payload),
          [VECTOR_FIELD]: point.vector,
        },
      };
    },

    search: async (name, query) => {
      if (query.kind !== "vector") {
        throw new Error(
          `Persistent data source only supports vector search; got "${query.kind}"`,
        );
      }
      const db = await open(name);
      const hits = db.search(query.vector, query.k ?? 10);
      const records: ScoredRecord[] = hits.map((hit) => ({
        id: bigintToRecordId(hit.id),
        score: hit.score,
        fields: payloadToFields(hit.payload),
      }));
      return { records };
    },

    upsertRecord: async (name, record) => {
      const db = await open(name);
      await db.upsert([
        {
          id: idToBigint(record.id),
          vector: extractVector(record),
          payload: payloadOnly(record),
        },
      ]);
    },

    upsertRecords: async (name, records) => {
      const db = await open(name);
      await db.upsert(
        records.map((record) => ({
          id: idToBigint(record.id),
          vector: extractVector(record),
          payload: payloadOnly(record),
        })),
      );
    },

    deleteRecord: async (name, id) => {
      const db = await open(name);
      await db.remove(idToBigint(id));
    },
  };
}

// ---------------------------------------------------------------------------
// id and field helpers
// ---------------------------------------------------------------------------

function bigintToRecordId(id: bigint): RecordId {
  // PersistentDB ids can exceed Number.MAX_SAFE_INTEGER, so we render to
  // a decimal string. DataTable / inspector display this verbatim.
  return id.toString();
}

function idToBigint(id: RecordId): bigint {
  if (typeof id === "number") return BigInt(id);
  // String form: accept either decimal or 0x-prefixed hex.
  if (id.startsWith("0x") || id.startsWith("0X")) {
    return BigInt(id);
  }
  return BigInt(id);
}

function payloadToFields(
  payload: Record<string, unknown> | null,
): DataRecord["fields"] {
  return (payload ?? {}) as DataRecord["fields"];
}

function extractVector(record: DataRecord): number[] {
  const value = record.fields[VECTOR_FIELD];
  if (!Array.isArray(value) || !value.every((n) => typeof n === "number")) {
    throw new Error(
      `DataRecord.fields["${VECTOR_FIELD}"] must be a number[] for PersistentDB`,
    );
  }
  return value as number[];
}

function payloadOnly(record: DataRecord): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(record.fields)) {
    if (key === VECTOR_FIELD) continue;
    out[key] = value;
  }
  return out;
}
