///|
test "native_serve/parse_args_rejects_invalid_port" {
  let opts = parse_args(["--port", "bad"])
  assert_eq(opts.error, Some("Invalid port: bad"))
}

///|
test "native_serve/parse_args_accepts_valid_port" {
  let opts = parse_args(["--port", "7000", "--host", "0.0.0.0"])
  assert_eq(opts.error, None)
  assert_eq(opts.port, 7000)
  assert_eq(opts.host, "0.0.0.0")
}
