// @vcdb/data-source-vcdb — adapts @vcdb/api-client to the DataSource
// interface from @vcdb/data-source. Vector → DataRecord mapping uses
// VECTOR_FIELD ("__vector") for the primary embedding.

import {
  createGatewayClient,
  type Attrs,
  type CollectionInfo,
  type PointRecord,
  type VectorRowInput,
} from "@vcdb/api-client";
import {
  VECTOR_FIELD,
  type CollectionDescriptor,
  type CreateCollectionInput,
  type DataRecord,
  type DataSource,
  type ListOptions,
  type ListPage,
  type RecordId,
  type SearchQuery,
  type SearchResult,
} from "@vcdb/data-source";

export type VcdbDataSourceOptions = {
  apiBase?: string;
};

export function createVcdbDataSource(options: VcdbDataSourceOptions = {}): DataSource {
  const client = createGatewayClient(options.apiBase ?? "");

  async function listRecords(collection: string, opts?: ListOptions): Promise<ListPage> {
    const page = await client.listVectors(collection, {
      limit: opts?.limit,
      offset: opts?.offset,
    });
    return {
      records: page.rows.map((row) => ({
        id: row.id,
        fields: (row.attrs ?? {}) as DataRecord["fields"],
      })),
      total: page.total,
    };
  }

  async function getRecord(collection: string, id: RecordId): Promise<DataRecord | null> {
    const point = await client.getPoint(collection, idToNumber(id));
    return point ? pointToRecord(point) : null;
  }

  async function search(collection: string, query: SearchQuery): Promise<SearchResult> {
    if (query.kind !== "vector") {
      throw new Error(`vcdb data source supports only vector search; got "${query.kind}"`);
    }
    const hits = await client.search(collection, query.vector, { k: query.k });
    return {
      records: hits.map((hit) => ({
        id: hit.id,
        score: hit.score,
        fields: {
          ...((hit.attrs ?? {}) as DataRecord["fields"]),
          ...(hit.vector ? { [VECTOR_FIELD]: hit.vector } : {}),
        },
      })),
    };
  }

  async function upsertRecord(collection: string, record: DataRecord): Promise<void> {
    await client.upsertPoint(collection, idToNumber(record.id), {
      vector: extractVector(record),
      attrs: extractAttrs(record),
    });
  }

  async function upsertRecords(collection: string, records: DataRecord[]): Promise<void> {
    const rows: VectorRowInput[] = records.map((record) => ({
      id: idToNumber(record.id),
      vector: extractVector(record),
      attrs: extractAttrs(record),
    }));
    await client.bulkUpsert(collection, rows);
  }

  return {
    health: () => client.health(),
    listCollections: async () => (await client.listCollections()).map(infoToDescriptor),
    describeCollection: async (name) => infoToDescriptor(await client.getCollection(name)),
    listRecords,
    getRecord,
    search,
    upsertRecord,
    upsertRecords,
    deleteRecord: async (collection, id) => {
      await client.deletePoint(collection, idToNumber(id));
    },
    createCollection: async (input: CreateCollectionInput) => {
      const config = input.config as { dim: number; metric?: string; strategy?: string };
      await client.createCollection({ name: input.name, config });
    },
    deleteCollection: async (name) => {
      await client.deleteCollection(name);
    },
  };
}

function infoToDescriptor(info: CollectionInfo): CollectionDescriptor {
  return {
    name: info.name,
    recordCount: info.vectors_count,
    schema: {
      fields: [{ name: VECTOR_FIELD, kind: "vector", vectorDim: info.dim }],
    },
  };
}

function pointToRecord(point: PointRecord): DataRecord {
  return {
    id: point.id,
    fields: {
      ...(point.attrs as DataRecord["fields"]),
      [VECTOR_FIELD]: point.vector,
    },
  };
}

function idToNumber(id: RecordId): number {
  if (typeof id === "number") return id;
  const parsed = Number(id);
  if (!Number.isFinite(parsed)) {
    throw new Error(`vcdb requires numeric record ids; got ${JSON.stringify(id)}`);
  }
  return parsed;
}

function extractVector(record: DataRecord): number[] {
  const value = record.fields[VECTOR_FIELD];
  if (!Array.isArray(value) || !value.every((n) => typeof n === "number")) {
    throw new Error(`DataRecord.fields["${VECTOR_FIELD}"] must be a number[] for vcdb`);
  }
  return value as number[];
}

function extractAttrs(record: DataRecord): Attrs {
  const attrs: Attrs = {};
  for (const [key, value] of Object.entries(record.fields)) {
    if (key === VECTOR_FIELD) continue;
    if (
      typeof value === "string" ||
      typeof value === "number" ||
      typeof value === "boolean" ||
      value === null
    ) {
      attrs[key] = value;
    }
  }
  return attrs;
}
