///|
/// Native gateway executor.
///
/// This package is the MoonBit-native entrypoint for executing vcdb gateway
/// requests without the JavaScript runtime adapter.

///|
fn run_async_main(f : async () -> Unit noraise) -> Unit = "%async.run"

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
  args : Array[String],
) -> @gateway.ApiResponse {
  let parsed = @cli.parse_args(args)
  match (parsed.command, parsed.subcommand) {
    ("healthz", _) => self.request("GET", "/healthz", "")
    ("collections", "list") => self.request("GET", "/collections", "")
    ("collections", "create") => self.create_collection(parsed)
    ("collections", "info") => {
      let name = expect_positional(parsed, 0, "Collection name is required")
      match name {
        Some(it) => self.request("GET", "/collections/" + it, "")
        None => @gateway.ApiResponse::err("Collection name is required")
      }
    }
    ("collections", "delete") => {
      let name = expect_positional(parsed, 0, "Collection name is required")
      match name {
        Some(it) => self.request("DELETE", "/collections/" + it, "")
        None => @gateway.ApiResponse::err("Collection name is required")
      }
    }
    ("points", "upsert") => self.upsert_point(parsed)
    ("points", "get") => self.get_point(parsed)
    ("points", "delete") => self.delete_point(parsed)
    ("points", "search") => self.search_points(parsed)
    ("request", _) => self.execute_raw_request(parsed)
    _ => @gateway.ApiResponse::err("Unknown command")
  }
}

///|
pub async fn NativeGateway::run(
  self : NativeGateway,
  args : Array[String],
) -> String {
  if args.length() == 0 {
    return @cli.print_help()
  }
  if has_arg(args, "--help") {
    return @cli.print_help()
  }
  if has_arg(args, "--version") {
    return @cli.print_version()
  }
  self.execute(args).to_json().to_string()
}

///|
fn main {
  let app = NativeGateway::new()
  run_async_main(async fn() noraise {
    let result = app.run(command_args()) catch { _ => "error" }
    println(result)
  })
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
fn has_arg(args : Array[String], expected : String) -> Bool {
  for arg in args {
    if arg == expected {
      return true
    }
  }
  false
}

///|
fn expect_positional(
  parsed : @cli.ParsedArgs,
  index : Int,
  _message : String,
) -> String? {
  parsed.get_positional(index)
}

///|
fn parse_metric(metric : String) -> @types.Metric? {
  match metric {
    "cosine" | "Cosine" => Some(@types.Cosine)
    "l2" | "L2" => Some(@types.L2)
    "dot" | "Dot" => Some(@types.Dot)
    _ => None
  }
}

///|
fn parse_strategy(strategy : String) -> @types.Strategy? {
  match strategy {
    "hnsw" | "HNSW" => Some(@types.HNSW(@types.HNSWParams::default()))
    "ivf" | "IVF" => Some(@types.IVF(@types.IVFParams::default()))
    "bruteforce" | "Bruteforce" => Some(@types.Bruteforce)
    _ => None
  }
}

///|
fn build_upsert_body(
  id : Int64,
  vector : Array[Double],
  payload : @gateway.JsonValue,
) -> String {
  @gateway.json_object([
    (
      "points",
      @gateway.json_array([
        @gateway.json_object([
          ("id", @gateway.JNumber(id.to_double())),
          ("vector", @gateway.vector_to_json(vector)),
          ("payload", payload),
        ]),
      ]),
    ),
  ]).to_string()
}

///|
fn build_search_body(vector : Array[Double], limit : Int) -> String {
  @gateway.json_object([
    ("vector", @gateway.vector_to_json(vector)),
    ("limit", @gateway.JNumber(limit.to_double())),
    ("with_payload", @gateway.JBool(true)),
  ]).to_string()
}

///|
fn metric_name(metric : @types.Metric) -> String {
  match metric {
    @types.Cosine => "Cosine"
    @types.L2 => "L2"
    @types.Dot => "Dot"
  }
}

///|
fn strategy_name(strategy : @types.Strategy) -> String {
  match strategy {
    @types.Bruteforce => "Bruteforce"
    @types.HNSW(_) => "HNSW"
    @types.IVF(_) => "IVF"
  }
}

///|
fn build_collection_body(
  dim : Int,
  metric : @types.Metric,
  strategy : @types.Strategy,
) -> String {
  @gateway.json_object([
    ("dim", @gateway.JNumber(dim.to_double())),
    ("metric", @gateway.JString(metric_name(metric))),
    ("strategy", @gateway.JString(strategy_name(strategy))),
  ]).to_string()
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
  parsed : @cli.ParsedArgs,
) -> @gateway.ApiResponse {
  let name = match parsed.get_positional(0) {
    Some(it) => it
    None => return @gateway.ApiResponse::err("Collection name is required")
  }
  let dim = parsed.get_int_flag_or("dim", 128)
  let metric = match parsed.get_flag("metric") {
    Some(value) =>
      match parse_metric(value) {
        Some(it) => it
        None => return @gateway.ApiResponse::err("Invalid metric")
      }
    None => @types.Cosine
  }
  let strategy = match parsed.get_flag("strategy") {
    Some(value) =>
      match parse_strategy(value) {
        Some(it) => it
        None => return @gateway.ApiResponse::err("Invalid strategy")
      }
    None => @types.HNSW(@types.HNSWParams::default())
  }
  let body = build_collection_body(dim, metric, strategy)
  self.request("POST", "/collections/" + name, body)
}

///|
async fn NativeGateway::upsert_point(
  self : NativeGateway,
  parsed : @cli.ParsedArgs,
) -> @gateway.ApiResponse {
  let collection = match parsed.get_positional(0) {
    Some(it) => it
    None => return @gateway.ApiResponse::err("Collection name is required")
  }
  let id = match parsed.get_int_flag("id") {
    Some(it) => it.to_int64()
    None => return @gateway.ApiResponse::err("Point ID is required")
  }
  let vector = match parsed.get_flag("vector") {
    Some(value) =>
      match @cli.parse_vector(value) {
        Some(it) => it
        None => return @gateway.ApiResponse::err("Invalid vector")
      }
    None => return @gateway.ApiResponse::err("Vector is required")
  }
  let payload = match parsed.get_flag("payload") {
    Some(value) => @cli.parse_payload(value)
    None => @gateway.json_object([])
  }
  let body = build_upsert_body(id, vector, payload)
  self.request("PUT", "/collections/" + collection + "/points", body)
}

///|
async fn NativeGateway::get_point(
  self : NativeGateway,
  parsed : @cli.ParsedArgs,
) -> @gateway.ApiResponse {
  let collection = match parsed.get_positional(0) {
    Some(it) => it
    None => return @gateway.ApiResponse::err("Collection name is required")
  }
  let id = match parsed.get_positional(1) {
    Some(it) => it
    None => return @gateway.ApiResponse::err("Point ID is required")
  }
  self.request("GET", "/collections/" + collection + "/points/" + id, "")
}

///|
async fn NativeGateway::delete_point(
  self : NativeGateway,
  parsed : @cli.ParsedArgs,
) -> @gateway.ApiResponse {
  let collection = match parsed.get_positional(0) {
    Some(it) => it
    None => return @gateway.ApiResponse::err("Collection name is required")
  }
  let id = match parsed.get_positional(1) {
    Some(it) => it
    None => return @gateway.ApiResponse::err("Point ID is required")
  }
  self.request("DELETE", "/collections/" + collection + "/points/" + id, "")
}

///|
async fn NativeGateway::search_points(
  self : NativeGateway,
  parsed : @cli.ParsedArgs,
) -> @gateway.ApiResponse {
  let collection = match parsed.get_positional(0) {
    Some(it) => it
    None => return @gateway.ApiResponse::err("Collection name is required")
  }
  let vector = match parsed.get_flag("vector") {
    Some(value) =>
      match @cli.parse_vector(value) {
        Some(it) => it
        None => return @gateway.ApiResponse::err("Invalid vector")
      }
    None => return @gateway.ApiResponse::err("Vector is required")
  }
  let limit = parsed.get_int_flag_or("k", 10)
  let body = build_search_body(vector, limit)
  self.request("POST", "/collections/" + collection + "/points/search", body)
}

///|
async fn NativeGateway::execute_raw_request(
  self : NativeGateway,
  parsed : @cli.ParsedArgs,
) -> @gateway.ApiResponse {
  let http_method = parsed.get_flag_or("method", "GET")
  let path = parsed.get_flag_or("path", "/healthz")
  let body = parsed.get_flag_or("body", "")
  self.request(http_method, path, body)
}
