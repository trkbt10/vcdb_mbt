/**
 * MoonBit WASM/JS VectorDB bindings
 */
import type { StorageKindType } from "../storage/types.js";

// Re-export storage types for convenience
export { StorageKind, type StorageAdapter, type StorageKindType } from "../storage/types.js";

type MoonBitModule = {
  vcdb_create(dim: number): number;
  vcdb_create_hnsw(dim: number): number;
  vcdb_create_ivf(dim: number): number;
  vcdb_destroy(instanceId: number): void;
  vcdb_size(instanceId: number): number;
  vcdb_dim(instanceId: number): number;
  vcdb_add(instanceId: number, vectorId: number, vector: number[]): number;
  vcdb_upsert(instanceId: number, vectorId: number, vector: number[]): number;
  vcdb_get(instanceId: number, vectorId: number): { _0: number[]; _1: number };
  vcdb_search(instanceId: number, query: number[], k: number): Array<{ _0: number; _1: number }>;
  vcdb_has(instanceId: number, vectorId: number): number;
  vcdb_remove(instanceId: number, vectorId: number): number;
  vcdb_serialize(instanceId: number): Uint8Array;
  vcdb_deserialize(data: Uint8Array): number;
  gateway_request(method: string, path: string[], body: string): string;
  gateway_register_storage(
    readFn: (path: string, kind: number) => Uint8Array,
    writeFn: (path: string, data: Uint8Array, kind: number) => void,
    existsFn: (path: string, kind: number) => boolean,
    delFn: (path: string, kind: number) => void,
    listFn: (kind: number) => string[]
  ): void;
  gateway_clear_storage_callbacks(): void;
  gateway_storage_list(kind: number): string[];
  gateway_storage_read(path: string, kind: number): Uint8Array;
  gateway_storage_write(path: string, data: Uint8Array, kind: number): void;
  gateway_storage_exists(path: string, kind: number): boolean;
};

let wasmModule: MoonBitModule | null = null;
const DEFAULT_LIB_PATH = "./lib.js";

export async function loadWasm(moduleOrPath?: string | Record<string, unknown>): Promise<void> {
  if (wasmModule) return;
  if (typeof moduleOrPath === "object" && moduleOrPath !== null) {
    // Accept a pre-imported module object directly (for bundlers like Wrangler)
    wasmModule = moduleOrPath as unknown as MoonBitModule;
    return;
  }
  const path = moduleOrPath ?? DEFAULT_LIB_PATH;
  const mod = await import(path);
  wasmModule = mod as unknown as MoonBitModule;
}

export function isLoaded(): boolean {
  return wasmModule !== null;
}

function getModule(): MoonBitModule {
  if (!wasmModule) {
    throw new Error("WASM module not loaded. Call loadWasm() first.");
  }
  return wasmModule;
}

// ============================================================================
// Gateway API
// ============================================================================

export interface GatewayResponse {
  status: "ok" | "error";
  result?: unknown;
  error?: string;
}

export function gatewayRequest(
  method: string,
  path: string[],
  body: unknown = {}
): GatewayResponse {
  const mod = getModule();
  const bodyStr = typeof body === "string" ? body : JSON.stringify(body);
  const responseStr = mod.gateway_request(method, path, bodyStr);
  return JSON.parse(responseStr) as GatewayResponse;
}

// ============================================================================
// Storage Registration (low-level)
// ============================================================================

export interface WasmStorageCallbacks {
  read: (path: string, kind: number) => Uint8Array;
  write: (path: string, data: Uint8Array, kind: number) => void;
  exists: (path: string, kind: number) => boolean;
  del: (path: string, kind: number) => void;
  list: (kind: number) => string[];
}

/**
 * Register storage callbacks with the WASM gateway.
 * Note: Callbacks must be synchronous (WASM FFI limitation).
 */
export function registerStorageCallbacks(callbacks: WasmStorageCallbacks): void {
  getModule().gateway_register_storage(
    callbacks.read,
    callbacks.write,
    callbacks.exists,
    callbacks.del,
    callbacks.list
  );
}

export function clearStorageCallbacks(): void {
  getModule().gateway_clear_storage_callbacks();
}

// ============================================================================
// Direct Storage Access
// ============================================================================

export function gatewayStorageList(kind: StorageKindType): string[] {
  return getModule().gateway_storage_list(kind);
}

export function gatewayStorageRead(path: string, kind: StorageKindType): Uint8Array {
  return getModule().gateway_storage_read(path, kind);
}

export function gatewayStorageWrite(path: string, data: Uint8Array, kind: StorageKindType): void {
  getModule().gateway_storage_write(path, data, kind);
}

export function gatewayStorageExists(path: string, kind: StorageKindType): boolean {
  return getModule().gateway_storage_exists(path, kind);
}

// ============================================================================
// VectorDB Class
// ============================================================================

export type Metric = "cosine" | "l2" | "dot";
export type Strategy = "bruteforce" | "hnsw" | "ivf";
export interface SearchResult { id: number; score: number; }

export class VectorDB {
  private instanceId: number;
  private disposed = false;

  constructor(dim: number, strategy: Strategy = "bruteforce") {
    const mod = getModule();
    switch (strategy) {
      case "hnsw":
        this.instanceId = mod.vcdb_create_hnsw(dim);
        break;
      case "ivf":
        this.instanceId = mod.vcdb_create_ivf(dim);
        break;
      default:
        this.instanceId = mod.vcdb_create(dim);
    }
  }

  private checkDisposed(): void {
    if (this.disposed) throw new Error("VectorDB instance has been disposed");
  }

  get size(): number {
    this.checkDisposed();
    return getModule().vcdb_size(this.instanceId);
  }

  get dim(): number {
    this.checkDisposed();
    return getModule().vcdb_dim(this.instanceId);
  }

  add(id: number, vector: number[]): void {
    this.checkDisposed();
    const result = getModule().vcdb_add(this.instanceId, id, vector);
    if (result === -2) throw new Error("Vector already exists");
    if (result !== 0) throw new Error("Failed to add vector");
  }

  upsert(id: number, vector: number[]): void {
    this.checkDisposed();
    const result = getModule().vcdb_upsert(this.instanceId, id, vector);
    if (result !== 0) throw new Error("Failed to upsert vector");
  }

  get(id: number): number[] | undefined {
    this.checkDisposed();
    const result = getModule().vcdb_get(this.instanceId, id);
    return result._1 === 1 ? result._0 : undefined;
  }

  search(query: number[], k: number): SearchResult[] {
    this.checkDisposed();
    const results = getModule().vcdb_search(this.instanceId, query, k);
    return results.map((r) => ({ id: r._0, score: r._1 }));
  }

  has(id: number): boolean {
    this.checkDisposed();
    return getModule().vcdb_has(this.instanceId, id) === 1;
  }

  remove(id: number): boolean {
    this.checkDisposed();
    return getModule().vcdb_remove(this.instanceId, id) === 1;
  }

  serialize(): Uint8Array {
    this.checkDisposed();
    return getModule().vcdb_serialize(this.instanceId);
  }

  static deserialize(data: Uint8Array): VectorDB {
    const mod = getModule();
    const instanceId = mod.vcdb_deserialize(data);
    const db = Object.create(VectorDB.prototype) as VectorDB;
    db.instanceId = instanceId;
    db.disposed = false;
    return db;
  }

  dispose(): void {
    if (!this.disposed) {
      getModule().vcdb_destroy(this.instanceId);
      this.disposed = true;
    }
  }
}
