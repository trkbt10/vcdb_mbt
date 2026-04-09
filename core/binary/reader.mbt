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
/// Ensure n bytes are available, abort with message if not.
fn BinaryReader::ensure(self : BinaryReader, n : Int) -> Unit {
  if self.offset + n > self.data.length() {
    abort(
      "BinaryReader: read out of bounds (offset=" +
      self.offset.to_string() +
      ", need=" +
      n.to_string() +
      ", len=" +
      self.data.length().to_string() +
      ")",
    )
  }
}

///|
/// Read a u32 value (little-endian)
pub fn BinaryReader::read_u32(self : BinaryReader) -> UInt {
  self.ensure(4)
  let value = read_u32_le(self.data, self.offset)
  self.offset = self.offset + 4
  value
}

///|
/// Read an i32 value (little-endian)
pub fn BinaryReader::read_i32(self : BinaryReader) -> Int {
  self.read_u32().reinterpret_as_int()
}

///|
/// Read a u64 value (little-endian)
pub fn BinaryReader::read_u64(self : BinaryReader) -> UInt64 {
  self.ensure(8)
  let value = read_u64_le(self.data, self.offset)
  self.offset = self.offset + 8
  value
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
  self.ensure(1)
  let b = self.data[self.offset]
  self.offset = self.offset + 1
  b
}

///|
/// Read len bytes. Aborts if not enough data remaining.
pub fn BinaryReader::read_bytes(self : BinaryReader, len : Int) -> Bytes {
  self.ensure(len)
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
/// Skip n bytes. Aborts if not enough data remaining.
pub fn BinaryReader::skip(self : BinaryReader, n : Int) -> Unit {
  self.ensure(n)
  self.offset = self.offset + n
}
