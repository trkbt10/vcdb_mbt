///|
/// Tests for HTTP router
test "http/parse_path" {
  let segments = parse_path("/collections/test/points")
  assert_eq(segments, ["collections", "test", "points"])
}

///|
test "http/parse_path_empty" {
  let segments = parse_path("/")
  assert_eq(segments, [])
}

///|
test "http/parse_path_root" {
  let segments = parse_path("")
  assert_eq(segments, [])
}

///|
test "http/parse_query" {
  let params = parse_query("key1=value1&key2=value2")
  assert_eq(params.get("key1"), Some("value1"))
  assert_eq(params.get("key2"), Some("value2"))
}

///|
test "http/split_path_query" {
  let (path, query) = split_path_query("/collections?limit=10")
  assert_eq(path, "/collections")
  assert_eq(query, "limit=10")
}

///|
test "http/split_path_query_no_query" {
  let (path, query) = split_path_query("/collections/test")
  assert_eq(path, "/collections/test")
  assert_eq(query, "")
}

///|
test "http/router_health" {
  let router : Router[@storage.MemoryStorage] = Router::new()
  let response = router.route(HttpRequest::new("GET", "/healthz"))
  assert_eq(response.status, 200)
}

///|
test "http/router_collections" {
  let router : Router[@storage.MemoryStorage] = Router::new()
  // Create a collection
  let _ = router.route(
    HttpRequest::new("POST", "/collections/test", body="{\"dim\":3}"),
  )
  // List collections
  let response = router.route(HttpRequest::new("GET", "/collections"))
  assert_eq(response.status, 200)
}

///|
test "http/router_not_found" {
  let router : Router[@storage.MemoryStorage] = Router::new()
  let response = router.route(HttpRequest::new("GET", "/unknown"))
  assert_eq(response.status, 404) // "Not found" from execute_request
}
