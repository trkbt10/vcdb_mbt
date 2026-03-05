///|
test "header/encode_decode" {
  let w = @binary.BinaryWriter::new()
  encode_header(w, Wal, b'\x01')
  let bytes = w.concat()
  inspect(bytes.length(), content="12")
  // Verify magic bytes: "VCDBMBT\x00"
  inspect(bytes[0], content="b'\\x56'") // V
  inspect(bytes[1], content="b'\\x43'") // C
  inspect(bytes[2], content="b'\\x44'") // D
  inspect(bytes[3], content="b'\\x42'") // B
  inspect(bytes[4], content="b'\\x4D'") // M
  inspect(bytes[5], content="b'\\x42'") // B
  inspect(bytes[6], content="b'\\x54'") // T
  inspect(bytes[7], content="b'\\x00'") // \0
  inspect(bytes[8], content="b'\\x01'") // Type: Wal
  inspect(bytes[9], content="b'\\x01'") // Version
}

///|
test "header/read_header" {
  let w = @binary.BinaryWriter::new()
  encode_header(w, Segment, b'\x02')
  let r = @binary.BinaryReader::new(w.concat())
  match read_header(r) {
    None => inspect(false, content="true")
    Some((file_type, version)) => {
      inspect(file_type, content="Segment")
      inspect(version, content="b'\\x02'")
    }
  }
}

///|
test "header/verify_magic" {
  let w = @binary.BinaryWriter::new()
  encode_header(w, Index, b'\x01')
  let r = @binary.BinaryReader::new(w.concat())
  inspect(verify_magic(r), content="true")
  // Invalid magic
  let bad = Bytes::make(12, b'\x00')
  let r2 = @binary.BinaryReader::new(bad)
  inspect(verify_magic(r2), content="false")
}

///|
test "header/is_vcdb_file" {
  let w = @binary.BinaryWriter::new()
  encode_header(w, Wal, b'\x01')
  inspect(is_vcdb_file(w.concat()), content="true")
  // Too short
  inspect(is_vcdb_file(Bytes::make(4, b'\x00')), content="false")
  // Wrong magic
  inspect(is_vcdb_file(Bytes::make(12, b'\xFF')), content="false")
}

///|
test "header/get_file_type" {
  let w1 = @binary.BinaryWriter::new()
  encode_header(w1, Wal, b'\x01')
  inspect(get_file_type(w1.concat()), content="Some(Wal)")
  let w2 = @binary.BinaryWriter::new()
  encode_header(w2, Segment, b'\x01')
  inspect(get_file_type(w2.concat()), content="Some(Segment)")
  let w3 = @binary.BinaryWriter::new()
  encode_header(w3, Index, b'\x01')
  inspect(get_file_type(w3.concat()), content="Some(Index)")
  // Invalid
  inspect(get_file_type(Bytes::make(12, b'\x00')), content="None")
}

///|
test "header/file_type_roundtrip" {
  let types = [Wal, Segment, Index]
  for ft in types {
    let b = ft.to_byte()
    match FileType::from_byte(b) {
      None => inspect(false, content="true")
      Some(decoded) => inspect(decoded == ft, content="true")
    }
  }
  // Invalid type byte
  inspect(FileType::from_byte(b'\x00'), content="None")
  inspect(FileType::from_byte(b'\xFF'), content="None")
}

///|
test "ext/file_extensions" {
  // Verify extension constants
  inspect(ext_wal, content=".vwal")
  inspect(ext_segment, content=".vseg")
  inspect(ext_index, content=".vidx")
  inspect(ext_manifest, content=".vcdb.manifest")
  // Verify FileType::extension
  inspect(Wal.extension(), content=".vwal")
  inspect(Segment.extension(), content=".vseg")
  inspect(Index.extension(), content=".vidx")
}
