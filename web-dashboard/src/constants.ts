/**
 * Default values for the gateway-backed dashboard UI.
 */

export const DEFAULT_PORT = 6333;
export const DEFAULT_HOST = "localhost";

/**
 * Index strategy options (Single Source of Truth)
 */
import type { OptionGridItem } from "@/components/ui";

export type VectorStrategyKind = "hnsw" | "ivf" | "bruteforce";
export type AttributeStrategyKind = "bptree" | "lsm" | "bitmap" | "basic";

export const VECTOR_STRATEGIES: OptionGridItem<VectorStrategyKind>[] = [
  { value: "hnsw", label: "HNSW", description: "Fast graph-based search" },
  { value: "ivf", label: "IVF", description: "Clustering-based, memory efficient" },
  { value: "bruteforce", label: "Bruteforce", description: "Exact search, small datasets" },
];

export const ATTR_STRATEGIES: OptionGridItem<AttributeStrategyKind>[] = [
  { value: "bptree", label: "B+ Tree", description: "Range queries, balanced" },
  { value: "lsm", label: "LSM", description: "Write-heavy workloads" },
  { value: "bitmap", label: "Bitmap", description: "Low cardinality fields" },
  { value: "basic", label: "Basic", description: "Simple hash lookup" },
];

export const EXECUTION_OPTIONS = [
  { value: "auto", label: "Auto (choose based on selectivity)" },
  { value: "prefilter", label: "Prefilter (filter first, then search)" },
  { value: "postfilter", label: "Postfilter (search first, then filter)" },
] as const;

/**
 * Vector metric options
 */
export const METRIC_OPTIONS = [
  { value: "cosine", label: "Cosine" },
  { value: "l2", label: "L2 (Euclidean)" },
  { value: "dot", label: "Dot Product" },
] as const;

/**
 * Composite index field order options
 */
export const ORDER_OPTIONS = [
  { value: "declared", label: "Declared (as defined)" },
  { value: "alpha", label: "Alphabetical (sorted)" },
] as const;

/**
 * Field type options for attribute indexes
 */
export const TYPE_OPTIONS = [
  { value: "string", label: "String" },
  { value: "number", label: "Number" },
  { value: "boolean", label: "Boolean" },
] as const;

/**
 * Attribute operation options
 */
export type AttrOp = "eq" | "range" | "exists";

export const OP_OPTIONS: { value: AttrOp; label: string }[] = [
  { value: "eq", label: "Equality (eq)" },
  { value: "range", label: "Range (range)" },
  { value: "exists", label: "Exists (exists)" },
];
