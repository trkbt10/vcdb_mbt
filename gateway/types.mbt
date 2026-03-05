///|
/// Gateway API types for CLI and HTTP server

///|
/// Gateway errors
pub(all) suberror GatewayError {
  NotFound(String)
  InvalidInput(String)
  DimensionMismatch(expected~ : Int, got~ : Int)
  CollectionExists(String)
  CollectionNotFound(String)
  StorageError(String)
} derive(Show)

///|
/// Collection configuration
pub struct CollectionConfig {
  name : String
  dim : Int
  metric : @types.Metric
  strategy : @types.Strategy
} derive(Show)

///|
/// Create default collection config
pub fn CollectionConfig::default(name : String, dim : Int) -> CollectionConfig {
  {
    name,
    dim,
    metric: @types.Cosine,
    strategy: @types.HNSW(@types.HNSWParams::default()),
  }
}

///|
/// Parse collection config from JSON
/// Supports both formats:
/// - {"dim": 4, "metric": "Cosine"}
/// - {"vectors": {"size": 4, "distance": "Cosine"}} (Qdrant-compatible)
pub fn CollectionConfig::from_json(json : JsonValue) -> CollectionConfig? {
  match json {
    JObject(_) => {
      let name = get_string(json, "name").unwrap_or("")
      // Support both formats for dimension
      let dim = match get_object(json, "vectors") {
        Some(vectors) => get_int(JObject(vectors), "size").unwrap_or(128)
        None => get_int(json, "dim").unwrap_or(128)
      }
      // Support both formats for metric
      let metric_str = match get_object(json, "vectors") {
        Some(vectors) => get_string(JObject(vectors), "distance")
        None => get_string(json, "metric")
      }
      let metric = match metric_str {
        Some("l2") | Some("L2") => @types.L2
        Some("dot") | Some("Dot") => @types.Dot
        _ => @types.Cosine
      }
      let strategy = match get_string(json, "strategy") {
        Some("bruteforce") | Some("Bruteforce") => @types.Bruteforce
        Some("ivf") | Some("IVF") => @types.IVF(@types.IVFParams::default())
        _ => @types.HNSW(@types.HNSWParams::default())
      }
      Some({ name, dim, metric, strategy })
    }
    _ => None
  }
}

///|
/// Convert collection config to JSON
pub fn CollectionConfig::to_json(self : CollectionConfig) -> JsonValue {
  let metric_str = match self.metric {
    @types.Cosine => "Cosine"
    @types.L2 => "L2"
    @types.Dot => "Dot"
  }
  let strategy_str = match self.strategy {
    @types.Bruteforce => "Bruteforce"
    @types.HNSW(_) => "HNSW"
    @types.IVF(_) => "IVF"
  }
  json_object([
    ("name", JString(self.name)),
    ("dim", JNumber(self.dim.to_double())),
    ("metric", JString(metric_str)),
    ("strategy", JString(strategy_str)),
  ])
}

///|
/// Single point for upsert
pub struct PointData {
  id : Int64
  vector : Array[Double]
  payload : @types.Attrs
} derive(Show)

///|
/// Parse point from JSON
pub fn PointData::from_json(json : JsonValue) -> PointData? {
  match json {
    JObject(_) => {
      let id = match get_int64(json, "id") {
        Some(i) => i
        None => return None
      }
      let vector_json = match get_array(json, "vector") {
        Some(arr) => arr
        None => return None
      }
      let vector = match json_to_vector(JArray(vector_json)) {
        Some(v) => v
        None => return None
      }
      let payload = match get_object(json, "payload") {
        Some(obj) => json_to_attrs(JObject(obj)).unwrap_or(@types.empty_attrs())
        None => @types.empty_attrs()
      }
      Some({ id, vector, payload })
    }
    _ => None
  }
}

///|
/// Convert point to JSON
pub fn PointData::to_json(self : PointData) -> JsonValue {
  json_object([
    ("id", JNumber(self.id.to_double())),
    ("vector", vector_to_json(self.vector)),
    ("payload", attrs_to_json(self.payload)),
  ])
}

///|
/// Upsert request (batch)
pub struct UpsertRequest {
  points : Array[PointData]
} derive(Show)

///|
/// Parse upsert request from JSON
pub fn UpsertRequest::from_json(json : JsonValue) -> UpsertRequest? {
  match json {
    JObject(_) => {
      let points_json = match get_array(json, "points") {
        Some(arr) => arr
        None => return None
      }
      let points : Array[PointData] = []
      for p in points_json {
        match PointData::from_json(p) {
          Some(point) => points.push(point)
          None => return None
        }
      }
      Some({ points, })
    }
    _ => None
  }
}

///|
/// Search request
pub struct SearchRequest {
  vector : Array[Double]
  limit : Int
  filter : JsonValue? // Optional filter expression as JSON
  with_payload : Bool
  with_vector : Bool
} derive(Show)

///|
/// Parse search request from JSON
pub fn SearchRequest::from_json(json : JsonValue) -> SearchRequest? {
  match json {
    JObject(_) => {
      let vector_json = match get_array(json, "vector") {
        Some(arr) => arr
        None => return None
      }
      let vector = match json_to_vector(JArray(vector_json)) {
        Some(v) => v
        None => return None
      }
      let limit = get_int(json, "limit").unwrap_or(10)
      let with_payload = get_bool(json, "with_payload").unwrap_or(true)
      let with_vector = get_bool(json, "with_vector").unwrap_or(false)
      let filter = match get_object(json, "filter") {
        Some(f) => Some(JObject(f))
        None => None
      }
      Some({ vector, limit, filter, with_payload, with_vector })
    }
    _ => None
  }
}

///|
/// Search hit (result item)
pub struct SearchHitResponse {
  id : Int64
  score : Double
  payload : @types.Attrs?
  vector : Array[Double]?
} derive(Show)

///|
/// Convert search hit to JSON
pub fn SearchHitResponse::to_json(self : SearchHitResponse) -> JsonValue {
  let parts : Array[(String, JsonValue)] = [
    ("id", JNumber(self.id.to_double())),
    ("score", JNumber(self.score)),
  ]
  match self.payload {
    Some(p) => parts.push(("payload", attrs_to_json(p)))
    None => ()
  }
  match self.vector {
    Some(v) => parts.push(("vector", vector_to_json(v)))
    None => ()
  }
  json_object(parts)
}

///|
/// Search response
pub struct SearchResponse {
  result : Array[SearchHitResponse]
  time_ms : Double
} derive(Show)

///|
/// Convert search response to JSON
pub fn SearchResponse::to_json(self : SearchResponse) -> JsonValue {
  let results = JArray(self.result.map(fn(h) { h.to_json() }))
  json_object([("result", results), ("time", JNumber(self.time_ms))])
}

///|
/// Point response (for get operations)
pub struct PointResponse {
  id : Int64
  payload : @types.Attrs
  vector : Array[Double]
} derive(Show)

///|
/// Convert point response to JSON
pub fn PointResponse::to_json(self : PointResponse) -> JsonValue {
  json_object([
    ("id", JNumber(self.id.to_double())),
    ("payload", attrs_to_json(self.payload)),
    ("vector", vector_to_json(self.vector)),
  ])
}

///|
/// Collection info response
pub struct CollectionInfo {
  name : String
  vectors_count : Int
  dim : Int
  metric : String
  strategy : String
} derive(Show)

///|
/// Convert collection info to JSON
pub fn CollectionInfo::to_json(self : CollectionInfo) -> JsonValue {
  json_object([
    ("name", JString(self.name)),
    ("vectors_count", JNumber(self.vectors_count.to_double())),
    ("dim", JNumber(self.dim.to_double())),
    ("metric", JString(self.metric)),
    ("strategy", JString(self.strategy)),
  ])
}

///|
/// Collections list response
pub struct CollectionsResponse {
  collections : Array[CollectionInfo]
} derive(Show)

///|
/// Convert collections list to JSON
pub fn CollectionsResponse::to_json(self : CollectionsResponse) -> JsonValue {
  let collections = JArray(self.collections.map(fn(c) { c.to_json() }))
  json_object([("collections", collections)])
}

///|
/// Generic API response wrapper
pub struct ApiResponse {
  status : String
  result : JsonValue?
  error : String?
} derive(Show)

///|
/// Create success response
pub fn ApiResponse::ok(result : JsonValue) -> ApiResponse {
  { status: "ok", result: Some(result), error: None }
}

///|
/// Create error response
pub fn ApiResponse::err(message : String) -> ApiResponse {
  { status: "error", result: None, error: Some(message) }
}

///|
/// Convert API response to JSON
pub fn ApiResponse::to_json(self : ApiResponse) -> JsonValue {
  let parts : Array[(String, JsonValue)] = [("status", JString(self.status))]
  match self.result {
    Some(r) => parts.push(("result", r))
    None => ()
  }
  match self.error {
    Some(e) => parts.push(("error", JString(e)))
    None => ()
  }
  json_object(parts)
}
