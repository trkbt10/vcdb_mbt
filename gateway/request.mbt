///|
/// Split a raw request target into path and query components.
pub fn split_request_target(target : String) -> (String, String) {
  let chars = target.to_array()
  let mut query_start = -1
  for i in 0..<chars.length() {
    if chars[i] == '?' {
      query_start = i
      break
    }
  }
  if query_start < 0 {
    (target, "")
  } else {
    let path = String::from_array(chars[0:query_start])
    let query = String::from_array(chars[query_start + 1:])
    (path, query)
  }
}

///|
/// Parse a request path into gateway route segments.
pub fn parse_request_path(path : String) -> Array[String] {
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
/// Execute a request using a raw path such as `/collections/demo?foo=bar`.
pub fn[S : @storage.Storage] execute_path_request(
  manager : CollectionManager[S],
  http_method : String,
  target : String,
  body : String,
) -> ApiResponse {
  let (path, _query) = split_request_target(target)
  execute_request(manager, http_method, parse_request_path(path), body)
}
