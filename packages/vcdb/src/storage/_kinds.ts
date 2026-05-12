/**
 * @file Storage-kind → namespace conventions shared between backends that
 * use the same key/path scheme.
 *
 * indexeddb and service-worker (Cache API) both key items by a flat
 * `<kind>/...` path. local-storage uses a colon-delimited
 * `vcdb:<kind>:...` namespace; the filesystem backend (node) uses bare
 * directory names. Those two have their own helpers — only the
 * shared "<kind>/" convention lives here.
 */

import { StorageKind, type StorageKindType } from "./types.js";

/** "config/" | "index/" | "data/". Used by IndexedDB and the Cache API. */
export function kindToPathPrefix(kind: StorageKindType): string {
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
