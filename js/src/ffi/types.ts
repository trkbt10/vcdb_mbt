/**
 * @file Internal FFI type definitions for MoonBit JS target interop.
 *
 * This file mirrors the MoonBit FFI wire format exactly.
 * It must not contain any JS-side opinions — only what MoonBit emits.
 *
 * Wire format for VectorId: Uint8Array of exactly 16 bytes.
 *   Int64Id(v)    → bytes 0-7 = v big-endian, bytes 8-15 = 0x00
 *   Bytes16Id(b)  → bytes 0-15 = b as-is
 *
 * SoT: ffi/exports.mbt, VectorId::to_wire_bytes / VectorId::from_wire_bytes
 * in core/types/types.mbt.
 *
 * When the MoonBit FFI changes, update this file first, then update
 * packages/core to consume the new shapes.
 */

/* ── MoonBit JS-target primitive representations ─────────────── */

/** MoonBit tuple representations in JS target. */
export type Tuple2<A, B> = { _0: A; _1: B };
export type Tuple3<A, B, C> = { _0: A; _1: B; _2: C };

/* ── FFI slices ──────────────────────────────────────────────── */

/**
 * In-memory VectorDB operations.
 *
 * VectorId wire format: Uint8Array(16)
 *   Returned IDs (from search) are Uint8Array(16).
 *   Passed IDs (to add/upsert/get/has/remove) are Uint8Array(16).
 */
export interface VectorDbFfi {
  vcdb_create(dim: number): number;
  vcdb_create_hnsw(dim: number): number;
  vcdb_create_ivf(dim: number): number;
  vcdb_destroy(instanceId: number): void;
  vcdb_size(instanceId: number): number;
  vcdb_dim(instanceId: number): number;
  /** Returns 0 on success, -2 if already exists, -1 on error. */
  vcdb_add(instanceId: number, idBytes: Uint8Array, vector: number[]): number;
  /** Returns 0 on success, -1 on error. */
  vcdb_upsert(instanceId: number, idBytes: Uint8Array, vector: number[]): number;
  /** Returns (vector, 1) if found, ([], 0) if not found, ([], -1) on error. */
  vcdb_get(instanceId: number, idBytes: Uint8Array): Tuple2<number[], number>;
  /** Returns Array of (idBytes: Uint8Array(16), score). */
  vcdb_search(instanceId: number, query: number[], k: number): Array<Tuple2<Uint8Array, number>>;
  /** Returns 1 if exists, 0 if not, -1 on error. */
  vcdb_has(instanceId: number, idBytes: Uint8Array): number;
  /** Returns 1 if removed, 0 if not found, -1 on error. */
  vcdb_remove(instanceId: number, idBytes: Uint8Array): number;
  vcdb_serialize(instanceId: number): Uint8Array;
  vcdb_deserialize(data: Uint8Array): number;
}

/** Synchronous storage callbacks shape for gateway registration. */
export interface SyncStorageCallbacks {
  read(path: string, kind: number): Uint8Array;
  write(path: string, data: Uint8Array, kind: number): void;
  exists(path: string, kind: number): boolean;
  del(path: string, kind: number): void;
  list(kind: number): string[];
}

/** Gateway (HTTP-layer) operations. */
export interface GatewayFfi {
  gateway_request(method: string, path: string[], body: string): Promise<string>;
  gateway_register_storage(
    readFn: SyncStorageCallbacks["read"],
    writeFn: SyncStorageCallbacks["write"],
    existsFn: SyncStorageCallbacks["exists"],
    delFn: SyncStorageCallbacks["del"],
    listFn: SyncStorageCallbacks["list"],
  ): void;
  gateway_clear_storage_callbacks(): void;
  gateway_storage_list(kind: number): string[];
  gateway_storage_read(path: string, kind: number): Uint8Array;
  gateway_storage_write(path: string, data: Uint8Array, kind: number): void;
  gateway_storage_exists(path: string, kind: number): boolean;
}

/** Async storage callback signatures for persistent storage registration. */
export interface AsyncStorageCallbacks {
  read(path: string, kind: number): Promise<Uint8Array>;
  write(path: string, data: Uint8Array, kind: number): Promise<void>;
  atomicWrite(path: string, data: Uint8Array, kind: number): Promise<void>;
  del(path: string, kind: number): Promise<void>;
  exists(path: string, kind: number): Promise<boolean>;
  list(kind: number): Promise<string[]>;
}

/**
 * Persistent VectorDB operations (WAL + snapshot).
 *
 * VectorId wire format: Uint8Array(16)
 * Points tuple: (idBytes: Uint8Array(16), vector, payloadJson)
 * Search result: (idBytes: Uint8Array(16), score, payloadJson)
 * Scroll result: (idBytes: Uint8Array(16), payloadJson)
 */
export interface PersistentFfi {
  persistent_register_wal_storage(
    instanceId: number,
    read: AsyncStorageCallbacks["read"],
    write: AsyncStorageCallbacks["write"],
    atomicWrite: AsyncStorageCallbacks["atomicWrite"],
    del: AsyncStorageCallbacks["del"],
    exists: AsyncStorageCallbacks["exists"],
    list: AsyncStorageCallbacks["list"],
  ): void;
  persistent_register_snapshot_storage(
    instanceId: number,
    read: AsyncStorageCallbacks["read"],
    write: AsyncStorageCallbacks["write"],
    atomicWrite: AsyncStorageCallbacks["atomicWrite"],
    del: AsyncStorageCallbacks["del"],
    exists: AsyncStorageCallbacks["exists"],
    list: AsyncStorageCallbacks["list"],
  ): void;
  persistent_init(
    instanceId: number,
    collectionName: string,
    basePath: string,
    dim: number,
    capacity: number,
    metric: string,
    strategy: string,
  ): Promise<void>;
  /** points: Array of (idBytes: Uint8Array(16), vector, payloadJson) */
  persistent_upsert(
    instanceId: number,
    points: Array<Tuple3<Uint8Array, number[], string>>,
    timestampNs: bigint,
  ): Promise<void>;
  /** Returns Promise<boolean>: true if removed. */
  persistent_remove(
    instanceId: number,
    idBytes: Uint8Array,
    timestampNs: bigint,
  ): Promise<boolean>;
  persistent_update_attrs(
    instanceId: number,
    idBytes: Uint8Array,
    attrsJson: string,
    timestampNs: bigint,
  ): Promise<boolean>;
  persistent_checkpoint(instanceId: number): Promise<void>;
  persistent_compact(instanceId: number): Promise<number>;
  persistent_destroy(instanceId: number): void;
  /** Returns Array of (idBytes: Uint8Array(16), score, payloadJson) */
  persistent_search(
    instanceId: number,
    query: number[],
    k: number,
    withPayload: boolean,
    filterJson: string,
  ): Array<Tuple3<Uint8Array, number, string>>;
  /** Returns (found, vector, payloadJson) */
  persistent_get(
    instanceId: number,
    idBytes: Uint8Array,
    withPayload: boolean,
  ): Tuple3<boolean, number[], string>;
  persistent_has(instanceId: number, idBytes: Uint8Array): boolean;
  /** offset: Uint8Array(16) or empty Uint8Array to start from beginning */
  persistent_scroll(
    instanceId: number,
    offsetBytes: Uint8Array,
    limit: number,
    withPayload: boolean,
  ): Array<Tuple2<Uint8Array, string>>;
  persistent_scroll_filtered(
    instanceId: number,
    filterJson: string,
    offsetBytes: Uint8Array,
    limit: number,
    withPayload: boolean,
  ): Array<Tuple2<Uint8Array, string>>;
  persistent_count_filtered(instanceId: number, filterJson: string): number;
  persistent_db_size(instanceId: number): number;
  persistent_db_raw_size(instanceId: number): number;
  persistent_db_dim(instanceId: number): number;
}

/**
 * CRUSH placement & distributed merge operations.
 *
 * VectorId wire format: Uint8Array(16)
 */
export interface DistributedFfi {
  /** id_bytes: Uint8Array(16). Returns placement group in [0, pgCount). */
  crush_placement_group(idBytes: Uint8Array, pgCount: number): number;
  /** shard hits: (idBytes: Uint8Array(16), score, payloadJson) */
  distributed_merge_search(
    shardResults: Array<Tuple3<number, Array<Tuple3<Uint8Array, number, string>>, string>>,
    topK: number,
  ): Tuple3<Array<Tuple3<Uint8Array, number, string>>, number[], Array<Tuple2<number, string>>>;
  /** shard entries: (idBytes: Uint8Array(16), attrsJson) */
  distributed_merge_scroll(
    shardResults: Array<Tuple3<number, Array<Tuple2<Uint8Array, string>>, string>>,
    limit: number,
  ): Tuple3<Array<Tuple2<Uint8Array, string>>, number[], Array<Tuple2<number, string>>>;
  distributed_merge_count(
    shardResults: Array<Tuple3<number, number, string>>,
  ): Tuple3<number, number[], Array<Tuple2<number, string>>>;
  /** points: (idBytes: Uint8Array(16), vector, payloadJson) */
  distributed_group_upsert(
    points: Array<Tuple3<Uint8Array, number[], string>>,
    pgCount: number,
  ): Array<Tuple2<number, Array<Tuple3<Uint8Array, number[], string>>>>;
}

/* ── Composite FFI types ────────────────────────────────────── */

/**
 * Complete MoonBit JS-target module interface.
 *
 * Only the loader needs this full type.
 * All other code should depend on the specific slice it actually uses.
 */
export type WasmModule =
  & VectorDbFfi
  & GatewayFfi
  & PersistentFfi
  & DistributedFfi;
