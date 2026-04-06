///|
/// Command handlers for gateway API
/// These handlers implement the business logic for CLI and HTTP operations
///
/// Write operations are async (WAL-before-state via PersistentVectorDB).
/// Read operations are sync (in-memory VectorDB).

///|
/// Handle search in a collection (sync — reads from in-memory engine)
pub fn[W, S] handle_search(
  db : @vcdb.VectorDB[W, S],
  req : SearchRequest,
) -> Result[SearchResponse, GatewayError] {
  let dim = db.dim()
  if req.vector.length() != dim {
    return Err(DimensionMismatch(expected=dim, got=req.vector.length()))
  }
  let filter = match req.filter {
    Some(json) => @filter.parse_filter_json(json.to_string())
    None => None
  }
  let hits = db.search(req.vector, req.limit, filter)
  let results : Array[SearchHitResponse] = []
  for hit in hits {
    let payload = if req.with_payload { Some(hit.attrs) } else { None }
    let vector = if req.with_vector {
      match db.get(hit.id) {
        Some(rec) => Some(rec.vector)
        None => None
      }
    } else {
      None
    }
    results.push({ id: hit.id.to_int64(), score: hit.score, payload, vector })
  }
  Ok({ result: results, time_ms: 0.0 })
}

///|
/// Handle get point by ID (sync)
pub fn[W, S] handle_get_point(
  db : @vcdb.VectorDB[W, S],
  id : Int64,
) -> Result[PointResponse, GatewayError] {
  let vec_id = @types.VectorId::from_int64(id)
  match db.get(vec_id) {
    Some(record) => Ok({ id, payload: record.attrs, vector: record.vector })
    None => Err(NotFound("Point with id " + id.to_string() + " not found"))
  }
}

///|
/// Handle scrolling points in a collection (sync).
pub fn[W, S] handle_scroll(
  db : @vcdb.VectorDB[W, S],
  req : ScrollRequest,
) -> Result[ScrollResponse, GatewayError] {
  let entries = db.scroll(offset=req.offset, limit=req.limit)
  let points : Array[ScrollPointResponse] = []
  for i, entry in entries {
    let (id, record) = entry
    points.push({
      id: id.to_int64(),
      payload: if req.with_payload {
        Some(record.attrs)
      } else {
        None
      },
      vector: if req.with_vector {
        Some(record.vector)
      } else {
        None
      },
    })
    ignore(i)
  }
  let next_page_offset = if entries.length() < req.limit {
    None
  } else {
    match entries.last() {
      Some((id, _)) => Some(id.to_int64() + 1L)
      None => None
    }
  }
  Ok({ points, next_page_offset })
}

///|
/// Handle collection creation (async — writes to storage)
pub async fn[S : @storage.AsyncStorage] handle_create_collection(
  manager : CollectionManager[S],
  config : CollectionConfig,
) -> Result[Unit, GatewayError] {
  manager.create(config)
}

///|
/// Handle collection deletion (async — writes to storage)
pub async fn[S : @storage.AsyncStorage] handle_delete_collection(
  manager : CollectionManager[S],
  name : String,
) -> Result[Unit, GatewayError] {
  manager.delete(name)
}

///|
/// Handle list collections (async — may load from storage)
pub async fn[S : @storage.AsyncStorage] handle_list_collections(
  manager : CollectionManager[S],
) -> Result[CollectionsResponse, GatewayError] {
  match manager.list_info() {
    Ok(collections) => Ok({ collections, })
    Err(err) => Err(err)
  }
}

///|
/// Handle get collection info (async — may load from storage)
pub async fn[S : @storage.AsyncStorage] handle_get_collection(
  manager : CollectionManager[S],
  name : String,
) -> Result[CollectionInfo, GatewayError] {
  manager.get_info(name)
}

///|
/// Convenience: Handle request with collection name (async)
pub async fn[S : @storage.AsyncStorage, T] with_collection(
  manager : CollectionManager[S],
  name : String,
  handler : (@vcdb.VectorDB[S, S]) -> Result[T, GatewayError],
) -> Result[T, GatewayError] {
  match manager.get(name) {
    Ok(db) => handler(db)
    Err(err) => Err(err)
  }
}

///|
/// Handle health check
pub fn handle_health() -> JsonValue {
  json_object([("status", JString("ok"))])
}

///|
/// Handle service info
pub fn handle_service_info() -> JsonValue {
  json_object([
    ("name", JString("vcdb")),
    ("version", JString("0.1.0")),
    ("description", JString("MoonBit vector database")),
  ])
}

///|
/// Helper to format GatewayError to string
fn error_to_string(e : GatewayError) -> String {
  match e {
    NotFound(s) => "Not found: " + s
    InvalidInput(s) => "Invalid input: " + s
    DimensionMismatch(expected~, got~) =>
      "Dimension mismatch: expected " +
      expected.to_string() +
      ", got " +
      got.to_string()
    CollectionExists(s) => "Collection already exists: " + s
    CollectionNotFound(s) => "Collection not found: " + s
    StorageError(s) => "Storage error: " + s
  }
}

///|
/// Parse and execute an API request, returning JSON response.
/// All operations are now async since collection loading and writes require I/O.
pub async fn[S : @storage.AsyncStorage] execute_request(
  manager : CollectionManager[S],
  http_method : String,
  path : Array[String],
  body : String,
) -> ApiResponse {
  match (http_method, path) {
    ("GET", []) => ApiResponse::ok(handle_service_info())
    ("GET", ["healthz"]) => ApiResponse::ok(handle_health())
    ("GET", ["collections"]) =>
      match handle_list_collections(manager) {
        Ok(resp) => ApiResponse::ok(resp.to_json())
        Err(e) => ApiResponse::err(error_to_string(e))
      }
    ("POST", ["collections", name]) => {
      let config = match parse_json(body) {
        Some(json) => {
          let base = match CollectionConfig::from_json(json) {
            Ok(parsed) => parsed
            Err(msg) => return ApiResponse::err("Invalid request body: " + msg)
          }
          { ..base, name, }
        }
        None => return ApiResponse::err("Invalid JSON")
      }
      match handle_create_collection(manager, config) {
        Ok(_) => ApiResponse::ok(JBool(true))
        Err(e) => ApiResponse::err(error_to_string(e))
      }
    }
    ("GET", ["collections", name]) =>
      match handle_get_collection(manager, name) {
        Ok(info) => ApiResponse::ok(info.to_json())
        Err(e) => ApiResponse::err(error_to_string(e))
      }
    ("DELETE", ["collections", name]) =>
      match handle_delete_collection(manager, name) {
        Ok(_) => ApiResponse::ok(JBool(true))
        Err(e) => ApiResponse::err(error_to_string(e))
      }
    ("PUT", ["collections", name, "points"]) => {
      let req = match parse_json(body) {
        Some(json) =>
          match UpsertRequest::from_json(json) {
            Some(r) => r
            None => return ApiResponse::err("Invalid request body")
          }
        None => return ApiResponse::err("Invalid JSON")
      }
      let points : Array[(@types.VectorId, Array[Double], @types.Attrs)] = req.points.map(fn(
          p,
        ) {
          (@types.VectorId::from_int64(p.id), p.vector, p.payload)
        },
      )
      match manager.upsert_points(name, points) {
        Ok(count) =>
          ApiResponse::ok(
            json_object([
              ("status", JString("ok")),
              ("upserted", JNumber(count.to_double())),
            ]),
          )
        Err(e) => ApiResponse::err(error_to_string(e))
      }
    }
    ("POST", ["collections", name, "points", "search"]) => {
      let req = match parse_json(body) {
        Some(json) =>
          match SearchRequest::from_json(json) {
            Some(r) => r
            None => return ApiResponse::err("Invalid request body")
          }
        None => return ApiResponse::err("Invalid JSON")
      }
      match with_collection(manager, name, fn(db) { handle_search(db, req) }) {
        Ok(resp) => ApiResponse::ok(resp.to_json())
        Err(e) => ApiResponse::err(error_to_string(e))
      }
    }
    ("POST", ["collections", name, "points", "scroll"]) => {
      let req = if body.length() == 0 {
        { offset: None, limit: 10, with_payload: true, with_vector: false }
      } else {
        match parse_json(body) {
          Some(json) =>
            match ScrollRequest::from_json(json) {
              Some(r) => r
              None => return ApiResponse::err("Invalid request body")
            }
          None => return ApiResponse::err("Invalid JSON")
        }
      }
      match with_collection(manager, name, fn(db) { handle_scroll(db, req) }) {
        Ok(resp) => ApiResponse::ok(resp.to_json())
        Err(e) => ApiResponse::err(error_to_string(e))
      }
    }
    ("GET", ["collections", name, "points", id_str]) => {
      let parse_result : Result[Int64, _] = try? @strconv.parse_int64(id_str)
      let id : Int64 = match parse_result {
        Ok(i) => i
        Err(_) => return ApiResponse::err("Invalid point ID")
      }
      match
        with_collection(manager, name, fn(db) { handle_get_point(db, id) }) {
        Ok(point) => ApiResponse::ok(point.to_json())
        Err(e) => ApiResponse::err(error_to_string(e))
      }
    }
    ("DELETE", ["collections", name, "points", id_str]) => {
      let parse_result : Result[Int64, _] = try? @strconv.parse_int64(id_str)
      let id : Int64 = match parse_result {
        Ok(i) => i
        Err(_) => return ApiResponse::err("Invalid point ID")
      }
      match manager.remove_point(name, @types.VectorId::from_int64(id)) {
        Ok(_) => ApiResponse::ok(JBool(true))
        Err(e) => ApiResponse::err(error_to_string(e))
      }
    }
    _ => ApiResponse::err("Not found")
  }
}
