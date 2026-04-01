///|
/// Write-Ahead Log (WAL) implementation
///
/// Format v1 (wal_version=0x01):
///   Header (12 bytes): Magic (8 bytes "VCDBMBT\0") + Type (1) + Version (1) + Reserved (2)
///   Records: Type (1) + Reserved (1) + ID (8) + AttrsLen (4) + VectorLen (4) + Attrs + Vector
///   Footer (8 bytes, optional): Magic (4 bytes) + CRC32 (4 bytes)
///
/// Format v2 (wal_version=0x02):
///   Header: same as v1 (version byte = 0x02)
///   Records: Type (1) + Flags (1) + Timestamp (8) + ID (8) + AttrsLen (4) + VectorLen (4) + Attrs + Vector
///   Footer: same as v1
///
/// Flags byte: bit 0 = has timestamp (always 1 in v2)
/// Timestamp: nanoseconds since Unix epoch (Int64)
///
/// v2 reader can read v1 records (flags=0 → timestamp=0)
/// v1 reader cannot read v2 records (version check rejects)

///|
/// WAL Footer magic: "WCRC" in little-endian
pub let wal_footer_magic : UInt = 0x43524357U

///|
/// Current WAL format version
pub let wal_version : Byte = b'\x02'

///|
/// V1 WAL version (for backward compatibility)
let wal_version_v1 : Byte = b'\x01'

///|
/// Flags
let flag_has_timestamp : Byte = b'\x01'

///|
/// WAL record types
pub enum WalRecordType {
  Upsert // 1 - Insert or update vector with attrs
  Remove // 2 - Delete vector
  SetAttrs // 3 - Update attrs only
} derive(Eq, Show)

///|
pub fn WalRecordType::to_byte(self : WalRecordType) -> Byte {
  match self {
    Upsert => b'\x01'
    Remove => b'\x02'
    SetAttrs => b'\x03'
  }
}

///|
pub fn WalRecordType::from_byte(b : Byte) -> WalRecordType? {
  match b {
    b'\x01' => Some(Upsert)
    b'\x02' => Some(Remove)
    b'\x03' => Some(SetAttrs)
    _ => None
  }
}

///|
/// WAL record with timestamp
pub struct WalRecord {
  record_type : WalRecordType
  id : @types.VectorId
  attrs : @types.Attrs?
  vector : Array[Double]?
  /// Nanoseconds since Unix epoch. 0 = no timestamp (v1 compatibility).
  timestamp : Int64
} derive(Show)

///|
/// Create an upsert record with timestamp
pub fn WalRecord::upsert(
  id : @types.VectorId,
  vector : Array[Double],
  attrs : @types.Attrs,
  timestamp? : Int64 = 0L,
) -> WalRecord {
  { record_type: Upsert, id, attrs: Some(attrs), vector: Some(vector), timestamp }
}

///|
/// Create a remove record with timestamp
pub fn WalRecord::remove(
  id : @types.VectorId,
  timestamp? : Int64 = 0L,
) -> WalRecord {
  { record_type: Remove, id, attrs: None, vector: None, timestamp }
}

///|
/// Create a set_attrs record with timestamp
pub fn WalRecord::set_attrs(
  id : @types.VectorId,
  attrs : @types.Attrs,
  timestamp? : Int64 = 0L,
) -> WalRecord {
  { record_type: SetAttrs, id, attrs: Some(attrs), vector: None, timestamp }
}

///|
fn encode_attrs_json(attrs : @types.Attrs?) -> Bytes {
  @codec.encode_attrs_json(attrs)
}

///|
fn decode_attrs_json(bytes : Bytes) -> @types.Attrs? {
  @codec.decode_attrs_json(bytes)
}

///|
/// Encode a WAL record to bytes (v2 format with timestamp)
pub fn encode_wal_record(record : WalRecord) -> Bytes {
  let w = @binary.BinaryWriter::new()
  encode_wal_record_to(w, record)
  w.concat()
}

///|
/// Encode a WAL record to an existing writer (v2 format)
fn encode_wal_record_to(w : @binary.BinaryWriter, record : WalRecord) -> Unit {
  // Type (1 byte)
  w.push_byte(record.record_type.to_byte())
  // Flags (1 byte) — v2: always has timestamp
  w.push_byte(flag_has_timestamp)
  // Timestamp (8 bytes, Int64 nanoseconds)
  w.push_i64(record.timestamp)
  // ID (8 bytes)
  w.push_u64(record.id.to_int64().reinterpret_as_uint64())
  // Attrs
  let attrs_bytes = encode_attrs_json(record.attrs)
  let vector_len = match record.vector {
    None => 0
    Some(v) => v.length() * 4
  }
  w.push_u32(attrs_bytes.length().reinterpret_as_uint())
  w.push_u32(vector_len.reinterpret_as_uint())
  w.push_bytes(attrs_bytes)
  match record.vector {
    None => ()
    Some(v) =>
      for val in v {
        w.push_f32(Float::from_double(val))
      }
  }
}

///|
/// Decode a WAL record from reader (supports both v1 and v2)
pub fn decode_wal_record(r : @binary.BinaryReader) -> WalRecord? {
  if r.remaining() < 18 {
    return None
  }
  // Type
  let type_byte = r.read_byte()
  let record_type = match WalRecordType::from_byte(type_byte) {
    None => return None
    Some(t) => t
  }
  // Flags/Reserved
  let flags = r.read_byte()
  // Timestamp (v2) or skip (v1)
  let timestamp : Int64 = if flags.land(flag_has_timestamp) != b'\x00' {
    // v2: read 8-byte timestamp
    if r.remaining() < 24 {
      // Need: timestamp(8) + id(8) + attrs_len(4) + vector_len(4)
      return None
    }
    r.read_i64()
  } else {
    // v1: no timestamp, flags byte was reserved=0x00
    0L
  }
  // ID (8 bytes)
  if r.remaining() < 16 {
    return None
  }
  let id = @types.VectorId(r.read_u64().reinterpret_as_int64())
  // Lengths
  let attrs_len = r.read_u32().reinterpret_as_int()
  let vector_len = r.read_u32().reinterpret_as_int()
  if attrs_len < 0 || vector_len < 0 || r.remaining() < attrs_len + vector_len {
    return None
  }
  // Attrs
  let attrs = if attrs_len > 0 {
    let attrs_bytes = r.read_bytes(attrs_len)
    decode_attrs_json(attrs_bytes)
  } else {
    None
  }
  // Vector
  let vector = if vector_len > 0 {
    if vector_len % 4 != 0 {
      return None
    }
    let vec : Array[Double] = []
    let count = vector_len / 4
    for _ in 0..<count {
      vec.push(r.read_f32().to_double())
    }
    Some(vec)
  } else {
    None
  }
  Some({ record_type, id, attrs, vector, timestamp })
}

///|
/// Encode WAL header (12 bytes)
pub fn encode_wal_header() -> Bytes {
  let w = @binary.BinaryWriter::new()
  @codec.encode_header(w, Wal, wal_version)
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
  @codec.encode_header(w, Wal, wal_version)
  for record in records {
    encode_wal_record_to(w, record)
  }
  let body = w.concat()
  w.push_u32(wal_footer_magic)
  w.push_u32(@binary.crc32_fast(body))
  w.concat()
}

///|
/// Verify WAL header (accepts both v1 and v2)
pub fn verify_wal_header(r : @binary.BinaryReader) -> Bool {
  match @codec.read_header(r) {
    None => false
    Some((file_type, version)) =>
      file_type == Wal && (version == wal_version || version == wal_version_v1)
  }
}

///|
fn wal_footer_start(data : Bytes) -> Int? {
  if data.length() < @codec.header_size + 8 {
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
fn wal_body_length(data : Bytes) -> Int {
  match wal_footer_start(data) {
    Some(footer_start) => footer_start
    None => data.length()
  }
}

///|
/// Check if WAL has valid footer and verify CRC32
pub fn verify_wal_checksum(data : Bytes) -> Bool {
  if data.length() < @codec.header_size {
    return false
  }
  if data.length() < @codec.header_size + 8 {
    return true
  }
  let footer_start = match wal_footer_start(data) {
    None => return true
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
/// Decode all records from WAL data (supports v1 and v2)
pub fn decode_wal_records(data : Bytes) -> Array[WalRecord] {
  let records : Array[WalRecord] = []
  if data.length() < @codec.header_size {
    return records
  }
  let r = @binary.BinaryReader::new(data)
  if not(verify_wal_header(r)) {
    return records
  }
  let body_len = wal_body_length(data)
  while r.position() < body_len {
    match decode_wal_record(r) {
      None => break
      Some(record) => records.push(record)
    }
  }
  records
}

///|
/// Merge an existing WAL with a new WAL segment (SoT for WAL merge).
pub fn merge_wal(existing : Bytes, new_segment : Bytes) -> Bytes {
  let w = @binary.BinaryWriter::new()
  let mut use_existing = false

  if existing.length() >= @codec.header_size {
    if verify_wal_checksum(existing) {
      let safe_len = get_safe_copy_length(existing)
      if safe_len >= @codec.header_size {
        for i in 0..<safe_len {
          w.push_byte(existing[i])
        }
        use_existing = true
      }
    }
  }

  if not(use_existing) {
    w.push_bytes(encode_wal_header())
  }

  let new_body_len = wal_body_length(new_segment)
  if new_segment.length() >= @codec.header_size {
    let r = @binary.BinaryReader::new(new_segment)
    r.skip(@codec.header_size)
    while r.position() < new_body_len {
      match decode_wal_record(r) {
        None => break
        Some(record) => encode_wal_record_to(w, record)
      }
    }
  }

  let body = w.concat()
  let footer = encode_wal_footer(body)
  let final_w = @binary.BinaryWriter::new()
  final_w.push_bytes(body)
  final_w.push_bytes(footer)
  final_w.concat()
}

///|
/// Filter WAL records by timestamp — returns only records with timestamp <= cutoff.
/// Used for read-at-timestamp (consistent cross-shard reads).
pub fn filter_wal_by_timestamp(
  data : Bytes,
  cutoff_ts : Int64,
) -> Array[WalRecord] {
  let all = decode_wal_records(data)
  let filtered : Array[WalRecord] = []
  for record in all {
    // timestamp=0 means v1 record (no timestamp) — always include
    if record.timestamp == 0L || record.timestamp <= cutoff_ts {
      filtered.push(record)
    }
  }
  filtered
}

///|
/// Get the maximum timestamp across all records in a WAL.
/// Returns 0 if no timestamped records.
pub fn max_wal_timestamp(data : Bytes) -> Int64 {
  let records = decode_wal_records(data)
  let mut max_ts = 0L
  for record in records {
    if record.timestamp > max_ts {
      max_ts = record.timestamp
    }
  }
  max_ts
}
