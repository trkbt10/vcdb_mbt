/**
 * @file Cached storage adapter.
 *
 * Wraps an async StorageAdapter with an in-memory cache.
 * - prefetch(): Load data from storage into cache
 * - flush(): Write dirty entries back to storage
 * - getCallbacks(): Synchronous read/write callbacks (for any sync consumer)
 *
 * This has no dependency on WASM or FFI — it is a pure storage concern.
 */
import type { StorageAdapter, StorageKindType } from "./types.js";
import type { SyncStorageCallbacks } from "../ffi/types.js";
import { StorageKind } from "./types.js";

export interface CachedStorageOptions {
  /** Underlying async storage adapter */
  adapter: StorageAdapter;
  /** Auto-flush interval in ms (0 = disabled) */
  autoFlushInterval?: number;
}

interface CacheEntry {
  data: Uint8Array;
  dirty: boolean;
}

export class CachedStorage {
  private adapter: StorageAdapter;
  private cache = new Map<string, CacheEntry>();
  private deleted = new Set<string>();
  private flushTimer: ReturnType<typeof setInterval> | null = null;
  private flushing = false;

  constructor(options: CachedStorageOptions) {
    this.adapter = options.adapter;

    if (options.autoFlushInterval && options.autoFlushInterval > 0) {
      this.flushTimer = setInterval(() => {
        this.flush().catch(console.error);
      }, options.autoFlushInterval);
    }
  }

  private makeKey(path: string, kind: StorageKindType): string {
    return `${kind}:${path}`;
  }

  private parseKey(key: string): { path: string; kind: StorageKindType } {
    const colonIdx = key.indexOf(":");
    const kind = parseInt(key.slice(0, colonIdx), 10) as StorageKindType;
    const path = key.slice(colonIdx + 1);
    return { path, kind };
  }

  async prefetch(): Promise<void> {
    const kinds: StorageKindType[] = [
      StorageKind.Config,
      StorageKind.Index,
      StorageKind.Data,
    ];

    for (const kind of kinds) {
      const files = await this.adapter.list(kind);
      await Promise.all(
        files.map(async (path) => {
          const data = await this.adapter.read(path, kind);
          if (data) {
            this.cache.set(this.makeKey(path, kind), { data, dirty: false });
          }
        })
      );
    }
  }

  async prefetchPaths(
    paths: Array<{ path: string; kind: StorageKindType }>
  ): Promise<void> {
    await Promise.all(
      paths.map(async ({ path, kind }) => {
        const key = this.makeKey(path, kind);
        if (!this.cache.has(key)) {
          const data = await this.adapter.read(path, kind);
          if (data) {
            this.cache.set(key, { data, dirty: false });
          }
        }
      })
    );
  }

  async flush(): Promise<string[]> {
    if (this.flushing) {
      return [];
    }

    this.flushing = true;
    const failed: string[] = [];

    try {
      const deletePromises = Array.from(this.deleted).map(async (key) => {
        const { path, kind } = this.parseKey(key);
        try {
          await this.adapter.delete(path, kind);
          this.deleted.delete(key);
        } catch (e) {
          console.error(`Failed to delete ${key}:`, e);
          failed.push(key);
        }
      });
      await Promise.all(deletePromises);

      const writePromises: Promise<void>[] = [];
      for (const [key, entry] of this.cache) {
        if (entry.dirty) {
          const { path, kind } = this.parseKey(key);
          writePromises.push(
            this.adapter
              .write(path, entry.data, kind)
              .then(() => {
                entry.dirty = false;
              })
              .catch((e) => {
                console.error(`Failed to write ${key}:`, e);
                failed.push(key);
              })
          );
        }
      }
      await Promise.all(writePromises);
    } finally {
      this.flushing = false;
    }

    return failed;
  }

  async flushOrThrow(): Promise<void> {
    const failed = await this.flush();
    if (failed.length > 0) {
      throw new Error(`Failed to flush: ${failed.join(", ")}`);
    }
  }

  hasDirty(): boolean {
    if (this.deleted.size > 0) return true;
    for (const entry of this.cache.values()) {
      if (entry.dirty) return true;
    }
    return false;
  }

  /**
   * Get synchronous callbacks operating on the in-memory cache.
   *
   * The returned shape matches SyncStorageCallbacks from ffi/types,
   * suitable for passing to gateway registration or any other sync consumer.
   */
  getCallbacks(): SyncStorageCallbacks {
    return {
      read: (path: string, kind: number): Uint8Array => {
        const entry = this.cache.get(this.makeKey(path, kind as StorageKindType));
        return entry?.data ?? new Uint8Array(0);
      },

      write: (path: string, data: Uint8Array, kind: number): void => {
        const key = this.makeKey(path, kind as StorageKindType);
        this.cache.set(key, { data: new Uint8Array(data), dirty: true });
        this.deleted.delete(key);
      },

      exists: (path: string, kind: number): boolean => {
        const key = this.makeKey(path, kind as StorageKindType);
        return this.cache.has(key) && !this.deleted.has(key);
      },

      del: (path: string, kind: number): void => {
        const key = this.makeKey(path, kind as StorageKindType);
        if (this.cache.has(key)) {
          this.cache.delete(key);
          this.deleted.add(key);
        }
      },

      list: (kind: number): string[] => {
        const prefix = `${kind}:`;
        const results: string[] = [];
        for (const key of this.cache.keys()) {
          if (key.startsWith(prefix) && !this.deleted.has(key)) {
            results.push(key.slice(prefix.length));
          }
        }
        return results;
      },
    };
  }

  async close(): Promise<void> {
    if (this.flushTimer) {
      clearInterval(this.flushTimer);
      this.flushTimer = null;
    }
    await this.flushOrThrow();
  }

  clear(): void {
    this.cache.clear();
    this.deleted.clear();
  }
}
