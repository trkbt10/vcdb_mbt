///|
/// Binary reader for deserialization
pub struct BinaryReader {
  data : Bytes
  mut offset : Int
}

///|
/// Create a new binary reader
pub fn BinaryReader::new(data : Bytes) -> BinaryReader {
  { data, offset: 0 }
}

///|
/// Get current read position
pub fn BinaryReader::position(self : BinaryReader) -> Int {
  self.offset
}

///|
/// Read a u32 value (little-endian)
pub fn BinaryReader::read_u32(self : BinaryReader) -> UInt {
  let b0 = self.data[self.offset].to_int() & 0xFF
  let b1 = self.data[self.offset + 1].to_int() & 0xFF
  let b2 = self.data[self.offset + 2].to_int() & 0xFF
  let b3 = self.data[self.offset + 3].to_int() & 0xFF
  self.offset = self.offset + 4
  (b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)).reinterpret_as_uint()
}

///|
/// Read an i32 value (little-endian)
pub fn BinaryReader::read_i32(self : BinaryReader) -> Int {
  self.read_u32().reinterpret_as_int()
}

///|
/// Read a u64 value (little-endian)
pub fn BinaryReader::read_u64(self : BinaryReader) -> UInt64 {
  let b0 = self.data[self.offset].to_int().land(0xFF).to_int64()
  let b1 = self.data[self.offset + 1].to_int().land(0xFF).to_int64()
  let b2 = self.data[self.offset + 2].to_int().land(0xFF).to_int64()
  let b3 = self.data[self.offset + 3].to_int().land(0xFF).to_int64()
  let b4 = self.data[self.offset + 4].to_int().land(0xFF).to_int64()
  let b5 = self.data[self.offset + 5].to_int().land(0xFF).to_int64()
  let b6 = self.data[self.offset + 6].to_int().land(0xFF).to_int64()
  let b7 = self.data[self.offset + 7].to_int().land(0xFF).to_int64()
  self.offset = self.offset + 8
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
/// Read an i64 value (little-endian)
pub fn BinaryReader::read_i64(self : BinaryReader) -> Int64 {
  self.read_u64().reinterpret_as_int64()
}

///|
/// Read a f64 value
pub fn BinaryReader::read_f64(self : BinaryReader) -> Double {
  self.read_u64().reinterpret_as_double()
}

///|
/// Read a f32 value (little-endian)
pub fn BinaryReader::read_f32(self : BinaryReader) -> Float {
  Float::reinterpret_from_uint(self.read_u32())
}

///|
/// Read a single byte
pub fn BinaryReader::read_byte(self : BinaryReader) -> Byte {
  let b = self.data[self.offset]
  self.offset = self.offset + 1
  b
}

///|
/// Read len bytes
pub fn BinaryReader::read_bytes(self : BinaryReader, len : Int) -> Bytes {
  let result : FixedArray[Byte] = FixedArray::make(len, b'\x00')
  for i in 0..<len {
    result[i] = self.data[self.offset + i]
  }
  self.offset = self.offset + len
  Bytes::from_array(result[:])
}

///|
/// Check if there are more bytes to read
pub fn BinaryReader::has_more(self : BinaryReader) -> Bool {
  self.offset < self.data.length()
}

///|
/// Get remaining bytes count
pub fn BinaryReader::remaining(self : BinaryReader) -> Int {
  self.data.length() - self.offset
}

///|
/// Skip n bytes
pub fn BinaryReader::skip(self : BinaryReader, n : Int) -> Unit {
  self.offset = self.offset + n
}
