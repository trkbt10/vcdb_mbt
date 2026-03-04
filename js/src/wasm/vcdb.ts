/**
 * @file MoonBit WASM/JS VectorDB bindings
 * High-level TypeScript wrapper for the MoonBit vcdb library.
 */

// These types will be provided by the MoonBit JS build
type MoonBitModule = {
  vcdb_create(dim: number): number;
  vcdb_create_hnsw(dim: number): number;
  vcdb_create_ivf(dim: number): number;
  vcdb_destroy(instanceId: number): void;
  vcdb_size(instanceId: number): number;
  vcdb_dim(instanceId: number): number;
  vcdb_add(instanceId: number, vectorId: number, vector: number[]): number;
  vcdb_upsert(instanceId: number, vectorId: number, vector: number[]): number;
  vcdb_get(
    instanceId: number,
    vectorId: number
  ): { _0: number[]; _1: number };
  vcdb_search(
    instanceId: number,
    query: number[],
    k: number
  ): Array<{ _0: number; _1: number }>;
  vcdb_has(instanceId: number, vectorId: number): number;
  vcdb_remove(instanceId: number, vectorId: number): number;
  vcdb_serialize(instanceId: number): Uint8Array;
  vcdb_deserialize(data: Uint8Array): number;
  gateway_request(method: string, path: string[], body: string): string;
  gateway_storage_list(): string[];
  gateway_storage_read(path: string): Uint8Array;
  gateway_storage_write(path: string, data: Uint8Array): void;
  gateway_storage_exists(path: string): boolean;
};

let wasmModule: MoonBitModule | null = null;

// Default module path (relative to dist/wasm/)
const DEFAULT_LIB_PATH = "./lib.js";

/**
 * Load the MoonBit WASM module.
 * Call this before using any VectorDB functions.
 *
 * @param modulePath - Optional path to the lib.js module (for bundlers)
 */
export async function loadWasm(modulePath?: string): Promise<void> {
  if (wasmModule) return;

  const path = modulePath ?? DEFAULT_LIB_PATH;
  // Dynamic import - path is resolved at runtime
  const mod = await import(path);
  wasmModule = mod as unknown as MoonBitModule;
}

/**
 * Check if WASM module is loaded
 */
export function isLoaded(): boolean {
  return wasmModule !== null;
}

/**
 * Gateway API response
 */
export interface GatewayResponse {
  status: "ok" | "error";
  result?: unknown;
  error?: string;
}

/**
 * Execute a gateway API request.
 * This delegates to the MoonBit gateway implementation.
 *
 * @param method - HTTP method (GET, POST, PUT, DELETE)
 * @param path - URL path segments
 * @param body - Request body (will be JSON stringified)
 * @returns Gateway response
 */
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
// Gateway Storage API - for syncing WASM storage to disk
// ============================================================================

/**
 * List all files in gateway storage
 */
export function gatewayStorageList(): string[] {
  return getModule().gateway_storage_list();
}

/**
 * Read a file from gateway storage
 */
export function gatewayStorageRead(path: string): Uint8Array {
  return getModule().gateway_storage_read(path);
}

/**
 * Write a file to gateway storage
 */
export function gatewayStorageWrite(path: string, data: Uint8Array): void {
  getModule().gateway_storage_write(path, data);
}

/**
 * Check if a file exists in gateway storage
 */
export function gatewayStorageExists(path: string): boolean {
  return getModule().gateway_storage_exists(path);
}

function getModule(): MoonBitModule {
  if (!wasmModule) {
    throw new Error("WASM module not loaded. Call loadWasm() first.");
  }
  return wasmModule;
}

/** Distance metric */
export type Metric = "cosine" | "l2" | "dot";

/** Indexing strategy */
export type Strategy = "bruteforce" | "hnsw" | "ivf";

/** Search result */
export interface SearchResult {
  id: number;
  score: number;
}

/**
 * VectorDB - High-performance vector database powered by MoonBit WASM.
 *
 * Usage:
 * ```typescript
 * import { loadWasm, VectorDB } from "@vcdb/server/wasm";
 *
 * await loadWasm();
 * const db = new VectorDB(128); // 128-dimensional vectors
 * db.add(1, [0.1, 0.2, ...]);
 * const results = db.search([0.1, 0.2, ...], 10);
 * ```
 */
export class VectorDB {
  private instanceId: number;
  private disposed = false;

  /**
   * Create a new VectorDB instance.
   *
   * @param dim - Vector dimension
   * @param strategy - Indexing strategy (default: bruteforce)
   */
  constructor(dim: number, strategy: Strategy = "bruteforce") {
    const mod = getModule();

    switch (strategy) {
      case "hnsw":
        this.instanceId = mod.vcdb_create_hnsw(dim);
        break;
      case "ivf":
        this.instanceId = mod.vcdb_create_ivf(dim);
        break;
      case "bruteforce":
      default:
        this.instanceId = mod.vcdb_create(dim);
        break;
    }
  }

  private checkDisposed(): void {
    if (this.disposed) {
      throw new Error("VectorDB instance has been disposed");
    }
  }

  /** Get the number of vectors in the database */
  get size(): number {
    this.checkDisposed();
    return getModule().vcdb_size(this.instanceId);
  }

  /** Get the vector dimension */
  get dim(): number {
    this.checkDisposed();
    return getModule().vcdb_dim(this.instanceId);
  }

  /**
   * Add a vector to the database (fails if exists).
   *
   * @param id - Unique vector ID
   * @param vector - Vector data (must match dimension)
   */
  add(id: number, vector: number[]): void {
    this.checkDisposed();
    const result = getModule().vcdb_add(this.instanceId, id, vector);
    if (result === -2) {
      throw new Error("Vector already exists");
    }
    if (result !== 0) {
      throw new Error("Failed to add vector");
    }
  }

  /**
   * Upsert a vector (add or update).
   *
   * @param id - Unique vector ID
   * @param vector - Vector data (must match dimension)
   */
  upsert(id: number, vector: number[]): void {
    this.checkDisposed();
    const result = getModule().vcdb_upsert(this.instanceId, id, vector);
    if (result !== 0) {
      throw new Error("Failed to upsert vector");
    }
  }

  /**
   * Get a vector by ID.
   *
   * @param id - Vector ID
   * @returns Vector data or undefined if not found
   */
  get(id: number): number[] | undefined {
    this.checkDisposed();
    const result = getModule().vcdb_get(this.instanceId, id);
    if (result._1 === 1) {
      return result._0;
    }
    return undefined;
  }

  /**
   * Search for k nearest neighbors.
   *
   * @param query - Query vector
   * @param k - Number of results to return
   * @returns Array of search results sorted by score (highest first)
   */
  search(query: number[], k: number): SearchResult[] {
    this.checkDisposed();
    const results = getModule().vcdb_search(this.instanceId, query, k);
    return results.map((r) => ({ id: r._0, score: r._1 }));
  }

  /**
   * Check if a vector exists.
   *
   * @param id - Vector ID
   * @returns true if exists
   */
  has(id: number): boolean {
    this.checkDisposed();
    return getModule().vcdb_has(this.instanceId, id) === 1;
  }

  /**
   * Remove a vector.
   *
   * @param id - Vector ID
   * @returns true if removed, false if not found
   */
  remove(id: number): boolean {
    this.checkDisposed();
    return getModule().vcdb_remove(this.instanceId, id) === 1;
  }

  /**
   * Serialize the database to bytes.
   *
   * @returns Serialized database
   */
  serialize(): Uint8Array {
    this.checkDisposed();
    return getModule().vcdb_serialize(this.instanceId);
  }

  /**
   * Deserialize a database from bytes.
   *
   * @param data - Serialized database
   * @returns New VectorDB instance
   */
  static deserialize(data: Uint8Array): VectorDB {
    const mod = getModule();
    const instanceId = mod.vcdb_deserialize(data);
    const db = Object.create(VectorDB.prototype) as VectorDB;
    db.instanceId = instanceId;
    db.disposed = false;
    return db;
  }

  /**
   * Dispose the database and free resources.
   * The instance cannot be used after calling this.
   */
  dispose(): void {
    if (!this.disposed) {
      getModule().vcdb_destroy(this.instanceId);
      this.disposed = true;
    }
  }
}
