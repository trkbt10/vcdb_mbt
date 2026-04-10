/**
 * @file High-level distributed VectorDB operations.
 *
 * Wraps DistributedFfi with JS-idiomatic types, hiding MoonBit
 * tuple encoding and wire-format byte conversions.
 *
 * All functions require loadModule() to have been called first.
 */
import type { VectorId, SearchHit, ScrollEntry } from "./types.js";
import { getDistributedFfi, isModuleLoaded } from "./ffi/loader.js";
import { int64ToWireBytes, wireBytesBigInt } from "./ffi/vector-id.js";

function ensureLoaded(caller: string): void {
  if (!isModuleLoaded()) {
    throw new Error(`${caller}() requires loadModule() to have been called first.`);
  }
}

const parsePayload = (json: string): Record<string, unknown> | null => {
  if (!json) return null;
  try {
    return JSON.parse(json) as Record<string, unknown>;
  } catch {
    return null;
  }
};

/* ── Public types ────────────────────────────────────────────── */

export type ShardSearchResult =
  | { shardIndex: number; hits: readonly SearchHit[] }
  | { shardIndex: number; error: string };

export type ShardScrollResult =
  | { shardIndex: number; entries: readonly ScrollEntry[] }
  | { shardIndex: number; error: string };

export type ShardCountResult =
  | { shardIndex: number; count: number }
  | { shardIndex: number; error: string };

export interface MergedResult<T> {
  data: T;
  succeededShards: number[];
  errors: ReadonlyArray<{ shardIndex: number; message: string }>;
}

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
 * Compute the primary shard for a vector ID (single replica).
 * Returns a single shard index in [0, pgCount).
 */
export function placementGroup(
  id: VectorId,
  pgCount: number,
): number {
  ensureLoaded("placementGroup");
  return getDistributedFfi().crush_placement_group(int64ToWireBytes(id), pgCount);
}

/**
 * Compute all shard indices (primary + replicas) for a vector ID.
 * Returns an ordered array: first is primary, rest are replicas.
 *
 * @param replicas - Total number of copies (e.g. 3 for triple replication).
 *   Must be <= pgCount. Clamped to pgCount if larger.
 */
export function placementGroups(
  id: VectorId,
  pgCount: number,
  replicas: number,
): number[] {
  ensureLoaded("placementGroups");
  return getDistributedFfi().crush_placement_groups(int64ToWireBytes(id), pgCount, replicas);
}

/* ── Upsert grouping ─────────────────────────────────────────── */

/**
 * Group upsert points by shard (single replica — no replication).
 * Each point appears in exactly one shard group.
 */
export function groupUpsert(
  points: ReadonlyArray<{
    id: VectorId;
    vector: number[];
    payload: Record<string, unknown>;
  }>,
  pgCount: number,
): UpsertGroup[] {
  return groupUpsertReplicated(points, pgCount, 1);
}

/**
 * Group upsert points by shard with replication.
 *
 * Each point is placed on `replicas` shards via CRUSH placement.
 * When replicas=1, each point appears in exactly one group.
 * When replicas=3, each point appears in 3 groups (primary + 2 replicas).
 *
 * The caller should fan out upserts to all shard groups.
 */
export function groupUpsertReplicated(
  points: ReadonlyArray<{
    id: VectorId;
    vector: number[];
    payload: Record<string, unknown>;
  }>,
  pgCount: number,
  replicas: number,
): UpsertGroup[] {
  ensureLoaded("groupUpsertReplicated");
  const ffi = getDistributedFfi();
  const ffiPoints = points.map((p) => ({
    _0: int64ToWireBytes(p.id),
    _1: p.vector,
    _2: JSON.stringify(p.payload),
  }));

  const groups = ffi.distributed_group_upsert_replicated(ffiPoints, pgCount, replicas);

  return groups.map((g) => ({
    shardIndex: g._0,
    points: g._1.map((p) => ({
      id: wireBytesBigInt(p._0),
      vector: p._1,
      payload: p._2,
    })),
  }));
}

/* ── Merge operations ────────────────────────────────────────── */

export function mergeSearch(
  shardResults: readonly ShardSearchResult[],
  topK: number,
): MergedResult<readonly SearchHit[]> {
  ensureLoaded("mergeSearch");
  const ffi = getDistributedFfi();
  const ffiInput = shardResults.map((r) => {
    if ("error" in r) {
      return { _0: r.shardIndex, _1: [] as Array<{ _0: Uint8Array; _1: number; _2: string }>, _2: r.error };
    }
    const hits = r.hits.map((h) => ({
      _0: int64ToWireBytes(h.id),
      _1: h.score,
      _2: JSON.stringify(h.payload ?? {}),
    }));
    return { _0: r.shardIndex, _1: hits, _2: "" };
  });

  const result = ffi.distributed_merge_search(ffiInput, topK);

  return {
    data: result._0.map((r) => ({
      id: wireBytesBigInt(r._0),
      score: r._1,
      payload: parsePayload(r._2),
    })),
    succeededShards: result._1 as number[],
    errors: result._2.map((e) => ({ shardIndex: e._0, message: e._1 })),
  };
}

export function mergeScroll(
  shardResults: readonly ShardScrollResult[],
  limit: number,
): MergedResult<readonly ScrollEntry[]> {
  ensureLoaded("mergeScroll");
  const ffi = getDistributedFfi();
  const ffiInput = shardResults.map((r) => {
    if ("error" in r) {
      return { _0: r.shardIndex, _1: [] as Array<{ _0: Uint8Array; _1: string }>, _2: r.error };
    }
    const entries = r.entries.map((e) => ({
      _0: int64ToWireBytes(e.id),
      _1: JSON.stringify(e.payload ?? {}),
    }));
    return { _0: r.shardIndex, _1: entries, _2: "" };
  });

  const result = ffi.distributed_merge_scroll(ffiInput, limit);

  return {
    data: result._0.map((r) => ({
      id: wireBytesBigInt(r._0),
      payload: parsePayload(r._1),
    })),
    succeededShards: result._1 as number[],
    errors: result._2.map((e) => ({ shardIndex: e._0, message: e._1 })),
  };
}

/**
 * Read from any available replica.
 *
 * All replicas are equal — there is no "primary" or "fallback".
 * Queries each replica shard until one returns a non-null value.
 * A null return from readFn means the shard responded but doesn't
 * have the data (stale/lagging replica), so the next replica is tried.
 * A thrown error means the shard is unreachable, also tries next.
 *
 * Returns null only after all replicas have been exhausted.
 * Throws only if all replicas throw (none responded at all).
 *
 * @param id - Vector ID to look up
 * @param pgCount - Total number of placement groups (shards)
 * @param replicas - Number of replicas per data point
 * @param readFn - Function that reads from a shard index. Returns null if
 *   the shard doesn't have the data, throws on error.
 */
export async function readFromReplicas<T>(
  id: VectorId,
  pgCount: number,
  replicas: number,
  readFn: (shardIndex: number) => Promise<T | null>,
): Promise<{ value: T | null; shardIndex: number; attempts: number }> {
  ensureLoaded("readFromReplicas");
  const shards = placementGroups(id, pgCount, replicas);
  let lastError: unknown = null;
  let attempts = 0;
  let anyResponded = false;

  for (const shardIndex of shards) {
    attempts++;
    try {
      const value = await readFn(shardIndex);
      anyResponded = true;
      if (value !== null) {
        return { value, shardIndex, attempts };
      }
      // null = shard responded but doesn't have it → try next replica
    } catch (err) {
      lastError = err;
    }
  }

  // If at least one shard responded (with null), the data genuinely
  // doesn't exist — return null rather than throwing.
  if (anyResponded) {
    return { value: null, shardIndex: -1, attempts };
  }

  // No shard responded at all — throw.
  throw lastError ?? new Error(`All ${shards.length} replicas failed for ID ${id}`);
}

export function mergeCount(
  shardResults: readonly ShardCountResult[],
): MergedResult<number> {
  ensureLoaded("mergeCount");
  const ffi = getDistributedFfi();
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

/**
 * @deprecated Use `mergeCount` instead. With correct fan-out (one target
 * per PG via `select_read_targets`), each PG's data is counted exactly
 * once, so the raw sum is already the unique count. Division by replicas
 * would produce an incorrect (deflated) result.
 *
 * Retained for backward compatibility — now delegates directly to mergeCount.
 */
export function mergeCountReplicated(
  shardResults: readonly ShardCountResult[],
  _replicas: number,
): MergedResult<number> {
  return mergeCount(shardResults);
}

/* ── Rebalance ──────────────────────────────────────────────── */

export interface RebalanceAction {
  id: VectorId;
  /** Shards that need to receive this vector (new − old). */
  addTo: number[];
  /** Shards that should remove this vector (old − new). */
  removeFrom: number[];
}

export interface RebalanceSummary {
  affectedVectors: number;
  totalAdditions: number;
  totalRemovals: number;
}

/**
 * Compute a rebalance plan when shard configuration changes.
 *
 * Compares old and new CRUSH placements for each vector ID and returns
 * the minimal set of shard transfers needed. Vectors whose placement
 * is unchanged produce no action.
 *
 * This is pure computation — no I/O. The caller executes the transfers.
 */
export function rebalancePlan(
  ids: readonly VectorId[],
  oldPgCount: number,
  oldReplicas: number,
  newPgCount: number,
  newReplicas: number,
): RebalanceAction[] {
  ensureLoaded("rebalancePlan");
  const ffi = getDistributedFfi();
  const wireIds = ids.map((id) => int64ToWireBytes(id));
  const raw = ffi.distributed_rebalance_plan(
    wireIds,
    oldPgCount,
    oldReplicas,
    newPgCount,
    newReplicas,
  );
  return raw.map((r) => ({
    id: wireBytesBigInt(r._0),
    addTo: r._1 as number[],
    removeFrom: r._2 as number[],
  }));
}

/**
 * Summarize a rebalance without computing full per-vector actions.
 * Useful for estimating the cost of a shard configuration change.
 */
export function rebalanceSummary(
  ids: readonly VectorId[],
  oldPgCount: number,
  oldReplicas: number,
  newPgCount: number,
  newReplicas: number,
): RebalanceSummary {
  ensureLoaded("rebalanceSummary");
  const ffi = getDistributedFfi();
  const wireIds = ids.map((id) => int64ToWireBytes(id));
  const raw = ffi.distributed_rebalance_summary(
    wireIds,
    oldPgCount,
    oldReplicas,
    newPgCount,
    newReplicas,
  );
  return {
    affectedVectors: raw._0,
    totalAdditions: raw._1,
    totalRemovals: raw._2,
  };
}
