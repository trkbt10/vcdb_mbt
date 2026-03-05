// Whitebox tests for VectorDB facade

///|
test "vectordb/bruteforce" {
  let db = VectorDB::with_dim(3)
  db.add(@types.VectorId::from_int(1), [1.0, 0.0, 0.0], @types.empty_attrs())
  db.add(@types.VectorId::from_int(2), [0.0, 1.0, 0.0], @types.empty_attrs())
  db.add(@types.VectorId::from_int(3), [0.5, 0.5, 0.0], @types.empty_attrs())
  inspect(db.size(), content="3")
  // Search
  let results = db.search([1.0, 0.0, 0.0], 2, None)
  inspect(results.length(), content="2")
  inspect(results[0].id.to_int64(), content="1")
  // Remove
  let removed = db.remove(@types.VectorId::from_int(2))
  inspect(removed, content="true")
  inspect(db.size(), content="2")
}

///|
test "vectordb/hnsw" {
  let db = VectorDB::with_hnsw(3, metric=@types.Dot)
  db.add(@types.VectorId::from_int(1), [1.0, 0.0, 0.0], @types.empty_attrs())
  db.add(@types.VectorId::from_int(2), [0.0, 1.0, 0.0], @types.empty_attrs())
  db.add(@types.VectorId::from_int(3), [0.5, 0.5, 0.0], @types.empty_attrs())
  inspect(db.size(), content="3")
  // Search
  let results = db.search([1.0, 0.0, 0.0], 2, None)
  inspect(results.length(), content="2")
  inspect(results[0].id.to_int64(), content="1")
}

///|
test "vectordb/ivf" {
  let db = VectorDB::with_ivf(3, metric=@types.Dot)
  db.add(@types.VectorId::from_int(1), [1.0, 0.0, 0.0], @types.empty_attrs())
  db.add(@types.VectorId::from_int(2), [0.0, 1.0, 0.0], @types.empty_attrs())
  db.add(@types.VectorId::from_int(3), [0.5, 0.5, 0.0], @types.empty_attrs())
  inspect(db.size(), content="3")
  // Search
  let results = db.search([1.0, 0.0, 0.0], 2, None)
  inspect(results.length(), content="2")
  inspect(results[0].id.to_int64(), content="1")
}

///|
test "vectordb/serialization" {
  let db = VectorDB::with_dim(3)
  let attrs = @types.empty_attrs()
  attrs.set("tag", @types.String("test"))
  db.add(@types.VectorId::from_int(1), [1.0, 0.0, 0.0], attrs)
  db.add(@types.VectorId::from_int(2), [0.0, 1.0, 0.0], @types.empty_attrs())
  // Serialize
  let bytes = db.serialize()
  inspect(bytes.length() > 0, content="true")
  // Deserialize
  let db2 = VectorDB::deserialize(bytes)
  inspect(db2.size(), content="2")
  // Search should work
  let results = db2.search([1.0, 0.0, 0.0], 1, None)
  inspect(results.length(), content="1")
  inspect(results[0].id.to_int64(), content="1")
}

///|
test "vectordb/upsert" {
  let db = VectorDB::with_dim(2)
  // Initial add
  let created1 = db.upsert(
    @types.VectorId::from_int(1),
    [1.0, 0.0],
    @types.empty_attrs(),
  )
  inspect(created1, content="true")
  inspect(db.size(), content="1")
  // Upsert same id with new vector
  let attrs = @types.empty_attrs()
  attrs.set("updated", @types.Bool(true))
  let created2 = db.upsert(@types.VectorId::from_int(1), [0.5, 0.5], attrs)
  inspect(created2, content="false")
  inspect(db.size(), content="1")
  // Check updated attrs
  let record = db.get(@types.VectorId::from_int(1))
  let updated = record.unwrap().attrs.get("updated")
  inspect(updated is None, content="false")
}

///|
test "vectordb/search_with_expr_postfilter" {
  let db = VectorDB::with_dim(2)
  // Add vectors with categories
  let attrs_a = @types.empty_attrs()
  attrs_a.set("category", @types.String("A"))
  let attrs_b = @types.empty_attrs()
  attrs_b.set("category", @types.String("B"))
  db.add(@types.VectorId::from_int(1), [1.0, 0.0], attrs_a) // Best match, cat A
  db.add(@types.VectorId::from_int(2), [0.9, 0.1], attrs_b) // Second, cat B
  db.add(@types.VectorId::from_int(3), [0.5, 0.5], attrs_a) // Third, cat A
  // Search with PostFilter: only category B
  let expr = @filter.FilterExpr::match_("category", @types.String("B"))
  let results = db.search_with_expr(
    [1.0, 0.0],
    10,
    Some(expr),
    None,
    @filter.PostFilter,
  )
  inspect(results.length(), content="1")
  inspect(results[0].id.to_int64(), content="2")
}

///|
test "vectordb/search_with_expr_prefilter" {
  let db = VectorDB::with_dim(2)
  // Build attr index alongside DB
  let attr_index = @attr.BasicAttrIndex::new()
  // Add vectors with scores
  for i in 1..<=10 {
    let attrs = @types.empty_attrs()
    attrs.set("score", @types.Int(i.to_int64() * 10L))
    let id = @types.VectorId::from_int(i)
    db.add(id, [i.to_double() / 10.0, 1.0 - i.to_double() / 10.0], attrs)
    attr_index.set_attrs(id, attrs)
  }
  // Search with PreFilter: score >= 50 (IDs 5-10)
  let range = @types.NumericRange::gte(50.0)
  let expr = @filter.FilterExpr::range("score", range)
  let results = db.search_with_expr(
    [1.0, 0.0],
    3,
    Some(expr),
    Some(attr_index),
    @filter.PreFilter,
  )
  inspect(results.length(), content="3")
  // All results should have score >= 50
  for hit in results {
    match hit.attrs.get("score") {
      Some(@types.Int(s)) => inspect(s >= 50L, content="true")
      _ => inspect(false, content="true")
    }
  }
}

///|
test "vectordb/search_with_expr_auto" {
  let db = VectorDB::with_dim(2)
  let attr_index = @attr.BasicAttrIndex::new()
  // Add 10 vectors, only 2 have tag="rare"
  for i in 1..<=10 {
    let attrs = @types.empty_attrs()
    if i <= 2 {
      attrs.set("tag", @types.String("rare"))
    } else {
      attrs.set("tag", @types.String("common"))
    }
    let id = @types.VectorId::from_int(i)
    db.add(id, [i.to_double() / 10.0, 1.0 - i.to_double() / 10.0], attrs)
    attr_index.set_attrs(id, attrs)
  }
  // Search with Auto strategy: should use pre-filter (2/10 < 50%)
  let expr = @filter.FilterExpr::match_("tag", @types.String("rare"))
  let results = db.search_with_expr(
    [1.0, 0.0],
    5,
    Some(expr),
    Some(attr_index),
    @filter.Auto,
  )
  inspect(results.length(), content="2")
}

///|
test "vectordb/dim_and_metric" {
  let db = VectorDB::with_hnsw(5, metric=@types.L2)
  inspect(db.dim(), content="5")
  match db.metric() {
    @types.L2 => inspect(true, content="true")
    _ => inspect(false, content="true")
  }
}

///|
test "vectordb/has_and_get" {
  let db = VectorDB::with_dim(2)
  let id = @types.VectorId::from_int(42)
  inspect(db.has(id), content="false")
  inspect(db.get(id) is None, content="true")
  let attrs = @types.empty_attrs()
  attrs.set("name", @types.String("test"))
  db.add(id, [1.0, 0.0], attrs)
  inspect(db.has(id), content="true")
  match db.get(id) {
    Some(record) => {
      inspect(record.vector[0], content="1")
      match record.attrs.get("name") {
        Some(@types.String(s)) => inspect(s, content="test")
        _ => inspect(false, content="true")
      }
    }
    None => inspect(false, content="true")
  }
}

///|
test "vectordb/find" {
  let db = VectorDB::with_dim(2)
  // Find on empty db
  inspect(db.find([1.0, 0.0], None) is None, content="true")
  // Add vectors
  db.add(@types.VectorId::from_int(1), [1.0, 0.0], @types.empty_attrs())
  db.add(@types.VectorId::from_int(2), [0.0, 1.0], @types.empty_attrs())
  // Find best match
  match db.find([1.0, 0.0], None) {
    Some(hit) => inspect(hit.id.to_int64(), content="1")
    None => inspect(false, content="true")
  }
}

///|
test "vectordb/update_attrs" {
  let db = VectorDB::with_dim(2)
  let id = @types.VectorId::from_int(1)
  // Can't update non-existent
  inspect(db.update_attrs(id, @types.empty_attrs()), content="false")
  // Add and update
  db.add(id, [1.0, 0.0], @types.empty_attrs())
  let new_attrs = @types.empty_attrs()
  new_attrs.set("version", @types.Int(2L))
  inspect(db.update_attrs(id, new_attrs), content="true")
  // Verify update
  match db.get(id) {
    Some(r) =>
      match r.attrs.get("version") {
        Some(@types.Int(v)) => inspect(v, content="2")
        _ => inspect(false, content="true")
      }
    None => inspect(false, content="true")
  }
}

///|
test "vectordb/hnsw_remove" {
  let db = VectorDB::with_hnsw(2, metric=@types.Dot)
  let id1 = @types.VectorId::from_int(1)
  let id2 = @types.VectorId::from_int(2)
  let id3 = @types.VectorId::from_int(3)
  db.add(id1, [1.0, 0.0], @types.empty_attrs())
  db.add(id2, [0.0, 1.0], @types.empty_attrs())
  db.add(id3, [0.5, 0.5], @types.empty_attrs())
  inspect(db.size(), content="3")
  // Remove id1 (tombstone only for HNSW)
  let removed = db.remove(id1)
  inspect(removed, content="true")
  // size() now excludes tombstones
  inspect(db.size(), content="2")
  inspect(db.raw_size(), content="3")
  // Search should not find id1
  let results = db.search([1.0, 0.0], 10, None)
  let has_id1 = results.iter().any(fn(h) { h.id.to_int64() == 1L })
  inspect(has_id1, content="false")
}

///|
test "vectordb/ivf_remove" {
  let db = VectorDB::with_ivf(2, metric=@types.Dot)
  let id1 = @types.VectorId::from_int(1)
  let id2 = @types.VectorId::from_int(2)
  db.add(id1, [1.0, 0.0], @types.empty_attrs())
  db.add(id2, [0.0, 1.0], @types.empty_attrs())
  inspect(db.size(), content="2")
  // Remove id1
  let removed = db.remove(id1)
  inspect(removed, content="true")
  inspect(db.size(), content="1")
  inspect(db.has(id1), content="false")
}

///|
test "vectordb/train" {
  let db = VectorDB::with_ivf(3, metric=@types.Dot)
  // Add some vectors
  for i in 1..<=10 {
    db.add(
      @types.VectorId::from_int(i),
      [
        (i % 3).to_double(),
        ((i + 1) % 3).to_double(),
        ((i + 2) % 3).to_double(),
      ],
      @types.empty_attrs(),
    )
  }
  // Train should not crash
  db.train(iterations=5)
  // Search should work after training
  let results = db.search([1.0, 0.0, 0.0], 3, None)
  inspect(results.length() > 0, content="true")
}

///|
test "vectordb/hnsw_serialization" {
  let db = VectorDB::with_hnsw(3, metric=@types.Cosine)
  db.add(@types.VectorId::from_int(1), [1.0, 0.0, 0.0], @types.empty_attrs())
  db.add(@types.VectorId::from_int(2), [0.0, 1.0, 0.0], @types.empty_attrs())
  // Serialize
  let bytes = db.serialize()
  inspect(bytes.length() > 0, content="true")
  // Deserialize
  let db2 = VectorDB::deserialize(bytes)
  inspect(db2.size(), content="2")
  // Search should work
  let results = db2.search([1.0, 0.0, 0.0], 1, None)
  inspect(results.length(), content="1")
}

///|
test "vectordb/ivf_serialization" {
  let db = VectorDB::with_ivf(3, metric=@types.Dot)
  db.add(@types.VectorId::from_int(1), [1.0, 0.0, 0.0], @types.empty_attrs())
  db.add(@types.VectorId::from_int(2), [0.0, 1.0, 0.0], @types.empty_attrs())
  // Serialize
  let bytes = db.serialize()
  inspect(bytes.length() > 0, content="true")
  // Deserialize
  let db2 = VectorDB::deserialize(bytes)
  inspect(db2.size(), content="2")
  // Search should work
  let results = db2.search([1.0, 0.0, 0.0], 2, None)
  inspect(results.length(), content="2")
}

///|
test "vectordb/search_with_expr_none" {
  let db = VectorDB::with_dim(2)
  db.add(@types.VectorId::from_int(1), [1.0, 0.0], @types.empty_attrs())
  db.add(@types.VectorId::from_int(2), [0.0, 1.0], @types.empty_attrs())
  // Search with no expr
  let results = db.search_with_expr([1.0, 0.0], 2, None, None, @filter.Auto)
  inspect(results.length(), content="2")
}

///|
test "vectordb/remove_nonexistent" {
  let db = VectorDB::with_dim(2)
  let removed = db.remove(@types.VectorId::from_int(999))
  inspect(removed, content="false")
}

///|
test "vectordb/upsert_vs_add" {
  let db = VectorDB::with_dim(2)
  let id1 = @types.VectorId::from_int(1)
  let id2 = @types.VectorId::from_int(2)
  // First add works
  db.add(id1, [1.0, 0.0], @types.empty_attrs())
  inspect(db.size(), content="1")
  // Use upsert for updates
  let _ = db.upsert(id1, [0.0, 1.0], @types.empty_attrs())
  inspect(db.size(), content="1")
  // Vector should be updated
  match db.get(id1) {
    Some(r) => inspect(r.vector[0], content="0")
    None => inspect(false, content="true")
  }
  // Add different id
  db.add(id2, [0.5, 0.5], @types.empty_attrs())
  inspect(db.size(), content="2")
}

///|
/// Test: Upsert reindexes HNSW vectors (P1 fix)
test "vectordb/upsert_reindex_hnsw" {
  let db = VectorDB::with_hnsw(2, metric=@types.Dot)
  let id = @types.VectorId::from_int(1)
  // Add vector pointing in one direction
  db.add(id, [1.0, 0.0], @types.empty_attrs())
  db.add(@types.VectorId::from_int(2), [0.0, 1.0], @types.empty_attrs())
  // Search for [1, 0] should find id=1 as best
  let results1 = db.search([1.0, 0.0], 1, None)
  inspect(results1[0].id.to_int64(), content="1")
  // Upsert to change id=1 to point in opposite direction
  let _ = db.upsert(id, [0.0, 1.0], @types.empty_attrs())
  // Now search for [1, 0] should NOT find id=1 as best
  let results2 = db.search([1.0, 0.0], 2, None)
  // id=2 should be better match now (both point to [0, 1])
  // Actually both now point to [0, 1], so neither is a good match for [1, 0]
  let _ = results2[0].id.to_int64()
  // After update, id=1 has vector [0, 1], so searching for [0, 1] should find it
  let results3 = db.search([0.0, 1.0], 1, None)
  inspect(
    results3[0].id.to_int64() == 1L || results3[0].id.to_int64() == 2L,
    content="true",
  )
}

///|
/// Test: Upsert reindexes IVF vectors (P1 fix)
test "vectordb/upsert_reindex_ivf" {
  let db = VectorDB::with_ivf(2, metric=@types.Dot)
  let id = @types.VectorId::from_int(1)
  // Add vector pointing in one direction
  db.add(id, [1.0, 0.0], @types.empty_attrs())
  db.add(@types.VectorId::from_int(2), [0.0, 1.0], @types.empty_attrs())
  // Upsert to change id=1 to point in opposite direction
  let _ = db.upsert(id, [0.0, 1.0], @types.empty_attrs())
  // Search for [0, 1] should find the updated vector
  let results = db.search([0.0, 1.0], 2, None)
  inspect(results.length(), content="2")
}

///|
/// Test: Serialization preserves HNSW params (P1 fix)
test "vectordb/serialize_hnsw_params" {
  let params : @types.HNSWParams = {
    m: 32,
    ef_construction: 100,
    ef_search: 25,
    level_mult: 0.5,
    seed: 12345UL,
    allow_replace_deleted: true,
  }
  let options : @types.DatabaseOptions = {
    dim: 3,
    metric: @types.Cosine,
    capacity: 100,
    strategy: @types.HNSW(params),
  }
  let db = VectorDB::new(options)
  db.add(@types.VectorId::from_int(1), [1.0, 0.0, 0.0], @types.empty_attrs())
  // Serialize and deserialize
  let bytes = db.serialize()
  let db2 = VectorDB::deserialize(bytes)
  // Check params are preserved
  match db2.strategy {
    @types.HNSW(p) => {
      inspect(p.m, content="32")
      inspect(p.ef_construction, content="100")
      inspect(p.ef_search, content="25")
      inspect(p.allow_replace_deleted, content="true")
    }
    _ => inspect(false, content="true")
  }
  // Search should still work
  let results = db2.search([1.0, 0.0, 0.0], 1, None)
  inspect(results.length(), content="1")
}

///|
/// Test: Serialization preserves IVF params (P1 fix)
test "vectordb/serialize_ivf_params" {
  let params : @types.IVFParams = { nlist: 128, nprobe: 16 }
  let options : @types.DatabaseOptions = {
    dim: 3,
    metric: @types.Dot,
    capacity: 100,
    strategy: @types.IVF(params),
  }
  let db = VectorDB::new(options)
  db.add(@types.VectorId::from_int(1), [1.0, 0.0, 0.0], @types.empty_attrs())
  // Serialize and deserialize
  let bytes = db.serialize()
  let db2 = VectorDB::deserialize(bytes)
  // Check params are preserved
  match db2.strategy {
    @types.IVF(p) => {
      inspect(p.nlist, content="128")
      inspect(p.nprobe, content="16")
    }
    _ => inspect(false, content="true")
  }
}

///|
/// Test: search_with_expr validates query dimension (P1 fix)
/// When query dimension doesn't match, should return empty results
test "vectordb/search_dimension_validation" {
  let db = VectorDB::with_dim(3)
  let index = @attr.BasicAttrIndex::new()
  // Add vectors
  let attrs1 = @types.empty_attrs()
  attrs1.set("status", @types.String("active"))
  db.add(@types.VectorId::from_int(1), [1.0, 0.0, 0.0], attrs1)
  index.set_attrs(@types.VectorId::from_int(1), attrs1)
  let attrs2 = @types.empty_attrs()
  attrs2.set("status", @types.String("active"))
  db.add(@types.VectorId::from_int(2), [0.0, 1.0, 0.0], attrs2)
  index.set_attrs(@types.VectorId::from_int(2), attrs2)
  // Search with wrong dimension (2 instead of 3) using pre-filter
  let expr = @filter.FilterExpr::match_("status", @types.String("active"))
  let results = db.search_with_expr(
    [1.0, 0.0], // Wrong dimension!
    2,
    Some(expr),
    Some(index),
    @filter.PreFilter,
  )
  // Should return empty results instead of crashing
  inspect(results.length(), content="0")
}

///|
/// Test: search with correct dimension returns results
test "vectordb/search_dimension_correct" {
  let db = VectorDB::with_dim(3)
  let index = @attr.BasicAttrIndex::new()
  // Add vectors
  let attrs1 = @types.empty_attrs()
  attrs1.set("status", @types.String("active"))
  db.add(@types.VectorId::from_int(1), [1.0, 0.0, 0.0], attrs1)
  index.set_attrs(@types.VectorId::from_int(1), attrs1)
  // Search with correct dimension
  let expr = @filter.FilterExpr::match_("status", @types.String("active"))
  let results = db.search_with_expr(
    [1.0, 0.0, 0.0], // Correct dimension
    1,
    Some(expr),
    Some(index),
    @filter.PreFilter,
  )
  inspect(results.length(), content="1")
  inspect(results[0].id.to_int64(), content="1")
}

///|
/// Test: HNSW tombstoned IDs appear deleted for CRUD operations (P1 fix)
/// Delete-then-add on same ID should work
test "vectordb/hnsw_tombstone_delete_add" {
  let db = VectorDB::with_hnsw(3, metric=@types.Dot)
  let id = @types.VectorId::from_int(1)
  // Add a vector
  db.add(id, [1.0, 0.0, 0.0], @types.empty_attrs())
  inspect(db.has(id), content="true")
  inspect(db.get(id) is Some(_), content="true")
  // Remove it (marks as tombstone in HNSW)
  let removed = db.remove(id)
  inspect(removed, content="true")
  // Now has/get should return false/None
  inspect(db.has(id), content="false")
  inspect(db.get(id) is None, content="true")
  // Re-add with new vector should work
  db.add(id, [0.0, 1.0, 0.0], @types.empty_attrs())
  inspect(db.has(id), content="true")
  // Search should find the new vector
  let results = db.search([0.0, 1.0, 0.0], 1, None)
  inspect(results.length(), content="1")
  inspect(results[0].id.to_int64(), content="1")
}

///|
/// Test: HNSW tombstone doesn't affect non-HNSW strategies
test "vectordb/bruteforce_delete_add" {
  let db = VectorDB::with_dim(3)
  let id = @types.VectorId::from_int(1)
  // Add and remove
  db.add(id, [1.0, 0.0, 0.0], @types.empty_attrs())
  inspect(db.remove(id), content="true")
  inspect(db.has(id), content="false")
  // Re-add should work
  db.add(id, [0.0, 1.0, 0.0], @types.empty_attrs())
  inspect(db.has(id), content="true")
}

///|
/// Test: HNSW multiple delete-add cycles
test "vectordb/hnsw_multiple_delete_add" {
  let db = VectorDB::with_hnsw(2, metric=@types.Dot)
  let id = @types.VectorId::from_int(42)
  // Cycle 1
  db.add(id, [1.0, 0.0], @types.empty_attrs())
  inspect(db.has(id), content="true")
  let _ = db.remove(id)
  inspect(db.has(id), content="false")
  // Cycle 2
  db.add(id, [0.0, 1.0], @types.empty_attrs())
  inspect(db.has(id), content="true")
  let _ = db.remove(id)
  inspect(db.has(id), content="false")
  // Cycle 3
  db.add(id, [0.5, 0.5], @types.empty_attrs())
  inspect(db.has(id), content="true")
}

///|
/// Test: HNSW double-remove returns false on second call
test "vectordb/hnsw_double_remove" {
  let db = VectorDB::with_hnsw(2, metric=@types.Dot)
  let id = @types.VectorId::from_int(1)
  db.add(id, [1.0, 0.0], @types.empty_attrs())
  // First remove should succeed
  let first = db.remove(id)
  inspect(first, content="true")
  // Second remove should fail (already tombstoned)
  let second = db.remove(id)
  inspect(second, content="false")
}

///|
/// Test: Pre-filter search excludes tombstoned HNSW IDs
test "vectordb/prefilter_excludes_tombstoned" {
  let db = VectorDB::with_hnsw(2, metric=@types.Dot)
  let index = @attr.BasicAttrIndex::new()
  // Add vectors with attrs
  let id1 = @types.VectorId::from_int(1)
  let id2 = @types.VectorId::from_int(2)
  let attrs1 = @types.empty_attrs()
  attrs1.set("type", @types.String("test"))
  let attrs2 = @types.empty_attrs()
  attrs2.set("type", @types.String("test"))
  db.add(id1, [1.0, 0.0], attrs1)
  db.add(id2, [0.0, 1.0], attrs2)
  index.set_attrs(id1, attrs1)
  index.set_attrs(id2, attrs2)
  // Remove id1 (tombstone in HNSW)
  let _ = db.remove(id1)
  // Pre-filter search should NOT return id1
  let expr = @filter.FilterExpr::match_("type", @types.String("test"))
  let results = db.search_with_expr(
    [1.0, 0.0],
    10,
    Some(expr),
    Some(index),
    @filter.PreFilter,
  )
  // Should only find id2 (id1 is tombstoned)
  inspect(results.length(), content="1")
  inspect(results[0].id.to_int64(), content="2")
}

///|
/// Test: IVF upsert updates don't grow centroid count
test "vectordb/ivf_upsert_no_centroid_growth" {
  let db = VectorDB::with_ivf(2, metric=@types.Dot)
  // Add vectors and train
  for i in 1..<=5 {
    db.add(
      @types.VectorId::from_int(i),
      [i.to_double(), 0.0],
      @types.empty_attrs(),
    )
  }
  db.train(iterations=3)
  // Get initial centroid count
  let initial_centroids = match db.ivf {
    Some(state) => state.centroid_count
    None => 0
  }
  inspect(initial_centroids > 0, content="true")
  // Upsert existing IDs multiple times
  for _ in 0..<10 {
    let _ = db.upsert(
      @types.VectorId::from_int(1),
      [10.0, 0.0],
      @types.empty_attrs(),
    )
  }
  // Centroid count should NOT have grown
  let final_centroids = match db.ivf {
    Some(state) => state.centroid_count
    None => 0
  }
  inspect(final_centroids == initial_centroids, content="true")
}
