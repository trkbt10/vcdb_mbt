/**
 * @vcdb/server - Vector database server package
 *
 * Subpath imports for tree-shaking:
 *
 * Storage backends:
 *   - `@vcdb/server/storage/memory`
 *   - `@vcdb/server/storage/node`
 *   - `@vcdb/server/storage/indexeddb`
 *   - `@vcdb/server/storage/opfs`
 *   - `@vcdb/server/storage/local-storage`
 *   - `@vcdb/server/storage/service-worker`
 *   - `@vcdb/server/storage/r2`
 *   - `@vcdb/server/storage/do-kv`
 *   - `@vcdb/server/storage/cached`
 *
 * VectorDB:
 *   - `@vcdb/server/vectordb`        — in-memory VectorDB
 *   - `@vcdb/server/persistent`      — persistent VectorDB (WAL)
 *   - `@vcdb/server/gateway`         — HTTP gateway API
 *
 * Cloudflare:
 *   - `@vcdb/server/cloudflare/persistent-do` — DO storage bridge
 *
 * Module loader:
 *   - `@vcdb/server/loader`          — loadModule / isModuleLoaded
 */

// Domain types
export type {
  VectorId,
  Metric,
  Strategy,
  SearchResult,
  SearchHit,
  PointRecord,
  ScrollEntry,
} from "./types.js";

// Storage types
export {
  StorageKind,
  type StorageAdapter,
  type StorageKindType,
  toUint8,
} from "./storage/types.js";
