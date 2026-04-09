/**
 * @file VectorId wire format conversions.
 *
 * The canonical wire format for VectorId is Uint8Array(16):
 *   Int64Id(v)    → bytes 0-7 = v big-endian int64, bytes 8-15 = 0x00
 *   Bytes16Id(b)  → bytes 0-15 = b as-is
 *
 * SoT: VectorId::to_wire_bytes / VectorId::from_wire_bytes in
 *      core/types/types.mbt
 *
 * This file contains only the JS-side mirror of those conversions.
 * String format parsing (UUID, ULID) belongs in packages/core, not here.
 */

export const WIRE_BYTES_LENGTH = 16;

/**
 * Encode a signed 64-bit integer (as bigint) to the 16-byte wire format.
 * Bytes 0-7: value big-endian. Bytes 8-15: 0x00.
 */
export function int64ToWireBytes(value: bigint): Uint8Array {
  const buf = new Uint8Array(WIRE_BYTES_LENGTH);
  // Write big-endian int64 into bytes 0-7
  let v = BigInt.asUintN(64, value);
  for (let i = 7; i >= 0; i--) {
    buf[i] = Number(v & 0xffn);
    v >>= 8n;
  }
  // bytes 8-15 remain 0x00
  return buf;
}

/**
 * Decode a signed 64-bit integer from the wire format (bytes 0-7, big-endian).
 * Caller is responsible for verifying bytes 8-15 are zero before treating
 * as Int64Id (use isInt64WireBytes for that check).
 */
export function wireBytesBigInt(buf: Uint8Array): bigint {
  let v = 0n;
  for (let i = 0; i < 8; i++) {
    v = (v << 8n) | BigInt(buf[i]);
  }
  // Reinterpret as signed int64
  return BigInt.asIntN(64, v);
}

/**
 * Returns true if bytes 8-15 are all zero — indicating an Int64Id wire encoding.
 * If false, the bytes represent a Bytes16Id.
 */
export function isInt64WireBytes(buf: Uint8Array): boolean {
  for (let i = 8; i < WIRE_BYTES_LENGTH; i++) {
    if (buf[i] !== 0) return false;
  }
  return true;
}

/**
 * Encode a 16-byte Uint8Array directly as wire bytes.
 * The caller must ensure data.length === 16.
 */
export function bytes16ToWireBytes(data: Uint8Array): Uint8Array {
  if (data.length !== WIRE_BYTES_LENGTH) {
    throw new Error(`bytes16ToWireBytes: expected 16 bytes, got ${data.length}`);
  }
  return data.slice();
}

/**
 * Current time as a bigint nanoseconds since epoch.
 * Used for WAL timestamps passed to persistent_* operations.
 */
export function nowNs(): bigint {
  return BigInt(Date.now()) * 1_000_000n;
}
