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
} derive(Show)

///|
/// HTTP response representation
pub struct HttpResponse {
  status : Int
  headers : Map[String, String]
  body : String
} derive(Show)

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
/// Parse URL path into segments
pub fn parse_path(path : String) -> Array[String] {
  let segments : Array[String] = []
  let current : Array[Char] = []
  for c in path {
    if c == '/' {
      if current.length() > 0 {
        segments.push(String::from_array(current))
        current.clear()
      }
    } else {
      current.push(c)
    }
  }
  if current.length() > 0 {
    segments.push(String::from_array(current))
  }
  segments
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
/// Extract path and query from full path
pub fn split_path_query(full_path : String) -> (String, String) {
  let chars = full_path.to_array()
  let mut query_start = -1
  for i in 0..<chars.length() {
    if chars[i] == '?' {
      query_start = i
      break
    }
  }
  if query_start < 0 {
    (full_path, "")
  } else {
    let path = String::from_array(chars[0:query_start])
    let query = String::from_array(chars[query_start + 1:])
    (path, query)
  }
}

///|
/// HTTP router that wraps gateway handlers
pub struct Router {
  manager : @gateway.CollectionManager
}

///|
/// Create a new router
pub fn Router::new(storage_path? : String = "./storage") -> Router {
  { manager: @gateway.CollectionManager::new(storage_path~) }
}

///|
/// Get the collection manager
pub fn Router::get_manager(self : Router) -> @gateway.CollectionManager {
  self.manager
}

///|
/// Route an HTTP request to the appropriate handler
pub fn Router::route(self : Router, request : HttpRequest) -> HttpResponse {
  let (path, _query) = split_path_query(request.path)
  let segments = parse_path(path)

  // Execute the request through gateway
  let response = @gateway.execute_request(
    self.manager,
    request.http_method,
    segments,
    request.body,
  )

  // Convert gateway response to HTTP response
  let json_body = response.to_json().to_string()
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
/// Convenience method to handle a raw HTTP request
pub fn handle_http(
  router : Router,
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
