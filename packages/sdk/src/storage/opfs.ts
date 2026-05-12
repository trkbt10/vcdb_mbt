/**
 * @file Browser OPFS (Origin Private File System) storage adapter
 * Modern file system access API for high-performance browser storage.
 */
import type { StorageAdapter, StorageKindType } from "./types.js";
import { StorageKind, toUint8 } from "./types.js";

type FileWritable = {
  write(data: Uint8Array): Promise<void>;
  close(): Promise<void>;
};

type FileHandleWritable = {
  createWritable(options?: { keepExistingData?: boolean }): Promise<FileWritable>;
};

type FileHandleReadable = {
  getFile(): Promise<{ arrayBuffer(): Promise<ArrayBuffer> }>;
};

type FileHandle = FileHandleWritable & FileHandleReadable;

type OPFSDirectory = {
  getDirectoryHandle(name: string, opts?: { create?: boolean }): Promise<OPFSDirectory>;
  getFileHandle(name: string, opts?: { create?: boolean }): Promise<FileHandle>;
  removeEntry?(name: string): Promise<void>;
  entries?(): AsyncIterable<[string, FileHandle | OPFSDirectory]>;
};

type NavigatorWithOPFS = {
  storage: { getDirectory(): Promise<OPFSDirectory> };
};

function hasOPFSNavigator(x: unknown): x is NavigatorWithOPFS {
  const storage = (x as Record<string, unknown> | undefined)?.storage;
  if (!storage) return false;
  const getDir = (storage as { getDirectory?: unknown }).getDirectory;
  return typeof getDir === "function";
}

function requireRoot(): Promise<OPFSDirectory> {
  const nav: unknown = (globalThis as { navigator?: unknown }).navigator;
  if (!hasOPFSNavigator(nav)) {
    throw new Error("OPFS not available in this environment");
  }
  return (nav as NavigatorWithOPFS).storage.getDirectory();
}

function kindToDir(kind: StorageKindType): string {
  switch (kind) {
    case StorageKind.Config:
      return "config";
    case StorageKind.Index:
      return "index";
    case StorageKind.Data:
      return "data";
    default:
      return "data";
  }
}

/** Create an OPFS StorageAdapter */
export function createOPFSStorage(): StorageAdapter {
  async function getKindDir(kind: StorageKindType): Promise<OPFSDirectory> {
    const root = await requireRoot();
    return root.getDirectoryHandle(kindToDir(kind), { create: true });
  }

  return {
    async read(path: string, kind: StorageKindType): Promise<Uint8Array | null> {
      try {
        const dir = await getKindDir(kind);
        const fh = await dir.getFileHandle(path);
        const file = await fh.getFile();
        return new Uint8Array(await file.arrayBuffer());
      } catch {
        return null;
      }
    },

    async write(path: string, data: Uint8Array, kind: StorageKindType): Promise<void> {
      const dir = await getKindDir(kind);
      const fh = await dir.getFileHandle(path, { create: true });
      const w = await fh.createWritable({ keepExistingData: false });
      await w.write(toUint8(data));
      await w.close();
    },

    async delete(path: string, kind: StorageKindType): Promise<void> {
      const dir = await getKindDir(kind);
      if (dir.removeEntry) {
        try {
          await dir.removeEntry(path);
        } catch {
          // ignore not found
        }
      }
    },

    async exists(path: string, kind: StorageKindType): Promise<boolean> {
      try {
        const dir = await getKindDir(kind);
        await dir.getFileHandle(path);
        return true;
      } catch {
        return false;
      }
    },

    async list(kind: StorageKindType, prefix = ""): Promise<string[]> {
      const dir = await getKindDir(kind);
      const files: string[] = [];
      if (dir.entries) {
        for await (const [name] of dir.entries()) {
          if (name.startsWith(prefix)) {
            files.push(name);
          }
        }
      }
      return files;
    },
  };
}
