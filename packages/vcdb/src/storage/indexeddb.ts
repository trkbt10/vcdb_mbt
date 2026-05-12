/**
 * @file IndexedDB storage adapter for browsers
 * Persistent key-value storage using the IndexedDB API with StorageKind routing.
 */
import type { StorageAdapter, StorageKindType } from "./types.js";
import { toUint8 } from "./types.js";
import { kindToPathPrefix } from "./_kinds.js";

type IDBReq<T> = IDBRequest<T>;

function requireIDB(): IDBFactory {
  const idb = (globalThis as unknown as { indexedDB?: IDBFactory }).indexedDB;
  if (!idb) {
    throw new Error("indexedDB not available");
  }
  return idb;
}

function openDB(dbName: string, storeName: string): Promise<IDBDatabase> {
  const idb = requireIDB();
  return new Promise((resolve, reject) => {
    const req = idb.open(dbName, 1);
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains(storeName)) {
        db.createObjectStore(storeName);
      }
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

function tx(db: IDBDatabase, store: string, mode: IDBTransactionMode) {
  const t = db.transaction(store, mode);
  return t.objectStore(store);
}

function reqToPromise<T>(req: IDBReq<T>): Promise<T> {
  return new Promise((resolve, reject) => {
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

export interface IndexedDBStorageOptions {
  /** Database name (default: "vcdb") */
  dbName?: string;
  /** Object store name (default: "files") */
  storeName?: string;
}

/** Create an IndexedDB StorageAdapter instance */
export function createIndexedDBStorage(options?: IndexedDBStorageOptions): StorageAdapter {
  const dbName = options?.dbName ?? "vcdb";
  const storeName = options?.storeName ?? "files";
  const state: { promise: Promise<IDBDatabase> | null } = { promise: null };

  function getDB() {
    if (!state.promise) {
      state.promise = openDB(dbName, storeName);
    }
    return state.promise;
  }

  const makeKey = (path: string, kind: StorageKindType): string =>
    kindToPathPrefix(kind) + path;

  return {
    async read(path: string, kind: StorageKindType): Promise<Uint8Array | null> {
      const db = await getDB();
      const key = makeKey(path, kind);
      const res = await reqToPromise<ArrayBuffer | undefined>(
        tx(db, storeName, "readonly").get(key) as IDBReq<ArrayBuffer | undefined>
      );
      return res != null ? new Uint8Array(res) : null;
    },

    async write(path: string, data: Uint8Array, kind: StorageKindType): Promise<void> {
      const db = await getDB();
      const key = makeKey(path, kind);
      await reqToPromise(
        tx(db, storeName, "readwrite").put(toUint8(data).buffer, key)
      );
    },

    async delete(path: string, kind: StorageKindType): Promise<void> {
      const db = await getDB();
      const key = makeKey(path, kind);
      await reqToPromise(tx(db, storeName, "readwrite").delete(key));
    },

    async exists(path: string, kind: StorageKindType): Promise<boolean> {
      const db = await getDB();
      const key = makeKey(path, kind);
      const res = await reqToPromise<ArrayBuffer | undefined>(
        tx(db, storeName, "readonly").get(key) as IDBReq<ArrayBuffer | undefined>
      );
      return res != null;
    },

    async list(kind: StorageKindType, prefix = ""): Promise<string[]> {
      const db = await getDB();
      const kindPrefix = kindToPathPrefix(kind);
      const fullPrefix = kindPrefix + prefix;
      const store = tx(db, storeName, "readonly");

      return new Promise((resolve, reject) => {
        const files: string[] = [];
        const req = store.openCursor();

        req.onsuccess = () => {
          const cursor = req.result;
          if (cursor) {
            const key = cursor.key as string;
            if (key.startsWith(fullPrefix)) {
              files.push(key.slice(kindPrefix.length));
            }
            cursor.continue();
          } else {
            resolve(files);
          }
        };
        req.onerror = () => reject(req.error);
      });
    },
  };
}
