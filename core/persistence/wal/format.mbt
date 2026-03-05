///|
/// Write-Ahead Log (WAL) implementation
/// Format:
/// - Header (8 bytes): Magic (4 bytes) + Version (4 bytes)
/// - Records: Type (1 byte) + Reserved (1 byte) + ID (8 bytes) + AttrsLen (4 bytes) + VectorLen (4 bytes) + Data
/// - Footer (8 bytes, optional): Magic (4 bytes) + CRC32 (4 bytes)
/// - Attrs: JSON encoded UTF-8 string
/// - Vectors: Float32 array (4 bytes per element)

///|
/// WAL Magic number: "VLWA" in little-endian
pub let wal_magic : UInt = 0x41574C56U

///|
/// WAL Footer magic: "WCRC" in little-endian
pub let wal_footer_magic : UInt = 0x43524357U

///|
/// WAL format version
pub let wal_version : UInt = 1U

///|
/// WAL record types
pub enum WalRecordType {
  Upsert // 1 - Insert or update vector with attrs
  Remove // 2 - Delete vector
  SetAttrs // 3 - Update attrs only
} derive(Eq, Show)

///|
/// Convert record type to byte
pub fn WalRecordType::to_byte(self : WalRecordType) -> Byte {
  match self {
    Upsert => b'\x01'
    Remove => b'\x02'
    SetAttrs => b'\x03'
  }
}

///|
/// Convert byte to record type
pub fn WalRecordType::from_byte(b : Byte) -> WalRecordType? {
  match b {
    b'\x01' => Some(Upsert)
    b'\x02' => Some(Remove)
    b'\x03' => Some(SetAttrs)
    _ => None
  }
}

///|
/// WAL record
pub struct WalRecord {
  record_type : WalRecordType
  id : @core.VectorId
  attrs : @core.Attrs?
  vector : Array[Double]?
} derive(Show)

///|
/// Create an upsert record
pub fn WalRecord::upsert(
  id : @core.VectorId,
  vector : Array[Double],
  attrs : @core.Attrs,
) -> WalRecord {
  { record_type: Upsert, id, attrs: Some(attrs), vector: Some(vector) }
}

///|
/// Create a remove record
pub fn WalRecord::remove(id : @core.VectorId) -> WalRecord {
  { record_type: Remove, id, attrs: None, vector: None }
}

///|
/// Create a set_attrs record
pub fn WalRecord::set_attrs(
  id : @core.VectorId,
  attrs : @core.Attrs,
) -> WalRecord {
  { record_type: SetAttrs, id, attrs: Some(attrs), vector: None }
}

///|
/// Encode attrs to JSON bytes (TypeScript compatible)
fn encode_attrs_json(attrs : @core.Attrs?) -> Bytes {
  @codec.encode_attrs_json(attrs)
}

///|
/// Decode JSON string to attrs
fn decode_attrs_json(bytes : Bytes) -> @core.Attrs? {
  @codec.decode_attrs_json(bytes)
}

///|
/// Encode a WAL record to bytes
/// Note: Uses 64-bit IDs to preserve full VectorId range
pub fn encode_wal_record(record : WalRecord) -> Bytes {
  let w = @binary.BinaryWriter::new()
  encode_wal_record_to(w, record)
  w.concat()
}

///|
/// Encode a WAL record to an existing writer (avoids intermediate allocations)
fn encode_wal_record_to(w : @binary.BinaryWriter, record : WalRecord) -> Unit {
  // Type (1 byte)
  w.push_byte(record.record_type.to_byte())
  // Reserved (1 byte)
  w.push_byte(b'\x00')
  // ID (8 bytes as u64 to preserve full Int64 range)
  w.push_u64(record.id.to_int64().reinterpret_as_uint64())
  // Encode attrs as JSON
  let attrs_bytes = encode_attrs_json(record.attrs)
  // Calculate vector length
  let vector_len = match record.vector {
    None => 0
    Some(v) => v.length() * 4
  }
  // Write lengths
  w.push_u32(attrs_bytes.length().reinterpret_as_uint())
  w.push_u32(vector_len.reinterpret_as_uint())
  // Write attrs
  w.push_bytes(attrs_bytes)
  // Write vector inline (no intermediate buffer)
  match record.vector {
    None => ()
    Some(v) =>
      for val in v {
        w.push_f32(Float::from_double(val))
      }
  }
}

///|
/// Decode a WAL record from reader
/// Note: Uses 64-bit IDs to preserve full VectorId range
pub fn decode_wal_record(r : @binary.BinaryReader) -> WalRecord? {
  if r.remaining() < 18 {
    // Minimum: type(1) + reserved(1) + id(8) + attrs_len(4) + vector_len(4)
    return None
  }
  // Type
  let type_byte = r.read_byte()
  let record_type = match WalRecordType::from_byte(type_byte) {
    None => return None
    Some(t) => t
  }
  // Reserved
  let _ = r.read_byte()
  // ID (8 bytes as u64)
  let id = @core.VectorId(r.read_u64().reinterpret_as_int64())
  // Lengths
  let attrs_len = r.read_u32().reinterpret_as_int()
  let vector_len = r.read_u32().reinterpret_as_int()
  // Validate payload lengths fit in remaining buffer (corruption/truncation check)
  if attrs_len < 0 || vector_len < 0 || r.remaining() < attrs_len + vector_len {
    return None
  }
  // Read attrs (JSON)
  let attrs = if attrs_len > 0 {
    let attrs_bytes = r.read_bytes(attrs_len)
    decode_attrs_json(attrs_bytes)
  } else {
    None
  }
  // Read vector (Float32) - reject non-aligned payloads
  let vector = if vector_len > 0 {
    // Reject if not Float32-aligned (must be multiple of 4)
    if vector_len % 4 != 0 {
      return None
    }
    let vec : Array[Double] = []
    let count = vector_len / 4 // Float32 = 4 bytes
    for _ in 0..<count {
      vec.push(r.read_f32().to_double())
    }
    Some(vec)
  } else {
    None
  }
  Some({ record_type, id, attrs, vector })
}

///|
/// Encode WAL header
pub fn encode_wal_header() -> Bytes {
  let w = @binary.BinaryWriter::new()
  w.push_u32(wal_magic)
  w.push_u32(wal_version)
  w.concat()
}

///|
/// Encode WAL footer with CRC32
pub fn encode_wal_footer(body : Bytes) -> Bytes {
  let w = @binary.BinaryWriter::new()
  w.push_u32(wal_footer_magic)
  w.push_u32(@binary.crc32_fast(body))
  w.concat()
}

///|
/// Encode multiple records to a complete WAL segment
pub fn encode_wal_segment(records : Array[WalRecord]) -> Bytes {
  let w = @binary.BinaryWriter::new()
  // Write header inline
  w.push_u32(wal_magic)
  w.push_u32(wal_version)
  // Write records directly (no intermediate allocations)
  for record in records {
    encode_wal_record_to(w, record)
  }
  // Get body (header + records)
  let body = w.concat()
  // Add footer with CRC32 inline
  w.push_u32(wal_footer_magic)
  w.push_u32(@binary.crc32_fast(body))
  w.concat()
}

///|
/// Verify WAL header
pub fn verify_wal_header(r : @binary.BinaryReader) -> Bool {
  let magic = r.read_u32()
  let version = r.read_u32()
  magic == wal_magic && version == wal_version
}

///|
/// Return footer start offset when WAL checksum footer is present.
fn wal_footer_start(data : Bytes) -> Int? {
  if data.length() < 16 {
    return None
  }
  let footer_start = data.length() - 8
  let r = @binary.BinaryReader::new(data)
  r.skip(footer_start)
  let footer_magic = r.read_u32()
  if footer_magic == wal_footer_magic {
    Some(footer_start)
  } else {
    None
  }
}

///|
/// Return WAL body length (header + records, excludes checksum footer if present).
fn wal_body_length(data : Bytes) -> Int {
  match wal_footer_start(data) {
    Some(footer_start) => footer_start
    None => data.length()
  }
}

///|
/// Check if WAL has valid footer and verify CRC32
/// A header-only WAL (8 bytes) is valid - no footer to verify
pub fn verify_wal_checksum(data : Bytes) -> Bool {
  // Too short to even have a header
  if data.length() < 8 {
    return false
  }
  // Header-only WAL (no footer) is valid
  if data.length() < 16 {
    return true
  }
  let footer_start = match wal_footer_start(data) {
    None => return true // No footer, assume valid
    Some(offset) => offset
  }
  let footer_reader = @binary.BinaryReader::new(data)
  footer_reader.skip(footer_start + 4)
  let stored_crc = footer_reader.read_u32()
  let body_reader = @binary.BinaryReader::new(data)
  let body = body_reader.read_bytes(footer_start)
  let computed_crc = @binary.crc32_fast(body)
  stored_crc == computed_crc
}

///|
/// Decode all records from WAL data
pub fn decode_wal_records(data : Bytes) -> Array[WalRecord] {
  let records : Array[WalRecord] = []
  if data.length() < 8 {
    return records
  }
  let r = @binary.BinaryReader::new(data)
  // Verify header
  if not(verify_wal_header(r)) {
    return records
  }
  // Calculate body length
  let body_len = wal_body_length(data)
  // Read records
  while r.position() < body_len {
    match decode_wal_record(r) {
      None => break
      Some(record) => records.push(record)
    }
  }
  records
}
