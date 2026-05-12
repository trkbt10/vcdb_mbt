/**
 * @file Public domain types for vcdb.
 *
 * This is the single source of truth for all public-facing types.
 * Other modules import from here; index.ts re-exports them.
 */

/** Unique identifier for a vector. Uses bigint for full Int64 range. */
export type VectorId = bigint;

/** Distance/similarity metric. */
export type Metric = "cosine" | "l2" | "dot";

/** ANN (Approximate Nearest Neighbor) indexing strategy. */
export type Strategy = "bruteforce" | "hnsw" | "ivf";

/** A single search result (score only, no payload). */
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

// =============================================================================
// Attribute / field shapes
//
// The dashboard wizard and any user-facing configuration UI need to describe
// the attribute fields a collection indexes. Keeping these in the public
// types module lets the SDK be self-describing.
// =============================================================================

/** Operations an attribute index can answer. */
export type AttrOp = "eq" | "range" | "exists";

/** Scalar attribute field type. */
export type FieldType = "string" | "number" | "boolean";

/** Definition of one attribute column inside an attribute index. */
export interface FieldDef {
  /** JSON-pointer-style path into the payload object. */
  readonly path: string;
  readonly type: FieldType;
  /** Non-empty list of operations the index must support for this field. */
  readonly ops: ReadonlyArray<AttrOp>;
}

/** Ordering for composite (multi-field) attribute indexes. */
export type CompositeOrder = "declared" | "alpha";
