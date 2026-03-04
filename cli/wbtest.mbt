///|
/// Tests for CLI argument parsing
test "cli/parse_args_empty" {
  let args = parse_args([])
  assert_eq(args.command, "")
  assert_eq(args.subcommand, "")
}

///|
test "cli/parse_args_command" {
  let args = parse_args(["collections", "list"])
  assert_eq(args.command, "collections")
  assert_eq(args.subcommand, "list")
}

///|
test "cli/parse_args_with_flags" {
  let args = parse_args([
    "collections", "create", "test", "--dim", "128", "--metric", "cosine",
  ])
  assert_eq(args.command, "collections")
  assert_eq(args.subcommand, "create")
  assert_eq(args.positional, ["test"])
  assert_eq(args.get_flag("dim"), Some("128"))
  assert_eq(args.get_flag("metric"), Some("cosine"))
}

///|
test "cli/parse_args_int_flag" {
  let args = parse_args(["serve", "--port", "8080"])
  assert_eq(args.command, "serve")
  assert_eq(args.get_int_flag("port"), Some(8080))
}

///|
test "cli/parse_args_bool_flag" {
  let args = parse_args(["--help"])
  assert_true(args.has_flag("help"))
}

///|
test "cli/parse_vector" {
  let vec = parse_vector("1.0, 2.5, 3.0")
  assert_eq(vec, Some([1.0, 2.5, 3.0]))
}

///|
test "cli/parse_vector_no_spaces" {
  let vec = parse_vector("1.0,2.5,3.0")
  assert_eq(vec, Some([1.0, 2.5, 3.0]))
}

///|
test "cli/parse_payload" {
  let payload = parse_payload("name=test,count=42,active=true")
  match payload {
    @gateway.JObject(obj) => {
      assert_eq(obj.get("name"), Some(@gateway.JString("test")))
      assert_eq(obj.get("count"), Some(@gateway.JNumber(42.0)))
      assert_eq(obj.get("active"), Some(@gateway.JBool(true)))
    }
    _ => assert_true(false)
  }
}
