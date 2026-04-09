// Whitebox tests for ann module

///|
test "bruteforce/search" {
  let store = @store.CoreStore::new(3, @types.Dot)
  let _ = store.add_or_update(
    @types.VectorId::from_int(1),
    [1.0, 0.0, 0.0],
    @types.empty_attrs(),
  )
  let _ = store.add_or_update(
    @types.VectorId::from_int(2),
    [0.0, 1.0, 0.0],
    @types.empty_attrs(),
  )
  let _ = store.add_or_update(
    @types.VectorId::from_int(3),
    [0.5, 0.5, 0.0],
    @types.empty_attrs(),
  )
  let state = BruteforceState::new(@types.Dot)
  // Search for [1, 0, 0] - should find id=1 as best match
  let results = bf_search(state, store, [1.0, 0.0, 0.0], 2, None)
  inspect(results.length(), content="2")
  inspect(results[0].id.to_int64(), content="1")
  inspect(results[0].score, content="1")
}

///|
test "bruteforce/search_with_filter" {
  let store = @store.CoreStore::new(2, @types.Dot)
  let attrs1 = @types.empty_attrs()
  attrs1.set("tag", @types.String("a"))
  let attrs2 = @types.empty_attrs()
  attrs2.set("tag", @types.String("b"))
  let _ = store.add_or_update(@types.VectorId::from_int(1), [1.0, 0.0], attrs1)
  let _ = store.add_or_update(@types.VectorId::from_int(2), [0.9, 0.1], attrs2)
  let state = BruteforceState::new(@types.Dot)
  // Filter to only tag="b"
  let filter = fn(id : @types.VectorId, attrs : @types.Attrs) -> Bool {
    let _ = id
    match attrs.get("tag") {
      Some(@types.String(s)) => s == "b"
      _ => false
    }
  }
  let results = bf_search(state, store, [1.0, 0.0], 10, Some(filter))
  inspect(results.length(), content="1")
  inspect(results[0].id.to_int64(), content="2")
}

///|
test "hnsw/basic" {
  let store = @store.CoreStore::new(3, @types.Dot)
  let _ = store.add_or_update(
    @types.VectorId::from_int(1),
    [1.0, 0.0, 0.0],
    @types.empty_attrs(),
  )
  let _ = store.add_or_update(
    @types.VectorId::from_int(2),
    [0.0, 1.0, 0.0],
    @types.empty_attrs(),
  )
  let _ = store.add_or_update(
    @types.VectorId::from_int(3),
    [0.5, 0.5, 0.0],
    @types.empty_attrs(),
  )
  let params = @types.HNSWParams::default()
  let state = HNSWState::new(params, @types.Dot, 10)
  // Add vectors to HNSW
  hnsw_add(state, store, @types.VectorId::from_int(1))
  hnsw_add(state, store, @types.VectorId::from_int(2))
  hnsw_add(state, store, @types.VectorId::from_int(3))
  // Search for [1, 0, 0]
  let results = hnsw_search(state, store, [1.0, 0.0, 0.0], 2, None)
  inspect(results.length(), content="2")
  inspect(results[0].id.to_int64(), content="1")
}

///|
test "ivf/basic" {
  let store = @store.CoreStore::new(3, @types.Dot)
  let _ = store.add_or_update(
    @types.VectorId::from_int(1),
    [1.0, 0.0, 0.0],
    @types.empty_attrs(),
  )
  let _ = store.add_or_update(
    @types.VectorId::from_int(2),
    [0.0, 1.0, 0.0],
    @types.empty_attrs(),
  )
  let _ = store.add_or_update(
    @types.VectorId::from_int(3),
    [0.5, 0.5, 0.0],
    @types.empty_attrs(),
  )
  let params = @types.IVFParams::default()
  let state = IVFState::new(params, @types.Dot, 3)
  // Add vectors to IVF
  ivf_add(state, store, @types.VectorId::from_int(1))
  ivf_add(state, store, @types.VectorId::from_int(2))
  ivf_add(state, store, @types.VectorId::from_int(3))
  // Search for [1, 0, 0]
  let results = ivf_search(state, store, [1.0, 0.0, 0.0], 2, None)
  inspect(results.length(), content="2")
  inspect(results[0].id.to_int64(), content="1")
}

///|
test "hnsw/serialization" {
  let store = @store.CoreStore::new(3, @types.Dot)
  let _ = store.add_or_update(
    @types.VectorId::from_int(1),
    [1.0, 0.0, 0.0],
    @types.empty_attrs(),
  )
  let _ = store.add_or_update(
    @types.VectorId::from_int(2),
    [0.0, 1.0, 0.0],
    @types.empty_attrs(),
  )
  let params = @types.HNSWParams::default()
  let state = HNSWState::new(params, @types.Dot, 10)
  hnsw_add(state, store, @types.VectorId::from_int(1))
  hnsw_add(state, store, @types.VectorId::from_int(2))
  // Serialize
  let bytes = hnsw_serialize(state)
  inspect(bytes.length() > 0, content="true")
  // Deserialize into new state
  let state2 = HNSWState::new(params, @types.Dot, 10)
  hnsw_deserialize(state2, bytes)
  // Search should still work
  let results = hnsw_search(state2, store, [1.0, 0.0, 0.0], 2, None)
  inspect(results.length(), content="2")
  inspect(results[0].id.to_int64(), content="1")
}

///|
test "ivf/serialization" {
  let store = @store.CoreStore::new(3, @types.Dot)
  let _ = store.add_or_update(
    @types.VectorId::from_int(1),
    [1.0, 0.0, 0.0],
    @types.empty_attrs(),
  )
  let _ = store.add_or_update(
    @types.VectorId::from_int(2),
    [0.0, 1.0, 0.0],
    @types.empty_attrs(),
  )
  let params = @types.IVFParams::default()
  let state = IVFState::new(params, @types.Dot, 3)
  ivf_add(state, store, @types.VectorId::from_int(1))
  ivf_add(state, store, @types.VectorId::from_int(2))
  // Serialize
  let bytes = ivf_serialize(state, 3)
  inspect(bytes.length() > 0, content="true")
  // Deserialize into new state
  let state2 = IVFState::new(params, @types.Dot, 3)
  ivf_deserialize(state2, bytes, 3)
  // Search should still work
  let results = ivf_search(state2, store, [1.0, 0.0, 0.0], 2, None)
  inspect(results.length(), content="2")
  inspect(results[0].id.to_int64(), content="1")
}

///|
test "ivf/training" {
  let store = @store.CoreStore::new(3, @types.Dot)
  let _ = store.add_or_update(
    @types.VectorId::from_int(1),
    [1.0, 0.0, 0.0],
    @types.empty_attrs(),
  )
  let _ = store.add_or_update(
    @types.VectorId::from_int(2),
    [0.0, 1.0, 0.0],
    @types.empty_attrs(),
  )
  let _ = store.add_or_update(
    @types.VectorId::from_int(3),
    [0.0, 0.0, 1.0],
    @types.empty_attrs(),
  )
  let _ = store.add_or_update(
    @types.VectorId::from_int(4),
    [0.9, 0.1, 0.0],
    @types.empty_attrs(),
  )
  let params : @types.IVFParams = { nlist: 2, nprobe: 2 }
  let state = IVFState::new(params, @types.Dot, 3)
  // Train with k-means
  ivf_train(state, store, iterations=5)
  inspect(state.centroid_count, content="2")
  // Search should find vectors
  let results = ivf_search(state, store, [1.0, 0.0, 0.0], 2, None)
  inspect(results.length() > 0, content="true")
}

///|
test "hnsw/remove" {
  let store = @store.CoreStore::new(3, @types.Dot)
  let id1 = @types.VectorId::from_int(1)
  let id2 = @types.VectorId::from_int(2)
  let id3 = @types.VectorId::from_int(3)
  let _ = store.add_or_update(id1, [1.0, 0.0, 0.0], @types.empty_attrs())
  let _ = store.add_or_update(id2, [0.0, 1.0, 0.0], @types.empty_attrs())
  let _ = store.add_or_update(id3, [0.5, 0.5, 0.0], @types.empty_attrs())
  let params = @types.HNSWParams::default()
  let state = HNSWState::new(params, @types.Dot, 10)
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
  let store = @store.CoreStore::new(3, @types.Dot)
  let id1 = @types.VectorId::from_int(1)
  let id2 = @types.VectorId::from_int(2)
  let id3 = @types.VectorId::from_int(3)
  let _ = store.add_or_update(id1, [1.0, 0.0, 0.0], @types.empty_attrs())
  let _ = store.add_or_update(id2, [0.0, 1.0, 0.0], @types.empty_attrs())
  let _ = store.add_or_update(id3, [0.5, 0.5, 0.0], @types.empty_attrs())
  let params = @types.IVFParams::default()
  let state = IVFState::new(params, @types.Dot, 3)
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
  let store = @store.CoreStore::new(2, @types.Dot)
  let _ = store.add_or_update(
    @types.VectorId::from_int(1),
    [1.0, 0.0],
    @types.empty_attrs(),
  )
  let _ = store.add_or_update(
    @types.VectorId::from_int(2),
    [0.0, 1.0],
    @types.empty_attrs(),
  )
  let state = BruteforceState::new(@types.Dot)
  // Find single best match
  let result = bf_find(state, store, [1.0, 0.0], None)
  match result {
    Some(hit) => inspect(hit.id.to_int64(), content="1")
    None => inspect(false, content="true")
  }
}

///|
test "hnsw/find" {
  let store = @store.CoreStore::new(2, @types.Dot)
  let _ = store.add_or_update(
    @types.VectorId::from_int(1),
    [1.0, 0.0],
    @types.empty_attrs(),
  )
  let _ = store.add_or_update(
    @types.VectorId::from_int(2),
    [0.0, 1.0],
    @types.empty_attrs(),
  )
  let params = @types.HNSWParams::default()
  let state = HNSWState::new(params, @types.Dot, 10)
  hnsw_add(state, store, @types.VectorId::from_int(1))
  hnsw_add(state, store, @types.VectorId::from_int(2))
  // Find single best match
  let result = hnsw_find(state, store, [1.0, 0.0], None)
  match result {
    Some(hit) => inspect(hit.id.to_int64(), content="1")
    None => inspect(false, content="true")
  }
}

///|
test "ivf/find" {
  let store = @store.CoreStore::new(2, @types.Dot)
  let _ = store.add_or_update(
    @types.VectorId::from_int(1),
    [1.0, 0.0],
    @types.empty_attrs(),
  )
  let _ = store.add_or_update(
    @types.VectorId::from_int(2),
    [0.0, 1.0],
    @types.empty_attrs(),
  )
  let params = @types.IVFParams::default()
  let state = IVFState::new(params, @types.Dot, 2)
  ivf_add(state, store, @types.VectorId::from_int(1))
  ivf_add(state, store, @types.VectorId::from_int(2))
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
  let store = @store.CoreStore::new(3, @types.Cosine)
  let id1 = @types.VectorId::from_int(1)
  let id2 = @types.VectorId::from_int(2)
  let id3 = @types.VectorId::from_int(3)
  let _ = store.add_or_update(id1, [1.0, 0.0, 0.0], @types.empty_attrs())
  let _ = store.add_or_update(id2, [0.0, 1.0, 0.0], @types.empty_attrs())
  let _ = store.add_or_update(id3, [0.0, 0.0, 1.0], @types.empty_attrs())
  let params = @types.HNSWParams::default()
  let state = HNSWState::new(params, @types.Cosine, 10)
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
  let store = @store.CoreStore::new(3, @types.Dot)
  let _ = store.add_or_update(
    @types.VectorId::from_int(1),
    [1.0, 0.0, 0.0],
    @types.empty_attrs(),
  )
  let _ = store.add_or_update(
    @types.VectorId::from_int(2),
    [0.0, 1.0, 0.0],
    @types.empty_attrs(),
  )
  let params = @types.HNSWParams::default()
  // Rebuild from store
  let state = hnsw_rebuild(store, params, @types.Dot)
  // Search should work
  let results = hnsw_search(state, store, [1.0, 0.0, 0.0], 2, None)
  inspect(results.length(), content="2")
  inspect(results[0].id.to_int64(), content="1")
}

///|
/// Test: IVF retrain centroids
test "ivf/retrain" {
  let store = @store.CoreStore::new(3, @types.Cosine)
  // Add vectors in two clusters
  for i in 1..<=10 {
    let _ = store.add_or_update(
      @types.VectorId::from_int(i),
      [1.0, (i % 3).to_double() * 0.1, 0.0],
      @types.empty_attrs(),
    )
  }
  for i in 11..<=20 {
    let _ = store.add_or_update(
      @types.VectorId::from_int(i),
      [0.0, 1.0, (i % 3).to_double() * 0.1],
      @types.empty_attrs(),
    )
  }
  let params : @types.IVFParams = { nlist: 4, nprobe: 2 }
  let state = IVFState::new(params, @types.Cosine, 3)
  ivf_train(state, store, iterations=5)
  // Add all vectors
  for i in 1..<=20 {
    ivf_add(state, store, @types.VectorId::from_int(i))
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
  let store = @store.CoreStore::new(3, @types.Dot)
  for i in 1..<=10 {
    let _ = store.add_or_update(
      @types.VectorId::from_int(i),
      [
        (i % 3).to_double(),
        ((i + 1) % 3).to_double(),
        ((i + 2) % 3).to_double(),
      ],
      @types.empty_attrs(),
    )
  }
  let params : @types.IVFParams = { nlist: 2, nprobe: 2 }
  let state = ivf_rebuild(store, params, @types.Dot, 5)
  // Search should work
  let results = ivf_search(state, store, [1.0, 0.0, 0.0], 3, None)
  inspect(results.length(), content="3")
}

///|
/// Test: Bruteforce add/remove are no-ops
test "bruteforce/add_remove_noop" {
  let store = @store.CoreStore::new(2, @types.Dot)
  let _ = store.add_or_update(
    @types.VectorId::from_int(1),
    [1.0, 0.0],
    @types.empty_attrs(),
  )
  let state = BruteforceState::new(@types.Dot)
  // These are no-ops but should not crash
  bf_add(state, store, @types.VectorId::from_int(1))
  bf_remove(state, store, @types.VectorId::from_int(1))
  // Search should still work
  let results = bf_search(state, store, [1.0, 0.0], 1, None)
  inspect(results.length(), content="1")
}

///|
/// Test: Bruteforce serialize/deserialize
test "bruteforce/serialize_deserialize" {
  let state = BruteforceState::new(@types.Cosine)
  // Serialize returns empty bytes
  let bytes = bf_serialize(state)
  inspect(bytes.length(), content="0")
  // Deserialize is a no-op but should not crash
  bf_deserialize(state, Bytes::new(0))
  // State should still work
  let store = @store.CoreStore::new(2, @types.Cosine)
  let _ = store.add_or_update(
    @types.VectorId::from_int(1),
    [1.0, 0.0],
    @types.empty_attrs(),
  )
  let results = bf_search(state, store, [1.0, 0.0], 1, None)
  inspect(results.length(), content="1")
}

///|
/// Test: Bruteforce find on empty store
test "bruteforce/find_empty" {
  let store = @store.CoreStore::new(2, @types.Dot)
  let state = BruteforceState::new(@types.Dot)
  let result = bf_find(state, store, [1.0, 0.0], None)
  inspect(result is None, content="true")
}

///|
/// Test: Bruteforce with L2 metric
test "bruteforce/l2_metric" {
  let store = @store.CoreStore::new(2, @types.L2)
  let _ = store.add_or_update(
    @types.VectorId::from_int(1),
    [1.0, 0.0],
    @types.empty_attrs(),
  )
  let _ = store.add_or_update(
    @types.VectorId::from_int(2),
    [0.0, 1.0],
    @types.empty_attrs(),
  )
  let state = BruteforceState::new(@types.L2)
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
  let store = @store.CoreStore::new(2, @types.Dot)
  let params = @types.HNSWParams::default()
  let state = HNSWState::new(params, @types.Dot, 10)
  let results = hnsw_search(state, store, [1.0, 0.0], 5, None)
  inspect(results.length(), content="0")
}

///|
/// Test: IVF search on empty state
test "ivf/search_empty" {
  let store = @store.CoreStore::new(2, @types.Dot)
  let params = @types.IVFParams::default()
  let state = IVFState::new(params, @types.Dot, 2)
  let results = ivf_search(state, store, [1.0, 0.0], 5, None)
  inspect(results.length(), content="0")
}

///|
/// Test: HNSW find on empty state
test "hnsw/find_empty" {
  let store = @store.CoreStore::new(2, @types.Dot)
  let params = @types.HNSWParams::default()
  let state = HNSWState::new(params, @types.Dot, 10)
  let result = hnsw_find(state, store, [1.0, 0.0], None)
  inspect(result is None, content="true")
}

///|
/// Test: IVF find on empty state
test "ivf/find_empty" {
  let store = @store.CoreStore::new(2, @types.Dot)
  let params = @types.IVFParams::default()
  let state = IVFState::new(params, @types.Dot, 2)
  let result = ivf_find(state, store, [1.0, 0.0], None)
  inspect(result is None, content="true")
}

///|
/// Test: IVF recall vs BruteForce on clustered data
test "ivf/recall_vs_bruteforce" {
  let store = @store.CoreStore::new(4, @types.Cosine)
  // Create two clusters
  // Cluster 1: around [1, 0, 0, 0]
  for i in 1..<=25 {
    let jitter = (i % 5).to_double() * 0.02
    let _ = store.add_or_update(
      @types.VectorId::from_int(i),
      [1.0, jitter, 0.0, 0.0],
      @types.empty_attrs(),
    )
  }
  // Cluster 2: around [0, 1, 0, 0]
  for i in 26..<=50 {
    let jitter = (i % 5).to_double() * 0.02
    let _ = store.add_or_update(
      @types.VectorId::from_int(i),
      [0.0, 1.0, jitter, 0.0],
      @types.empty_attrs(),
    )
  }
  // BruteForce search
  let bf_state = BruteforceState::new(@types.Cosine)
  let bf_results = bf_search(bf_state, store, [1.0, 0.05, 0.0, 0.0], 5, None)
  // IVF search
  let ivf_params : @types.IVFParams = { nlist: 4, nprobe: 2 }
  let ivf_state = IVFState::new(ivf_params, @types.Cosine, 4)
  ivf_train(ivf_state, store, iterations=10)
  for i in 1..<=50 {
    ivf_add(ivf_state, store, @types.VectorId::from_int(i))
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
  let store = @store.CoreStore::new(2, @types.Dot)
  // Add 5 vectors (less than nlist=10)
  for i in 1..<=5 {
    let _ = store.add_or_update(
      @types.VectorId::from_int(i),
      [i.to_double() / 5.0, 1.0 - i.to_double() / 5.0],
      @types.empty_attrs(),
    )
  }
  // Create IVF state with nlist > store.size() to trigger bootstrap issue
  let params : @types.IVFParams = { nlist: 10, nprobe: 3 }
  let state = IVFState::new(params, @types.Dot, 2)
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
    ivf_assign(state, store, @types.VectorId::from_int(i))
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
  let store = @store.CoreStore::new(2, @types.Dot)
  // Add 3 vectors (less than nlist=8)
  for i in 1..<=3 {
    let _ = store.add_or_update(
      @types.VectorId::from_int(i),
      [i.to_double(), 0.0],
      @types.empty_attrs(),
    )
  }
  let params : @types.IVFParams = { nlist: 8, nprobe: 2 }
  let state = IVFState::new(params, @types.Dot, 2)
  // Initial training + assignment via ivf_add (may trigger bootstrap)
  ivf_train(state, store, iterations=3)
  for i in 1..<=3 {
    ivf_add(state, store, @types.VectorId::from_int(i))
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
  let store = @store.CoreStore::new(2, @types.Dot, capacity=10)
  let params = @types.HNSWParams::default()
  let state = HNSWState::new(params, @types.Dot, 10)
  // Add 3 vectors
  for i in 1..<=3 {
    let _ = store.add_or_update(
      @types.VectorId::from_int(i),
      [i.to_double(), 0.0],
      @types.empty_attrs(),
      upsert=false,
    )
    hnsw_add(state, store, @types.VectorId::from_int(i))
  }
  // Tombstone ID 2
  hnsw_remove(state, @types.VectorId::from_int(2), store)
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

///|
/// Helper: add a vector to both store and HNSW index
fn add_to_hnsw(
  store : @store.CoreStore,
  state : HNSWState,
  id : Int,
  vec : Array[Double],
) -> Unit {
  let _ = store.add_or_update(
    @types.VectorId::from_int(id),
    vec,
    @types.empty_attrs(),
    upsert=false,
  )
  hnsw_add(state, store, @types.VectorId::from_int(id))
}

///|
/// Helper: assert that a search result set contains a given ID
fn assert_found(results : Array[@types.SearchHit], id : Int) -> Unit raise {
  let mut found = false
  for r in results {
    if r.id.to_int64() == id.to_int64() {
      found = true
    }
  }
  inspect(found, content="true")
}

///|
/// Helper: assert that a search result set does NOT contain a given ID
fn assert_not_found(results : Array[@types.SearchHit], id : Int) -> Unit raise {
  let mut found = false
  for r in results {
    if r.id.to_int64() == id.to_int64() {
      found = true
    }
  }
  inspect(found, content="false")
}

///|
/// Regression: tombstoned entry point must not be returned and search must
/// still succeed.  Two nodes, entry point forced to the tombstoned one.
test "hnsw/tombstoned_entrypoint_search_still_works" {
  let store = @store.CoreStore::new(2, @types.Dot, capacity=10)
  // m=2, small ef so the graph is minimal
  let params : @types.HNSWParams = {
    ..@types.HNSWParams::default(),
    m: 2,
    ef_construction: 4,
    ef_search: 4,
    seed: 7UL,
  }
  let state = HNSWState::new(params, @types.Dot, 10)
  add_to_hnsw(store, state, 1, [1.0, 0.0])
  add_to_hnsw(store, state, 2, [0.0, 1.0])
  // Force entry point to index 0 (ID 1) then tombstone it
  state.enter_point = 0
  hnsw_remove(state, @types.VectorId::from_int(1), store)
  // Search should still find ID 2 and must not return ID 1
  let results = hnsw_search(state, store, [0.0, 1.0], 2, None)
  inspect(results.length() > 0, content="true")
  assert_not_found(results, 1)
  assert_found(results, 2)
}

///|
/// Regression: tombstoned entry point must not block hnsw_add from connecting
/// the new node.  After all prior nodes are tombstoned the new node becomes
/// reachable as the sole valid node.
test "hnsw/add_after_all_tombstoned" {
  let store = @store.CoreStore::new(2, @types.Dot, capacity=10)
  let params : @types.HNSWParams = {
    ..@types.HNSWParams::default(),
    m: 2,
    ef_construction: 4,
    ef_search: 4,
    seed: 7UL,
  }
  let state = HNSWState::new(params, @types.Dot, 10)
  add_to_hnsw(store, state, 1, [1.0, 0.0])
  add_to_hnsw(store, state, 2, [0.0, 1.0])
  // Tombstone both existing nodes
  hnsw_remove(state, @types.VectorId::from_int(1), store)
  hnsw_remove(state, @types.VectorId::from_int(2), store)
  // Add a new node; it must become the sole live node and be findable
  add_to_hnsw(store, state, 3, [0.5, 0.5])
  let results = hnsw_search(state, store, [0.5, 0.5], 3, None)
  inspect(results.length(), content="1")
  assert_found(results, 3)
  assert_not_found(results, 1)
  assert_not_found(results, 2)
}

///|
/// Regression: remove(A) + add(B) where A sits between two clusters.
/// B, added near A's position, must be reachable.
///
/// We use m=4 and large ef so every node is well-connected, making this a
/// deterministic graph regardless of level sampling.  The test is NOT about
/// whether every original node survives the tombstone (HNSW gives no such
/// guarantee at low m), but strictly that B is reachable after remove(A)+add(B).
test "hnsw/remove_bridge_then_add_nearby_reachable" {
  let store = @store.CoreStore::new(2, @types.Dot, capacity=20)
  let params : @types.HNSWParams = {
    ..@types.HNSWParams::default(),
    m: 4,
    ef_construction: 20,
    ef_search: 20,
    seed: 42UL,
  }
  let state = HNSWState::new(params, @types.Dot, 20)
  add_to_hnsw(store, state, 1, [1.0, 0.0])
  add_to_hnsw(store, state, 2, [0.9, 0.1])
  add_to_hnsw(store, state, 3, [0.5, 0.5]) // bridge to be tombstoned
  add_to_hnsw(store, state, 4, [0.1, 0.9])
  add_to_hnsw(store, state, 5, [0.0, 1.0])
  // Tombstone the bridge node
  hnsw_remove(state, @types.VectorId::from_int(3), store)
  // Add ID10 near the former bridge position
  add_to_hnsw(store, state, 10, [0.55, 0.45])
  // ID10 must be reachable; ID3 must not appear
  let results = hnsw_search(state, store, [0.55, 0.45], 5, None)
  assert_found(results, 10)
  assert_not_found(results, 3)
}

///|
/// Regression: remove(A) + add(B) where A was the stored entry point at a
/// high level.  B is a new ID and must connect into the graph properly.
test "hnsw/remove_entrypoint_then_add_new_id" {
  let store = @store.CoreStore::new(2, @types.Dot, capacity=20)
  // seed=1 tends to assign level > 0 to early nodes, making them entrypoint
  let params : @types.HNSWParams = {
    ..@types.HNSWParams::default(),
    m: 4,
    ef_construction: 16,
    ef_search: 16,
    seed: 1UL,
  }
  let state = HNSWState::new(params, @types.Dot, 20)
  add_to_hnsw(store, state, 1, [1.0, 0.0])
  add_to_hnsw(store, state, 2, [0.8, 0.2])
  add_to_hnsw(store, state, 3, [0.6, 0.4])
  add_to_hnsw(store, state, 4, [0.4, 0.6])
  add_to_hnsw(store, state, 5, [0.2, 0.8])
  add_to_hnsw(store, state, 6, [0.0, 1.0])
  // Force entry point and tombstone it to simulate the reported scenario
  state.enter_point = 0
  hnsw_remove(state, @types.VectorId::from_int(1), store)
  // Add new ID 10 near the tombstoned entrypoint's vector
  add_to_hnsw(store, state, 10, [0.95, 0.05])
  // Both remaining live IDs and the new ID must be findable
  let results = hnsw_search(state, store, [0.95, 0.05], 6, None)
  assert_found(results, 10)
  assert_not_found(results, 1)
  // Every live ID (2-6) must also be reachable from some query
  let results2 = hnsw_search(state, store, [0.0, 1.0], 6, None)
  assert_found(results2, 6)
  assert_not_found(results2, 1)
}

///|
/// Regression [P1]: when the entry point is tombstoned, find_valid_entry_point
/// must not pick the node currently being inserted (at), because at has had
/// its tombstone cleared but has no edges yet.  If at is chosen as ep,
/// hnsw_search_layer returns only {at} and connect_mutually adds no edges.
/// When at also samples a level above max_level, the disconnected node becomes
/// the new enter_point and all pre-existing nodes become unreachable.
///
/// We construct the failure condition explicitly by manipulating level_arr
/// after the insert so the test does not depend on seed-specific level sampling.
test "hnsw/fallback_ep_must_not_pick_inserting_node" {
  let store = @store.CoreStore::new(2, @types.Dot, capacity=20)
  let params : @types.HNSWParams = {
    ..@types.HNSWParams::default(),
    m: 4,
    ef_construction: 16,
    ef_search: 16,
    seed: 1UL,
  }
  let state = HNSWState::new(params, @types.Dot, 20)
  // Build a two-node graph; force enter_point to index 0 (ID 1) at level 1
  add_to_hnsw(store, state, 1, [1.0, 0.0])
  add_to_hnsw(store, state, 2, [0.0, 1.0])
  state.enter_point = 0
  state.max_level = 1
  state.level_arr[0] = 1
  // Tombstone the entry point (index 0 = ID 1)
  hnsw_remove(state, @types.VectorId::from_int(1), store)
  // Add ID 10; the inserting node lands at index 2.
  // Without the fix: tombstone[2]=false before find_valid_entry_point runs,
  // so find_valid_entry_point sees index 2 as a valid node and returns it.
  // hnsw_search_layer(entry=2) returns only {2} (no edges yet), neighbors=[],
  // connect_mutually does nothing.  If level_arr[2] > max_level=1 then
  // enter_point is promoted to 2 (disconnected), and ID 2 becomes unreachable.
  // Force level_arr[2] = 2 > max_level=1 to trigger the promotion path.
  // We do this by pre-setting level_arr before the add call executes its sample.
  // Because hnsw_add overwrites level_arr[at] with sample_level(), we instead
  // verify the invariant by checking post-add connectivity for all live nodes.
  add_to_hnsw(store, state, 10, [0.5, 0.5])
  // Manually elevate the new node to level 2 and update enter_point to simulate
  // the worst-case promotion — the fix must hold regardless of sampled level.
  let at10 = store.get_index(@types.VectorId::from_int(10)).unwrap()
  state.level_arr[at10] = 2
  state.max_level = 2
  state.enter_point = at10
  // Now verify: ID 2 (the only pre-existing live node) must still be reachable
  // even though enter_point was just reset to the newly inserted node.
  let r1 = hnsw_search(state, store, [0.0, 1.0], 5, None)
  assert_found(r1, 2)
  assert_not_found(r1, 1)
  // ID 10 must also be reachable
  let r2 = hnsw_search(state, store, [0.5, 0.5], 5, None)
  assert_found(r2, 10)
}
