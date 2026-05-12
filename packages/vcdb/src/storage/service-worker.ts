/**
 * @file Cache API storage adapter
 * For Service Worker environments and offline-first scenarios.
 */
import type { StorageAdapter, StorageKindType } from "./types.js";
import { StorageKind, toUint8 } from "./types.js";

function kindToPrefix(kind: StorageKindType): string {
  switch (kind) {
    case StorageKind.Config:
      return "config/";
    case StorageKind.Index:
      return "index/";
    case StorageKind.Data:
      return "data/";
    default:
      return "data/";
  }
}

export interface CacheStorageOptions {
  /** Cache name for namespacing */
  cacheName: string;
  /** URL prefix for cache entries (e.g., "https://vcdb.local") */
  urlPrefix: string;
}

/** Create a Cache API StorageAdapter */
export function createCacheStorage(options: CacheStorageOptions): StorageAdapter {
  const { cacheName, urlPrefix } = options;

  if (!cacheName) {
    throw new Error("cacheName is required");
  }

  if (!urlPrefix) {
    throw new Error("urlPrefix is required");
  }

  if (typeof caches === "undefined") {
    throw new Error("Cache API is not available in this environment");
  }

  const getCache = () => caches.open(cacheName);

  const pathToUrl = (path: string, kind: StorageKindType): string => {
    if (path.includes("..") || path.includes("//")) {
      throw new Error(`Invalid path: ${path}`);
    }
    return `${urlPrefix}/${cacheName}/${kindToPrefix(kind)}${path}`;
  };

  return {
    async read(path: string, kind: StorageKindType): Promise<Uint8Array | null> {
      const cache = await getCache();
      const url = pathToUrl(path, kind);
      const response = await cache.match(url);

      if (!response) {
        return null;
      }

      const arrayBuffer = await response.arrayBuffer();
      return new Uint8Array(arrayBuffer);
    },

    async write(path: string, data: Uint8Array, kind: StorageKindType): Promise<void> {
      const cache = await getCache();
      const url = pathToUrl(path, kind);
      const uint8 = toUint8(data);

      const buf = new ArrayBuffer(uint8.byteLength);
      new Uint8Array(buf).set(uint8);
      const response = new Response(new Blob([buf]), {
        headers: {
          "Content-Type": "application/octet-stream",
          "Content-Length": String(uint8.length),
        },
      });

      await cache.put(url, response);
    },

    async delete(path: string, kind: StorageKindType): Promise<void> {
      const cache = await getCache();
      const url = pathToUrl(path, kind);
      await cache.delete(url);
    },

    async exists(path: string, kind: StorageKindType): Promise<boolean> {
      const cache = await getCache();
      const url = pathToUrl(path, kind);
      const response = await cache.match(url);
      return response != null;
    },

    async list(kind: StorageKindType, prefix = ""): Promise<string[]> {
      const cache = await getCache();
      const keys = await cache.keys();
      const kindPrefix = kindToPrefix(kind);
      const baseUrl = `${urlPrefix}/${cacheName}/${kindPrefix}`;
      const fullPrefix = baseUrl + prefix;

      const files: string[] = [];
      for (const req of keys) {
        if (req.url.startsWith(fullPrefix)) {
          files.push(req.url.slice(baseUrl.length));
        }
      }
      return files;
    },
  };
}
