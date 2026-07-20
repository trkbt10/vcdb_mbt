///|
/// HTTP router for vcdb REST API
/// Parses HTTP requests and routes to gateway handlers

///|
/// HTTP request representation
pub struct HttpRequest {
  http_method : String
  path : String
  headers : Map[String, String]
  body : String
}

///|
pub impl Show for HttpRequest with fn output(self, logger) {
  logger.write_string("{ http_method: ")
  Show::output(self.http_method, logger)
  logger.write_string(", path: ")
  Show::output(self.path, logger)
  logger.write_string(", headers: ")
  Show::output(self.headers, logger)
  logger.write_string(", body: ")
  Show::output(self.body, logger)
  logger.write_string(" }")
}

///|
/// HTTP response representation
pub struct HttpResponse {
  status : Int
  headers : Map[String, String]
  body : String
}

///|
pub impl Show for HttpResponse with fn output(self, logger) {
  logger.write_string("{ status: ")
  Show::output(self.status, logger)
  logger.write_string(", headers: ")
  Show::output(self.headers, logger)
  logger.write_string(", body: ")
  Show::output(self.body, logger)
  logger.write_string(" }")
}

///|
/// Create an HTTP request
pub fn HttpRequest::new(
  http_method : String,
  path : String,
  body? : String = "",
) -> HttpRequest {
  { http_method, path, headers: {}, body }
}

///|
/// Create an HTTP response
pub fn HttpResponse::new(
  status : Int,
  body : String,
  content_type? : String = "application/json",
) -> HttpResponse {
  let headers : Map[String, String] = {}
  headers["Content-Type"] = content_type
  { status, headers, body }
}

///|
/// Common response helpers
pub fn HttpResponse::ok(body : String) -> HttpResponse {
  HttpResponse::new(200, body)
}

///|
pub fn HttpResponse::created(body : String) -> HttpResponse {
  HttpResponse::new(201, body)
}

///|
pub fn HttpResponse::bad_request(body : String) -> HttpResponse {
  HttpResponse::new(400, body)
}

///|
pub fn HttpResponse::not_found(body : String) -> HttpResponse {
  HttpResponse::new(404, body)
}

///|
pub fn HttpResponse::internal_error(body : String) -> HttpResponse {
  HttpResponse::new(500, body)
}

///|
/// Parse query string into key-value pairs
pub fn parse_query(query : String) -> Map[String, String] {
  let params : Map[String, String] = {}
  if query.length() == 0 {
    return params
  }
  let parts = split_string(query, '&')
  for part in parts {
    let kv = split_string(part, '=')
    if kv.length() >= 2 {
      params[kv[0]] = kv[1]
    } else if kv.length() == 1 {
      params[kv[0]] = ""
    }
  }
  params
}

///|
/// Split string by delimiter
fn split_string(s : String, delim : Char) -> Array[String] {
  let parts : Array[String] = []
  let current : Array[Char] = []
  for c in s {
    if c == delim {
      parts.push(String::from_array(current))
      current.clear()
    } else {
      current.push(c)
    }
  }
  parts.push(String::from_array(current))
  parts
}

///|
/// HTTP router that wraps gateway handlers
pub struct Router[S] {
  manager : @gateway.CollectionManager[S]
}

///|
/// Create a new router
pub fn[S] Router::new(base_path? : String = "./storage") -> Router[S] {
  { manager: @gateway.CollectionManager::new(base_path~) }
}

///|
/// Create a new router with an explicit storage backend
pub fn[S] Router::with_storage(
  storage : S,
  base_path? : String = "./storage",
) -> Router[S] {
  { manager: @gateway.CollectionManager::with_storage(storage, base_path~) }
}

///|
/// Get the collection manager
pub fn[S] Router::get_manager(
  self : Router[S],
) -> @gateway.CollectionManager[S] {
  self.manager
}

///|
/// Route an HTTP request to the appropriate handler (async)
pub async fn[S : @storage.AsyncStorage] Router::route(
  self : Router[S],
  request : HttpRequest,
) -> HttpResponse {
  let response = @gateway.execute_path_request(
    self.manager,
    request.http_method,
    request.path,
    request.body,
  )

  // Convert gateway response to HTTP response
  let json_body = response.to_json().stringify()
  if response.status == "ok" {
    HttpResponse::ok(json_body)
  } else {
    // Determine appropriate status code based on error
    match response.error {
      Some(e) =>
        if e.has_prefix("Not found") || e.has_prefix("Collection not found") {
          HttpResponse::not_found(json_body)
        } else if e.has_prefix("Invalid") || e.has_prefix("Dimension mismatch") {
          HttpResponse::bad_request(json_body)
        } else {
          HttpResponse::internal_error(json_body)
        }
      None => HttpResponse::bad_request(json_body)
    }
  }
}

///|
/// Convenience method to handle a raw HTTP request (async)
pub async fn[S : @storage.AsyncStorage] handle_http(
  router : Router[S],
  http_method : String,
  path : String,
  body : String,
) -> HttpResponse {
  router.route(HttpRequest::new(http_method, path, body~))
}

///|
/// Add CORS headers to response
pub fn add_cors_headers(response : HttpResponse) -> HttpResponse {
  response.headers["Access-Control-Allow-Origin"] = "*"
  response.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS"
  response.headers["Access-Control-Allow-Headers"] = "Content-Type"
  response
}

///|
/// Handle OPTIONS preflight request
pub fn handle_options() -> HttpResponse {
  add_cors_headers(HttpResponse::new(204, ""))
}
