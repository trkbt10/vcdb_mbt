/**
 * @file Key-value storage adapter backed by Cloudflare R2.
 *
 * Same DOKeyValueStore interface as the DO adapter from @vcdb/server.
 * No chunking needed — R2 supports objects up to 5GB.
 * No write coalescing — R2 operations are individually atomic.
 *
 * Optional keyPrefix isolates each DO shard's data in the shared bucket.
 */
import type { DOKeyValueStore } from "@vcdb/server/storage/do-kv";

export function createR2Adapter(
  bucket: R2Bucket,
  keyPrefix: string = "",
): DOKeyValueStore {
  const key = (path: string): string => keyPrefix + path;

  return {
    async prefetch() {
      // R2 doesn't need prefetch — no chunk index to maintain
    },

    async read(path) {
      const obj = await bucket.get(key(path));
      if (!obj) return null;
      const buf = await obj.arrayBuffer();
      return new Uint8Array(buf);
    },

    async write(path, data) {
      await bucket.put(key(path), data);
    },

    async writeAtomic(entries) {
      for (const { path, data } of entries) {
        await bucket.put(key(path), data);
      }
    },

    async delete(path) {
      await bucket.delete(key(path));
    },

    async exists(path) {
      const head = await bucket.head(key(path));
      return head !== null;
    },

    async list(prefix) {
      const fullPrefix = keyPrefix + (prefix ?? "");
      const listed = await bucket.list(
        fullPrefix ? { prefix: fullPrefix } : undefined,
      );
      return listed.objects.map((obj) => obj.key.slice(keyPrefix.length));
    },
  };
}
