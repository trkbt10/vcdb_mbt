/**
 * @file bigint <-> MoonBit Int64 (hi/lo pair) conversion.
 *
 * Internal bridge between the public VectorId (bigint) and
 * the WASM FFI representation (signed i32 pair).
 *
 * Pure JS arithmetic — no WASM module dependency.
 */
import type { MbInt64 } from "./types.js";

/** Split a bigint into MoonBit's hi/lo i32 pair. */
export function toHiLo(id: bigint): MbInt64 {
  const lo = Number(BigInt.asIntN(32, id));
  const hi = Number(BigInt.asIntN(32, id >> 32n));
  return { hi, lo };
}

/** Join a hi/lo i32 pair into a bigint. */
export function fromHiLo(hi: number, lo: number): bigint {
  return (BigInt(hi) << 32n) | BigInt(lo >>> 0);
}

/** Current time as MoonBit Int64 nanoseconds since epoch. */
export function nowNs(): MbInt64 {
  const ms = Date.now();
  const ns = ms * 1_000_000;
  return { hi: Math.floor(ns / 0x100000000), lo: ns >>> 0 };
}
