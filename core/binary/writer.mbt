///|
/// Binary writer for serialization
pub struct BinaryWriter {
  chunks : Array[FixedArray[Byte]]
  mut total_size : Int
}

///|
/// Create a new binary writer
pub fn BinaryWriter::new() -> BinaryWriter {
  { chunks: [], total_size: 0 }
}

///|
/// Push a u32 value (little-endian)
pub fn BinaryWriter::push_u32(self : BinaryWriter, value : UInt) -> Unit {
  let bytes : FixedArray[Byte] = FixedArray::make(4, b'\x00')
  bytes[0] = (value & 0xFF).to_byte()
  bytes[1] = ((value >> 8) & 0xFF).to_byte()
  bytes[2] = ((value >> 16) & 0xFF).to_byte()
  bytes[3] = ((value >> 24) & 0xFF).to_byte()
  self.chunks.push(bytes)
  self.total_size = self.total_size + 4
}

///|
/// Push an i32 value (little-endian)
pub fn BinaryWriter::push_i32(self : BinaryWriter, value : Int) -> Unit {
  self.push_u32(value.reinterpret_as_uint())
}

///|
/// Push a u64 value (little-endian)
pub fn BinaryWriter::push_u64(self : BinaryWriter, value : UInt64) -> Unit {
  let bytes : FixedArray[Byte] = FixedArray::make(8, b'\x00')
  bytes[0] = (value & 0xFF).to_byte()
  bytes[1] = ((value >> 8) & 0xFF).to_byte()
  bytes[2] = ((value >> 16) & 0xFF).to_byte()
  bytes[3] = ((value >> 24) & 0xFF).to_byte()
  bytes[4] = ((value >> 32) & 0xFF).to_byte()
  bytes[5] = ((value >> 40) & 0xFF).to_byte()
  bytes[6] = ((value >> 48) & 0xFF).to_byte()
  bytes[7] = ((value >> 56) & 0xFF).to_byte()
  self.chunks.push(bytes)
  self.total_size = self.total_size + 8
}

///|
/// Push an i64 value (little-endian)
pub fn BinaryWriter::push_i64(self : BinaryWriter, value : Int64) -> Unit {
  self.push_u64(value.reinterpret_as_uint64())
}

///|
/// Push a f64 value
pub fn BinaryWriter::push_f64(self : BinaryWriter, value : Double) -> Unit {
  self.push_u64(value.reinterpret_as_uint64())
}

///|
/// Push a f32 value (little-endian)
pub fn BinaryWriter::push_f32(self : BinaryWriter, value : Float) -> Unit {
  self.push_u32(value.reinterpret_as_uint())
}

///|
/// Push a single byte
pub fn BinaryWriter::push_byte(self : BinaryWriter, value : Byte) -> Unit {
  let bytes : FixedArray[Byte] = FixedArray::make(1, value)
  self.chunks.push(bytes)
  self.total_size = self.total_size + 1
}

///|
/// Push raw bytes
pub fn BinaryWriter::push_bytes(self : BinaryWriter, data : Bytes) -> Unit {
  let arr : FixedArray[Byte] = FixedArray::make(data.length(), b'\x00')
  for i in 0..<data.length() {
    arr[i] = data[i]
  }
  self.chunks.push(arr)
  self.total_size = self.total_size + data.length()
}

///|
/// Concatenate all chunks into a single Bytes
pub fn BinaryWriter::concat(self : BinaryWriter) -> Bytes {
  let result : FixedArray[Byte] = FixedArray::make(self.total_size, b'\x00')
  let mut offset = 0
  for chunk in self.chunks {
    for i in 0..<chunk.length() {
      result[offset + i] = chunk[i]
    }
    offset = offset + chunk.length()
  }
  Bytes::from_array(result[:])
}
