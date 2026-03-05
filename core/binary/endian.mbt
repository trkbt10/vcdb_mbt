///|
/// Read a u32 value from bytes (little-endian).
fn read_u32_le(data : Bytes, offset : Int) -> UInt {
  let b0 = data[offset].to_int() & 0xFF
  let b1 = data[offset + 1].to_int() & 0xFF
  let b2 = data[offset + 2].to_int() & 0xFF
  let b3 = data[offset + 3].to_int() & 0xFF
  (b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)).reinterpret_as_uint()
}

///|
/// Read a u64 value from bytes (little-endian).
fn read_u64_le(data : Bytes, offset : Int) -> UInt64 {
  let b0 = data[offset].to_int().land(0xFF).to_int64()
  let b1 = data[offset + 1].to_int().land(0xFF).to_int64()
  let b2 = data[offset + 2].to_int().land(0xFF).to_int64()
  let b3 = data[offset + 3].to_int().land(0xFF).to_int64()
  let b4 = data[offset + 4].to_int().land(0xFF).to_int64()
  let b5 = data[offset + 5].to_int().land(0xFF).to_int64()
  let b6 = data[offset + 6].to_int().land(0xFF).to_int64()
  let b7 = data[offset + 7].to_int().land(0xFF).to_int64()
  (b0 |
  (b1 << 8) |
  (b2 << 16) |
  (b3 << 24) |
  (b4 << 32) |
  (b5 << 40) |
  (b6 << 48) |
  (b7 << 56)).reinterpret_as_uint64()
}

///|
/// Write a u32 value into a fixed buffer (little-endian).
fn write_u32_le(buf : FixedArray[Byte], offset : Int, value : UInt) -> Unit {
  buf[offset] = (value & 0xFF).to_byte()
  buf[offset + 1] = ((value >> 8) & 0xFF).to_byte()
  buf[offset + 2] = ((value >> 16) & 0xFF).to_byte()
  buf[offset + 3] = ((value >> 24) & 0xFF).to_byte()
}

///|
/// Write a u64 value into a fixed buffer (little-endian).
fn write_u64_le(buf : FixedArray[Byte], offset : Int, value : UInt64) -> Unit {
  buf[offset] = (value & 0xFF).to_byte()
  buf[offset + 1] = ((value >> 8) & 0xFF).to_byte()
  buf[offset + 2] = ((value >> 16) & 0xFF).to_byte()
  buf[offset + 3] = ((value >> 24) & 0xFF).to_byte()
  buf[offset + 4] = ((value >> 32) & 0xFF).to_byte()
  buf[offset + 5] = ((value >> 40) & 0xFF).to_byte()
  buf[offset + 6] = ((value >> 48) & 0xFF).to_byte()
  buf[offset + 7] = ((value >> 56) & 0xFF).to_byte()
}
