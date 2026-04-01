///|
/// JSON ↔ FilterExpr conversion (SoT for the filter JSON format).
///
/// Structured format (1:1 with FilterExpr):
///   {"match": {"key": "category", "value": "科学"}}
///   {"range": {"key": "score", "gt": 0.5, "lte": 1.0}}
///   {"exists": {"key": "category"}}
///   {"is_null": {"key": "deleted_at"}}
///   {"must": [<expr>, <expr>, ...]}
///   {"must_not": [<expr>, ...]}
///   {"should": {"exprs": [<expr>, ...], "min": 1}}
///
/// Shorthand (flat key-value → AND of match conditions):
///   {"category": "科学", "status": "解決済み"}
///   → Must([Match("category","科学"), Match("status","解決済み")])

///|
/// Parse a JSON string into a FilterExpr. Returns None for empty/invalid input.
pub fn parse_filter_json(json : String) -> FilterExpr? {
  if json.length() == 0 || json == "{}" {
    return None
  }
  let parsed = try { @json.parse(json) } catch { _ => return None }
  json_to_filter(parsed)
}

///|
/// Convert a parsed Json value to a FilterExpr.
fn json_to_filter(j : Json) -> FilterExpr? {
  match j {
    { "match": Object(inner), .. } => parse_match(inner)
    { "range": Object(inner), .. } => parse_range(inner)
    { "exists": Object(inner), .. } =>
      match inner.get("key") {
        Some(String(k)) => Some(FilterExpr::exists(k))
        _ => None
      }
    { "is_null": Object(inner), .. } =>
      match inner.get("key") {
        Some(String(k)) => Some(FilterExpr::is_null(k))
        _ => None
      }
    { "must": Array(exprs), .. } => parse_compound_must(exprs)
    { "must_not": Array(exprs), .. } => parse_compound_must_not(exprs)
    { "should": Object(inner), .. } => parse_compound_should(inner)
    Object(map) => parse_shorthand(map)
    _ => None
  }
}

///|
/// {"match": {"key": "k", "value": <v>}} → Match(k, v)
fn parse_match(inner : Map[String, Json]) -> FilterExpr? {
  let key = match inner.get("key") {
    Some(String(k)) => k
    _ => return None
  }
  let value = match inner.get("value") {
    Some(String(s)) => @types.String(s)
    Some(Number(n)) => {
      let d = n
      if d == d.to_int().to_double() {
        @types.Int(d.to_int64())
      } else {
        @types.Float(d)
      }
    }
    Some(True) => @types.Bool(true)
    Some(False) => @types.Bool(false)
    Some(Null) => @types.Null
    _ => return None
  }
  Some(FilterExpr::match_(key, value))
}

///|
/// {"range": {"key": "k", "gt": n, "gte": n, "lt": n, "lte": n}} → Range(k, range)
fn parse_range(inner : Map[String, Json]) -> FilterExpr? {
  let key = match inner.get("key") {
    Some(String(k)) => k
    _ => return None
  }
  let range : @types.NumericRange = {
    gt: json_to_double(inner.get("gt")),
    gte: json_to_double(inner.get("gte")),
    lt: json_to_double(inner.get("lt")),
    lte: json_to_double(inner.get("lte")),
  }
  Some(FilterExpr::range(key, range))
}

///|
fn json_to_double(j : Json?) -> Double? {
  match j {
    Some(Number(n)) => Some(n)
    _ => None
  }
}

///|
/// {"must": [<expr>, ...]} → Must([...])
fn parse_compound_must(exprs : Array[Json]) -> FilterExpr? {
  let children = parse_expr_array(exprs)
  if children.is_empty() {
    None
  } else {
    Some(FilterExpr::must(children))
  }
}

///|
/// {"must_not": [<expr>, ...]} → MustNot([...])
fn parse_compound_must_not(exprs : Array[Json]) -> FilterExpr? {
  let children = parse_expr_array(exprs)
  if children.is_empty() {
    None
  } else {
    Some(FilterExpr::must_not(children))
  }
}

///|
/// {"should": {"exprs": [...], "min": N}} → Should([...], N)
fn parse_compound_should(inner : Map[String, Json]) -> FilterExpr? {
  let exprs = match inner.get("exprs") {
    Some(Array(arr)) => parse_expr_array(arr)
    _ => return None
  }
  let min = match inner.get("min") {
    Some(Number(n)) => n.to_int()
    _ => 1
  }
  if exprs.is_empty() {
    None
  } else {
    Some(FilterExpr::should(exprs, min=min))
  }
}

///|
/// Parse an array of JSON filter expressions recursively.
fn parse_expr_array(arr : Array[Json]) -> Array[FilterExpr] {
  let result : Array[FilterExpr] = []
  for item in arr {
    match json_to_filter(item) {
      Some(expr) => result.push(expr)
      None => () // skip invalid entries
    }
  }
  result
}

///|
/// Shorthand: flat {"key": "value", ...} → Must([Match(k,v), ...])
fn parse_shorthand(map : Map[String, Json]) -> FilterExpr? {
  let conditions : Array[FilterExpr] = []
  for entry in map {
    let (key, json_val) = entry
    // Skip structural keys
    if key == "match" ||
      key == "range" ||
      key == "exists" ||
      key == "is_null" ||
      key == "must" ||
      key == "must_not" ||
      key == "should" {
      continue
    }
    let value = match json_val {
      String(s) => @types.String(s)
      Number(n) => {
        let d = n
        if d == d.to_int().to_double() {
          @types.Int(d.to_int64())
        } else {
          @types.Float(d)
        }
      }
      True => @types.Bool(true)
      False => @types.Bool(false)
      Null => @types.Null
      _ => continue
    }
    conditions.push(FilterExpr::match_(key, value))
  }
  if conditions.is_empty() {
    None
  } else if conditions.length() == 1 {
    Some(conditions[0])
  } else {
    Some(FilterExpr::must(conditions))
  }
}
