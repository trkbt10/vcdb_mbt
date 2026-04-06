///|
/// Native HTTP server for vcdb using moonbitlang/async/http.

///|
struct ServerOptions {
  mut host : String
  mut port : Int
  mut storage_path : String
  mut in_memory : Bool
  mut help : Bool
  mut error : String?
}

///|
fn ServerOptions::default() -> ServerOptions {
  {
    host: "127.0.0.1",
    port: 6333,
    storage_path: ".local-storage",
    in_memory: false,
    help: false,
    error: None,
  }
}

///|
fn parse_args(args : Array[String]) -> ServerOptions {
  let opts = ServerOptions::default()
  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    if arg == "--help" || arg == "-h" {
      opts.help = true
      return opts
    } else if arg == "--storage" && i + 1 < args.length() {
      opts.storage_path = args[i + 1]
      i = i + 1
    } else if arg == "--in-memory" {
      opts.in_memory = true
    } else if arg == "--host" && i + 1 < args.length() {
      opts.host = args[i + 1]
      i = i + 1
    } else if arg == "--port" && i + 1 < args.length() {
      let port_arg = args[i + 1]
      let parsed = @strconv.parse_int(port_arg) catch {
        _ => {
          opts.error = Some("Invalid port: " + port_arg)
          return opts
        }
      }
      opts.port = parsed
      i = i + 1
    }
    i = i + 1
  }
  opts
}

///|
fn print_help() -> Unit {
  println(
    "vcdb native HTTP server\n\nUsage: moon run cmd/native-serve -- [options]\n\nOptions:\n  --host <addr>      Host to bind (default: 127.0.0.1)\n  --port <n>         Port to bind (default: 6333)\n  --storage <path>   Storage root (default: .local-storage)\n  --in-memory        Disable filesystem persistence\n  -h, --help         Show this help message",
  )
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
fn method_name(request_method : @async_http.RequestMethod) -> String {
  match request_method {
    @async_http.RequestMethod::Get => "GET"
    @async_http.RequestMethod::Post => "POST"
    @async_http.RequestMethod::Put => "PUT"
    @async_http.RequestMethod::Delete => "DELETE"
    @async_http.RequestMethod::Options => "OPTIONS"
    _ => "GET"
  }
}

///|
async fn send_http_response(
  conn : @async_http.ServerConnection,
  response : @http.HttpResponse,
) -> Unit {
  conn.send_response(response.status, "OK", extra_headers=response.headers)
  conn.write(response.body)
  conn.end_response()
}

///|
async fn handle_preflight(conn : @async_http.ServerConnection) -> Unit {
  let response = @http.add_cors_headers(@http.HttpResponse::new(204, ""))
  conn.send_response(204, "No Content", extra_headers=response.headers)
  conn.end_response()
}

///|
async fn run_server(options : ServerOptions) -> Unit {
  if options.in_memory {
    run_server_with_router(
      options,
      @http.Router::with_storage(@storage.MemoryStorage::new()),
    )
  } else {
    run_server_with_router(
      options,
      @http.Router::with_storage(
        @storage.NativeFileStorage::new(options.storage_path),
      ),
    )
  }
}

///|
async fn[S : @storage.AsyncStorage] run_server_with_router(
  options : ServerOptions,
  router : @http.Router[S],
) -> Unit {
  let addr_str = options.host + ":" + options.port.to_string()
  let addr = @async_socket.Addr::parse(addr_str) catch {
    _ => {
      println("Failed to parse address: \{addr_str}")
      return
    }
  }
  let server = @async_http.Server::new(addr, reuse_addr=true) catch {
    e => {
      println("Failed to start server: \{e}")
      return
    }
  }
  println(
    "vcdb native gateway listening on http://\{options.host}:\{options.port}",
  )
  if options.in_memory {
    println("storage: in-memory")
  } else {
    println("storage: \{options.storage_path}")
  }
  server.run_forever((req, body_reader, conn) => {
    let http_method = method_name(req.meth)
    if http_method == "OPTIONS" {
      handle_preflight(conn)
      return
    }
    let body_data = @async_io.Reader::read_all(body_reader) catch {
      _ => {
        conn.send_response(400, "Bad Request")
        conn.write("{\"error\":\"failed to read body\"}")
        conn.end_response()
        return
      }
    }
    let body_text = body_data.text() catch {
      _ => {
        conn.send_response(400, "Bad Request")
        conn.write("{\"error\":\"request body is not valid UTF-8\"}")
        conn.end_response()
        return
      }
    }
    let response = @http.add_cors_headers(
      router.route(
        @http.HttpRequest::new(http_method, req.path, body=body_text),
      ),
    )
    send_http_response(conn, response)
  })
}

///|
async fn main {
  let options = parse_args(command_args())
  match options.error {
    Some(err) => {
      println(err)
      return
    }
    None => ()
  }
  if options.help {
    print_help()
    return
  }
  run_server(options)
}
