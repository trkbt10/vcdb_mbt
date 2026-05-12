// @vcdb/data-source — protocol-neutral abstraction for browsing record-shaped
// data. db-viewer consumes this interface; any backend (vcdb gateway,
// in-process SDK, indexion-style stores, mock fixtures) implements it.

export type RecordId = string | number;

export type FieldValue =
  | string
  | number
  | boolean
  | null
  | number[]
  | Record<string, unknown>
  | unknown[];

export type DataRecord = {
  id: RecordId;
  fields: Record<string, FieldValue>;
};

export type FieldKind =
  | "string"
  | "number"
  | "boolean"
  | "vector"
  | "json"
  | "unknown";

export type FieldDescriptor = {
  name: string;
  kind: FieldKind;
  vectorDim?: number;
};

export type CollectionSchema = {
  fields: FieldDescriptor[];
};

export type CollectionDescriptor = {
  name: string;
  recordCount: number;
  schema?: CollectionSchema;
};

export type ListOptions = {
  limit?: number;
  offset?: number;
  cursor?: string;
};

export type ListPage = {
  records: DataRecord[];
  total: number;
  nextCursor?: string;
};

export type SearchQuery =
  | { kind: "vector"; field: string; vector: number[]; k?: number }
  | { kind: "text"; field: string; text: string; limit?: number }
  | { kind: "filter"; filter: unknown; limit?: number };

export type ScoredRecord = DataRecord & { score?: number };

export type SearchResult = {
  records: ScoredRecord[];
};

export type CreateCollectionInput = {
  name: string;
  // Backend-specific configuration; not typed at this layer. Implementations
  // know the shape they expect (e.g. vcdb: { dim, metric, strategy }).
  config: Record<string, unknown>;
};

export interface DataSource {
  health(): Promise<{ ok: boolean }>;
  listCollections(): Promise<CollectionDescriptor[]>;
  describeCollection(name: string): Promise<CollectionDescriptor>;
  listRecords(collection: string, options?: ListOptions): Promise<ListPage>;
  getRecord(collection: string, id: RecordId): Promise<DataRecord | null>;
  search(collection: string, query: SearchQuery): Promise<SearchResult>;
  upsertRecord(collection: string, record: DataRecord): Promise<void>;
  upsertRecords(collection: string, records: DataRecord[]): Promise<void>;
  deleteRecord(collection: string, id: RecordId): Promise<void>;

  // Registry operations are optional — read-only sources need not implement them.
  createCollection?(input: CreateCollectionInput): Promise<void>;
  deleteCollection?(name: string): Promise<void>;
}

// Reserved field name used by backends that surface a primary vector alongside
// other attributes (e.g. vcdb). DataSource implementations may map this key
// to their native vector representation.
export const VECTOR_FIELD = "__vector";
