// Blackbox tests run against the package's public API. Use `@vcdb` to import.
// Prefer high-level behaviors over implementation details.
// Run `moon test` to execute and `moon test --update` to refresh snapshots.

///|
/// Test: Basic VectorDB operations with Bruteforce
test "api/bruteforce_basic" {
  let db = @vcdb.VectorDB::with_dim(3)
  // Add vectors
  db.add(@core.VectorId::from_int(1), [1.0, 0.0, 0.0], @core.empty_attrs())
  db.add(@core.VectorId::from_int(2), [0.0, 1.0, 0.0], @core.empty_attrs())
  db.add(@core.VectorId::from_int(3), [0.0, 0.0, 1.0], @core.empty_attrs())
  inspect(db.size(), content="3")
  // Search
  let results = db.search([1.0, 0.0, 0.0], 2, None)
  inspect(results.length(), content="2")
  inspect(results[0].id.to_int64(), content="1")
  // Has/Get
  inspect(db.has(@core.VectorId::from_int(1)), content="true")
  inspect(db.has(@core.VectorId::from_int(99)), content="false")
  let record = db.get(@core.VectorId::from_int(1))
  inspect(record is None, content="false")
}

///|
/// Test: HNSW search correctness
test "api/hnsw_search" {
  let db = @vcdb.VectorDB::with_hnsw(3, metric=@core.Dot)
  db.add(@core.VectorId::from_int(1), [1.0, 0.0, 0.0], @core.empty_attrs())
  db.add(@core.VectorId::from_int(2), [0.9, 0.1, 0.0], @core.empty_attrs())
  db.add(@core.VectorId::from_int(3), [0.0, 1.0, 0.0], @core.empty_attrs())
  db.add(@core.VectorId::from_int(4), [0.0, 0.0, 1.0], @core.empty_attrs())
  // Search for [1,0,0] - should find id=1 (exact match) or id=2 (similar)
  let results = db.search([1.0, 0.0, 0.0], 2, None)
  inspect(results.length(), content="2")
  // First result should be id=1 (dot product = 1.0)
  inspect(results[0].id.to_int64(), content="1")
}

///|
/// Test: IVF with training
test "api/ivf_training" {
  let db = @vcdb.VectorDB::with_ivf(3, metric=@core.Dot)
  // Add vectors in different clusters
  db.add(@core.VectorId::from_int(1), [1.0, 0.0, 0.0], @core.empty_attrs())
  db.add(@core.VectorId::from_int(2), [0.9, 0.1, 0.0], @core.empty_attrs())
  db.add(@core.VectorId::from_int(3), [0.0, 1.0, 0.0], @core.empty_attrs())
  db.add(@core.VectorId::from_int(4), [0.1, 0.9, 0.0], @core.empty_attrs())
  // Train IVF
  db.train(iterations=5)
  // Search should still work
  let results = db.search([1.0, 0.0, 0.0], 2, None)
  inspect(results.length() > 0, content="true")
}

///|
/// Test: Cosine metric auto-normalization
test "api/cosine_normalization" {
  let db = @vcdb.VectorDB::new({
    dim: 2,
    metric: @core.Cosine,
    capacity: 10,
    strategy: @core.Bruteforce,
  })
  // Add non-normalized vector [3, 4] - should be normalized to [0.6, 0.8]
  db.add(@core.VectorId::from_int(1), [3.0, 4.0], @core.empty_attrs())
  let record = db.get(@core.VectorId::from_int(1))
  let v = record.unwrap().vector
  // Check normalization: [3,4] -> [0.6, 0.8]
  inspect((v[0] - 0.6).abs() < 0.0001, content="true")
  inspect((v[1] - 0.8).abs() < 0.0001, content="true")
}

///|
/// Test: L2 metric (negative squared distance)
test "api/l2_metric" {
  let db = @vcdb.VectorDB::new({
    dim: 2,
    metric: @core.L2,
    capacity: 10,
    strategy: @core.Bruteforce,
  })
  db.add(@core.VectorId::from_int(1), [0.0, 0.0], @core.empty_attrs())
  db.add(@core.VectorId::from_int(2), [1.0, 0.0], @core.empty_attrs())
  db.add(@core.VectorId::from_int(3), [10.0, 10.0], @core.empty_attrs())
  // Search from origin - closest should be id=1
  let results = db.search([0.0, 0.0], 3, None)
  inspect(results[0].id.to_int64(), content="1")
  inspect(results[0].score, content="0") // L2 distance = 0
  inspect(results[1].id.to_int64(), content="2")
  inspect(results[1].score, content="-1") // L2 distance = -1
}

///|
/// Test: Attributes storage and retrieval
test "api/attributes" {
  let db = @vcdb.VectorDB::with_dim(2)
  let attrs = @core.empty_attrs()
  attrs.set("name", @core.String("test"))
  attrs.set("count", @core.Int(42L))
  attrs.set("score", @core.Float(3.14))
  attrs.set("active", @core.Bool(true))
  db.add(@core.VectorId::from_int(1), [1.0, 0.0], attrs)
  // Retrieve and check
  let record = db.get(@core.VectorId::from_int(1))
  let a = record.unwrap().attrs
  match a.get("name") {
    Some(@core.String(s)) => inspect(s, content="test")
    _ => inspect(false, content="true")
  }
  match a.get("count") {
    Some(@core.Int(n)) => inspect(n, content="42")
    _ => inspect(false, content="true")
  }
}

///|
/// Test: Search with filter
test "api/search_filter" {
  let db = @vcdb.VectorDB::with_dim(2)
  let attrs1 = @core.empty_attrs()
  attrs1.set("category", @core.String("A"))
  let attrs2 = @core.empty_attrs()
  attrs2.set("category", @core.String("B"))
  db.add(@core.VectorId::from_int(1), [1.0, 0.0], attrs1) // Best match, category A
  db.add(@core.VectorId::from_int(2), [0.9, 0.1], attrs2) // Second best, category B
  db.add(@core.VectorId::from_int(3), [0.5, 0.5], attrs1) // Third, category A
  // Search with filter: only category B
  let filter = fn(_id : @core.VectorId, attrs : @core.Attrs) -> Bool {
    match attrs.get("category") {
      Some(@core.String(s)) => s == "B"
      _ => false
    }
  }
  let results = db.search([1.0, 0.0], 10, Some(filter))
  inspect(results.length(), content="1")
  inspect(results[0].id.to_int64(), content="2")
}

///|
/// Test: Upsert (update existing vector)
test "api/upsert" {
  let db = @vcdb.VectorDB::with_dim(2)
  // Initial add
  let created1 = db.upsert(
    @core.VectorId::from_int(1),
    [1.0, 0.0],
    @core.empty_attrs(),
  )
  inspect(created1, content="true")
  inspect(db.size(), content="1")
  // Upsert with same id - should update
  let attrs = @core.empty_attrs()
  attrs.set("updated", @core.Bool(true))
  let created2 = db.upsert(@core.VectorId::from_int(1), [0.0, 1.0], attrs)
  inspect(created2, content="false")
  inspect(db.size(), content="1")
  // Verify update
  let record = db.get(@core.VectorId::from_int(1))
  let v = record.unwrap().vector
  inspect(v[0], content="0")
  inspect(v[1], content="1")
}

///|
/// Test: Remove vector
test "api/remove" {
  let db = @vcdb.VectorDB::with_dim(2)
  db.add(@core.VectorId::from_int(1), [1.0, 0.0], @core.empty_attrs())
  db.add(@core.VectorId::from_int(2), [0.0, 1.0], @core.empty_attrs())
  db.add(@core.VectorId::from_int(3), [0.5, 0.5], @core.empty_attrs())
  inspect(db.size(), content="3")
  // Remove middle element
  let removed = db.remove(@core.VectorId::from_int(2))
  inspect(removed, content="true")
  inspect(db.size(), content="2")
  inspect(db.has(@core.VectorId::from_int(2)), content="false")
  // Remove non-existent
  let removed2 = db.remove(@core.VectorId::from_int(99))
  inspect(removed2, content="false")
}

///|
/// Test: Full serialization roundtrip
test "api/serialization_roundtrip" {
  let db = @vcdb.VectorDB::with_dim(3)
  let attrs = @core.empty_attrs()
  attrs.set("tag", @core.String("important"))
  db.add(@core.VectorId::from_int(1), [1.0, 0.0, 0.0], attrs)
  db.add(@core.VectorId::from_int(2), [0.0, 1.0, 0.0], @core.empty_attrs())
  db.add(@core.VectorId::from_int(3), [0.0, 0.0, 1.0], @core.empty_attrs())
  // Serialize
  let bytes = db.serialize()
  inspect(bytes.length() > 0, content="true")
  // Deserialize
  let db2 = @vcdb.VectorDB::deserialize(bytes)
  inspect(db2.size(), content="3")
  // Verify data
  let record = db2.get(@core.VectorId::from_int(1))
  inspect(record is None, content="false")
  // Verify search still works
  let results = db2.search([1.0, 0.0, 0.0], 1, None)
  inspect(results[0].id.to_int64(), content="1")
  // Verify attrs preserved
  let a = record.unwrap().attrs
  match a.get("tag") {
    Some(@core.String(s)) => inspect(s, content="important")
    _ => inspect(false, content="true")
  }
}

///|
/// Test: HNSW serialization roundtrip
test "api/hnsw_serialization" {
  let db = @vcdb.VectorDB::with_hnsw(3, metric=@core.Dot)
  db.add(@core.VectorId::from_int(1), [1.0, 0.0, 0.0], @core.empty_attrs())
  db.add(@core.VectorId::from_int(2), [0.0, 1.0, 0.0], @core.empty_attrs())
  // Serialize & deserialize
  let bytes = db.serialize()
  let db2 = @vcdb.VectorDB::deserialize(bytes)
  // Search should work
  let results = db2.search([1.0, 0.0, 0.0], 1, None)
  inspect(results[0].id.to_int64(), content="1")
}

///|
/// Test: Larger dataset (recall validation)
test "api/recall_validation" {
  // Create bruteforce DB as ground truth (using Dot metric)
  let bf_options : @core.DatabaseOptions = {
    dim: 4,
    metric: Dot,
    capacity: 1024,
    strategy: Bruteforce,
  }
  let bf_db = @vcdb.VectorDB::new(bf_options)
  // Create HNSW DB with same metric
  let hnsw_db = @vcdb.VectorDB::with_hnsw(4, metric=@core.Dot)
  // Add same vectors to both
  for i in 0..<20 {
    let v = [
      (i % 4).to_double(),
      ((i + 1) % 4).to_double(),
      ((i + 2) % 4).to_double(),
      ((i + 3) % 4).to_double(),
    ]
    bf_db.add(@core.VectorId::from_int(i), v, @core.empty_attrs())
    hnsw_db.add(@core.VectorId::from_int(i), v, @core.empty_attrs())
  }
  // Search both
  let query = [1.0, 2.0, 3.0, 0.0]
  let bf_results = bf_db.search(query, 5, None)
  let hnsw_results = hnsw_db.search(query, 5, None)
  // Both should return results
  inspect(bf_results.length(), content="5")
  inspect(hnsw_results.length() > 0, content="true")
  // HNSW top result should be in bruteforce top-5 (approximate NN)
  let hnsw_top_id = hnsw_results[0].id.to_int64()
  let mut found_in_bf = false
  for r in bf_results {
    if r.id.to_int64() == hnsw_top_id {
      found_in_bf = true
      break
    }
  }
  inspect(found_in_bf, content="true")
}

///|
/// Test: Empty database edge case
test "api/empty_db" {
  let db = @vcdb.VectorDB::with_dim(3)
  inspect(db.size(), content="0")
  // Search on empty should return empty
  let results = db.search([1.0, 0.0, 0.0], 10, None)
  inspect(results.length(), content="0")
  // Get on non-existent should return None
  let record = db.get(@core.VectorId::from_int(1))
  inspect(record is None, content="true")
}

///|
/// Test: Find (single best match)
test "api/find" {
  let db = @vcdb.VectorDB::with_dim(2)
  db.add(@core.VectorId::from_int(1), [1.0, 0.0], @core.empty_attrs())
  db.add(@core.VectorId::from_int(2), [0.0, 1.0], @core.empty_attrs())
  // Find best match
  let result = db.find([1.0, 0.0], None)
  inspect(result is None, content="false")
  inspect(result.unwrap().id.to_int64(), content="1")
  // Find on empty should return None
  let empty_db = @vcdb.VectorDB::with_dim(2)
  let empty_result = empty_db.find([1.0, 0.0], None)
  inspect(empty_result is None, content="true")
}

///|
/// Test: Large dataset with 200 vectors
test "api/large_dataset" {
  let db = @vcdb.VectorDB::with_dim(4)
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
    let attrs = @core.empty_attrs()
    attrs.set("cluster", @core.Int(cluster.to_int64()))
    db.add(@core.VectorId::from_int(i), v, attrs)
  }
  inspect(db.size(), content="200")
  // Search for cluster 0 center
  let results = db.search([1.0, 0.0, 0.0, 0.0], 10, None)
  inspect(results.length(), content="10")
  // All top results should be from cluster 0 (ids 0-49)
  let mut cluster0_count = 0
  for hit in results {
    let id = hit.id.to_int64()
    if id >= 0L && id < 50L {
      cluster0_count = cluster0_count + 1
    }
  }
  // Most results should be from cluster 0
  inspect(cluster0_count >= 8, content="true")
}

///|
/// Test: HNSW with larger dataset
test "api/hnsw_large" {
  let db = @vcdb.VectorDB::with_hnsw(4, metric=@core.Cosine)
  // Add 100 vectors
  for i in 0..<100 {
    let v = [
      (i % 4).to_double(),
      ((i + 1) % 4).to_double(),
      ((i + 2) % 4).to_double(),
      ((i + 3) % 4).to_double(),
    ]
    db.add(@core.VectorId::from_int(i), v, @core.empty_attrs())
  }
  inspect(db.size(), content="100")
  // Search
  let results = db.search([1.0, 2.0, 3.0, 0.0], 10, None)
  inspect(results.length(), content="10")
  // Serialize and restore
  let bytes = db.serialize()
  let db2 = @vcdb.VectorDB::deserialize(bytes)
  inspect(db2.size(), content="100")
  let results2 = db2.search([1.0, 2.0, 3.0, 0.0], 10, None)
  inspect(results2.length(), content="10")
}

///|
/// Test: IVF training with clustered data
test "api/ivf_clustered" {
  let db = @vcdb.VectorDB::with_ivf(4, metric=@core.Cosine)
  // Create 3 clusters
  // Cluster A: around [1, 0, 0, 0]
  for i in 0..<30 {
    let jitter = (i % 5).to_double() * 0.02
    let attrs = @core.empty_attrs()
    attrs.set("cluster", @core.String("A"))
    db.add(@core.VectorId::from_int(i), [1.0, jitter, 0.0, 0.0], attrs)
  }
  // Cluster B: around [0, 1, 0, 0]
  for i in 30..<60 {
    let jitter = (i % 5).to_double() * 0.02
    let attrs = @core.empty_attrs()
    attrs.set("cluster", @core.String("B"))
    db.add(@core.VectorId::from_int(i), [0.0, 1.0, jitter, 0.0], attrs)
  }
  // Cluster C: around [0, 0, 1, 0]
  for i in 60..<90 {
    let jitter = (i % 5).to_double() * 0.02
    let attrs = @core.empty_attrs()
    attrs.set("cluster", @core.String("C"))
    db.add(@core.VectorId::from_int(i), [0.0, 0.0, 1.0, jitter], attrs)
  }
  // Train IVF
  db.train(iterations=10)
  // Search for cluster A
  let results_a = db.search([1.0, 0.0, 0.0, 0.0], 5, None)
  inspect(results_a.length(), content="5")
  // All should be from cluster A (ids 0-29)
  let mut cluster_a_count = 0
  for hit in results_a {
    let id = hit.id.to_int64()
    if id >= 0L && id < 30L {
      cluster_a_count = cluster_a_count + 1
    }
  }
  inspect(cluster_a_count >= 3, content="true")
}

///|
/// Test: Mixed operations (add, update, remove, search)
test "api/mixed_operations" {
  let db = @vcdb.VectorDB::with_dim(3)
  // Add initial vectors
  for i in 1..<=10 {
    let attrs = @core.empty_attrs()
    attrs.set("version", @core.Int(1L))
    db.add(
      @core.VectorId::from_int(i),
      [i.to_double() / 10.0, 1.0 - i.to_double() / 10.0, 0.0],
      attrs,
    )
  }
  inspect(db.size(), content="10")
  // Update some vectors
  for i in 1..<=5 {
    let attrs = @core.empty_attrs()
    attrs.set("version", @core.Int(2L))
    let _ = db.upsert(
      @core.VectorId::from_int(i),
      [0.0, i.to_double() / 10.0, 1.0 - i.to_double() / 10.0],
      attrs,
    )
  }
  inspect(db.size(), content="10")
  // Verify update
  let record3 = db.get(@core.VectorId::from_int(3))
  match record3 {
    Some(r) =>
      match r.attrs.get("version") {
        Some(@core.Int(v)) => inspect(v, content="2")
        _ => inspect(false, content="true")
      }
    None => inspect(false, content="true")
  }
  // Remove some vectors
  for i in 8..<=10 {
    let _ = db.remove(@core.VectorId::from_int(i))
  }
  inspect(db.size(), content="7")
  // Search should still work
  let results = db.search([1.0, 0.0, 0.0], 5, None)
  inspect(results.length(), content="5")
}

///|
/// Test: Search with complex filter
test "api/complex_filter" {
  let db = @vcdb.VectorDB::with_dim(2)
  // Add vectors with multiple attributes
  for i in 1..<=20 {
    let attrs = @core.empty_attrs()
    attrs.set("score", @core.Int((i * 5).to_int64()))
    attrs.set("active", @core.Bool(i % 2 == 0))
    attrs.set("category", @core.String(if i <= 10 { "A" } else { "B" }))
    db.add(
      @core.VectorId::from_int(i),
      [i.to_double() / 20.0, 1.0 - i.to_double() / 20.0],
      attrs,
    )
  }
  // Filter: category=A AND active=true AND score >= 30
  let filter = fn(_id : @core.VectorId, attrs : @core.Attrs) -> Bool {
    let is_category_a = match attrs.get("category") {
      Some(@core.String(s)) => s == "A"
      _ => false
    }
    let is_active = match attrs.get("active") {
      Some(@core.Bool(b)) => b
      _ => false
    }
    let score_ok = match attrs.get("score") {
      Some(@core.Int(n)) => n >= 30L
      _ => false
    }
    is_category_a && is_active && score_ok
  }
  let results = db.search([1.0, 0.0], 10, Some(filter))
  // Should find: ids 6, 8, 10 (even numbers in 1-10 with score >= 30)
  inspect(results.length(), content="3")
}

///|
/// Test: Similarity metrics comparison
test "api/metrics_comparison" {
  // Same data, different metrics
  let db_cosine = @vcdb.VectorDB::new({
    dim: 3,
    metric: @core.Cosine,
    capacity: 10,
    strategy: @core.Bruteforce,
  })
  let db_dot = @vcdb.VectorDB::new({
    dim: 3,
    metric: @core.Dot,
    capacity: 10,
    strategy: @core.Bruteforce,
  })
  let db_l2 = @vcdb.VectorDB::new({
    dim: 3,
    metric: @core.L2,
    capacity: 10,
    strategy: @core.Bruteforce,
  })
  // Add vectors
  db_cosine.add(
    @core.VectorId::from_int(1),
    [1.0, 0.0, 0.0],
    @core.empty_attrs(),
  )
  db_cosine.add(
    @core.VectorId::from_int(2),
    [2.0, 0.0, 0.0],
    @core.empty_attrs(),
  ) // Same direction, different magnitude
  db_cosine.add(
    @core.VectorId::from_int(3),
    [0.0, 1.0, 0.0],
    @core.empty_attrs(),
  ) // Orthogonal
  db_dot.add(@core.VectorId::from_int(1), [1.0, 0.0, 0.0], @core.empty_attrs())
  db_dot.add(@core.VectorId::from_int(2), [2.0, 0.0, 0.0], @core.empty_attrs())
  db_dot.add(@core.VectorId::from_int(3), [0.0, 1.0, 0.0], @core.empty_attrs())
  db_l2.add(@core.VectorId::from_int(1), [1.0, 0.0, 0.0], @core.empty_attrs())
  db_l2.add(@core.VectorId::from_int(2), [2.0, 0.0, 0.0], @core.empty_attrs())
  db_l2.add(@core.VectorId::from_int(3), [0.0, 1.0, 0.0], @core.empty_attrs())
  // Query [1, 0, 0]
  let cosine_results = db_cosine.search([1.0, 0.0, 0.0], 3, None)
  let dot_results = db_dot.search([1.0, 0.0, 0.0], 3, None)
  let l2_results = db_l2.search([1.0, 0.0, 0.0], 3, None)
  // Cosine: id=1 and id=2 should have same score (normalized)
  // Note: With cosine, [1,0,0] and [2,0,0] become the same after normalization
  inspect(cosine_results[0].id.to_int64() <= 2L, content="true")
  // Dot: id=2 should score highest (2.0 > 1.0)
  inspect(dot_results[0].id.to_int64(), content="2")
  // L2: id=1 should be closest (distance = 0)
  inspect(l2_results[0].id.to_int64(), content="1")
  inspect(l2_results[0].score, content="0")
}

///|
/// Test: Bulk add operations
test "api/bulk_add" {
  let db = @vcdb.VectorDB::with_dim(3)
  // Add multiple vectors at once
  for i in 1..<=50 {
    let attrs = @core.empty_attrs()
    attrs.set("batch", @core.Int(1L))
    db.add(
      @core.VectorId::from_int(i),
      [
        (i % 3).to_double(),
        ((i + 1) % 3).to_double(),
        ((i + 2) % 3).to_double(),
      ],
      attrs,
    )
  }
  inspect(db.size(), content="50")
  // Add another batch
  for i in 51..<=100 {
    let attrs = @core.empty_attrs()
    attrs.set("batch", @core.Int(2L))
    db.add(
      @core.VectorId::from_int(i),
      [
        (i % 3).to_double(),
        ((i + 1) % 3).to_double(),
        ((i + 2) % 3).to_double(),
      ],
      attrs,
    )
  }
  inspect(db.size(), content="100")
  // Search should return results from both batches
  let results = db.search([1.0, 0.0, 0.0], 10, None)
  inspect(results.length(), content="10")
}

///|
/// Test: Bulk upsert operations
test "api/bulk_upsert" {
  let db = @vcdb.VectorDB::with_dim(2)
  // Initial adds
  for i in 1..<=20 {
    db.add(
      @core.VectorId::from_int(i),
      [i.to_double() / 20.0, 1.0 - i.to_double() / 20.0],
      @core.empty_attrs(),
    )
  }
  inspect(db.size(), content="20")
  // Upsert: update half, add new half
  for i in 11..<=30 {
    let attrs = @core.empty_attrs()
    attrs.set("updated", @core.Bool(true))
    let _ = db.upsert(@core.VectorId::from_int(i), [0.5, 0.5], attrs)
  }
  inspect(db.size(), content="30") // 20 original + 10 new (11-20 were updated)
  // Verify updates
  let record15 = db.get(@core.VectorId::from_int(15))
  match record15 {
    Some(r) =>
      match r.attrs.get("updated") {
        Some(@core.Bool(b)) => inspect(b, content="true")
        _ => inspect(false, content="true")
      }
    None => inspect(false, content="true")
  }
}

///|
/// Test: Bulk remove operations
test "api/bulk_remove" {
  let db = @vcdb.VectorDB::with_dim(2)
  // Add 50 vectors
  for i in 1..<=50 {
    db.add(
      @core.VectorId::from_int(i),
      [i.to_double() / 50.0, 1.0 - i.to_double() / 50.0],
      @core.empty_attrs(),
    )
  }
  inspect(db.size(), content="50")
  // Remove odd numbers
  for i in 1..<=50 {
    if i % 2 == 1 {
      let _ = db.remove(@core.VectorId::from_int(i))
    }
  }
  inspect(db.size(), content="25")
  // Verify odd IDs are removed
  inspect(db.has(@core.VectorId::from_int(1)), content="false")
  inspect(db.has(@core.VectorId::from_int(2)), content="true")
  inspect(db.has(@core.VectorId::from_int(49)), content="false")
  inspect(db.has(@core.VectorId::from_int(50)), content="true")
}

///|
/// Test: Search with range filter using attr index
test "api/search_range_prefilter" {
  let db = @vcdb.VectorDB::with_dim(2)
  let attr_index = @attr.BasicAttrIndex::new()
  // Add vectors with numeric values
  for i in 1..<=100 {
    let attrs = @core.empty_attrs()
    attrs.set("price", @core.Int(i.to_int64() * 10L))
    let id = @core.VectorId::from_int(i)
    db.add(id, [i.to_double() / 100.0, 1.0 - i.to_double() / 100.0], attrs)
    attr_index.set_attrs(id, attrs)
  }
  // Filter: price >= 500 AND price <= 690
  let range = @core.NumericRange::between(500.0, 690.0)
  let expr = @filter.FilterExpr::range("price", range)
  let results = db.search_with_expr(
    [1.0, 0.0],
    50,
    Some(expr),
    Some(attr_index),
    @filter.PreFilter,
  )
  // Should get IDs 50-69 (price 500-690)
  inspect(results.length(), content="20")
}

///|
/// Test: HNSW remove and search consistency
/// Note: HNSW uses tombstone-based removal - physical size remains unchanged
/// until compact() is called. Heavy tombstoning degrades recall.
test "api/hnsw_remove_search" {
  let db = @vcdb.VectorDB::with_hnsw(3, metric=@core.Dot)
  // Add vectors
  for i in 1..<=20 {
    db.add(
      @core.VectorId::from_int(i),
      [
        (i % 3).to_double(),
        ((i + 1) % 3).to_double(),
        ((i + 2) % 3).to_double(),
      ],
      @core.empty_attrs(),
    )
  }
  inspect(db.size(), content="20")
  // Remove first 5 vectors (lighter tombstoning for better recall)
  for i in 1..<=5 {
    let removed = db.remove(@core.VectorId::from_int(i))
    inspect(removed, content="true")
  }
  // Store size unchanged (tombstones still count), but search excludes them
  inspect(db.size(), content="20")
  // Search should not return removed IDs
  let results = db.search([1.0, 0.0, 0.0], 20, None)
  // With 25% tombstones, expect good recall (at least 10 out of 15)
  inspect(results.length() >= 10, content="true")
  for hit in results {
    let id = hit.id.to_int64()
    // No tombstoned IDs should be returned
    inspect(id > 5L, content="true")
  }
}

///|
/// Test: High-dimensional vectors
test "api/high_dimensional" {
  let dim = 128
  let db = @vcdb.VectorDB::new({
    dim,
    metric: @core.Cosine,
    capacity: 100,
    strategy: @core.Bruteforce,
  })
  // Add vectors
  for i in 1..<=50 {
    let v : Array[Double] = Array::make(dim, 0.0)
    // Set some dimensions based on ID
    v[i % dim] = 1.0
    v[i * 7 % dim] = 0.5
    db.add(@core.VectorId::from_int(i), v, @core.empty_attrs())
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
  inspect(results[0].id.to_int64(), content="1")
}

///|
/// Test: Complex must/must_not/should expressions
test "api/complex_expr_search" {
  let db = @vcdb.VectorDB::with_dim(2)
  let attr_index = @attr.BasicAttrIndex::new()
  // Setup data
  for i in 1..<=20 {
    let attrs = @core.empty_attrs()
    attrs.set("active", @core.Bool(i % 2 == 0))
    attrs.set("score", @core.Int(i.to_int64() * 5L))
    attrs.set("category", @core.String(if i <= 10 { "X" } else { "Y" }))
    let id = @core.VectorId::from_int(i)
    db.add(id, [i.to_double() / 20.0, 1.0 - i.to_double() / 20.0], attrs)
    attr_index.set_attrs(id, attrs)
  }
  // Must: category=X AND active=true
  let expr = @filter.FilterExpr::must([
    @filter.FilterExpr::match_("category", @core.String("X")),
    @filter.FilterExpr::match_("active", @core.Bool(true)),
  ])
  let results = db.search_with_expr(
    [1.0, 0.0],
    10,
    Some(expr),
    Some(attr_index),
    @filter.PostFilter,
  )
  // IDs 2,4,6,8,10 (even numbers in 1-10)
  inspect(results.length(), content="5")
}

///|
/// Test: Unified CRUD operations
test "api/unified_crud" {
  let db = @vcdb.VectorDB::with_dim(3)
  // set single
  db.add(
    @core.VectorId::from_int(1),
    [1.0, 0.0, 0.0],
    {
      let a = @core.empty_attrs()
      a.set("tag", @core.String("a"))
      a
    },
  )
  inspect(db.has(@core.VectorId::from_int(1)), content="true")
  let r1 = db.get(@core.VectorId::from_int(1))
  match r1 {
    Some(r) =>
      match r.attrs.get("tag") {
        Some(@core.String(s)) => inspect(s, content="a")
        _ => inspect(false, content="true")
      }
    None => inspect(false, content="true")
  }
  // upsert update
  let _ = db.upsert(
    @core.VectorId::from_int(1),
    [1.0, 0.0, 0.0],
    {
      let a = @core.empty_attrs()
      a.set("tag", @core.String("aa"))
      a
    },
  )
  let r2 = db.get(@core.VectorId::from_int(1))
  match r2 {
    Some(r) =>
      match r.attrs.get("tag") {
        Some(@core.String(s)) => inspect(s, content="aa")
        _ => inspect(false, content="true")
      }
    None => inspect(false, content="true")
  }
  // add multiple
  db.add(
    @core.VectorId::from_int(2),
    [0.0, 1.0, 0.0],
    {
      let a = @core.empty_attrs()
      a.set("tag", @core.String("b"))
      a
    },
  )
  db.add(@core.VectorId::from_int(3), [0.0, 0.0, 1.0], @core.empty_attrs())
  inspect(db.size(), content="3")
  // delete
  let deleted = db.remove(@core.VectorId::from_int(3))
  inspect(deleted, content="true")
  inspect(db.has(@core.VectorId::from_int(3)), content="false")
}
