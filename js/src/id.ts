/**
 * @file VcdbId type and FFI boundary conversions.
 *
 * MoonBit's VectorId (Int64) is represented as a {hi, lo} pair of
 * i32 values on the JS target. This module provides the canonical
 * JS type and conversion utilities that mirror MoonBit's
 * vid_from_pair / vid_to_pair (the SoT in lib/exports.mbt).
 *
 * These conversions are trivial bit operations — calling them via
 * FFI would be unreasonable overhead, so they are mirrored in JS.
 * The MoonBit implementations remain the SoT; these must stay
 * in sync with vid_from_pair / vid_to_pair.
 *
 * Timestamp conversion (nowNs) is included because the persistent_*
 * FFI requires MoonBit Int64 timestamps, and the conversion involves
 * the same hi/lo split logic that is specific to MoonBit's JS target
 * encoding.
 */

/**
 * VectorId as hi/lo i32 pair — the JS representation of MoonBit's Int64.
 * This is the only ID format used across all vcdb FFI boundaries.
 */
export type VcdbId = { readonly hi: number; readonly lo: number };

/**
 * Split a JS number into hi/lo i32 pair.
 * Mirrors MoonBit's vid_from_pair (lib/exports.mbt).
 */
export const numericToId = (n: number): VcdbId => ({
  hi: (n / 0x100000000) | 0,
  lo: n | 0,
});

/**
 * Reconstruct a JS number from hi/lo pair.
 * Mirrors MoonBit's vid_to_pair (lib/exports.mbt).
 */
export const idToNumeric = (id: VcdbId): number =>
  (id.hi >>> 0) * 0x100000000 + (id.lo >>> 0);

/**
 * Current time as MoonBit Int64 nanoseconds since epoch (hi/lo pair).
 * Required by persistent_upsert, persistent_remove, etc.
 */
export const nowNs = (): VcdbId => {
  const ms = Date.now();
  const ns = ms * 1_000_000;
  return { hi: Math.floor(ns / 0x100000000), lo: ns >>> 0 };
};
