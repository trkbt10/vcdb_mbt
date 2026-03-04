/**
 * @file In-memory FileIO implementation
 * Lightweight backend for tests, demos, and ephemeral data.
 */
import type { FileIO } from "./types.js";
import { toUint8 } from "./types.js";

export interface MemoryFileIOOptions {
  /** Initial files to populate */
  initial?: Record<string, Uint8Array | ArrayBuffer>;
}

/** Create an in-memory FileIO instance */
export function createMemoryFileIO(options?: MemoryFileIOOptions): FileIO {
  const store = new Map<string, Uint8Array>();

  if (options?.initial) {
    for (const [k, v] of Object.entries(options.initial)) {
      store.set(k, toUint8(v));
    }
  }

  return {
    async read(path: string): Promise<Uint8Array> {
      const v = store.get(path);
      if (!v) {
        const err = new Error(
          `ENOENT: no such file or directory, open '${path}'`
        ) as Error & { code: string };
        err.code = "ENOENT";
        throw err;
      }
      return new Uint8Array(v);
    },

    async write(path: string, data: Uint8Array | ArrayBuffer): Promise<void> {
      store.set(path, toUint8(data));
    },

    async append(path: string, data: Uint8Array | ArrayBuffer): Promise<void> {
      const prev = store.get(path);
      const next = toUint8(data);
      if (!prev) {
        store.set(path, next);
        return;
      }
      const merged = new Uint8Array(prev.length + next.length);
      merged.set(prev, 0);
      merged.set(next, prev.length);
      store.set(path, merged);
    },

    async atomicWrite(
      path: string,
      data: Uint8Array | ArrayBuffer
    ): Promise<void> {
      store.set(path, toUint8(data));
    },

    async del(path: string): Promise<void> {
      store.delete(path);
    },
  };
}
