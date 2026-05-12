///|
/// Encode attrs option as JSON UTF-8 bytes.
pub fn encode_attrs_json(attrs : @types.Attrs?) -> Bytes {
  encode_utf8(attrs_to_json(attrs))
}

///|
/// Decode attrs option from JSON UTF-8 bytes.
/// Empty bytes are treated as None.
pub fn decode_attrs_json(bytes : Bytes) -> @types.Attrs? {
  if bytes.length() == 0 {
    return None
  }
  parse_attrs_json(decode_utf8(bytes))
}

///|
/// Convert attrs option to JSON string.
pub fn attrs_to_json(attrs : @types.Attrs?) -> String {
  match attrs {
    None => "null"
    Some(a) => attrs_to_json_value(a).stringify()
  }
}

///|
/// Convert Attrs to a Json value (for API responses).
pub fn attrs_to_json_value(attrs : @types.Attrs) -> Json {
  let obj : Map[String, Json] = {}
  for key in attrs.keys() {
    match attrs.get(key) {
      None => continue
      Some(value) => obj[key] = attr_value_to_json(value)
    }
  }
  Json::object(obj)
}

///|
/// Convert Json to AttrValue.
pub fn json_to_attr_value(json : Json) -> @types.AttrValue? {
  match json {
    Null => Some(@types.Null)
    True => Some(@types.Bool(true))
    False => Some(@types.Bool(false))
    Number(n, ..) => {
      let int_val = n.to_int64()
      if n == int_val.to_double() && n.abs() < 9007199254740992.0 {
        Some(@types.Int(int_val))
      } else {
        Some(@types.Float(n))
      }
    }
    String(s) => Some(@types.String(s))
    Array(_) => None
    Object(_) => None
  }
}

///|
/// Convert Json object to Attrs.
pub fn json_to_attrs(json : Json) -> @types.Attrs? {
  match json {
    Object(obj) => {
      let attrs = @types.empty_attrs()
      for kv in obj {
        let (key, value) = kv
        match json_to_attr_value(value) {
          Some(attr) => attrs.set(key, attr)
          None => return None
        }
      }
      Some(attrs)
    }
    _ => None
  }
}

///|
pub fn attr_value_to_json(value : @types.AttrValue) -> Json {
  match value {
    Null => Json::null()
    Bool(b) => b.to_json()
    Int(n) => n.to_double().to_json()
    Float(f) => f.to_json()
    String(s) => s.to_json()
  }
}

///|
/// Parse attrs option from JSON string.
pub fn parse_attrs_json(json : String) -> @types.Attrs? {
  let json = json.trim(chars=" \t\n\r").to_owned()
  if json == "null" {
    return None
  }
  let parsed = @json.parse(json) catch { _ => return None }
  match parsed {
    Object(obj) => {
      let attrs = @types.empty_attrs()
      for kv in obj {
        let (key, value) = kv
        match json_to_attr_value(value) {
          Some(attr) => attrs.set(key, attr)
          None => return None
        }
      }
      Some(attrs)
    }
    _ => None
  }
}

///|
/// Encode UTF-8 bytes from string.
pub fn encode_utf8(s : String) -> Bytes {
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
/// Decode string from UTF-8 bytes.
pub fn decode_utf8(bytes : Bytes) -> String {
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
