/**
 * @file Shard router — scatter-gather across multiple VcdbStore DOs.
 *
 * Uses vcdb core's CRUSH placement (crush_placement_group via FFI)
 * as the single source of truth for vector-to-shard mapping.
 * This ensures data placement and request routing use the same hash.
 *
 * This router exists because Cloudflare DO requires per-instance RPC
 * dispatch: we need to know which DO stub to call, not just which
 * storage to write to.
 */
import type { VcdbStore } from "./vcdb-do.ts";
import type { SearchHit } from "@vcdb/server/persistent";
import type { MbInt64 } from "@vcdb/server/storage/persistent-bridge";
import type { Bindings } from "../types.ts";

/** Reconstruct a JS number from hi/lo pair (for sort comparisons). */
const idToNumeric = (id: MbInt64): number =>
  (id.hi >>> 0) * 0x100000000 + (id.lo >>> 0);

/**
 * Placement function — maps a MbInt64 to a shard index in [0, shardCount).
 * Must be crush_placement_group from the WASM module.
 */
type PlacementFn = (id_hi: number, id_lo: number, pg_count: number) => number;

/** Get a DO stub for a specific shard. */
const getShardStub = (
  env: Bindings,
  shardIndex: number,
): DurableObjectStub<VcdbStore> => {
  const doId = env.VCDB_STORE.idFromName(`shard-${shardIndex}`);
  return env.VCDB_STORE.get(doId);
};

export type ShardRouter = {
  upsert(
    env: Bindings,
    points: readonly {
      id: MbInt64;
      vector: number[];
      payload: Record<string, unknown>;
    }[],
  ): Promise<void>;

  search(
    env: Bindings,
    vector: number[],
    topK: number,
    filterJson?: string,
  ): Promise<readonly SearchHit[]>;

  get(
    env: Bindings,
    id: MbInt64,
  ): Promise<{
    vector: number[];
    payload: Record<string, unknown>;
  } | null>;

  countFiltered(env: Bindings, filterJson: string): Promise<number>;

  scrollFiltered(
    env: Bindings,
    filterJson: string,
    offset: MbInt64 | undefined,
    limit: number,
  ): Promise<
    readonly { id: MbInt64; payload: Record<string, unknown> | null }[]
  >;

  readonly shardCount: number;
};

export function createShardRouter(
  shardCount: number,
  placementGroup: PlacementFn,
): ShardRouter {
  const shardFor = (id: MbInt64): number =>
    placementGroup(id.hi, id.lo, shardCount);

  return {
    shardCount,

    async upsert(env, points) {
      const buckets = new Map<
        number,
        { id: MbInt64; vector: number[]; payload: Record<string, unknown> }[]
      >();
      for (const point of points) {
        const shard = shardFor(point.id);
        const bucket = buckets.get(shard);
        if (bucket) {
          bucket.push(point);
        } else {
          buckets.set(shard, [point]);
        }
      }

      const writes: Promise<void>[] = [];
      for (const [shardIndex, shardPoints] of buckets) {
        const stub = getShardStub(env, shardIndex);
        writes.push(stub.upsert(shardPoints));
      }
      await Promise.all(writes);
    },

    async get(env, id) {
      const stub = getShardStub(env, shardFor(id));
      const result: {
        found: boolean;
        vector: number[];
        payload: Record<string, unknown> | null;
      } = await stub.getById(id);
      return result.found
        ? { vector: result.vector, payload: result.payload! }
        : null;
    },

    async countFiltered(env, filterJson) {
      const counts: Promise<number>[] = [];
      for (let i = 0; i < shardCount; i++) {
        counts.push(getShardStub(env, i).countFiltered(filterJson));
      }
      const shardCounts = await Promise.all(counts);
      return shardCounts.reduce((sum, n) => sum + n, 0);
    },

    async scrollFiltered(env, filterJson, offset, limit) {
      const fetches: Promise<
        readonly { id: MbInt64; payload: Record<string, unknown> | null }[]
      >[] = [];
      for (let i = 0; i < shardCount; i++) {
        fetches.push(
          getShardStub(env, i).scrollFiltered(filterJson, offset, limit),
        );
      }
      const shardResults = await Promise.all(fetches);

      const all: { id: MbInt64; payload: Record<string, unknown> | null }[] = [];
      for (const results of shardResults) {
        for (const entry of results) {
          all.push(entry);
        }
      }
      all.sort((a, b) => idToNumeric(a.id) - idToNumeric(b.id));
      return all.slice(0, limit);
    },

    async search(env, vector, topK, filterJson = "") {
      const searches: Promise<readonly SearchHit[]>[] = [];
      for (let i = 0; i < shardCount; i++) {
        searches.push(getShardStub(env, i).search(vector, topK, filterJson));
      }
      const shardResults = await Promise.all(searches);

      const all: SearchHit[] = [];
      for (const results of shardResults) {
        for (const hit of results) {
          all.push(hit);
        }
      }
      all.sort((a, b) => b.score - a.score);
      return all.slice(0, topK);
    },
  };
}
