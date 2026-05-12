// Blackbox tests run against the package's public API.
// All tests are async since VectorDB operations go through WAL.

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
/// Test: Basic VectorDB operations with Bruteforce
test "api/bruteforce_basic" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory_bruteforce(3)
    // Add vectors
    let _ = db.add(
      @types.VectorId::from_int(1),
      [1.0, 0.0, 0.0],
      @types.empty_attrs(),
      0L,
    )
    let _ = db.add(
      @types.VectorId::from_int(2),
      [0.0, 1.0, 0.0],
      @types.empty_attrs(),
      0L,
    )
    let _ = db.add(
      @types.VectorId::from_int(3),
      [0.0, 0.0, 1.0],
      @types.empty_attrs(),
      0L,
    )
    inspect(db.size(), content="3")
    // Search
    let results = db.search([1.0, 0.0, 0.0], 2, None)
    inspect(results.length(), content="2")
    inspect(results[0].id, content="Int64Id(1)")
    // Has/Get
    inspect(db.has(@types.VectorId::from_int(1)), content="true")
    inspect(db.has(@types.VectorId::from_int(99)), content="false")
    let record = db.get(@types.VectorId::from_int(1))
    inspect(record is None, content="false")
  })
}

///|
/// Test: HNSW search correctness
test "api/hnsw_search" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory_hnsw(3, metric=@types.Dot)
    let _ = db.add(
      @types.VectorId::from_int(1),
      [1.0, 0.0, 0.0],
      @types.empty_attrs(),
      0L,
    )
    let _ = db.add(
      @types.VectorId::from_int(2),
      [0.9, 0.1, 0.0],
      @types.empty_attrs(),
      0L,
    )
    let _ = db.add(
      @types.VectorId::from_int(3),
      [0.0, 1.0, 0.0],
      @types.empty_attrs(),
      0L,
    )
    let _ = db.add(
      @types.VectorId::from_int(4),
      [0.0, 0.0, 1.0],
      @types.empty_attrs(),
      0L,
    )
    // Search for [1,0,0] - should find id=1 (exact match) or id=2 (similar)
    let results = db.search([1.0, 0.0, 0.0], 2, None)
    inspect(results.length(), content="2")
    // First result should be id=1 (dot product = 1.0)
    inspect(results[0].id, content="Int64Id(1)")
  })
}

///|
/// Test: IVF with training
test "api/ivf_training" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory_ivf(3, metric=@types.Dot)
    // Add vectors in different clusters
    let _ = db.add(
      @types.VectorId::from_int(1),
      [1.0, 0.0, 0.0],
      @types.empty_attrs(),
      0L,
    )
    let _ = db.add(
      @types.VectorId::from_int(2),
      [0.9, 0.1, 0.0],
      @types.empty_attrs(),
      0L,
    )
    let _ = db.add(
      @types.VectorId::from_int(3),
      [0.0, 1.0, 0.0],
      @types.empty_attrs(),
      0L,
    )
    let _ = db.add(
      @types.VectorId::from_int(4),
      [0.1, 0.9, 0.0],
      @types.empty_attrs(),
      0L,
    )
    // Train IVF
    db.train(iterations=5)
    // Search should still work
    let results = db.search([1.0, 0.0, 0.0], 2, None)
    inspect(results.length() > 0, content="true")
  })
}

///|
/// Test: Cosine metric auto-normalization
test "api/cosine_normalization" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory(
      2,
      metric=@types.Cosine,
      strategy=@types.Bruteforce,
    )
    // Add non-normalized vector [3, 4] - should be normalized to [0.6, 0.8]
    let _ = db.add(
      @types.VectorId::from_int(1),
      [3.0, 4.0],
      @types.empty_attrs(),
      0L,
    )
    let record = db.get(@types.VectorId::from_int(1))
    let v = record.unwrap().vector
    // Check normalization: [3,4] -> [0.6, 0.8]
    inspect((v[0] - 0.6).abs() < 0.0001, content="true")
    inspect((v[1] - 0.8).abs() < 0.0001, content="true")
  })
}

///|
/// Test: L2 metric (negative squared distance)
test "api/l2_metric" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory(
      2,
      metric=@types.L2,
      strategy=@types.Bruteforce,
    )
    let _ = db.add(
      @types.VectorId::from_int(1),
      [0.0, 0.0],
      @types.empty_attrs(),
      0L,
    )
    let _ = db.add(
      @types.VectorId::from_int(2),
      [1.0, 0.0],
      @types.empty_attrs(),
      0L,
    )
    let _ = db.add(
      @types.VectorId::from_int(3),
      [10.0, 10.0],
      @types.empty_attrs(),
      0L,
    )
    // Search from origin - closest should be id=1
    let results = db.search([0.0, 0.0], 3, None)
    inspect(results[0].id, content="Int64Id(1)")
    inspect(results[0].score, content="0") // L2 distance = 0
    inspect(results[1].id, content="Int64Id(2)")
    inspect(results[1].score, content="-1") // L2 distance = -1
  })
}

///|
/// Test: Attributes storage and retrieval
test "api/attributes" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory_bruteforce(2)
    let attrs = @types.empty_attrs()
    attrs.set("name", @types.String("test"))
    attrs.set("count", @types.Int(42L))
    attrs.set("score", @types.Float(3.14))
    attrs.set("active", @types.Bool(true))
    let _ = db.add(@types.VectorId::from_int(1), [1.0, 0.0], attrs, 0L)
    // Retrieve and check
    let record = db.get(@types.VectorId::from_int(1))
    let a = record.unwrap().attrs
    match a.get("name") {
      Some(@types.String(s)) => inspect(s, content="test")
      _ => inspect(false, content="true")
    }
    match a.get("count") {
      Some(@types.Int(n)) => inspect(n, content="42")
      _ => inspect(false, content="true")
    }
  })
}

///|
/// Test: Search with filter
test "api/search_filter" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory_bruteforce(2)
    let attrs1 = @types.empty_attrs()
    attrs1.set("category", @types.String("A"))
    let attrs2 = @types.empty_attrs()
    attrs2.set("category", @types.String("B"))
    let _ = db.add(@types.VectorId::from_int(1), [1.0, 0.0], attrs1, 0L) // Best match, category A
    let _ = db.add(@types.VectorId::from_int(2), [0.9, 0.1], attrs2, 0L) // Second best, category B
    let _ = db.add(@types.VectorId::from_int(3), [0.5, 0.5], attrs1, 0L) // Third, category A
    // Search with filter: only category B
    let filter = fn(_id : @types.VectorId, attrs : @types.Attrs) -> Bool {
      match attrs.get("category") {
        Some(@types.String(s)) => s == "B"
        _ => false
      }
    }
    let results = db.search_with_filter([1.0, 0.0], 10, Some(filter))
    inspect(results.length(), content="1")
    inspect(results[0].id, content="Int64Id(2)")
  })
}

///|
/// Test: Upsert (update existing vector)
test "api/upsert" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory_bruteforce(2)
    // Initial upsert
    inspect(db.has(@types.VectorId::from_int(1)), content="false")
    db.upsert(
      [(@types.VectorId::from_int(1), [1.0, 0.0], @types.empty_attrs())],
      0L,
    )
    inspect(db.size(), content="1")
    // Upsert with same id - should update
    let attrs = @types.empty_attrs()
    attrs.set("updated", @types.Bool(true))
    db.upsert([(@types.VectorId::from_int(1), [0.0, 1.0], attrs)], 0L)
    inspect(db.size(), content="1")
    // Verify update
    let record = db.get(@types.VectorId::from_int(1))
    let v = record.unwrap().vector
    inspect(v[0], content="0")
    inspect(v[1], content="1")
  })
}

///|
/// Test: Remove vector
test "api/remove" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory_bruteforce(2)
    let _ = db.add(
      @types.VectorId::from_int(1),
      [1.0, 0.0],
      @types.empty_attrs(),
      0L,
    )
    let _ = db.add(
      @types.VectorId::from_int(2),
      [0.0, 1.0],
      @types.empty_attrs(),
      0L,
    )
    let _ = db.add(
      @types.VectorId::from_int(3),
      [0.5, 0.5],
      @types.empty_attrs(),
      0L,
    )
    inspect(db.size(), content="3")
    // Remove middle element
    let removed = db.remove(@types.VectorId::from_int(2), 0L)
    inspect(removed, content="true")
    inspect(db.size(), content="2")
    inspect(db.has(@types.VectorId::from_int(2)), content="false")
    // Remove non-existent
    let removed2 = db.remove(@types.VectorId::from_int(99), 0L)
    inspect(removed2, content="false")
  })
}

///|
/// Test: Full serialization roundtrip
test "api/serialization_roundtrip" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory_bruteforce(3)
    let attrs = @types.empty_attrs()
    attrs.set("tag", @types.String("important"))
    let _ = db.add(@types.VectorId::from_int(1), [1.0, 0.0, 0.0], attrs, 0L)
    let _ = db.add(
      @types.VectorId::from_int(2),
      [0.0, 1.0, 0.0],
      @types.empty_attrs(),
      0L,
    )
    let _ = db.add(
      @types.VectorId::from_int(3),
      [0.0, 0.0, 1.0],
      @types.empty_attrs(),
      0L,
    )
    // Serialize
    let bytes = db.serialize_snapshot()
    inspect(bytes.length() > 0, content="true")
    // Deserialize
    let db2 = @vcdb.PersistentDB::deserialize(bytes)
    inspect(db2.size(), content="3")
    // Verify data
    let record = db2.get(@types.VectorId::from_int(1))
    inspect(record is None, content="false")
    // Verify search still works
    let results = db2.search([1.0, 0.0, 0.0], 1, None)
    inspect(results[0].id, content="Int64Id(1)")
    // Verify attrs preserved
    let a = record.unwrap().attrs
    match a.get("tag") {
      Some(@types.String(s)) => inspect(s, content="important")
      _ => inspect(false, content="true")
    }
  })
}

///|
/// Test: HNSW serialization roundtrip
test "api/hnsw_serialization" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory_hnsw(3, metric=@types.Dot)
    let _ = db.add(
      @types.VectorId::from_int(1),
      [1.0, 0.0, 0.0],
      @types.empty_attrs(),
      0L,
    )
    let _ = db.add(
      @types.VectorId::from_int(2),
      [0.0, 1.0, 0.0],
      @types.empty_attrs(),
      0L,
    )
    // Serialize & deserialize
    let bytes = db.serialize_snapshot()
    let db2 = @vcdb.PersistentDB::deserialize(bytes)
    // Search should work
    let results = db2.search([1.0, 0.0, 0.0], 1, None)
    inspect(results[0].id, content="Int64Id(1)")
  })
}

///|
/// Test: Larger dataset (recall validation)
test "api/recall_validation" {
  run_async_test(async fn() {
    // Create bruteforce DB as ground truth (using Dot metric)
    let bf_db = @vcdb.PersistentDB::in_memory(
      4,
      metric=@types.Dot,
      strategy=@types.Bruteforce,
    )
    // Create HNSW DB with same metric
    let hnsw_db = @vcdb.PersistentDB::in_memory_hnsw(4, metric=@types.Dot)
    // Add same vectors to both
    for i in 0..<20 {
      let v = [
        (i % 4).to_double(),
        ((i + 1) % 4).to_double(),
        ((i + 2) % 4).to_double(),
        ((i + 3) % 4).to_double(),
      ]
      let _ = bf_db.add(
        @types.VectorId::from_int(i),
        v,
        @types.empty_attrs(),
        0L,
      )
      let _ = hnsw_db.add(
        @types.VectorId::from_int(i),
        v,
        @types.empty_attrs(),
        0L,
      )
    }
    // Search both
    let query = [1.0, 2.0, 3.0, 0.0]
    let bf_results = bf_db.search(query, 5, None)
    let hnsw_results = hnsw_db.search(query, 5, None)
    // Both should return results
    inspect(bf_results.length(), content="5")
    inspect(hnsw_results.length() > 0, content="true")
    // HNSW top result should be in bruteforce top-5 (approximate NN)
    let hnsw_top_id = hnsw_results[0].id
    let mut found_in_bf = false
    for r in bf_results {
      if r.id == hnsw_top_id {
        found_in_bf = true
        break
      }
    }
    inspect(found_in_bf, content="true")
  })
}

///|
/// Test: Empty database edge case
test "api/empty_db" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory_bruteforce(3)
    inspect(db.size(), content="0")
    // Search on empty should return empty
    let results = db.search([1.0, 0.0, 0.0], 10, None)
    inspect(results.length(), content="0")
    // Get on non-existent should return None
    let record = db.get(@types.VectorId::from_int(1))
    inspect(record is None, content="true")
  })
}

///|
/// Test: Find (single best match)
test "api/find" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory_bruteforce(2)
    let _ = db.add(
      @types.VectorId::from_int(1),
      [1.0, 0.0],
      @types.empty_attrs(),
      0L,
    )
    let _ = db.add(
      @types.VectorId::from_int(2),
      [0.0, 1.0],
      @types.empty_attrs(),
      0L,
    )
    // Find best match
    let result = db.find([1.0, 0.0], None)
    inspect(result is None, content="false")
    inspect(result.unwrap().id, content="Int64Id(1)")
    // Find on empty should return None
    let empty_db = @vcdb.PersistentDB::in_memory_bruteforce(2)
    let empty_result = empty_db.find([1.0, 0.0], None)
    inspect(empty_result is None, content="true")
  })
}

///|
/// Test: Large dataset with 200 vectors
test "api/large_dataset" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory_bruteforce(4)
    // Add 200 vectors in 4 clusters
    for i in 0..<200 {
      let cluster = i / 50
      let base = match cluster {
        0 => [1.0, 0.0, 0.0, 0.0]
        1 => [0.0, 1.0, 0.0, 0.0]
        2 => [0.0, 0.0, 1.0, 0.0]
        _ => [0.0, 0.0, 0.0, 1.0]
      }
      // Add small jitter
      let jitter = (i % 10).to_double() * 0.01
      let v = [base[0] + jitter, base[1] + jitter, base[2], base[3]]
      let attrs = @types.empty_attrs()
      attrs.set("cluster", @types.Int(cluster.to_int64()))
      let _ = db.add(@types.VectorId::from_int(i), v, attrs, 0L)
    }
    inspect(db.size(), content="200")
    // Search for cluster 0 center
    let results = db.search([1.0, 0.0, 0.0, 0.0], 10, None)
    inspect(results.length(), content="10")
    // All top results should be from cluster 0 (ids 0-49)
    let mut cluster0_count = 0
    for hit in results {
      let id = match hit.id {
        Int64Id(v) => v
        _ => abort("")
      }
      if id >= 0L && id < 50L {
        cluster0_count = cluster0_count + 1
      }
    }
    // Most results should be from cluster 0
    inspect(cluster0_count >= 8, content="true")
  })
}

///|
/// Test: HNSW with larger dataset
test "api/hnsw_large" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory_hnsw(4, metric=@types.Cosine)
    // Add 100 vectors
    for i in 0..<100 {
      let v = [
        (i % 4).to_double(),
        ((i + 1) % 4).to_double(),
        ((i + 2) % 4).to_double(),
        ((i + 3) % 4).to_double(),
      ]
      let _ = db.add(@types.VectorId::from_int(i), v, @types.empty_attrs(), 0L)
    }
    inspect(db.size(), content="100")
    // Search
    let results = db.search([1.0, 2.0, 3.0, 0.0], 10, None)
    inspect(results.length(), content="10")
    // Serialize and restore
    let bytes = db.serialize_snapshot()
    let db2 = @vcdb.PersistentDB::deserialize(bytes)
    inspect(db2.size(), content="100")
    let results2 = db2.search([1.0, 2.0, 3.0, 0.0], 10, None)
    inspect(results2.length(), content="10")
  })
}

///|
/// Test: IVF training with clustered data
test "api/ivf_clustered" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory_ivf(4, metric=@types.Cosine)
    // Create 3 clusters
    // Cluster A: around [1, 0, 0, 0]
    for i in 0..<30 {
      let jitter = (i % 5).to_double() * 0.02
      let attrs = @types.empty_attrs()
      attrs.set("cluster", @types.String("A"))
      let _ = db.add(
        @types.VectorId::from_int(i),
        [1.0, jitter, 0.0, 0.0],
        attrs,
        0L,
      )
    }
    // Cluster B: around [0, 1, 0, 0]
    for i in 30..<60 {
      let jitter = (i % 5).to_double() * 0.02
      let attrs = @types.empty_attrs()
      attrs.set("cluster", @types.String("B"))
      let _ = db.add(
        @types.VectorId::from_int(i),
        [0.0, 1.0, jitter, 0.0],
        attrs,
        0L,
      )
    }
    // Cluster C: around [0, 0, 1, 0]
    for i in 60..<90 {
      let jitter = (i % 5).to_double() * 0.02
      let attrs = @types.empty_attrs()
      attrs.set("cluster", @types.String("C"))
      let _ = db.add(
        @types.VectorId::from_int(i),
        [0.0, 0.0, 1.0, jitter],
        attrs,
        0L,
      )
    }
    // Train IVF
    db.train(iterations=10)
    // Search for cluster A
    let results_a = db.search([1.0, 0.0, 0.0, 0.0], 5, None)
    inspect(results_a.length(), content="5")
    // All should be from cluster A (ids 0-29)
    let mut cluster_a_count = 0
    for hit in results_a {
      let id = match hit.id {
        Int64Id(v) => v
        _ => abort("")
      }
      if id >= 0L && id < 30L {
        cluster_a_count = cluster_a_count + 1
      }
    }
    inspect(cluster_a_count >= 3, content="true")
  })
}

///|
/// Test: Mixed operations (add, update, remove, search)
test "api/mixed_operations" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory_bruteforce(3)
    // Add initial vectors
    for i in 1..<=10 {
      let attrs = @types.empty_attrs()
      attrs.set("version", @types.Int(1L))
      let _ = db.add(
        @types.VectorId::from_int(i),
        [i.to_double() / 10.0, 1.0 - i.to_double() / 10.0, 0.0],
        attrs,
        0L,
      )
    }
    inspect(db.size(), content="10")
    // Update some vectors
    for i in 1..<=5 {
      let attrs = @types.empty_attrs()
      attrs.set("version", @types.Int(2L))
      db.upsert(
        [
          (
            @types.VectorId::from_int(i),
            [0.0, i.to_double() / 10.0, 1.0 - i.to_double() / 10.0],
            attrs,
          ),
        ],
        0L,
      )
    }
    inspect(db.size(), content="10")
    // Verify update
    let record3 = db.get(@types.VectorId::from_int(3))
    match record3 {
      Some(r) =>
        match r.attrs.get("version") {
          Some(@types.Int(v)) => inspect(v, content="2")
          _ => inspect(false, content="true")
        }
      None => inspect(false, content="true")
    }
    // Remove some vectors
    for i in 8..<=10 {
      let _ = db.remove(@types.VectorId::from_int(i), 0L)
    }
    inspect(db.size(), content="7")
    // Search should still work
    let results = db.search([1.0, 0.0, 0.0], 5, None)
    inspect(results.length(), content="5")
  })
}

///|
/// Test: Search with complex filter
test "api/complex_filter" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory_bruteforce(2)
    // Add vectors with multiple attributes
    for i in 1..<=20 {
      let attrs = @types.empty_attrs()
      attrs.set("score", @types.Int((i * 5).to_int64()))
      attrs.set("active", @types.Bool(i % 2 == 0))
      attrs.set("category", @types.String(if i <= 10 { "A" } else { "B" }))
      let _ = db.add(
        @types.VectorId::from_int(i),
        [i.to_double() / 20.0, 1.0 - i.to_double() / 20.0],
        attrs,
        0L,
      )
    }
    // Filter: category=A AND active=true AND score >= 30
    let filter = fn(_id : @types.VectorId, attrs : @types.Attrs) -> Bool {
      let is_category_a = match attrs.get("category") {
        Some(@types.String(s)) => s == "A"
        _ => false
      }
      let is_active = match attrs.get("active") {
        Some(@types.Bool(b)) => b
        _ => false
      }
      let score_ok = match attrs.get("score") {
        Some(@types.Int(n)) => n >= 30L
        _ => false
      }
      is_category_a && is_active && score_ok
    }
    let results = db.search_with_filter([1.0, 0.0], 10, Some(filter))
    // Should find: ids 6, 8, 10 (even numbers in 1-10 with score >= 30)
    inspect(results.length(), content="3")
  })
}

///|
/// Test: Similarity metrics comparison
test "api/metrics_comparison" {
  run_async_test(async fn() {
    // Same data, different metrics
    let db_cosine = @vcdb.PersistentDB::in_memory(
      3,
      metric=@types.Cosine,
      strategy=@types.Bruteforce,
    )
    let db_dot = @vcdb.PersistentDB::in_memory(
      3,
      metric=@types.Dot,
      strategy=@types.Bruteforce,
    )
    let db_l2 = @vcdb.PersistentDB::in_memory(
      3,
      metric=@types.L2,
      strategy=@types.Bruteforce,
    )
    // Add vectors
    let _ = db_cosine.add(
      @types.VectorId::from_int(1),
      [1.0, 0.0, 0.0],
      @types.empty_attrs(),
      0L,
    )
    let _ = db_cosine.add(
      @types.VectorId::from_int(2),
      [2.0, 0.0, 0.0],
      @types.empty_attrs(),
      0L,
    ) // Same direction, different magnitude
    let _ = db_cosine.add(
      @types.VectorId::from_int(3),
      [0.0, 1.0, 0.0],
      @types.empty_attrs(),
      0L,
    ) // Orthogonal
    let _ = db_dot.add(
      @types.VectorId::from_int(1),
      [1.0, 0.0, 0.0],
      @types.empty_attrs(),
      0L,
    )
    let _ = db_dot.add(
      @types.VectorId::from_int(2),
      [2.0, 0.0, 0.0],
      @types.empty_attrs(),
      0L,
    )
    let _ = db_dot.add(
      @types.VectorId::from_int(3),
      [0.0, 1.0, 0.0],
      @types.empty_attrs(),
      0L,
    )
    let _ = db_l2.add(
      @types.VectorId::from_int(1),
      [1.0, 0.0, 0.0],
      @types.empty_attrs(),
      0L,
    )
    let _ = db_l2.add(
      @types.VectorId::from_int(2),
      [2.0, 0.0, 0.0],
      @types.empty_attrs(),
      0L,
    )
    let _ = db_l2.add(
      @types.VectorId::from_int(3),
      [0.0, 1.0, 0.0],
      @types.empty_attrs(),
      0L,
    )
    // Query [1, 0, 0]
    let cosine_results = db_cosine.search([1.0, 0.0, 0.0], 3, None)
    let dot_results = db_dot.search([1.0, 0.0, 0.0], 3, None)
    let l2_results = db_l2.search([1.0, 0.0, 0.0], 3, None)
    // Cosine: id=1 and id=2 should have same score (normalized)
    // Note: With cosine, [1,0,0] and [2,0,0] become the same after normalization
    inspect(
      match cosine_results[0].id {
        Int64Id(v) => v <= 2L
        _ => false
      },
      content="true",
    )
    // Dot: id=2 should score highest (2.0 > 1.0)
    inspect(dot_results[0].id, content="Int64Id(2)")
    // L2: id=1 should be closest (distance = 0)
    inspect(l2_results[0].id, content="Int64Id(1)")
    inspect(l2_results[0].score, content="0")
  })
}

///|
/// Test: Bulk add operations
test "api/bulk_add" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory_bruteforce(3)
    // Add multiple vectors at once
    for i in 1..<=50 {
      let attrs = @types.empty_attrs()
      attrs.set("batch", @types.Int(1L))
      let _ = db.add(
        @types.VectorId::from_int(i),
        [
          (i % 3).to_double(),
          ((i + 1) % 3).to_double(),
          ((i + 2) % 3).to_double(),
        ],
        attrs,
        0L,
      )
    }
    inspect(db.size(), content="50")
    // Add another batch
    for i in 51..<=100 {
      let attrs = @types.empty_attrs()
      attrs.set("batch", @types.Int(2L))
      let _ = db.add(
        @types.VectorId::from_int(i),
        [
          (i % 3).to_double(),
          ((i + 1) % 3).to_double(),
          ((i + 2) % 3).to_double(),
        ],
        attrs,
        0L,
      )
    }
    inspect(db.size(), content="100")
    // Search should return results from both batches
    let results = db.search([1.0, 0.0, 0.0], 10, None)
    inspect(results.length(), content="10")
  })
}

///|
/// Test: Bulk upsert operations
test "api/bulk_upsert" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory_bruteforce(2)
    // Initial adds
    for i in 1..<=20 {
      let _ = db.add(
        @types.VectorId::from_int(i),
        [i.to_double() / 20.0, 1.0 - i.to_double() / 20.0],
        @types.empty_attrs(),
        0L,
      )
    }
    inspect(db.size(), content="20")
    // Upsert: update half, add new half
    for i in 11..<=30 {
      let attrs = @types.empty_attrs()
      attrs.set("updated", @types.Bool(true))
      db.upsert([(@types.VectorId::from_int(i), [0.5, 0.5], attrs)], 0L)
    }
    inspect(db.size(), content="30") // 20 original + 10 new (11-20 were updated)
    // Verify updates
    let record15 = db.get(@types.VectorId::from_int(15))
    match record15 {
      Some(r) =>
        match r.attrs.get("updated") {
          Some(@types.Bool(b)) => inspect(b, content="true")
          _ => inspect(false, content="true")
        }
      None => inspect(false, content="true")
    }
  })
}

///|
/// Test: Bulk remove operations
test "api/bulk_remove" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory_bruteforce(2)
    // Add 50 vectors
    for i in 1..<=50 {
      let _ = db.add(
        @types.VectorId::from_int(i),
        [i.to_double() / 50.0, 1.0 - i.to_double() / 50.0],
        @types.empty_attrs(),
        0L,
      )
    }
    inspect(db.size(), content="50")
    // Remove odd numbers
    for i in 1..<=50 {
      if i % 2 == 1 {
        let _ = db.remove(@types.VectorId::from_int(i), 0L)
      }
    }
    inspect(db.size(), content="25")
    // Verify odd IDs are removed
    inspect(db.has(@types.VectorId::from_int(1)), content="false")
    inspect(db.has(@types.VectorId::from_int(2)), content="true")
    inspect(db.has(@types.VectorId::from_int(49)), content="false")
    inspect(db.has(@types.VectorId::from_int(50)), content="true")
  })
}

///|
/// Test: Search with range filter using attr index
test "api/search_range_prefilter" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory_bruteforce(2)
    // Add vectors with numeric values
    for i in 1..<=100 {
      let attrs = @types.empty_attrs()
      attrs.set("price", @types.Int(i.to_int64() * 10L))
      let id = @types.VectorId::from_int(i)
      let _ = db.add(
        id,
        [i.to_double() / 100.0, 1.0 - i.to_double() / 100.0],
        attrs,
        0L,
      )
    }
    // Filter: price >= 500 AND price <= 690
    let range = @types.NumericRange::between(500.0, 690.0)
    let expr = @filter.FilterExpr::range("price", range)
    let results = db.search_with_expr(
      [1.0, 0.0],
      50,
      Some(expr),
      None,
      @filter.PreFilter,
    )
    // Should get IDs 50-69 (price 500-690)
    inspect(results.length(), content="20")
  })
}

///|
/// Test: indexed filter paths treat Null as not existing.
test "api/filter_null_exists_semantics" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory_bruteforce(2)
    let attrs_null = @types.empty_attrs()
    attrs_null.set("deleted_at", @types.Null)
    let attrs_missing = @types.empty_attrs()
    let attrs_value = @types.empty_attrs()
    attrs_value.set("deleted_at", @types.String("2024-01-01"))
    let _ = db.add(@types.VectorId::from_int(1), [1.0, 0.0], attrs_null, 0L)
    let _ = db.add(@types.VectorId::from_int(2), [0.0, 1.0], attrs_missing, 0L)
    let _ = db.add(@types.VectorId::from_int(3), [0.5, 0.5], attrs_value, 0L)

    let exists_expr = @filter.FilterExpr::exists("deleted_at")
    let is_null_expr = @filter.FilterExpr::is_null("deleted_at")
    inspect(db.count_filtered(expr=Some(exists_expr)), content="1")
    inspect(db.count_filtered(expr=Some(is_null_expr)), content="2")

    let exists_search = db.search_with_expr(
      [1.0, 0.0],
      10,
      Some(exists_expr),
      None,
      @filter.PreFilter,
    )
    inspect(exists_search.length(), content="1")
    inspect(exists_search[0].id, content="Int64Id(3)")
    let is_null_search = db.search_with_expr(
      [1.0, 0.0],
      10,
      Some(is_null_expr),
      None,
      @filter.PreFilter,
    )
    inspect(is_null_search.length(), content="2")

    let exists_scroll = db.scroll_filtered(expr=Some(exists_expr), limit=10)
    inspect(exists_scroll.length(), content="1")
    let (exists_id, _) = exists_scroll[0]
    inspect(exists_id, content="Int64Id(3)")
    let is_null_scroll = db.scroll_filtered(expr=Some(is_null_expr), limit=10)
    inspect(is_null_scroll.length(), content="2")
    let (null_id0, _) = is_null_scroll[0]
    let (null_id1, _) = is_null_scroll[1]
    inspect(null_id0, content="Int64Id(1)")
    inspect(null_id1, content="Int64Id(2)")
  })
}

///|
/// Test: HNSW remove and search consistency
/// Note: HNSW uses tombstone-based removal - physical size remains unchanged
/// until compact() is called. Heavy tombstoning degrades recall.
test "api/hnsw_remove_search" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory_hnsw(3, metric=@types.Dot)
    // Add vectors
    for i in 1..<=20 {
      let _ = db.add(
        @types.VectorId::from_int(i),
        [
          (i % 3).to_double(),
          ((i + 1) % 3).to_double(),
          ((i + 2) % 3).to_double(),
        ],
        @types.empty_attrs(),
        0L,
      )
    }
    inspect(db.size(), content="20")
    // Remove first 5 vectors (lighter tombstoning for better recall)
    for i in 1..<=5 {
      let removed = db.remove(@types.VectorId::from_int(i), 0L)
      inspect(removed, content="true")
    }
    // size() now excludes tombstones (use raw_size() to include them)
    inspect(db.size(), content="15")
    inspect(db.raw_size(), content="20")
    // Search should not return removed IDs
    let results = db.search([1.0, 0.0, 0.0], 20, None)
    // With 25% tombstones, expect good recall (at least 10 out of 15)
    inspect(results.length() >= 10, content="true")
    for hit in results {
      let id = match hit.id {
        Int64Id(v) => v
        _ => abort("")
      }
      // No tombstoned IDs should be returned
      inspect(id > 5L, content="true")
    }
  })
}

///|
/// Test: High-dimensional vectors
test "api/high_dimensional" {
  run_async_test(async fn() {
    let dim = 128
    let db = @vcdb.PersistentDB::in_memory(
      dim,
      metric=@types.Cosine,
      strategy=@types.Bruteforce,
    )
    // Add vectors
    for i in 1..<=50 {
      let v : Array[Double] = Array::make(dim, 0.0)
      // Set some dimensions based on ID
      v[i % dim] = 1.0
      v[i * 7 % dim] = 0.5
      let _ = db.add(@types.VectorId::from_int(i), v, @types.empty_attrs(), 0L)
    }
    inspect(db.size(), content="50")
    // Create query vector
    let query : Array[Double] = Array::make(dim, 0.0)
    query[1] = 1.0
    query[7] = 0.5
    // Search
    let results = db.search(query, 5, None)
    inspect(results.length(), content="5")
    // ID 1 should be best match (same pattern)
    inspect(results[0].id, content="Int64Id(1)")
  })
}

///|
/// Test: Complex must/must_not/should expressions
test "api/complex_expr_search" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory_bruteforce(2)
    // Setup data
    for i in 1..<=20 {
      let attrs = @types.empty_attrs()
      attrs.set("active", @types.Bool(i % 2 == 0))
      attrs.set("score", @types.Int(i.to_int64() * 5L))
      attrs.set("category", @types.String(if i <= 10 { "X" } else { "Y" }))
      let id = @types.VectorId::from_int(i)
      let _ = db.add(
        id,
        [i.to_double() / 20.0, 1.0 - i.to_double() / 20.0],
        attrs,
        0L,
      )
    }
    // Must: category=X AND active=true
    let expr = @filter.FilterExpr::must([
      @filter.FilterExpr::match_("category", @types.String("X")),
      @filter.FilterExpr::match_("active", @types.Bool(true)),
    ])
    let results = db.search_with_expr(
      [1.0, 0.0],
      10,
      Some(expr),
      None,
      @filter.PostFilter,
    )
    // IDs 2,4,6,8,10 (even numbers in 1-10)
    inspect(results.length(), content="5")
  })
}

///|
/// Test: Unified CRUD operations
test "api/unified_crud" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory_bruteforce(3)
    // set single
    let _ = db.add(
      @types.VectorId::from_int(1),
      [1.0, 0.0, 0.0],
      {
        let a = @types.empty_attrs()
        a.set("tag", @types.String("a"))
        a
      },
      0L,
    )
    inspect(db.has(@types.VectorId::from_int(1)), content="true")
    let r1 = db.get(@types.VectorId::from_int(1))
    match r1 {
      Some(r) =>
        match r.attrs.get("tag") {
          Some(@types.String(s)) => inspect(s, content="a")
          _ => inspect(false, content="true")
        }
      None => inspect(false, content="true")
    }
    // upsert update
    db.upsert(
      [
        (
          @types.VectorId::from_int(1),
          [1.0, 0.0, 0.0],
          {
            let a = @types.empty_attrs()
            a.set("tag", @types.String("aa"))
            a
          },
        ),
      ],
      0L,
    )
    let r2 = db.get(@types.VectorId::from_int(1))
    match r2 {
      Some(r) =>
        match r.attrs.get("tag") {
          Some(@types.String(s)) => inspect(s, content="aa")
          _ => inspect(false, content="true")
        }
      None => inspect(false, content="true")
    }
    // add multiple
    let _ = db.add(
      @types.VectorId::from_int(2),
      [0.0, 1.0, 0.0],
      {
        let a = @types.empty_attrs()
        a.set("tag", @types.String("b"))
        a
      },
      0L,
    )
    let _ = db.add(
      @types.VectorId::from_int(3),
      [0.0, 0.0, 1.0],
      @types.empty_attrs(),
      0L,
    )
    inspect(db.size(), content="3")
    // delete
    let deleted = db.remove(@types.VectorId::from_int(3), 0L)
    inspect(deleted, content="true")
    inspect(db.has(@types.VectorId::from_int(3)), content="false")
  })
}
