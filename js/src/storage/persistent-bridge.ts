/**
 * @file Bridge from DOKeyValueStore to persistent_* FFI callbacks.
 *
 * The persistent_* API (persistent_register_wal_storage,
 * persistent_register_snapshot_storage) expects individual callback
 * functions with a StorageKind (int) parameter. DOKeyValueStore is
 * kind-agnostic — it doesn't route by StorageKind.
 *
 * This bridge adapts DOKeyValueStore instances into the callback
 * shape required by the persistent FFI, ignoring the kind parameter
 * since DOKeyValueStore handles routing at a higher level (e.g.,
 * separate stores for WAL vs snapshots).
 *
 * Usage:
 *   import { registerPersistentStorage, initPersistentDB } from "@vcdb/server/storage/persistent-bridge";
 *   import { createDOKeyValueStore } from "@vcdb/server/storage/do-kv";
 *
 *   const walStore = createDOKeyValueStore(ctx.storage, "w:");
 *   const snapshotStore = createR2Adapter(env.BUCKET, prefix);
 *   registerPersistentStorage(instanceId, walStore, snapshotStore);
 *   await initPersistentDB(instanceId, dim, capacity);
 */
import type { DOKeyValueStore } from "./do-kv.js";

/**
 * Minimal interface for the MoonBit WASM persistent_* FFI.
 * These functions are exported from @vcdb/server/wasm/lib.js.
 */
/**
 * MoonBit Int64 as hi/lo i32 pair — the JS target encoding.
 * Used for vector IDs, timestamps, and any Int64 across FFI boundaries.
 * Not vcdb-specific; this is how MoonBit's JS target represents Int64.
 */
export type MbInt64 = { readonly hi: number; readonly lo: number };

/**
 * MoonBit tuple representation in JS target.
 * Tuples like (A, B, C) become { _0: A, _1: B, _2: C } objects.
 */
type Tuple3<A, B, C> = { _0: A; _1: B; _2: C };
type Tuple4<A, B, C, D> = { _0: A; _1: B; _2: C; _3: D };

/**
 * Callback signature for persistent_register_*_storage.
 * MoonBit's StorageKind is passed as an int (0=Config, 1=Index, 2=Data).
 */
type StorageReadCb = (path: string, kind: number) => Promise<Uint8Array>;
type StorageWriteCb = (path: string, data: Uint8Array, kind: number) => Promise<void>;
type StorageDelCb = (path: string, kind: number) => Promise<void>;
type StorageExistsCb = (path: string, kind: number) => Promise<boolean>;
type StorageListCb = (kind: number) => Promise<string[]>;

interface PersistentFFI {
  persistent_register_wal_storage(
    instance_id: number,
    read: StorageReadCb,
    write: StorageWriteCb,
    atomic_write: StorageWriteCb,
    del: StorageDelCb,
    exists: StorageExistsCb,
    list: StorageListCb,
  ): void;

  persistent_register_snapshot_storage(
    instance_id: number,
    read: StorageReadCb,
    write: StorageWriteCb,
    atomic_write: StorageWriteCb,
    del: StorageDelCb,
    exists: StorageExistsCb,
    list: StorageListCb,
  ): void;

  persistent_init(
    instance_id: number,
    collection_name: string,
    base_path: string,
    dim: number,
    capacity: number,
  ): Promise<void>;

  persistent_upsert(
    instance_id: number,
    points: Array<Tuple4<number, number, number[], string>>,
    timestamp_ns: MbInt64,
  ): Promise<void>;

  persistent_remove(
    instance_id: number,
    id_hi: number,
    id_lo: number,
    timestamp_ns: MbInt64,
  ): Promise<boolean>;

  persistent_update_attrs(
    instance_id: number,
    id_hi: number,
    id_lo: number,
    attrs_json: string,
    timestamp_ns: MbInt64,
  ): Promise<boolean>;

  persistent_checkpoint(instance_id: number): Promise<void>;
  persistent_compact(instance_id: number): Promise<number>;
  persistent_destroy(instance_id: number): void;

  /** Returns Array of (id_hi, id_lo, score, payload_json) tuples. */
  persistent_search(
    instance_id: number,
    query: number[],
    k: number,
    with_payload: boolean,
    filter_json: string,
  ): Array<Tuple4<number, number, number, string>>;

  /** Returns (found, vector, payload_json) tuple. */
  persistent_get(
    instance_id: number,
    id_hi: number,
    id_lo: number,
    with_payload: boolean,
  ): Tuple3<boolean, number[], string>;

  persistent_has(
    instance_id: number,
    id_hi: number,
    id_lo: number,
  ): boolean;

  /** Returns Array of (id_hi, id_lo, payload_json) tuples. */
  persistent_scroll(
    instance_id: number,
    offset_hi: number,
    offset_lo: number,
    has_offset: boolean,
    limit: number,
    with_payload: boolean,
  ): Array<Tuple3<number, number, string>>;

  /** Returns Array of (id_hi, id_lo, payload_json) tuples. */
  persistent_scroll_filtered(
    instance_id: number,
    filter_json: string,
    offset_hi: number,
    offset_lo: number,
    has_offset: boolean,
    limit: number,
    with_payload: boolean,
  ): Array<Tuple3<number, number, string>>;

  persistent_count_filtered(
    instance_id: number,
    filter_json: string,
  ): number;

  persistent_db_size(instance_id: number): number;
  persistent_db_raw_size(instance_id: number): number;
  persistent_db_dim(instance_id: number): number;

  /**
   * CRUSH placement group for a vector ID.
   * Returns a number in [0, pg_count) — the SoT for shard routing.
   */
  crush_placement_group(
    id_hi: number,
    id_lo: number,
    pg_count: number,
  ): number;
}

/**
 * Adapt a DOKeyValueStore to the persistent_* callback shape.
 *
 * The persistent FFI passes a StorageKind int to every callback,
 * but DOKeyValueStore is kind-agnostic (routing is done at a higher
 * level by using separate stores for WAL vs snapshots). We ignore
 * the kind parameter.
 */
function storeToCallbacks(store: DOKeyValueStore) {
  return {
    read: async (path: string, _kind: number): Promise<Uint8Array> => {
      const data = await store.read(path);
      // MoonBit's async_read receives Bytes — return empty for missing files.
      // PersistentVectorDB handles empty bytes as "no data" during init.
      return data ?? new Uint8Array(0);
    },
    write: (path: string, data: Uint8Array, _kind: number): Promise<void> =>
      store.write(path, data),
    atomicWrite: (path: string, data: Uint8Array, _kind: number): Promise<void> =>
      store.write(path, data),
    del: (path: string, _kind: number): Promise<void> =>
      store.delete(path),
    exists: (path: string, _kind: number): Promise<boolean> =>
      store.exists(path),
    list: (_kind: number): Promise<string[]> =>
      store.list(),
  };
}

export interface RegisterPersistentStorageOptions {
  /**
   * Legacy snapshot store for one-time migration (e.g., DO → R2).
   *
   * When provided, if the snapshot is not found in snapshotStore but
   * exists in legacySnapshotStore, it is copied to snapshotStore and
   * deleted from legacySnapshotStore. This handles the migration
   * from storing snapshots in DO storage to R2.
   */
  legacySnapshotStore?: DOKeyValueStore;
  /**
   * Snapshot file path to check during legacy migration.
   * Defaults to the collection_data_path for the collection name.
   * Must match the actual file name used (e.g., "questions.data.bin").
   */
  legacySnapshotPath?: string;
}

/**
 * Register DOKeyValueStore instances as persistent storage backends.
 *
 * Prefetches chunk indexes for both stores, then registers the
 * adapted callbacks with the MoonBit persistent FFI.
 *
 * If legacySnapshotStore is provided, performs a one-time migration
 * of snapshot data from the legacy store to the new snapshot store.
 *
 * @param vcdb - The loaded WASM module (import("@vcdb/server/wasm/lib.js"))
 * @param instanceId - Stable instance ID (e.g., FNV-1a hash of DO ID)
 * @param walStore - DOKeyValueStore for WAL data (typically DO storage)
 * @param snapshotStore - DOKeyValueStore for snapshots (typically R2)
 * @param options - Optional legacy migration configuration
 */
export async function registerPersistentStorage(
  vcdb: PersistentFFI,
  instanceId: number,
  walStore: DOKeyValueStore,
  snapshotStore: DOKeyValueStore,
  options?: RegisterPersistentStorageOptions,
): Promise<void> {
  // Prefetch chunk indexes before registration — required for
  // chunked DO storage where values may exceed 120KB.
  const prefetches = [walStore.prefetch(), snapshotStore.prefetch()];
  if (options?.legacySnapshotStore) {
    prefetches.push(options.legacySnapshotStore.prefetch());
  }
  await Promise.all(prefetches);

  // One-time legacy migration: copy snapshot from old store to new store.
  if (options?.legacySnapshotStore && options.legacySnapshotPath) {
    const path = options.legacySnapshotPath;
    const existsInNew = await snapshotStore.exists(path);
    if (!existsInNew) {
      const legacyData = await options.legacySnapshotStore.read(path);
      if (legacyData) {
        await snapshotStore.write(path, legacyData);
        await options.legacySnapshotStore.delete(path);
      }
    }
  }

  const wal = storeToCallbacks(walStore);
  const snap = storeToCallbacks(snapshotStore);

  vcdb.persistent_register_wal_storage(
    instanceId,
    wal.read,
    wal.write,
    wal.atomicWrite,
    wal.del,
    wal.exists,
    wal.list,
  );

  vcdb.persistent_register_snapshot_storage(
    instanceId,
    snap.read,
    snap.write,
    snap.atomicWrite,
    snap.del,
    snap.exists,
    snap.list,
  );
}

export interface PersistentInitOptions {
  /**
   * Collection name — determines WAL/snapshot file names.
   * e.g., "questions" → "questions.vwal" + "questions.data.bin"
   */
  collectionName?: string;
  /**
   * Optional base path prefix for storage.
   * Empty string means files are stored at root.
   */
  basePath?: string;
}

/**
 * Initialize a persistent VectorDB instance.
 *
 * Loads WAL + snapshot from registered storage, replays WAL records,
 * and builds the in-memory VectorDB. Must be called after
 * registerPersistentStorage().
 *
 * @param collectionName - Determines file paths (default: "db").
 *   Must match the names used by existing data to avoid data loss.
 *   e.g., "questions" → "questions.vwal" + "questions.data.bin"
 */
export async function initPersistentDB(
  vcdb: PersistentFFI,
  instanceId: number,
  dim: number,
  capacity: number,
  options?: PersistentInitOptions,
): Promise<void> {
  const collectionName = options?.collectionName ?? "db";
  const basePath = options?.basePath ?? "";
  await vcdb.persistent_init(instanceId, collectionName, basePath, dim, capacity);
}

/**
 * Destroy a persistent instance and clean up storage callbacks.
 */
export function destroyPersistentDB(
  vcdb: PersistentFFI,
  instanceId: number,
): void {
  vcdb.persistent_destroy(instanceId);
}

export type { PersistentFFI };
