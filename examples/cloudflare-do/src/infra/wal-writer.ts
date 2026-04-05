/**
 * @file WAL buffer management and persistence.
 *
 * Maintains an in-memory WAL buffer, merges new segments via MoonBit's
 * merge_wal (single source of truth), and flushes to a DOKeyValueStore.
 *
 * WAL store and snapshot store are injected separately:
 *   - WAL stays in DO storage (write coalescing required for atomicity)
 *   - Snapshot goes to R2 (or DO storage if R2 is unavailable)
 *
 * Checkpoint is triggered by either record count OR WAL byte size,
 * whichever is reached first. This prevents WAL from exceeding
 * DO storage per-value limits (128KB) even with large payloads.
 */
import type { DOKeyValueStore } from "@vcdb/server/storage/do-kv";

type VcdbLib = typeof import("@vcdb/server/wasm/lib.js");

/** Max WAL size before forcing checkpoint (well under DO 128KB limit). */
const WAL_SIZE_CHECKPOINT_BYTES = 100_000;

export type WalWriter = {
  /** Load existing WAL + snapshot from storage. */
  load(): Promise<{
    walData: Uint8Array | null;
    snapshotData: Uint8Array | null;
  }>;
  /** Append a WAL segment and flush to storage. */
  append(vcdb: VcdbLib, walSegment: Uint8Array, pointCount: number): Promise<void>;
  /** Write snapshot + truncate WAL. */
  checkpoint(vcdb: VcdbLib, instanceId: number): Promise<void>;
  /** Whether checkpoint threshold has been reached (record count or WAL size). */
  readonly shouldCheckpoint: boolean;
};

export function createWalWriter(
  walStore: DOKeyValueStore,
  snapshotStore: DOKeyValueStore,
  walPath: string,
  snapshotPath: string,
  checkpointThreshold: number,
  /** Legacy snapshot store for one-time migration (e.g., DO→R2). */
  legacySnapshotStore?: DOKeyValueStore,
): WalWriter {
  const state: { data: Uint8Array; recordCount: number } = {
    data: new Uint8Array(0),
    recordCount: 0,
  };
  const sameBackend = walStore === snapshotStore;

  return {
    async load() {
      // Prefetch chunk indexes before reading — required for chunked
      // DO storage where values exceed 120KB.
      await walStore.prefetch();
      await snapshotStore.prefetch();

      const walData = await walStore.read(walPath);
      let snapshotData = await snapshotStore.read(snapshotPath);

      // One-time migration: if snapshot is in legacy store but not in
      // current store, copy it over and delete from legacy.
      if (!snapshotData && legacySnapshotStore) {
        await legacySnapshotStore.prefetch();
        const legacySnapshot = await legacySnapshotStore.read(snapshotPath);
        if (legacySnapshot) {
          await snapshotStore.write(snapshotPath, legacySnapshot);
          await legacySnapshotStore.delete(snapshotPath);
          snapshotData = legacySnapshot;
        }
      }

      if (walData) {
        state.data = walData;
      }
      return { walData, snapshotData };
    },

    async append(vcdb, walSegment, pointCount) {
      // Synchronous merge (DO input gate closed)
      state.data = vcdb.async_merge_wal(state.data, walSegment);
      state.recordCount += pointCount;

      await walStore.write(walPath, state.data);
    },

    async checkpoint(vcdb, instanceId) {
      const snapshot = vcdb.async_serialize_snapshot(instanceId);
      const walHeader = vcdb.async_wal_header();

      // Update in-memory state synchronously
      state.data = walHeader;
      state.recordCount = 0;

      if (sameBackend) {
        await walStore.writeAtomic([
          { path: snapshotPath, data: snapshot },
          { path: walPath, data: walHeader },
        ]);
      } else {
        // Different backends: write snapshot first (durable),
        // then truncate WAL. If crash between the two,
        // WAL replay on next load is idempotent — no data loss.
        await snapshotStore.write(snapshotPath, snapshot);
        await walStore.write(walPath, walHeader);
      }
    },

    get shouldCheckpoint() {
      return (
        state.recordCount >= checkpointThreshold ||
        state.data.byteLength >= WAL_SIZE_CHECKPOINT_BYTES
      );
    },
  };
}
