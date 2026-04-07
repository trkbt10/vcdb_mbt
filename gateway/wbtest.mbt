///|
/// Tests for JSON module
test "json/parse_null" {
  let result = parse_json("null")
  assert_eq(result, Some(JNull))
}

///|
test "json/parse_bool" {
  assert_eq(parse_json("true"), Some(JBool(true)))
  assert_eq(parse_json("false"), Some(JBool(false)))
}

///|
test "json/parse_number" {
  assert_eq(parse_json("42"), Some(JNumber(42.0)))
  assert_eq(parse_json("-123"), Some(JNumber(-123.0)))
  assert_eq(parse_json("3.14"), Some(JNumber(3.14)))
  assert_eq(parse_json("1e10"), Some(JNumber(10000000000.0)))
}

///|
test "json/parse_string" {
  assert_eq(parse_json("\"hello\""), Some(JString("hello")))
  assert_eq(parse_json("\"hello\\nworld\""), Some(JString("hello\nworld")))
  assert_eq(parse_json("\"tab\\there\""), Some(JString("tab\there")))
}

///|
test "json/parse_array" {
  let result = parse_json("[1, 2, 3]")
  assert_eq(result, Some(JArray([JNumber(1.0), JNumber(2.0), JNumber(3.0)])))

  let empty = parse_json("[]")
  assert_eq(empty, Some(JArray([])))
}

///|
test "json/parse_object" {
  let result = parse_json("{\"name\": \"test\", \"value\": 42}")
  match result {
    Some(JObject(obj)) => {
      assert_eq(get_string(JObject(obj), "name"), Some("test"))
      assert_eq(get_number(JObject(obj), "value"), Some(42.0))
    }
    _ => assert_true(false)
  }
}

///|
test "json/parse_nested" {
  let result = parse_json("{\"items\": [1, 2, 3], \"meta\": {\"count\": 3}}")
  match result {
    Some(JObject(obj)) => {
      let items = get_array(JObject(obj), "items")
      assert_true(items is Some(_))
      match get_object(JObject(obj), "meta") {
        Some(meta) => {
          let count = meta.get("count")
          match count {
            Some(JNumber(n)) => assert_eq(n, 3.0)
            _ => assert_true(false)
          }
        }
        None => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
test "json/to_string" {
  let obj = json_object([
    ("name", JString("test")),
    ("value", JNumber(42.0)),
    ("active", JBool(true)),
  ])
  let s = obj.to_string()
  // Parse it back to verify
  let parsed = parse_json(s)
  assert_true(parsed is Some(_))
}

///|
test "json/vector_conversion" {
  let vec = [1.0, 2.0, 3.0]
  let json = vector_to_json(vec)
  let back = json_to_vector(json)
  assert_eq(back, Some(vec))
}

///|
test "json/attrs_conversion" {
  let attrs = @types.empty_attrs()
  attrs.set("name", @types.String("test"))
  attrs.set("count", @types.Int(42L))
  attrs.set("ratio", @types.Float(0.5))
  attrs.set("active", @types.Bool(true))

  let json = attrs_to_json(attrs)
  let back = json_to_attrs(json)

  match back {
    Some(a) => {
      assert_eq(a.get("name"), Some(@types.String("test")))
      assert_eq(a.get("count"), Some(@types.Int(42L)))
      assert_eq(a.get("active"), Some(@types.Bool(true)))
    }
    None => assert_true(false)
  }
}

///|
test "json/get_helpers" {
  let obj = json_object([
    ("name", JString("test")),
    ("count", JNumber(42.0)),
    ("active", JBool(true)),
    ("items", json_array([JNumber(1.0), JNumber(2.0)])),
  ])

  assert_eq(get_string(obj, "name"), Some("test"))
  assert_eq(get_number(obj, "count"), Some(42.0))
  assert_eq(get_int(obj, "count"), Some(42))
  assert_eq(get_bool(obj, "active"), Some(true))
  assert_true(get_array(obj, "items") is Some(_))
  assert_eq(get_string(obj, "missing"), None)
}

///|
test "json/escape_roundtrip" {
  let special = "hello\nworld\ttab\"quote\\backslash"
  let json = JString(special)
  let s = json.to_string()
  let parsed = parse_json(s)
  assert_eq(parsed, Some(JString(special)))
}

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
fn string_to_bytes(value : String) -> Bytes {
  Bytes::from_array(value.to_array().map(fn(c) { c.to_int().to_byte() }))
}

///|
test "request/parse_request_path" {
  let segments = parse_request_path("/collections/test/points")
  assert_eq(segments, ["collections", "test", "points"])
}

///|
test "request/parse_request_path_empty" {
  assert_eq(parse_request_path("/"), [])
  assert_eq(parse_request_path(""), [])
}

///|
test "request/split_request_target" {
  let (path, query) = split_request_target("/collections/test?limit=10")
  assert_eq(path, "/collections/test")
  assert_eq(query, "limit=10")
}

///|
test "wal/upsert_creates_wal" {
  run_async_test(async fn() {
    let storage = @storage.MemoryStorage::new()
    let manager : CollectionManager[@storage.MemoryStorage] = CollectionManager::with_storage(
      storage,
    )
    let create = execute_path_request(
      manager, "POST", "/collections/test", "{\"dim\":3,\"strategy\":\"Bruteforce\"}",
    )
    assert_eq(create.status, "ok")
    let upsert = execute_path_request(
      manager, "PUT", "/collections/test/points", "{\"points\":[{\"id\":1,\"vector\":[1,0,0],\"payload\":{}}]}",
    )
    assert_eq(upsert.status, "ok")
    // WAL file should exist
    let wal_path = @storage.collection_wal_path("test")
    assert_true(storage.exists(wal_path))
  })
}

///|
test "wal/delete_persists_via_wal" {
  run_async_test(async fn() {
    let storage = @storage.MemoryStorage::new()
    let manager1 : CollectionManager[@storage.MemoryStorage] = CollectionManager::with_storage(
      storage,
    )
    let _ = execute_path_request(
      manager1, "POST", "/collections/test", "{\"dim\":2,\"strategy\":\"Bruteforce\"}",
    )
    let _ = execute_path_request(
      manager1, "PUT", "/collections/test/points", "{\"points\":[{\"id\":1,\"vector\":[1,0],\"payload\":{}},{\"id\":2,\"vector\":[0,1],\"payload\":{}}]}",
    )
    manager1.checkpoint("test")
    let del = execute_path_request(
      manager1, "DELETE", "/collections/test/points/1", "",
    )
    assert_eq(del.status, "ok")
    // Reload — deletion should be replayed from WAL
    let manager2 : CollectionManager[@storage.MemoryStorage] = CollectionManager::with_storage(
      storage,
    )
    match manager2.get("test") {
      Ok(d) => {
        assert_eq(d.size(), 1)
        assert_true(d.has(@types.VectorId::from_int(2)))
        assert_true(!d.has(@types.VectorId::from_int(1)))
      }
      Err(_) => assert_true(false)
    }
  })
}

///|
test "wal/checkpoint_snapshot_is_current" {
  run_async_test(async fn() {
    let storage = @storage.MemoryStorage::new()
    let manager1 : CollectionManager[@storage.MemoryStorage] = CollectionManager::with_storage(
      storage,
    )
    let _ = execute_path_request(
      manager1, "POST", "/collections/test", "{\"dim\":2,\"strategy\":\"Bruteforce\"}",
    )
    let _ = execute_path_request(
      manager1, "PUT", "/collections/test/points", "{\"points\":[{\"id\":1,\"vector\":[1,0],\"payload\":{}}]}",
    )
    manager1.checkpoint("test")
    // After checkpoint, reload should see the data without WAL
    let manager2 : CollectionManager[@storage.MemoryStorage] = CollectionManager::with_storage(
      storage,
    )
    match manager2.get("test") {
      Ok(d) => {
        assert_eq(d.size(), 1)
        assert_true(d.has(@types.VectorId::from_int(1)))
      }
      Err(_) => assert_true(false)
    }
  })
}

///|
test "wal/reload_replays_wal" {
  run_async_test(async fn() {
    let storage = @storage.MemoryStorage::new()
    // Phase 1: create collection, add data, checkpoint, then add more via WAL
    let manager1 : CollectionManager[@storage.MemoryStorage] = CollectionManager::with_storage(
      storage,
    )
    let _ = execute_path_request(
      manager1, "POST", "/collections/test", "{\"dim\":2,\"strategy\":\"Bruteforce\"}",
    )
    // Add initial points and checkpoint (snapshot includes these)
    let _ = execute_path_request(
      manager1, "PUT", "/collections/test/points", "{\"points\":[{\"id\":1,\"vector\":[1,0],\"payload\":{\"tag\":\"a\"}}]}",
    )
    manager1.checkpoint("test")
    // Add more points (only in WAL, not in snapshot)
    let _ = execute_path_request(
      manager1, "PUT", "/collections/test/points", "{\"points\":[{\"id\":2,\"vector\":[0,1],\"payload\":{\"tag\":\"b\"}}]}",
    )

    // Phase 2: create new manager from same storage - should replay WAL
    let manager2 : CollectionManager[@storage.MemoryStorage] = CollectionManager::with_storage(
      storage,
    )
    let db = manager2.get("test")
    match db {
      Ok(d) => {
        // Both points should exist: id=1 from snapshot, id=2 from WAL replay
        assert_eq(d.size(), 2)
        assert_true(d.has(@types.VectorId::from_int(1)))
        assert_true(d.has(@types.VectorId::from_int(2)))
      }
      Err(_) => assert_true(false)
    }
  })
}

///|
test "wal/auto_checkpoint_on_threshold" {
  run_async_test(async fn() {
    let storage = @storage.MemoryStorage::new()
    // Set very low threshold for testing
    let manager1 : CollectionManager[@storage.MemoryStorage] = CollectionManager::with_storage(
      storage,
      checkpoint_threshold=3,
    )
    let _ = execute_path_request(
      manager1, "POST", "/collections/test", "{\"dim\":1,\"strategy\":\"Bruteforce\"}",
    )
    // Add 3 points in one batch → reaches threshold → auto-checkpoint
    let _ = execute_path_request(
      manager1, "PUT", "/collections/test/points", "{\"points\":[{\"id\":1,\"vector\":[1],\"payload\":{}},{\"id\":2,\"vector\":[2],\"payload\":{}},{\"id\":3,\"vector\":[3],\"payload\":{}}]}",
    )
    // Data should be accessible
    match manager1.get("test") {
      Ok(d) => assert_eq(d.size(), 3)
      Err(_) => assert_true(false)
    }
    // Auto-checkpoint means data survives reload without explicit checkpoint
    let manager2 : CollectionManager[@storage.MemoryStorage] = CollectionManager::with_storage(
      storage,
      checkpoint_threshold=3,
    )
    match manager2.get("test") {
      Ok(d) => assert_eq(d.size(), 3)
      Err(_) => assert_true(false)
    }
  })
}

///|
test "wal/delete_collection_removes_wal" {
  run_async_test(async fn() {
    let storage = @storage.MemoryStorage::new()
    let manager : CollectionManager[@storage.MemoryStorage] = CollectionManager::with_storage(
      storage,
    )
    let _ = execute_path_request(
      manager, "POST", "/collections/test", "{\"dim\":2,\"strategy\":\"Bruteforce\"}",
    )
    let _ = execute_path_request(
      manager, "PUT", "/collections/test/points", "{\"points\":[{\"id\":1,\"vector\":[1,0],\"payload\":{}}]}",
    )
    // Delete collection
    let del = execute_path_request(manager, "DELETE", "/collections/test", "")
    assert_eq(del.status, "ok")
    // WAL file should be gone
    let wal_path = @storage.collection_wal_path("test")
    assert_eq(storage.exists(wal_path), false)
  })
}

///|
test "request/execute_path_request" {
  run_async_test(async fn() {
    let manager : CollectionManager[@storage.MemoryStorage] = CollectionManager::with_storage(
      @storage.MemoryStorage::new(),
    )
    let create = execute_path_request(
      manager, "POST", "/collections/demo", "{\"dim\":3}",
    )
    assert_eq(create.status, "ok")

    let list = execute_path_request(manager, "GET", "/collections?limit=10", "")
    assert_eq(list.status, "ok")
  })
}

///|
test "request/create_collection_rejects_invalid_config" {
  run_async_test(async fn() {
    let manager : CollectionManager[@storage.MemoryStorage] = CollectionManager::with_storage(
      @storage.MemoryStorage::new(),
    )
    let create = execute_path_request(
      manager, "POST", "/collections/demo", "{\"dim\":3,\"strategy\":\"bogus\"}",
    )
    assert_eq(create.status, "error")
    assert_eq(
      create.error,
      Some("Invalid request body: unsupported strategy: bogus"),
    )
  })
}

///|
test "request/upsert_rejects_invalid_payload" {
  run_async_test(async fn() {
    let manager : CollectionManager[@storage.MemoryStorage] = CollectionManager::with_storage(
      @storage.MemoryStorage::new(),
    )
    let create = execute_path_request(
      manager, "POST", "/collections/demo", "{\"dim\":3}",
    )
    assert_eq(create.status, "ok")

    let upsert = execute_path_request(
      manager, "PUT", "/collections/demo/points", "{\"points\":[{\"id\":1,\"vector\":[1,0,0],\"payload\":{\"nested\":{\"x\":1}}}]}",
    )
    assert_eq(upsert.status, "error")
    assert_eq(upsert.error, Some("Invalid request body"))
  })
}

///|
test "request/reload_preserves_metric_and_strategy" {
  run_async_test(async fn() {
    let storage = @storage.MemoryStorage::new()
    let manager1 : CollectionManager[@storage.MemoryStorage] = CollectionManager::with_storage(
      storage,
    )
    let create = execute_path_request(
      manager1, "POST", "/collections/test", "{\"dim\":2,\"metric\":\"L2\",\"strategy\":\"Bruteforce\"}",
    )
    assert_eq(create.status, "ok")
    let upsert = execute_path_request(
      manager1, "PUT", "/collections/test/points", "{\"points\":[{\"id\":1,\"vector\":[1,0],\"payload\":{}}]}",
    )
    assert_eq(upsert.status, "ok")

    let manager2 : CollectionManager[@storage.MemoryStorage] = CollectionManager::with_storage(
      storage,
    )
    match manager2.get("test") {
      Ok(db) => {
        assert_eq(db.metric(), @types.L2)
        assert_true(db.strategy() is @types.Bruteforce)
      }
      Err(_) => assert_true(false)
    }
  })
}

///|
test "request/invalid_persisted_config_surfaces_error" {
  run_async_test(async fn() {
    let storage = @storage.MemoryStorage::new()
    storage.write(
      @storage.collection_config_path("broken"),
      string_to_bytes("{\"metric\":\"Cosine\"}"),
    )
    let manager : CollectionManager[@storage.MemoryStorage] = CollectionManager::with_storage(
      storage,
    )

    let get_resp = execute_path_request(
      manager, "GET", "/collections/broken", "",
    )
    assert_eq(get_resp.status, "error")
    assert_eq(
      get_resp.error,
      Some(
        "Storage error: Invalid collection config for broken: dim is required",
      ),
    )

    let list_resp = execute_path_request(manager, "GET", "/collections", "")
    assert_eq(list_resp.status, "error")
    assert_eq(
      list_resp.error,
      Some(
        "Storage error: Invalid collection config for broken: dim is required",
      ),
    )
  })
}

///|
test "request/scroll_points" {
  run_async_test(async fn() {
    let manager : CollectionManager[@storage.MemoryStorage] = CollectionManager::with_storage(
      @storage.MemoryStorage::new(),
    )
    let create = execute_path_request(
      manager, "POST", "/collections/demo", "{\"dim\":3,\"strategy\":\"Bruteforce\"}",
    )
    assert_eq(create.status, "ok")

    let upsert = execute_path_request(
      manager, "PUT", "/collections/demo/points", "{\"points\":[{\"id\":1,\"vector\":[1,0,0],\"payload\":{\"label\":\"alpha\"}},{\"id\":2,\"vector\":[0,1,0],\"payload\":{\"label\":\"beta\"}}]}",
    )
    assert_eq(upsert.status, "ok")

    let scroll = execute_path_request(
      manager, "POST", "/collections/demo/points/scroll", "{\"limit\":1,\"with_payload\":true}",
    )
    assert_eq(scroll.status, "ok")
    match scroll.result {
      Some(JObject(result)) => {
        match result.get("points") {
          Some(JArray(points)) => assert_eq(points.length(), 1)
          _ => assert_true(false)
        }
        match result.get("next_page_offset") {
          Some(JNumber(offset)) => assert_eq(offset, 2.0)
          _ => assert_true(false)
        }
      }
      _ => assert_true(false)
    }
  })
}
