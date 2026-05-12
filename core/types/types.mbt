///|
/// Distance/Similarity Metric.
/// - Cosine: vectors are normalized internally, score in [-1,1]
/// - L2: score is negative squared distance (higher is closer)
/// - Dot: raw dot product (higher is more similar)
pub(all) enum Metric {
  Cosine
  L2
  Dot
} derive(Eq, Debug)

///|
pub impl Show for Metric with output(self, logger) {
  match self {
    Cosine => logger.write_string("Cosine")
    L2 => logger.write_string("L2")
    Dot => logger.write_string("Dot")
  }
}

///|
/// Canonical string representation of a Metric.
pub fn Metric::to_name(self : Metric) -> String {
  match self {
    Cosine => "cosine"
    L2 => "l2"
    Dot => "dot"
  }
}

///|
/// Parse a Metric from its string representation.
pub fn Metric::from_name(s : String) -> Metric? {
  match s {
    "cosine" | "Cosine" => Some(Cosine)
    "l2" | "L2" => Some(L2)
    "dot" | "Dot" => Some(Dot)
    _ => None
  }
}

///|
/// 128-bit fixed-size byte array for UUID/ULID/Snowflake-extended ID representation.
/// Stored as big-endian bytes so lexicographic order matches time order for ULID.
pub(all) struct Bytes16 {
  b0 : Byte
  b1 : Byte
  b2 : Byte
  b3 : Byte
  b4 : Byte
  b5 : Byte
  b6 : Byte
  b7 : Byte
  b8 : Byte
  b9 : Byte
  b10 : Byte
  b11 : Byte
  b12 : Byte
  b13 : Byte
  b14 : Byte
  b15 : Byte
} derive(Debug)

///|
pub fn Bytes16::new(
  b0 : Byte,
  b1 : Byte,
  b2 : Byte,
  b3 : Byte,
  b4 : Byte,
  b5 : Byte,
  b6 : Byte,
  b7 : Byte,
  b8 : Byte,
  b9 : Byte,
  b10 : Byte,
  b11 : Byte,
  b12 : Byte,
  b13 : Byte,
  b14 : Byte,
  b15 : Byte,
) -> Bytes16 {
  { b0, b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12, b13, b14, b15 }
}

///|
pub impl Eq for Bytes16 with equal(self, other) {
  self.b0 == other.b0 &&
  self.b1 == other.b1 &&
  self.b2 == other.b2 &&
  self.b3 == other.b3 &&
  self.b4 == other.b4 &&
  self.b5 == other.b5 &&
  self.b6 == other.b6 &&
  self.b7 == other.b7 &&
  self.b8 == other.b8 &&
  self.b9 == other.b9 &&
  self.b10 == other.b10 &&
  self.b11 == other.b11 &&
  self.b12 == other.b12 &&
  self.b13 == other.b13 &&
  self.b14 == other.b14 &&
  self.b15 == other.b15
}

///|
pub fn Bytes16::compare(self : Bytes16, other : Bytes16) -> Int {
  let mut r = self.b0.to_int() - other.b0.to_int()
  if r != 0 {
    return r
  }
  r = self.b1.to_int() - other.b1.to_int()
  if r != 0 {
    return r
  }
  r = self.b2.to_int() - other.b2.to_int()
  if r != 0 {
    return r
  }
  r = self.b3.to_int() - other.b3.to_int()
  if r != 0 {
    return r
  }
  r = self.b4.to_int() - other.b4.to_int()
  if r != 0 {
    return r
  }
  r = self.b5.to_int() - other.b5.to_int()
  if r != 0 {
    return r
  }
  r = self.b6.to_int() - other.b6.to_int()
  if r != 0 {
    return r
  }
  r = self.b7.to_int() - other.b7.to_int()
  if r != 0 {
    return r
  }
  r = self.b8.to_int() - other.b8.to_int()
  if r != 0 {
    return r
  }
  r = self.b9.to_int() - other.b9.to_int()
  if r != 0 {
    return r
  }
  r = self.b10.to_int() - other.b10.to_int()
  if r != 0 {
    return r
  }
  r = self.b11.to_int() - other.b11.to_int()
  if r != 0 {
    return r
  }
  r = self.b12.to_int() - other.b12.to_int()
  if r != 0 {
    return r
  }
  r = self.b13.to_int() - other.b13.to_int()
  if r != 0 {
    return r
  }
  r = self.b14.to_int() - other.b14.to_int()
  if r != 0 {
    return r
  }
  self.b15.to_int() - other.b15.to_int()
}

///|
pub impl Hash for Bytes16 with hash_combine(self, hasher) {
  hasher.combine_byte(self.b0)
  hasher.combine_byte(self.b1)
  hasher.combine_byte(self.b2)
  hasher.combine_byte(self.b3)
  hasher.combine_byte(self.b4)
  hasher.combine_byte(self.b5)
  hasher.combine_byte(self.b6)
  hasher.combine_byte(self.b7)
  hasher.combine_byte(self.b8)
  hasher.combine_byte(self.b9)
  hasher.combine_byte(self.b10)
  hasher.combine_byte(self.b11)
  hasher.combine_byte(self.b12)
  hasher.combine_byte(self.b13)
  hasher.combine_byte(self.b14)
  hasher.combine_byte(self.b15)
}

///|
pub impl Show for Bytes16 with output(self, logger) {
  let hex = "0123456789abcdef"
  let chars : Array[Char] = []
  let bytes = [
    self.b0,
    self.b1,
    self.b2,
    self.b3,
    self.b4,
    self.b5,
    self.b6,
    self.b7,
    self.b8,
    self.b9,
    self.b10,
    self.b11,
    self.b12,
    self.b13,
    self.b14,
    self.b15,
  ]
  for i, b in bytes {
    if i == 4 || i == 6 || i == 8 || i == 10 {
      chars.push('-')
    }
    chars.push(hex.code_unit_at(b.to_int() >> 4).to_int().unsafe_to_char())
    chars.push(hex.code_unit_at(b.to_int() & 0xF).to_int().unsafe_to_char())
  }
  logger.write_string("Bytes16(\"")
  logger.write_string(String::from_array(chars[:]))
  logger.write_string("\")")
}

///|
/// Parse a UUID string (8-4-4-4-12 hex, with or without hyphens) into Bytes16.
pub fn Bytes16::from_uuid_string(s : String) -> Bytes16? {
  let digits : Array[Int] = []
  for c in s {
    match c {
      '-' => ()
      '0' => digits.push(0)
      '1' => digits.push(1)
      '2' => digits.push(2)
      '3' => digits.push(3)
      '4' => digits.push(4)
      '5' => digits.push(5)
      '6' => digits.push(6)
      '7' => digits.push(7)
      '8' => digits.push(8)
      '9' => digits.push(9)
      'a' | 'A' => digits.push(10)
      'b' | 'B' => digits.push(11)
      'c' | 'C' => digits.push(12)
      'd' | 'D' => digits.push(13)
      'e' | 'E' => digits.push(14)
      'f' | 'F' => digits.push(15)
      _ => return None
    }
  }
  if digits.length() != 32 {
    return None
  }
  let byte_at = fn(i : Int) -> Byte {
    ((digits[i * 2] << 4) | digits[i * 2 + 1]).to_byte()
  }
  Some(Bytes16::{
    b0: byte_at(0),
    b1: byte_at(1),
    b2: byte_at(2),
    b3: byte_at(3),
    b4: byte_at(4),
    b5: byte_at(5),
    b6: byte_at(6),
    b7: byte_at(7),
    b8: byte_at(8),
    b9: byte_at(9),
    b10: byte_at(10),
    b11: byte_at(11),
    b12: byte_at(12),
    b13: byte_at(13),
    b14: byte_at(14),
    b15: byte_at(15),
  })
}

///|
/// Format Bytes16 as a UUID string (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx).
pub fn Bytes16::to_uuid_string(self : Bytes16) -> String {
  let hex = "0123456789abcdef"
  let chars : Array[Char] = []
  let bytes = [
    self.b0,
    self.b1,
    self.b2,
    self.b3,
    self.b4,
    self.b5,
    self.b6,
    self.b7,
    self.b8,
    self.b9,
    self.b10,
    self.b11,
    self.b12,
    self.b13,
    self.b14,
    self.b15,
  ]
  for i, b in bytes {
    if i == 4 || i == 6 || i == 8 || i == 10 {
      chars.push('-')
    }
    chars.push(hex.code_unit_at(b.to_int() >> 4).to_int().unsafe_to_char())
    chars.push(hex.code_unit_at(b.to_int() & 0xF).to_int().unsafe_to_char())
  }
  String::from_array(chars[:])
}

///|
/// Construct a Bytes16 from two Int64 values (hi = bytes 0-7, lo = bytes 8-15),
/// both interpreted as big-endian. This is the canonical way to embed a
/// Snowflake-style or ULID timestamp+random payload into a 128-bit ID.
pub fn Bytes16::from_hi_lo(hi : Int64, lo : Int64) -> Bytes16 {
  let hu = hi.reinterpret_as_uint64()
  let lu = lo.reinterpret_as_uint64()
  {
    b0: ((hu >> 56) & 0xFFUL).to_int().to_byte(),
    b1: ((hu >> 48) & 0xFFUL).to_int().to_byte(),
    b2: ((hu >> 40) & 0xFFUL).to_int().to_byte(),
    b3: ((hu >> 32) & 0xFFUL).to_int().to_byte(),
    b4: ((hu >> 24) & 0xFFUL).to_int().to_byte(),
    b5: ((hu >> 16) & 0xFFUL).to_int().to_byte(),
    b6: ((hu >> 8) & 0xFFUL).to_int().to_byte(),
    b7: (hu & 0xFFUL).to_int().to_byte(),
    b8: ((lu >> 56) & 0xFFUL).to_int().to_byte(),
    b9: ((lu >> 48) & 0xFFUL).to_int().to_byte(),
    b10: ((lu >> 40) & 0xFFUL).to_int().to_byte(),
    b11: ((lu >> 32) & 0xFFUL).to_int().to_byte(),
    b12: ((lu >> 24) & 0xFFUL).to_int().to_byte(),
    b13: ((lu >> 16) & 0xFFUL).to_int().to_byte(),
    b14: ((lu >> 8) & 0xFFUL).to_int().to_byte(),
    b15: (lu & 0xFFUL).to_int().to_byte(),
  }
}

///|
/// Extract the two Int64 halves (big-endian) from a Bytes16.
pub fn Bytes16::to_hi_lo(self : Bytes16) -> (Int64, Int64) {
  let hi = (self.b0.to_int64() << 56) |
    (self.b1.to_int64() << 48) |
    (self.b2.to_int64() << 40) |
    (self.b3.to_int64() << 32) |
    (self.b4.to_int64() << 24) |
    (self.b5.to_int64() << 16) |
    (self.b6.to_int64() << 8) |
    self.b7.to_int64()
  let lo = (self.b8.to_int64() << 56) |
    (self.b9.to_int64() << 48) |
    (self.b10.to_int64() << 40) |
    (self.b11.to_int64() << 32) |
    (self.b12.to_int64() << 24) |
    (self.b13.to_int64() << 16) |
    (self.b14.to_int64() << 8) |
    self.b15.to_int64()
  (hi, lo)
}

///|
/// Vector ID — supports Int64 (legacy) and 128-bit (UUID/ULID/Snowflake-extended)
/// for distributed environments.
///
/// Int64Id sorts before Bytes16Id in Compare so mixed collections have a stable order.
pub(all) enum VectorId {
  /// 64-bit integer ID (legacy, backward-compatible with WAL v1/v2)
  Int64Id(Int64)
  /// 128-bit byte array ID (UUID, ULID, or any 16-byte identifier)
  Bytes16Id(Bytes16)
} derive(Debug)

///|
pub impl Show for VectorId with output(self, logger) {
  match self {
    Int64Id(v) => {
      logger.write_string("Int64Id(")
      Show::output(v, logger)
      logger.write_string(")")
    }
    Bytes16Id(b) => {
      logger.write_string("Bytes16Id(")
      Show::output(b, logger)
      logger.write_string(")")
    }
  }
}

///|
pub impl Eq for VectorId with equal(self, other) {
  match (self, other) {
    (Int64Id(a), Int64Id(b)) => a == b
    (Bytes16Id(a), Bytes16Id(b)) => a == b
    _ => false
  }
}

///|
pub fn VectorId::compare(self : VectorId, other : VectorId) -> Int {
  match (self, other) {
    (Int64Id(a), Int64Id(b)) => a.compare(b)
    (Bytes16Id(a), Bytes16Id(b)) => a.compare(b)
    // Int64Id sorts before Bytes16Id
    (Int64Id(_), Bytes16Id(_)) => -1
    (Bytes16Id(_), Int64Id(_)) => 1
  }
}

///|
pub impl Hash for VectorId with hash_combine(self, hasher) {
  match self {
    Int64Id(v) => {
      hasher.combine_int(0)
      hasher.combine_int64(v)
    }
    Bytes16Id(b) => {
      hasher.combine_int(1)
      Hash::hash_combine(b, hasher)
    }
  }
}

///|
/// Attribute value - supports common primitive types
pub(all) enum AttrValue {
  Null
  Bool(Bool)
  Int(Int64)
  Float(Double)
  String(String)
} derive(Eq, Debug)

///|
pub impl Show for AttrValue with output(self, logger) {
  match self {
    Null => logger.write_string("Null")
    Bool(b) => {
      logger.write_string("Bool(")
      Show::output(b, logger)
      logger.write_string(")")
    }
    Int(n) => {
      logger.write_string("Int(")
      Show::output(n, logger)
      logger.write_string(")")
    }
    Float(f) => {
      logger.write_string("Float(")
      Show::output(f, logger)
      logger.write_string(")")
    }
    String(s) => {
      logger.write_string("String(")
      Show::output(s, logger)
      logger.write_string(")")
    }
  }
}

///|
/// Attributes map - empty map as default
pub(all) struct Attrs(Map[String, AttrValue]) derive(Debug)

///|
pub impl Show for Attrs with output(self, logger) {
  Show::output(self.0, logger)
}

///|
/// Search result: id + score + attrs
pub(all) struct SearchHit {
  id : VectorId
  score : Double
  attrs : Attrs
} derive(Debug)

///|
pub impl Show for SearchHit with output(self, logger) {
  logger.write_string("{ id: ")
  Show::output(self.id, logger)
  logger.write_string(", score: ")
  Show::output(self.score, logger)
  logger.write_string(", attrs: ")
  Show::output(self.attrs, logger)
  logger.write_string(" }")
}

///|
/// Result returned by get(): vector and attrs for an id
pub(all) struct VectorRecord {
  vector : Array[Double]
  attrs : Attrs
} derive(Debug)

///|
pub impl Show for VectorRecord with output(self, logger) {
  logger.write_string("{ vector: ")
  Show::output(self.vector, logger)
  logger.write_string(", attrs: ")
  Show::output(self.attrs, logger)
  logger.write_string(" }")
}

///|
/// HNSW algorithm parameters
pub(all) struct HNSWParams {
  m : Int // default: 16
  ef_construction : Int // default: 200
  ef_search : Int // default: 50
  level_mult : Double // default: 1/ln(M)
  seed : UInt64 // default: 42
  allow_replace_deleted : Bool // default: false
} derive(Debug)

///|
pub impl Show for HNSWParams with output(self, logger) {
  logger.write_string("{ m: ")
  Show::output(self.m, logger)
  logger.write_string(", ef_construction: ")
  Show::output(self.ef_construction, logger)
  logger.write_string(", ef_search: ")
  Show::output(self.ef_search, logger)
  logger.write_string(", level_mult: ")
  Show::output(self.level_mult, logger)
  logger.write_string(", seed: ")
  Show::output(self.seed, logger)
  logger.write_string(", allow_replace_deleted: ")
  Show::output(self.allow_replace_deleted, logger)
  logger.write_string(" }")
}

///|
/// HNSW parameter constraints
pub let hnsw_m_min : Int = 2

///|
pub let hnsw_m_max : Int = 100

///|
pub let hnsw_ef_construction_min : Int = 1

///|
pub let hnsw_ef_construction_max : Int = 1000

///|
/// IVF algorithm parameters
pub(all) struct IVFParams {
  nlist : Int // default: 64
  nprobe : Int // default: sqrt(nlist)
} derive(Debug)

///|
pub impl Show for IVFParams with output(self, logger) {
  logger.write_string("{ nlist: ")
  Show::output(self.nlist, logger)
  logger.write_string(", nprobe: ")
  Show::output(self.nprobe, logger)
  logger.write_string(" }")
}

///|
/// IVF parameter constraints
pub let ivf_nlist_min : Int = 1

///|
pub let ivf_nlist_max : Int = 65536

///|
/// ANN strategy selection
pub(all) enum Strategy {
  Bruteforce
  HNSW(HNSWParams)
  IVF(IVFParams)
} derive(Debug)

///|
pub impl Show for Strategy with output(self, logger) {
  match self {
    Bruteforce => logger.write_string("Bruteforce")
    HNSW(params) => {
      logger.write_string("HNSW(")
      Show::output(params, logger)
      logger.write_string(")")
    }
    IVF(params) => {
      logger.write_string("IVF(")
      Show::output(params, logger)
      logger.write_string(")")
    }
  }
}

///|
/// Canonical string representation of a Strategy (name only, no params).
pub fn Strategy::to_name(self : Strategy) -> String {
  match self {
    Bruteforce => "bruteforce"
    HNSW(_) => "hnsw"
    IVF(_) => "ivf"
  }
}

///|
/// Parse a Strategy from its string representation (uses default params).
pub fn Strategy::from_name(s : String) -> Strategy? {
  match s {
    "bruteforce" | "Bruteforce" => Some(Bruteforce)
    "hnsw" | "HNSW" => Some(Strategy::default_hnsw())
    "ivf" | "IVF" => Some(Strategy::default_ivf())
    _ => None
  }
}

///|
/// Database construction options
pub(all) struct DatabaseOptions {
  dim : Int
  metric : Metric // default: Cosine
  capacity : Int // default: 1024
  strategy : Strategy // default: Bruteforce
} derive(Debug)

///|
pub impl Show for DatabaseOptions with output(self, logger) {
  logger.write_string("{ dim: ")
  Show::output(self.dim, logger)
  logger.write_string(", metric: ")
  Show::output(self.metric, logger)
  logger.write_string(", capacity: ")
  Show::output(self.capacity, logger)
  logger.write_string(", strategy: ")
  Show::output(self.strategy, logger)
  logger.write_string(" }")
}

///|
/// Create default HNSW params
pub fn HNSWParams::default() -> HNSWParams {
  {
    m: 16,
    ef_construction: 200,
    ef_search: 50,
    level_mult: 0.36067376022224085, // 1.0 / ln(16.0)
    seed: 42,
    allow_replace_deleted: false,
  }
}

///|
/// Create default IVF params
pub fn IVFParams::default() -> IVFParams {
  { nlist: 64, nprobe: 8 }
}

///|
/// Default HNSW strategy (most common use case).
pub fn Strategy::default_hnsw() -> Strategy {
  HNSW(HNSWParams::default())
}

///|
/// Default IVF strategy.
pub fn Strategy::default_ivf() -> Strategy {
  IVF(IVFParams::default())
}

///|
/// Create default database options
pub fn DatabaseOptions::default(dim : Int) -> DatabaseOptions {
  { dim, metric: Cosine, capacity: 1024, strategy: Bruteforce }
}

///|
/// Create empty attrs
pub fn empty_attrs() -> Attrs {
  Attrs({})
}

///|
/// Create VectorId from Int64 (backward-compatible constructor).
pub fn VectorId::from_int64(id : Int64) -> VectorId {
  Int64Id(id)
}

///|
/// Create VectorId from Int (backward-compatible constructor).
pub fn VectorId::from_int(id : Int) -> VectorId {
  Int64Id(id.to_int64())
}

///|
/// Create VectorId from Bytes16 (UUID/ULID/128-bit ID).
pub fn VectorId::from_bytes16(b : Bytes16) -> VectorId {
  Bytes16Id(b)
}

///|
/// Create VectorId from a UUID string.
pub fn VectorId::from_uuid_string(s : String) -> VectorId? {
  match Bytes16::from_uuid_string(s) {
    Some(b) => Some(Bytes16Id(b))
    None => None
  }
}

///|
/// Get the underlying Int64 value as an option. Returns None for Bytes16Id.
pub fn VectorId::as_int64(self : VectorId) -> Int64? {
  match self {
    Int64Id(v) => Some(v)
    Bytes16Id(_) => None
  }
}

///|
/// Get the underlying Bytes16 value. Returns None for Int64Id.
pub fn VectorId::as_bytes16(self : VectorId) -> Bytes16? {
  match self {
    Int64Id(_) => None
    Bytes16Id(b) => Some(b)
  }
}

///|
/// Format a VectorId as a human-readable string.
/// Int64Id: decimal integer string.
/// Bytes16Id: UUID string (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx).
pub fn VectorId::to_display_string(self : VectorId) -> String {
  match self {
    Int64Id(v) => v.to_string()
    Bytes16Id(b) => b.to_uuid_string()
  }
}

///|
/// Encode a VectorId as a 16-byte wire representation.
///
/// This is the canonical FFI wire format for VectorId.
/// - Int64Id(v): bytes 0-7 = v as big-endian Int64, bytes 8-15 = 0x00
/// - Bytes16Id(b): bytes 0-15 = b as-is
///
/// JS callers receive a Uint8Array(16) and must use VectorId::from_wire_bytes
/// to reconstruct the VectorId.
pub fn VectorId::to_wire_bytes(self : VectorId) -> Bytes {
  match self {
    Int64Id(v) => {
      let u = v.reinterpret_as_uint64()
      Bytes::makei(16, fn(i) {
        match i {
          0 => ((u >> 56) & 0xFFUL).to_int().to_byte()
          1 => ((u >> 48) & 0xFFUL).to_int().to_byte()
          2 => ((u >> 40) & 0xFFUL).to_int().to_byte()
          3 => ((u >> 32) & 0xFFUL).to_int().to_byte()
          4 => ((u >> 24) & 0xFFUL).to_int().to_byte()
          5 => ((u >> 16) & 0xFFUL).to_int().to_byte()
          6 => ((u >> 8) & 0xFFUL).to_int().to_byte()
          7 => (u & 0xFFUL).to_int().to_byte()
          _ => b'\x00'
        }
      })
    }
    Bytes16Id(b) => {
      let arr = [
        b.b0,
        b.b1,
        b.b2,
        b.b3,
        b.b4,
        b.b5,
        b.b6,
        b.b7,
        b.b8,
        b.b9,
        b.b10,
        b.b11,
        b.b12,
        b.b13,
        b.b14,
        b.b15,
      ]
      Bytes::from_array(arr[:])
    }
  }
}

///|
/// Decode a VectorId from a 16-byte wire representation.
///
/// Inverse of VectorId::to_wire_bytes.
/// - If bytes 8-15 are all 0x00, reconstructs as Int64Id (big-endian bytes 0-7).
/// - Otherwise reconstructs as Bytes16Id.
///
/// Returns None if data length is not exactly 16 bytes.
pub fn VectorId::from_wire_bytes(data : Bytes) -> VectorId? {
  if data.length() != 16 {
    return None
  }
  // Check if lower 8 bytes are all zero → Int64Id
  let lower_zero = data[8] == b'\x00' &&
    data[9] == b'\x00' &&
    data[10] == b'\x00' &&
    data[11] == b'\x00' &&
    data[12] == b'\x00' &&
    data[13] == b'\x00' &&
    data[14] == b'\x00' &&
    data[15] == b'\x00'
  if lower_zero {
    let v = (data[0].to_int64() << 56) |
      (data[1].to_int64() << 48) |
      (data[2].to_int64() << 40) |
      (data[3].to_int64() << 32) |
      (data[4].to_int64() << 24) |
      (data[5].to_int64() << 16) |
      (data[6].to_int64() << 8) |
      data[7].to_int64()
    Some(Int64Id(v))
  } else {
    Some(
      Bytes16Id(Bytes16::{
        b0: data[0],
        b1: data[1],
        b2: data[2],
        b3: data[3],
        b4: data[4],
        b5: data[5],
        b6: data[6],
        b7: data[7],
        b8: data[8],
        b9: data[9],
        b10: data[10],
        b11: data[11],
        b12: data[12],
        b13: data[13],
        b14: data[14],
        b15: data[15],
      }),
    )
  }
}

///|
/// Get a value from attrs
pub fn Attrs::get(self : Attrs, key : String) -> AttrValue? {
  self.0.get(key)
}

///|
/// Set a value in attrs
pub fn Attrs::set(self : Attrs, key : String, value : AttrValue) -> Unit {
  self.0.set(key, value)
}

///|
/// Check if attrs is empty
pub fn Attrs::is_empty(self : Attrs) -> Bool {
  self.0.is_empty()
}

///|
/// Get all keys from attrs
pub fn Attrs::keys(self : Attrs) -> Array[String] {
  self.0.keys().collect()
}

///|
/// Get size of attrs
pub fn Attrs::size(self : Attrs) -> Int {
  self.0.length()
}

///|
/// Clear all attrs
pub fn Attrs::clear(self : Attrs) -> Unit {
  self.0.clear()
}

///|
/// Create a defensive copy of attrs
pub fn Attrs::copy(self : Attrs) -> Attrs {
  let new_map : Map[String, AttrValue] = {}
  for k, v in self.0 {
    new_map.set(k, v)
  }
  Attrs(new_map)
}

///|
/// Numeric range for range queries
pub(all) struct NumericRange {
  gt : Double? // greater than
  gte : Double? // greater than or equal
  lt : Double? // less than
  lte : Double? // less than or equal
} derive(Debug)

///|
pub impl Show for NumericRange with output(self, logger) {
  logger.write_string("{ gt: ")
  Debug::to_repr(self.gt).output(logger)
  logger.write_string(", gte: ")
  Debug::to_repr(self.gte).output(logger)
  logger.write_string(", lt: ")
  Debug::to_repr(self.lt).output(logger)
  logger.write_string(", lte: ")
  Debug::to_repr(self.lte).output(logger)
  logger.write_string(" }")
}

///|
fn numeric_range(
  gt : Double?,
  gte : Double?,
  lt : Double?,
  lte : Double?,
) -> NumericRange {
  { gt, gte, lt, lte }
}

///|
pub fn NumericRange::empty() -> NumericRange {
  numeric_range(None, None, None, None)
}

///|
pub fn NumericRange::gt(value : Double) -> NumericRange {
  numeric_range(Some(value), None, None, None)
}

///|
pub fn NumericRange::gte(value : Double) -> NumericRange {
  numeric_range(None, Some(value), None, None)
}

///|
pub fn NumericRange::lt(value : Double) -> NumericRange {
  numeric_range(None, None, Some(value), None)
}

///|
pub fn NumericRange::lte(value : Double) -> NumericRange {
  numeric_range(None, None, None, Some(value))
}

///|
pub fn NumericRange::between(
  lower : Double,
  upper : Double,
  lower_inclusive? : Bool = true,
  upper_inclusive? : Bool = true,
) -> NumericRange {
  numeric_range(
    if lower_inclusive {
      None
    } else {
      Some(lower)
    },
    if lower_inclusive {
      Some(lower)
    } else {
      None
    },
    if upper_inclusive {
      None
    } else {
      Some(upper)
    },
    if upper_inclusive {
      Some(upper)
    } else {
      None
    },
  )
}

///|
pub fn NumericRange::matches(self : NumericRange, value : Double) -> Bool {
  match self.gt {
    Some(bound) => if value <= bound { return false }
    None => ()
  }
  match self.gte {
    Some(bound) => if value < bound { return false }
    None => ()
  }
  match self.lt {
    Some(bound) => if value >= bound { return false }
    None => ()
  }
  match self.lte {
    Some(bound) => if value > bound { return false }
    None => ()
  }
  true
}

///|
pub fn attr_value_to_number(value : AttrValue) -> Double? {
  match value {
    Int(n) => Some(n.to_double())
    Float(f) => Some(f)
    _ => None
  }
}
