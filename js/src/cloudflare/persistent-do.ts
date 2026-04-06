/**
 * @file Cloudflare Durable Object persistent storage bridge.
 *
 * Adapts DOKeyValueStore instances into the async callback shape
 * required by PersistentFfi for WAL and snapshot registration.
 *
 * This is Cloudflare DO-specific. Other platforms should write
 * their own bridge against PersistentFfi + AsyncStorageCallbacks.
 */
import type { DOKeyValueStore } from "../storage/do-kv.js";
import type { PersistentFfi, AsyncStorageCallbacks } from "../ffi/types.js";
import type { Metric, Strategy } from "../types.js";

/**
 * Adapt a DOKeyValueStore to AsyncStorageCallbacks.
 *
 * The persistent FFI passes a StorageKind int to every callback,
 * but DOKeyValueStore is kind-agnostic (routing is done at a higher
 * level by using separate stores for WAL vs snapshots). We ignore
 * the kind parameter.
 */
function storeToCallbacks(store: DOKeyValueStore): AsyncStorageCallbacks {
  return {
    read: async (path: string, _kind: number): Promise<Uint8Array> => {
      const data = await store.read(path);
      if (data === null) {
        throw new Error(`Persistent storage read failed: ${path} not found`);
      }
      return data;
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
  legacySnapshotStore?: DOKeyValueStore;
  legacySnapshotPath?: string;
}

/**
 * Register DOKeyValueStore instances as persistent storage backends.
 *
 * Prefetches chunk indexes for both stores, then registers the
 * adapted callbacks with the MoonBit persistent FFI.
 */
export async function registerPersistentStorage(
  ffi: PersistentFfi,
  instanceId: number,
  walStore: DOKeyValueStore,
  snapshotStore: DOKeyValueStore,
  options?: RegisterPersistentStorageOptions,
): Promise<void> {
  const prefetches = [walStore.prefetch(), snapshotStore.prefetch()];
  if (options?.legacySnapshotStore) {
    prefetches.push(options.legacySnapshotStore.prefetch());
  }
  await Promise.all(prefetches);

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

  ffi.persistent_register_wal_storage(
    instanceId,
    wal.read,
    wal.write,
    wal.atomicWrite,
    wal.del,
    wal.exists,
    wal.list,
  );

  ffi.persistent_register_snapshot_storage(
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
  collectionName?: string;
  basePath?: string;
  metric: Metric;
  strategy: Strategy;
}

/**
 * Initialize a persistent VectorDB instance.
 */
export async function initPersistentDB(
  ffi: PersistentFfi,
  instanceId: number,
  dim: number,
  capacity: number,
  options: PersistentInitOptions,
): Promise<void> {
  const collectionName = options.collectionName ?? "db";
  const basePath = options.basePath ?? "";
  await ffi.persistent_init(
    instanceId,
    collectionName,
    basePath,
    dim,
    capacity,
    options.metric,
    options.strategy,
  );
}

/**
 * Destroy a persistent instance and clean up storage callbacks.
 */
export function destroyPersistentDB(
  ffi: PersistentFfi,
  instanceId: number,
): void {
  ffi.persistent_destroy(instanceId);
}
