/**
 * @file Shard router for distributing vectors across multiple VcdbStore DOs.
 *
 * Each DO shard holds a partial index (~thousands of vectors each).
 * Upsert routes by vector ID hash. Search queries all shards in parallel
 * and merges results by score (scatter-gather).
 *
 * This enables scaling beyond a single DO's 128MB memory limit.
 *
 * Based on production patterns from usbkr (v5 shard format).
 */
import type { VcdbStore, VcdbSearchHit } from "./vcdb-do.ts";
import type { VcdbId, Bindings } from "../types.ts";
import { idToNumeric } from "../types.ts";

const DEFAULT_SHARD_COUNT = 8;

/** Determine shard index from a VcdbId. */
const shardFor = (id: VcdbId, shardCount: number): number =>
  Math.abs(idToNumeric(id) | 0) % shardCount;

/**
 * Shard name version — increment when storage format or API breaks.
 * v5: IDs clamped to i32 (vcdb WAL replay loses IDs > 2^31-1 on JS target)
 */
const SHARD_VERSION = "v5";

/** Get a DO stub for a specific shard. */
const getShardStub = (
  env: Bindings,
  shardIndex: number,
): DurableObjectStub<VcdbStore> => {
  const doId = env.VCDB_STORE.idFromName(
    `${SHARD_VERSION}-shard-${shardIndex}`,
  );
  return env.VCDB_STORE.get(doId);
};

export type ShardRouter = {
  /** Upsert points — routes each point to its shard by ID hash. */
  upsert(
    env: Bindings,
    points: readonly {
      id: VcdbId;
      vector: number[];
      payload: Record<string, unknown>;
    }[],
  ): Promise<void>;

  /** Search all shards in parallel, merge by score, return top K. */
  search(
    env: Bindings,
    vector: number[],
    topK: number,
    filterJson?: string,
  ): Promise<readonly VcdbSearchHit[]>;

  /** Get a single vector + payload by VcdbId. */
  get(
    env: Bindings,
    id: VcdbId,
  ): Promise<{
    vector: number[];
    payload: Record<string, unknown>;
  } | null>;

  /** Count vectors matching a filter across all shards. */
  countFiltered(env: Bindings, filterJson: string): Promise<number>;

  /** Scroll all shards with a filter, merge by ID ascending, return up to limit. */
  scrollFiltered(
    env: Bindings,
    filterJson: string,
    offset: VcdbId | undefined,
    limit: number,
  ): Promise<
    readonly { id: VcdbId; payload: Record<string, unknown> | null }[]
  >;

  readonly shardCount: number;
};

export function createShardRouter(
  shardCount: number = DEFAULT_SHARD_COUNT,
): ShardRouter {
  return {
    shardCount,

    async upsert(env, points) {
      // Group points by shard
      const buckets = new Map<
        number,
        { id: VcdbId; vector: number[]; payload: Record<string, unknown> }[]
      >();
      for (const point of points) {
        const shard = shardFor(point.id, shardCount);
        const bucket = buckets.get(shard);
        if (bucket) {
          bucket.push(point);
        } else {
          buckets.set(shard, [point]);
        }
      }

      // Write to each shard in parallel
      const writes: Promise<void>[] = [];
      for (const [shardIndex, shardPoints] of buckets) {
        const stub = getShardStub(env, shardIndex);
        writes.push(stub.upsert(shardPoints));
      }
      await Promise.all(writes);
    },

    async get(env, id) {
      const shard = shardFor(id, shardCount);
      const stub = getShardStub(env, shard);
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
        const stub = getShardStub(env, i);
        counts.push(stub.countFiltered(filterJson));
      }
      const shardCounts = await Promise.all(counts);
      return shardCounts.reduce((sum, n) => sum + n, 0);
    },

    async scrollFiltered(env, filterJson, offset, limit) {
      // Each shard returns its own filtered+sorted results.
      // Over-fetch from each shard (limit entries each), then merge globally.
      const fetches: Promise<
        readonly { id: VcdbId; payload: Record<string, unknown> | null }[]
      >[] = [];
      for (let i = 0; i < shardCount; i++) {
        const stub = getShardStub(env, i);
        fetches.push(stub.scrollFiltered(filterJson, offset, limit));
      }
      const shardResults = await Promise.all(fetches);

      // Merge all shard results, sort by ID ascending, take top `limit`
      const all: { id: VcdbId; payload: Record<string, unknown> | null }[] = [];
      for (const results of shardResults) {
        for (const entry of results) {
          all.push(entry);
        }
      }
      all.sort((a, b) => idToNumeric(a.id) - idToNumeric(b.id));
      return all.slice(0, limit);
    },

    async search(env, vector, topK, filterJson = "") {
      // Query all shards in parallel
      const searches: Promise<readonly VcdbSearchHit[]>[] = [];
      for (let i = 0; i < shardCount; i++) {
        const stub = getShardStub(env, i);
        searches.push(stub.search(vector, topK, filterJson));
      }
      const shardResults = await Promise.all(searches);

      // Merge and sort by score descending, take top K
      const all: VcdbSearchHit[] = [];
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
