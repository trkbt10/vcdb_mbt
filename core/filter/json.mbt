///|
/// JSON ↔ FilterExpr conversion.
///
/// SoT for the JSON filter format used by the FFI boundary.
/// All filter JSON parsing goes through parse_filter_json.
///
/// Format (structured — maps 1:1 to FilterExpr):
///   {"match": {"key": "category", "value": "科学"}}
///   {"range": {"key": "score", "gt": 0.5, "lte": 1.0}}
///   {"exists": {"key": "category"}}
///   {"is_null": {"key": "deleted_at"}}
///   {"must": [<expr>, ...]}
///   {"must_not": [<expr>, ...]}
///   {"should": {"exprs": [<expr>, ...], "min": 1}}
///
/// Shorthand (flat key-value → AND of match conditions):
///   {"category": "科学", "status": "解決済み"}
///   → Must([Match("category","科学"), Match("status","解決済み")])

///|
/// Parse a JSON string into a FilterExpr.
/// Returns None for empty/invalid input.
pub fn parse_filter_json(json : String) -> FilterExpr? {
  if json.length() == 0 || json == "{}" {
    return None
  }
  let bytes = @codec.encode_utf8(json)
  // Try structured format first (has "match"/"must"/etc. keys)
  let parsed = try_parse_structured(json)
  match parsed {
    Some(_) => parsed
    None => {
      // Fall back to shorthand: flat key-value → AND of match conditions
      match @codec.decode_attrs_json(bytes) {
        Some(attrs) => attrs_to_filter(attrs)
        None => None
      }
    }
  }
}

///|
/// Convert flat attrs to a Must([Match, ...]) filter.
fn attrs_to_filter(attrs : @types.Attrs) -> FilterExpr? {
  let conditions : Array[FilterExpr] = []
  for key in attrs.keys() {
    match attrs.get(key) {
      Some(value) => conditions.push(FilterExpr::match_(key, value))
      None => ()
    }
  }
  if conditions.is_empty() {
    None
  } else if conditions.length() == 1 {
    Some(conditions[0])
  } else {
    Some(FilterExpr::must(conditions))
  }
}

///|
/// Try to parse structured filter format.
/// Returns None if the JSON doesn't match any structured pattern.
fn try_parse_structured(json : String) -> FilterExpr? {
  let chars = json.to_array()
  if chars.length() < 2 || chars[0] != '{' {
    return None
  }
  // Check for structural keys
  if has_key(json, "match") {
    return parse_match_expr(json)
  }
  if has_key(json, "range") {
    return parse_range_expr(json)
  }
  if has_key(json, "exists") {
    return parse_exists_expr(json)
  }
  if has_key(json, "is_null") {
    return parse_is_null_expr(json)
  }
  if has_key(json, "must") {
    return parse_must_expr(json)
  }
  if has_key(json, "must_not") {
    return parse_must_not_expr(json)
  }
  if has_key(json, "should") {
    return parse_should_expr(json)
  }
  None
}

///|
fn has_key(json : String, key : String) -> Bool {
  let pattern = "\"" + key + "\""
  json.contains(pattern)
}

///|
/// Parse {"match": {"key": "k", "value": <v>}}
fn parse_match_expr(json : String) -> FilterExpr? {
  let bytes = @codec.encode_utf8(json)
  let attrs = @codec.decode_attrs_json(bytes)
  match attrs {
    None => None
    Some(outer) =>
      // "match" value is a nested object as JSON string
      // For simplicity, parse the inner {"key": ..., "value": ...}
      match outer.get("match") {
        Some(@types.String(inner_json)) => {
          let inner_bytes = @codec.encode_utf8(inner_json)
          match @codec.decode_attrs_json(inner_bytes) {
            Some(inner) => {
              let key = match inner.get("key") {
                Some(@types.String(k)) => k
                _ => return None
              }
              let value = match inner.get("value") {
                Some(v) => v
                None => return None
              }
              Some(FilterExpr::match_(key, value))
            }
            None => None
          }
        }
        _ => None
      }
  }
}

///|
/// Parse {"range": {"key": "k", "gt": n, "gte": n, "lt": n, "lte": n}}
fn parse_range_expr(json : String) -> FilterExpr? {
  let bytes = @codec.encode_utf8(json)
  match @codec.decode_attrs_json(bytes) {
    None => None
    Some(outer) =>
      match outer.get("range") {
        Some(@types.String(inner_json)) => {
          let inner_bytes = @codec.encode_utf8(inner_json)
          match @codec.decode_attrs_json(inner_bytes) {
            Some(inner) => {
              let key = match inner.get("key") {
                Some(@types.String(k)) => k
                _ => return None
              }
              let range : @types.NumericRange = {
                gt: match inner.get("gt") {
                  Some(@types.Float(n)) => Some(n)
                  Some(@types.Int(n)) => Some(n.to_double())
                  _ => None
                },
                gte: match inner.get("gte") {
                  Some(@types.Float(n)) => Some(n)
                  Some(@types.Int(n)) => Some(n.to_double())
                  _ => None
                },
                lt: match inner.get("lt") {
                  Some(@types.Float(n)) => Some(n)
                  Some(@types.Int(n)) => Some(n.to_double())
                  _ => None
                },
                lte: match inner.get("lte") {
                  Some(@types.Float(n)) => Some(n)
                  Some(@types.Int(n)) => Some(n.to_double())
                  _ => None
                },
              }
              Some(FilterExpr::range(key, range))
            }
            None => None
          }
        }
        _ => None
      }
  }
}

///|
/// Parse {"exists": {"key": "k"}}
fn parse_exists_expr(json : String) -> FilterExpr? {
  let bytes = @codec.encode_utf8(json)
  match @codec.decode_attrs_json(bytes) {
    None => None
    Some(outer) =>
      match outer.get("exists") {
        Some(@types.String(inner_json)) => {
          let inner_bytes = @codec.encode_utf8(inner_json)
          match @codec.decode_attrs_json(inner_bytes) {
            Some(inner) =>
              match inner.get("key") {
                Some(@types.String(k)) => Some(FilterExpr::exists(k))
                _ => None
              }
            None => None
          }
        }
        _ => None
      }
  }
}

///|
/// Parse {"is_null": {"key": "k"}}
fn parse_is_null_expr(json : String) -> FilterExpr? {
  let bytes = @codec.encode_utf8(json)
  match @codec.decode_attrs_json(bytes) {
    None => None
    Some(outer) =>
      match outer.get("is_null") {
        Some(@types.String(inner_json)) => {
          let inner_bytes = @codec.encode_utf8(inner_json)
          match @codec.decode_attrs_json(inner_bytes) {
            Some(inner) =>
              match inner.get("key") {
                Some(@types.String(k)) => Some(FilterExpr::is_null(k))
                _ => None
              }
            None => None
          }
        }
        _ => None
      }
  }
}

///|
/// Parse {"must": [<expr>, ...]} — recursive
fn parse_must_expr(_json : String) -> FilterExpr? {
  // TODO: implement recursive array parsing
  // For now, fall through to shorthand
  None
}

///|
fn parse_must_not_expr(_json : String) -> FilterExpr? {
  None
}

///|
fn parse_should_expr(_json : String) -> FilterExpr? {
  None
}
