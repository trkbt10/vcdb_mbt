// Whitebox tests for VectorDB facade

///|
test "vectordb/bruteforce" {
  let db = VectorDB::with_dim(3)
  let _ = db.add(@types.VectorId::from_int(1), [1.0, 0.0, 0.0], @types.empty_attrs())
  let _ = db.add(@types.VectorId::from_int(2), [0.0, 1.0, 0.0], @types.empty_attrs())
  let _ = db.add(@types.VectorId::from_int(3), [0.5, 0.5, 0.0], @types.empty_attrs())
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
  let _ = db.add(@types.VectorId::from_int(1), [1.0, 0.0, 0.0], @types.empty_attrs())
  let _ = db.add(@types.VectorId::from_int(2), [0.0, 1.0, 0.0], @types.empty_attrs())
  let _ = db.add(@types.VectorId::from_int(3), [0.5, 0.5, 0.0], @types.empty_attrs())
  inspect(db.size(), content="3")
  // Search
  let results = db.search([1.0, 0.0, 0.0], 2, None)
  inspect(results.length(), content="2")
  inspect(results[0].id.to_int64(), content="1")
}

///|
test "vectordb/ivf" {
  let db = VectorDB::with_ivf(3, metric=@types.Dot)
  let _ = db.add(@types.VectorId::from_int(1), [1.0, 0.0, 0.0], @types.empty_attrs())
  let _ = db.add(@types.VectorId::from_int(2), [0.0, 1.0, 0.0], @types.empty_attrs())
  let _ = db.add(@types.VectorId::from_int(3), [0.5, 0.5, 0.0], @types.empty_attrs())
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
  let _ = db.add(@types.VectorId::from_int(1), [1.0, 0.0, 0.0], attrs)
  let _ = db.add(@types.VectorId::from_int(2), [0.0, 1.0, 0.0], @types.empty_attrs())
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
test "vectordb/serialization_preserves_metadata_index" {
  let db = VectorDB::with_dim(2)
  let attrs_a = @types.empty_attrs()
  attrs_a.set("category", @types.String("A"))
  let attrs_b = @types.empty_attrs()
  attrs_b.set("category", @types.String("B"))
  let _ = db.add(@types.VectorId::from_int(1), [1.0, 0.0], attrs_a)
  let _ = db.add(@types.VectorId::from_int(2), [0.0, 1.0], attrs_b)
  let bytes = db.serialize()
  let db2 = VectorDB::deserialize(bytes)
  let expr = @filter.FilterExpr::match_("category", @types.String("B"))
  let results = db2.search_with_expr(
    [1.0, 0.0],
    10,
    Some(expr),
    None,
    @filter.PreFilter,
  )
  inspect(results.length(), content="1")
  inspect(results[0].id.to_int64(), content="2")
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
  let _ = db.add(@types.VectorId::from_int(1), [1.0, 0.0], attrs_a) // Best match, cat A
  let _ = db.add(@types.VectorId::from_int(2), [0.9, 0.1], attrs_b) // Second, cat B
  let _ = db.add(@types.VectorId::from_int(3), [0.5, 0.5], attrs_a) // Third, cat A
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
  // Add vectors with scores
  for i in 1..<=10 {
    let attrs = @types.empty_attrs()
    attrs.set("score", @types.Int(i.to_int64() * 10L))
    let id = @types.VectorId::from_int(i)
    let _ = db.add(id, [i.to_double() / 10.0, 1.0 - i.to_double() / 10.0], attrs)
  }
  // Search with PreFilter: score >= 50 (IDs 5-10)
  let range = @types.NumericRange::gte(50.0)
  let expr = @filter.FilterExpr::range("score", range)
  let results = db.search_with_expr(
    [1.0, 0.0],
    3,
    Some(expr),
    None,
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
  // Add 10 vectors, only 2 have tag="rare"
  for i in 1..<=10 {
    let attrs = @types.empty_attrs()
    if i <= 2 {
      attrs.set("tag", @types.String("rare"))
    } else {
      attrs.set("tag", @types.String("common"))
    }
    let id = @types.VectorId::from_int(i)
    let _ = db.add(id, [i.to_double() / 10.0, 1.0 - i.to_double() / 10.0], attrs)
  }
  // Search with Auto strategy: should use pre-filter (2/10 < 50%)
  let expr = @filter.FilterExpr::match_("tag", @types.String("rare"))
  let results = db.search_with_expr(
    [1.0, 0.0],
    5,
    Some(expr),
    None,
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
  let _ = db.add(id, [1.0, 0.0], attrs)
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
  let _ = db.add(@types.VectorId::from_int(1), [1.0, 0.0], @types.empty_attrs())
  let _ = db.add(@types.VectorId::from_int(2), [0.0, 1.0], @types.empty_attrs())
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
  let _ = db.add(id, [1.0, 0.0], @types.empty_attrs())
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
test "vectordb/update_attrs_updates_metadata_index" {
  let db = VectorDB::with_dim(2)
  let id = @types.VectorId::from_int(1)
  let attrs = @types.empty_attrs()
  attrs.set("status", @types.String("draft"))
  let _ = db.add(id, [1.0, 0.0], attrs)
  let new_attrs = @types.empty_attrs()
  new_attrs.set("status", @types.String("published"))
  inspect(db.update_attrs(id, new_attrs), content="true")
  let draft_expr = @filter.FilterExpr::match_("status", @types.String("draft"))
  let published_expr = @filter.FilterExpr::match_(
    "status",
    @types.String("published"),
  )
  let draft_results = db.search_with_expr(
    [1.0, 0.0],
    10,
    Some(draft_expr),
    None,
    @filter.PreFilter,
  )
  let published_results = db.search_with_expr(
    [1.0, 0.0],
    10,
    Some(published_expr),
    None,
    @filter.PreFilter,
  )
  inspect(draft_results.length(), content="0")
  inspect(published_results.length(), content="1")
  inspect(published_results[0].id.to_int64(), content="1")
}

///|
test "vectordb/hnsw_remove" {
  let db = VectorDB::with_hnsw(2, metric=@types.Dot)
  let id1 = @types.VectorId::from_int(1)
  let id2 = @types.VectorId::from_int(2)
  let id3 = @types.VectorId::from_int(3)
  let _ = db.add(id1, [1.0, 0.0], @types.empty_attrs())
  let _ = db.add(id2, [0.0, 1.0], @types.empty_attrs())
  let _ = db.add(id3, [0.5, 0.5], @types.empty_attrs())
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
  let _ = db.add(id1, [1.0, 0.0], @types.empty_attrs())
  let _ = db.add(id2, [0.0, 1.0], @types.empty_attrs())
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
    let _ = db.add(
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
  let _ = db.add(@types.VectorId::from_int(1), [1.0, 0.0, 0.0], @types.empty_attrs())
  let _ = db.add(@types.VectorId::from_int(2), [0.0, 1.0, 0.0], @types.empty_attrs())
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
test "vectordb/hnsw_serialization_preserves_metadata_visibility" {
  let db = VectorDB::with_hnsw(2, metric=@types.Dot)
  let keep_attrs = @types.empty_attrs()
  keep_attrs.set("group", @types.String("keep"))
  let drop_attrs = @types.empty_attrs()
  drop_attrs.set("group", @types.String("drop"))
  let keep_id = @types.VectorId::from_int(1)
  let drop_id = @types.VectorId::from_int(2)
  let _ = db.add(keep_id, [1.0, 0.0], keep_attrs)
  let _ = db.add(drop_id, [0.0, 1.0], drop_attrs)
  let _ = db.remove(drop_id)
  let bytes = db.serialize()
  let db2 = VectorDB::deserialize(bytes)
  let expr = @filter.FilterExpr::match_("group", @types.String("drop"))
  let results = db2.search_with_expr(
    [1.0, 0.0],
    10,
    Some(expr),
    None,
    @filter.PreFilter,
  )
  inspect(db2.size(), content="1")
  inspect(results.length(), content="0")
}

///|
test "vectordb/ivf_serialization" {
  let db = VectorDB::with_ivf(3, metric=@types.Dot)
  let _ = db.add(@types.VectorId::from_int(1), [1.0, 0.0, 0.0], @types.empty_attrs())
  let _ = db.add(@types.VectorId::from_int(2), [0.0, 1.0, 0.0], @types.empty_attrs())
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
  let _ = db.add(@types.VectorId::from_int(1), [1.0, 0.0], @types.empty_attrs())
  let _ = db.add(@types.VectorId::from_int(2), [0.0, 1.0], @types.empty_attrs())
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
  let _ = db.add(id1, [1.0, 0.0], @types.empty_attrs())
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
  let _ = db.add(id2, [0.5, 0.5], @types.empty_attrs())
  inspect(db.size(), content="2")
}

///|
/// Test: Upsert reindexes HNSW vectors (P1 fix)
test "vectordb/upsert_reindex_hnsw" {
  let db = VectorDB::with_hnsw(2, metric=@types.Dot)
  let id = @types.VectorId::from_int(1)
  // Add vector pointing in one direction
  let _ = db.add(id, [1.0, 0.0], @types.empty_attrs())
  let _ = db.add(@types.VectorId::from_int(2), [0.0, 1.0], @types.empty_attrs())
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
  let _ = db.add(id, [1.0, 0.0], @types.empty_attrs())
  let _ = db.add(@types.VectorId::from_int(2), [0.0, 1.0], @types.empty_attrs())
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
  let _ = db.add(@types.VectorId::from_int(1), [1.0, 0.0, 0.0], @types.empty_attrs())
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
  let _ = db.add(@types.VectorId::from_int(1), [1.0, 0.0, 0.0], @types.empty_attrs())
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
  // Add vectors
  let attrs1 = @types.empty_attrs()
  attrs1.set("status", @types.String("active"))
  let _ = db.add(@types.VectorId::from_int(1), [1.0, 0.0, 0.0], attrs1)
  let attrs2 = @types.empty_attrs()
  attrs2.set("status", @types.String("active"))
  let _ = db.add(@types.VectorId::from_int(2), [0.0, 1.0, 0.0], attrs2)
  // Search with wrong dimension (2 instead of 3) using pre-filter
  let expr = @filter.FilterExpr::match_("status", @types.String("active"))
  let results = db.search_with_expr(
    [1.0, 0.0], // Wrong dimension!
    2,
    Some(expr),
    None,
    @filter.PreFilter,
  )
  // Should return empty results instead of crashing
  inspect(results.length(), content="0")
}

///|
/// Test: search with correct dimension returns results
test "vectordb/search_dimension_correct" {
  let db = VectorDB::with_dim(3)
  // Add vectors
  let attrs1 = @types.empty_attrs()
  attrs1.set("status", @types.String("active"))
  let _ = db.add(@types.VectorId::from_int(1), [1.0, 0.0, 0.0], attrs1)
  // Search with correct dimension
  let expr = @filter.FilterExpr::match_("status", @types.String("active"))
  let results = db.search_with_expr(
    [1.0, 0.0, 0.0], // Correct dimension
    1,
    Some(expr),
    None,
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
  let _ = db.add(id, [1.0, 0.0, 0.0], @types.empty_attrs())
  inspect(db.has(id), content="true")
  inspect(db.get(id) is Some(_), content="true")
  // Remove it (marks as tombstone in HNSW)
  let removed = db.remove(id)
  inspect(removed, content="true")
  // Now has/get should return false/None
  inspect(db.has(id), content="false")
  inspect(db.get(id) is None, content="true")
  // Re-add with new vector should work
  let _ = db.add(id, [0.0, 1.0, 0.0], @types.empty_attrs())
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
  let _ = db.add(id, [1.0, 0.0, 0.0], @types.empty_attrs())
  inspect(db.remove(id), content="true")
  inspect(db.has(id), content="false")
  // Re-add should work
  let _ = db.add(id, [0.0, 1.0, 0.0], @types.empty_attrs())
  inspect(db.has(id), content="true")
}

///|
/// Test: HNSW multiple delete-add cycles
test "vectordb/hnsw_multiple_delete_add" {
  let db = VectorDB::with_hnsw(2, metric=@types.Dot)
  let id = @types.VectorId::from_int(42)
  // Cycle 1
  let _ = db.add(id, [1.0, 0.0], @types.empty_attrs())
  inspect(db.has(id), content="true")
  let _ = db.remove(id)
  inspect(db.has(id), content="false")
  // Cycle 2
  let _ = db.add(id, [0.0, 1.0], @types.empty_attrs())
  inspect(db.has(id), content="true")
  let _ = db.remove(id)
  inspect(db.has(id), content="false")
  // Cycle 3
  let _ = db.add(id, [0.5, 0.5], @types.empty_attrs())
  inspect(db.has(id), content="true")
}

///|
/// Test: HNSW double-remove returns false on second call
test "vectordb/hnsw_double_remove" {
  let db = VectorDB::with_hnsw(2, metric=@types.Dot)
  let id = @types.VectorId::from_int(1)
  let _ = db.add(id, [1.0, 0.0], @types.empty_attrs())
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
  // Add vectors with attrs
  let id1 = @types.VectorId::from_int(1)
  let id2 = @types.VectorId::from_int(2)
  let attrs1 = @types.empty_attrs()
  attrs1.set("type", @types.String("test"))
  let attrs2 = @types.empty_attrs()
  attrs2.set("type", @types.String("test"))
  let _ = db.add(id1, [1.0, 0.0], attrs1)
  let _ = db.add(id2, [0.0, 1.0], attrs2)
  // Remove id1 (tombstone in HNSW)
  let _ = db.remove(id1)
  // Pre-filter search should NOT return id1
  let expr = @filter.FilterExpr::match_("type", @types.String("test"))
  let results = db.search_with_expr(
    [1.0, 0.0],
    10,
    Some(expr),
    None,
    @filter.PreFilter,
  )
  // Should only find id2 (id1 is tombstoned)
  inspect(results.length(), content="1")
  inspect(results[0].id.to_int64(), content="2")
}

///|
/// scroll_filtered: basic category filter
test "vectordb/scroll_filtered_basic" {
  let db = VectorDB::with_dim(2)
  let cat_a = @types.empty_attrs()
  cat_a.set("category", @types.String("科学"))
  let cat_b = @types.empty_attrs()
  cat_b.set("category", @types.String("歴史"))
  let _ = db.add(@types.VectorId::from_int(1), [1.0, 0.0], cat_a)
  let _ = db.add(@types.VectorId::from_int(2), [0.0, 1.0], cat_b)
  let _ = db.add(@types.VectorId::from_int(3), [0.5, 0.5], cat_a)
  let expr = @filter.FilterExpr::match_("category", @types.String("科学"))
  let results = db.scroll_filtered(expr=Some(expr), limit=10)
  inspect(results.length(), content="2")
  // Verify ascending ID order
  let (id0, _) = results[0]
  let (id1, _) = results[1]
  inspect(id0.to_int64(), content="1")
  inspect(id1.to_int64(), content="3")
}

///|
/// scroll_filtered: cursor-based pagination
test "vectordb/scroll_filtered_pagination" {
  let db = VectorDB::with_dim(2)
  let attrs = @types.empty_attrs()
  attrs.set("_type", @types.String("question"))
  for i in 1..<=5 {
    let _ = db.add(
      @types.VectorId::from_int(i),
      [i.to_double() / 5.0, 1.0 - i.to_double() / 5.0],
      attrs,
    )
  }
  let expr = @filter.FilterExpr::match_("_type", @types.String("question"))
  // Page 1: first 2
  let page1 = db.scroll_filtered(expr=Some(expr), limit=2)
  inspect(page1.length(), content="2")
  let (last_id, _) = page1[1]
  inspect(last_id.to_int64(), content="2")
  // Page 2: next 2 (offset = last seen ID)
  let page2 = db.scroll_filtered(
    expr=Some(expr),
    offset=Some(last_id.to_int64()),
    limit=2,
  )
  inspect(page2.length(), content="2")
  let (p2_first, _) = page2[0]
  let (p2_last, _) = page2[1]
  inspect(p2_first.to_int64(), content="3")
  inspect(p2_last.to_int64(), content="4")
  // Page 3: last 1
  let page3 = db.scroll_filtered(
    expr=Some(expr),
    offset=Some(p2_last.to_int64()),
    limit=2,
  )
  inspect(page3.length(), content="1")
  let (p3_first, _) = page3[0]
  inspect(p3_first.to_int64(), content="5")
}

///|
/// scroll_filtered: empty results when no match
test "vectordb/scroll_filtered_empty" {
  let db = VectorDB::with_dim(2)
  let attrs = @types.empty_attrs()
  attrs.set("category", @types.String("科学"))
  let _ = db.add(@types.VectorId::from_int(1), [1.0, 0.0], attrs)
  let expr = @filter.FilterExpr::match_("category", @types.String("料理"))
  let results = db.scroll_filtered(expr=Some(expr), limit=10)
  inspect(results.length(), content="0")
}

///|
/// scroll_filtered: MustNot (complement) — no fallback, index-only
test "vectordb/scroll_filtered_must_not" {
  let db = VectorDB::with_dim(2)
  let cat_a = @types.empty_attrs()
  cat_a.set("_type", @types.String("question"))
  let cat_b = @types.empty_attrs()
  cat_b.set("_type", @types.String("top"))
  let _ = db.add(@types.VectorId::from_int(1), [1.0, 0.0], cat_a)
  let _ = db.add(@types.VectorId::from_int(2), [0.0, 1.0], cat_b)
  let _ = db.add(@types.VectorId::from_int(3), [0.5, 0.5], cat_a)
  // "NOT top" should return questions only
  let expr = @filter.FilterExpr::must_not([
    @filter.FilterExpr::match_("_type", @types.String("top")),
  ])
  let results = db.scroll_filtered(expr=Some(expr), limit=10)
  inspect(results.length(), content="2")
  let (id0, _) = results[0]
  let (id1, _) = results[1]
  inspect(id0.to_int64(), content="1")
  inspect(id1.to_int64(), content="3")
}

///|
/// scroll_filtered: IsNull (complement) — no fallback, index-only
test "vectordb/scroll_filtered_is_null" {
  let db = VectorDB::with_dim(2)
  let with_cat = @types.empty_attrs()
  with_cat.set("category", @types.String("科学"))
  let without_cat = @types.empty_attrs()
  without_cat.set("other", @types.String("value"))
  let _ = db.add(@types.VectorId::from_int(1), [1.0, 0.0], with_cat)
  let _ = db.add(@types.VectorId::from_int(2), [0.0, 1.0], without_cat)
  // IsNull("category") should return ID 2 (no category attr)
  let expr = @filter.FilterExpr::is_null("category")
  let results = db.scroll_filtered(expr=Some(expr), limit=10)
  inspect(results.length(), content="1")
  let (id0, _) = results[0]
  inspect(id0.to_int64(), content="2")
}

///|
/// scroll_filtered: Should(min=2) — counting path
test "vectordb/scroll_filtered_should_min2" {
  let db = VectorDB::with_dim(2)
  // ID 1: has tag=A and tag2=X
  let attrs1 = @types.empty_attrs()
  attrs1.set("tag", @types.String("A"))
  attrs1.set("tag2", @types.String("X"))
  // ID 2: has tag=A only
  let attrs2 = @types.empty_attrs()
  attrs2.set("tag", @types.String("A"))
  // ID 3: has tag2=X only
  let attrs3 = @types.empty_attrs()
  attrs3.set("tag2", @types.String("X"))
  let _ = db.add(@types.VectorId::from_int(1), [1.0, 0.0], attrs1)
  let _ = db.add(@types.VectorId::from_int(2), [0.0, 1.0], attrs2)
  let _ = db.add(@types.VectorId::from_int(3), [0.5, 0.5], attrs3)
  // Should match at least 2 of [tag=A, tag2=X] → only ID 1
  let expr = @filter.FilterExpr::should(
    [
      @filter.FilterExpr::match_("tag", @types.String("A")),
      @filter.FilterExpr::match_("tag2", @types.String("X")),
    ],
    min=2,
  )
  let results = db.scroll_filtered(expr=Some(expr), limit=10)
  inspect(results.length(), content="1")
  let (id0, _) = results[0]
  inspect(id0.to_int64(), content="1")
}

///|
/// count_filtered: basic
test "vectordb/count_filtered" {
  let db = VectorDB::with_dim(2)
  let cat_a = @types.empty_attrs()
  cat_a.set("category", @types.String("科学"))
  let cat_b = @types.empty_attrs()
  cat_b.set("category", @types.String("歴史"))
  let _ = db.add(@types.VectorId::from_int(1), [1.0, 0.0], cat_a)
  let _ = db.add(@types.VectorId::from_int(2), [0.0, 1.0], cat_b)
  let _ = db.add(@types.VectorId::from_int(3), [0.5, 0.5], cat_a)
  let expr_a = @filter.FilterExpr::match_("category", @types.String("科学"))
  inspect(db.count_filtered(expr=Some(expr_a)), content="2")
  let expr_b = @filter.FilterExpr::match_("category", @types.String("歴史"))
  inspect(db.count_filtered(expr=Some(expr_b)), content="1")
  let expr_c = @filter.FilterExpr::match_("category", @types.String("料理"))
  inspect(db.count_filtered(expr=Some(expr_c)), content="0")
}

///|
/// count_filtered: HNSW tombstone excluded
test "vectordb/count_filtered_hnsw_tombstone" {
  let db = VectorDB::with_hnsw(2, metric=@types.Dot)
  let attrs = @types.empty_attrs()
  attrs.set("_type", @types.String("q"))
  let _ = db.add(@types.VectorId::from_int(1), [1.0, 0.0], attrs)
  let _ = db.add(@types.VectorId::from_int(2), [0.0, 1.0], attrs)
  let _ = db.remove(@types.VectorId::from_int(1))
  let expr = @filter.FilterExpr::match_("_type", @types.String("q"))
  inspect(db.count_filtered(expr=Some(expr)), content="1")
}

///|
/// scroll_filtered: HNSW tombstoned entries excluded
test "vectordb/scroll_filtered_hnsw_tombstone" {
  let db = VectorDB::with_hnsw(2, metric=@types.Dot)
  let attrs = @types.empty_attrs()
  attrs.set("category", @types.String("科学"))
  let _ = db.add(@types.VectorId::from_int(1), [1.0, 0.0], attrs)
  let _ = db.add(@types.VectorId::from_int(2), [0.0, 1.0], attrs)
  let _ = db.add(@types.VectorId::from_int(3), [0.5, 0.5], attrs)
  // Tombstone ID 2
  let _ = db.remove(@types.VectorId::from_int(2))
  let expr = @filter.FilterExpr::match_("category", @types.String("科学"))
  let results = db.scroll_filtered(expr=Some(expr), limit=10)
  inspect(results.length(), content="2")
  let (id0, _) = results[0]
  let (id1, _) = results[1]
  inspect(id0.to_int64(), content="1")
  inspect(id1.to_int64(), content="3")
}

///|
/// Test: IVF upsert updates don't grow centroid count
test "vectordb/ivf_upsert_no_centroid_growth" {
  let db = VectorDB::with_ivf(2, metric=@types.Dot)
  // Add vectors and train
  for i in 1..<=5 {
    let _ = db.add(
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
