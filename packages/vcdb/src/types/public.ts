/**
 * @file Public top-level configuration shapes plus constraint constants
 * exposed to user-facing tooling (dashboard wizard, CLI).
 */

import type { Metric, Strategy } from "../types.ts";

export type { Metric, Strategy };

/** Options for creating a new vcdb collection. */
export interface DatabaseOptions {
  /** Vector dimensionality. */
  readonly dim: number;
  /** Distance metric for the primary vector index. */
  readonly metric?: Metric;
  /** Primary ANN strategy. */
  readonly strategy?: Strategy;
}

interface NumericRange {
  readonly min: number;
  readonly max: number;
  readonly default: number;
}

/** Tuning ranges for HNSW. Mirrors what the core implementation accepts. */
export const HNSW_CONSTRAINTS = {
  M: { min: 2, max: 100, default: 16 },
  efConstruction: { min: 10, max: 2000, default: 200 },
  efSearch: { min: 1, max: 2000, default: 50 },
} as const satisfies Record<string, NumericRange>;

/** Tuning ranges for IVF. */
export const IVF_CONSTRAINTS = {
  nlist: { min: 1, max: 65536, default: 100 },
  nprobe: { min: 1, max: 65536, default: 8 },
} as const satisfies Record<string, NumericRange>;
