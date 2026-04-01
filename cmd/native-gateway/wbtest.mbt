///|
test "native gateway request healthz" {
  let app = NativeGateway::new()
  let response = app.execute([
    "request", "--method", "GET", "--path", "/healthz",
  ])
  assert_eq(response.status, "ok")
}

///|
test "native gateway collection lifecycle" {
  let app = NativeGateway::new()

  let create = app.execute([
    "collections", "create", "demo", "--dim", "3", "--metric", "cosine",
  ])
  assert_eq(create.status, "ok")

  let list = app.execute(["collections", "list"])
  assert_eq(list.status, "ok")

  let upsert = app.execute([
    "points", "upsert", "demo", "--id", "1", "--vector", "1,0,0", "--payload", "label=test",
  ])
  assert_eq(upsert.status, "ok")

  let search = app.execute([
    "points", "search", "demo", "--vector", "1,0,0", "--k", "1",
  ])
  assert_eq(search.status, "ok")
}
