///|
/// Tests for CLI utilities

///|
test "cli/vcdb_command_parses_collections_list" {
  let cmd = vcdb_command()
  let matches = try! cmd.parse(argv=["collections", "list"], env={})
  guard matches.subcommand is Some(("collections", col_matches))
  guard col_matches.subcommand is Some(("list", _))
}

///|
test "cli/vcdb_command_parses_collections_create" {
  let cmd = vcdb_command()
  let matches = try! cmd.parse(
    argv=[
      "collections", "create", "test", "--dim", "128", "--metric", "cosine",
    ],
    env={},
  )
  guard matches.subcommand is Some(("collections", col_matches))
  guard col_matches.subcommand is Some(("create", create_matches))
  assert_eq(get_value(create_matches, "name"), Some("test"))
  assert_eq(get_value(create_matches, "dim"), Some("128"))
  assert_eq(get_value(create_matches, "metric"), Some("cosine"))
}

///|
test "cli/vcdb_command_parses_points_search" {
  let cmd = vcdb_command()
  let matches = try! cmd.parse(
    argv=["points", "search", "mydb", "--vector", "1.0,2.0,3.0", "--k", "5"],
    env={},
  )
  guard matches.subcommand is Some(("points", pts_matches))
  guard pts_matches.subcommand is Some(("search", search_matches))
  assert_eq(get_value(search_matches, "collection"), Some("mydb"))
  assert_eq(get_value(search_matches, "vector"), Some("1.0,2.0,3.0"))
  assert_eq(get_int_value(search_matches, "k"), Some(5))
}

///|
test "cli/vcdb_command_parses_request" {
  let cmd = vcdb_command()
  let matches = try! cmd.parse(
    argv=["request", "--method", "POST", "--path", "/collections/demo"],
    env={},
  )
  guard matches.subcommand is Some(("request", req_matches))
  assert_eq(get_value(req_matches, "method"), Some("POST"))
  assert_eq(get_value(req_matches, "path"), Some("/collections/demo"))
}

///|
test "cli/vcdb_command_default_values" {
  let cmd = vcdb_command()
  let matches = try! cmd.parse(argv=["request"], env={})
  guard matches.subcommand is Some(("request", req_matches))
  assert_eq(get_value_or(req_matches, "method", "GET"), "GET")
  assert_eq(get_value_or(req_matches, "path", "/healthz"), "/healthz")
}

///|
test "cli/get_int_value" {
  let cmd = vcdb_command()
  let matches = try! cmd.parse(
    argv=["collections", "create", "test", "--dim", "256"],
    env={},
  )
  guard matches.subcommand is Some(("collections", col_matches))
  guard col_matches.subcommand is Some(("create", create_matches))
  assert_eq(get_int_value(create_matches, "dim"), Some(256))
  assert_eq(get_int_value_or(create_matches, "dim", 128), 256)
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
    Object(obj) => {
      assert_eq(obj.get("name"), Some("test".to_json()))
      assert_eq(obj.get("count"), Some((42.0).to_json()))
      assert_eq(obj.get("active"), Some(true.to_json()))
    }
    _ => assert_true(false)
  }
}
