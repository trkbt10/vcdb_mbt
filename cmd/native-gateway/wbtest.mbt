///|
fn run_async_blocking(f : async () -> Unit noraise) -> Unit = "%async.run"

///|
fn run_async_test(f : async () -> Unit) -> Unit {
  run_async_blocking(async fn() noraise {
    f() catch {
      e => abort("async test failed: " + e.to_string())
    }
  })
}

///|
/// Helper: parse argv and execute
async fn execute_argv(
  app : NativeGateway,
  args : Array[String],
) -> @gateway.ApiResponse {
  let cmd = @cli.vcdb_command()
  let matches = cmd.parse(argv=args, env={}) catch {
    e => return @gateway.ApiResponse::err(e.to_string())
  }
  app.execute(matches)
}

///|
test "native gateway request healthz" {
  run_async_test(async fn() {
    let app = NativeGateway::new()
    let response = execute_argv(app, [
      "request", "--method", "GET", "--path", "/healthz",
    ])
    assert_eq(response.status, "ok")
  })
}

///|
test "native gateway collection lifecycle" {
  run_async_test(async fn() {
    let app = NativeGateway::new()

    let create = execute_argv(app, [
      "collections", "create", "demo", "--dim", "3", "--metric", "cosine",
    ])
    assert_eq(create.status, "ok")

    let list = execute_argv(app, ["collections", "list"])
    assert_eq(list.status, "ok")

    let upsert = execute_argv(app, [
      "points", "upsert", "demo", "--id", "1", "--vector", "1,0,0", "--payload",
      "label=test",
    ])
    assert_eq(upsert.status, "ok")

    let search = execute_argv(app, [
      "points", "search", "demo", "--vector", "1,0,0", "--k", "1",
    ])
    assert_eq(search.status, "ok")
  })
}
