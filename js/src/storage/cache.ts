/**
 * @file Cache API-backed FileIO implementation
 * For Service Worker environments and offline-first scenarios.
 */
import type { FileIO } from "./types.js";
import { toUint8 } from "./types.js";

export interface CacheStorageFileIOOptions {
  /** Cache name for namespacing */
  cacheName: string;
  /** URL prefix for cache entries (e.g., "https://vcdb.local") */
  urlPrefix: string;
}

/**
 * Create a FileIO implementation using the Cache API.
 * Designed for Service Worker environments and enables offline-first scenarios.
 */
export function createCacheStorageFileIO(
  options: CacheStorageFileIOOptions
): FileIO {
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

  const pathToUrl = (path: string): string => {
    if (path.includes("..") || path.includes("//")) {
      throw new Error(`Invalid path: ${path}`);
    }
    return `${urlPrefix}/${cacheName}/${path}`;
  };

  return {
    async read(path: string): Promise<Uint8Array> {
      const cache = await getCache();
      const url = pathToUrl(path);
      const response = await cache.match(url);

      if (!response) {
        throw new Error(`File not found: ${path}`);
      }

      const arrayBuffer = await response.arrayBuffer();
      return new Uint8Array(arrayBuffer);
    },

    async write(
      path: string,
      data: Uint8Array | ArrayBuffer
    ): Promise<void> {
      const cache = await getCache();
      const url = pathToUrl(path);
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

    async append(
      path: string,
      data: Uint8Array | ArrayBuffer
    ): Promise<void> {
      const cache = await getCache();
      const url = pathToUrl(path);

      const existingResponse = await cache.match(url);
      const existingData = existingResponse
        ? new Uint8Array(await existingResponse.arrayBuffer())
        : new Uint8Array(0);

      const newData = toUint8(data);
      const combined = new Uint8Array(existingData.length + newData.length);
      combined.set(existingData);
      combined.set(newData, existingData.length);

      await this.write(path, combined);
    },

    async atomicWrite(
      path: string,
      data: Uint8Array | ArrayBuffer
    ): Promise<void> {
      await this.write(path, data);
    },

    async del(path: string): Promise<void> {
      const cache = await getCache();
      const url = pathToUrl(path);
      const deleted = await cache.delete(url);

      if (!deleted) {
        throw new Error(`File not found: ${path}`);
      }
    },
  };
}
