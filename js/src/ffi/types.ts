/**
 * @file Internal FFI type definitions for MoonBit JS target interop.
 *
 * This file defines the raw shapes that MoonBit's JS target emits.
 * Nothing here should be re-exported from the public API.
 *
 * Each FFI slice is a minimal interface covering one functional area.
 * Consumers declare which slice they need — they never see the full module.
 *
 * When the target changes (e.g. wasm-gc), only this file and the
 * conversion functions in vector-id.ts need to change.
 */

/* ── MoonBit JS-target primitive representations ─────────────── */

/** MoonBit Int64 as hi/lo i32 pair (JS target specific). */
export type MbInt64 = { readonly hi: number; readonly lo: number };

/** MoonBit tuple representations in JS target. */
export type Tuple2<A, B> = { _0: A; _1: B };
export type Tuple3<A, B, C> = { _0: A; _1: B; _2: C };
export type Tuple4<A, B, C, D> = { _0: A; _1: B; _2: C; _3: D };

/* ── FFI slices ──────────────────────────────────────────────── */

/** In-memory VectorDB operations. */
export interface VectorDbFfi {
  vcdb_create(dim: number): number;
  vcdb_create_hnsw(dim: number): number;
  vcdb_create_ivf(dim: number): number;
  vcdb_destroy(instanceId: number): void;
  vcdb_size(instanceId: number): number;
  vcdb_dim(instanceId: number): number;
  vcdb_add(instanceId: number, idHi: number, idLo: number, vector: number[]): number;
  vcdb_upsert(instanceId: number, idHi: number, idLo: number, vector: number[]): number;
  vcdb_get(instanceId: number, idHi: number, idLo: number): Tuple2<number[], number>;
  vcdb_search(instanceId: number, query: number[], k: number): Array<Tuple3<number, number, number>>;
  vcdb_has(instanceId: number, idHi: number, idLo: number): number;
  vcdb_remove(instanceId: number, idHi: number, idLo: number): number;
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

/** Persistent VectorDB operations (WAL + snapshot). */
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
  persistent_upsert(
    instanceId: number,
    points: Array<Tuple4<number, number, number[], string>>,
    timestampNs: MbInt64,
  ): Promise<void>;
  persistent_remove(
    instanceId: number,
    idHi: number,
    idLo: number,
    timestampNs: MbInt64,
  ): Promise<boolean>;
  persistent_update_attrs(
    instanceId: number,
    idHi: number,
    idLo: number,
    attrsJson: string,
    timestampNs: MbInt64,
  ): Promise<boolean>;
  persistent_checkpoint(instanceId: number): Promise<void>;
  persistent_compact(instanceId: number): Promise<number>;
  persistent_destroy(instanceId: number): void;
  persistent_search(
    instanceId: number,
    query: number[],
    k: number,
    withPayload: boolean,
    filterJson: string,
  ): Array<Tuple4<number, number, number, string>>;
  persistent_get(
    instanceId: number,
    idHi: number,
    idLo: number,
    withPayload: boolean,
  ): Tuple3<boolean, number[], string>;
  persistent_has(instanceId: number, idHi: number, idLo: number): boolean;
  persistent_scroll(
    instanceId: number,
    offsetHi: number,
    offsetLo: number,
    hasOffset: boolean,
    limit: number,
    withPayload: boolean,
  ): Array<Tuple3<number, number, string>>;
  persistent_scroll_filtered(
    instanceId: number,
    filterJson: string,
    offsetHi: number,
    offsetLo: number,
    hasOffset: boolean,
    limit: number,
    withPayload: boolean,
  ): Array<Tuple3<number, number, string>>;
  persistent_count_filtered(instanceId: number, filterJson: string): number;
  persistent_db_size(instanceId: number): number;
  persistent_db_raw_size(instanceId: number): number;
  persistent_db_dim(instanceId: number): number;
}

/** CRUSH placement & distributed merge operations. */
export interface DistributedFfi {
  crush_placement_group(idHi: number, idLo: number, pgCount: number): number;
  distributed_merge_search(
    shardResults: Array<Tuple3<number, Array<Tuple4<number, number, number, string>>, string>>,
    topK: number,
  ): Tuple3<Array<Tuple4<number, number, number, string>>, number[], Array<Tuple2<number, string>>>;
  distributed_merge_scroll(
    shardResults: Array<Tuple3<number, Array<Tuple3<number, number, string>>, string>>,
    limit: number,
  ): Tuple3<Array<Tuple3<number, number, string>>, number[], Array<Tuple2<number, string>>>;
  distributed_merge_count(
    shardResults: Array<Tuple3<number, number, string>>,
  ): Tuple3<number, number[], Array<Tuple2<number, string>>>;
  distributed_group_upsert(
    points: Array<Tuple4<number, number, number[], string>>,
    pgCount: number,
  ): Array<Tuple2<number, Array<Tuple4<number, number, number[], string>>>>;
}

/** Int64 string utilities (internal — not exposed in public API). */
export interface Int64UtilFfi {
  parse_int64(input: string): Tuple3<boolean, number, number>;
  format_int64(hi: number, lo: number): string;
}

/* ── Full module type (for loader only) ──────────────────────── */

/**
 * Complete MoonBit JS-target module interface.
 *
 * This is the intersection of all FFI slices. Only the loader
 * needs this full type — all other code should depend on the
 * specific slice it actually uses.
 */
export type WasmModule =
  & VectorDbFfi
  & GatewayFfi
  & PersistentFfi
  & DistributedFfi
  & Int64UtilFfi;
