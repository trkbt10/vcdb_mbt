/**
 * @file Index configuration shapes.
 *
 * Describes how to declare vector / attribute / combined indexes on a vcdb
 * collection. UI tooling (e.g. the dashboard wizard) and programmatic
 * callers consume these types to produce configuration objects the
 * gateway and core accept.
 */

import type { CompositeOrder, FieldDef, Metric } from "../types.ts";

// -----------------------------------------------------------------------------
// Vector indexes
// -----------------------------------------------------------------------------

export type VectorIndexKind = "hnsw" | "ivf" | "bruteforce";

export interface HnswVectorIndex {
  readonly kind: "hnsw";
  readonly metric?: Metric;
  /** Max neighbours per node. */
  readonly M?: number;
  /** Neighbour candidate list size during build. */
  readonly efConstruction?: number;
  /** Neighbour candidate list size during search. */
  readonly efSearch?: number;
}

export interface IvfVectorIndex {
  readonly kind: "ivf";
  readonly metric?: Metric;
  /** Number of inverted lists / clusters. */
  readonly nlist?: number;
  /** Probe count at query time. */
  readonly nprobe?: number;
}

export interface BruteforceVectorIndex {
  readonly kind: "bruteforce";
  readonly metric?: Metric;
}

export type VectorIndexConfig =
  | HnswVectorIndex
  | IvfVectorIndex
  | BruteforceVectorIndex;

// -----------------------------------------------------------------------------
// Attribute indexes
// -----------------------------------------------------------------------------

export type AttributeIndexKind = "bptree" | "lsm" | "bitmap" | "basic";

export interface AttributeIndexConfig {
  readonly kind: AttributeIndexKind;
  readonly fields: FieldDef[];
  /** Composite key ordering — applies to bptree/lsm. */
  readonly order?: CompositeOrder;
}

// -----------------------------------------------------------------------------
// Combined index (vector + attribute with an execution strategy)
// -----------------------------------------------------------------------------

export type CombinedExecutionStrategy = "auto" | "prefilter" | "postfilter";

export interface CombinedIndexConfig {
  readonly kind: "combined";
  readonly vector: VectorIndexConfig;
  readonly attribute: AttributeIndexConfig;
  readonly execution?: CombinedExecutionStrategy;
}

// -----------------------------------------------------------------------------
// Top-level discriminated union
// -----------------------------------------------------------------------------

export type IndexConfig =
  | VectorIndexConfig
  | AttributeIndexConfig
  | CombinedIndexConfig;

/** Lifecycle state of a declared index on the server. */
export type IndexStatus = "ready" | "building" | "error";

/** A named index entry, as returned by `listIndexes()`. */
export interface IndexEntry {
  readonly id: string;
  readonly name: string;
  readonly def: IndexConfig;
  readonly status: IndexStatus;
  /** Set when `status === "error"`. */
  readonly errorMessage?: string;
}

/** Input shape accepted by `createIndex()`. */
export interface CreateIndexInput {
  readonly name: string;
  readonly config: IndexConfig;
  /** If true, replace any existing index with the same name. */
  readonly replace?: boolean;
}
