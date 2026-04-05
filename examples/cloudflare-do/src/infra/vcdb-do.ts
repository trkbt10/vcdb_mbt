/**
 * @file Durable Object that hosts a vcdb collection shard.
 *
 * Each DO shard gets its own vcdb instance_id — no global singleton.
 * Multiple shards sharing the same JS module are fully isolated.
 *
 * Uses the persistent_* FFI API which handles WAL management,
 * checkpointing, and crash recovery internally. This DO only needs
 * to register storage backends and call the persistent operations.
 *
 * Based on production patterns from usbkr.
 */
import { DurableObject } from "cloudflare:workers";
import { createDOKeyValueStore } from "@vcdb/server/storage/do-kv";
import { createR2KeyValueStore } from "@vcdb/server/storage/r2";
import {
  registerPersistentStorage,
  initPersistentDB,
  destroyPersistentDB,
  type PersistentFFI,
} from "@vcdb/server/storage/persistent-bridge";
import type { VcdbId, Bindings } from "../types.ts";
import { fnvHash } from "../types.ts";

const COLLECTION_NAME = "vectors";
const DIMENSIONS = 1024;
const INITIAL_CAPACITY = 1024;

type VcdbLib = PersistentFFI;

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

/** Current time as MoonBit Int64 (nanoseconds since epoch, hi/lo pair). */
const nowNs = (): { hi: number; lo: number } => {
  const ms = Date.now();
  const ns = ms * 1_000_000;
  return { hi: Math.floor(ns / 0x100000000), lo: ns >>> 0 };
};

export class VcdbStore extends DurableObject<Bindings> {
  private vcdb: VcdbLib | null = null;
  /** vcdb instance ID — derived from DO ID, stable across restarts. */
  private readonly instanceId: number;
  private initPromise: Promise<void> | null = null;

  constructor(ctx: DurableObjectState, env: Bindings) {
    super(ctx, env);

    // Stable instance ID derived from DO ID — survives DO restarts.
    this.instanceId = fnvHash(ctx.id.toString());

    // R2 keys are prefixed with the DO ID to isolate each shard's data.
    const doPrefix = ctx.id.toString() + "/";
    const walStore = createDOKeyValueStore(ctx.storage, "w:");
    const snapshotStore = createR2KeyValueStore({
      bucket: env.VCDB_DATA,
      keyPrefix: doPrefix,
    });

    // Store references for lazy initialization.
    this._walStore = walStore;
    this._snapshotStore = snapshotStore;
  }

  private _walStore;
  private _snapshotStore;

  private ensureInitialized(): Promise<void> {
    this.initPromise ??= this.doInit();
    return this.initPromise;
  }

  private async doInit(): Promise<void> {
    const vcdbLib: VcdbLib = await import("@vcdb/server/wasm/lib.js");
    this.vcdb = vcdbLib;

    // Register storage backends with the persistent FFI.
    // This prefetches chunk indexes and wires callbacks.
    await registerPersistentStorage(
      vcdbLib,
      this.instanceId,
      this._walStore,
      this._snapshotStore,
    );

    // Initialize: loads WAL + snapshot, replays, builds VectorDB.
    await initPersistentDB(vcdbLib, this.instanceId, DIMENSIONS, INITIAL_CAPACITY, {
      collectionName: COLLECTION_NAME,
    });

    const size = vcdbLib.persistent_db_size(this.instanceId);
    console.log(
      `[VcdbStore] instanceId=${this.instanceId} initialized, size=${size}`,
    );
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

    // persistent_upsert handles WAL-before-state and auto-checkpoint.
    await this.vcdb!.persistent_upsert(
      this.instanceId,
      vcdbPoints,
      nowNs(),
    );
  }

  async search(
    vector: number[],
    topK: number,
    filterJson: string = "",
  ): Promise<readonly VcdbSearchHit[]> {
    await this.ensureInitialized();

    // persistent_search is synchronous (reads are in-memory).
    const results = this.vcdb!.persistent_search(
      this.instanceId,
      vector,
      topK,
      true,
      filterJson,
    );
    return results.map((r: { _0: number; _1: number; _2: number; _3: string }) => ({
      id: { hi: r._0, lo: r._1 },
      score: r._2,
      payload: parsePayload(r._3),
    }));
  }

  async remove(id: VcdbId): Promise<void> {
    await this.ensureInitialized();
    await this.vcdb!.persistent_remove(
      this.instanceId,
      id.hi,
      id.lo,
      nowNs(),
    );
  }

  async getById(
    id: VcdbId,
  ): Promise<{
    found: boolean;
    vector: number[];
    payload: Record<string, unknown> | null;
  }> {
    await this.ensureInitialized();
    const result: { _0: boolean; _1: number[]; _2: string } =
      this.vcdb!.persistent_get(this.instanceId, id.hi, id.lo, true);
    return {
      found: result._0,
      vector: result._1,
      payload: result._0 ? parsePayload(result._2) : null,
    };
  }

  async has(id: VcdbId): Promise<boolean> {
    await this.ensureInitialized();
    return this.vcdb!.persistent_has(this.instanceId, id.hi, id.lo);
  }

  async updateAttrs(
    id: VcdbId,
    attrs: Record<string, unknown>,
  ): Promise<void> {
    await this.ensureInitialized();
    await this.vcdb!.persistent_update_attrs(
      this.instanceId,
      id.hi,
      id.lo,
      JSON.stringify(attrs),
      nowNs(),
    );
  }

  async scroll(
    offset: VcdbId | undefined,
    limit: number,
  ): Promise<readonly { id: VcdbId; payload: Record<string, unknown> | null }[]> {
    await this.ensureInitialized();
    const hasOffset = offset !== undefined;
    const offsetHi = offset?.hi ?? 0;
    const offsetLo = offset?.lo ?? 0;
    const results = this.vcdb!.persistent_scroll(
      this.instanceId,
      offsetHi,
      offsetLo,
      hasOffset,
      limit,
      true,
    );
    return results.map((r: { _0: number; _1: number; _2: string }) => ({
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
    const results = this.vcdb!.persistent_scroll_filtered(
      this.instanceId,
      filterJson,
      offsetHi,
      offsetLo,
      hasOffset,
      limit,
      true,
    );
    return results.map((r: { _0: number; _1: number; _2: string }) => ({
      id: { hi: r._0, lo: r._1 },
      payload: parsePayload(r._2),
    }));
  }

  async countFiltered(filterJson: string): Promise<number> {
    await this.ensureInitialized();
    return this.vcdb!.persistent_count_filtered(this.instanceId, filterJson);
  }

  async compact(): Promise<{ removed: number }> {
    await this.ensureInitialized();
    const removed = await this.vcdb!.persistent_compact(this.instanceId);
    return { removed };
  }

  size(): number {
    return this.vcdb?.persistent_db_size(this.instanceId) ?? 0;
  }

  rawSize(): number {
    return this.vcdb?.persistent_db_raw_size(this.instanceId) ?? 0;
  }

  dim(): number {
    return this.vcdb?.persistent_db_dim(this.instanceId) ?? 0;
  }
}
