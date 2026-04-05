///|
fn run_async_blocking(f : async () -> Unit noraise) -> Unit = "%async.run"

///|
fn run_async_test(f : async () -> Unit) -> Unit {
  run_async_blocking(async fn() noraise {
    try f() catch {
      e => abort("async test failed: " + e.to_string())
    }
  })
}

///|
test "http/parse_query" {
  let params = parse_query("key1=value1&key2=value2")
  assert_eq(params.get("key1"), Some("value1"))
  assert_eq(params.get("key2"), Some("value2"))
}

///|
test "http/router_health" {
  run_async_test(async fn() {
    let router = Router::with_storage(@storage.MemoryStorage::new())
    let response = router.route(HttpRequest::new("GET", "/healthz"))
    assert_eq(response.status, 200)
  })
}

///|
test "http/router_collections" {
  run_async_test(async fn() {
    let router = Router::with_storage(@storage.MemoryStorage::new())
    let _ = router.route(
      HttpRequest::new("POST", "/collections/test", body="{\"dim\":3}"),
    )
    let response = router.route(HttpRequest::new("GET", "/collections"))
    assert_eq(response.status, 200)
  })
}

///|
test "http/router_not_found" {
  run_async_test(async fn() {
    let router = Router::with_storage(@storage.MemoryStorage::new())
    let response = router.route(HttpRequest::new("GET", "/unknown"))
    assert_eq(response.status, 404)
  })
}

///|
test "http/router_scroll_points" {
  run_async_test(async fn() {
    let router = Router::with_storage(@storage.MemoryStorage::new())
    let _ = router.route(
      HttpRequest::new("POST", "/collections/test", body="{\"dim\":3}"),
    )
    let _ = router.route(
      HttpRequest::new(
        "PUT",
        "/collections/test/points",
        body="{\"points\":[{\"id\":1,\"vector\":[1,0,0],\"payload\":{\"label\":\"alpha\"}}]}",
      ),
    )
    let response = router.route(
      HttpRequest::new(
        "POST",
        "/collections/test/points/scroll",
        body="{\"limit\":10,\"with_payload\":true}",
      ),
    )
    assert_eq(response.status, 200)
  })
}
