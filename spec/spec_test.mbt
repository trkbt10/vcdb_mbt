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

// Specification tests for VectorDB
// These tests verify mathematical correctness of vector search with known expected results.

// =============================================================================
// Section 1: Metric Calculation Tests
// Verify that distance/similarity metrics are computed correctly.
// =============================================================================

///|
/// Test: Dot product calculation - exact values
test "spec/metric/dot_exact" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory(
      3,
      metric=@types.Dot,
      strategy=@types.Bruteforce,
    )
    // Vectors with known dot products to query [1, 2, 3]
    // v1 = [1, 0, 0] -> dot = 1*1 + 2*0 + 3*0 = 1.0
    // v2 = [0, 1, 0] -> dot = 1*0 + 2*1 + 3*0 = 2.0
    // v3 = [0, 0, 1] -> dot = 1*0 + 2*0 + 3*1 = 3.0
    // v4 = [1, 1, 1] -> dot = 1*1 + 2*1 + 3*1 = 6.0
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
    let _ = db.add(
      @types.VectorId::from_int(4),
      [1.0, 1.0, 1.0],
      @types.empty_attrs(),
      0L,
    )
    let results = db.search([1.0, 2.0, 3.0], 4, None)
    // Expected order: v4 (6.0) > v3 (3.0) > v2 (2.0) > v1 (1.0)
    inspect(results[0].id.to_int64(), content="4")
    inspect(results[0].score, content="6")
    inspect(results[1].id.to_int64(), content="3")
    inspect(results[1].score, content="3")
    inspect(results[2].id.to_int64(), content="2")
    inspect(results[2].score, content="2")
    inspect(results[3].id.to_int64(), content="1")
    inspect(results[3].score, content="1")
  })
}

///|
/// Test: L2 distance calculation - exact values
test "spec/metric/l2_exact" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory(
      2,
      metric=@types.L2,
      strategy=@types.Bruteforce,
    )
    // Query: [0, 0]
    // v1 = [0, 0] -> L2^2 = 0
    // v2 = [1, 0] -> L2^2 = 1
    // v3 = [0, 2] -> L2^2 = 4
    // v4 = [3, 4] -> L2^2 = 25
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
      [0.0, 2.0],
      @types.empty_attrs(),
      0L,
    )
    let _ = db.add(
      @types.VectorId::from_int(4),
      [3.0, 4.0],
      @types.empty_attrs(),
      0L,
    )
    let results = db.search([0.0, 0.0], 4, None)
    // Expected order by -L2^2: v1 (0) > v2 (-1) > v3 (-4) > v4 (-25)
    inspect(results[0].id.to_int64(), content="1")
    inspect(results[0].score, content="0")
    inspect(results[1].id.to_int64(), content="2")
    inspect(results[1].score, content="-1")
    inspect(results[2].id.to_int64(), content="3")
    inspect(results[2].score, content="-4")
    inspect(results[3].id.to_int64(), content="4")
    inspect(results[3].score, content="-25")
  })
}

///|
/// Test: Cosine similarity - auto-normalization verification
test "spec/metric/cosine_normalization" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory(
      2,
      metric=@types.Cosine,
      strategy=@types.Bruteforce,
    )
    // Vectors with same direction but different magnitudes
    // [1, 0] and [2, 0] should have the same cosine similarity to [1, 0]
    let _ = db.add(
      @types.VectorId::from_int(1),
      [1.0, 0.0],
      @types.empty_attrs(),
      0L,
    )
    let _ = db.add(
      @types.VectorId::from_int(2),
      [2.0, 0.0],
      @types.empty_attrs(),
      0L,
    )
    let _ = db.add(
      @types.VectorId::from_int(3),
      [100.0, 0.0],
      @types.empty_attrs(),
      0L,
    )
    let results = db.search([1.0, 0.0], 3, None)
    // All should have cosine similarity = 1.0 (same direction)
    // Verify they are indistinguishable (all score 1.0)
    inspect(results[0].score, content="1")
    inspect(results[1].score, content="1")
    inspect(results[2].score, content="1")
  })
}

///|
/// Test: Cosine similarity - orthogonal vectors
test "spec/metric/cosine_orthogonal" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory(
      2,
      metric=@types.Cosine,
      strategy=@types.Bruteforce,
    )
    // Orthogonal vectors should have cosine = 0
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
    let results = db.search([1.0, 0.0], 2, None)
    // v1 should be perfect match (cos=1), v2 orthogonal (cos=0)
    inspect(results[0].id.to_int64(), content="1")
    inspect(results[0].score, content="1")
    inspect(results[1].id.to_int64(), content="2")
    inspect(results[1].score, content="0")
  })
}

///|
/// Test: Cosine similarity - opposite vectors
test "spec/metric/cosine_opposite" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory(
      2,
      metric=@types.Cosine,
      strategy=@types.Bruteforce,
    )
    // Opposite vectors should have cosine = -1
    let _ = db.add(
      @types.VectorId::from_int(1),
      [1.0, 0.0],
      @types.empty_attrs(),
      0L,
    )
    let _ = db.add(
      @types.VectorId::from_int(2),
      [-1.0, 0.0],
      @types.empty_attrs(),
      0L,
    )
    let results = db.search([1.0, 0.0], 2, None)
    inspect(results[0].id.to_int64(), content="1")
    inspect(results[0].score, content="1")
    inspect(results[1].id.to_int64(), content="2")
    inspect(results[1].score, content="-1")
  })
}

// =============================================================================
// Section 2: Search Correctness Tests
// Verify that search returns correct results in correct order.
// =============================================================================

///|
/// Test: k=1 returns the single best match
test "spec/search/k1_best_match" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory_bruteforce(3)
    let _ = db.add(
      @types.VectorId::from_int(1),
      [0.9, 0.1, 0.0],
      @types.empty_attrs(),
      0L,
    )
    let _ = db.add(
      @types.VectorId::from_int(2),
      [1.0, 0.0, 0.0],
      @types.empty_attrs(),
      0L,
    ) // Best match
    let _ = db.add(
      @types.VectorId::from_int(3),
      [0.8, 0.2, 0.0],
      @types.empty_attrs(),
      0L,
    )
    let results = db.search([1.0, 0.0, 0.0], 1, None)
    inspect(results.length(), content="1")
    inspect(results[0].id.to_int64(), content="2")
  })
}

///|
/// Test: k > size returns all vectors
test "spec/search/k_exceeds_size" {
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
    let results = db.search([1.0, 0.0], 100, None)
    inspect(results.length(), content="2")
  })
}

///|
/// Test: Search with filter reduces results
test "spec/search/filter_reduces" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory_bruteforce(2)
    for i in 1..<=10 {
      let attrs = @types.empty_attrs()
      attrs.set("even", @types.Bool(i % 2 == 0))
      let _ = db.add(
        @types.VectorId::from_int(i),
        [i.to_double(), 0.0],
        attrs,
        0L,
      )
    }
    let filter = fn(_id : @types.VectorId, attrs : @types.Attrs) -> Bool {
      match attrs.get("even") {
        Some(@types.Bool(b)) => b
        _ => false
      }
    }
    let results = db.search_with_filter([10.0, 0.0], 10, Some(filter))
    inspect(results.length(), content="5")
    // All results should be even IDs
    for hit in results {
      inspect(hit.id.to_int64() % 2L, content="0")
    }
  })
}

///|
/// Test: Results are sorted by score (descending)
test "spec/search/sorted_descending" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory(
      1,
      metric=@types.Dot,
      strategy=@types.Bruteforce,
    )
    // Add in random order
    let _ = db.add(
      @types.VectorId::from_int(3),
      [3.0],
      @types.empty_attrs(),
      0L,
    )
    let _ = db.add(
      @types.VectorId::from_int(1),
      [1.0],
      @types.empty_attrs(),
      0L,
    )
    let _ = db.add(
      @types.VectorId::from_int(5),
      [5.0],
      @types.empty_attrs(),
      0L,
    )
    let _ = db.add(
      @types.VectorId::from_int(2),
      [2.0],
      @types.empty_attrs(),
      0L,
    )
    let _ = db.add(
      @types.VectorId::from_int(4),
      [4.0],
      @types.empty_attrs(),
      0L,
    )
    let results = db.search([1.0], 5, None)
    // Should be sorted by dot product: 5, 4, 3, 2, 1
    inspect(results[0].id.to_int64(), content="5")
    inspect(results[1].id.to_int64(), content="4")
    inspect(results[2].id.to_int64(), content="3")
    inspect(results[3].id.to_int64(), content="2")
    inspect(results[4].id.to_int64(), content="1")
  })
}

// =============================================================================
// Section 3: Algorithm Consistency Tests (Ground Truth Comparison)
// HNSW and IVF should return results consistent with Bruteforce ground truth.
// =============================================================================

///|
/// Test: HNSW top-1 is in Bruteforce top-3 (high recall)
/// Note: HNSW is approximate NN, so 100% top-1 match is not guaranteed
test "spec/recall/hnsw_top1_in_top3" {
  run_async_test(async fn() {
    let bf_db = @vcdb.PersistentDB::in_memory_bruteforce(4)
    let hnsw_db = @vcdb.PersistentDB::in_memory_hnsw(4, metric=@types.Cosine)
    // Add 50 vectors to both
    for i in 0..<50 {
      let v = [
        (i % 5).to_double(),
        ((i + 1) % 5).to_double(),
        ((i + 2) % 5).to_double(),
        ((i + 3) % 5).to_double(),
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
    // Test multiple queries - HNSW top-1 should be in Bruteforce top-3
    let queries = [
      [1.0, 2.0, 3.0, 4.0],
      [4.0, 3.0, 2.0, 1.0],
      [0.0, 0.0, 0.0, 1.0],
      [1.0, 0.0, 0.0, 0.0],
    ]
    let mut matches = 0
    for query in queries {
      let bf_results = bf_db.search(query, 3, None)
      let hnsw_result = hnsw_db.search(query, 1, None)
      let hnsw_top1 = hnsw_result[0].id.to_int64()
      // Check if HNSW top-1 is in BF top-3
      for bf_hit in bf_results {
        if bf_hit.id.to_int64() == hnsw_top1 {
          matches = matches + 1
          break
        }
      }
    }
    // At least 3 of 4 queries should have HNSW top-1 in BF top-3
    inspect(matches >= 3, content="true")
  })
}

///|
/// Test: IVF returns correct results after training
test "spec/recall/ivf_trained_recall" {
  run_async_test(async fn() {
    let bf_db = @vcdb.PersistentDB::in_memory_bruteforce(4)
    let ivf_db = @vcdb.PersistentDB::in_memory_ivf(4, metric=@types.Cosine)
    // Create 3 clear clusters
    for i in 0..<30 {
      let cluster = i / 10
      let v = match cluster {
        0 => [1.0, 0.0, 0.0, 0.0]
        1 => [0.0, 1.0, 0.0, 0.0]
        _ => [0.0, 0.0, 1.0, 0.0]
      }
      let _ = bf_db.add(
        @types.VectorId::from_int(i),
        v,
        @types.empty_attrs(),
        0L,
      )
      let _ = ivf_db.add(
        @types.VectorId::from_int(i),
        v,
        @types.empty_attrs(),
        0L,
      )
    }
    ivf_db.train(iterations=10)
    // Query for cluster 0 center
    let bf_results = bf_db.search([1.0, 0.0, 0.0, 0.0], 10, None)
    let ivf_results = ivf_db.search([1.0, 0.0, 0.0, 0.0], 10, None)
    // IVF should find at least 8/10 of the same results
    let bf_ids : Array[Int64] = bf_results
      .iter()
      .map(fn(h) { h.id.to_int64() })
      .collect()
    let mut overlap = 0
    for hit in ivf_results {
      if bf_ids.contains(hit.id.to_int64()) {
        overlap = overlap + 1
      }
    }
    inspect(overlap >= 8, content="true")
  })
}

///|
/// Test: All strategies find the same best match
test "spec/recall/exact_match_all_strategies" {
  run_async_test(async fn() {
    let bf_db = @vcdb.PersistentDB::in_memory_bruteforce(3)
    let hnsw_db = @vcdb.PersistentDB::in_memory_hnsw(3, metric=@types.Dot)
    let ivf_db = @vcdb.PersistentDB::in_memory_ivf(3, metric=@types.Dot)
    // Add vectors - id=7 is unique exact match for query [10, 0, 0]
    let query = [10.0, 0.0, 0.0]
    for i in 0..<20 {
      let v = if i == 7 {
        [10.0, 0.0, 0.0] // Exact match at id=7, highest dot = 100
      } else {
        // Other vectors have lower dot product with query
        [
          i.to_double() % 5.0,
          (i.to_double() + 1.0) % 5.0,
          (i.to_double() + 2.0) % 5.0,
        ]
      }
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
      let _ = ivf_db.add(
        @types.VectorId::from_int(i),
        v,
        @types.empty_attrs(),
        0L,
      )
    }
    // All should find id=7 as top result (dot = 100, others max dot with [10,0,0] is <50)
    let bf_result = bf_db.find(query, None)
    let hnsw_result = hnsw_db.find(query, None)
    let ivf_result = ivf_db.find(query, None)
    inspect(bf_result.unwrap().id.to_int64(), content="7")
    inspect(hnsw_result.unwrap().id.to_int64(), content="7")
    inspect(ivf_result.unwrap().id.to_int64(), content="7")
  })
}

// =============================================================================
// Section 4: CRUD Consistency Tests
// Verify that CRUD operations maintain data consistency.
// =============================================================================

///|
/// Test: Add then remove then add same ID maintains consistency
test "spec/crud/add_remove_add" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory_bruteforce(2)
    let id = @types.VectorId::from_int(42)
    // Add
    let _ = db.add(id, [1.0, 0.0], @types.empty_attrs(), 0L)
    inspect(db.has(id), content="true")
    let r1 = db.get(id).unwrap()
    inspect(r1.vector[0], content="1")
    // Remove
    let removed = db.remove(id, 0L)
    inspect(removed, content="true")
    inspect(db.has(id), content="false")
    // Re-add with different vector
    let _ = db.add(id, [0.0, 1.0], @types.empty_attrs(), 0L)
    inspect(db.has(id), content="true")
    let r2 = db.get(id).unwrap()
    inspect(r2.vector[0], content="0")
    inspect(r2.vector[1], content="1")
  })
}

///|
/// Test: Upsert preserves search correctness
test "spec/crud/upsert_search_correctness" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory_bruteforce(2)
    // Add vectors
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
    // Initial search: [1,0] should find id=1
    let r1 = db.find([1.0, 0.0], None)
    inspect(r1.unwrap().id.to_int64(), content="1")
    // Upsert id=1 to point in different direction
    db.upsert(
      [(@types.VectorId::from_int(1), [0.0, 1.0], @types.empty_attrs())],
      0L,
    )
    // Now search for [1,0] should NOT find id=1 as best (both point to [0,1])
    // Search for [0,1] should find both equally
    let r2 = db.search([0.0, 1.0], 2, None)
    inspect(r2.length(), content="2")
    // Both should have same score (both are [0,1])
    inspect(r2[0].score, content="1")
    inspect(r2[1].score, content="1")
  })
}

///|
/// Test: Removed vectors don't appear in search
test "spec/crud/remove_excludes_from_search" {
  run_async_test(async fn() {
    // Use Dot metric to distinguish vectors by magnitude
    let db = @vcdb.PersistentDB::in_memory(
      2,
      metric=@types.Dot,
      strategy=@types.Bruteforce,
    )
    for i in 1..<=5 {
      let _ = db.add(
        @types.VectorId::from_int(i),
        [i.to_double(), 0.0],
        @types.empty_attrs(),
        0L,
      )
    }
    // Remove id=5 (would be best match for [1, 0] due to highest dot = 5)
    let _ = db.remove(@types.VectorId::from_int(5), 0L)
    // Search should not return id=5
    let results = db.search([1.0, 0.0], 5, None)
    for hit in results {
      inspect(hit.id.to_int64() != 5L, content="true")
    }
    // Best match should now be id=4 (dot = 4)
    inspect(results[0].id.to_int64(), content="4")
  })
}

// =============================================================================
// Section 5: Edge Cases and Boundary Conditions
// =============================================================================

///|
/// Test: Zero vector handling (L2 metric)
test "spec/edge/zero_vector_l2" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory(
      3,
      metric=@types.L2,
      strategy=@types.Bruteforce,
    )
    // Zero vector should have L2 distance 0 to itself
    let _ = db.add(
      @types.VectorId::from_int(1),
      [0.0, 0.0, 0.0],
      @types.empty_attrs(),
      0L,
    )
    let _ = db.add(
      @types.VectorId::from_int(2),
      [1.0, 0.0, 0.0],
      @types.empty_attrs(),
      0L,
    )
    let results = db.search([0.0, 0.0, 0.0], 2, None)
    inspect(results[0].id.to_int64(), content="1")
    inspect(results[0].score, content="0") // Distance 0
  })
}

///|
/// Test: Very small differences are distinguishable
test "spec/edge/small_differences" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory(
      1,
      metric=@types.Dot,
      strategy=@types.Bruteforce,
    )
    let _ = db.add(
      @types.VectorId::from_int(1),
      [1.0],
      @types.empty_attrs(),
      0L,
    )
    let _ = db.add(
      @types.VectorId::from_int(2),
      [1.0000000001],
      @types.empty_attrs(),
      0L,
    )
    let _ = db.add(
      @types.VectorId::from_int(3),
      [1.00001],
      @types.empty_attrs(),
      0L,
    )
    let results = db.search([1.0], 3, None)
    // Should be ordered by score descending: 3 > 2 > 1
    inspect(results[0].id.to_int64(), content="3")
    inspect(results[1].id.to_int64(), content="2")
    inspect(results[2].id.to_int64(), content="1")
  })
}

///|
/// Test: High-dimensional sparse vectors
test "spec/edge/sparse_high_dim" {
  run_async_test(async fn() {
    let dim = 256
    let db = @vcdb.PersistentDB::in_memory(
      dim,
      metric=@types.Cosine,
      strategy=@types.Bruteforce,
    )
    // Create sparse vectors (only a few non-zero components)
    for i in 0..<10 {
      let v : Array[Double] = Array::make(dim, 0.0)
      v[i] = 1.0 // Single hot encoding
      let _ = db.add(@types.VectorId::from_int(i), v, @types.empty_attrs(), 0L)
    }
    // Query with single hot at position 5
    let query : Array[Double] = Array::make(dim, 0.0)
    query[5] = 1.0
    let results = db.search(query, 1, None)
    // Should find id=5 (exact match)
    inspect(results[0].id.to_int64(), content="5")
    inspect(results[0].score, content="1") // Cosine = 1
  })
}

///|
/// Test: Duplicate vectors (same embedding, different IDs)
test "spec/edge/duplicate_vectors" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory_bruteforce(2)
    // Add same vector with different IDs
    let _ = db.add(
      @types.VectorId::from_int(1),
      [1.0, 0.0],
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
      [1.0, 0.0],
      @types.empty_attrs(),
      0L,
    )
    let results = db.search([1.0, 0.0], 3, None)
    // All should have same score
    inspect(results[0].score, content="1")
    inspect(results[1].score, content="1")
    inspect(results[2].score, content="1")
    // All three IDs should be present
    let ids : Array[Int64] = results
      .iter()
      .map(fn(h) { h.id.to_int64() })
      .collect()
    inspect(ids.contains(1L), content="true")
    inspect(ids.contains(2L), content="true")
    inspect(ids.contains(3L), content="true")
  })
}

///|
/// Test: Empty query handling
test "spec/edge/empty_db_search" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory_bruteforce(3)
    // Search on empty DB
    let results = db.search([1.0, 0.0, 0.0], 10, None)
    inspect(results.length(), content="0")
    // Find on empty DB
    let found = db.find([1.0, 0.0, 0.0], None)
    inspect(found is None, content="true")
  })
}

///|
/// Test: k=0 returns empty results
test "spec/edge/k_zero" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory_bruteforce(2)
    let _ = db.add(
      @types.VectorId::from_int(1),
      [1.0, 0.0],
      @types.empty_attrs(),
      0L,
    )
    let results = db.search([1.0, 0.0], 0, None)
    inspect(results.length(), content="0")
  })
}

// =============================================================================
// Section 6: Serialization Correctness Tests
// Verify that serialize/deserialize preserves all data and search behavior.
// =============================================================================

///|
/// Test: Serialization preserves search results exactly
test "spec/serialization/search_preserved" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory_bruteforce(4)
    // Add vectors
    for i in 0..<20 {
      let v = [
        (i % 4).to_double(),
        ((i + 1) % 4).to_double(),
        ((i + 2) % 4).to_double(),
        ((i + 3) % 4).to_double(),
      ]
      let _ = db.add(@types.VectorId::from_int(i), v, @types.empty_attrs(), 0L)
    }
    // Search before serialization
    let query = [1.0, 2.0, 3.0, 0.0]
    let before = db.search(query, 5, None)
    // Serialize and deserialize
    let bytes = db.serialize_snapshot()
    let db2 = @vcdb.PersistentDB::deserialize(bytes)
    // Search after deserialization
    let after = db2.search(query, 5, None)
    // Results should be identical
    inspect(after.length(), content="5")
    for i in 0..<5 {
      inspect(after[i].id.to_int64() == before[i].id.to_int64(), content="true")
      inspect(
        (after[i].score - before[i].score).abs() < 0.0000000001,
        content="true",
      )
    }
  })
}

///|
/// Test: Serialization preserves attributes
test "spec/serialization/attrs_preserved" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory_bruteforce(2)
    let attrs = @types.empty_attrs()
    attrs.set("name", @types.String("test-vector"))
    attrs.set("count", @types.Int(42L))
    attrs.set("score", @types.Float(3.14159))
    attrs.set("active", @types.Bool(true))
    let _ = db.add(@types.VectorId::from_int(1), [1.0, 0.0], attrs, 0L)
    // Serialize and deserialize
    let db2 = @vcdb.PersistentDB::deserialize(db.serialize_snapshot())
    // Verify attributes
    let record = db2.get(@types.VectorId::from_int(1)).unwrap()
    match record.attrs.get("name") {
      Some(@types.String(s)) => inspect(s, content="test-vector")
      _ => inspect(false, content="true")
    }
    match record.attrs.get("count") {
      Some(@types.Int(n)) => inspect(n, content="42")
      _ => inspect(false, content="true")
    }
    match record.attrs.get("score") {
      Some(@types.Float(f)) =>
        inspect((f - 3.14159).abs() < 0.00001, content="true")
      _ => inspect(false, content="true")
    }
    match record.attrs.get("active") {
      Some(@types.Bool(b)) => inspect(b, content="true")
      _ => inspect(false, content="true")
    }
  })
}

///|
/// Test: HNSW serialization preserves graph structure
test "spec/serialization/hnsw_graph_preserved" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory_hnsw(3, metric=@types.Dot)
    for i in 0..<30 {
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
    // Get search results before
    let query = [1.0, 2.0, 0.0]
    let before = db.search(query, 10, None)
    // Serialize and deserialize
    let db2 = @vcdb.PersistentDB::deserialize(db.serialize_snapshot())
    let after = db2.search(query, 10, None)
    // Top-5 results should be the same (HNSW recall might vary slightly)
    let mut top5_match = 0
    for i in 0..<5 {
      for j in 0..<5 {
        if after[i].id.to_int64() == before[j].id.to_int64() {
          top5_match = top5_match + 1
          break
        }
      }
    }
    // At least 4 of top-5 should match
    inspect(top5_match >= 4, content="true")
  })
}

// =============================================================================
// Section 7: Attribute Filtering Tests
// =============================================================================

///|
/// Test: Complex boolean filter with AND logic
test "spec/filter/and_logic" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory_bruteforce(2)
    for i in 1..<=10 {
      let attrs = @types.empty_attrs()
      attrs.set("value", @types.Int(i.to_int64()))
      attrs.set("even", @types.Bool(i % 2 == 0))
      let _ = db.add(
        @types.VectorId::from_int(i),
        [i.to_double(), 0.0],
        attrs,
        0L,
      )
    }
    // Filter: value >= 5 AND even = true
    // Should match: 6, 8, 10
    let filter = fn(_id : @types.VectorId, attrs : @types.Attrs) -> Bool {
      let value_ok = match attrs.get("value") {
        Some(@types.Int(v)) => v >= 5L
        _ => false
      }
      let even_ok = match attrs.get("even") {
        Some(@types.Bool(b)) => b
        _ => false
      }
      value_ok && even_ok
    }
    let results = db.search_with_filter([10.0, 0.0], 10, Some(filter))
    inspect(results.length(), content="3")
    // Check all results satisfy filter
    for hit in results {
      let id = hit.id.to_int64()
      inspect(id >= 5L && id % 2L == 0L, content="true")
    }
  })
}

///|
/// Test: OR logic filter
test "spec/filter/or_logic" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory_bruteforce(2)
    for i in 1..<=10 {
      let attrs = @types.empty_attrs()
      attrs.set(
        "category",
        @types.String(if i <= 3 { "A" } else if i <= 6 { "B" } else { "C" }),
      )
      let _ = db.add(
        @types.VectorId::from_int(i),
        [i.to_double(), 0.0],
        attrs,
        0L,
      )
    }
    // Filter: category = "A" OR category = "C"
    // Should match: 1,2,3,7,8,9,10 (7 results)
    let filter = fn(_id : @types.VectorId, attrs : @types.Attrs) -> Bool {
      match attrs.get("category") {
        Some(@types.String(s)) => s == "A" || s == "C"
        _ => false
      }
    }
    let results = db.search_with_filter([5.0, 0.0], 10, Some(filter))
    inspect(results.length(), content="7")
  })
}

///|
/// Test: Filter that matches nothing returns empty
test "spec/filter/no_match" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory_bruteforce(2)
    for i in 1..<=5 {
      let attrs = @types.empty_attrs()
      attrs.set("type", @types.String("normal"))
      let _ = db.add(
        @types.VectorId::from_int(i),
        [i.to_double(), 0.0],
        attrs,
        0L,
      )
    }
    // Filter for non-existent type
    let filter = fn(_id : @types.VectorId, attrs : @types.Attrs) -> Bool {
      match attrs.get("type") {
        Some(@types.String(s)) => s == "special"
        _ => false
      }
    }
    let results = db.search_with_filter([3.0, 0.0], 10, Some(filter))
    inspect(results.length(), content="0")
  })
}

// =============================================================================
// Section 8: Stress Tests for Data Integrity
// =============================================================================

///|
/// Test: Interleaved add/remove/search maintains consistency
test "spec/stress/interleaved_operations" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory_bruteforce(2)
    // Add initial vectors
    for i in 1..<=20 {
      let _ = db.add(
        @types.VectorId::from_int(i),
        [i.to_double(), 0.0],
        @types.empty_attrs(),
        0L,
      )
    }
    // Remove some
    for i in [5, 10, 15] {
      let _ = db.remove(@types.VectorId::from_int(i), 0L)
    }
    // Add more
    for i in 21..<=25 {
      let _ = db.add(
        @types.VectorId::from_int(i),
        [i.to_double(), 0.0],
        @types.empty_attrs(),
        0L,
      )
    }
    // Verify size
    inspect(db.size(), content="22") // 20 - 3 + 5 = 22
    // Search should not include removed IDs
    let results = db.search([15.0, 0.0], 25, None)
    for hit in results {
      let id = hit.id.to_int64()
      inspect(id != 5L && id != 10L && id != 15L, content="true")
    }
  })
}

///|
/// Test: Many updates via upsert maintains correctness
test "spec/stress/many_upserts" {
  run_async_test(async fn() {
    // Use Dot metric to avoid normalization
    let db = @vcdb.PersistentDB::in_memory(
      2,
      metric=@types.Dot,
      strategy=@types.Bruteforce,
    )
    let id = @types.VectorId::from_int(1)
    // Add initial
    let _ = db.add(id, [1.0, 0.0], @types.empty_attrs(), 0L)
    // Upsert 50 times
    for i in 1..<=50 {
      db.upsert([(id, [i.to_double(), 0.0], @types.empty_attrs())], 0L)
    }
    // Size should still be 1
    inspect(db.size(), content="1")
    // Vector should have final value
    let record = db.get(id).unwrap()
    inspect(record.vector[0], content="50")
  })
}

///|
/// Test: Large dataset maintains recall
test "spec/stress/large_dataset_recall" {
  run_async_test(async fn() {
    let bf_db = @vcdb.PersistentDB::in_memory_bruteforce(8)
    let hnsw_db = @vcdb.PersistentDB::in_memory_hnsw(8, metric=@types.Cosine)
    // Add 500 vectors in batches to avoid stack overflow from coroutine frames
    let bf_points : Array[(@types.VectorId, Array[Double], @types.Attrs)] = []
    let hnsw_points : Array[(@types.VectorId, Array[Double], @types.Attrs)] = []
    for i in 0..<500 {
      let v : Array[Double] = []
      for j in 0..<8 {
        v.push(((i * 7 + j * 3) % 100).to_double() / 100.0)
      }
      bf_points.push((@types.VectorId::from_int(i), v, @types.empty_attrs()))
      hnsw_points.push((@types.VectorId::from_int(i), v, @types.empty_attrs()))
    }
    bf_db.upsert(bf_points, 0L)
    hnsw_db.upsert(hnsw_points, 0L)
    // Test recall for top-10
    let query = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8]
    let bf_results = bf_db.search(query, 10, None)
    let hnsw_results = hnsw_db.search(query, 10, None)
    // HNSW should achieve at least 70% recall
    let bf_ids : Array[Int64] = bf_results
      .iter()
      .map(fn(h) { h.id.to_int64() })
      .collect()
    let mut overlap = 0
    for hit in hnsw_results {
      if bf_ids.contains(hit.id.to_int64()) {
        overlap = overlap + 1
      }
    }
    inspect(overlap >= 7, content="true")
  })
}

// =============================================================================
// Section 9: HNSW-Specific Tests
// =============================================================================

///|
/// Test: HNSW tombstone exclusion in search
test "spec/hnsw/tombstone_exclusion" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory_hnsw(2, metric=@types.Dot)
    for i in 1..<=10 {
      let _ = db.add(
        @types.VectorId::from_int(i),
        [i.to_double(), 0.0],
        @types.empty_attrs(),
        0L,
      )
    }
    // Remove the best match for query [10, 0]
    let _ = db.remove(@types.VectorId::from_int(10), 0L)
    // Search should return id=9 as best (not 10)
    let results = db.search([10.0, 0.0], 1, None)
    inspect(results[0].id.to_int64(), content="9")
  })
}

///|
/// Test: HNSW re-add after tombstone
test "spec/hnsw/readd_after_tombstone" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory_hnsw(2, metric=@types.Dot)
    let id = @types.VectorId::from_int(1)
    // Add, remove, re-add with different vector
    let _ = db.add(id, [1.0, 0.0], @types.empty_attrs(), 0L)
    let _ = db.remove(id, 0L)
    let _ = db.add(id, [0.0, 10.0], @types.empty_attrs(), 0L)
    // Search for [0, 10] should find id=1
    let results = db.search([0.0, 10.0], 1, None)
    inspect(results[0].id.to_int64(), content="1")
    // Search for [1, 0] should NOT find id=1 as best
    let _ = db.add(
      @types.VectorId::from_int(2),
      [1.0, 0.0],
      @types.empty_attrs(),
      0L,
    )
    let results2 = db.search([1.0, 0.0], 1, None)
    inspect(results2[0].id.to_int64(), content="2")
  })
}

// =============================================================================
// Section 10: IVF-Specific Tests
// =============================================================================

///|
/// Test: IVF untrained still works (bruteforce fallback)
test "spec/ivf/untrained_search" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory_ivf(3, metric=@types.Dot)
    for i in 1..<=10 {
      let _ = db.add(
        @types.VectorId::from_int(i),
        [i.to_double(), 0.0, 0.0],
        @types.empty_attrs(),
        0L,
      )
    }
    // Search without training
    let results = db.search([10.0, 0.0, 0.0], 3, None)
    inspect(results.length(), content="3")
    // Should still find best matches (linear scan fallback)
    inspect(results[0].id.to_int64(), content="10")
  })
}

///|
/// Test: IVF training improves cluster assignment
test "spec/ivf/training_clusters" {
  run_async_test(async fn() {
    let db = @vcdb.PersistentDB::in_memory_ivf(4, metric=@types.Cosine)
    // Create 4 distinct clusters
    for i in 0..<40 {
      let cluster = i / 10
      let v = match cluster {
        0 => [1.0, 0.0, 0.0, 0.0]
        1 => [0.0, 1.0, 0.0, 0.0]
        2 => [0.0, 0.0, 1.0, 0.0]
        _ => [0.0, 0.0, 0.0, 1.0]
      }
      let _ = db.add(@types.VectorId::from_int(i), v, @types.empty_attrs(), 0L)
    }
    db.train(iterations=15)
    // Query for cluster 2 center - should find cluster 2 vectors (ids 20-29)
    let results = db.search([0.0, 0.0, 1.0, 0.0], 5, None)
    let mut cluster2_count = 0
    for hit in results {
      let id = hit.id.to_int64()
      if id >= 20L && id < 30L {
        cluster2_count = cluster2_count + 1
      }
    }
    // At least 4 of top-5 should be from cluster 2
    inspect(cluster2_count >= 4, content="true")
  })
}
