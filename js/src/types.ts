/**
 * @file Public domain types for vcdb.
 *
 * These types define the vcdb public API surface.
 * They intentionally have no dependency on FFI internals.
 */

/** Unique identifier for a vector. Uses bigint for full Int64 range. */
export type VectorId = bigint;

/** Distance/similarity metric. */
export type Metric = "cosine" | "l2" | "dot";

/** ANN (Approximate Nearest Neighbor) indexing strategy. */
export type Strategy = "bruteforce" | "hnsw" | "ivf";

/** A single search result. */
export interface SearchResult {
  readonly id: VectorId;
  readonly score: number;
}

/** A search result with optional payload. */
export interface SearchHit {
  readonly id: VectorId;
  readonly score: number;
  readonly payload: Record<string, unknown> | null;
}

/** A point record retrieved by ID. */
export interface PointRecord {
  readonly found: boolean;
  readonly vector: number[];
  readonly payload: Record<string, unknown> | null;
}

/** An entry from scroll (cursor-based iteration). */
export interface ScrollEntry {
  readonly id: VectorId;
  readonly payload: Record<string, unknown> | null;
}
