///|
/// Data Segment - Binary format for storing vectors in distributed segments
/// Format: Header (8 bytes) + Records
/// Header: Magic (4 bytes "VSEG") + Version (4 bytes)
/// Record: ID (8 bytes) + AttrsLen (4 bytes) + VectorLen (4 bytes) + Attrs + Vector

///|
/// Segment magic number: "VSEG" in little-endian
pub let segment_magic : UInt = 0x47455356U

///|
/// Segment format version
pub let segment_version : UInt = 1U

///|
/// Data pointer - reference to a record within a segment
pub(all) struct DataPointer {
  segment : String // Segment name
  offset : Int // Byte offset within segment
  length : Int // Record length in bytes
} derive(Show, Eq)

///|
/// Index entry - mapping from vector ID to data location
pub(all) struct IndexEntry {
  id : @core.VectorId
  ptr : DataPointer
} derive(Show)

///|
/// Segment writer - builds a segment in memory
pub struct SegmentWriter {
  name : String
  buffer : @binary.BinaryWriter
  mut size : Int
}

///|
/// Create a new segment writer
pub fn SegmentWriter::new(name : String) -> SegmentWriter {
  let buffer = @binary.BinaryWriter::new()
  // Write header
  buffer.push_u32(segment_magic)
  buffer.push_u32(segment_version)
  { name, buffer, size: 8 }
}

///|
/// Append a record to the segment
/// Returns DataPointer to the appended record
pub fn SegmentWriter::append(
  self : SegmentWriter,
  id : @core.VectorId,
  vector : Array[Double],
  attrs : @core.Attrs,
) -> DataPointer {
  let offset = self.size
  let w = @binary.BinaryWriter::new()

  // Write ID (8 bytes)
  w.push_u64(id.to_int64().reinterpret_as_uint64())

  // Encode attrs as JSON
  let attrs_bytes = encode_attrs_for_segment(attrs)
  w.push_u32(attrs_bytes.length().reinterpret_as_uint())

  // Encode vector as Float32
  let vector_len = vector.length() * 4
  w.push_u32(vector_len.reinterpret_as_uint())

  // Write attrs
  w.push_bytes(attrs_bytes)

  // Write vector
  for val in vector {
    w.push_f32(Float::from_double(val))
  }

  let record_bytes = w.concat()
  let length = record_bytes.length()

  self.buffer.push_bytes(record_bytes)
  self.size = self.size + length

  { segment: self.name, offset, length }
}

///|
/// Get the segment data
pub fn SegmentWriter::to_bytes(self : SegmentWriter) -> Bytes {
  self.buffer.concat()
}

///|
/// Get the segment name
pub fn SegmentWriter::get_name(self : SegmentWriter) -> String {
  self.name
}

///|
/// Segment reader - reads records from a segment
pub struct SegmentReader {
  name : String
  data : Bytes
}

///|
/// Create a segment reader from bytes
pub fn SegmentReader::from_bytes(name : String, data : Bytes) -> SegmentReader? {
  if data.length() < 8 {
    return None
  }
  let r = @binary.BinaryReader::new(data)
  let magic = r.read_u32()
  let version = r.read_u32()
  if magic != segment_magic || version != segment_version {
    return None
  }
  Some({ name, data })
}

///|
/// Read record at specific offset
pub fn SegmentReader::read_at(
  self : SegmentReader,
  offset : Int,
  length : Int,
) -> (@core.VectorId, Array[Double], @core.Attrs)? {
  if offset + length > self.data.length() {
    return None
  }

  // Create a reader starting at offset
  let record_bytes : Array[Byte] = []
  for i in offset..<(offset + length) {
    record_bytes.push(self.data[i])
  }
  let r = @binary.BinaryReader::new(Bytes::from_array(record_bytes))

  // Read ID
  let id = @core.VectorId(r.read_u64().reinterpret_as_int64())

  // Read lengths
  let attrs_len = r.read_u32().reinterpret_as_int()
  let vector_len = r.read_u32().reinterpret_as_int()

  // Read attrs
  let attrs = if attrs_len > 0 {
    let attrs_bytes = r.read_bytes(attrs_len)
    decode_attrs_from_segment(attrs_bytes)
  } else {
    @core.empty_attrs()
  }

  // Read vector
  let count = vector_len / 4
  let vector : Array[Double] = []
  for _ in 0..<count {
    vector.push(r.read_f32().to_double())
  }

  Some((id, vector, attrs))
}

///|
/// Collect all records in the segment into an array
pub fn SegmentReader::collect(
  self : SegmentReader,
) -> Array[(@core.VectorId, Array[Double], @core.Attrs)] {
  let results : Array[(@core.VectorId, Array[Double], @core.Attrs)] = []
  let mut pos = 8 // Skip header
  while pos < self.data.length() {
    // Read record header to get length
    if pos + 16 > self.data.length() {
      break
    }
    let r = @binary.BinaryReader::new(self.data)
    let _ = r.read_bytes(pos)
    let _ = r.read_u64() // id
    let attrs_len = r.read_u32().reinterpret_as_int()
    let vector_len = r.read_u32().reinterpret_as_int()
    let length = 16 + attrs_len + vector_len

    match self.read_at(pos, length) {
      Some((id, vec, attrs)) => results.push((id, vec, attrs))
      None => break
    }
    pos = pos + length
  }
  results
}

///|
/// Iterate over all records in the segment
pub fn SegmentReader::iter(
  self : SegmentReader,
) -> Iter[(@core.VectorId, Array[Double], @core.Attrs)] {
  self.collect().iter()
}

///|
/// Helper: Encode attrs for segment (uses WAL encoding)
fn encode_attrs_for_segment(attrs : @core.Attrs) -> Bytes {
  // Reuse WAL JSON encoding
  let json = attrs_to_json_segment(attrs)
  string_to_utf8_segment(json)
}

///|
/// Helper: Decode attrs from segment
fn decode_attrs_from_segment(bytes : Bytes) -> @core.Attrs {
  match parse_json_object_segment(utf8_to_string_segment(bytes)) {
    Some(a) => a
    None => @core.empty_attrs()
  }
}

// JSON encoding helpers (simplified versions of WAL)

///|
fn attrs_to_json_segment(attrs : @core.Attrs) -> String {
  let parts : Array[String] = []
  for key in attrs.keys() {
    match attrs.get(key) {
      None => continue
      Some(value) => {
        let value_json = attr_value_to_json_segment(value)
        parts.push("\"" + escape_json_segment(key) + "\":" + value_json)
      }
    }
  }
  "{" +
  parts.iter().intersperse(",").fold(init="", fn(acc, s) { acc + s }) +
  "}"
}

///|
fn attr_value_to_json_segment(value : @core.AttrValue) -> String {
  match value {
    Null => "null"
    Bool(b) => if b { "true" } else { "false" }
    Int(n) => n.to_string()
    Float(f) => f.to_string()
    String(s) => "\"" + escape_json_segment(s) + "\""
  }
}

///|
fn escape_json_segment(s : String) -> String {
  let chars : Array[Char] = []
  for c in s {
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
      _ => chars.push(c)
    }
  }
  String::from_array(chars)
}

///|
pub fn string_to_utf8_segment(s : String) -> Bytes {
  let w = @binary.BinaryWriter::new()
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
pub fn utf8_to_string_segment(bytes : Bytes) -> String {
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
fn parse_json_object_segment(json : String) -> @core.Attrs? {
  let json = json.trim(chars=" \t\n\r").to_string()
  if json == "null" || json == "{}" {
    return Some(@core.empty_attrs())
  }
  if not(json.has_prefix("{")) || not(json.has_suffix("}")) {
    return None
  }
  let attrs = @core.empty_attrs()
  let content = json.unsafe_substring(start=1, end=json.length() - 1)
  if content.trim(chars=" \t\n\r").length() == 0 {
    return Some(attrs)
  }
  let chars = content.to_array()
  let mut i = 0
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
    if chars[i] != '"' {
      break
    }
    let (key, new_i) = parse_json_string_segment(chars, i)
    i = new_i
    while i < chars.length() &&
          (chars[i] == ' ' || chars[i] == '\t' || chars[i] == ':') {
      i = i + 1
    }
    let (value, new_i2) = parse_json_value_segment(chars, i)
    i = new_i2
    attrs.set(key, value)
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
fn parse_json_string_segment(chars : Array[Char], start : Int) -> (String, Int) {
  let mut i = start + 1
  let result : Array[Char] = []
  while i < chars.length() && chars[i] != '"' {
    if chars[i] == '\\' && i + 1 < chars.length() {
      i = i + 1
      match chars[i] {
        'n' => result.push('\n')
        'r' => result.push('\r')
        't' => result.push('\t')
        '"' => result.push('"')
        '\\' => result.push('\\')
        _ => result.push(chars[i])
      }
    } else {
      result.push(chars[i])
    }
    i = i + 1
  }
  (String::from_array(result), i + 1)
}

///|
fn parse_json_value_segment(
  chars : Array[Char],
  start : Int,
) -> (@core.AttrValue, Int) {
  let mut i = start
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
      let (s, new_i) = parse_json_string_segment(chars, i)
      (String(s), new_i)
    }
    't' => (Bool(true), i + 4)
    'f' => (Bool(false), i + 5)
    'n' => (Null, i + 4)
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
          has_dot = true
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
