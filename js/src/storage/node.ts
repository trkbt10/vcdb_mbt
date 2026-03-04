/**
 * @file Node.js file system storage adapter
 * Persistent storage using the local filesystem.
 */
import { readFile, rename, mkdir, rm, open } from "node:fs/promises";
import { dirname, join as joinPath } from "node:path";
import type { FileIO } from "./types.js";
import { toUint8 } from "./types.js";

type FileSystemError = Error & { code?: string };

function isRetryableError(error: unknown): boolean {
  if (!(error instanceof Error)) return false;
  const fsError = error as FileSystemError;
  return (
    fsError.code === "EBUSY" ||
    fsError.code === "EMFILE" ||
    fsError.code === "ENFILE"
  );
}

function isFileNotFoundError(error: unknown): boolean {
  if (!(error instanceof Error)) return false;
  const fsError = error as FileSystemError;
  return fsError.code === "ENOENT";
}

async function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function retryOperation<T>(
  operation: () => Promise<T>,
  maxRetries = 3,
  baseDelay = 100
): Promise<T> {
  let lastError: unknown;

  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      return await operation();
    } catch (error) {
      lastError = error;

      if (attempt === maxRetries || !isRetryableError(error)) {
        throw error;
      }

      const delay = baseDelay * Math.pow(2, attempt) + Math.random() * 50;
      await sleep(delay);
    }
  }

  throw lastError;
}

async function writeToTempFile(
  tmpPath: string,
  data: ArrayBuffer | Uint8Array
): Promise<void> {
  const fd = await open(tmpPath, "w");
  try {
    await fd.writeFile(toUint8(data));
    await fd.sync();
  } finally {
    await fd.close();
  }
}

async function syncParentDirectory(filePath: string): Promise<void> {
  try {
    const dirFd = await open(dirname(filePath), "r");
    try {
      await dirFd.sync();
    } finally {
      await dirFd.close();
    }
  } catch {
    // ignore directory fsync errors
  }
}

async function safeDelete(
  filePath: string,
  options: { silent?: boolean } = {}
): Promise<void> {
  try {
    await rm(filePath, { force: true });
  } catch (error) {
    if (isFileNotFoundError(error)) return;
    if (options.silent) {
      console.warn(`Failed to delete file ${filePath}:`, error);
      return;
    }
    throw error;
  }
}

async function cleanupTempFile(tmpPath: string): Promise<void> {
  await safeDelete(tmpPath, { silent: true });
}

export interface NodeFileIOOptions {
  /** Base directory for all file operations */
  baseDir: string;
}

/** Create a Node.js filesystem FileIO instance */
export function createNodeFileIO(options: NodeFileIOOptions): FileIO {
  const { baseDir } = options;

  async function ensureDir(p: string) {
    await mkdir(dirname(p), { recursive: true });
  }

  return {
    async read(path: string): Promise<Uint8Array> {
      const full = joinPath(baseDir, path);
      const u8 = await readFile(full);
      const out = new Uint8Array(u8.byteLength);
      out.set(u8);
      return out;
    },

    async write(
      path: string,
      data: Uint8Array | ArrayBuffer
    ): Promise<void> {
      const full = joinPath(baseDir, path);
      await ensureDir(full);
      const fd = await open(full, "w");
      try {
        await fd.writeFile(toUint8(data));
        await fd.sync();
      } finally {
        await fd.close();
      }
    },

    async append(
      path: string,
      data: Uint8Array | ArrayBuffer
    ): Promise<void> {
      const full = joinPath(baseDir, path);
      await ensureDir(full);
      const fd = await open(full, "a");
      try {
        await fd.writeFile(toUint8(data));
        await fd.sync();
      } finally {
        await fd.close();
      }
    },

    async atomicWrite(
      path: string,
      data: Uint8Array | ArrayBuffer
    ): Promise<void> {
      const full = joinPath(baseDir, path);
      await ensureDir(full);
      const tmp = `${full}.tmp`;

      try {
        await writeToTempFile(tmp, data);
        await retryOperation(() => rename(tmp, full));
        await syncParentDirectory(full);
      } catch (error) {
        await cleanupTempFile(tmp);
        throw error;
      }
    },

    async del(path: string): Promise<void> {
      const full = joinPath(baseDir, path);
      await safeDelete(full);
    },
  };
}
