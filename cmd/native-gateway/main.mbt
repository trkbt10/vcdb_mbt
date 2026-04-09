///|
/// Native gateway executor.
///
/// This package is the MoonBit-native entrypoint for executing vcdb gateway
/// requests without the JavaScript runtime adapter.

// Uses `async fn main` — moonbitlang/async event loop is started automatically.

///|
pub struct NativeGateway {
  manager : @gateway.CollectionManager[@storage.MemoryStorage]
}

///|
pub fn NativeGateway::new() -> NativeGateway {
  let storage = @storage.MemoryStorage::new()
  { manager: @gateway.CollectionManager::with_storage(storage) }
}

///|
pub async fn NativeGateway::execute(
  self : NativeGateway,
  matches : @argparse.Matches,
) -> @gateway.ApiResponse {
  match matches.subcommand {
    Some(("healthz", _)) => self.request("GET", "/healthz", "")
    Some(("collections", sub_matches)) => self.execute_collections(sub_matches)
    Some(("points", sub_matches)) => self.execute_points(sub_matches)
    Some(("request", sub_matches)) => self.execute_raw_request(sub_matches)
    _ => @gateway.ApiResponse::err("Unknown command")
  }
}

///|
/// Check if the command is a direct CLI command (dump/load) that
/// bypasses the gateway and writes its own output.
pub async fn NativeGateway::try_execute_direct(
  _self : NativeGateway,
  matches : @argparse.Matches,
) -> Bool {
  match matches.subcommand {
    Some(("dump", sub)) => {
      execute_dump(sub)
      true
    }
    Some(("load", sub)) => {
      execute_load(sub)
      true
    }
    _ => false
  }
}

///|
async fn NativeGateway::execute_collections(
  self : NativeGateway,
  matches : @argparse.Matches,
) -> @gateway.ApiResponse {
  match matches.subcommand {
    Some(("list", _)) => self.request("GET", "/collections", "")
    Some(("create", sub)) => self.create_collection(sub)
    Some(("info", sub)) => {
      let name = match @cli.get_value(sub, "name") {
        Some(it) => it
        None => return @gateway.ApiResponse::err("Collection name is required")
      }
      self.request("GET", "/collections/" + name, "")
    }
    Some(("delete", sub)) => {
      let name = match @cli.get_value(sub, "name") {
        Some(it) => it
        None => return @gateway.ApiResponse::err("Collection name is required")
      }
      self.request("DELETE", "/collections/" + name, "")
    }
    _ => @gateway.ApiResponse::err("Unknown collections subcommand")
  }
}

///|
async fn NativeGateway::execute_points(
  self : NativeGateway,
  matches : @argparse.Matches,
) -> @gateway.ApiResponse {
  match matches.subcommand {
    Some(("upsert", sub)) => self.upsert_point(sub)
    Some(("get", sub)) => self.get_point(sub)
    Some(("delete", sub)) => self.delete_point(sub)
    Some(("search", sub)) => self.search_points(sub)
    _ => @gateway.ApiResponse::err("Unknown points subcommand")
  }
}

///|
pub async fn NativeGateway::run(
  self : NativeGateway,
  args : Array[String],
) -> String {
  let cmd = @cli.vcdb_command()
  let matches = cmd.parse(argv=args, env={}) catch { e => return e.to_string() }
  // Direct commands (dump/load) handle their own output
  if self.try_execute_direct(matches) {
    return ""
  }
  self.execute(matches).to_json().stringify()
}

///|
async fn main {
  let app = NativeGateway::new()
  let result = app.run(command_args()) catch { e => e.to_string() }
  if result.length() > 0 {
    println(result)
  }
}

///|
fn command_args() -> Array[String] {
  let argv = @env.args()
  if argv.length() <= 1 {
    []
  } else {
    let args : Array[String] = []
    for i in 1..<argv.length() {
      args.push(argv[i])
    }
    args
  }
}

///|
fn build_upsert_body(
  id : Int64,
  vector : Array[Double],
  payload : Json,
) -> String {
  @gateway.json_object([
    (
      "points",
      @gateway.json_array([
        @gateway.json_object([
          ("id", id.to_double().to_json()),
          ("vector", @gateway.vector_to_json(vector)),
          ("payload", payload),
        ]),
      ]),
    ),
  ]).stringify()
}

///|
fn build_search_body(vector : Array[Double], limit : Int) -> String {
  @gateway.json_object([
    ("vector", @gateway.vector_to_json(vector)),
    ("limit", limit.to_double().to_json()),
    ("with_payload", true.to_json()),
  ]).stringify()
}

///|
fn build_collection_body(
  dim : Int,
  metric : @types.Metric,
  strategy : @types.Strategy,
) -> String {
  @gateway.json_object([
    ("dim", dim.to_double().to_json()),
    ("metric", metric.to_name().to_json()),
    ("strategy", strategy.to_name().to_json()),
  ]).stringify()
}

///|
async fn NativeGateway::request(
  self : NativeGateway,
  http_method : String,
  path : String,
  body : String,
) -> @gateway.ApiResponse {
  @gateway.execute_path_request(self.manager, http_method, path, body)
}

///|
async fn NativeGateway::create_collection(
  self : NativeGateway,
  matches : @argparse.Matches,
) -> @gateway.ApiResponse {
  let name = match @cli.get_value(matches, "name") {
    Some(it) => it
    None => return @gateway.ApiResponse::err("Collection name is required")
  }
  let dim = @cli.get_int_value_or(matches, "dim", 128)
  let metric = match @cli.get_value(matches, "metric") {
    Some(value) =>
      match @cli.parse_metric(value) {
        Some(it) => it
        None => return @gateway.ApiResponse::err("Invalid metric")
      }
    None => @types.Cosine
  }
  let strategy = match @cli.get_value(matches, "strategy") {
    Some(value) =>
      match @cli.parse_strategy(value) {
        Some(it) => it
        None => return @gateway.ApiResponse::err("Invalid strategy")
      }
    None => @types.Strategy::default_hnsw()
  }
  let body = build_collection_body(dim, metric, strategy)
  self.request("POST", "/collections/" + name, body)
}

///|
async fn NativeGateway::upsert_point(
  self : NativeGateway,
  matches : @argparse.Matches,
) -> @gateway.ApiResponse {
  let collection = match @cli.get_value(matches, "collection") {
    Some(it) => it
    None => return @gateway.ApiResponse::err("Collection name is required")
  }
  let id = match @cli.get_int_value(matches, "id") {
    Some(it) => it.to_int64()
    None => return @gateway.ApiResponse::err("Point ID is required")
  }
  let vector = match @cli.get_value(matches, "vector") {
    Some(value) =>
      match @cli.parse_vector(value) {
        Some(it) => it
        None => return @gateway.ApiResponse::err("Invalid vector")
      }
    None => return @gateway.ApiResponse::err("Vector is required")
  }
  let payload = match @cli.get_value(matches, "payload") {
    Some(value) => @cli.parse_payload(value)
    None => @gateway.json_object([])
  }
  let body = build_upsert_body(id, vector, payload)
  self.request("PUT", "/collections/" + collection + "/points", body)
}

///|
async fn NativeGateway::get_point(
  self : NativeGateway,
  matches : @argparse.Matches,
) -> @gateway.ApiResponse {
  let collection = match @cli.get_value(matches, "collection") {
    Some(it) => it
    None => return @gateway.ApiResponse::err("Collection name is required")
  }
  let id = match @cli.get_value(matches, "id") {
    Some(it) => it
    None => return @gateway.ApiResponse::err("Point ID is required")
  }
  self.request("GET", "/collections/" + collection + "/points/" + id, "")
}

///|
async fn NativeGateway::delete_point(
  self : NativeGateway,
  matches : @argparse.Matches,
) -> @gateway.ApiResponse {
  let collection = match @cli.get_value(matches, "collection") {
    Some(it) => it
    None => return @gateway.ApiResponse::err("Collection name is required")
  }
  let id = match @cli.get_value(matches, "id") {
    Some(it) => it
    None => return @gateway.ApiResponse::err("Point ID is required")
  }
  self.request("DELETE", "/collections/" + collection + "/points/" + id, "")
}

///|
async fn NativeGateway::search_points(
  self : NativeGateway,
  matches : @argparse.Matches,
) -> @gateway.ApiResponse {
  let collection = match @cli.get_value(matches, "collection") {
    Some(it) => it
    None => return @gateway.ApiResponse::err("Collection name is required")
  }
  let vector = match @cli.get_value(matches, "vector") {
    Some(value) =>
      match @cli.parse_vector(value) {
        Some(it) => it
        None => return @gateway.ApiResponse::err("Invalid vector")
      }
    None => return @gateway.ApiResponse::err("Vector is required")
  }
  let limit = @cli.get_int_value_or(matches, "k", 10)
  let body = build_search_body(vector, limit)
  self.request("POST", "/collections/" + collection + "/points/search", body)
}

///|
async fn NativeGateway::execute_raw_request(
  self : NativeGateway,
  matches : @argparse.Matches,
) -> @gateway.ApiResponse {
  let http_method = @cli.get_value_or(matches, "method", "GET")
  let path = @cli.get_value_or(matches, "path", "/healthz")
  let body = @cli.get_value_or(matches, "body", "")
  self.request(http_method, path, body)
}
