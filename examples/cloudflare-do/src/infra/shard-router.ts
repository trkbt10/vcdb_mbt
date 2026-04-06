/**
 * @file Shard router — scatter-gather across multiple VcdbStore DOs.
 *
 * All merge logic, routing, and ID handling is delegated to vcdb core
 * FFI (distributed_merge_*, crush_placement_group). This file only
 * handles Cloudflare DO RPC dispatch and result collection.
 */
import type { VcdbStore } from "./vcdb-do.ts";
import type { SearchHit, ScrollEntry } from "@vcdb/server/persistent";
import type { MbInt64, PersistentFFI } from "@vcdb/server/storage/persistent-bridge";
import type { Bindings } from "../types.ts";

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
  ): Promise<readonly ScrollEntry[]>;

  readonly shardCount: number;
};

export function createShardRouter(
  shardCount: number,
  ffi: PersistentFFI,
): ShardRouter {
  const shardFor = (id: MbInt64): number =>
    ffi.crush_placement_group(id.hi, id.lo, shardCount);

  return {
    shardCount,

    async upsert(env, points) {
      // Group by shard using CRUSH (SoT)
      const ffiPoints = points.map((p) => ({
        _0: p.id.hi,
        _1: p.id.lo,
        _2: p.vector,
        _3: JSON.stringify(p.payload),
      }));
      const groups = ffi.distributed_group_upsert(ffiPoints, shardCount);

      const writes: Promise<void>[] = [];
      for (const group of groups) {
        const shardIndex = group._0;
        const shardPoints = group._1.map((p) => ({
          id: { hi: p._0, lo: p._1 } as MbInt64,
          vector: p._2,
          payload: JSON.parse(p._3) as Record<string, unknown>,
        }));
        writes.push(getShardStub(env, shardIndex).upsert(shardPoints));
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
      const shardResults: Array<{ _0: number; _1: number; _2: string }> = [];
      const tasks = Array.from({ length: shardCount }, (_, i) =>
        (async () => {
          try {
            const count = await getShardStub(env, i).countFiltered(filterJson);
            shardResults.push({ _0: i, _1: count, _2: "" });
          } catch (e) {
            shardResults.push({ _0: i, _1: 0, _2: String(e) });
          }
        })(),
      );
      await Promise.all(tasks);
      return ffi.distributed_merge_count(shardResults)._0;
    },

    async scrollFiltered(env, filterJson, offset, limit) {
      type RawEntry = { _0: number; _1: number; _2: string };
      const shardResults: Array<{ _0: number; _1: RawEntry[]; _2: string }> = [];
      const tasks = Array.from({ length: shardCount }, (_, i) =>
        (async () => {
          try {
            const entries = await getShardStub(env, i).scrollFiltered(filterJson, offset, limit);
            shardResults.push({
              _0: i,
              _1: (entries as readonly ScrollEntry[]).map((e) => ({
                _0: e.id.hi, _1: e.id.lo, _2: JSON.stringify(e.payload ?? {}),
              })),
              _2: "",
            });
          } catch (e) {
            shardResults.push({ _0: i, _1: [], _2: String(e) });
          }
        })(),
      );
      await Promise.all(tasks);

      const merged = ffi.distributed_merge_scroll(shardResults, limit);
      return merged._0.map((r) => ({
        id: { hi: r._0, lo: r._1 } as MbInt64,
        payload: r._2 ? (JSON.parse(r._2) as Record<string, unknown>) : null,
      }));
    },

    async search(env, vector, topK, filterJson = "") {
      type RawHit = { _0: number; _1: number; _2: number; _3: string };
      const shardResults: Array<{ _0: number; _1: RawHit[]; _2: string }> = [];
      const tasks = Array.from({ length: shardCount }, (_, i) =>
        (async () => {
          try {
            const hits = await getShardStub(env, i).search(vector, topK, filterJson);
            shardResults.push({
              _0: i,
              _1: (hits as readonly SearchHit[]).map((h) => ({
                _0: h.id.hi, _1: h.id.lo, _2: h.score, _3: JSON.stringify(h.payload ?? {}),
              })),
              _2: "",
            });
          } catch (e) {
            shardResults.push({ _0: i, _1: [], _2: String(e) });
          }
        })(),
      );
      await Promise.all(tasks);

      const merged = ffi.distributed_merge_search(shardResults, topK);
      return merged._0.map((r) => ({
        id: { hi: r._0, lo: r._1 } as MbInt64,
        score: r._2,
        payload: r._3 ? (JSON.parse(r._3) as Record<string, unknown>) : null,
      }));
    },
  };
}
