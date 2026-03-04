// Whitebox tests for ann module

///|
test "bruteforce/search" {
  let store = @core.CoreStore::new(3, @core.Dot)
  let _ = store.add_or_update(
    @core.VectorId::from_int(1),
    [1.0, 0.0, 0.0],
    @core.empty_attrs(),
  )
  let _ = store.add_or_update(
    @core.VectorId::from_int(2),
    [0.0, 1.0, 0.0],
    @core.empty_attrs(),
  )
  let _ = store.add_or_update(
    @core.VectorId::from_int(3),
    [0.5, 0.5, 0.0],
    @core.empty_attrs(),
  )
  let state = BruteforceState::new(@core.Dot)
  // Search for [1, 0, 0] - should find id=1 as best match
  let results = bf_search(state, store, [1.0, 0.0, 0.0], 2, None)
  inspect(results.length(), content="2")
  inspect(results[0].id.to_int64(), content="1")
  inspect(results[0].score, content="1")
}

///|
test "bruteforce/search_with_filter" {
  let store = @core.CoreStore::new(2, @core.Dot)
  let attrs1 = @core.empty_attrs()
  attrs1.set("tag", @core.String("a"))
  let attrs2 = @core.empty_attrs()
  attrs2.set("tag", @core.String("b"))
  let _ = store.add_or_update(@core.VectorId::from_int(1), [1.0, 0.0], attrs1)
  let _ = store.add_or_update(@core.VectorId::from_int(2), [0.9, 0.1], attrs2)
  let state = BruteforceState::new(@core.Dot)
  // Filter to only tag="b"
  let filter = fn(id : @core.VectorId, attrs : @core.Attrs) -> Bool {
    let _ = id
    match attrs.get("tag") {
      Some(@core.String(s)) => s == "b"
      _ => false
    }
  }
  let results = bf_search(state, store, [1.0, 0.0], 10, Some(filter))
  inspect(results.length(), content="1")
  inspect(results[0].id.to_int64(), content="2")
}

///|
test "hnsw/basic" {
  let store = @core.CoreStore::new(3, @core.Dot)
  let _ = store.add_or_update(
    @core.VectorId::from_int(1),
    [1.0, 0.0, 0.0],
    @core.empty_attrs(),
  )
  let _ = store.add_or_update(
    @core.VectorId::from_int(2),
    [0.0, 1.0, 0.0],
    @core.empty_attrs(),
  )
  let _ = store.add_or_update(
    @core.VectorId::from_int(3),
    [0.5, 0.5, 0.0],
    @core.empty_attrs(),
  )
  let params = @core.HNSWParams::default()
  let state = HNSWState::new(params, @core.Dot, 10)
  // Add vectors to HNSW
  hnsw_add(state, store, @core.VectorId::from_int(1))
  hnsw_add(state, store, @core.VectorId::from_int(2))
  hnsw_add(state, store, @core.VectorId::from_int(3))
  // Search for [1, 0, 0]
  let results = hnsw_search(state, store, [1.0, 0.0, 0.0], 2, None)
  inspect(results.length(), content="2")
  inspect(results[0].id.to_int64(), content="1")
}

///|
test "ivf/basic" {
  let store = @core.CoreStore::new(3, @core.Dot)
  let _ = store.add_or_update(
    @core.VectorId::from_int(1),
    [1.0, 0.0, 0.0],
    @core.empty_attrs(),
  )
  let _ = store.add_or_update(
    @core.VectorId::from_int(2),
    [0.0, 1.0, 0.0],
    @core.empty_attrs(),
  )
  let _ = store.add_or_update(
    @core.VectorId::from_int(3),
    [0.5, 0.5, 0.0],
    @core.empty_attrs(),
  )
  let params = @core.IVFParams::default()
  let state = IVFState::new(params, @core.Dot, 3)
  // Add vectors to IVF
  ivf_add(state, store, @core.VectorId::from_int(1))
  ivf_add(state, store, @core.VectorId::from_int(2))
  ivf_add(state, store, @core.VectorId::from_int(3))
  // Search for [1, 0, 0]
  let results = ivf_search(state, store, [1.0, 0.0, 0.0], 2, None)
  inspect(results.length(), content="2")
  inspect(results[0].id.to_int64(), content="1")
}

///|
test "hnsw/serialization" {
  let store = @core.CoreStore::new(3, @core.Dot)
  let _ = store.add_or_update(
    @core.VectorId::from_int(1),
    [1.0, 0.0, 0.0],
    @core.empty_attrs(),
  )
  let _ = store.add_or_update(
    @core.VectorId::from_int(2),
    [0.0, 1.0, 0.0],
    @core.empty_attrs(),
  )
  let params = @core.HNSWParams::default()
  let state = HNSWState::new(params, @core.Dot, 10)
  hnsw_add(state, store, @core.VectorId::from_int(1))
  hnsw_add(state, store, @core.VectorId::from_int(2))
  // Serialize
  let bytes = hnsw_serialize(state)
  inspect(bytes.length() > 0, content="true")
  // Deserialize into new state
  let state2 = HNSWState::new(params, @core.Dot, 10)
  hnsw_deserialize(state2, bytes)
  // Search should still work
  let results = hnsw_search(state2, store, [1.0, 0.0, 0.0], 2, None)
  inspect(results.length(), content="2")
  inspect(results[0].id.to_int64(), content="1")
}

///|
test "ivf/serialization" {
  let store = @core.CoreStore::new(3, @core.Dot)
  let _ = store.add_or_update(
    @core.VectorId::from_int(1),
    [1.0, 0.0, 0.0],
    @core.empty_attrs(),
  )
  let _ = store.add_or_update(
    @core.VectorId::from_int(2),
    [0.0, 1.0, 0.0],
    @core.empty_attrs(),
  )
  let params = @core.IVFParams::default()
  let state = IVFState::new(params, @core.Dot, 3)
  ivf_add(state, store, @core.VectorId::from_int(1))
  ivf_add(state, store, @core.VectorId::from_int(2))
  // Serialize
  let bytes = ivf_serialize(state, 3)
  inspect(bytes.length() > 0, content="true")
  // Deserialize into new state
  let state2 = IVFState::new(params, @core.Dot, 3)
  ivf_deserialize(state2, bytes, 3)
  // Search should still work
  let results = ivf_search(state2, store, [1.0, 0.0, 0.0], 2, None)
  inspect(results.length(), content="2")
  inspect(results[0].id.to_int64(), content="1")
}

///|
test "ivf/training" {
  let store = @core.CoreStore::new(3, @core.Dot)
  let _ = store.add_or_update(
    @core.VectorId::from_int(1),
    [1.0, 0.0, 0.0],
    @core.empty_attrs(),
  )
  let _ = store.add_or_update(
    @core.VectorId::from_int(2),
    [0.0, 1.0, 0.0],
    @core.empty_attrs(),
  )
  let _ = store.add_or_update(
    @core.VectorId::from_int(3),
    [0.0, 0.0, 1.0],
    @core.empty_attrs(),
  )
  let _ = store.add_or_update(
    @core.VectorId::from_int(4),
    [0.9, 0.1, 0.0],
    @core.empty_attrs(),
  )
  let params : @core.IVFParams = { nlist: 2, nprobe: 2 }
  let state = IVFState::new(params, @core.Dot, 3)
  // Train with k-means
  ivf_train(state, store, iterations=5)
  inspect(state.centroid_count, content="2")
  // Search should find vectors
  let results = ivf_search(state, store, [1.0, 0.0, 0.0], 2, None)
  inspect(results.length() > 0, content="true")
}

///|
test "hnsw/remove" {
  let store = @core.CoreStore::new(3, @core.Dot)
  let id1 = @core.VectorId::from_int(1)
  let id2 = @core.VectorId::from_int(2)
  let id3 = @core.VectorId::from_int(3)
  let _ = store.add_or_update(id1, [1.0, 0.0, 0.0], @core.empty_attrs())
  let _ = store.add_or_update(id2, [0.0, 1.0, 0.0], @core.empty_attrs())
  let _ = store.add_or_update(id3, [0.5, 0.5, 0.0], @core.empty_attrs())
  let params = @core.HNSWParams::default()
  let state = HNSWState::new(params, @core.Dot, 10)
  hnsw_add(state, store, id1)
  hnsw_add(state, store, id2)
  hnsw_add(state, store, id3)
  // Verify all 3 are searchable
  let results1 = hnsw_search(state, store, [1.0, 0.0, 0.0], 10, None)
  inspect(results1.length(), content="3")
  // Remove id1
  hnsw_remove(state, id1, store)
  // Search should not find id1 anymore
  let results2 = hnsw_search(state, store, [1.0, 0.0, 0.0], 10, None)
  // Note: hnsw_remove marks as deleted, search still works but skips deleted
  let has_id1 = results2.iter().any(fn(h) { h.id.to_int64() == 1L })
  inspect(has_id1, content="false")
}

///|
test "ivf/remove" {
  let store = @core.CoreStore::new(3, @core.Dot)
  let id1 = @core.VectorId::from_int(1)
  let id2 = @core.VectorId::from_int(2)
  let id3 = @core.VectorId::from_int(3)
  let _ = store.add_or_update(id1, [1.0, 0.0, 0.0], @core.empty_attrs())
  let _ = store.add_or_update(id2, [0.0, 1.0, 0.0], @core.empty_attrs())
  let _ = store.add_or_update(id3, [0.5, 0.5, 0.0], @core.empty_attrs())
  let params = @core.IVFParams::default()
  let state = IVFState::new(params, @core.Dot, 3)
  ivf_add(state, store, id1)
  ivf_add(state, store, id2)
  ivf_add(state, store, id3)
  // Remove id1 from IVF
  ivf_remove(state, id1)
  // Search should not return id1
  let results = ivf_search(state, store, [1.0, 0.0, 0.0], 10, None)
  let has_id1 = results.iter().any(fn(h) { h.id.to_int64() == 1L })
  inspect(has_id1, content="false")
}

///|
test "bruteforce/find" {
  let store = @core.CoreStore::new(2, @core.Dot)
  let _ = store.add_or_update(
    @core.VectorId::from_int(1),
    [1.0, 0.0],
    @core.empty_attrs(),
  )
  let _ = store.add_or_update(
    @core.VectorId::from_int(2),
    [0.0, 1.0],
    @core.empty_attrs(),
  )
  let state = BruteforceState::new(@core.Dot)
  // Find single best match
  let result = bf_find(state, store, [1.0, 0.0], None)
  match result {
    Some(hit) => inspect(hit.id.to_int64(), content="1")
    None => inspect(false, content="true")
  }
}

///|
test "hnsw/find" {
  let store = @core.CoreStore::new(2, @core.Dot)
  let _ = store.add_or_update(
    @core.VectorId::from_int(1),
    [1.0, 0.0],
    @core.empty_attrs(),
  )
  let _ = store.add_or_update(
    @core.VectorId::from_int(2),
    [0.0, 1.0],
    @core.empty_attrs(),
  )
  let params = @core.HNSWParams::default()
  let state = HNSWState::new(params, @core.Dot, 10)
  hnsw_add(state, store, @core.VectorId::from_int(1))
  hnsw_add(state, store, @core.VectorId::from_int(2))
  // Find single best match
  let result = hnsw_find(state, store, [1.0, 0.0], None)
  match result {
    Some(hit) => inspect(hit.id.to_int64(), content="1")
    None => inspect(false, content="true")
  }
}

///|
test "ivf/find" {
  let store = @core.CoreStore::new(2, @core.Dot)
  let _ = store.add_or_update(
    @core.VectorId::from_int(1),
    [1.0, 0.0],
    @core.empty_attrs(),
  )
  let _ = store.add_or_update(
    @core.VectorId::from_int(2),
    [0.0, 1.0],
    @core.empty_attrs(),
  )
  let params = @core.IVFParams::default()
  let state = IVFState::new(params, @core.Dot, 2)
  ivf_add(state, store, @core.VectorId::from_int(1))
  ivf_add(state, store, @core.VectorId::from_int(2))
  // Find single best match
  let result = ivf_find(state, store, [1.0, 0.0], None)
  match result {
    Some(hit) => inspect(hit.id.to_int64(), content="1")
    None => inspect(false, content="true")
  }
}

///|
/// Test: HNSW compact and rebuild drops tombstones
test "hnsw/compact_rebuild" {
  let store = @core.CoreStore::new(3, @core.Cosine)
  let id1 = @core.VectorId::from_int(1)
  let id2 = @core.VectorId::from_int(2)
  let id3 = @core.VectorId::from_int(3)
  let _ = store.add_or_update(id1, [1.0, 0.0, 0.0], @core.empty_attrs())
  let _ = store.add_or_update(id2, [0.0, 1.0, 0.0], @core.empty_attrs())
  let _ = store.add_or_update(id3, [0.0, 0.0, 1.0], @core.empty_attrs())
  let params = @core.HNSWParams::default()
  let state = HNSWState::new(params, @core.Cosine, 10)
  hnsw_add(state, store, id1)
  hnsw_add(state, store, id2)
  hnsw_add(state, store, id3)
  // Verify search works
  let results1 = hnsw_search(state, store, [1.0, 0.0, 0.0], 1, None)
  inspect(results1[0].id.to_int64(), content="1")
  // Remove id1
  hnsw_remove(state, id1, store)
  // Tombstone stats
  let (alive, dead) = hnsw_tombstone_stats(state, store)
  inspect(dead, content="1")
  inspect(alive, content="2")
  // Compact and rebuild
  let (new_state, removed) = hnsw_compact_and_rebuild(state, store)
  inspect(removed, content="1")
  // Search on rebuilt state - id1 should be completely gone
  let results2 = hnsw_search(new_state, store, [1.0, 0.0, 0.0], 10, None)
  let has_id1 = results2.iter().any(fn(h) { h.id.to_int64() == 1L })
  inspect(has_id1, content="false")
}

///|
/// Test: HNSW rebuild from scratch
test "hnsw/rebuild" {
  let store = @core.CoreStore::new(3, @core.Dot)
  let _ = store.add_or_update(
    @core.VectorId::from_int(1),
    [1.0, 0.0, 0.0],
    @core.empty_attrs(),
  )
  let _ = store.add_or_update(
    @core.VectorId::from_int(2),
    [0.0, 1.0, 0.0],
    @core.empty_attrs(),
  )
  let params = @core.HNSWParams::default()
  // Rebuild from store
  let state = hnsw_rebuild(store, params, @core.Dot)
  // Search should work
  let results = hnsw_search(state, store, [1.0, 0.0, 0.0], 2, None)
  inspect(results.length(), content="2")
  inspect(results[0].id.to_int64(), content="1")
}

///|
/// Test: IVF retrain centroids
test "ivf/retrain" {
  let store = @core.CoreStore::new(3, @core.Cosine)
  // Add vectors in two clusters
  for i in 1..<=10 {
    let _ = store.add_or_update(
      @core.VectorId::from_int(i),
      [1.0, (i % 3).to_double() * 0.1, 0.0],
      @core.empty_attrs(),
    )
  }
  for i in 11..<=20 {
    let _ = store.add_or_update(
      @core.VectorId::from_int(i),
      [0.0, 1.0, (i % 3).to_double() * 0.1],
      @core.empty_attrs(),
    )
  }
  let params : @core.IVFParams = { nlist: 4, nprobe: 2 }
  let state = IVFState::new(params, @core.Cosine, 3)
  ivf_train(state, store, iterations=5)
  // Add all vectors
  for i in 1..<=20 {
    ivf_add(state, store, @core.VectorId::from_int(i))
  }
  // Retrain
  let reassigned = ivf_retrain(state, store, 5)
  inspect(reassigned, content="20")
  // Search should still work
  let results = ivf_search(state, store, [1.0, 0.0, 0.0], 5, None)
  inspect(results.length() > 0, content="true")
}

///|
/// Test: IVF rebuild with new parameters
test "ivf/rebuild" {
  let store = @core.CoreStore::new(3, @core.Dot)
  for i in 1..<=10 {
    let _ = store.add_or_update(
      @core.VectorId::from_int(i),
      [
        (i % 3).to_double(),
        ((i + 1) % 3).to_double(),
        ((i + 2) % 3).to_double(),
      ],
      @core.empty_attrs(),
    )
  }
  let params : @core.IVFParams = { nlist: 2, nprobe: 2 }
  let state = ivf_rebuild(store, params, @core.Dot, 5)
  // Search should work
  let results = ivf_search(state, store, [1.0, 0.0, 0.0], 3, None)
  inspect(results.length(), content="3")
}

///|
/// Test: Bruteforce add/remove are no-ops
test "bruteforce/add_remove_noop" {
  let store = @core.CoreStore::new(2, @core.Dot)
  let _ = store.add_or_update(
    @core.VectorId::from_int(1),
    [1.0, 0.0],
    @core.empty_attrs(),
  )
  let state = BruteforceState::new(@core.Dot)
  // These are no-ops but should not crash
  bf_add(state, store, @core.VectorId::from_int(1))
  bf_remove(state, store, @core.VectorId::from_int(1))
  // Search should still work
  let results = bf_search(state, store, [1.0, 0.0], 1, None)
  inspect(results.length(), content="1")
}

///|
/// Test: Bruteforce serialize/deserialize
test "bruteforce/serialize_deserialize" {
  let state = BruteforceState::new(@core.Cosine)
  // Serialize returns empty bytes
  let bytes = bf_serialize(state)
  inspect(bytes.length(), content="0")
  // Deserialize is a no-op but should not crash
  bf_deserialize(state, Bytes::new(0))
  // State should still work
  let store = @core.CoreStore::new(2, @core.Cosine)
  let _ = store.add_or_update(
    @core.VectorId::from_int(1),
    [1.0, 0.0],
    @core.empty_attrs(),
  )
  let results = bf_search(state, store, [1.0, 0.0], 1, None)
  inspect(results.length(), content="1")
}

///|
/// Test: Bruteforce find on empty store
test "bruteforce/find_empty" {
  let store = @core.CoreStore::new(2, @core.Dot)
  let state = BruteforceState::new(@core.Dot)
  let result = bf_find(state, store, [1.0, 0.0], None)
  inspect(result is None, content="true")
}

///|
/// Test: Bruteforce with L2 metric
test "bruteforce/l2_metric" {
  let store = @core.CoreStore::new(2, @core.L2)
  let _ = store.add_or_update(
    @core.VectorId::from_int(1),
    [1.0, 0.0],
    @core.empty_attrs(),
  )
  let _ = store.add_or_update(
    @core.VectorId::from_int(2),
    [0.0, 1.0],
    @core.empty_attrs(),
  )
  let state = BruteforceState::new(@core.L2)
  // L2 returns negative squared distance, so closer is higher
  let results = bf_search(state, store, [1.0, 0.0], 2, None)
  inspect(results.length(), content="2")
  // id=1 should be best (distance 0)
  inspect(results[0].id.to_int64(), content="1")
  inspect(results[0].score, content="0")
}

///|
/// Test: HNSW search on empty state
test "hnsw/search_empty" {
  let store = @core.CoreStore::new(2, @core.Dot)
  let params = @core.HNSWParams::default()
  let state = HNSWState::new(params, @core.Dot, 10)
  let results = hnsw_search(state, store, [1.0, 0.0], 5, None)
  inspect(results.length(), content="0")
}

///|
/// Test: IVF search on empty state
test "ivf/search_empty" {
  let store = @core.CoreStore::new(2, @core.Dot)
  let params = @core.IVFParams::default()
  let state = IVFState::new(params, @core.Dot, 2)
  let results = ivf_search(state, store, [1.0, 0.0], 5, None)
  inspect(results.length(), content="0")
}

///|
/// Test: HNSW find on empty state
test "hnsw/find_empty" {
  let store = @core.CoreStore::new(2, @core.Dot)
  let params = @core.HNSWParams::default()
  let state = HNSWState::new(params, @core.Dot, 10)
  let result = hnsw_find(state, store, [1.0, 0.0], None)
  inspect(result is None, content="true")
}

///|
/// Test: IVF find on empty state
test "ivf/find_empty" {
  let store = @core.CoreStore::new(2, @core.Dot)
  let params = @core.IVFParams::default()
  let state = IVFState::new(params, @core.Dot, 2)
  let result = ivf_find(state, store, [1.0, 0.0], None)
  inspect(result is None, content="true")
}

///|
/// Test: IVF recall vs BruteForce on clustered data
test "ivf/recall_vs_bruteforce" {
  let store = @core.CoreStore::new(4, @core.Cosine)
  // Create two clusters
  // Cluster 1: around [1, 0, 0, 0]
  for i in 1..<=25 {
    let jitter = (i % 5).to_double() * 0.02
    let _ = store.add_or_update(
      @core.VectorId::from_int(i),
      [1.0, jitter, 0.0, 0.0],
      @core.empty_attrs(),
    )
  }
  // Cluster 2: around [0, 1, 0, 0]
  for i in 26..<=50 {
    let jitter = (i % 5).to_double() * 0.02
    let _ = store.add_or_update(
      @core.VectorId::from_int(i),
      [0.0, 1.0, jitter, 0.0],
      @core.empty_attrs(),
    )
  }
  // BruteForce search
  let bf_state = BruteforceState::new(@core.Cosine)
  let bf_results = bf_search(bf_state, store, [1.0, 0.05, 0.0, 0.0], 5, None)
  // IVF search
  let ivf_params : @core.IVFParams = { nlist: 4, nprobe: 2 }
  let ivf_state = IVFState::new(ivf_params, @core.Cosine, 4)
  ivf_train(ivf_state, store, iterations=10)
  for i in 1..<=50 {
    ivf_add(ivf_state, store, @core.VectorId::from_int(i))
  }
  let ivf_results = ivf_search(ivf_state, store, [1.0, 0.05, 0.0, 0.0], 5, None)
  // Calculate recall: how many IVF results match BF results
  let bf_ids : Array[Int64] = bf_results.map(fn(h) { h.id.to_int64() })
  let mut matches = 0
  for ivf_hit in ivf_results {
    let ivf_id = ivf_hit.id.to_int64()
    if bf_ids.iter().any(fn(id) { id == ivf_id }) {
      matches = matches + 1
    }
  }
  let recall = matches.to_double() / bf_results.length().to_double()
  // Expect at least 60% recall
  inspect(recall >= 0.6, content="true")
}

///|
/// Test: ivf_assign assigns to existing centroids without bootstrap (P2 fix)
/// After training, ivf_assign should use trained centroids, not create new ones
test "ivf/assign_no_bootstrap" {
  let store = @core.CoreStore::new(2, @core.Dot)
  // Add 5 vectors (less than nlist=10)
  for i in 1..<=5 {
    let _ = store.add_or_update(
      @core.VectorId::from_int(i),
      [i.to_double() / 5.0, 1.0 - i.to_double() / 5.0],
      @core.empty_attrs(),
    )
  }
  // Create IVF state with nlist > store.size() to trigger bootstrap issue
  let params : @core.IVFParams = { nlist: 10, nprobe: 3 }
  let state = IVFState::new(params, @core.Dot, 2)
  // Train with existing vectors
  ivf_train(state, store, iterations=5)
  // Save the centroid count after training
  let centroid_count_after_train = state.centroid_count
  inspect(centroid_count_after_train, content="5") // Should equal store.size()
  // Clear lists for reassignment
  for list in state.lists {
    list.clear()
  }
  state.id_to_list.clear()
  // Use ivf_assign which should NOT bootstrap (unlike ivf_add)
  for i in 1..<=5 {
    ivf_assign(state, store, @core.VectorId::from_int(i))
  }
  // Centroid count should remain the same (no new centroids created)
  inspect(state.centroid_count, content="5")
  // All vectors should be assigned
  let mut total_assigned = 0
  for list in state.lists {
    total_assigned = total_assigned + list.length()
  }
  inspect(total_assigned, content="5")
}

///|
/// Test: ivf_retrain uses ivf_assign, not ivf_add (P2 fix)
test "ivf/retrain_no_bootstrap" {
  let store = @core.CoreStore::new(2, @core.Dot)
  // Add 3 vectors (less than nlist=8)
  for i in 1..<=3 {
    let _ = store.add_or_update(
      @core.VectorId::from_int(i),
      [i.to_double(), 0.0],
      @core.empty_attrs(),
    )
  }
  let params : @core.IVFParams = { nlist: 8, nprobe: 2 }
  let state = IVFState::new(params, @core.Dot, 2)
  // Initial training + assignment via ivf_add (may trigger bootstrap)
  ivf_train(state, store, iterations=3)
  for i in 1..<=3 {
    ivf_add(state, store, @core.VectorId::from_int(i))
  }
  let _initial_centroid_count = state.centroid_count
  // Retrain should use ivf_assign, not ivf_add
  let _ = ivf_retrain(state, store, 3)
  // After retrain, centroid count should be based on training only (not bootstrap)
  // With 3 vectors and nlist=8, centroid_count should be 3 (min of vectors, nlist)
  inspect(state.centroid_count, content="3")
  // All vectors should be searchable
  let results = ivf_search(state, store, [2.0, 0.0], 3, None)
  inspect(results.length(), content="3")
}

///|
/// Test: HNSW compaction preserves tombstone state for skipped indices
test "hnsw/compact_preserves_tombstones" {
  let store = @core.CoreStore::new(2, @core.Dot, capacity=10)
  let params = @core.HNSWParams::default()
  let state = HNSWState::new(params, @core.Dot, 10)
  // Add 3 vectors
  for i in 1..<=3 {
    let _ = store.add_or_update(
      @core.VectorId::from_int(i),
      [i.to_double(), 0.0],
      @core.empty_attrs(),
      upsert=false,
    )
    hnsw_add(state, store, @core.VectorId::from_int(i))
  }
  // Tombstone ID 2
  hnsw_remove(state, @core.VectorId::from_int(2), store)
  inspect(state.tombstone[1], content="true") // ID 2 is at index 1
  // Compact
  let (new_state, removed) = hnsw_compact_and_rebuild(state, store)
  inspect(removed, content="1")
  // Verify index 1 (ID 2) is still tombstoned in new state
  inspect(new_state.tombstone[1], content="true")
  // Search should not return ID 2
  let results = hnsw_search(new_state, store, [2.0, 0.0], 3, None)
  for r in results {
    inspect(r.id.to_int64() != 2L, content="true")
  }
}
