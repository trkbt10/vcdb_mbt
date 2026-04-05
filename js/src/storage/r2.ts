/**
 * @file Cloudflare R2 storage adapter for vcdb.
 *
 * Implements StorageAdapter using Cloudflare R2 buckets.
 * R2 supports objects up to 5GB — no chunking needed.
 *
 * Each StorageKind is isolated by key prefix (config/, index/, data/).
 *
 * Usage:
 *   import { createR2Storage } from "@vcdb/server/storage/r2";
 *   const adapter = createR2Storage({ bucket: env.VCDB_BUCKET });
 */
import type { StorageAdapter, StorageKindType } from "./types.js";
import { StorageKind } from "./types.js";

/**
 * Minimal R2 bucket interface — matches Cloudflare Workers R2Bucket type
 * without requiring @cloudflare/workers-types as a dependency.
 */
export interface R2BucketLike {
  get(key: string): Promise<{ arrayBuffer(): Promise<ArrayBuffer> } | null>;
  put(key: string, value: ArrayBuffer | Uint8Array | string): Promise<unknown>;
  delete(key: string | string[]): Promise<void>;
  head(key: string): Promise<object | null>;
  list(options?: {
    prefix?: string;
    cursor?: string;
    limit?: number;
  }): Promise<{
    objects: Array<{ key: string }>;
    truncated: boolean;
    cursor?: string;
  }>;
}

export interface R2StorageOptions {
  /** R2 bucket binding (env.MY_BUCKET). */
  bucket: R2BucketLike;
  /**
   * Optional key prefix for multi-tenant isolation.
   * All keys are stored under `${prefix}${kindDir}/${path}`.
   */
  prefix?: string;
}

const kindDir = (kind: StorageKindType): string => {
  switch (kind) {
    case StorageKind.Config:
      return "config";
    case StorageKind.Index:
      return "index";
    case StorageKind.Data:
      return "data";
  }
};

const makeKey = (prefix: string, path: string, kind: StorageKindType): string =>
  `${prefix}${kindDir(kind)}/${path}`;

export function createR2Storage(options: R2StorageOptions): StorageAdapter {
  const { bucket, prefix = "" } = options;

  return {
    async read(path, kind) {
      const obj = await bucket.get(makeKey(prefix, path, kind));
      if (!obj) return null;
      const buf = await obj.arrayBuffer();
      return new Uint8Array(buf);
    },

    async write(path, data, kind) {
      await bucket.put(makeKey(prefix, path, kind), data);
    },

    async delete(path, kind) {
      await bucket.delete(makeKey(prefix, path, kind));
    },

    async exists(path, kind) {
      const head = await bucket.head(makeKey(prefix, path, kind));
      return head !== null;
    },

    async list(kind, subPrefix) {
      const fullPrefix = makeKey(prefix, subPrefix ?? "", kind);
      const baseLen = `${prefix}${kindDir(kind)}/`.length;
      const keys: string[] = [];

      let cursor: string | undefined;
      // R2 list is paginated — exhaust all pages.
      do {
        const page = await bucket.list({
          prefix: fullPrefix,
          cursor,
          limit: 1000,
        });
        for (const obj of page.objects) {
          keys.push(obj.key.slice(baseLen));
        }
        cursor = page.truncated ? page.cursor : undefined;
      } while (cursor);

      return keys;
    },
  };
}
