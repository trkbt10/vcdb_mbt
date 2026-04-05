/**
 * @file Shared types for the Cloudflare DO example.
 *
 * VcdbId type and numeric conversions come from @vcdb/server/id
 * (mirrors MoonBit's vid_from_pair / vid_to_pair).
 *
 * Application-specific ID strategies (FNV-1a hash, hex parsing)
 * are defined here — they are NOT part of vcdb's responsibility.
 */
import type { VcdbStore } from "./infra/vcdb-do.ts";

// Re-export FFI boundary types from core.
export { type VcdbId, numericToId, idToNumeric } from "@vcdb/server/id";

/* ─── Application-specific ID utilities ────────────── */

/**
 * Derive a stable u32 from a string via FNV-1a hash.
 * Used to create persistent_* instance IDs from DO IDs.
 */
export const fnvHash = (key: string): number => {
  let h = 0x811c9dc5;
  for (const byte of new TextEncoder().encode(key)) {
    h ^= byte;
    h = Math.imul(h, 0x01000193) | 0;
  }
  return h >>> 0;
};

/* ─── Cloudflare Bindings ────────────── */

export type Bindings = {
  /** R2 bucket for vcdb snapshot storage. */
  VCDB_DATA: R2Bucket;
  /** Durable Object namespace for vcdb shards. */
  VCDB_STORE: DurableObjectNamespace<VcdbStore>;
};

/* ─── Point types ────────────────────── */

export type VcdbPoint = {
  readonly id: { readonly hi: number; readonly lo: number };
  readonly vector: number[];
  readonly payload: Record<string, unknown>;
};

export type VcdbHit = {
  readonly id: { readonly hi: number; readonly lo: number };
  readonly score: number;
  readonly payload: Record<string, unknown> | null;
};
