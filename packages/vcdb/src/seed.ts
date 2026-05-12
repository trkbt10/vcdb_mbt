/**
 * @file Seed utility — build sharded vcdb databases locally and deploy to remote storage.
 *
 * ## Workflow
 *
 *   1. Create a LocalSeedBuilder with shard count and vector dimensions
 *   2. Add points — they are automatically routed to the correct shard via CRUSH placement
 *   3. Call build() to checkpoint all shards and produce per-shard snapshot files
 *   4. Call deploy() to upload snapshots to remote storage (R2, S3, etc.)
 *
 * This enables a "local-first" workflow where vector data is built and tested
 * on the local filesystem, then deployed to a distributed environment
 * (e.g. Cloudflare Durable Objects + R2) without re-embedding.
 *
 * ## Example
 *
 * ```ts
 * import { loadModule } from "vcdb";
 * import { LocalSeedBuilder } from "vcdb/seed";
 * import { createNodeStorage } from "vcdb/storage/node";
 *
 * await loadModule();
 *
 * const builder = await LocalSeedBuilder.create({
 *   baseDir: "./.vcdb-seed",
 *   shardCount: 4,
 *   dim: 1024,
 *   collectionName: "products-v1",
 * });
 *
 * // Add points (automatically sharded)
 * await builder.addPoints(points);
 *
 * // Build snapshots
 * const manifest = await builder.build();
 *
 * // Deploy to remote storage
 * await builder.deploy(async (shardIndex, filePath, data) => {
 *   await r2Bucket.put(`shard-${shardIndex}/${filePath}`, data);
 * });
 * ```
 */
import { join } from "node:path";
import { readdir, stat, readFile, rm } from "node:fs/promises";
import type { VectorId, Metric, Strategy } from "./types.js";
import { PersistentDB, storageToCallbacks } from "./db.js";
import { StorageKind } from "./storage/types.js";
import { createNodeStorage } from "./storage/node.js";
import { placementGroup, groupUpsert } from "./distributed.js";

export interface SeedBuilderOptions {
  /** Base directory for local shard data */
  baseDir: string;
  /** Number of shards (must match distributed environment) */
  shardCount: number;
  /** Vector dimensions */
  dim: number;
  /** Initial capacity per shard */
  capacity?: number;
  /** Distance metric */
  metric?: Metric;
  /** ANN strategy */
  strategy?: Strategy;
  /** Collection name (must match remote environment) */
  collectionName?: string;
}

export interface SeedPoint {
  id: VectorId;
  vector: number[];
  payload: Record<string, unknown>;
}

export interface ShardManifest {
  shardIndex: number;
  pointCount: number;
  files: Array<{ path: string; sizeBytes: number }>;
}

export interface BuildManifest {
  shardCount: number;
  dim: number;
  metric: string;
  strategy: string;
  collectionName: string;
  totalPoints: number;
  shards: ShardManifest[];
  createdAt: string;
}

/**
 * Callback for deploying shard data to remote storage.
 *
 * @param shardIndex - The shard index (0-based)
 * @param filePath   - Relative file path within the shard (e.g. "products-v1.data.bin")
 * @param data       - File contents as Uint8Array
 */
export type DeployCallback = (
  shardIndex: number,
  filePath: string,
  data: Uint8Array,
) => Promise<void>;

export class LocalSeedBuilder {
  private readonly shards: PersistentDB[];
  private readonly options: Required<
    Pick<SeedBuilderOptions, "baseDir" | "shardCount" | "dim" | "capacity" | "metric" | "strategy" | "collectionName">
  >;
  private pointCounts: number[];

  private constructor(
    shards: PersistentDB[],
    options: LocalSeedBuilder["options"],
  ) {
    this.shards = shards;
    this.options = options;
    this.pointCounts = new Array(options.shardCount).fill(0) as number[];
  }

  static async create(options: SeedBuilderOptions): Promise<LocalSeedBuilder> {
    const {
      baseDir,
      shardCount,
      dim,
      capacity = 1024,
      metric = "cosine",
      strategy = "hnsw",
      collectionName = "db",
    } = options;

    const resolvedOptions = { baseDir, shardCount, dim, capacity, metric, strategy, collectionName };

    const shards: PersistentDB[] = [];
    for (let i = 0; i < shardCount; i++) {
      const shardDir = join(baseDir, `shard-${i}`);
      const storage = createNodeStorage({ baseDir: shardDir });
      const db = await PersistentDB.create({
        instanceId: 50000 + i,
        dim,
        capacity,
        metric,
        strategy,
        walStorage: storageToCallbacks(storage, StorageKind.Data),
        snapshotStorage: storageToCallbacks(storage, StorageKind.Data),
        collectionName,
        basePath: "",
      });
      shards.push(db);
    }

    return new LocalSeedBuilder(shards, resolvedOptions);
  }

  /** Add points, automatically routing to the correct shard via CRUSH placement. */
  async addPoints(points: readonly SeedPoint[]): Promise<{ shardDistribution: Record<number, number> }> {
    const groups = groupUpsert(points, this.options.shardCount);
    const distribution: Record<number, number> = {};

    for (const group of groups) {
      const shardPoints = group.points.map((p) => ({
        id: p.id,
        vector: p.vector,
        payload: JSON.parse(p.payload) as Record<string, unknown>,
      }));
      await this.shards[group.shardIndex]!.upsert(shardPoints);
      this.pointCounts[group.shardIndex]! += shardPoints.length;
      distribution[group.shardIndex] = shardPoints.length;
    }

    return { shardDistribution: distribution };
  }

  /** Get a point by ID from the correct shard. */
  get(id: VectorId): { found: boolean; vector: number[]; payload: Record<string, unknown> | null } {
    const shardIdx = placementGroup(id, this.options.shardCount);
    return this.shards[shardIdx]!.get(id);
  }

  /** Check if a point exists. */
  has(id: VectorId): boolean {
    const shardIdx = placementGroup(id, this.options.shardCount);
    return this.shards[shardIdx]!.has(id);
  }

  /** Total number of points across all shards. */
  get totalSize(): number {
    return this.shards.reduce((sum, db) => sum + db.size(), 0);
  }

  /** Checkpoint all shards and produce a build manifest. */
  async build(): Promise<BuildManifest> {
    const shardManifests: ShardManifest[] = [];

    for (let i = 0; i < this.options.shardCount; i++) {
      await this.shards[i]!.checkpoint();

      const shardDir = join(this.options.baseDir, `shard-${i}`, "data");
      const files: Array<{ path: string; sizeBytes: number }> = [];

      try {
        const entries = await readdir(shardDir);
        for (const entry of entries) {
          const st = await stat(join(shardDir, entry));
          if (st.isFile()) {
            files.push({ path: entry, sizeBytes: st.size });
          }
        }
      } catch {
        // No data directory — shard has no data
      }

      shardManifests.push({
        shardIndex: i,
        pointCount: this.shards[i]!.size(),
        files,
      });
    }

    return {
      shardCount: this.options.shardCount,
      dim: this.options.dim,
      metric: this.options.metric,
      strategy: this.options.strategy,
      collectionName: this.options.collectionName,
      totalPoints: this.totalSize,
      shards: shardManifests,
      createdAt: new Date().toISOString(),
    };
  }

  /**
   * Deploy built shard data to remote storage via callback.
   *
   * The callback is called for each file in each shard.
   * The caller is responsible for mapping the shard index and file path
   * to the correct remote location (e.g. R2 key prefix per DO shard).
   */
  async deploy(callback: DeployCallback): Promise<{ totalFiles: number; totalBytes: number }> {
    let totalFiles = 0;
    let totalBytes = 0;

    for (let i = 0; i < this.options.shardCount; i++) {
      const shardDir = join(this.options.baseDir, `shard-${i}`, "data");

      try {
        const entries = await readdir(shardDir);
        for (const entry of entries) {
          const fullPath = join(shardDir, entry);
          const st = await stat(fullPath);
          if (st.isFile()) {
            const data = await readFile(fullPath);
            const u8 = new Uint8Array(data.buffer, data.byteOffset, data.byteLength);
            await callback(i, entry, u8);
            totalFiles++;
            totalBytes += data.byteLength;
          }
        }
      } catch {
        // No data directory for this shard
      }
    }

    return { totalFiles, totalBytes };
  }

  /** Destroy all shard databases and optionally clean up the base directory. */
  async destroy(cleanUp = false): Promise<void> {
    for (const shard of this.shards) {
      shard.destroy();
    }
    if (cleanUp) {
      await rm(this.options.baseDir, { recursive: true, force: true });
    }
  }
}
