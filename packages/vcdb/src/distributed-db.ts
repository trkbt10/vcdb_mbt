/**
 * @file JS-native DistributedDB — scatter-gather orchestrator.
 *
 * Accepts a JS async ShardTransport and uses CRUSH placement + merge
 * functions from the MoonBit core to perform distributed operations.
 *
 * This is the JS counterpart of the MoonBit DistributedDB. It exists
 * because MoonBit's ShardTransport trait uses CPS-style callbacks that
 * cannot bridge to JS async/await (e.g. Cloudflare DO RPC).
 */
import type { VectorId, SearchHit, PointRecord, ScrollEntry } from "./types.js";
import type { MergedResult, ShardSearchResult, ShardScrollResult, ShardCountResult } from "./distributed.js";
import {
  placementGroups,
  mergeSearch,
  mergeScroll,
  mergeCount,
  readFromReplicas,
} from "./distributed.js";

/* ── Transport interface ──────────────────────────────────────── */

/**
 * JS-native shard transport.
 *
 * Each method talks to a single shard identified by index.
 * The implementation decides how to reach that shard (DO RPC,
 * local PersistentDB, HTTP, etc.).
 */
export interface ShardTransport {
  upsert(
    shardIndex: number,
    points: readonly { id: VectorId; vector: number[]; payload: Record<string, unknown> }[],
  ): Promise<void>;

  search(
    shardIndex: number,
    query: number[],
    topK: number,
    filterJson: string,
  ): Promise<readonly SearchHit[]>;

  get(shardIndex: number, id: VectorId): Promise<PointRecord>;

  has(shardIndex: number, id: VectorId): Promise<boolean>;

  remove(shardIndex: number, id: VectorId): Promise<boolean>;

  scrollFiltered(
    shardIndex: number,
    filterJson: string,
    offset: VectorId | undefined,
    limit: number,
  ): Promise<readonly ScrollEntry[]>;

  countFiltered(shardIndex: number, filterJson: string): Promise<number>;
}

/* ── Options ──────────────────────────────────────────────────── */

export interface DistributedDBOptions {
  /** Number of placement groups (= number of shards). */
  shardCount: number;
  /** Number of replicas per data point. Default 1. */
  replicas?: number;
  /** How to talk to each shard. */
  transport: ShardTransport;
}

/* ── DistributedDB ────────────────────────────────────────────── */

export class DistributedDB {
  readonly shardCount: number;
  readonly replicas: number;
  private readonly transport: ShardTransport;

  constructor(options: DistributedDBOptions) {
    this.shardCount = options.shardCount;
    this.replicas = options.replicas ?? 1;
    this.transport = options.transport;
  }

  /* ── Writes ───────────────────────────────────────────────── */

  /**
   * Upsert points across shards.
   *
   * Each point is placed on `replicas` shards via CRUSH.
   * All replica shards receive the point in parallel.
   */
  async upsert(
    points: readonly { id: VectorId; vector: number[]; payload: Record<string, unknown> }[],
  ): Promise<void> {
    const groups = new Map<number, { id: VectorId; vector: number[]; payload: Record<string, unknown> }[]>();
    for (const point of points) {
      const shards = placementGroups(point.id, this.shardCount, this.replicas);
      for (const shard of shards) {
        let list = groups.get(shard);
        if (!list) {
          list = [];
          groups.set(shard, list);
        }
        list.push(point);
      }
    }
    await Promise.all(
      [...groups.entries()].map(([shard, pts]) => this.transport.upsert(shard, pts)),
    );
  }

  /**
   * Remove a vector from all replica shards.
   * Returns true if removed from at least one shard.
   */
  async remove(id: VectorId): Promise<boolean> {
    const shards = placementGroups(id, this.shardCount, this.replicas);
    const results = await Promise.all(
      shards.map((shard) => this.transport.remove(shard, id).catch(() => false)),
    );
    return results.some(Boolean);
  }

  /* ── Reads ────────────────────────────────────────────────── */

  /**
   * Search across all shards, merge results by score.
   */
  async search(
    query: number[],
    topK: number,
    filterJson: string = "",
  ): Promise<MergedResult<readonly SearchHit[]>> {
    const shardResults: ShardSearchResult[] = await Promise.all(
      Array.from({ length: this.shardCount }, async (_, i): Promise<ShardSearchResult> => {
        try {
          const hits = await this.transport.search(i, query, topK, filterJson);
          return { shardIndex: i, hits };
        } catch (err: unknown) {
          return { shardIndex: i, error: String(err) };
        }
      }),
    );
    return mergeSearch(shardResults, topK);
  }

  /**
   * Get a vector from any replica that holds it.
   *
   * Tries each replica shard in order. Returns null only after
   * all replicas have been exhausted.
   */
  async get(id: VectorId): Promise<PointRecord | null> {
    const result = await readFromReplicas<PointRecord>(
      id,
      this.shardCount,
      this.replicas,
      async (shard) => {
        const record = await this.transport.get(shard, id);
        return record.found ? record : null;
      },
    );
    return result.value;
  }

  /**
   * Check if a vector exists on any replica.
   */
  async has(id: VectorId): Promise<boolean> {
    const result = await readFromReplicas<boolean>(
      id,
      this.shardCount,
      this.replicas,
      async (shard) => {
        const found = await this.transport.has(shard, id);
        return found ? true : null;
      },
    );
    return result.value === true;
  }

  /**
   * Scroll across all shards with optional filter.
   */
  async scrollFiltered(
    filterJson: string = "",
    offset?: VectorId,
    limit: number = 10,
  ): Promise<MergedResult<readonly ScrollEntry[]>> {
    const shardResults: ShardScrollResult[] = await Promise.all(
      Array.from({ length: this.shardCount }, async (_, i): Promise<ShardScrollResult> => {
        try {
          const entries = await this.transport.scrollFiltered(i, filterJson, offset, limit);
          return { shardIndex: i, entries };
        } catch (err: unknown) {
          return { shardIndex: i, error: String(err) };
        }
      }),
    );
    return mergeScroll(shardResults, limit);
  }

  /**
   * Count across all shards with optional filter.
   */
  async countFiltered(
    filterJson: string = "",
  ): Promise<MergedResult<number>> {
    const shardResults: ShardCountResult[] = await Promise.all(
      Array.from({ length: this.shardCount }, async (_, i): Promise<ShardCountResult> => {
        try {
          const count = await this.transport.countFiltered(i, filterJson);
          return { shardIndex: i, count };
        } catch (err: unknown) {
          return { shardIndex: i, error: String(err) };
        }
      }),
    );
    return mergeCount(shardResults);
  }
}
