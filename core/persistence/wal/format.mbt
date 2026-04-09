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
/// Format v3 (wal_version=0x03, legacy):
///   Header: same as v1 (version byte = 0x03)
///   Records: Type (1) + Flags (1) + Timestamp (8) + IDLen (1) + ID (IDLen bytes) + AttrsLen (4) + VectorLen (4) + Attrs + Vector
///   Footer: same as v1
///
/// Format v4 (wal_version=0x04, current):
///   Header: same as v1 (version byte = 0x04)
///   Records: Type (1) + Flags (1) + Timestamp (8) + IDWireLen (4) + ID (wire bytes) + AttrsLen (4) + VectorLen (4) + Attrs + Vector
///   Footer: same as v1
///   ID uses VectorId::to_wire_bytes() / from_wire_bytes() — SoT for all ID serialization.
///
/// Flags byte:
///   bit 0 (0x01) = has_timestamp  — always set in v2/v3/v4
///   bit 1 (0x02) = has_128bit_id  — v3 only (deprecated in v4)
///
/// v4 reader can read v1/v2/v3 records (version-aware decode).
/// v3 reader cannot read v4 records (IDWireLen is u32, not u8).

///|
/// WAL Footer magic: "WCRC" in little-endian
pub let wal_footer_magic : UInt = 0x43524357U

///|
/// Current WAL format version
pub let wal_version : Byte = b'\x04'

///|
/// V3 WAL version (for backward compatibility reads)
let wal_version_v3 : Byte = b'\x03'

///|
/// V2 WAL version (for backward compatibility reads)
let wal_version_v2 : Byte = b'\x02'

///|
/// V1 WAL version (for backward compatibility)
let wal_version_v1 : Byte = b'\x01'

///|
/// Flags
let flag_has_timestamp : Byte = b'\x01'

///|
/// Flag indicating the ID field is 128-bit (Bytes16Id). Absent = 8-byte Int64Id.
let flag_has_128bit_id : Byte = b'\x02'

///|
/// WAL record types
pub enum WalRecordType {
  Upsert // 1 - Insert or update vector with attrs
  Remove // 2 - Delete vector
  SetAttrs // 3 - Update attrs only
} derive(Eq)

///|
pub impl Show for WalRecordType with output(self, logger) {
  match self {
    Upsert => logger.write_string("Upsert")
    Remove => logger.write_string("Remove")
    SetAttrs => logger.write_string("SetAttrs")
  }
}

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
}

///|
pub impl Show for WalRecord with output(self, logger) {
  logger.write_string("{ record_type: ")
  Show::output(self.record_type, logger)
  logger.write_string(", id: ")
  Show::output(self.id, logger)
  logger.write_string(", attrs: ")
  Show::output(self.attrs, logger)
  logger.write_string(", vector: ")
  Show::output(self.vector, logger)
  logger.write_string(", timestamp: ")
  Show::output(self.timestamp, logger)
  logger.write_string(" }")
}

///|
/// Create an upsert record with timestamp
pub fn WalRecord::upsert(
  id : @types.VectorId,
  vector : Array[Double],
  attrs : @types.Attrs,
  timestamp? : Int64 = 0L,
) -> WalRecord {
  {
    record_type: Upsert,
    id,
    attrs: Some(attrs),
    vector: Some(vector),
    timestamp,
  }
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
/// Encode a WAL record to an existing writer (v3 format)
fn encode_wal_record_to(w : @binary.BinaryWriter, record : WalRecord) -> Unit {
  // Type (1 byte)
  w.push_byte(record.record_type.to_byte())
  // Flags (1 byte) — v4: has_timestamp only (ID type encoded in wire bytes)
  w.push_byte(flag_has_timestamp)
  // Timestamp (8 bytes, Int64 nanoseconds)
  w.push_i64(record.timestamp)
  // ID: length-prefixed wire bytes (SoT: VectorId::to_wire_bytes)
  let id_wire = record.id.to_wire_bytes()
  w.push_u32(id_wire.length().reinterpret_as_uint())
  w.push_bytes(id_wire)
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
/// Decode a WAL record from reader (public entry point — assumes v3 format).
/// For reading v1/v2 WAL files, use decode_wal_records which handles versioning.
pub fn decode_wal_record(r : @binary.BinaryReader) -> WalRecord? {
  decode_wal_record_versioned(r, wal_version)
}

///|
/// Version-aware WAL record decoder (v1, v2, v3).
///
/// v1: Type(1) + Reserved(1) + ID(8) + AttrsLen(4) + VectorLen(4) + ...
/// v2: Type(1) + Flags(1) + Timestamp(8) + ID(8) + AttrsLen(4) + VectorLen(4) + ...
/// v3: Type(1) + Flags(1) + Timestamp(8) + IDLen(1) + ID(IDLen) + AttrsLen(4) + VectorLen(4) + ...
fn decode_wal_record_versioned(
  r : @binary.BinaryReader,
  version : Byte,
) -> WalRecord? {
  if r.remaining() < 2 {
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
  let has_timestamp = flags.land(flag_has_timestamp) != b'\x00'
  let has_128bit_id = flags.land(flag_has_128bit_id) != b'\x00'
  // Timestamp (v2/v3) or absent (v1)
  let timestamp : Int64 = if has_timestamp {
    if r.remaining() < 8 {
      return None
    }
    r.read_i64()
  } else {
    0L
  }
  // ID field layout differs by version:
  //   v1: fixed 8 bytes (no IDLen byte, no timestamp)
  //   v2: fixed 8 bytes (no IDLen byte, has timestamp)
  //   v3: IDLen(1) + payload(IDLen bytes), flag_has_128bit_id for Bytes16Id
  //   v4: WireLen(u32=4) + wire bytes (SoT: VectorId::from_wire_bytes)
  let id : @types.VectorId = if version == wal_version {
    // v4: length-prefixed wire bytes
    if r.remaining() < 4 {
      return None
    }
    let wire_len = r.read_u32().reinterpret_as_int()
    if r.remaining() < wire_len {
      return None
    }
    match @types.VectorId::from_wire_bytes(r.read_bytes(wire_len)) {
      Some(v) => v
      None => return None
    }
  } else if has_128bit_id {
    // v3 only: 128-bit ID
    if r.remaining() < 1 {
      return None
    }
    let id_len = r.read_byte().to_int()
    if id_len != 16 || r.remaining() < 16 {
      return None
    }
    let wire = r.read_bytes(16)
    match @types.VectorId::from_wire_bytes(wire) {
      Some(v) => v
      None => return None
    }
  } else if version == wal_version_v3 {
    // v3 with Int64Id: IDLen(1) + 8 bytes
    if r.remaining() < 1 {
      return None
    }
    let id_len = r.read_byte().to_int()
    if id_len != 8 || r.remaining() < 8 {
      return None
    }
    @types.Int64Id(r.read_u64().reinterpret_as_int64())
  } else {
    // v1 or v2: fixed 8-byte ID (no IDLen byte)
    if r.remaining() < 8 {
      return None
    }
    @types.Int64Id(r.read_u64().reinterpret_as_int64())
  }
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
/// Verify WAL header (accepts v1, v2, and v3). Returns the version byte on success.
pub fn verify_wal_header(r : @binary.BinaryReader) -> Bool {
  match @codec.read_header(r) {
    None => false
    Some((file_type, version)) =>
      file_type == Wal &&
      (
        version == wal_version ||
        version == wal_version_v3 ||
        version == wal_version_v2 ||
        version == wal_version_v1
      )
  }
}

///|
/// Read the WAL version from a header, returning None if the header is invalid.
fn read_wal_version(data : Bytes) -> Byte? {
  if data.length() < @codec.header_size {
    return None
  }
  let r = @binary.BinaryReader::new(data)
  match @codec.read_header(r) {
    None => None
    Some((file_type, version)) =>
      if file_type == Wal &&
        (
          version == wal_version ||
          version == wal_version_v2 ||
          version == wal_version_v1
        ) {
        Some(version)
      } else {
        None
      }
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
/// Decode all records from WAL data (supports v1, v2, and v3)
pub fn decode_wal_records(data : Bytes) -> Array[WalRecord] {
  let records : Array[WalRecord] = []
  let version = match read_wal_version(data) {
    None => return records
    Some(v) => v
  }
  let r = @binary.BinaryReader::new(data)
  // Skip header (already validated by read_wal_version)
  r.skip(@codec.header_size)
  let body_len = wal_body_length(data)
  while r.position() < body_len {
    match decode_wal_record_versioned(r, version) {
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

  // Always write v4 header, then re-encode existing records in v4 format
  w.push_bytes(encode_wal_header())

  if existing.length() >= @codec.header_size {
    if verify_wal_checksum(existing) {
      let existing_body_len = wal_body_length(existing)
      match read_wal_version(existing) {
        None => ()
        Some(existing_version) => {
          let er = @binary.BinaryReader::new(existing)
          er.skip(@codec.header_size)
          while er.position() < existing_body_len {
            match decode_wal_record_versioned(er, existing_version) {
              None => break
              Some(record) => encode_wal_record_to(w, record)
            }
          }
          use_existing = true
        }
      }
    }
  }

  let _ = use_existing

  let new_body_len = wal_body_length(new_segment)
  match read_wal_version(new_segment) {
    None => ()
    Some(new_version) => {
      let r = @binary.BinaryReader::new(new_segment)
      r.skip(@codec.header_size)
      while r.position() < new_body_len {
        match decode_wal_record_versioned(r, new_version) {
          None => break
          // Re-encode in current (v4) format
          Some(record) => encode_wal_record_to(w, record)
        }
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

///|
/// Replay WAL binary data into a CoreStore (no Storage dependency).
/// This is the SoT for WAL replay logic. Used by:
/// - AsyncWalRuntime::replay_into (reads from AsyncStorage, then delegates here)
/// - JS persistent exports (passes WAL bytes directly)
///
/// Returns the number of records applied. Returns 0 for empty/invalid data.
pub fn replay_wal_data(
  data : Bytes,
  store : @store.CoreStore,
  cutoff_ts? : Int64 = 0L,
) -> Int {
  if data.length() < @codec.header_size {
    return 0
  }
  let header_reader = @binary.BinaryReader::new(data)
  if !verify_wal_header(header_reader) {
    return 0
  }
  if !verify_wal_checksum(data) {
    return 0
  }
  let records = if cutoff_ts > 0L {
    filter_wal_by_timestamp(data, cutoff_ts)
  } else {
    decode_wal_records(data)
  }
  let mut applied = 0
  for record in records {
    match record.record_type {
      Upsert =>
        match record.vector {
          None => ()
          Some(vector) => {
            let attrs = match record.attrs {
              None => @types.empty_attrs()
              Some(a) => a
            }
            let _ = store.add_or_update(record.id, vector, attrs, upsert=true)
            applied = applied + 1
          }
        }
      Remove => {
        let _ = store.remove_by_id(record.id)
        applied = applied + 1
      }
      SetAttrs =>
        match record.attrs {
          None => ()
          Some(attrs) => {
            let _ = store.update_attrs(record.id, attrs)
            applied = applied + 1
          }
        }
    }
  }
  applied
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
