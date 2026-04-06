/**
 * @file Durable Object that hosts a vcdb collection shard.
 *
 * Each DO shard gets its own vcdb instance_id — no global singleton.
 * Multiple shards sharing the same JS module are fully isolated.
 *
 * This DO exists solely to satisfy Cloudflare's RPC constraint:
 * each cross-DO method call requires a class method on the DO itself.
 * It initializes PersistentDB on first access, then delegates all
 * operations to it.
 *
 * Based on production deployment patterns.
 */
import { DurableObject } from "cloudflare:workers";
import { createDOKeyValueStore } from "@vcdb/server/storage/do-kv";
import { createR2KeyValueStore } from "@vcdb/server/storage/r2";
import {
  registerPersistentStorage,
  initPersistentDB,
  type PersistentFFI,
} from "@vcdb/server/storage/persistent-bridge";
import { PersistentDB } from "@vcdb/server/persistent";
import type { Bindings } from "../types.ts";

const COLLECTION_NAME = "vectors";
const DIMENSIONS = 1024;
const INITIAL_CAPACITY = 1024;

/**
 * Derive a stable u32 from a string via FNV-1a hash.
 * DO IDs are hex strings (UUID-based); persistent_* API needs an Int
 * instance_id. FNV-1a gives a deterministic mapping that survives
 * DO restarts without requiring external state.
 */
const fnvHash = (key: string): number => {
  let h = 0x811c9dc5;
  for (const byte of new TextEncoder().encode(key)) {
    h ^= byte;
    h = Math.imul(h, 0x01000193) | 0;
  }
  return h >>> 0;
};

export class VcdbStore extends DurableObject<Bindings> {
  private db: PersistentDB | null = null;
  private readonly instanceId: number;
  private initPromise: Promise<void> | null = null;
  private _walStore;
  private _snapshotStore;

  constructor(ctx: DurableObjectState, env: Bindings) {
    super(ctx, env);

    this.instanceId = fnvHash(ctx.id.toString());

    const doPrefix = ctx.id.toString() + "/";
    this._walStore = createDOKeyValueStore(ctx.storage, "w:");
    this._snapshotStore = createR2KeyValueStore({
      bucket: env.VCDB_DATA,
      keyPrefix: doPrefix,
    });
  }

  private ensureInitialized(): Promise<void> {
    this.initPromise ??= this.doInit();
    return this.initPromise;
  }

  private async doInit(): Promise<void> {
    const ffi: PersistentFFI = await import("@vcdb/server/wasm/lib.js");

    await registerPersistentStorage(
      ffi,
      this.instanceId,
      this._walStore,
      this._snapshotStore,
    );

    await initPersistentDB(ffi, this.instanceId, DIMENSIONS, INITIAL_CAPACITY, {
      collectionName: COLLECTION_NAME,
    });

    this.db = new PersistentDB(ffi, this.instanceId);

    console.log(
      `[VcdbStore] instanceId=${this.instanceId} initialized, size=${this.db.size()}`,
    );
  }

  // ── DO RPC methods ────────────────────────────────────────
  //
  // Cloudflare DO RPC requires each operation to be a method on the
  // DO class itself — we cannot return PersistentDB and let callers
  // invoke methods on it. These thin methods exist solely for that
  // constraint. Add methods here only when shard-router needs them.

  /** @internal Used by shard-router */
  async upsert(
    points: Parameters<PersistentDB["upsert"]>[0],
  ): Promise<void> {
    await this.ensureInitialized();
    await this.db!.upsert(points);
  }

  /** @internal Used by shard-router */
  async search(
    ...args: Parameters<PersistentDB["search"]>
  ): Promise<ReturnType<PersistentDB["search"]>> {
    await this.ensureInitialized();
    return this.db!.search(...args);
  }

  /** @internal Used by shard-router */
  async getById(
    ...args: Parameters<PersistentDB["get"]>
  ): Promise<ReturnType<PersistentDB["get"]>> {
    await this.ensureInitialized();
    return this.db!.get(...args);
  }

  /** @internal Used by shard-router */
  async scrollFiltered(
    ...args: Parameters<PersistentDB["scrollFiltered"]>
  ): Promise<ReturnType<PersistentDB["scrollFiltered"]>> {
    await this.ensureInitialized();
    return this.db!.scrollFiltered(...args);
  }

  /** @internal Used by shard-router */
  async countFiltered(
    ...args: Parameters<PersistentDB["countFiltered"]>
  ): Promise<ReturnType<PersistentDB["countFiltered"]>> {
    await this.ensureInitialized();
    return this.db!.countFiltered(...args);
  }
}
