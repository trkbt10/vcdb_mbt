/**
 * @file Cloudflare Durable Object storage adapter for vcdb.
 *
 * Implements StorageAdapter using Durable Object transactional storage.
 *
 * DO storage has a 128KB per-value limit. Values exceeding this threshold
 * are transparently chunked into 120KB pieces with a metadata key
 * tracking the chunk count. An in-memory chunk index eliminates
 * extra async reads during writes.
 *
 * Concurrency: All write operations use DO write coalescing
 * (no await between storage.delete and storage.put) for atomicity.
 *
 * Usage:
 *   import { createDOStorage } from "@vcdb/server/storage/do-kv";
 *   const adapter = createDOStorage({ storage: ctx.storage });
 */
import type { StorageAdapter, StorageKindType } from "./types.js";
import { StorageKind } from "./types.js";

/**
 * Minimal Durable Object storage interface — matches
 * DurableObjectStorage without requiring @cloudflare/workers-types.
 */
export interface DOStorageLike {
  get<T = unknown>(key: string): Promise<T | undefined>;
  get<T = unknown>(keys: string[]): Promise<Map<string, T>>;
  put(key: string, value: unknown): Promise<void>;
  put(entries: Record<string, unknown>): Promise<void>;
  delete(key: string): Promise<boolean>;
  delete(keys: string[]): Promise<number>;
  list(options?: { prefix?: string }): Promise<Map<string, unknown>>;
}

export interface DOStorageOptions {
  /** Durable Object ctx.storage instance. */
  storage: DOStorageLike;
  /**
   * Optional key prefix for namespace isolation when multiple
   * logical stores share the same DO storage.
   */
  prefix?: string;
}

/* ── Chunking constants ────────────────────────────────────── */

/** Chunk size: comfortably under DO's 128KB per-value limit. */
const CHUNK_SIZE = 120_000;
const CHUNK_SEP = "::chunk::";
const META_SEP = "::meta";

const chunkKey = (base: string, index: number): string =>
  `${base}${CHUNK_SEP}${index}`;

const metaKey = (base: string): string =>
  `${base}${META_SEP}`;

/* ── Kind routing ──────────────────────────────────────────── */

const kindPrefix = (kind: StorageKindType): string => {
  switch (kind) {
    case StorageKind.Config:
      return "c:";
    case StorageKind.Index:
      return "i:";
    case StorageKind.Data:
      return "d:";
  }
};

const makeKey = (prefix: string, path: string, kind: StorageKindType): string =>
  `${prefix}${kindPrefix(kind)}${path}`;

/* ── Internal helpers ──────────────────────────────────────── */

/** Collect old chunk keys for a base key (for deletion before overwrite). */
const oldKeysToDelete = (
  base: string,
  chunkIndex: Map<string, number>,
): string[] => {
  const oldChunks = chunkIndex.get(base);
  if (oldChunks === undefined) return [];
  const keys = [metaKey(base)];
  for (let i = 0; i < oldChunks; i++) {
    keys.push(chunkKey(base, i));
  }
  return keys;
};

/** Write data, chunking if necessary. Returns without awaiting for coalescing. */
const putEntry = (
  storage: DOStorageLike,
  base: string,
  data: Uint8Array,
  chunkIndex: Map<string, number>,
): void => {
  const buf = data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength);

  if (data.length <= CHUNK_SIZE) {
    chunkIndex.delete(base);
    storage.put(base, buf);
    return;
  }

  const numChunks = Math.ceil(data.length / CHUNK_SIZE);
  chunkIndex.set(base, numChunks);
  const entries: Record<string, ArrayBuffer | { chunks: number }> = {};
  for (let i = 0; i < numChunks; i++) {
    const start = i * CHUNK_SIZE;
    const end = Math.min(start + CHUNK_SIZE, data.length);
    const slice = data.slice(start, end);
    entries[chunkKey(base, i)] = slice.buffer.slice(
      slice.byteOffset,
      slice.byteOffset + slice.byteLength,
    );
  }
  entries[metaKey(base)] = { chunks: numChunks };
  storage.put(entries);
};

/** Write data with await (for standalone writes). */
const putEntryAsync = async (
  storage: DOStorageLike,
  base: string,
  data: Uint8Array,
  chunkIndex: Map<string, number>,
): Promise<void> => {
  const buf = data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength);

  if (data.length <= CHUNK_SIZE) {
    chunkIndex.delete(base);
    await storage.put(base, buf);
    return;
  }

  const numChunks = Math.ceil(data.length / CHUNK_SIZE);
  chunkIndex.set(base, numChunks);
  const entries: Record<string, ArrayBuffer | { chunks: number }> = {};
  for (let i = 0; i < numChunks; i++) {
    const start = i * CHUNK_SIZE;
    const end = Math.min(start + CHUNK_SIZE, data.length);
    const slice = data.slice(start, end);
    entries[chunkKey(base, i)] = slice.buffer.slice(
      slice.byteOffset,
      slice.byteOffset + slice.byteLength,
    );
  }
  entries[metaKey(base)] = { chunks: numChunks };
  await storage.put(entries);
};

/** Read a possibly-chunked value. */
const readEntry = async (
  storage: DOStorageLike,
  base: string,
  chunkIndex: Map<string, number>,
): Promise<Uint8Array | null> => {
  const chunks = chunkIndex.get(base);

  if (chunks === undefined) {
    const data = await storage.get<ArrayBuffer>(base);
    if (!data) return null;
    return new Uint8Array(data);
  }

  const keys: string[] = [];
  for (let i = 0; i < chunks; i++) {
    keys.push(chunkKey(base, i));
  }
  const entries = await storage.get<ArrayBuffer>(keys);

  const parts: Uint8Array[] = [];
  for (let i = 0; i < chunks; i++) {
    const chunk = entries.get(chunkKey(base, i));
    if (!chunk) return null;
    parts.push(new Uint8Array(chunk));
  }

  const total = parts.reduce((sum, p) => sum + p.length, 0);
  const result = new Uint8Array(total);
  let offset = 0;
  for (const part of parts) {
    result.set(part, offset);
    offset += part.length;
  }
  return result;
};

/* ── Public API ────────────────────────────────────────────── */

/**
 * Build chunk index by scanning existing metadata keys in storage.
 * Must be called once before read/write operations.
 */
async function prefetchChunkIndex(
  storage: DOStorageLike,
  keyPrefix: string,
  chunkIndex: Map<string, number>,
): Promise<void> {
  const opts = keyPrefix ? { prefix: keyPrefix } : undefined;
  const allKeys = await storage.list(opts);
  for (const [k, v] of allKeys) {
    if (k.endsWith(META_SEP)) {
      const meta = v as { chunks: number } | undefined;
      if (meta && typeof meta.chunks === "number") {
        const base = k.slice(0, k.length - META_SEP.length);
        chunkIndex.set(base, meta.chunks);
      }
    }
  }
}

export function createDOStorage(options: DOStorageOptions): StorageAdapter {
  const { storage, prefix = "" } = options;
  const chunkIndex = new Map<string, number>();
  let prefetched = false;

  const ensurePrefetched = async (): Promise<void> => {
    if (!prefetched) {
      await prefetchChunkIndex(storage, prefix, chunkIndex);
      prefetched = true;
    }
  };

  return {
    async read(path, kind) {
      await ensurePrefetched();
      return readEntry(storage, makeKey(prefix, path, kind), chunkIndex);
    },

    async write(path, data, kind) {
      await ensurePrefetched();
      const k = makeKey(prefix, path, kind);
      const deleteKeys = oldKeysToDelete(k, chunkIndex);
      if (deleteKeys.length > 0) {
        await storage.delete(deleteKeys);
      }
      await putEntryAsync(storage, k, data, chunkIndex);
    },

    async delete(path, kind) {
      await ensurePrefetched();
      const k = makeKey(prefix, path, kind);
      const chunks = chunkIndex.get(k);
      if (chunks !== undefined) {
        const keys = [metaKey(k)];
        for (let i = 0; i < chunks; i++) {
          keys.push(chunkKey(k, i));
        }
        chunkIndex.delete(k);
        await storage.delete(keys);
      } else {
        await storage.delete(k);
      }
    },

    async exists(path, kind) {
      await ensurePrefetched();
      const k = makeKey(prefix, path, kind);
      if (chunkIndex.has(k)) return true;
      const data = await storage.get(k);
      return data !== undefined;
    },

    async list(kind, subPrefix) {
      await ensurePrefetched();
      const kp = kindPrefix(kind);
      const fullPrefix = `${prefix}${kp}${subPrefix ?? ""}`;
      const baseLen = `${prefix}${kp}`.length;
      const opts = fullPrefix ? { prefix: fullPrefix } : undefined;
      const entries = await storage.list(opts);
      const paths = new Set<string>();

      for (const k of entries.keys()) {
        const withoutPrefix = k.slice(baseLen);
        const chunkIdx = withoutPrefix.indexOf(CHUNK_SEP);
        if (chunkIdx >= 0) {
          paths.add(withoutPrefix.slice(0, chunkIdx));
        } else if (withoutPrefix.endsWith(META_SEP)) {
          paths.add(withoutPrefix.slice(0, withoutPrefix.length - META_SEP.length));
        } else {
          paths.add(withoutPrefix);
        }
      }

      return [...paths];
    },
  };
}

/* ── Lower-level utilities for advanced use (WAL writer, etc.) ── */

/**
 * Kind-agnostic key-value store — same interface as usbkr's DOKeyValueStore.
 * For advanced patterns like direct WAL management where StorageKind
 * routing is handled at a higher level.
 */
export type DOKeyValueStore = {
  prefetch(): Promise<void>;
  read(path: string): Promise<Uint8Array | null>;
  write(path: string, data: Uint8Array): Promise<void>;
  writeAtomic(entries: readonly { path: string; data: Uint8Array }[]): Promise<void>;
  delete(path: string): Promise<void>;
  exists(path: string): Promise<boolean>;
  list(prefix?: string): Promise<string[]>;
};

/**
 * Create a kind-agnostic key-value store for advanced use cases.
 *
 * Unlike createDOStorage which routes by StorageKind, this provides
 * raw key-value access with an optional prefix for namespace isolation.
 * Supports atomic batch writes via writeAtomic() using DO write coalescing.
 */
export function createDOKeyValueStore(
  storage: DOStorageLike,
  keyPrefix: string = "",
): DOKeyValueStore {
  const chunkIndex = new Map<string, number>();
  const key = (path: string): string => keyPrefix + path;

  return {
    async prefetch() {
      await prefetchChunkIndex(storage, keyPrefix, chunkIndex);
    },

    async read(path) {
      return readEntry(storage, key(path), chunkIndex);
    },

    async write(path, data) {
      const k = key(path);
      const deleteKeys = oldKeysToDelete(k, chunkIndex);
      if (deleteKeys.length > 0) {
        await storage.delete(deleteKeys);
      }
      await putEntryAsync(storage, k, data, chunkIndex);
    },

    async writeAtomic(entries) {
      const allDeleteKeys: string[] = [];
      for (const { path } of entries) {
        allDeleteKeys.push(...oldKeysToDelete(key(path), chunkIndex));
      }
      if (allDeleteKeys.length > 0) {
        storage.delete(allDeleteKeys);
      }
      for (const { path, data } of entries) {
        putEntry(storage, key(path), data, chunkIndex);
      }
      // Flush: empty put commits all pending puts via write coalescing
      await storage.put({});
    },

    async delete(path) {
      const k = key(path);
      const chunks = chunkIndex.get(k);
      if (chunks !== undefined) {
        const keys = [metaKey(k)];
        for (let i = 0; i < chunks; i++) {
          keys.push(chunkKey(k, i));
        }
        chunkIndex.delete(k);
        await storage.delete(keys);
      } else {
        await storage.delete(k);
      }
    },

    async exists(path) {
      const k = key(path);
      if (chunkIndex.has(k)) return true;
      const data = await storage.get(k);
      return data !== undefined;
    },

    async list(prefix) {
      const fullPrefix = keyPrefix + (prefix ?? "");
      const opts = fullPrefix ? { prefix: fullPrefix } : undefined;
      const entries = await storage.list(opts);
      const paths = new Set<string>();

      for (const k of entries.keys()) {
        const withoutPrefix = k.slice(keyPrefix.length);
        const chunkIdx = withoutPrefix.indexOf(CHUNK_SEP);
        if (chunkIdx >= 0) {
          paths.add(withoutPrefix.slice(0, chunkIdx));
        } else if (withoutPrefix.endsWith(META_SEP)) {
          paths.add(withoutPrefix.slice(0, withoutPrefix.length - META_SEP.length));
        } else {
          paths.add(withoutPrefix);
        }
      }

      return [...paths];
    },
  };
}
