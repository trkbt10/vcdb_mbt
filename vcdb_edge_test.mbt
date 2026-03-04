// Comprehensive Edge Case Tests
// Tests boundary conditions, extreme values, and error scenarios

// =============================================================================
// Section 1: Numeric Boundary Tests
// =============================================================================

///|
/// Test: Int64 max/min values in attributes
test "edge/numeric/int64_bounds" {
  let db = @vcdb.VectorDB::with_dim(2)

  let attrs = @core.empty_attrs()
  attrs.set("max", @core.Int(9223372036854775807L)) // Int64.max
  attrs.set("min", @core.Int(-9223372036854775808L)) // Int64.min
  attrs.set("zero", @core.Int(0L))

  db.add(@core.VectorId::from_int(1), [1.0, 0.0], attrs)

  let record = db.get(@core.VectorId::from_int(1)).unwrap()
  match record.attrs.get("max") {
    Some(@core.Int(n)) => inspect(n, content="9223372036854775807")
    _ => inspect(false, content="true")
  }
  match record.attrs.get("min") {
    Some(@core.Int(n)) => inspect(n, content="-9223372036854775808")
    _ => inspect(false, content="true")
  }
}

///|
/// Test: Float64 special values
test "edge/numeric/float_special" {
  let db = @vcdb.VectorDB::new({
      dim: 2,
      metric: @core.Dot,
      capacity: 10,
      strategy: @core.Bruteforce,
    }, // Don't normalize to preserve values
  )

  let attrs = @core.empty_attrs()
  attrs.set("tiny", @core.Float(0.00000000001))
  attrs.set("huge", @core.Float(1000000000000.0))
  attrs.set("neg_tiny", @core.Float(-0.00000000001))

  db.add(@core.VectorId::from_int(1), [1.0, 0.0], attrs)

  let record = db.get(@core.VectorId::from_int(1)).unwrap()
  match record.attrs.get("tiny") {
    Some(@core.Float(f)) => inspect(f > 0.0 && f < 0.001, content="true")
    _ => inspect(false, content="true")
  }
  match record.attrs.get("huge") {
    Some(@core.Float(f)) => inspect(f > 999999999999.0, content="true")
    _ => inspect(false, content="true")
  }
}

///|
/// Test: VectorId boundary values
test "edge/numeric/vectorid_bounds" {
  let db = @vcdb.VectorDB::with_dim(2)

  let max_id = @core.VectorId::from_int64(9223372036854775807L)
  let zero_id = @core.VectorId::from_int(0)
  let neg_id = @core.VectorId::from_int64(-1L)

  db.add(max_id, [1.0, 0.0], @core.empty_attrs())
  db.add(zero_id, [0.0, 1.0], @core.empty_attrs())
  db.add(neg_id, [0.5, 0.5], @core.empty_attrs())

  inspect(db.has(max_id), content="true")
  inspect(db.has(zero_id), content="true")
  inspect(db.has(neg_id), content="true")
  inspect(db.size(), content="3")
}

// =============================================================================
// Section 2: Vector Dimension Edge Cases
// =============================================================================

///|
/// Test: Single dimension vector (dim=1)
test "edge/dim/single_dimension" {
  let db = @vcdb.VectorDB::new({
    dim: 1,
    metric: @core.Dot,
    capacity: 10,
    strategy: @core.Bruteforce,
  })

  db.add(@core.VectorId::from_int(1), [5.0], @core.empty_attrs())
  db.add(@core.VectorId::from_int(2), [3.0], @core.empty_attrs())
  db.add(@core.VectorId::from_int(3), [7.0], @core.empty_attrs())

  let results = db.search([1.0], 3, None)

  // Dot product with [1.0]: 7 > 5 > 3
  inspect(results[0].id.to_int64(), content="3")
  inspect(results[1].id.to_int64(), content="1")
  inspect(results[2].id.to_int64(), content="2")
}

///|
/// Test: High dimension vector (dim=512)
test "edge/dim/high_dimension" {
  let dim = 512
  let db = @vcdb.VectorDB::new({
    dim,
    metric: @core.Cosine,
    capacity: 20,
    strategy: @core.Bruteforce,
  })

  // Create vectors with different "hot" positions
  for i in 0..<10 {
    let v : Array[Double] = Array::make(dim, 0.0)
    v[i * 50] = 1.0 // Single hot at different positions
    db.add(@core.VectorId::from_int(i), v, @core.empty_attrs())
  }

  inspect(db.size(), content="10")

  // Query for position 100
  let query : Array[Double] = Array::make(dim, 0.0)
  query[100] = 1.0

  let results = db.search(query, 1, None)
  inspect(results[0].id.to_int64(), content="2") // id=2 has hot at 100
}

// =============================================================================
// Section 3: Same Score / Tie Breaking
// =============================================================================

///|
/// Test: Multiple vectors with identical scores
test "edge/score/identical_scores" {
  let db = @vcdb.VectorDB::new({
    dim: 2,
    metric: @core.Dot,
    capacity: 10,
    strategy: @core.Bruteforce,
  })

  // All have dot product = 1.0 with [1, 0]
  db.add(@core.VectorId::from_int(1), [1.0, 0.0], @core.empty_attrs())
  db.add(@core.VectorId::from_int(2), [1.0, 0.0], @core.empty_attrs())
  db.add(@core.VectorId::from_int(3), [1.0, 0.0], @core.empty_attrs())

  let results = db.search([1.0, 0.0], 3, None)

  // All should have same score
  inspect(results[0].score, content="1")
  inspect(results[1].score, content="1")
  inspect(results[2].score, content="1")

  // All 3 IDs should be present
  let ids : Array[Int64] = results
    .iter()
    .map(fn(h) { h.id.to_int64() })
    .collect()
  inspect(ids.length(), content="3")
}

///|
/// Test: Very close but distinct scores
test "edge/score/close_scores" {
  let db = @vcdb.VectorDB::new({
    dim: 1,
    metric: @core.Dot,
    capacity: 10,
    strategy: @core.Bruteforce,
  })

  db.add(@core.VectorId::from_int(1), [1.0], @core.empty_attrs())
  db.add(@core.VectorId::from_int(2), [1.0000001], @core.empty_attrs())
  db.add(@core.VectorId::from_int(3), [1.0000002], @core.empty_attrs())

  let results = db.search([1.0], 3, None)

  // Should be ordered correctly despite tiny differences
  inspect(results[0].id.to_int64(), content="3")
  inspect(results[1].id.to_int64(), content="2")
  inspect(results[2].id.to_int64(), content="1")
}

// =============================================================================
// Section 4: Zero Vector and Edge Vectors
// =============================================================================

///|
/// Test: All-zero vector with L2 metric
test "edge/vector/zero_vector_l2" {
  let db = @vcdb.VectorDB::new({
    dim: 3,
    metric: @core.L2,
    capacity: 10,
    strategy: @core.Bruteforce,
  })

  db.add(@core.VectorId::from_int(1), [0.0, 0.0, 0.0], @core.empty_attrs())
  db.add(@core.VectorId::from_int(2), [1.0, 0.0, 0.0], @core.empty_attrs())

  // Query with zero vector
  let results = db.search([0.0, 0.0, 0.0], 2, None)

  // Zero to zero distance = 0 (score = 0)
  inspect(results[0].id.to_int64(), content="1")
  inspect(results[0].score, content="0")
}

///|
/// Test: All-zero vector with Cosine (normalized to itself)
test "edge/vector/zero_vector_cosine" {
  let db = @vcdb.VectorDB::new({
    dim: 2,
    metric: @core.Cosine,
    capacity: 10,
    strategy: @core.Bruteforce,
  })

  // Note: Zero vector can't be normalized, implementation should handle gracefully
  db.add(@core.VectorId::from_int(1), [0.0, 0.0], @core.empty_attrs())
  db.add(@core.VectorId::from_int(2), [1.0, 0.0], @core.empty_attrs())

  // Should not crash
  let results = db.search([1.0, 0.0], 2, None)
  inspect(results.length(), content="2")
}

///|
/// Test: All same value vector
test "edge/vector/uniform_values" {
  let db = @vcdb.VectorDB::new({
    dim: 4,
    metric: @core.Cosine,
    capacity: 10,
    strategy: @core.Bruteforce,
  })

  // All components same value
  db.add(@core.VectorId::from_int(1), [1.0, 1.0, 1.0, 1.0], @core.empty_attrs())
  db.add(@core.VectorId::from_int(2), [2.0, 2.0, 2.0, 2.0], @core.empty_attrs())

  // With Cosine, both should have same similarity to [1,1,1,1]
  let results = db.search([1.0, 1.0, 1.0, 1.0], 2, None)
  inspect(results[0].score, content="1")
  inspect(results[1].score, content="1")
}

// =============================================================================
// Section 5: HNSW Edge Cases
// =============================================================================

///|
/// Test: HNSW with single node
test "edge/hnsw/single_node" {
  let db = @vcdb.VectorDB::with_hnsw(3, metric=@core.Dot)

  db.add(@core.VectorId::from_int(1), [1.0, 0.0, 0.0], @core.empty_attrs())

  let results = db.search([1.0, 0.0, 0.0], 10, None)
  inspect(results.length(), content="1")
  inspect(results[0].id.to_int64(), content="1")
}

///|
/// Test: HNSW after removing most nodes (high tombstone ratio)
test "edge/hnsw/high_tombstone_ratio" {
  let db = @vcdb.VectorDB::with_hnsw(2, metric=@core.Dot)

  // Add 20 nodes
  for i in 1..<=20 {
    db.add(
      @core.VectorId::from_int(i),
      [i.to_double(), 0.0],
      @core.empty_attrs(),
    )
  }

  // Remove 18 of them (90% tombstone)
  for i in 1..<=18 {
    let _ = db.remove(@core.VectorId::from_int(i))
  }

  // Search should still work and only return non-tombstoned
  let results = db.search([20.0, 0.0], 10, None)

  // Should find at most 2 (ids 19 and 20)
  inspect(results.length() <= 2, content="true")

  for hit in results {
    let id = hit.id.to_int64()
    inspect(id >= 19L, content="true")
  }
}

///|
/// Test: HNSW with minimal params
test "edge/hnsw/minimal_params" {
  let params : @core.HNSWParams = {
    m: 2, // Minimum allowed
    ef_construction: 1, // Minimum
    ef_search: 1, // Minimum
    level_mult: 1.0,
    seed: 42UL,
    allow_replace_deleted: false,
  }
  let db = @vcdb.VectorDB::new({
    dim: 2,
    metric: @core.Dot,
    capacity: 20,
    strategy: @core.HNSW(params),
  })

  for i in 1..<=10 {
    db.add(
      @core.VectorId::from_int(i),
      [i.to_double(), 0.0],
      @core.empty_attrs(),
    )
  }

  // Should still work even with minimal params
  let results = db.search([10.0, 0.0], 3, None)
  inspect(results.length() > 0, content="true")
}

// =============================================================================
// Section 6: IVF Edge Cases
// =============================================================================

///|
/// Test: IVF with nprobe > nlist
test "edge/ivf/nprobe_exceeds_nlist" {
  let params : @core.IVFParams = { nlist: 4, nprobe: 100 } // nprobe >> nlist
  let db = @vcdb.VectorDB::new({
    dim: 2,
    metric: @core.Dot,
    capacity: 20,
    strategy: @core.IVF(params),
  })

  for i in 1..<=10 {
    db.add(
      @core.VectorId::from_int(i),
      [i.to_double(), 0.0],
      @core.empty_attrs(),
    )
  }

  db.train(iterations=5)

  // Should handle gracefully
  let results = db.search([5.0, 0.0], 5, None)
  inspect(results.length() > 0, content="true")
}

///|
/// Test: IVF with minimal nlist
test "edge/ivf/minimal_nlist" {
  let params : @core.IVFParams = { nlist: 1, nprobe: 1 }
  let db = @vcdb.VectorDB::new({
    dim: 2,
    metric: @core.Dot,
    capacity: 20,
    strategy: @core.IVF(params),
  })

  for i in 1..<=10 {
    db.add(
      @core.VectorId::from_int(i),
      [i.to_double(), 0.0],
      @core.empty_attrs(),
    )
  }

  db.train(iterations=3)

  // Single cluster should work
  let results = db.search([5.0, 0.0], 5, None)
  inspect(results.length(), content="5")
}

// =============================================================================
// Section 7: Filter Edge Cases
// =============================================================================

///|
/// Test: Filter that matches nothing
test "edge/filter/none_match" {
  let db = @vcdb.VectorDB::with_dim(2)

  for i in 1..<=10 {
    let attrs = @core.empty_attrs()
    attrs.set("type", @core.String("normal"))
    db.add(@core.VectorId::from_int(i), [i.to_double(), 0.0], attrs)
  }

  let filter = fn(_id : @core.VectorId, attrs : @core.Attrs) -> Bool {
    match attrs.get("type") {
      Some(@core.String(s)) => s == "special" // None have this
      _ => false
    }
  }

  let results = db.search([5.0, 0.0], 10, Some(filter))
  inspect(results.length(), content="0")
}

///|
/// Test: Filter that matches everything
test "edge/filter/all_match" {
  let db = @vcdb.VectorDB::with_dim(2)

  for i in 1..<=10 {
    let attrs = @core.empty_attrs()
    attrs.set("exists", @core.Bool(true))
    db.add(@core.VectorId::from_int(i), [i.to_double(), 0.0], attrs)
  }

  let filter = fn(_id : @core.VectorId, attrs : @core.Attrs) -> Bool {
    match attrs.get("exists") {
      Some(@core.Bool(b)) => b
      _ => false
    }
  }

  let results = db.search([5.0, 0.0], 10, Some(filter))
  inspect(results.length(), content="10")
}

///|
/// Test: Empty Must array (should match all)
test "edge/filter/empty_must" {
  let attrs = @core.empty_attrs()
  attrs.set("val", @core.Int(1L))

  let expr = @filter.FilterExpr::must([]) // Empty array
  let filter = @filter.compile_filter(expr)

  // Empty Must should be vacuously true
  inspect(filter(@core.VectorId::from_int(1), attrs), content="true")
}

///|
/// Test: Empty MustNot array (should match all)
test "edge/filter/empty_must_not" {
  let attrs = @core.empty_attrs()
  attrs.set("val", @core.Int(1L))

  let expr = @filter.FilterExpr::must_not([]) // Empty array
  let filter = @filter.compile_filter(expr)

  // Empty MustNot should be vacuously true
  inspect(filter(@core.VectorId::from_int(1), attrs), content="true")
}

///|
/// Test: Should with min=0 (always true)
test "edge/filter/should_min_zero" {
  let attrs = @core.empty_attrs()
  attrs.set("val", @core.Int(1L))

  let expr = @filter.FilterExpr::should(
    [@filter.FilterExpr::match_("nonexistent", @core.Bool(true))],
    min=0,
  )

  let filter = @filter.compile_filter(expr)

  // min=0 means we need 0 matches, so always true
  inspect(filter(@core.VectorId::from_int(1), attrs), content="true")
}

///|
/// Test: Should with min > array length (always false)
test "edge/filter/should_min_exceeds" {
  let attrs = @core.empty_attrs()
  attrs.set("a", @core.Bool(true))
  attrs.set("b", @core.Bool(true))

  let expr = @filter.FilterExpr::should(
    [
      @filter.FilterExpr::match_("a", @core.Bool(true)),
      @filter.FilterExpr::match_("b", @core.Bool(true)),
    ],
    min=5,
  ) // Need 5, but only 2 clauses

  let filter = @filter.compile_filter(expr)

  // Can never satisfy min=5 with 2 clauses
  inspect(filter(@core.VectorId::from_int(1), attrs), content="false")
}

///|
/// Test: Deeply nested filter (10 levels)
test "edge/filter/deeply_nested" {
  let attrs = @core.empty_attrs()
  attrs.set("val", @core.Int(42L))

  // Build nested Must: Must([Must([Must([...match...])])])
  let mut expr = @filter.FilterExpr::match_("val", @core.Int(42L))
  for _ in 0..<10 {
    expr = @filter.FilterExpr::must([expr])
  }

  let filter = @filter.compile_filter(expr)
  inspect(filter(@core.VectorId::from_int(1), attrs), content="true")
}

// =============================================================================
// Section 8: String Edge Cases
// =============================================================================

///|
/// Test: Empty string key and value
test "edge/string/empty" {
  let db = @vcdb.VectorDB::with_dim(2)

  let attrs = @core.empty_attrs()
  attrs.set("", @core.String("")) // Both empty

  db.add(@core.VectorId::from_int(1), [1.0, 0.0], attrs)

  let record = db.get(@core.VectorId::from_int(1)).unwrap()
  match record.attrs.get("") {
    Some(@core.String(s)) => inspect(s, content="")
    _ => inspect(false, content="true")
  }
}

///|
/// Test: Very long key name
test "edge/string/long_key" {
  let db = @vcdb.VectorDB::with_dim(2)

  // 1000 character key
  let mut long_key = ""
  for _ in 0..<100 {
    long_key = long_key + "0123456789"
  }

  let attrs = @core.empty_attrs()
  attrs.set(long_key, @core.String("value"))

  db.add(@core.VectorId::from_int(1), [1.0, 0.0], attrs)

  let record = db.get(@core.VectorId::from_int(1)).unwrap()
  match record.attrs.get(long_key) {
    Some(@core.String(s)) => inspect(s, content="value")
    _ => inspect(false, content="true")
  }
}

///|
/// Test: Special characters in strings
test "edge/string/special_chars" {
  let db = @vcdb.VectorDB::with_dim(2)

  let attrs = @core.empty_attrs()
  attrs.set("newline", @core.String("line1\nline2"))
  attrs.set("tab", @core.String("col1\tcol2"))
  attrs.set("null_char", @core.String("before\u0000after"))
  attrs.set("backslash", @core.String("path\\to\\file"))
  attrs.set("quotes", @core.String("say \"hello\""))

  db.add(@core.VectorId::from_int(1), [1.0, 0.0], attrs)

  let record = db.get(@core.VectorId::from_int(1)).unwrap()

  match record.attrs.get("newline") {
    Some(@core.String(s)) => inspect(s.contains("\n"), content="true")
    _ => inspect(false, content="true")
  }
  match record.attrs.get("backslash") {
    Some(@core.String(s)) => inspect(s.contains("\\"), content="true")
    _ => inspect(false, content="true")
  }
}

// =============================================================================
// Section 9: Serialization Edge Cases
// =============================================================================

///|
/// Test: Serialize empty database
test "edge/serialize/empty_db" {
  let db = @vcdb.VectorDB::with_dim(3)

  let bytes = db.serialize()
  inspect(bytes.length() > 0, content="true")

  let db2 = @vcdb.VectorDB::deserialize(bytes)
  inspect(db2.size(), content="0")
  inspect(db2.dim(), content="3")
}

///|
/// Test: Serialize single vector
test "edge/serialize/single_vector" {
  let db = @vcdb.VectorDB::with_dim(2)

  let attrs = @core.empty_attrs()
  attrs.set("only", @core.Bool(true))

  db.add(@core.VectorId::from_int(42), [1.0, 0.0], attrs)

  let bytes = db.serialize()
  let db2 = @vcdb.VectorDB::deserialize(bytes)

  inspect(db2.size(), content="1")
  inspect(db2.has(@core.VectorId::from_int(42)), content="true")

  let record = db2.get(@core.VectorId::from_int(42)).unwrap()
  match record.attrs.get("only") {
    Some(@core.Bool(b)) => inspect(b, content="true")
    _ => inspect(false, content="true")
  }
}

///|
/// Test: Serialize with many attributes per vector
test "edge/serialize/many_attrs" {
  let db = @vcdb.VectorDB::with_dim(2)

  let attrs = @core.empty_attrs()
  for i in 0..<100 {
    attrs.set("attr_\{i}", @core.Int(i.to_int64()))
  }

  db.add(@core.VectorId::from_int(1), [1.0, 0.0], attrs)

  let bytes = db.serialize()
  let db2 = @vcdb.VectorDB::deserialize(bytes)

  let record = db2.get(@core.VectorId::from_int(1)).unwrap()
  inspect(record.attrs.size(), content="100")

  match record.attrs.get("attr_50") {
    Some(@core.Int(n)) => inspect(n, content="50")
    _ => inspect(false, content="true")
  }
}

///|
/// Test: Serialize HNSW with tombstones
test "edge/serialize/hnsw_tombstones" {
  let db = @vcdb.VectorDB::with_hnsw(2, metric=@core.Dot)

  for i in 1..<=10 {
    db.add(
      @core.VectorId::from_int(i),
      [i.to_double(), 0.0],
      @core.empty_attrs(),
    )
  }

  // Remove some
  let _ = db.remove(@core.VectorId::from_int(3))
  let _ = db.remove(@core.VectorId::from_int(7))

  let bytes = db.serialize()
  let db2 = @vcdb.VectorDB::deserialize(bytes)

  // Tombstoned IDs should still be tombstoned
  inspect(db2.has(@core.VectorId::from_int(3)), content="false")
  inspect(db2.has(@core.VectorId::from_int(7)), content="false")
  inspect(db2.has(@core.VectorId::from_int(5)), content="true")
}

// =============================================================================
// Section 10: Capacity and Growth Edge Cases
// =============================================================================

///|
/// Test: Exceed initial capacity
test "edge/capacity/exceed_initial" {
  let db = @vcdb.VectorDB::new({
      dim: 2,
      metric: @core.Dot,
      capacity: 5,
      strategy: @core.Bruteforce,
    }, // Small initial capacity
  )

  // Add more than capacity
  for i in 1..<=20 {
    db.add(
      @core.VectorId::from_int(i),
      [i.to_double(), 0.0],
      @core.empty_attrs(),
    )
  }

  inspect(db.size(), content="20")

  // Search should still work
  let results = db.search([15.0, 0.0], 5, None)
  inspect(results.length(), content="5")
}

///|
/// Test: Capacity=1
test "edge/capacity/minimal" {
  let db = @vcdb.VectorDB::new({
    dim: 2,
    metric: @core.Dot,
    capacity: 1,
    strategy: @core.Bruteforce,
  })

  db.add(@core.VectorId::from_int(1), [1.0, 0.0], @core.empty_attrs())
  db.add(@core.VectorId::from_int(2), [2.0, 0.0], @core.empty_attrs())

  inspect(db.size(), content="2")
}

// =============================================================================
// Section 11: k Parameter Edge Cases
// =============================================================================

///|
/// Test: k=0 returns empty
test "edge/k/zero" {
  let db = @vcdb.VectorDB::with_dim(2)
  db.add(@core.VectorId::from_int(1), [1.0, 0.0], @core.empty_attrs())

  let results = db.search([1.0, 0.0], 0, None)
  inspect(results.length(), content="0")
}

///|
/// Test: k=1 returns exactly one
test "edge/k/one" {
  let db = @vcdb.VectorDB::with_dim(2)

  for i in 1..<=100 {
    db.add(
      @core.VectorId::from_int(i),
      [i.to_double(), 0.0],
      @core.empty_attrs(),
    )
  }

  let results = db.search([50.0, 0.0], 1, None)
  inspect(results.length(), content="1")
}

///|
/// Test: k much larger than database size
test "edge/k/exceeds_size" {
  let db = @vcdb.VectorDB::with_dim(2)

  for i in 1..<=5 {
    db.add(
      @core.VectorId::from_int(i),
      [i.to_double(), 0.0],
      @core.empty_attrs(),
    )
  }

  let results = db.search([3.0, 0.0], 1000, None)
  inspect(results.length(), content="5") // Can only return what exists
}

// =============================================================================
// Section 12: NumericRange Edge Cases
// =============================================================================

///|
/// Test: Range with same lower and upper bound
test "edge/range/single_point" {
  let range = @core.NumericRange::between(5.0, 5.0)

  inspect(range.matches(5.0), content="true")
  inspect(range.matches(4.99), content="false")
  inspect(range.matches(5.01), content="false")
}

///|
/// Test: Range with inverted bounds (lower > upper)
test "edge/range/inverted_bounds" {
  // This creates a range where gte=10 and lte=5, which can never match
  let range = @core.NumericRange::between(10.0, 5.0)

  // Nothing should match when lower > upper
  inspect(range.matches(5.0), content="false")
  inspect(range.matches(7.0), content="false")
  inspect(range.matches(10.0), content="false")
}

///|
/// Test: Range with negative values
test "edge/range/negative_range" {
  let range = @core.NumericRange::between(-100.0, -50.0)

  inspect(range.matches(-75.0), content="true")
  inspect(range.matches(-100.0), content="true")
  inspect(range.matches(-50.0), content="true")
  inspect(range.matches(-49.0), content="false")
  inspect(range.matches(-101.0), content="false")
  inspect(range.matches(0.0), content="false")
}

// =============================================================================
// Section 13: Concurrent-like Operations
// =============================================================================

///|
/// Test: Rapid add/remove/search cycle
test "edge/ops/rapid_cycle" {
  let db = @vcdb.VectorDB::with_dim(2)

  for cycle in 0..<10 {
    // Add 10
    for i in 0..<10 {
      let id = cycle * 10 + i
      db.add(
        @core.VectorId::from_int(id),
        [id.to_double(), 0.0],
        @core.empty_attrs(),
      )
    }

    // Search
    let _ = db.search([50.0, 0.0], 5, None)

    // Remove 5
    for i in 0..<5 {
      let id = cycle * 10 + i
      let _ = db.remove(@core.VectorId::from_int(id))
    }
  }

  // Should have 50 remaining (10 cycles * 5 kept per cycle)
  inspect(db.size(), content="50")
}

///|
/// Test: Interleaved upsert and search
test "edge/ops/upsert_search_interleave" {
  let db = @vcdb.VectorDB::with_dim(2)

  for i in 1..<=20 {
    // Upsert
    let _ = db.upsert(
      @core.VectorId::from_int(i % 5 + 1), // Only 5 unique IDs
      [i.to_double(), 0.0],
      @core.empty_attrs(),
    )

    // Search after each upsert
    let results = db.search([i.to_double(), 0.0], 3, None)
    inspect(results.length() > 0, content="true")
  }

  // Should only have 5 vectors
  inspect(db.size(), content="5")
}

// =============================================================================
// Section 14: Attribute Index Edge Cases with VectorDB
// =============================================================================

///|
/// Test: PreFilter with empty candidate set
test "edge/prefilter/empty_candidates" {
  let db = @vcdb.VectorDB::with_dim(2)
  let index = @attr.BasicAttrIndex::new()

  for i in 1..<=10 {
    let attrs = @core.empty_attrs()
    attrs.set("type", @core.String("A"))

    let id = @core.VectorId::from_int(i)
    db.add(id, [i.to_double(), 0.0], attrs)
    index.set_attrs(id, attrs)
  }

  // Filter for non-existent type
  let expr = @filter.FilterExpr::match_("type", @core.String("Z"))
  let results = db.search_with_expr(
    [5.0, 0.0],
    10,
    Some(expr),
    Some(index),
    @filter.PreFilter,
  )

  inspect(results.length(), content="0")
}

///|
/// Test: Index and DB out of sync
test "edge/index/desync" {
  let db = @vcdb.VectorDB::with_dim(2)
  let index = @attr.BasicAttrIndex::new()

  // Add to both
  let attrs = @core.empty_attrs()
  attrs.set("key", @core.String("val"))

  let id = @core.VectorId::from_int(1)
  db.add(id, [1.0, 0.0], attrs)
  index.set_attrs(id, attrs)

  // Remove from DB but not index
  let _ = db.remove(id)

  // Index still has it
  inspect(index.eq("key", @core.String("val")).length(), content="1")

  // But search with prefilter should return empty (vector doesn't exist)
  let expr = @filter.FilterExpr::match_("key", @core.String("val"))
  let results = db.search_with_expr(
    [1.0, 0.0],
    10,
    Some(expr),
    Some(index),
    @filter.PreFilter,
  )

  inspect(results.length(), content="0")
}
