/**
 * @file Node.js filesystem storage adapter
 * Persistent storage using the local filesystem with StorageKind routing.
 */
import { readFile, mkdir, rm, open, readdir, stat } from "node:fs/promises";
import { dirname, join as joinPath } from "node:path";
import type { StorageAdapter, StorageKindType } from "./types.js";
import { StorageKind, toUint8 } from "./types.js";

type FileSystemError = Error & { code?: string };

function isFileNotFoundError(error: unknown): boolean {
  if (!(error instanceof Error)) return false;
  return (error as FileSystemError).code === "ENOENT";
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

export interface NodeStorageOptions {
  /** Base directory for all file operations */
  baseDir: string;
}

/** Create a Node.js filesystem StorageAdapter instance */
export function createNodeStorage(options: NodeStorageOptions): StorageAdapter {
  const { baseDir } = options;

  const getFullPath = (filePath: string, kind: StorageKindType): string =>
    joinPath(baseDir, kindToDir(kind), filePath);

  async function ensureDir(p: string) {
    await mkdir(dirname(p), { recursive: true });
  }

  return {
    async read(filePath: string, kind: StorageKindType): Promise<Uint8Array | null> {
      const full = getFullPath(filePath, kind);
      try {
        const u8 = await readFile(full);
        const out = new Uint8Array(u8.byteLength);
        out.set(u8);
        return out;
      } catch (error) {
        if (isFileNotFoundError(error)) return null;
        throw error;
      }
    },

    async write(filePath: string, data: Uint8Array, kind: StorageKindType): Promise<void> {
      const full = getFullPath(filePath, kind);
      await ensureDir(full);
      const fd = await open(full, "w");
      try {
        await fd.writeFile(toUint8(data));
        await fd.sync();
      } finally {
        await fd.close();
      }
    },

    async delete(filePath: string, kind: StorageKindType): Promise<void> {
      const full = getFullPath(filePath, kind);
      try {
        await rm(full, { force: true });
      } catch (error) {
        if (!isFileNotFoundError(error)) throw error;
      }
    },

    async exists(filePath: string, kind: StorageKindType): Promise<boolean> {
      const full = getFullPath(filePath, kind);
      try {
        await stat(full);
        return true;
      } catch {
        return false;
      }
    },

    async list(kind: StorageKindType, prefix = ""): Promise<string[]> {
      const kindDir = joinPath(baseDir, kindToDir(kind));
      const files: string[] = [];

      async function walk(dir: string, relativePrefix: string) {
        try {
          const entries = await readdir(dir, { withFileTypes: true });
          for (const entry of entries) {
            const relativePath = relativePrefix
              ? `${relativePrefix}/${entry.name}`
              : entry.name;
            if (entry.isDirectory()) {
              await walk(joinPath(dir, entry.name), relativePath);
            } else if (relativePath.startsWith(prefix)) {
              files.push(relativePath);
            }
          }
        } catch (error) {
          if (!isFileNotFoundError(error)) throw error;
        }
      }

      await walk(kindDir, "");
      return files;
    },
  };
}
