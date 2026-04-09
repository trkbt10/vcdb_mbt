/**
 * @file vcdb — public API entry point.
 *
 * Exports the core database classes, domain types, and storage utilities.
 * Internal FFI details (wire format, loader, WASM module) are not exposed.
 */

/* ── Domain types ───────────────────────────────────────────── */

export type {
  VectorId,
  Metric,
  Strategy,
  SearchResult,
  SearchHit,
  PointRecord,
  ScrollEntry,
} from "./types.js";

/* ── Module loader ──────────────────────────────────────────── */

export { loadModule, isModuleLoaded } from "./ffi/loader.js";

/* ── Database classes ───────────────────────────────────────── */

export {
  VectorDB,
  PersistentDB,
  kvStoreToCallbacks,
  storageToCallbacks,
} from "./db.js";
export type {
  PersistentDBOptions,
  KeyValueStore,
} from "./db.js";

/* ── Storage types ──────────────────────────────────────────── */

export type { AsyncStorageCallbacks } from "./ffi/types.js";
export type {
  StorageAdapter,
  StorageKind,
  StorageKindType,
} from "./storage/types.js";
