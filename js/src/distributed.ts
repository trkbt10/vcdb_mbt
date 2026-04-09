/**
 * @file High-level distributed VectorDB operations.
 *
 * Wraps DistributedFfi with JS-idiomatic types, hiding MoonBit
 * tuple encoding and wire-format byte conversions.
 */
import type { DistributedFfi } from "./ffi/types.js";
import type { VectorId, SearchHit, ScrollEntry } from "./index.js";
import { int64ToWireBytes, wireBytesBigInt } from "./ffi/vector-id.js";

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

export function placementGroup(
  ffi: DistributedFfi,
  id: VectorId,
  pgCount: number,
): number {
  return ffi.crush_placement_group(int64ToWireBytes(id), pgCount);
}

/* ── Upsert grouping ─────────────────────────────────────────── */

export function groupUpsert(
  ffi: DistributedFfi,
  points: ReadonlyArray<{
    id: VectorId;
    vector: number[];
    payload: Record<string, unknown>;
  }>,
  pgCount: number,
): UpsertGroup[] {
  const ffiPoints = points.map((p) => ({
    _0: int64ToWireBytes(p.id),
    _1: p.vector,
    _2: JSON.stringify(p.payload),
  }));

  const groups = ffi.distributed_group_upsert(ffiPoints, pgCount);

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
  ffi: DistributedFfi,
  shardResults: readonly ShardSearchResult[],
  topK: number,
): MergedResult<readonly SearchHit[]> {
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
  ffi: DistributedFfi,
  shardResults: readonly ShardScrollResult[],
  limit: number,
): MergedResult<readonly ScrollEntry[]> {
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
