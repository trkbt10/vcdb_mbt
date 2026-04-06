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
  let parsed = @json.parse(json) catch { _ => return None }
  json_to_filter(parsed)
}

///|
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
fn parse_match(inner : Map[String, Json]) -> FilterExpr? {
  let key = match inner.get("key") {
    Some(String(k)) => k
    _ => return None
  }
  let value = match inner.get("value") {
    Some(String(s)) => @types.String(s)
    Some(Number(n)) =>
      if n == n.to_int().to_double() {
        @types.Int(n.to_int64())
      } else {
        @types.Float(n)
      }
    Some(True) => @types.Bool(true)
    Some(False) => @types.Bool(false)
    Some(Null) => @types.Null
    _ => return None
  }
  Some(FilterExpr::match_(key, value))
}

///|
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
fn parse_compound_must(exprs : Array[Json]) -> FilterExpr? {
  let children = parse_expr_array(exprs)
  if children.is_empty() {
    None
  } else {
    Some(FilterExpr::must(children))
  }
}

///|
fn parse_compound_must_not(exprs : Array[Json]) -> FilterExpr? {
  let children = parse_expr_array(exprs)
  if children.is_empty() {
    None
  } else {
    Some(FilterExpr::must_not(children))
  }
}

///|
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
    Some(FilterExpr::should(exprs, min~))
  }
}

///|
fn parse_expr_array(arr : Array[Json]) -> Array[FilterExpr] {
  let result : Array[FilterExpr] = []
  for item in arr {
    match json_to_filter(item) {
      Some(expr) => result.push(expr)
      None => ()
    }
  }
  result
}

///|
fn parse_shorthand(map : Map[String, Json]) -> FilterExpr? {
  let conditions : Array[FilterExpr] = []
  for entry in map {
    let (key, json_val) = entry
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
      Number(n) =>
        if n == n.to_int().to_double() {
          @types.Int(n.to_int64())
        } else {
          @types.Float(n)
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

// ============================================================================
// FilterExpr → JSON serialization (round-trip with parse_filter_json)
// Uses @json.Json type for correct serialization.
// ============================================================================

///|
/// Serialize a FilterExpr to JSON string.
pub fn filter_to_json(expr : FilterExpr) -> String {
  expr.to_json().stringify()
}

///|
fn FilterExpr::to_json(self : FilterExpr) -> Json {
  match self {
    Leaf(leaf) => leaf.to_json()
    Must(exprs) => { "must": exprs.map(FilterExpr::to_json) }
    MustNot(exprs) => { "must_not": exprs.map(FilterExpr::to_json) }
    Should(exprs, min) =>
      { "should": { "exprs": exprs.map(FilterExpr::to_json), "min": min } }
  }
}

///|
fn LeafExpr::to_json(self : LeafExpr) -> Json {
  match self {
    Match(key, value) => { "match": { "key": key, "value": value.to_json() } }
    Range(key, range) => {
      let inner : Map[String, Json] = {}
      inner["key"] = key.to_json()
      match range.gt {
        Some(v) => inner["gt"] = v.to_json()
        None => ()
      }
      match range.gte {
        Some(v) => inner["gte"] = v.to_json()
        None => ()
      }
      match range.lt {
        Some(v) => inner["lt"] = v.to_json()
        None => ()
      }
      match range.lte {
        Some(v) => inner["lte"] = v.to_json()
        None => ()
      }
      { "range": inner.to_json() }
    }
    Exists(key) => { "exists": { "key": key } }
    IsNull(key) => { "is_null": { "key": key } }
  }
}

///|
fn json_null() -> Json {
  @json.parse("null") catch {
    _ => abort("failed to construct JSON null")
  }
}

///|
fn @types.AttrValue::to_json(self : @types.AttrValue) -> Json {
  match self {
    @types.String(s) => s.to_json()
    @types.Int(n) => n.to_double().to_json()
    @types.Float(f) => f.to_json()
    @types.Bool(b) => b.to_json()
    @types.Null => json_null()
  }
}
