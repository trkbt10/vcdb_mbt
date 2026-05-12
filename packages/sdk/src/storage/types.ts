/**
 * @file Unified storage abstraction
 *
 * StorageAdapter is the single interface for all storage backends.
 * Supports StorageKind routing for separating config/index/data.
 */

/**
 * Storage kind - tells app what type of data is being stored.
 * App uses this to route to appropriate backend (e.g., index→DynamoDB, data→S3)
 */
export const StorageKind = {
  Config: 0, // Collection configuration (.config.json)
  Index: 1, // Index structures, manifests (.index, .manifest.json)
  Data: 2, // Vector data, segments (.data.bin, segment files)
} as const;

export type StorageKindType = (typeof StorageKind)[keyof typeof StorageKind];

/**
 * Unified storage interface for all backends.
 * All methods are async to support remote storage (S3, etc.).
 */
export interface StorageAdapter {
  /** Read file contents. Returns null if not found. */
  read(path: string, kind: StorageKindType): Promise<Uint8Array | null>;

  /** Write data to file (overwrites existing) */
  write(path: string, data: Uint8Array, kind: StorageKindType): Promise<void>;

  /** Delete file */
  delete(path: string, kind: StorageKindType): Promise<void>;

  /** Check if file exists */
  exists(path: string, kind: StorageKindType): Promise<boolean>;

  /** List all files for a given kind */
  list(kind: StorageKindType, prefix?: string): Promise<string[]>;
}

/** Convert ArrayBuffer to Uint8Array (no-copy when possible) */
export function toUint8(data: Uint8Array | ArrayBuffer): Uint8Array {
  return data instanceof Uint8Array ? data : new Uint8Array(data);
}
