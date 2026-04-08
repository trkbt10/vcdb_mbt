///|
/// JSON utilities for gateway API — built on top of the standard Json type.

///|
/// Parse a JSON string. Returns None for invalid input.
pub fn parse_json(s : String) -> Json? {
  let result = @json.parse(s) catch { _ => return None }
  Some(result)
}

///|
/// Extract a vector (Array[Double]) from a JSON array
pub fn json_to_vector(json : Json) -> Array[Double]? {
  match json {
    Array(arr) => {
      let result : Array[Double] = []
      for item in arr {
        match item {
          Number(n, ..) => result.push(n)
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
pub fn vector_to_json(vec : Array[Double]) -> Json {
  Json::array(vec.map(fn(n) { n.to_json() }))
}

///|
/// Convert Attrs to Json
pub fn attrs_to_json(attrs : @types.Attrs) -> Json {
  @codec.attrs_to_json_value(attrs)
}

///|
/// Convert AttrValue to Json
pub fn attr_value_to_json(value : @types.AttrValue) -> Json {
  @codec.attr_value_to_json(value)
}

///|
/// Convert Json to AttrValue
pub fn json_to_attr_value(json : Json) -> @types.AttrValue? {
  @codec.json_to_attr_value(json)
}

///|
/// Convert Json (object) to Attrs
pub fn json_to_attrs(json : Json) -> @types.Attrs? {
  @codec.json_to_attrs(json)
}

///|
/// Get a string field from a JSON object
pub fn get_string(obj : Json, key : String) -> String? {
  match obj {
    Object(m) =>
      match m.get(key) {
        Some(String(s)) => Some(s)
        _ => None
      }
    _ => None
  }
}

///|
/// Get a number field from a JSON object
pub fn get_number(obj : Json, key : String) -> Double? {
  match obj {
    Object(m) =>
      match m.get(key) {
        Some(Number(n, ..)) => Some(n)
        _ => None
      }
    _ => None
  }
}

///|
/// Get an integer field from a JSON object
pub fn get_int(obj : Json, key : String) -> Int? {
  match obj {
    Object(m) =>
      match m.get(key) {
        Some(Number(n, ..)) => Some(n.to_int())
        _ => None
      }
    _ => None
  }
}

///|
/// Get an Int64 field from a JSON object
pub fn get_int64(obj : Json, key : String) -> Int64? {
  match obj {
    Object(m) =>
      match m.get(key) {
        Some(Number(n, ..)) => Some(n.to_int64())
        _ => None
      }
    _ => None
  }
}

///|
/// Get a boolean field from a JSON object
pub fn get_bool(obj : Json, key : String) -> Bool? {
  match obj {
    Object(m) =>
      match m.get(key) {
        Some(True) => Some(true)
        Some(False) => Some(false)
        _ => None
      }
    _ => None
  }
}

///|
/// Get an array field from a JSON object
pub fn get_array(obj : Json, key : String) -> Array[Json]? {
  match obj {
    Object(m) =>
      match m.get(key) {
        Some(Array(arr)) => Some(arr)
        _ => None
      }
    _ => None
  }
}

///|
/// Get an object field from a JSON object
pub fn get_object(obj : Json, key : String) -> Map[String, Json]? {
  match obj {
    Object(m) =>
      match m.get(key) {
        Some(Object(o)) => Some(o)
        _ => None
      }
    _ => None
  }
}

///|
/// Build a JSON object from key-value pairs
pub fn json_object(pairs : Array[(String, Json)]) -> Json {
  let obj : Map[String, Json] = {}
  for pair in pairs {
    let (key, value) = pair
    obj[key] = value
  }
  Json::object(obj)
}

///|
/// Build a JSON array
pub fn json_array(items : Array[Json]) -> Json {
  Json::array(items)
}
