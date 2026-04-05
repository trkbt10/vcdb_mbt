/**
 * @file Durable Object that hosts a vcdb collection shard.
 *
 * Each DO shard gets its own vcdb instance_id — no global singleton.
 * Multiple shards sharing the same JS module are fully isolated.
 *
 * Responsibilities: vcdb operations (upsert, search) only.
 * WAL persistence is delegated to WalWriter.
 * Storage backends are injected via DOKeyValueStore / R2Adapter.
 *
 * Based on production patterns from usbkr.
 */
import { DurableObject } from "cloudflare:workers";
import { createDOKeyValueStore } from "@vcdb/server/storage/do-kv";
import { createR2Adapter } from "./r2-store.ts";
import { createWalWriter, type WalWriter } from "./wal-writer.ts";
import type { VcdbId, Bindings } from "../types.ts";

const DIMENSIONS = 1024;
const INITIAL_CAPACITY = 1024;
const COLLECTION_NAME = "vectors";
const WAL_PATH = `${COLLECTION_NAME}.vwal`;
const SNAPSHOT_PATH = `${COLLECTION_NAME}.data.bin`;
const CHECKPOINT_THRESHOLD = 50;

type VcdbLib = typeof import("@vcdb/server/wasm/lib.js");

export type VcdbSearchHit = {
  readonly id: VcdbId;
  readonly score: number;
  readonly payload: Record<string, unknown> | null;
};

const parsePayload = (json: string): Record<string, unknown> | null => {
  if (!json) return null;
  try {
    return JSON.parse(json) as Record<string, unknown>;
  } catch {
    return null;
  }
};

/** Current time as MoonBit Int64 (nanoseconds since epoch). */
const nowNs = (): { hi: number; lo: number } => {
  const ms = Date.now();
  const ns = ms * 1_000_000;
  return { hi: Math.floor(ns / 0x100000000), lo: ns >>> 0 };
};

export class VcdbStore extends DurableObject<Bindings> {
  private vcdb: VcdbLib | null = null;
  /** vcdb instance ID — derived from DO ID, stable across restarts. */
  private readonly instanceId: number;
  private wal: WalWriter;
  private initPromise: Promise<void> | null = null;

  constructor(ctx: DurableObjectState, env: Bindings) {
    super(ctx, env);

    // Stable instance ID derived from DO ID — survives DO restarts.
    // FNV-1a hash of the DO ID hex string.
    const idStr = ctx.id.toString();
    const h = { value: 0x811c9dc5 };
    for (const byte of new TextEncoder().encode(idStr)) {
      h.value ^= byte;
      h.value = Math.imul(h.value, 0x01000193) | 0;
    }
    this.instanceId = h.value >>> 0;

    // R2 keys are prefixed with the DO ID to isolate each shard's data.
    const doPrefix = idStr + "/";
    const walStore = createDOKeyValueStore(ctx.storage, "w:");
    const dataStore = createR2Adapter(env.VCDB_DATA, doPrefix);
    const legacyDataStore = createDOKeyValueStore(ctx.storage, "d:");

    this.wal = createWalWriter(
      walStore,
      dataStore,
      WAL_PATH,
      SNAPSHOT_PATH,
      CHECKPOINT_THRESHOLD,
      legacyDataStore,
    );
  }

  private ensureInitialized(): Promise<void> {
    this.initPromise ??= this.doInit();
    return this.initPromise;
  }

  private async doInit(): Promise<void> {
    const vcdbLib: VcdbLib = await import("@vcdb/server/wasm/lib.js");
    this.vcdb = vcdbLib;

    const { walData, snapshotData } = await this.wal.load();

    if (snapshotData || walData) {
      const applied = vcdbLib.async_replay_wal_and_init(
        this.instanceId,
        walData ?? new Uint8Array(0),
        snapshotData ?? new Uint8Array(0),
        DIMENSIONS,
        INITIAL_CAPACITY,
      );
      const size = vcdbLib.async_db_size(this.instanceId);
      console.log(
        `[VcdbStore] instanceId=${this.instanceId} wal=${walData?.length ?? 0} snap=${snapshotData?.length ?? 0} applied=${applied} size=${size}`,
      );
    } else {
      vcdbLib.async_init_db(this.instanceId, DIMENSIONS, INITIAL_CAPACITY);
      console.log(
        `[VcdbStore] instanceId=${this.instanceId} fresh (no WAL/snapshot)`,
      );
    }
  }

  async upsert(
    points: readonly {
      id: VcdbId;
      vector: number[];
      payload: Record<string, unknown>;
    }[],
  ): Promise<void> {
    await this.ensureInitialized();

    const vcdbPoints = points.map((p) => ({
      _0: p.id.hi,
      _1: p.id.lo,
      _2: p.vector,
      _3: JSON.stringify(p.payload),
    }));
    const walSegment = this.vcdb!.async_upsert(
      this.instanceId,
      vcdbPoints,
      nowNs(),
    );

    await this.wal.append(this.vcdb!, walSegment, points.length);

    if (this.wal.shouldCheckpoint) {
      await this.wal.checkpoint(this.vcdb!, this.instanceId);
    }
  }

  async search(
    vector: number[],
    topK: number,
    filterJson: string = "",
  ): Promise<readonly VcdbSearchHit[]> {
    await this.ensureInitialized();

    const results = this.vcdb!.async_search(
      this.instanceId,
      vector,
      topK,
      true,
      filterJson,
    );
    return results.map((r) => ({
      id: { hi: r._0, lo: r._1 },
      score: r._2,
      payload: parsePayload(r._3),
    }));
  }

  async remove(id: VcdbId): Promise<void> {
    await this.ensureInitialized();
    const walSegment = this.vcdb!.async_remove(
      this.instanceId,
      id.hi,
      id.lo,
      nowNs(),
    );
    if (walSegment.length > 0) {
      await this.wal.append(this.vcdb!, walSegment, 1);
      if (this.wal.shouldCheckpoint) {
        await this.wal.checkpoint(this.vcdb!, this.instanceId);
      }
    }
  }

  async getById(
    id: VcdbId,
  ): Promise<{
    found: boolean;
    vector: number[];
    payload: Record<string, unknown> | null;
  }> {
    await this.ensureInitialized();
    const result = this.vcdb!.async_get(this.instanceId, id.hi, id.lo, true);
    return {
      found: result._0,
      vector: result._1,
      payload: result._0 ? parsePayload(result._2) : null,
    };
  }

  async has(id: VcdbId): Promise<boolean> {
    await this.ensureInitialized();
    return this.vcdb!.async_has(this.instanceId, id.hi, id.lo);
  }

  async updateAttrs(
    id: VcdbId,
    attrs: Record<string, unknown>,
  ): Promise<void> {
    await this.ensureInitialized();
    const walSegment = this.vcdb!.async_update_attrs(
      this.instanceId,
      id.hi,
      id.lo,
      JSON.stringify(attrs),
      nowNs(),
    );
    if (walSegment.length > 0) {
      await this.wal.append(this.vcdb!, walSegment, 1);
    }
  }

  async scroll(
    offset: VcdbId | undefined,
    limit: number,
  ): Promise<readonly { id: VcdbId; payload: Record<string, unknown> | null }[]> {
    await this.ensureInitialized();
    const hasOffset = offset !== undefined;
    const offsetHi = offset?.hi ?? 0;
    const offsetLo = offset?.lo ?? 0;
    const results = this.vcdb!.async_scroll(
      this.instanceId,
      offsetHi,
      offsetLo,
      hasOffset,
      limit,
      true,
    );
    return results.map((r) => ({
      id: { hi: r._0, lo: r._1 },
      payload: parsePayload(r._2),
    }));
  }

  async scrollFiltered(
    filterJson: string,
    offset: VcdbId | undefined,
    limit: number,
  ): Promise<readonly { id: VcdbId; payload: Record<string, unknown> | null }[]> {
    await this.ensureInitialized();
    const hasOffset = offset !== undefined;
    const offsetHi = offset?.hi ?? 0;
    const offsetLo = offset?.lo ?? 0;
    const results = this.vcdb!.async_scroll_filtered(
      this.instanceId,
      filterJson,
      offsetHi,
      offsetLo,
      hasOffset,
      limit,
      true,
    );
    return results.map((r) => ({
      id: { hi: r._0, lo: r._1 },
      payload: parsePayload(r._2),
    }));
  }

  async countFiltered(filterJson: string): Promise<number> {
    await this.ensureInitialized();
    return this.vcdb!.async_count_filtered(this.instanceId, filterJson);
  }

  async compact(): Promise<{ removed: number }> {
    await this.ensureInitialized();
    const result = this.vcdb!.async_compact(this.instanceId);
    const removed = result._1;
    if (removed > 0) {
      await this.wal.checkpoint(this.vcdb!, this.instanceId);
    }
    return { removed };
  }

  size(): number {
    return this.vcdb?.async_db_size(this.instanceId) ?? 0;
  }

  rawSize(): number {
    return this.vcdb?.async_db_raw_size(this.instanceId) ?? 0;
  }

  dim(): number {
    return this.vcdb?.async_db_dim(this.instanceId) ?? 0;
  }
}
