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
}

///|
pub impl Show for GatewayError with fn output(self, logger) {
  match self {
    NotFound(s) => {
      logger.write_string("NotFound(")
      Show::output(s, logger)
      logger.write_string(")")
    }
    InvalidInput(s) => {
      logger.write_string("InvalidInput(")
      Show::output(s, logger)
      logger.write_string(")")
    }
    DimensionMismatch(expected~, got~) => {
      logger.write_string("DimensionMismatch(expected: ")
      Show::output(expected, logger)
      logger.write_string(", got: ")
      Show::output(got, logger)
      logger.write_string(")")
    }
    CollectionExists(s) => {
      logger.write_string("CollectionExists(")
      Show::output(s, logger)
      logger.write_string(")")
    }
    CollectionNotFound(s) => {
      logger.write_string("CollectionNotFound(")
      Show::output(s, logger)
      logger.write_string(")")
    }
    StorageError(s) => {
      logger.write_string("StorageError(")
      Show::output(s, logger)
      logger.write_string(")")
    }
  }
}

///|
/// Collection configuration
pub struct CollectionConfig {
  name : String
  dim : Int
  metric : @types.Metric
  strategy : @types.Strategy
}

///|
pub impl Show for CollectionConfig with fn output(self, logger) {
  logger.write_string("{ name: ")
  Show::output(self.name, logger)
  logger.write_string(", dim: ")
  Show::output(self.dim, logger)
  logger.write_string(", metric: ")
  Show::output(self.metric, logger)
  logger.write_string(", strategy: ")
  Show::output(self.strategy, logger)
  logger.write_string(" }")
}

///|
/// Create default collection config
pub fn CollectionConfig::default(name : String, dim : Int) -> CollectionConfig {
  {
    name,
    dim,
    metric: @types.Cosine,
    strategy: @types.Strategy::default_hnsw(),
  }
}

///|
/// Parse collection config from JSON
/// Supports both formats:
/// - {"dim": 4, "metric": "Cosine"}
/// - {"vectors": {"size": 4, "distance": "Cosine"}} (Qdrant-compatible)
pub fn CollectionConfig::from_json(
  json : Json,
) -> Result[CollectionConfig, String] {
  match json {
    Object(_) => {
      let name = get_string(json, "name").unwrap_or("")
      let dim = match parse_collection_dim(json) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      let metric = match parse_collection_metric(json) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      let strategy = match parse_collection_strategy(json) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      Ok({ name, dim, metric, strategy })
    }
    _ => Err("expected JSON object")
  }
}

///|
fn parse_collection_dim(json : Json) -> Result[Int, String] {
  match get_object(json, "vectors") {
    Some(vectors) =>
      match get_int(Json::object(vectors), "size") {
        Some(dim) =>
          if dim > 0 {
            Ok(dim)
          } else {
            Err("vectors.size must be > 0")
          }
        None => Err("vectors.size is required")
      }
    None =>
      match get_int(json, "dim") {
        Some(dim) => if dim > 0 { Ok(dim) } else { Err("dim must be > 0") }
        None => Err("dim is required")
      }
  }
}

///|
fn parse_collection_metric(json : Json) -> Result[@types.Metric, String] {
  let metric_str = match get_object(json, "vectors") {
    Some(vectors) => get_string(Json::object(vectors), "distance")
    None => get_string(json, "metric")
  }
  match metric_str {
    None => Ok(@types.Cosine)
    Some(s) =>
      match @types.Metric::from_name(s) {
        Some(m) => Ok(m)
        None => Err("unsupported metric: " + s)
      }
  }
}

///|
fn parse_collection_strategy(json : Json) -> Result[@types.Strategy, String] {
  match get_string(json, "strategy") {
    None => Ok(@types.Strategy::default_hnsw())
    Some(s) =>
      match @types.Strategy::from_name(s) {
        Some(st) => Ok(st)
        None => Err("unsupported strategy: " + s)
      }
  }
}

///|
/// Convert collection config to JSON
pub fn CollectionConfig::to_json(self : CollectionConfig) -> Json {
  let metric_str = self.metric.to_name()
  let strategy_str = self.strategy.to_name()
  json_object([
    ("name", self.name.to_json()),
    ("dim", self.dim.to_double().to_json()),
    ("metric", metric_str.to_json()),
    ("strategy", strategy_str.to_json()),
  ])
}

///|
fn vector_id_to_json(id : @types.VectorId) -> Json {
  match id {
    Int64Id(v) => int64_id_to_json(v)
    Bytes16Id(_) => id.to_display_string().to_json()
  }
}

///|
/// Single point for upsert
pub struct PointData {
  id : Int64
  vector : Array[Double]
  payload : @types.Attrs
}

///|
pub impl Show for PointData with fn output(self, logger) {
  logger.write_string("{ id: ")
  Show::output(self.id, logger)
  logger.write_string(", vector: ")
  Show::output(self.vector, logger)
  logger.write_string(", payload: ")
  Show::output(self.payload, logger)
  logger.write_string(" }")
}

///|
/// Parse point from JSON
pub fn PointData::from_json(json : Json) -> PointData? {
  match json {
    Object(_) => {
      let id = match get_int64_id(json, "id") {
        Some(i) => i
        None => return None
      }
      let vector_json = match get_array(json, "vector") {
        Some(arr) => arr
        None => return None
      }
      let vector = match json_to_vector(Json::array(vector_json)) {
        Some(v) => v
        None => return None
      }
      let payload = match get_object(json, "payload") {
        Some(obj) =>
          match json_to_attrs(Json::object(obj)) {
            Some(attrs) => attrs
            None => return None
          }
        None => @types.empty_attrs()
      }
      Some({ id, vector, payload })
    }
    _ => None
  }
}

///|
/// Convert point to JSON
pub fn PointData::to_json(self : PointData) -> Json {
  json_object([
    ("id", int64_id_to_json(self.id)),
    ("vector", vector_to_json(self.vector)),
    ("payload", attrs_to_json(self.payload)),
  ])
}

///|
/// Upsert request (batch)
pub struct UpsertRequest {
  points : Array[PointData]
}

///|
pub impl Show for UpsertRequest with fn output(self, logger) {
  logger.write_string("{ points: ")
  Show::output(self.points, logger)
  logger.write_string(" }")
}

///|
/// Parse upsert request from JSON
pub fn UpsertRequest::from_json(json : Json) -> UpsertRequest? {
  match json {
    Object(_) => {
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
  filter : Json?
  with_payload : Bool
  with_vector : Bool
}

///|
pub impl Show for SearchRequest with fn output(self, logger) {
  logger.write_string("{ vector: ")
  Show::output(self.vector, logger)
  logger.write_string(", limit: ")
  Show::output(self.limit, logger)
  logger.write_string(", filter: ")
  Debug::to_repr(self.filter).output(logger)
  logger.write_string(", with_payload: ")
  Show::output(self.with_payload, logger)
  logger.write_string(", with_vector: ")
  Show::output(self.with_vector, logger)
  logger.write_string(" }")
}

///|
/// Parse search request from JSON
pub fn SearchRequest::from_json(json : Json) -> SearchRequest? {
  match json {
    Object(_) => {
      let vector_json = match get_array(json, "vector") {
        Some(arr) => arr
        None => return None
      }
      let vector = match json_to_vector(Json::array(vector_json)) {
        Some(v) => v
        None => return None
      }
      let limit = get_int(json, "limit").unwrap_or(10)
      let with_payload = get_bool(json, "with_payload").unwrap_or(true)
      let with_vector = get_bool(json, "with_vector").unwrap_or(false)
      let filter : Json? = match get_object(json, "filter") {
        Some(f) => Some(Json::object(f))
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
  id : @types.VectorId
  score : Double
  payload : @types.Attrs?
  vector : Array[Double]?
}

///|
pub impl Show for SearchHitResponse with fn output(self, logger) {
  logger.write_string("{ id: ")
  Show::output(self.id, logger)
  logger.write_string(", score: ")
  Show::output(self.score, logger)
  logger.write_string(", payload: ")
  Debug::to_repr(self.payload).output(logger)
  logger.write_string(", vector: ")
  Debug::to_repr(self.vector).output(logger)
  logger.write_string(" }")
}

///|
/// Convert search hit to JSON
pub fn SearchHitResponse::to_json(self : SearchHitResponse) -> Json {
  let parts : Array[(String, Json)] = [
    ("id", vector_id_to_json(self.id)),
    ("score", self.score.to_json()),
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
}

///|
pub impl Show for SearchResponse with fn output(self, logger) {
  logger.write_string("{ result: ")
  Show::output(self.result, logger)
  logger.write_string(", time_ms: ")
  Show::output(self.time_ms, logger)
  logger.write_string(" }")
}

///|
/// Convert search response to JSON
pub fn SearchResponse::to_json(self : SearchResponse) -> Json {
  let results = Json::array(self.result.map(fn(h) { h.to_json() }))
  json_object([("result", results), ("time", self.time_ms.to_json())])
}

///|
/// Point response (for get operations)
pub struct PointResponse {
  id : @types.VectorId
  payload : @types.Attrs
  vector : Array[Double]
}

///|
pub impl Show for PointResponse with fn output(self, logger) {
  logger.write_string("{ id: ")
  Show::output(self.id, logger)
  logger.write_string(", payload: ")
  Show::output(self.payload, logger)
  logger.write_string(", vector: ")
  Show::output(self.vector, logger)
  logger.write_string(" }")
}

///|
/// Convert point response to JSON
pub fn PointResponse::to_json(self : PointResponse) -> Json {
  json_object([
    ("id", vector_id_to_json(self.id)),
    ("payload", attrs_to_json(self.payload)),
    ("vector", vector_to_json(self.vector)),
  ])
}

///|
/// Scroll request, modelled after Qdrant's scroll points API.
pub struct ScrollRequest {
  offset : Int64?
  limit : Int
  with_payload : Bool
  with_vector : Bool
}

///|
pub impl Show for ScrollRequest with fn output(self, logger) {
  logger.write_string("{ offset: ")
  Debug::to_repr(self.offset).output(logger)
  logger.write_string(", limit: ")
  Show::output(self.limit, logger)
  logger.write_string(", with_payload: ")
  Show::output(self.with_payload, logger)
  logger.write_string(", with_vector: ")
  Show::output(self.with_vector, logger)
  logger.write_string(" }")
}

///|
pub fn ScrollRequest::from_json(json : Json) -> ScrollRequest? {
  match json {
    Object(_) =>
      Some({
        offset: get_int64_id(json, "offset"),
        limit: get_int(json, "limit").unwrap_or(10),
        with_payload: get_bool(json, "with_payload").unwrap_or(true),
        with_vector: get_bool(json, "with_vector").unwrap_or(false),
      })
    _ => None
  }
}

///|
pub struct ScrollPointResponse {
  id : @types.VectorId
  payload : @types.Attrs?
  vector : Array[Double]?
}

///|
pub impl Show for ScrollPointResponse with fn output(self, logger) {
  logger.write_string("{ id: ")
  Show::output(self.id, logger)
  logger.write_string(", payload: ")
  Debug::to_repr(self.payload).output(logger)
  logger.write_string(", vector: ")
  Debug::to_repr(self.vector).output(logger)
  logger.write_string(" }")
}

///|
pub fn ScrollPointResponse::to_json(self : ScrollPointResponse) -> Json {
  let parts : Array[(String, Json)] = [("id", vector_id_to_json(self.id))]
  match self.payload {
    Some(payload) => parts.push(("payload", attrs_to_json(payload)))
    None => ()
  }
  match self.vector {
    Some(vector) => parts.push(("vector", vector_to_json(vector)))
    None => ()
  }
  json_object(parts)
}

///|
pub struct ScrollResponse {
  points : Array[ScrollPointResponse]
  next_page_offset : @types.VectorId?
}

///|
pub impl Show for ScrollResponse with fn output(self, logger) {
  logger.write_string("{ points: ")
  Show::output(self.points, logger)
  logger.write_string(", next_page_offset: ")
  Debug::to_repr(self.next_page_offset).output(logger)
  logger.write_string(" }")
}

///|
pub fn ScrollResponse::to_json(self : ScrollResponse) -> Json {
  let parts : Array[(String, Json)] = [
    ("points", Json::array(self.points.map(fn(point) { point.to_json() }))),
  ]
  match self.next_page_offset {
    Some(offset) => parts.push(("next_page_offset", vector_id_to_json(offset)))
    None => ()
  }
  json_object(parts)
}

///|
/// Collection info response
pub struct CollectionInfo {
  name : String
  vectors_count : Int
  dim : Int
  metric : String
  strategy : String
}

///|
pub impl Show for CollectionInfo with fn output(self, logger) {
  logger.write_string("{ name: ")
  Show::output(self.name, logger)
  logger.write_string(", vectors_count: ")
  Show::output(self.vectors_count, logger)
  logger.write_string(", dim: ")
  Show::output(self.dim, logger)
  logger.write_string(", metric: ")
  Show::output(self.metric, logger)
  logger.write_string(", strategy: ")
  Show::output(self.strategy, logger)
  logger.write_string(" }")
}

///|
/// Convert collection info to JSON
pub fn CollectionInfo::to_json(self : CollectionInfo) -> Json {
  json_object([
    ("name", self.name.to_json()),
    ("vectors_count", self.vectors_count.to_double().to_json()),
    ("dim", self.dim.to_double().to_json()),
    ("metric", self.metric.to_json()),
    ("strategy", self.strategy.to_json()),
  ])
}

///|
/// Collections list response
pub struct CollectionsResponse {
  collections : Array[CollectionInfo]
}

///|
pub impl Show for CollectionsResponse with fn output(self, logger) {
  logger.write_string("{ collections: ")
  Show::output(self.collections, logger)
  logger.write_string(" }")
}

///|
/// Convert collections list to JSON
pub fn CollectionsResponse::to_json(self : CollectionsResponse) -> Json {
  let collections = Json::array(self.collections.map(fn(c) { c.to_json() }))
  json_object([("collections", collections)])
}

///|
/// Generic API response wrapper
pub struct ApiResponse {
  status : String
  result : Json?
  error : String?
}

///|
pub impl Show for ApiResponse with fn output(self, logger) {
  logger.write_string("{ status: ")
  Show::output(self.status, logger)
  logger.write_string(", result: ")
  Debug::to_repr(self.result).output(logger)
  logger.write_string(", error: ")
  Debug::to_repr(self.error).output(logger)
  logger.write_string(" }")
}

///|
/// Create success response
pub fn ApiResponse::ok(result : Json) -> ApiResponse {
  { status: "ok", result: Some(result), error: None }
}

///|
/// Create error response
pub fn ApiResponse::err(message : String) -> ApiResponse {
  { status: "error", result: None, error: Some(message) }
}

///|
/// Convert API response to JSON
pub fn ApiResponse::to_json(self : ApiResponse) -> Json {
  let parts : Array[(String, Json)] = [("status", self.status.to_json())]
  match self.result {
    Some(r) => parts.push(("result", r))
    None => ()
  }
  match self.error {
    Some(e) => parts.push(("error", e.to_json()))
    None => ()
  }
  json_object(parts)
}
