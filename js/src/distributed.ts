/**
 * @file High-level distributed VectorDB operations.
 *
 * Wraps DistributedFfi with JS-idiomatic types, hiding MoonBit
 * tuple encoding. Provides scatter-gather primitives for
 * multi-shard PersistentDB deployments.
 *
 * This module handles:
 *   - CRUSH-based placement (which shard owns which vector)
 *   - Upsert grouping (partition points by target shard)
 *   - Result merging (search, scroll, count across shards)
 *   - Partial failure reporting (which shards failed)
 *
 * Consumers provide shard-level query execution; this module
 * handles routing and merge logic.
 */
import type { DistributedFfi } from "./ffi/types.js";
import type { VectorId, SearchHit, ScrollEntry } from "./index.js";
import { toHiLo, fromHiLo } from "./ffi/vector-id.js";

const parsePayload = (json: string): Record<string, unknown> | null => {
  if (!json) return null;
  try {
    return JSON.parse(json) as Record<string, unknown>;
  } catch {
    return null;
  }
};

/* ── Public types ────────────────────────────────────────────── */

/** A single shard's search results (or error). */
export type ShardSearchResult =
  | { shardIndex: number; hits: readonly SearchHit[] }
  | { shardIndex: number; error: string };

/** A single shard's scroll results (or error). */
export type ShardScrollResult =
  | { shardIndex: number; entries: readonly ScrollEntry[] }
  | { shardIndex: number; error: string };

/** A single shard's count result (or error). */
export type ShardCountResult =
  | { shardIndex: number; count: number }
  | { shardIndex: number; error: string };

/** Result of a distributed merge, with partial failure info. */
export interface MergedResult<T> {
  /** Merged result. */
  data: T;
  /** Shard indices that contributed to the result. */
  succeededShards: number[];
  /** Shard-level errors (empty if all shards succeeded). */
  errors: ReadonlyArray<{ shardIndex: number; message: string }>;
}

/** A group of upsert points destined for a specific shard. */
export interface UpsertGroup {
  shardIndex: number;
  points: ReadonlyArray<{
    id: VectorId;
    vector: number[];
    payload: string;
  }>;
}

/* ── Placement ───────────────────────────────────────────────── */

/**
 * Determine which placement group (shard) a vector ID belongs to.
 *
 * Uses CRUSH placement, which provides better rebalancing properties
 * than simple hash-mod.
 */
export function placementGroup(
  ffi: DistributedFfi,
  id: VectorId,
  pgCount: number,
): number {
  const { hi, lo } = toHiLo(id);
  return ffi.crush_placement_group(hi, lo, pgCount);
}

/* ── Upsert grouping ─────────────────────────────────────────── */

/**
 * Partition upsert points by their target shard.
 *
 * Returns an array of groups, each containing the shard index
 * and the points that should be upserted into that shard.
 */
export function groupUpsert(
  ffi: DistributedFfi,
  points: ReadonlyArray<{
    id: VectorId;
    vector: number[];
    payload: Record<string, unknown>;
  }>,
  pgCount: number,
): UpsertGroup[] {
  const ffiPoints = points.map((p) => {
    const { hi, lo } = toHiLo(p.id);
    return { _0: hi, _1: lo, _2: p.vector, _3: JSON.stringify(p.payload) };
  });

  const groups = ffi.distributed_group_upsert(ffiPoints, pgCount);

  return groups.map((g) => ({
    shardIndex: g._0,
    points: g._1.map((p) => ({
      id: fromHiLo(p._0, p._1),
      vector: p._2,
      payload: p._3,
    })),
  }));
}

/* ── Merge operations ────────────────────────────────────────── */

/**
 * Merge search results from multiple shards.
 *
 * Each shard result is either hits or an error. Successful shards'
 * results are merged by score; failed shards are reported in errors.
 */
export function mergeSearch(
  ffi: DistributedFfi,
  shardResults: readonly ShardSearchResult[],
  topK: number,
): MergedResult<readonly SearchHit[]> {
  const ffiInput = shardResults.map((r) => {
    if ("error" in r) {
      return { _0: r.shardIndex, _1: [] as Array<{ _0: number; _1: number; _2: number; _3: string }>, _2: r.error };
    }
    const hits = r.hits.map((h) => {
      const { hi, lo } = toHiLo(h.id);
      return { _0: hi, _1: lo, _2: h.score, _3: JSON.stringify(h.payload ?? {}) };
    });
    return { _0: r.shardIndex, _1: hits, _2: "" };
  });

  const result = ffi.distributed_merge_search(ffiInput, topK);

  return {
    data: result._0.map((r) => ({
      id: fromHiLo(r._0, r._1),
      score: r._2,
      payload: parsePayload(r._3),
    })),
    succeededShards: result._1 as number[],
    errors: result._2.map((e) => ({ shardIndex: e._0, message: e._1 })),
  };
}

/**
 * Merge scroll results from multiple shards.
 *
 * Results are merged in ID-ascending order, truncated to limit.
 */
export function mergeScroll(
  ffi: DistributedFfi,
  shardResults: readonly ShardScrollResult[],
  limit: number,
): MergedResult<readonly ScrollEntry[]> {
  const ffiInput = shardResults.map((r) => {
    if ("error" in r) {
      return { _0: r.shardIndex, _1: [] as Array<{ _0: number; _1: number; _2: string }>, _2: r.error };
    }
    const entries = r.entries.map((e) => {
      const { hi, lo } = toHiLo(e.id);
      return { _0: hi, _1: lo, _2: JSON.stringify(e.payload ?? {}) };
    });
    return { _0: r.shardIndex, _1: entries, _2: "" };
  });

  const result = ffi.distributed_merge_scroll(ffiInput, limit);

  return {
    data: result._0.map((r) => ({
      id: fromHiLo(r._0, r._1),
      payload: parsePayload(r._2),
    })),
    succeededShards: result._1 as number[],
    errors: result._2.map((e) => ({ shardIndex: e._0, message: e._1 })),
  };
}

/**
 * Merge count results from multiple shards.
 *
 * Sums counts from successful shards; reports failed shards.
 */
export function mergeCount(
  ffi: DistributedFfi,
  shardResults: readonly ShardCountResult[],
): MergedResult<number> {
  const ffiInput = shardResults.map((r) => {
    if ("error" in r) {
      return { _0: r.shardIndex, _1: 0, _2: r.error };
    }
    return { _0: r.shardIndex, _1: r.count, _2: "" };
  });

  const result = ffi.distributed_merge_count(ffiInput);

  return {
    data: result._0,
    succeededShards: result._1 as number[],
    errors: result._2.map((e) => ({ shardIndex: e._0, message: e._1 })),
  };
}
