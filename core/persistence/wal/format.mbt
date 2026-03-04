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
  let json = attrs_to_json(attrs)
  string_to_utf8(json)
}

///|
/// Convert attrs to JSON string
fn attrs_to_json(attrs : @core.Attrs?) -> String {
  match attrs {
    None => "null"
    Some(a) => {
      let parts : Array[String] = []
      for key in a.keys() {
        match a.get(key) {
          None => continue
          Some(value) => {
            let value_json = attr_value_to_json(value)
            parts.push("\"" + escape_json_string(key) + "\":" + value_json)
          }
        }
      }
      "{" +
      parts.iter().intersperse(",").fold(init="", fn(acc, s) { acc + s }) +
      "}"
    }
  }
}

///|
/// Convert AttrValue to JSON string
fn attr_value_to_json(value : @core.AttrValue) -> String {
  match value {
    Null => "null"
    Bool(b) => if b { "true" } else { "false" }
    Int(n) => n.to_string()
    Float(f) => f.to_string()
    String(s) => "\"" + escape_json_string(s) + "\""
  }
}

///|
/// Escape special characters in JSON string
/// Escapes all control characters (U+0000..U+001F) per JSON spec
fn escape_json_string(s : String) -> String {
  let chars : Array[Char] = []
  for c in s {
    let code = c.to_uint()
    match c {
      '"' => {
        chars.push('\\')
        chars.push('"')
      }
      '\\' => {
        chars.push('\\')
        chars.push('\\')
      }
      '\n' => {
        chars.push('\\')
        chars.push('n')
      }
      '\r' => {
        chars.push('\\')
        chars.push('r')
      }
      '\t' => {
        chars.push('\\')
        chars.push('t')
      }
      '\u0008' => {
        // Backspace
        chars.push('\\')
        chars.push('b')
      }
      '\u000C' => {
        // Form feed
        chars.push('\\')
        chars.push('f')
      }
      _ =>
        if code < 0x20U {
          // Other control characters: escape as \uXXXX
          chars.push('\\')
          chars.push('u')
          chars.push('0')
          chars.push('0')
          chars.push(hex_digit((code >> 4) & 0xFU))
          chars.push(hex_digit(code & 0xFU))
        } else {
          chars.push(c)
        }
    }
  }
  String::from_array(chars)
}

///|
/// Convert a nibble (0-15) to hex digit
fn hex_digit(n : UInt) -> Char {
  if n < 10U {
    (n + 48U).reinterpret_as_int().unsafe_to_char() // '0' + n
  } else {
    (n - 10U + 97U).reinterpret_as_int().unsafe_to_char() // 'a' + (n - 10)
  }
}

///|
/// Convert string to UTF-8 bytes
fn string_to_utf8(s : String) -> Bytes {
  let w = @core.BinaryWriter::new()
  for c in s {
    let code = c.to_uint()
    if code < 0x80U {
      w.push_byte(code.to_byte())
    } else if code < 0x800U {
      w.push_byte((0xC0U | (code >> 6)).to_byte())
      w.push_byte((0x80U | (code & 0x3FU)).to_byte())
    } else if code < 0x10000U {
      w.push_byte((0xE0U | (code >> 12)).to_byte())
      w.push_byte((0x80U | ((code >> 6) & 0x3FU)).to_byte())
      w.push_byte((0x80U | (code & 0x3FU)).to_byte())
    } else {
      w.push_byte((0xF0U | (code >> 18)).to_byte())
      w.push_byte((0x80U | ((code >> 12) & 0x3FU)).to_byte())
      w.push_byte((0x80U | ((code >> 6) & 0x3FU)).to_byte())
      w.push_byte((0x80U | (code & 0x3FU)).to_byte())
    }
  }
  w.concat()
}

///|
/// Convert UTF-8 bytes to string
fn utf8_to_string(bytes : Bytes) -> String {
  let chars : Array[Char] = []
  let mut i = 0
  while i < bytes.length() {
    let b0 = bytes[i].to_uint()
    if b0 < 0x80U {
      chars.push(b0.reinterpret_as_int().unsafe_to_char())
      i = i + 1
    } else if b0 < 0xE0U && i + 1 < bytes.length() {
      let b1 = bytes[i + 1].to_uint()
      let code = ((b0 & 0x1FU) << 6) | (b1 & 0x3FU)
      chars.push(code.reinterpret_as_int().unsafe_to_char())
      i = i + 2
    } else if b0 < 0xF0U && i + 2 < bytes.length() {
      let b1 = bytes[i + 1].to_uint()
      let b2 = bytes[i + 2].to_uint()
      let code = ((b0 & 0x0FU) << 12) | ((b1 & 0x3FU) << 6) | (b2 & 0x3FU)
      chars.push(code.reinterpret_as_int().unsafe_to_char())
      i = i + 3
    } else if i + 3 < bytes.length() {
      let b1 = bytes[i + 1].to_uint()
      let b2 = bytes[i + 2].to_uint()
      let b3 = bytes[i + 3].to_uint()
      let code = ((b0 & 0x07U) << 18) |
        ((b1 & 0x3FU) << 12) |
        ((b2 & 0x3FU) << 6) |
        (b3 & 0x3FU)
      chars.push(code.reinterpret_as_int().unsafe_to_char())
      i = i + 4
    } else {
      i = i + 1
    }
  }
  String::from_array(chars)
}

///|
/// Decode JSON string to attrs
fn decode_attrs_json(bytes : Bytes) -> @core.Attrs? {
  if bytes.length() == 0 {
    return None
  }
  let json = utf8_to_string(bytes)
  parse_json_object(json)
}

///|
/// Simple JSON object parser for attrs
fn parse_json_object(json : String) -> @core.Attrs? {
  let json = json.trim(chars=" \t\n\r").to_string()
  if json == "null" {
    return None
  }
  if not(json.has_prefix("{")) || not(json.has_suffix("}")) {
    return None
  }
  let attrs = @core.empty_attrs()
  let content = json.unsafe_substring(start=1, end=json.length() - 1)
  if content.trim(chars=" \t\n\r").length() == 0 {
    return Some(attrs)
  }
  // Simple key-value parser
  let mut i = 0
  let chars = content.to_array()
  while i < chars.length() {
    // Skip whitespace
    while i < chars.length() &&
          (
            chars[i] == ' ' ||
            chars[i] == '\t' ||
            chars[i] == '\n' ||
            chars[i] == '\r'
          ) {
      i = i + 1
    }
    if i >= chars.length() {
      break
    }
    // Parse key
    if chars[i] != '"' {
      break
    }
    let (key, new_i) = parse_json_string(chars, i)
    i = new_i
    // Skip colon
    while i < chars.length() &&
          (chars[i] == ' ' || chars[i] == '\t' || chars[i] == ':') {
      i = i + 1
    }
    // Parse value
    let (value, new_i2) = parse_json_value(chars, i)
    i = new_i2
    attrs.set(key, value)
    // Skip comma
    while i < chars.length() &&
          (
            chars[i] == ' ' ||
            chars[i] == '\t' ||
            chars[i] == ',' ||
            chars[i] == '\n' ||
            chars[i] == '\r'
          ) {
      i = i + 1
    }
  }
  Some(attrs)
}

///|
/// Parse JSON string starting at index i
fn parse_json_string(chars : Array[Char], start : Int) -> (String, Int) {
  let mut i = start + 1 // Skip opening quote
  let result : Array[Char] = []
  while i < chars.length() && chars[i] != '"' {
    if chars[i] == '\\' && i + 1 < chars.length() {
      i = i + 1
      match chars[i] {
        'n' => result.push('\n')
        'r' => result.push('\r')
        't' => result.push('\t')
        'b' => result.push('\u0008') // Backspace
        'f' => result.push('\u000C') // Form feed
        '"' => result.push('"')
        '\\' => result.push('\\')
        'u' =>
          // Unicode escape: \uXXXX
          if i + 4 < chars.length() {
            let h1 = hex_char_value(chars[i + 1])
            let h2 = hex_char_value(chars[i + 2])
            let h3 = hex_char_value(chars[i + 3])
            let h4 = hex_char_value(chars[i + 4])
            let code = (h1 << 12) | (h2 << 8) | (h3 << 4) | h4
            result.push(code.unsafe_to_char())
            i = i + 4
          } else {
            result.push('u')
          }
        _ => result.push(chars[i])
      }
    } else {
      result.push(chars[i])
    }
    i = i + 1
  }
  (String::from_array(result), i + 1) // Skip closing quote
}

///|
/// Convert hex character to value (0-15)
fn hex_char_value(c : Char) -> Int {
  let code = c.to_uint().reinterpret_as_int()
  if code >= 48 && code <= 57 {
    // '0'-'9'
    code - 48
  } else if code >= 97 && code <= 102 {
    // 'a'-'f'
    code - 97 + 10
  } else if code >= 65 && code <= 70 {
    // 'A'-'F'
    code - 65 + 10
  } else {
    0
  }
}

///|
/// Parse JSON value starting at index i
fn parse_json_value(chars : Array[Char], start : Int) -> (@core.AttrValue, Int) {
  let mut i = start
  // Skip whitespace
  while i < chars.length() &&
        (
          chars[i] == ' ' ||
          chars[i] == '\t' ||
          chars[i] == '\n' ||
          chars[i] == '\r'
        ) {
    i = i + 1
  }
  if i >= chars.length() {
    return (Null, i)
  }
  match chars[i] {
    '"' => {
      let (s, new_i) = parse_json_string(chars, i)
      (String(s), new_i)
    }
    't' =>
      // true
      (Bool(true), i + 4)
    'f' =>
      // false
      (Bool(false), i + 5)
    'n' =>
      // null
      (Null, i + 4)
    '-' | '0' | '1' | '2' | '3' | '4' | '5' | '6' | '7' | '8' | '9' => {
      let num_start = i
      let mut has_dot = false
      while i < chars.length() &&
            (
              chars[i] == '-' ||
              chars[i] == '+' ||
              chars[i] == '.' ||
              chars[i] == 'e' ||
              chars[i] == 'E' ||
              (chars[i] >= '0' && chars[i] <= '9')
            ) {
        if chars[i] == '.' || chars[i] == 'e' || chars[i] == 'E' {
          has_dot = true // Also treat exponent notation as float
        }
        i = i + 1
      }
      let num_str = String::from_array(chars[num_start:i])
      if has_dot {
        let result : Result[Double, _] = try? @strconv.parse_double(num_str)
        match result {
          Ok(f) => (Float(f), i)
          Err(_) => (Null, i)
        }
      } else {
        let result : Result[Int64, _] = try? @strconv.parse_int64(num_str)
        match result {
          Ok(n) => (Int(n), i)
          Err(_) => (Null, i)
        }
      }
    }
    _ => (Null, i + 1)
  }
}

///|
/// Encode a WAL record to bytes
/// Note: Uses 64-bit IDs to preserve full VectorId range
pub fn encode_wal_record(record : WalRecord) -> Bytes {
  let w = @core.BinaryWriter::new()
  // Type (1 byte)
  w.push_byte(record.record_type.to_byte())
  // Reserved (1 byte)
  w.push_byte(b'\x00')
  // ID (8 bytes as u64 to preserve full Int64 range)
  w.push_u64(record.id.to_int64().reinterpret_as_uint64())
  // Encode attrs as JSON
  let attrs_bytes = encode_attrs_json(record.attrs)
  // Encode vector as Float32 (TypeScript compatible)
  let vector_bytes = match record.vector {
    None => Bytes::new(0)
    Some(v) => {
      let vw = @core.BinaryWriter::new()
      for val in v {
        vw.push_f32(Float::from_double(val))
      }
      vw.concat()
    }
  }
  // Write lengths
  w.push_u32(attrs_bytes.length().reinterpret_as_uint())
  w.push_u32(vector_bytes.length().reinterpret_as_uint())
  // Write data
  w.push_bytes(attrs_bytes)
  w.push_bytes(vector_bytes)
  w.concat()
}

///|
/// Decode a WAL record from reader
/// Note: Uses 64-bit IDs to preserve full VectorId range
pub fn decode_wal_record(r : @core.BinaryReader) -> WalRecord? {
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
  let w = @core.BinaryWriter::new()
  w.push_u32(wal_magic)
  w.push_u32(wal_version)
  w.concat()
}

///|
/// Encode WAL footer with CRC32
pub fn encode_wal_footer(body : Bytes) -> Bytes {
  let w = @core.BinaryWriter::new()
  w.push_u32(wal_footer_magic)
  w.push_u32(@core.crc32(body))
  w.concat()
}

///|
/// Encode multiple records to a complete WAL segment
pub fn encode_wal_segment(records : Array[WalRecord]) -> Bytes {
  let w = @core.BinaryWriter::new()
  // Write header
  w.push_bytes(encode_wal_header())
  // Write records
  for record in records {
    w.push_bytes(encode_wal_record(record))
  }
  // Get body (header + records)
  let body = w.concat()
  // Add footer with CRC32
  let footer = encode_wal_footer(body)
  // Combine
  let result = @core.BinaryWriter::new()
  result.push_bytes(body)
  result.push_bytes(footer)
  result.concat()
}

///|
/// Verify WAL header
pub fn verify_wal_header(r : @core.BinaryReader) -> Bool {
  let magic = r.read_u32()
  let version = r.read_u32()
  magic == wal_magic && version == wal_version
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
  // Check footer magic
  let footer_start = data.length() - 8
  let r = @core.BinaryReader::new(data)
  let _ = r.read_bytes(footer_start)
  let footer_magic = r.read_u32()
  if footer_magic != wal_footer_magic {
    return true // No footer, assume valid
  }
  let stored_crc = r.read_u32()
  let body_reader = @core.BinaryReader::new(data)
  let body = body_reader.read_bytes(footer_start)
  let computed_crc = @core.crc32(body)
  stored_crc == computed_crc
}

///|
/// Decode all records from WAL data
pub fn decode_wal_records(data : Bytes) -> Array[WalRecord] {
  let records : Array[WalRecord] = []
  if data.length() < 8 {
    return records
  }
  let r = @core.BinaryReader::new(data)
  // Verify header
  if not(verify_wal_header(r)) {
    return records
  }
  // Calculate body length
  let body_len = if data.length() >= 16 {
    let footer_check = @core.BinaryReader::new(data)
    let _ = footer_check.read_bytes(data.length() - 8)
    let footer_magic = footer_check.read_u32()
    if footer_magic == wal_footer_magic {
      data.length() - 8
    } else {
      data.length()
    }
  } else {
    data.length()
  }
  // Read records
  while r.position() < body_len {
    match decode_wal_record(r) {
      None => break
      Some(record) => records.push(record)
    }
  }
  records
}
