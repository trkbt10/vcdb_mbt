/**
 * @vcdb/server - Vector database server package
 *
 * For storage backends, use subpath imports to enable tree-shaking:
 *
 * - `@vcdb/server/storage/memory` - In-memory storage
 * - `@vcdb/server/storage/node` - Node.js filesystem
 * - `@vcdb/server/storage/indexeddb` - Browser IndexedDB
 * - `@vcdb/server/storage/opfs` - Browser OPFS
 * - `@vcdb/server/storage/local-storage` - Browser localStorage
 * - `@vcdb/server/storage/cache` - Browser Cache API
 * - `@vcdb/server/storage/r2` - Cloudflare R2
 * - `@vcdb/server/storage/do-kv` - Cloudflare Durable Object storage
 * - `@vcdb/server/wasm` - MoonBit WASM VectorDB
 */

// Only export types from the main entry point
export {
  StorageKind,
  type StorageAdapter,
  type StorageKindType,
  toUint8,
} from "./storage/types.js";
