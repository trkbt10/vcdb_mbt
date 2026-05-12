/**
 * @file Browser localStorage/sessionStorage adapter
 * String-based storage using base64 encoding for binary data.
 */
import type { StorageAdapter, StorageKindType } from "./types.js";
import { StorageKind, toUint8 } from "./types.js";

function requireStorage(kind: "localStorage" | "sessionStorage"): Storage {
  const g = globalThis as unknown as { [k: string]: unknown };
  const s = g[kind] as Storage | undefined;
  if (!s || typeof s.getItem !== "function") {
    throw new Error(`${kind} not available`);
  }
  return s;
}

function encodeBase64(u8: Uint8Array): string {
  const binary = Array.from(u8, (v) => String.fromCharCode(v)).join("");
  return btoa(binary);
}

function decodeBase64(s: string): Uint8Array {
  const bin = atob(s);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) {
    out[i] = bin.charCodeAt(i) & 0xff;
  }
  return out;
}

function kindToPrefix(kind: StorageKindType): string {
  switch (kind) {
    case StorageKind.Config:
      return "vcdb:config:";
    case StorageKind.Index:
      return "vcdb:index:";
    case StorageKind.Data:
      return "vcdb:data:";
    default:
      return "vcdb:data:";
  }
}

function createWebStorageAdapter(storage: Storage): StorageAdapter {
  const makeKey = (path: string, kind: StorageKindType): string =>
    kindToPrefix(kind) + path;

  return {
    async read(path: string, kind: StorageKindType): Promise<Uint8Array | null> {
      const v = storage.getItem(makeKey(path, kind));
      return v != null ? decodeBase64(v) : null;
    },

    async write(path: string, data: Uint8Array, kind: StorageKindType): Promise<void> {
      storage.setItem(makeKey(path, kind), encodeBase64(toUint8(data)));
    },

    async delete(path: string, kind: StorageKindType): Promise<void> {
      storage.removeItem(makeKey(path, kind));
    },

    async exists(path: string, kind: StorageKindType): Promise<boolean> {
      return storage.getItem(makeKey(path, kind)) != null;
    },

    async list(kind: StorageKindType, prefix = ""): Promise<string[]> {
      const kindPrefix = kindToPrefix(kind);
      const fullPrefix = kindPrefix + prefix;
      const files: string[] = [];
      for (let i = 0; i < storage.length; i++) {
        const key = storage.key(i);
        if (key?.startsWith(fullPrefix)) {
          files.push(key.slice(kindPrefix.length));
        }
      }
      return files;
    },
  };
}

/** Create a StorageAdapter backed by localStorage */
export function createLocalStorage(): StorageAdapter {
  return createWebStorageAdapter(requireStorage("localStorage"));
}

/** Create a StorageAdapter backed by sessionStorage */
export function createSessionStorage(): StorageAdapter {
  return createWebStorageAdapter(requireStorage("sessionStorage"));
}

/** Create a StorageAdapter backed by a provided Storage instance (for testing) */
export function createFromWebStorage(storage: Storage): StorageAdapter {
  return createWebStorageAdapter(storage);
}
