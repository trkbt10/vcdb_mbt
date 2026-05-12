/**
 * @file Configuration shapes shared between the dashboard wizard and the
 * gateway's app-config persistence layer.
 */

/**
 * Names are used as both URL path components and persistence keys, so we
 * keep them ASCII-safe and bounded.
 */
export const INDEX_NAME_PATTERN: RegExp = /^[A-Za-z][A-Za-z0-9_-]{0,63}$/;

/**
 * Storage URIs for a collection — the index side (manifests, ANN graph,
 * etc.) and the data side (vector segments / payload). Both accept the
 * scheme set the active backend understands; commonly `file://`, `memory://`,
 * or an HTTP-backed identifier.
 */
export interface RawStorageConfig {
  readonly index: string;
  readonly data: string;
}

/**
 * Raw index/CRUSH parameters (placement groups, shards, replicas, segment
 * controls). The shape mirrors what the gateway accepts under its `index`
 * config slot.
 */
export interface RawIndexConfig {
  readonly pgs?: number;
  readonly shards?: number;
  readonly replicas?: number;
  readonly segmented?: boolean;
  readonly segmentBytes?: number;
}

/** What `getDbConfig` on a connected vcdb collection returns. */
export interface RawAppConfig {
  readonly storage?: string | RawStorageConfig;
  readonly index?: RawIndexConfig;
}
