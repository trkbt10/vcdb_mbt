/**
 * @file File I/O abstraction layer
 * Unified read/write/append/atomic operations across backends.
 */

/**
 * FileIO interface for storage backends.
 * All backends must implement these methods for interoperability.
 */
export interface FileIO {
  /** Read file contents as Uint8Array */
  read(path: string): Promise<Uint8Array>;

  /** Write data to file (overwrites existing) */
  write(path: string, data: Uint8Array | ArrayBuffer): Promise<void>;

  /** Append data to existing file (creates if not exists) */
  append(path: string, data: Uint8Array | ArrayBuffer): Promise<void>;

  /** Atomic write (write-then-rename pattern where supported) */
  atomicWrite(path: string, data: Uint8Array | ArrayBuffer): Promise<void>;

  /** Delete file (optional, may throw if not supported) */
  del?(path: string): Promise<void>;
}

/** Convert ArrayBuffer to Uint8Array (no-copy when possible) */
export function toUint8(data: Uint8Array | ArrayBuffer): Uint8Array {
  return data instanceof Uint8Array ? data : new Uint8Array(data);
}
