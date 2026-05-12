// Whitebox tests for binary module

///|
test "binary/writer_reader" {
  let w = BinaryWriter::new()
  w.push_u32(42U)
  w.push_i32(-100)
  w.push_u64(0x123456789ABCDEF0UL)
  w.push_f64(3.14159)
  let bytes = w.concat()
  let r = BinaryReader::new(bytes)
  inspect(r.read_u32(), content="42")
  inspect(r.read_i32(), content="-100")
  inspect(r.read_u64(), content="1311768467463790320")
  let f = r.read_f64()
  inspect((f - 3.14159).abs() < 0.0001, content="true")
}

///|
/// Test: BinaryWriter and BinaryReader roundtrip
test "binary/roundtrip" {
  let writer = BinaryWriter::new()
  writer.push_u32(0x12345678U)
  writer.push_i32(-123)
  writer.push_u64(12345678901234UL)
  writer.push_f64(3.14159)
  writer.push_byte(b'\xFF')
  let data = writer.concat()
  let reader = BinaryReader::new(data)
  inspect(reader.read_u32(), content="305419896")
  inspect(reader.read_i32(), content="-123")
  inspect(reader.read_u64(), content="12345678901234")
  let f = reader.read_f64()
  inspect((f - 3.14159).abs() < 0.00001, content="true")
  inspect(reader.read_byte().to_int(), content="255")
}

///|
/// Test: Float32 binary roundtrip
test "binary/f32_roundtrip" {
  let writer = BinaryWriter::new()
  writer.push_f32(Float::from_double(3.14159))
  writer.push_f32(Float::from_double(-1.5))
  writer.push_f32(Float::from_double(0.0))
  let data = writer.concat()
  let reader = BinaryReader::new(data)
  let f1 = reader.read_f32().to_double()
  let f2 = reader.read_f32().to_double()
  let f3 = reader.read_f32().to_double()
  // Float32 precision (about 7 significant digits)
  inspect((f1 - 3.14159).abs() < 0.0001, content="true")
  inspect((f2 - -1.5).abs() < 0.0001, content="true")
  inspect(f3, content="0")
}

///|
/// Test: BinaryWriter push_bytes
test "binary/push_bytes" {
  let w = BinaryWriter::new()
  w.push_u32(0x12345678U)
  let bytes = Bytes::from_array([b'a', b'b', b'c', b'd'][:])
  w.push_bytes(bytes)
  w.push_u32(0xDEADBEEFU)
  let data = w.concat()
  let r = BinaryReader::new(data)
  inspect(r.read_u32(), content="305419896")
  let read_bytes = r.read_bytes(4)
  inspect(read_bytes[0] == b'a', content="true")
  inspect(read_bytes[3] == b'd', content="true")
  inspect(r.read_u32(), content="3735928559")
}

///|
test "binary/bytes_equal" {
  let same1 = Bytes::from_array([b'a', b'b', b'c'][:])
  let same2 = Bytes::from_array([b'a', b'b', b'c'][:])
  let diff_value = Bytes::from_array([b'a', b'b', b'd'][:])
  let diff_len = Bytes::from_array([b'a', b'b'][:])
  inspect(bytes_equal(same1, same2), content="true")
  inspect(bytes_equal(same1, diff_value), content="false")
  inspect(bytes_equal(same1, diff_len), content="false")
}

///|
/// Test: BinaryReader position tracking
test "binary/reader_position" {
  let bytes = Bytes::from_array(
    [b'a', b'b', b'c', b'd', b'e', b'f', b'g', b'h'][:],
  )
  let r = BinaryReader::new(bytes)
  inspect(r.offset, content="0")
  let _ = r.read_u32()
  inspect(r.offset, content="4")
  let _ = r.read_u32()
  inspect(r.offset, content="8")
}

///|
/// Test: Checksum CRC32
test "checksum/crc32_known_values" {
  // Known CRC32 values for testing
  let data1 = Bytes::from_array([b'h', b'e', b'l', b'l', b'o'][:])
  let crc1 = crc32(data1)
  // Known CRC32 for "hello" is 0x3610A686
  inspect(crc1 == 0x3610A686U, content="true")
  // Empty data
  let data2 = Bytes::new(0)
  let crc2 = crc32(data2)
  inspect(crc2, content="0") // CRC32 of empty = 0
  // Single byte
  let data3 = Bytes::from_array([b'a'][:])
  let crc3 = crc32(data3)
  // CRC32 of "a" is 0xE8B7BE43
  inspect(crc3 == 0xE8B7BE43U, content="true")
}

///|
/// Test: CRC32 fast implementation
test "checksum/crc32_fast" {
  let data = Bytes::from_array([b'h', b'e', b'l', b'l', b'o'][:])
  let crc_fast = crc32_fast(data)
  let crc_normal = crc32(data)
  // Both should give same result
  inspect(crc_fast == crc_normal, content="true")
  inspect(crc_fast == 0x3610A686U, content="true")
}

///|
/// Test: CRC32 verify
test "checksum/crc32_verify" {
  let data = Bytes::from_array([b't', b'e', b's', b't'][:])
  let crc = crc32(data)
  inspect(crc32_verify(data, crc), content="true")
  inspect(crc32_verify(data, 0x12345678U), content="false")
}
