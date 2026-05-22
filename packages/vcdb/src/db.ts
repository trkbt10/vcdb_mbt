/**
 * @file VectorDB and PersistentDB — the two database classes.
 *
 * VectorDB: in-memory, no persistence, synchronous API.
 * PersistentDB: WAL + snapshot, async mutations, sync reads.
 *
 * Both hide MoonBit FFI details (wire bytes, tuple encoding).
 * Consumers work with VectorId (bigint for Int64Id) and plain JS objects.
 *
 * NOTE: Bytes16Id support in write operations (add/upsert) is currently
 * blocked by a limitation in core/attr/bptree.mbt. Only Int64Id is
 * fully supported for mutations at this time.
 */
import type {
  VectorDbFfi,
  PersistentFfi,
  AsyncStorageCallbacks,
} from "./ffi/types.js";
import type {
  VectorId,
  Metric,
  Strategy,
  SearchResult,
  SearchHit,
  PointRecord,
  ScrollEntry,
} from "./types.js";
import type { StorageAdapter, StorageKindType } from "./storage/types.js";
import { getVectorDbFfi, getPersistentFfi, isModuleLoaded } from "./ffi/loader.js";
import {
  int64ToWireBytes,
  wireBytesBigInt,
  nowNs,
} from "./ffi/vector-id.js";


const parsePayload = (json: string): Record<string, unknown> | null => {
  if (!json) return null;
  try {
    return JSON.parse(json) as Record<string, unknown>;
  } catch {
    return null;
  }
};

/**
 * Allocate a PersistentDB instance id.
 *
 * Prefer the MoonBit-side allocator (`persistent_allocate_id`) when the
 * loaded WASM build exports it — that keeps the id space aligned with the
 * runtime that actually owns the persistent state. Older builds don't
 * export the function; in that case we fall back to a JS-side counter
 * that is unique within this module. The counter starts high enough that
 * a future overlap with WASM-allocated ids stays unlikely.
 *
 * This is the single source of truth for "where does an instance id come
 * from?" — every consumer (including the wrappers in @vcdb/data-source-vcdb)
 * should rely on PersistentDB.create's default rather than rolling their own.
 */
let jsAllocatedInstanceIds = 1 << 20;
function allocatePersistentInstanceId(ffi: PersistentFfi): number {
  if (typeof ffi.persistent_allocate_id === "function") {
    return ffi.persistent_allocate_id();
  }
  const id = jsAllocatedInstanceIds;
  jsAllocatedInstanceIds += 1;
  return id;
}

/* ── VectorId ↔ wire bytes ───────────────────────────────────── */

/**
 * Encode a VectorId to the 16-byte wire format.
 * VectorId is bigint (Int64Id only — Bytes16Id write path is not yet supported).
 */
function encodeId(id: VectorId): Uint8Array {
  return int64ToWireBytes(id);
}

/**
 * Decode a VectorId from the 16-byte wire format.
 * Returns bigint (treating the result as Int64Id).
 */
function decodeId(buf: Uint8Array): VectorId {
  return wireBytesBigInt(buf);
}

/* ══════════════════════════════════════════════════════════════ */
/*  VectorDB — in-memory, no persistence                        */
/* ══════════════════════════════════════════════════════════════ */

export class VectorDB {
  private instanceId: number;
  private disposed = false;

  constructor(dim: number, strategy: Strategy = "bruteforce") {
    const ffi = getVectorDbFfi();
    switch (strategy) {
      case "hnsw":
        this.instanceId = ffi.vcdb_create_hnsw(dim);
        break;
      case "ivf":
        this.instanceId = ffi.vcdb_create_ivf(dim);
        break;
      default:
        this.instanceId = ffi.vcdb_create(dim);
    }
  }

  private checkDisposed(): void {
    if (this.disposed) throw new Error("VectorDB instance has been disposed");
  }

  private get ffi(): VectorDbFfi {
    return getVectorDbFfi();
  }

  get size(): number {
    this.checkDisposed();
    return this.ffi.vcdb_size(this.instanceId);
  }

  get dim(): number {
    this.checkDisposed();
    return this.ffi.vcdb_dim(this.instanceId);
  }

  add(id: VectorId, vector: number[]): void {
    this.checkDisposed();
    const result = this.ffi.vcdb_add(this.instanceId, encodeId(id), vector);
    if (result === -2) throw new Error("Vector already exists");
    if (result !== 0) throw new Error("Failed to add vector");
  }

  upsert(id: VectorId, vector: number[]): void {
    this.checkDisposed();
    const result = this.ffi.vcdb_upsert(this.instanceId, encodeId(id), vector);
    if (result !== 0) throw new Error("Failed to upsert vector");
  }

  get_(id: VectorId): number[] | undefined {
    this.checkDisposed();
    const result = this.ffi.vcdb_get(this.instanceId, encodeId(id));
    return result._1 === 1 ? result._0 : undefined;
  }

  search(query: number[], k: number): SearchResult[] {
    this.checkDisposed();
    const results = this.ffi.vcdb_search(this.instanceId, query, k);
    return results.map((r) => ({
      id: decodeId(r._0),
      score: r._1,
    }));
  }

  has(id: VectorId): boolean {
    this.checkDisposed();
    return this.ffi.vcdb_has(this.instanceId, encodeId(id)) === 1;
  }

  remove(id: VectorId): boolean {
    this.checkDisposed();
    return this.ffi.vcdb_remove(this.instanceId, encodeId(id)) === 1;
  }

  serialize(): Uint8Array {
    this.checkDisposed();
    return this.ffi.vcdb_serialize(this.instanceId);
  }

  static deserialize(data: Uint8Array): VectorDB {
    const ffi = getVectorDbFfi();
    const instanceId = ffi.vcdb_deserialize(data);
    const db = Object.create(VectorDB.prototype) as VectorDB;
    db.instanceId = instanceId;
    db.disposed = false;
    return db;
  }

  dispose(): void {
    if (!this.disposed) {
      this.ffi.vcdb_destroy(this.instanceId);
      this.disposed = true;
    }
  }
}

/* ══════════════════════════════════════════════════════════════ */
/*  PersistentDB — WAL + snapshot persistence                   */
/* ══════════════════════════════════════════════════════════════ */

export interface PersistentDBOptions {
  /** Explicit instance ID. If omitted, allocated by MoonBit runtime. Useful when a stable ID is needed (e.g. Durable Objects). */
  instanceId?: number;
  dim: number;
  capacity: number;
  metric?: Metric;
  strategy?: Strategy;
  walStorage: AsyncStorageCallbacks;
  snapshotStorage: AsyncStorageCallbacks;
  collectionName?: string;
  basePath?: string;
}

export class PersistentDB {
  private constructor(
    private readonly ffi: PersistentFfi,
    private readonly instanceId: number,
  ) {}

  static async create(options: PersistentDBOptions): Promise<PersistentDB> {
    if (!isModuleLoaded()) {
      throw new Error("PersistentDB.create() requires loadModule() to have been called first.");
    }
    const ffi = getPersistentFfi();
    const instanceId = options.instanceId ?? allocatePersistentInstanceId(ffi);
    const {
      dim,
      capacity,
      walStorage,
      snapshotStorage,
      metric = "cosine",
      strategy = "hnsw",
      collectionName = "db",
      basePath = "",
    } = options;

    ffi.persistent_register_wal_storage(
      instanceId,
      walStorage.read, walStorage.write, walStorage.atomicWrite,
      walStorage.del, walStorage.exists, walStorage.list,
    );
    ffi.persistent_register_snapshot_storage(
      instanceId,
      snapshotStorage.read, snapshotStorage.write, snapshotStorage.atomicWrite,
      snapshotStorage.del, snapshotStorage.exists, snapshotStorage.list,
    );

    await ffi.persistent_init(
      instanceId, collectionName, basePath, dim, capacity, metric, strategy,
    );

    return new PersistentDB(ffi, instanceId);
  }

  /* ── Mutations (async — WAL I/O) ───────────────────────────── */

  async upsert(
    points: readonly { id: VectorId; vector: number[]; payload: Record<string, unknown> }[],
  ): Promise<void> {
    const ffiPoints = points.map((p) => ({
      _0: encodeId(p.id),
      _1: p.vector,
      _2: JSON.stringify(p.payload),
    }));
    await this.ffi.persistent_upsert(this.instanceId, ffiPoints, nowNs());
  }

  async remove(id: VectorId): Promise<boolean> {
    return this.ffi.persistent_remove(this.instanceId, encodeId(id), nowNs());
  }

  async updateAttrs(id: VectorId, attrs: Record<string, unknown>): Promise<boolean> {
    return this.ffi.persistent_update_attrs(
      this.instanceId, encodeId(id), JSON.stringify(attrs), nowNs(),
    );
  }

  async checkpoint(): Promise<void> {
    await this.ffi.persistent_checkpoint(this.instanceId);
  }

  async compact(): Promise<number> {
    return this.ffi.persistent_compact(this.instanceId);
  }

  /* ── Reads (synchronous — in-memory) ───────────────────────── */

  search(vector: number[], topK: number, filterJson: string = ""): readonly SearchHit[] {
    return this.ffi.persistent_search(this.instanceId, vector, topK, true, filterJson)
      .map((r) => ({ id: decodeId(r._0), score: r._1, payload: parsePayload(r._2) }));
  }

  get(id: VectorId): PointRecord {
    const r = this.ffi.persistent_get(this.instanceId, encodeId(id), true);
    return { found: r._0, vector: r._1, payload: r._0 ? parsePayload(r._2) : null };
  }

  has(id: VectorId): boolean {
    return this.ffi.persistent_has(this.instanceId, encodeId(id));
  }

  scroll(offset: VectorId | undefined, limit: number): readonly ScrollEntry[] {
    const offsetBytes = offset !== undefined ? encodeId(offset) : new Uint8Array(0);
    return this.ffi.persistent_scroll(this.instanceId, offsetBytes, limit, true)
      .map((r) => ({ id: decodeId(r._0), payload: parsePayload(r._1) }));
  }

  scrollFiltered(filterJson: string, offset: VectorId | undefined, limit: number): readonly ScrollEntry[] {
    const offsetBytes = offset !== undefined ? encodeId(offset) : new Uint8Array(0);
    return this.ffi.persistent_scroll_filtered(this.instanceId, filterJson, offsetBytes, limit, true)
      .map((r) => ({ id: decodeId(r._0), payload: parsePayload(r._1) }));
  }

  countFiltered(filterJson: string): number {
    return this.ffi.persistent_count_filtered(this.instanceId, filterJson);
  }

  /* ── Diagnostics ───────────────────────────────────────────── */

  size(): number { return this.ffi.persistent_db_size(this.instanceId); }
  rawSize(): number { return this.ffi.persistent_db_raw_size(this.instanceId); }
  dim(): number { return this.ffi.persistent_db_dim(this.instanceId); }

  /* ── Lifecycle ─────────────────────────────────────────────── */

  destroy(): void { this.ffi.persistent_destroy(this.instanceId); }
}

/* ══════════════════════════════════════════════════════════════ */
/*  Storage → AsyncStorageCallbacks conversion                  */
/* ══════════════════════════════════════════════════════════════ */

export interface KeyValueStore {
  read(path: string): Promise<Uint8Array | null>;
  write(path: string, data: Uint8Array): Promise<void>;
  delete(path: string): Promise<void>;
  exists(path: string): Promise<boolean>;
  list(): Promise<string[]>;
}

export function kvStoreToCallbacks(store: KeyValueStore): AsyncStorageCallbacks {
  return {
    read: async (path: string, _kind: number): Promise<Uint8Array> => {
      const data = await store.read(path);
      if (data === null) throw new Error(`Persistent storage read failed: ${path} not found`);
      return data;
    },
    write: (path, data, _kind) => store.write(path, data),
    atomicWrite: (path, data, _kind) => store.write(path, data),
    del: (path, _kind) => store.delete(path),
    exists: (path, _kind) => store.exists(path),
    list: (_kind) => store.list(),
  };
}

export function storageToCallbacks(adapter: StorageAdapter, kind: StorageKindType): AsyncStorageCallbacks {
  return {
    read: async (path: string, _kind: number): Promise<Uint8Array> => {
      const data = await adapter.read(path, kind);
      if (data === null) throw new Error(`Persistent storage read failed: ${path} not found`);
      return data;
    },
    write: (path, data, _kind) => adapter.write(path, data, kind),
    atomicWrite: (path, data, _kind) => adapter.write(path, data, kind),
    del: (path, _kind) => adapter.delete(path, kind),
    exists: (path, _kind) => adapter.exists(path, kind),
    list: (_kind) => adapter.list(kind),
  };
}

