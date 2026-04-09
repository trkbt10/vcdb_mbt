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
/// Format v3 (wal_version=0x03):
///   Header: same as v1 (version byte = 0x03)
///   Records: Type (1) + Flags (1) + Timestamp (8) + IDLen (1) + ID (IDLen bytes) + AttrsLen (4) + VectorLen (4) + Attrs + Vector
///   Footer: same as v1
///
/// Flags byte:
///   bit 0 (0x01) = has_timestamp  — always set in v2/v3
///   bit 1 (0x02) = has_128bit_id  — set in v3 when ID is Bytes16Id (IDLen=16)
///                                    absent in v3 when ID is Int64Id (IDLen=8)
///
/// Timestamp: nanoseconds since Unix epoch (Int64)
/// IDLen: 8 (Int64Id) or 16 (Bytes16Id)
///
/// v2/v3 reader can read v1 records (flags=0 → timestamp=0, id=8 bytes)
/// v3 reader can read v2 records (no has_128bit_id flag → IDLen=8)
/// v1 reader cannot read v2/v3 records (version check rejects)

///|
/// WAL Footer magic: "WCRC" in little-endian
pub let wal_footer_magic : UInt = 0x43524357U

///|
/// Current WAL format version
pub let wal_version : Byte = b'\x03'

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
  // Flags (1 byte) — v3: has_timestamp always set; has_128bit_id if Bytes16Id
  let flags = match record.id {
    @types.Bytes16Id(_) => flag_has_timestamp | flag_has_128bit_id
    @types.Int64Id(_) => flag_has_timestamp
  }
  w.push_byte(flags)
  // Timestamp (8 bytes, Int64 nanoseconds)
  w.push_i64(record.timestamp)
  // ID: IDLen(1) + payload(8 or 16 bytes)
  match record.id {
    @types.Int64Id(v) => {
      w.push_byte(b'\x08')
      w.push_u64(v.reinterpret_as_uint64())
    }
    @types.Bytes16Id(b) => {
      w.push_byte(b'\x10')
      w.push_byte(b.b0)
      w.push_byte(b.b1)
      w.push_byte(b.b2)
      w.push_byte(b.b3)
      w.push_byte(b.b4)
      w.push_byte(b.b5)
      w.push_byte(b.b6)
      w.push_byte(b.b7)
      w.push_byte(b.b8)
      w.push_byte(b.b9)
      w.push_byte(b.b10)
      w.push_byte(b.b11)
      w.push_byte(b.b12)
      w.push_byte(b.b13)
      w.push_byte(b.b14)
      w.push_byte(b.b15)
    }
  }
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
  //   v3: IDLen(1) + payload(IDLen bytes)
  let id : @types.VectorId = if has_128bit_id {
    // v3 only: 128-bit ID
    if r.remaining() < 1 {
      return None
    }
    let id_len = r.read_byte().to_int()
    if id_len != 16 || r.remaining() < 16 {
      return None
    }
    let b0 = r.read_byte()
    let b1 = r.read_byte()
    let b2 = r.read_byte()
    let b3 = r.read_byte()
    let b4 = r.read_byte()
    let b5 = r.read_byte()
    let b6 = r.read_byte()
    let b7 = r.read_byte()
    let b8 = r.read_byte()
    let b9 = r.read_byte()
    let b10 = r.read_byte()
    let b11 = r.read_byte()
    let b12 = r.read_byte()
    let b13 = r.read_byte()
    let b14 = r.read_byte()
    let b15 = r.read_byte()
    @types.Bytes16Id(@types.Bytes16::{
      b0,
      b1,
      b2,
      b3,
      b4,
      b5,
      b6,
      b7,
      b8,
      b9,
      b10,
      b11,
      b12,
      b13,
      b14,
      b15,
    })
  } else if version == wal_version {
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

  if !use_existing {
    w.push_bytes(encode_wal_header())
  }

  let new_body_len = wal_body_length(new_segment)
  match read_wal_version(new_segment) {
    None => ()
    Some(new_version) => {
      let r = @binary.BinaryReader::new(new_segment)
      r.skip(@codec.header_size)
      while r.position() < new_body_len {
        match decode_wal_record_versioned(r, new_version) {
          None => break
          // Re-encode in current (v3) format
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
/// Get safe copy length - up to the last decodable record boundary
/// Returns header length (12) if no records are decodable
fn get_safe_copy_length(data : Bytes) -> Int {
  let version = match read_wal_version(data) {
    None => return 0
    Some(v) => v
  }
  let r = @binary.BinaryReader::new(data)
  r.skip(@codec.header_size)
  let body_len = wal_body_length(data)
  let mut last_valid_pos = @codec.header_size
  while r.position() < body_len {
    match decode_wal_record_versioned(r, version) {
      None => break
      Some(_) => last_valid_pos = r.position()
    }
  }
  last_valid_pos
}

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
