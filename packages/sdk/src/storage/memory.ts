/**
 * @file In-memory storage implementation
 * Lightweight backend for tests, demos, and ephemeral data.
 */
import type { StorageAdapter, StorageKindType } from "./types.js";
import { toUint8 } from "./types.js";

export interface MemoryStorageOptions {
  /** Initial files to populate (keyed by "kind:path") */
  initial?: Map<string, Uint8Array>;
}

/** Create an in-memory StorageAdapter instance */
export function createMemoryStorage(options?: MemoryStorageOptions): StorageAdapter {
  const store = new Map<string, Uint8Array>(options?.initial);

  const makeKey = (path: string, kind: StorageKindType): string => `${kind}:${path}`;

  return {
    async read(path: string, kind: StorageKindType): Promise<Uint8Array | null> {
      const v = store.get(makeKey(path, kind));
      return v ? new Uint8Array(v) : null;
    },

    async write(path: string, data: Uint8Array, kind: StorageKindType): Promise<void> {
      store.set(makeKey(path, kind), toUint8(data));
    },

    async delete(path: string, kind: StorageKindType): Promise<void> {
      store.delete(makeKey(path, kind));
    },

    async exists(path: string, kind: StorageKindType): Promise<boolean> {
      return store.has(makeKey(path, kind));
    },

    async list(kind: StorageKindType, prefix = ""): Promise<string[]> {
      const kindPrefix = `${kind}:`;
      const results: string[] = [];
      for (const key of store.keys()) {
        if (key.startsWith(kindPrefix)) {
          const path = key.slice(kindPrefix.length);
          if (path.startsWith(prefix)) {
            results.push(path);
          }
        }
      }
      return results;
    },
  };
}
