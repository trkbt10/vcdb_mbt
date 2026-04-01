///|
/// Command handlers for gateway API
/// These handlers implement the business logic for CLI and HTTP operations

///|
/// Handle upsert points into a collection
/// Returns (count, needs_persist) - caller should persist if needed
pub fn handle_upsert(
  db : @vcdb.VectorDB,
  req : UpsertRequest,
) -> Result[Int, GatewayError] {
  let dim = db.dim()
  let mut count = 0
  for point in req.points {
    let vec_dim = point.vector.length()
    if vec_dim != dim {
      return Err(DimensionMismatch(expected=dim, got=vec_dim))
    }
    let id = @types.VectorId::from_int64(point.id)
    let _ = db.upsert(id, point.vector, point.payload)
    count = count + 1
  }
  Ok(count)
}

///|
/// Handle search in a collection
pub fn handle_search(
  db : @vcdb.VectorDB,
  req : SearchRequest,
) -> Result[SearchResponse, GatewayError] {
  let dim = db.dim()
  if req.vector.length() != dim {
    return Err(DimensionMismatch(expected=dim, got=req.vector.length()))
  }
  // Note: filter is not yet implemented (would need to parse JSON filter to FilterExpr)
  let hits = db.search(req.vector, req.limit, None)
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
/// Handle get point by ID
pub fn handle_get_point(
  db : @vcdb.VectorDB,
  id : Int64,
) -> Result[PointResponse, GatewayError] {
  let vec_id = @types.VectorId::from_int64(id)
  match db.get(vec_id) {
    Some(record) => Ok({ id, payload: record.attrs, vector: record.vector })
    None => Err(NotFound("Point with id " + id.to_string() + " not found"))
  }
}

///|
/// Handle scrolling points in a collection.
pub fn handle_scroll(
  db : @vcdb.VectorDB,
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
/// Handle delete point by ID
pub fn handle_delete_point(
  db : @vcdb.VectorDB,
  id : Int64,
) -> Result[Unit, GatewayError] {
  let vec_id = @types.VectorId::from_int64(id)
  if not(db.has(vec_id)) {
    return Err(NotFound("Point with id " + id.to_string() + " not found"))
  }
  let _ = db.remove(vec_id)
  Ok(())
}

///|
/// Handle collection creation
pub fn[S : @storage.Storage] handle_create_collection(
  manager : CollectionManager[S],
  config : CollectionConfig,
) -> Result[Unit, GatewayError] {
  manager.create(config)
}

///|
/// Handle collection deletion
pub fn[S : @storage.Storage] handle_delete_collection(
  manager : CollectionManager[S],
  name : String,
) -> Result[Unit, GatewayError] {
  manager.delete(name)
}

///|
/// Handle list collections
pub fn[S : @storage.Storage] handle_list_collections(
  manager : CollectionManager[S],
) -> CollectionsResponse {
  { collections: manager.list_info() }
}

///|
/// Handle get collection info
pub fn[S : @storage.Storage] handle_get_collection(
  manager : CollectionManager[S],
  name : String,
) -> Result[CollectionInfo, GatewayError] {
  match manager.get_info(name) {
    Some(info) => Ok(info)
    None => Err(CollectionNotFound(name))
  }
}

///|
/// Convenience: Handle request with collection name
pub fn[S : @storage.Storage, T] with_collection(
  manager : CollectionManager[S],
  name : String,
  handler : (@vcdb.VectorDB) -> Result[T, GatewayError],
) -> Result[T, GatewayError] {
  match manager.get(name) {
    Some(db) => handler(db)
    None => Err(CollectionNotFound(name))
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
/// Parse and execute an API request, returning JSON response
pub fn[S : @storage.Storage] execute_request(
  manager : CollectionManager[S],
  http_method : String,
  path : Array[String],
  body : String,
) -> ApiResponse {
  match (http_method, path) {
    ("GET", []) => ApiResponse::ok(handle_service_info())
    ("GET", ["healthz"]) => ApiResponse::ok(handle_health())
    ("GET", ["collections"]) => {
      let resp = handle_list_collections(manager)
      ApiResponse::ok(resp.to_json())
    }
    ("POST", ["collections", name]) => {
      let config = match parse_json(body) {
        Some(json) => {
          let base = CollectionConfig::from_json(json).unwrap_or(
            CollectionConfig::default(name, 128),
          )
          // Create new config with the URL name
          { ..base, name, }
        }
        None => CollectionConfig::default(name, 128)
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
      match with_collection(manager, name, fn(db) { handle_upsert(db, req) }) {
        Ok(count) => {
          // Record upserts to WAL for differential persistence
          let wal_points : Array[(@types.VectorId, Array[Double], @types.Attrs)] = req
            .points
            .map(fn(p) {
              (@types.VectorId::from_int64(p.id), p.vector, p.payload)
            })
          manager.notify_upsert(name, wal_points)
          ApiResponse::ok(
            json_object([
              ("status", JString("ok")),
              ("upserted", JNumber(count.to_double())),
            ]),
          )
        }
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
      match
        with_collection(manager, name, fn(db) { handle_delete_point(db, id) }) {
        Ok(_) => {
          manager.notify_remove(name, [@types.VectorId::from_int64(id)])
          ApiResponse::ok(JBool(true))
        }
        Err(e) => ApiResponse::err(error_to_string(e))
      }
    }
    _ => ApiResponse::err("Not found")
  }
}
