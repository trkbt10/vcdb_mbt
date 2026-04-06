///|
test "filter_json/empty" {
  inspect(parse_filter_json("") is None, content="true")
  inspect(parse_filter_json("{}") is None, content="true")
}

///|
test "filter_json/shorthand_single" {
  let f = parse_filter_json("{\"category\":\"科学\"}")
  match f {
    Some(Leaf(Match(key, @types.String(val)))) => {
      inspect(key, content="category")
      inspect(val, content="科学")
    }
    _ => inspect(false, content="true")
  }
}

///|
test "filter_json/shorthand_multiple" {
  let f = parse_filter_json(
    "{\"category\":\"科学\",\"status\":\"解決済み\"}",
  )
  match f {
    Some(Must(exprs)) => inspect(exprs.length(), content="2")
    _ => inspect(false, content="true")
  }
}

///|
test "filter_json/match_structured" {
  let f = parse_filter_json(
    "{\"match\":{\"key\":\"category\",\"value\":\"生活\"}}",
  )
  match f {
    Some(Leaf(Match(key, @types.String(val)))) => {
      inspect(key, content="category")
      inspect(val, content="生活")
    }
    _ => inspect(false, content="true")
  }
}

///|
test "filter_json/match_number" {
  let f = parse_filter_json("{\"match\":{\"key\":\"count\",\"value\":42}}")
  match f {
    Some(Leaf(Match(key, @types.Int(val)))) => {
      inspect(key, content="count")
      inspect(val, content="42")
    }
    _ => inspect(false, content="true")
  }
}

///|
test "filter_json/match_bool" {
  let f = parse_filter_json("{\"match\":{\"key\":\"active\",\"value\":true}}")
  match f {
    Some(Leaf(Match(key, @types.Bool(val)))) => {
      inspect(key, content="active")
      inspect(val, content="true")
    }
    _ => inspect(false, content="true")
  }
}

///|
test "filter_json/range" {
  let f = parse_filter_json(
    "{\"range\":{\"key\":\"score\",\"gte\":0.5,\"lt\":1.0}}",
  )
  match f {
    Some(Leaf(Range(key, range))) => {
      inspect(key, content="score")
      inspect(range.gte is Some(_), content="true")
      inspect(range.lt is Some(_), content="true")
      inspect(range.gt is None, content="true")
      inspect(range.lte is None, content="true")
    }
    _ => inspect(false, content="true")
  }
}

///|
test "filter_json/exists" {
  let f = parse_filter_json("{\"exists\":{\"key\":\"category\"}}")
  match f {
    Some(Leaf(Exists(key))) => inspect(key, content="category")
    _ => inspect(false, content="true")
  }
}

///|
test "filter_json/is_null" {
  let f = parse_filter_json("{\"is_null\":{\"key\":\"deleted_at\"}}")
  match f {
    Some(Leaf(IsNull(key))) => inspect(key, content="deleted_at")
    _ => inspect(false, content="true")
  }
}

///|
test "filter_json/must_compound" {
  let f = parse_filter_json(
    "{\"must\":[{\"match\":{\"key\":\"category\",\"value\":\"科学\"}},{\"match\":{\"key\":\"status\",\"value\":\"解決済み\"}}]}",
  )
  match f {
    Some(Must(exprs)) => {
      inspect(exprs.length(), content="2")
      match exprs[0] {
        Leaf(Match(k, _)) => inspect(k, content="category")
        _ => inspect(false, content="true")
      }
    }
    _ => inspect(false, content="true")
  }
}

///|
test "filter_json/must_not" {
  let f = parse_filter_json(
    "{\"must_not\":[{\"match\":{\"key\":\"status\",\"value\":\"解決済み\"}}]}",
  )
  match f {
    Some(MustNot(exprs)) => inspect(exprs.length(), content="1")
    _ => inspect(false, content="true")
  }
}

///|
test "filter_json/should" {
  let f = parse_filter_json(
    "{\"should\":{\"exprs\":[{\"match\":{\"key\":\"category\",\"value\":\"科学\"}},{\"match\":{\"key\":\"category\",\"value\":\"生活\"}}],\"min\":1}}",
  )
  match f {
    Some(Should(exprs, min)) => {
      inspect(exprs.length(), content="2")
      inspect(min, content="1")
    }
    _ => inspect(false, content="true")
  }
}

///|
test "filter_json/nested_must_with_must_not" {
  let f = parse_filter_json(
    "{\"must\":[{\"match\":{\"key\":\"category\",\"value\":\"科学\"}},{\"must_not\":[{\"match\":{\"key\":\"status\",\"value\":\"解決済み\"}}]}]}",
  )
  match f {
    Some(Must(exprs)) => {
      inspect(exprs.length(), content="2")
      match exprs[1] {
        MustNot(inner) => inspect(inner.length(), content="1")
        _ => inspect(false, content="true")
      }
    }
    _ => inspect(false, content="true")
  }
}

///|
test "filter_json/round_trip_match" {
  let json = "{\"match\":{\"key\":\"category\",\"value\":\"科学\"}}"
  let expr = parse_filter_json(json).unwrap()
  let serialized = filter_to_json(expr)
  let reparsed = parse_filter_json(serialized).unwrap()
  // Verify structural equivalence
  inspect(filter_to_json(reparsed) == serialized, content="true")
}

///|
test "filter_json/round_trip_must" {
  let json = "{\"must\":[{\"match\":{\"key\":\"a\",\"value\":\"x\"}},{\"match\":{\"key\":\"b\",\"value\":1}}]}"
  let expr = parse_filter_json(json).unwrap()
  let serialized = filter_to_json(expr)
  let reparsed = parse_filter_json(serialized)
  inspect(reparsed is Some(_), content="true")
}

///|
test "filter_json/serialize_range" {
  let json = "{\"range\":{\"key\":\"score\",\"gte\":0.5,\"lt\":1}}"
  let expr = parse_filter_json(json).unwrap()
  let serialized = filter_to_json(expr)
  inspect(serialized.contains("\"range\""), content="true")
  inspect(serialized.contains("\"gte\""), content="true")
}

///|
test "filter_json/invalid_json" {
  inspect(parse_filter_json("not json") is None, content="true")
  inspect(parse_filter_json("[1,2,3]") is None, content="true")
}
