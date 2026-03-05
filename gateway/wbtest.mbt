///|
/// Tests for JSON module
test "json/parse_null" {
  let result = parse_json("null")
  assert_eq(result, Some(JNull))
}

///|
test "json/parse_bool" {
  assert_eq(parse_json("true"), Some(JBool(true)))
  assert_eq(parse_json("false"), Some(JBool(false)))
}

///|
test "json/parse_number" {
  assert_eq(parse_json("42"), Some(JNumber(42.0)))
  assert_eq(parse_json("-123"), Some(JNumber(-123.0)))
  assert_eq(parse_json("3.14"), Some(JNumber(3.14)))
  assert_eq(parse_json("1e10"), Some(JNumber(10000000000.0)))
}

///|
test "json/parse_string" {
  assert_eq(parse_json("\"hello\""), Some(JString("hello")))
  assert_eq(parse_json("\"hello\\nworld\""), Some(JString("hello\nworld")))
  assert_eq(parse_json("\"tab\\there\""), Some(JString("tab\there")))
}

///|
test "json/parse_array" {
  let result = parse_json("[1, 2, 3]")
  assert_eq(result, Some(JArray([JNumber(1.0), JNumber(2.0), JNumber(3.0)])))

  let empty = parse_json("[]")
  assert_eq(empty, Some(JArray([])))
}

///|
test "json/parse_object" {
  let result = parse_json("{\"name\": \"test\", \"value\": 42}")
  match result {
    Some(JObject(obj)) => {
      assert_eq(get_string(JObject(obj), "name"), Some("test"))
      assert_eq(get_number(JObject(obj), "value"), Some(42.0))
    }
    _ => assert_true(false)
  }
}

///|
test "json/parse_nested" {
  let result = parse_json("{\"items\": [1, 2, 3], \"meta\": {\"count\": 3}}")
  match result {
    Some(JObject(obj)) => {
      let items = get_array(JObject(obj), "items")
      assert_true(items is Some(_))
      match get_object(JObject(obj), "meta") {
        Some(meta) => {
          let count = meta.get("count")
          match count {
            Some(JNumber(n)) => assert_eq(n, 3.0)
            _ => assert_true(false)
          }
        }
        None => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
test "json/to_string" {
  let obj = json_object([
    ("name", JString("test")),
    ("value", JNumber(42.0)),
    ("active", JBool(true)),
  ])
  let s = obj.to_string()
  // Parse it back to verify
  let parsed = parse_json(s)
  assert_true(parsed is Some(_))
}

///|
test "json/vector_conversion" {
  let vec = [1.0, 2.0, 3.0]
  let json = vector_to_json(vec)
  let back = json_to_vector(json)
  assert_eq(back, Some(vec))
}

///|
test "json/attrs_conversion" {
  let attrs = @types.empty_attrs()
  attrs.set("name", @types.String("test"))
  attrs.set("count", @types.Int(42L))
  attrs.set("ratio", @types.Float(0.5))
  attrs.set("active", @types.Bool(true))

  let json = attrs_to_json(attrs)
  let back = json_to_attrs(json)

  match back {
    Some(a) => {
      assert_eq(a.get("name"), Some(@types.String("test")))
      assert_eq(a.get("count"), Some(@types.Int(42L)))
      assert_eq(a.get("active"), Some(@types.Bool(true)))
    }
    None => assert_true(false)
  }
}

///|
test "json/get_helpers" {
  let obj = json_object([
    ("name", JString("test")),
    ("count", JNumber(42.0)),
    ("active", JBool(true)),
    ("items", json_array([JNumber(1.0), JNumber(2.0)])),
  ])

  assert_eq(get_string(obj, "name"), Some("test"))
  assert_eq(get_number(obj, "count"), Some(42.0))
  assert_eq(get_int(obj, "count"), Some(42))
  assert_eq(get_bool(obj, "active"), Some(true))
  assert_true(get_array(obj, "items") is Some(_))
  assert_eq(get_string(obj, "missing"), None)
}

///|
test "json/escape_roundtrip" {
  let special = "hello\nworld\ttab\"quote\\backslash"
  let json = JString(special)
  let s = json.to_string()
  let parsed = parse_json(s)
  assert_eq(parsed, Some(JString(special)))
}
