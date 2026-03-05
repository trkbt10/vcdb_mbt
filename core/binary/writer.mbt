///|
/// Binary writer for serialization - single buffer with grow-on-demand
pub struct BinaryWriter {
  mut buf : FixedArray[Byte]
  mut len : Int
}

///|
/// Create a new binary writer with initial capacity
pub fn BinaryWriter::new(capacity? : Int = 256) -> BinaryWriter {
  { buf: FixedArray::make(capacity, b'\x00'), len: 0 }
}

///|
/// Ensure capacity for additional bytes
fn BinaryWriter::ensure(self : BinaryWriter, extra : Int) -> Unit {
  let needed = self.len + extra
  if needed <= self.buf.length() {
    return
  }
  let mut new_cap = self.buf.length()
  while new_cap < needed {
    new_cap = new_cap * 2
  }
  let new_buf = FixedArray::make(new_cap, b'\x00')
  for i in 0..<self.len {
    new_buf[i] = self.buf[i]
  }
  self.buf = new_buf
}

///|
/// Push a u32 value (little-endian)
pub fn BinaryWriter::push_u32(self : BinaryWriter, value : UInt) -> Unit {
  self.ensure(4)
  write_u32_le(self.buf, self.len, value)
  self.len = self.len + 4
}

///|
/// Push an i32 value (little-endian)
pub fn BinaryWriter::push_i32(self : BinaryWriter, value : Int) -> Unit {
  self.push_u32(value.reinterpret_as_uint())
}

///|
/// Push a u64 value (little-endian)
pub fn BinaryWriter::push_u64(self : BinaryWriter, value : UInt64) -> Unit {
  self.ensure(8)
  write_u64_le(self.buf, self.len, value)
  self.len = self.len + 8
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
  self.ensure(1)
  self.buf[self.len] = value
  self.len = self.len + 1
}

///|
/// Push raw bytes
pub fn BinaryWriter::push_bytes(self : BinaryWriter, data : Bytes) -> Unit {
  let n = data.length()
  self.ensure(n)
  for i in 0..<n {
    self.buf[self.len + i] = data[i]
  }
  self.len = self.len + n
}

///|
/// Get result as Bytes (zero-copy slice)
pub fn BinaryWriter::concat(self : BinaryWriter) -> Bytes {
  Bytes::from_array(self.buf[:self.len])
}
