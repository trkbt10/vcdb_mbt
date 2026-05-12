export type AttrValue = string | number | boolean | null;
export type Attrs = Record<string, AttrValue>;
export type Metric = "Cosine" | "L2" | "Dot";
export type Strategy = "Bruteforce" | "HNSW" | "IVF";

export type CollectionStats = {
  size: number;
  dim: number;
  metric: Metric;
  strategy: Strategy;
};

export type CollectionInfo = {
  name: string;
  vectors_count: number;
  dim: number;
  metric: Metric;
  strategy: Strategy;
};

export type SearchHit = {
  id: number;
  score: number;
  attrs: Attrs | null;
  vector?: number[];
};

export type PointRecord = {
  id: number;
  vector: number[];
  attrs: Attrs;
};

export type BulkResult = {
  ok: boolean;
  results: Array<{ id: number; ok: boolean }>;
};

export type VectorRowInput = {
  id: number;
  vector: number[];
  attrs?: Attrs;
};

export type ListVectorsResult = {
  rows: Array<{ id: number; attrs: Attrs | null }>;
  total: number;
  offset: number;
  limit: number;
};
