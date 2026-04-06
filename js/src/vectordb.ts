/**
 * @file In-memory VectorDB class.
 *
 * High-level wrapper over VectorDbFfi. Uses bigint VectorId.
 * No dependency on Gateway, Persistent, or storage concepts.
 */
import type { VectorDbFfi } from "./ffi/types.js";
import type { VectorId, Strategy, SearchResult } from "./types.js";
import { getVectorDbFfi } from "./ffi/loader.js";
import { toHiLo, fromHiLo } from "./ffi/vector-id.js";

export class VectorDB {
  private instanceId: number;
  private disposed = false;

  constructor(dim: number, strategy: Strategy = "bruteforce") {
    const ffi = getVectorDbFfi();
    switch (strategy) {
      case "hnsw":
        this.instanceId = ffi.vcdb_create_hnsw(dim);
        break;
      case "ivf":
        this.instanceId = ffi.vcdb_create_ivf(dim);
        break;
      default:
        this.instanceId = ffi.vcdb_create(dim);
    }
  }

  private checkDisposed(): void {
    if (this.disposed) throw new Error("VectorDB instance has been disposed");
  }

  private get ffi(): VectorDbFfi {
    return getVectorDbFfi();
  }

  get size(): number {
    this.checkDisposed();
    return this.ffi.vcdb_size(this.instanceId);
  }

  get dim(): number {
    this.checkDisposed();
    return this.ffi.vcdb_dim(this.instanceId);
  }

  add(id: VectorId, vector: number[]): void {
    this.checkDisposed();
    const { hi, lo } = toHiLo(id);
    const result = this.ffi.vcdb_add(this.instanceId, hi, lo, vector);
    if (result === -2) throw new Error("Vector already exists");
    if (result !== 0) throw new Error("Failed to add vector");
  }

  upsert(id: VectorId, vector: number[]): void {
    this.checkDisposed();
    const { hi, lo } = toHiLo(id);
    const result = this.ffi.vcdb_upsert(this.instanceId, hi, lo, vector);
    if (result !== 0) throw new Error("Failed to upsert vector");
  }

  get(id: VectorId): number[] | undefined {
    this.checkDisposed();
    const { hi, lo } = toHiLo(id);
    const result = this.ffi.vcdb_get(this.instanceId, hi, lo);
    return result._1 === 1 ? result._0 : undefined;
  }

  search(query: number[], k: number): SearchResult[] {
    this.checkDisposed();
    const results = this.ffi.vcdb_search(this.instanceId, query, k);
    return results.map((r) => ({
      id: fromHiLo(r._0, r._1),
      score: r._2,
    }));
  }

  has(id: VectorId): boolean {
    this.checkDisposed();
    const { hi, lo } = toHiLo(id);
    return this.ffi.vcdb_has(this.instanceId, hi, lo) === 1;
  }

  remove(id: VectorId): boolean {
    this.checkDisposed();
    const { hi, lo } = toHiLo(id);
    return this.ffi.vcdb_remove(this.instanceId, hi, lo) === 1;
  }

  serialize(): Uint8Array {
    this.checkDisposed();
    return this.ffi.vcdb_serialize(this.instanceId);
  }

  static deserialize(data: Uint8Array): VectorDB {
    const ffi = getVectorDbFfi();
    const instanceId = ffi.vcdb_deserialize(data);
    const db = Object.create(VectorDB.prototype) as VectorDB;
    db.instanceId = instanceId;
    db.disposed = false;
    return db;
  }

  dispose(): void {
    if (!this.disposed) {
      this.ffi.vcdb_destroy(this.instanceId);
      this.disposed = true;
    }
  }
}
