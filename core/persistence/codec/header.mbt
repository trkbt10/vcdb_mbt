///|
/// Common header format for all vcdb binary files
/// Header (12 bytes):
/// - Magic: 8 bytes "VCDBMBT\x00"
/// - Type: 1 byte (0x01=WAL, 0x02=Segment, 0x03=Index)
/// - Version: 1 byte
/// - Reserved: 2 bytes

///|
/// Common magic bytes: "VCDBMBT\x00" (8 bytes)
/// Stored as two UInt32 values in little-endian:
/// - First 4 bytes: "VCDB" = 0x42444356
/// - Next 4 bytes: "MBT\x00" = 0x0054424D
pub let vcdb_magic_lo : UInt = 0x42444356U // "VCDB" LE

///|
pub let vcdb_magic_hi : UInt = 0x0054424DU // "MBT\x00" LE

///|
/// File type codes
pub(all) enum FileType {
  Wal // 0x01
  Segment // 0x02
  Index // 0x03
} derive(Eq, Show)

///|
/// Convert file type to byte
pub fn FileType::to_byte(self : FileType) -> Byte {
  match self {
    Wal => b'\x01'
    Segment => b'\x02'
    Index => b'\x03'
  }
}

///|
/// Convert byte to file type
pub fn FileType::from_byte(b : Byte) -> FileType? {
  match b {
    b'\x01' => Some(Wal)
    b'\x02' => Some(Segment)
    b'\x03' => Some(Index)
    _ => None
  }
}

///|
/// Header size in bytes
pub let header_size : Int = 12

///|
/// Encode common header
pub fn encode_header(
  w : @binary.BinaryWriter,
  file_type : FileType,
  version : Byte,
) -> Unit {
  w.push_u32(vcdb_magic_lo)
  w.push_u32(vcdb_magic_hi)
  w.push_byte(file_type.to_byte())
  w.push_byte(version)
  w.push_byte(b'\x00') // Reserved
  w.push_byte(b'\x00') // Reserved
}

///|
/// Verify magic bytes
pub fn verify_magic(r : @binary.BinaryReader) -> Bool {
  if r.remaining() < 8 {
    return false
  }
  let lo = r.read_u32()
  let hi = r.read_u32()
  lo == vcdb_magic_lo && hi == vcdb_magic_hi
}

///|
/// Read and verify header, returns (file_type, version) if valid
pub fn read_header(r : @binary.BinaryReader) -> (FileType, Byte)? {
  if r.remaining() < header_size {
    return None
  }
  if !verify_magic(r) {
    return None
  }
  let type_byte = r.read_byte()
  let file_type = match FileType::from_byte(type_byte) {
    None => return None
    Some(t) => t
  }
  let version = r.read_byte()
  let _ = r.read_byte() // Reserved
  let _ = r.read_byte() // Reserved
  Some((file_type, version))
}

///|
/// Check if bytes start with vcdb magic
pub fn is_vcdb_file(data : Bytes) -> Bool {
  if data.length() < 8 {
    return false
  }
  let r = @binary.BinaryReader::new(data)
  verify_magic(r)
}

///|
/// Get file type from bytes (without consuming version)
pub fn get_file_type(data : Bytes) -> FileType? {
  if data.length() < header_size {
    return None
  }
  let r = @binary.BinaryReader::new(data)
  if !verify_magic(r) {
    return None
  }
  FileType::from_byte(r.read_byte())
}

// ============================================================================
// File Extensions (Single Source of Truth)
// ============================================================================

///|
/// WAL file extension
pub let ext_wal : String = ".vwal"

///|
/// Data segment file extension
pub let ext_segment : String = ".vseg"

///|
/// Index file extension
pub let ext_index : String = ".vidx"

///|
/// Manifest file extension
pub let ext_manifest : String = ".vcdb.manifest"

///|
/// Get file extension for a file type
pub fn FileType::extension(self : FileType) -> String {
  match self {
    Wal => ext_wal
    Segment => ext_segment
    Index => ext_index
  }
}
