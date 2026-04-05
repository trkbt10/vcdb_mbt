/**
 * @file Shared types for the Cloudflare DO example.
 */
import type { VcdbStore } from "./infra/vcdb-do.ts";

/* ─── Cloudflare Bindings ────────────── */

export type Bindings = {
  /** R2 bucket for vcdb snapshot storage. */
  VCDB_DATA: R2Bucket;
  /** Durable Object namespace for vcdb shards. */
  VCDB_STORE: DurableObjectNamespace<VcdbStore>;
};

/* ─── ID types & conversion ────────────── */

/**
 * VectorId as hi/lo pair — the only ID representation used across vcdb FFI.
 * Matches MoonBit's Int64 {hi, lo} encoding on the JS target.
 */
export type VcdbId = { readonly hi: number; readonly lo: number };

/** Split a JS number into hi/lo i32 pair (matching MoonBit's vid_from_pair). */
export const numericToId = (n: number): VcdbId => ({
  hi: (n / 0x100000000) | 0,
  lo: n | 0,
});

/** Reconstruct a JS number from hi/lo pair (for shard routing etc). */
export const idToNumeric = (id: VcdbId): number =>
  (id.hi >>> 0) * 0x100000000 + (id.lo >>> 0);

/** Convert a hex string to a VcdbId (first 13 hex chars → 52-bit). */
export const stringToId = (id: string): VcdbId =>
  numericToId(parseInt(id.slice(0, 13), 16));

/** Deterministic VcdbId for a well-known string key via FNV-1a. */
export const wellKnownToId = (key: string): VcdbId => {
  const h = { value: 0x811c9dc5 };
  for (const byte of new TextEncoder().encode(key)) {
    h.value ^= byte;
    h.value = Math.imul(h.value, 0x01000193) | 0;
  }
  return numericToId(h.value >>> 0);
};

/* ─── Point types ────────────────────── */

export type VcdbPoint = {
  readonly id: VcdbId;
  readonly vector: number[];
  readonly payload: Record<string, unknown>;
};

export type VcdbHit = {
  readonly id: VcdbId;
  readonly score: number;
  readonly payload: Record<string, unknown> | null;
};
