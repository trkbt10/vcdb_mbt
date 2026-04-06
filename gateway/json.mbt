///|
/// JSON parsing and building module for gateway API
/// Extends patterns from core/persistence/wal/format.mbt

///|
/// JSON value type (prefixed with J to avoid name collisions)
pub(all) enum JsonValue {
  JNull
  JBool(Bool)
  JNumber(Double)
  JString(String)
  JArray(Array[JsonValue])
  JObject(Map[String, JsonValue])
} derive(Eq, Show)

///|
/// Convert JsonValue to string representation
pub fn JsonValue::to_string(self : JsonValue) -> String {
  match self {
    JNull => "null"
    JBool(b) => if b { "true" } else { "false" }
    JNumber(n) => format_number(n)
    JString(s) => "\"" + escape_json_string(s) + "\""
    JArray(arr) => {
      let parts : Array[String] = []
      for item in arr {
        parts.push(item.to_string())
      }
      "[" +
      parts.iter().intersperse(",").fold(init="", fn(acc, s) { acc + s }) +
      "]"
    }
    JObject(obj) => {
      let parts : Array[String] = []
      for kv in obj {
        let (key, value) = kv
        parts.push("\"" + escape_json_string(key) + "\":" + value.to_string())
      }
      "{" +
      parts.iter().intersperse(",").fold(init="", fn(acc, s) { acc + s }) +
      "}"
    }
  }
}

///|
/// Format number for JSON (integer or float)
fn format_number(n : Double) -> String {
  let int_part = n.to_int64()
  if n == int_part.to_double() && n.abs() < 9007199254740992.0 {
    int_part.to_string()
  } else {
    n.to_string()
  }
}

///|
/// Escape special characters in JSON string
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
  String::from_array(chars)
}

///|
/// Convert a nibble (0-15) to hex digit
fn hex_digit(n : UInt) -> Char {
  if n < 10U {
    (n + 48U).reinterpret_as_int().unsafe_to_char()
  } else {
    (n - 10U + 97U).reinterpret_as_int().unsafe_to_char()
  }
}

///|
/// JSON parser state
priv struct JsonParser {
  chars : Array[Char]
  mut pos : Int
}

///|
/// Create a new parser
fn JsonParser::new(s : String) -> JsonParser {
  { chars: s.to_array(), pos: 0 }
}

///|
/// Parse a JSON string into a JsonValue
pub fn parse_json(s : String) -> JsonValue? {
  let p = JsonParser::new(s)
  p.skip_whitespace()
  let result = p.parse_value()
  p.skip_whitespace()
  if p.pos < p.chars.length() {
    return None // Trailing content
  }
  result
}

///|
/// Skip whitespace
fn JsonParser::skip_whitespace(self : JsonParser) -> Unit {
  while self.pos < self.chars.length() {
    let c = self.chars[self.pos]
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      self.pos = self.pos + 1
    } else {
      break
    }
  }
}

///|
/// Peek current character
fn JsonParser::peek(self : JsonParser) -> Char? {
  if self.pos < self.chars.length() {
    Some(self.chars[self.pos])
  } else {
    None
  }
}

///|
/// Parse a JSON value
fn JsonParser::parse_value(self : JsonParser) -> JsonValue? {
  self.skip_whitespace()
  match self.peek() {
    None => None
    Some(c) =>
      match c {
        '"' => self.parse_string().map(fn(s) { JString(s) })
        't' => self.parse_true()
        'f' => self.parse_false()
        'n' => self.parse_null()
        '[' => self.parse_array()
        '{' => self.parse_object()
        '-' | '0' | '1' | '2' | '3' | '4' | '5' | '6' | '7' | '8' | '9' =>
          self.parse_number()
        _ => None
      }
  }
}

///|
/// Parse null
fn JsonParser::parse_null(self : JsonParser) -> JsonValue? {
  if self.pos + 4 <= self.chars.length() &&
    self.chars[self.pos] == 'n' &&
    self.chars[self.pos + 1] == 'u' &&
    self.chars[self.pos + 2] == 'l' &&
    self.chars[self.pos + 3] == 'l' {
    self.pos = self.pos + 4
    Some(JNull)
  } else {
    None
  }
}

///|
/// Parse true
fn JsonParser::parse_true(self : JsonParser) -> JsonValue? {
  if self.pos + 4 <= self.chars.length() &&
    self.chars[self.pos] == 't' &&
    self.chars[self.pos + 1] == 'r' &&
    self.chars[self.pos + 2] == 'u' &&
    self.chars[self.pos + 3] == 'e' {
    self.pos = self.pos + 4
    Some(JBool(true))
  } else {
    None
  }
}

///|
/// Parse false
fn JsonParser::parse_false(self : JsonParser) -> JsonValue? {
  if self.pos + 5 <= self.chars.length() &&
    self.chars[self.pos] == 'f' &&
    self.chars[self.pos + 1] == 'a' &&
    self.chars[self.pos + 2] == 'l' &&
    self.chars[self.pos + 3] == 's' &&
    self.chars[self.pos + 4] == 'e' {
    self.pos = self.pos + 5
    Some(JBool(false))
  } else {
    None
  }
}

///|
/// Parse a JSON string
fn JsonParser::parse_string(self : JsonParser) -> String? {
  if self.peek() != Some('"') {
    return None
  }
  self.pos = self.pos + 1
  let result : Array[Char] = []
  while self.pos < self.chars.length() {
    let c = self.chars[self.pos]
    if c == '"' {
      self.pos = self.pos + 1
      return Some(String::from_array(result))
    } else if c == '\\' {
      self.pos = self.pos + 1
      if self.pos >= self.chars.length() {
        return None
      }
      let escaped = self.chars[self.pos]
      match escaped {
        '"' => result.push('"')
        '\\' => result.push('\\')
        '/' => result.push('/')
        'b' => result.push('\u0008')
        'f' => result.push('\u000C')
        'n' => result.push('\n')
        'r' => result.push('\r')
        't' => result.push('\t')
        'u' => {
          if self.pos + 4 >= self.chars.length() {
            return None
          }
          let h1 = hex_char_value(self.chars[self.pos + 1])
          let h2 = hex_char_value(self.chars[self.pos + 2])
          let h3 = hex_char_value(self.chars[self.pos + 3])
          let h4 = hex_char_value(self.chars[self.pos + 4])
          let code = (h1 << 12) | (h2 << 8) | (h3 << 4) | h4
          result.push(code.unsafe_to_char())
          self.pos = self.pos + 4
        }
        _ => return None
      }
      self.pos = self.pos + 1
    } else {
      result.push(c)
      self.pos = self.pos + 1
    }
  }
  None
}

///|
/// Convert hex character to value (0-15)
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
/// Parse a number
fn JsonParser::parse_number(self : JsonParser) -> JsonValue? {
  let start = self.pos
  // Handle negative
  if self.pos < self.chars.length() && self.chars[self.pos] == '-' {
    self.pos = self.pos + 1
  }
  // Integer part
  while self.pos < self.chars.length() {
    let c = self.chars[self.pos]
    if c >= '0' && c <= '9' {
      self.pos = self.pos + 1
    } else {
      break
    }
  }
  // Decimal part
  if self.pos < self.chars.length() && self.chars[self.pos] == '.' {
    self.pos = self.pos + 1
    while self.pos < self.chars.length() {
      let c = self.chars[self.pos]
      if c >= '0' && c <= '9' {
        self.pos = self.pos + 1
      } else {
        break
      }
    }
  }
  // Exponent part
  if self.pos < self.chars.length() &&
    (self.chars[self.pos] == 'e' || self.chars[self.pos] == 'E') {
    self.pos = self.pos + 1
    if self.pos < self.chars.length() &&
      (self.chars[self.pos] == '+' || self.chars[self.pos] == '-') {
      self.pos = self.pos + 1
    }
    while self.pos < self.chars.length() {
      let c = self.chars[self.pos]
      if c >= '0' && c <= '9' {
        self.pos = self.pos + 1
      } else {
        break
      }
    }
  }
  let num_str = String::from_array(self.chars[start:self.pos])
  let result : Result[Double, _] = try? @strconv.parse_double(num_str)
  match result {
    Ok(n) => Some(JNumber(n))
    Err(_) => None
  }
}

///|
/// Parse an array
fn JsonParser::parse_array(self : JsonParser) -> JsonValue? {
  if self.peek() != Some('[') {
    return None
  }
  self.pos = self.pos + 1
  let items : Array[JsonValue] = []
  self.skip_whitespace()
  if self.peek() == Some(']') {
    self.pos = self.pos + 1
    return Some(JArray(items))
  }
  while true {
    match self.parse_value() {
      None => return None
      Some(value) => items.push(value)
    }
    self.skip_whitespace()
    match self.peek() {
      Some(']') => {
        self.pos = self.pos + 1
        return Some(JArray(items))
      }
      Some(',') => {
        self.pos = self.pos + 1
        self.skip_whitespace()
      }
      _ => return None
    }
  }
  None // unreachable
}

///|
/// Parse an object
fn JsonParser::parse_object(self : JsonParser) -> JsonValue? {
  if self.peek() != Some('{') {
    return None
  }
  self.pos = self.pos + 1
  let obj : Map[String, JsonValue] = {}
  self.skip_whitespace()
  if self.peek() == Some('}') {
    self.pos = self.pos + 1
    return Some(JObject(obj))
  }
  while true {
    self.skip_whitespace()
    let key = match self.parse_string() {
      None => return None
      Some(k) => k
    }
    self.skip_whitespace()
    if self.peek() != Some(':') {
      return None
    }
    self.pos = self.pos + 1
    self.skip_whitespace()
    let value = match self.parse_value() {
      None => return None
      Some(v) => v
    }
    obj[key] = value
    self.skip_whitespace()
    match self.peek() {
      Some('}') => {
        self.pos = self.pos + 1
        return Some(JObject(obj))
      }
      Some(',') => {
        self.pos = self.pos + 1
        self.skip_whitespace()
      }
      _ => return None
    }
  }
  None // unreachable
}

///|
/// Extract a vector (Array[Double]) from a JSON array
pub fn json_to_vector(json : JsonValue) -> Array[Double]? {
  match json {
    JArray(arr) => {
      let result : Array[Double] = []
      for item in arr {
        match item {
          JNumber(n) => result.push(n)
          _ => return None
        }
      }
      Some(result)
    }
    _ => None
  }
}

///|
/// Convert a vector to JSON array
pub fn vector_to_json(vec : Array[Double]) -> JsonValue {
  JArray(vec.map(fn(n) { JNumber(n) }))
}

///|
/// Convert Attrs to JsonValue
pub fn attrs_to_json(attrs : @types.Attrs) -> JsonValue {
  let obj : Map[String, JsonValue] = {}
  for key in attrs.keys() {
    match attrs.get(key) {
      None => continue
      Some(value) => obj[key] = attr_value_to_json(value)
    }
  }
  JObject(obj)
}

///|
/// Convert AttrValue to JsonValue
pub fn attr_value_to_json(value : @types.AttrValue) -> JsonValue {
  match value {
    Null => JNull
    Bool(b) => JBool(b)
    Int(n) => JNumber(n.to_double())
    Float(f) => JNumber(f)
    String(s) => JString(s)
  }
}

///|
/// Convert JsonValue to AttrValue
pub fn json_to_attr_value(json : JsonValue) -> @types.AttrValue? {
  match json {
    JNull => Some(@types.Null)
    JBool(b) => Some(@types.Bool(b))
    JNumber(n) => {
      let int_val = n.to_int64()
      if n == int_val.to_double() && n.abs() < 9007199254740992.0 {
        Some(@types.Int(int_val))
      } else {
        Some(@types.Float(n))
      }
    }
    JString(s) => Some(@types.String(s))
    JArray(_) => None
    JObject(_) => None
  }
}

///|
/// Convert JsonValue (object) to Attrs
pub fn json_to_attrs(json : JsonValue) -> @types.Attrs? {
  match json {
    JObject(obj) => {
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
/// Get a string field from a JSON object
pub fn get_string(obj : JsonValue, key : String) -> String? {
  match obj {
    JObject(m) =>
      match m.get(key) {
        Some(v) =>
          match v {
            JString(s) => Some(s)
            _ => None
          }
        None => None
      }
    _ => None
  }
}

///|
/// Get a number field from a JSON object
pub fn get_number(obj : JsonValue, key : String) -> Double? {
  match obj {
    JObject(m) =>
      match m.get(key) {
        Some(v) =>
          match v {
            JNumber(n) => Some(n)
            _ => None
          }
        None => None
      }
    _ => None
  }
}

///|
/// Get an integer field from a JSON object
pub fn get_int(obj : JsonValue, key : String) -> Int? {
  match obj {
    JObject(m) =>
      match m.get(key) {
        Some(v) =>
          match v {
            JNumber(n) => Some(n.to_int())
            _ => None
          }
        None => None
      }
    _ => None
  }
}

///|
/// Get an Int64 field from a JSON object
pub fn get_int64(obj : JsonValue, key : String) -> Int64? {
  match obj {
    JObject(m) =>
      match m.get(key) {
        Some(v) =>
          match v {
            JNumber(n) => Some(n.to_int64())
            _ => None
          }
        None => None
      }
    _ => None
  }
}

///|
/// Get a boolean field from a JSON object
pub fn get_bool(obj : JsonValue, key : String) -> Bool? {
  match obj {
    JObject(m) =>
      match m.get(key) {
        Some(v) =>
          match v {
            JBool(b) => Some(b)
            _ => None
          }
        None => None
      }
    _ => None
  }
}

///|
/// Get an array field from a JSON object
pub fn get_array(obj : JsonValue, key : String) -> Array[JsonValue]? {
  match obj {
    JObject(m) =>
      match m.get(key) {
        Some(v) =>
          match v {
            JArray(arr) => Some(arr)
            _ => None
          }
        None => None
      }
    _ => None
  }
}

///|
/// Get an object field from a JSON object
pub fn get_object(obj : JsonValue, key : String) -> Map[String, JsonValue]? {
  match obj {
    JObject(m) =>
      match m.get(key) {
        Some(v) =>
          match v {
            JObject(o) => Some(o)
            _ => None
          }
        None => None
      }
    _ => None
  }
}

///|
/// Build a JSON object from key-value pairs
pub fn json_object(pairs : Array[(String, JsonValue)]) -> JsonValue {
  let obj : Map[String, JsonValue] = {}
  for pair in pairs {
    let (key, value) = pair
    obj[key] = value
  }
  JObject(obj)
}

///|
/// Build a JSON array
pub fn json_array(items : Array[JsonValue]) -> JsonValue {
  JArray(items)
}
