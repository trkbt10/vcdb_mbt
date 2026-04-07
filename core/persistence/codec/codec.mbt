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
    Some(a) => {
      let keys = a.keys()
      if keys.length() == 0 {
        return "{}"
      }
      let chars : Array[Char] = []
      chars.push('{')
      let mut first = true
      for key in keys {
        match a.get(key) {
          None => continue
          Some(value) => {
            if !first {
              chars.push(',')
            }
            first = false
            chars.push('"')
            push_escaped_json(chars, key)
            chars.push('"')
            chars.push(':')
            push_attr_value_json(chars, value)
          }
        }
      }
      chars.push('}')
      String::from_array(chars)
    }
  }
}

///|
/// Parse attrs option from JSON string.
pub fn parse_attrs_json(json : String) -> @types.Attrs? {
  let json = json.trim(chars=" \t\n\r").to_string()
  if json == "null" {
    return None
  }
  if !json.has_prefix("{") || !json.has_suffix("}") {
    return None
  }
  let attrs = @types.empty_attrs()
  let content = json.unsafe_substring(start=1, end=json.length() - 1)
  if content.trim(chars=" \t\n\r").length() == 0 {
    return Some(attrs)
  }
  let mut i = 0
  let chars = content.to_array()
  while i < chars.length() {
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
    let (key, new_i) = parse_json_string(chars, i)
    i = new_i
    while i < chars.length() &&
          (chars[i] == ' ' || chars[i] == '\t' || chars[i] == ':') {
      i = i + 1
    }
    let (value, new_i2) = parse_json_value(chars, i)
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

///|
fn push_attr_value_json(chars : Array[Char], value : @types.AttrValue) -> Unit {
  match value {
    Null => {
      chars.push('n')
      chars.push('u')
      chars.push('l')
      chars.push('l')
    }
    Bool(b) =>
      if b {
        chars.push('t')
        chars.push('r')
        chars.push('u')
        chars.push('e')
      } else {
        chars.push('f')
        chars.push('a')
        chars.push('l')
        chars.push('s')
        chars.push('e')
      }
    Int(n) => {
      let s = n.to_string()
      for c in s {
        chars.push(c)
      }
    }
    Float(f) => {
      let s = f.to_string()
      for c in s {
        chars.push(c)
      }
    }
    String(s) => {
      chars.push('"')
      push_escaped_json(chars, s)
      chars.push('"')
    }
  }
}

///|
fn push_escaped_json(chars : Array[Char], s : String) -> Unit {
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
        chars.push('\\')
        chars.push('b')
      }
      '\u000C' => {
        chars.push('\\')
        chars.push('f')
      }
      _ =>
        if code < 0x20U {
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
}

///|
fn hex_digit(n : UInt) -> Char {
  if n < 10U {
    (n + 48U).reinterpret_as_int().unsafe_to_char()
  } else {
    (n - 10U + 97U).reinterpret_as_int().unsafe_to_char()
  }
}

///|
fn parse_json_string(chars : Array[Char], start : Int) -> (String, Int) {
  let mut i = start + 1
  let result : Array[Char] = []
  while i < chars.length() && chars[i] != '"' {
    if chars[i] == '\\' && i + 1 < chars.length() {
      i = i + 1
      match chars[i] {
        'n' => result.push('\n')
        'r' => result.push('\r')
        't' => result.push('\t')
        'b' => result.push('\u0008')
        'f' => result.push('\u000C')
        '"' => result.push('"')
        '\\' => result.push('\\')
        'u' =>
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
  (String::from_array(result), i + 1)
}

///|
fn hex_char_value(c : Char) -> Int {
  let code = c.to_uint().reinterpret_as_int()
  if code >= 48 && code <= 57 {
    code - 48
  } else if code >= 97 && code <= 102 {
    code - 97 + 10
  } else if code >= 65 && code <= 70 {
    code - 65 + 10
  } else {
    0
  }
}

///|
fn parse_json_value(
  chars : Array[Char],
  start : Int,
) -> (@types.AttrValue, Int) {
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
      let (s, new_i) = parse_json_string(chars, i)
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
        let result : Result[Double, _] = try? @string.parse_double(num_str)
        match result {
          Ok(f) => (Float(f), i)
          Err(_) => (Null, i)
        }
      } else {
        let result : Result[Int64, _] = try? @string.parse_int64(num_str)
        match result {
          Ok(n) => (Int(n), i)
          Err(_) => (Null, i)
        }
      }
    }
    _ => (Null, i + 1)
  }
}
