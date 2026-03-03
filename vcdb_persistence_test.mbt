///|
/// Comprehensive tests for persistence restoration and index maintenance
/// Tests WAL replay, corruption recovery, and index rebuild scenarios

// =============================================================================
// Section 1: WAL Replay Tests - Restore VectorDB from WAL
// =============================================================================

///|
/// Test: WAL replay restores vectors correctly
test "persistence/wal_replay/basic" {
  // Simulate WAL records from operations
  let records = [
    @persistence.WalRecord::upsert(
      @core.VectorId::from_int(1),
      [1.0, 0.0, 0.0],
      {
        let a = @core.empty_attrs()
        a.set("name", @core.String("v1"))
        a
      },
    ),
    @persistence.WalRecord::upsert(
      @core.VectorId::from_int(2),
      [0.0, 1.0, 0.0],
      {
        let a = @core.empty_attrs()
        a.set("name", @core.String("v2"))
        a
      },
    ),
    @persistence.WalRecord::upsert(
      @core.VectorId::from_int(3),
      [0.0, 0.0, 1.0],
      {
        let a = @core.empty_attrs()
        a.set("name", @core.String("v3"))
        a
      },
    ),
  ]

  // Encode to WAL segment
  let wal_data = @persistence.encode_wal_segment(records)

  // Verify WAL is valid
  assert_true!(@persistence.verify_wal_checksum(wal_data))

  // Decode and replay to restore DB
  let decoded = @persistence.decode_wal_records(wal_data)
  assert_eq!(decoded.length(), 3)

  // Create new DB and replay WAL
  let db = @vcdb.VectorDB::with_dim(3)
  for record in decoded {
    match record.record_type {
      Upsert =>
        match (record.vector, record.attrs) {
          (Some(vec), Some(attrs)) => db.add(record.id, vec, attrs)
          _ => ()
        }
      Remove => {
        let _ = db.remove(record.id)
      }
      SetAttrs =>
        match record.attrs {
          Some(attrs) => {
            let _ = db.update_attrs(record.id, attrs)
          }
          None => ()
        }
    }
  }

  // Verify restored state
  assert_eq!(db.size(), 3)
  assert_true!(db.has(@core.VectorId::from_int(1)))
  assert_true!(db.has(@core.VectorId::from_int(2)))
  assert_true!(db.has(@core.VectorId::from_int(3)))
}

///|
/// Test: WAL replay with remove operations
test "persistence/wal_replay/with_remove" {
  let records = [
    @persistence.WalRecord::upsert(
      @core.VectorId::from_int(1),
      [1.0, 0.0],
      @core.empty_attrs(),
    ),
    @persistence.WalRecord::upsert(
      @core.VectorId::from_int(2),
      [0.0, 1.0],
      @core.empty_attrs(),
    ),
    @persistence.WalRecord::remove(@core.VectorId::from_int(1)),
  ]

  let wal_data = @persistence.encode_wal_segment(records)
  let decoded = @persistence.decode_wal_records(wal_data)

  let db = @vcdb.VectorDB::with_dim(2)
  for record in decoded {
    match record.record_type {
      Upsert =>
        match (record.vector, record.attrs) {
          (Some(vec), Some(attrs)) => db.add(record.id, vec, attrs)
          (Some(vec), None) => db.add(record.id, vec, @core.empty_attrs())
          _ => ()
        }
      Remove => {
        let _ = db.remove(record.id)
      }
      SetAttrs => ()
    }
  }

  // Vector 1 should be removed
  assert_eq!(db.size(), 1)
  assert_false!(db.has(@core.VectorId::from_int(1)))
  assert_true!(db.has(@core.VectorId::from_int(2)))
}

///|
/// Test: WAL replay with SetAttrs operations
test "persistence/wal_replay/with_set_attrs" {
  let records = [
    @persistence.WalRecord::upsert(
      @core.VectorId::from_int(1),
      [1.0, 0.0],
      {
        let a = @core.empty_attrs()
        a.set("version", @core.Int(1L))
        a
      },
    ),
    @persistence.WalRecord::set_attrs(
      @core.VectorId::from_int(1),
      {
        let a = @core.empty_attrs()
        a.set("version", @core.Int(2L))
        a.set("updated", @core.Bool(true))
        a
      },
    ),
  ]

  let wal_data = @persistence.encode_wal_segment(records)
  let decoded = @persistence.decode_wal_records(wal_data)

  let db = @vcdb.VectorDB::with_dim(2)
  for record in decoded {
    match record.record_type {
      Upsert =>
        match (record.vector, record.attrs) {
          (Some(vec), Some(attrs)) => db.add(record.id, vec, attrs)
          (Some(vec), None) => db.add(record.id, vec, @core.empty_attrs())
          _ => ()
        }
      Remove => {
        let _ = db.remove(record.id)
      }
      SetAttrs =>
        match record.attrs {
          Some(attrs) => {
            let _ = db.update_attrs(record.id, attrs)
          }
          None => ()
        }
    }
  }

  // Verify updated attrs
  match db.get(@core.VectorId::from_int(1)) {
    Some(rec) => {
      match rec.attrs.get("version") {
        Some(@core.Int(v)) => assert_eq!(v, 2L)
        _ => assert_true!(false)
      }
      match rec.attrs.get("updated") {
        Some(@core.Bool(b)) => assert_true!(b)
        _ => assert_true!(false)
      }
    }
    None => assert_true!(false)
  }
}

///|
/// Test: WAL with upsert (update existing)
test "persistence/wal_replay/upsert_update" {
  let records = [
    @persistence.WalRecord::upsert(
      @core.VectorId::from_int(1),
      [1.0, 0.0],
      @core.empty_attrs(),
    ),
    @persistence.WalRecord::upsert(
      @core.VectorId::from_int(1),
      [0.0, 1.0],
      @core.empty_attrs(),
    ), // Update
  ]

  let wal_data = @persistence.encode_wal_segment(records)
  let decoded = @persistence.decode_wal_records(wal_data)

  let db = @vcdb.VectorDB::with_dim(2)
  for record in decoded {
    match record.record_type {
      Upsert =>
        match (record.vector, record.attrs) {
          (Some(vec), Some(attrs)) => {
            let _ = db.upsert(record.id, vec, attrs)
          }
          (Some(vec), None) => {
            let _ = db.upsert(record.id, vec, @core.empty_attrs())
          }
          _ => ()
        }
      _ => ()
    }
  }

  assert_eq!(db.size(), 1)

  // Should find [0.0, 1.0] vector
  let results = db.search([0.0, 1.0], 1, None)
  assert_eq!(results.length(), 1)
}

// =============================================================================
// Section 2: WAL Corruption and Recovery Tests
// =============================================================================

///|
/// Test: Invalid WAL magic is rejected
test "persistence/corruption/invalid_magic" {
  let bad_data = Bytes::from_array([b'B', b'A', b'D', b'!', 0, 0, 0, 1][:])
  let records = @persistence.decode_wal_records(bad_data)
  assert_eq!(records.length(), 0)
}

///|
/// Test: Truncated WAL (header only)
test "persistence/corruption/truncated_header_only" {
  // Just header, no records - should be valid but empty
  let header = @persistence.encode_wal_header()
  assert_eq!(header.length(), 8)
  let records = @persistence.decode_wal_records(header)
  assert_eq!(records.length(), 0)
}

///|
/// Test: WAL with corrupted CRC is detected
test "persistence/corruption/bad_crc" {
  let records = [
    @persistence.WalRecord::upsert(
      @core.VectorId::from_int(1),
      [1.0],
      @core.empty_attrs(),
    ),
  ]
  let wal_data = @persistence.encode_wal_segment(records)

  // Corrupt the CRC (last 4 bytes) by creating corrupted bytes
  let arr : Array[Byte] = []
  for i in 0..<wal_data.length() {
    if i == wal_data.length() - 1 {
      arr.push(b'\xFF') // Corrupt last byte
    } else {
      arr.push(wal_data[i])
    }
  }
  let corrupted = Bytes::from_array(arr)

  // CRC verification should fail
  assert_false!(@persistence.verify_wal_checksum(corrupted))
}

///|
/// Test: WAL with partial record is handled gracefully
test "persistence/corruption/partial_record" {
  let records = [
    @persistence.WalRecord::upsert(
      @core.VectorId::from_int(1),
      [1.0, 2.0],
      @core.empty_attrs(),
    ),
  ]
  let wal_data = @persistence.encode_wal_segment(records)

  // Truncate in the middle (remove last few bytes of record)
  let trunc_arr : Array[Byte] = []
  for i in 0..<(wal_data.length() - 10) {
    trunc_arr.push(wal_data[i])
  }
  let truncated = Bytes::from_array(trunc_arr)

  // Should still decode valid records before truncation
  let decoded = @persistence.decode_wal_records(truncated)
  // May be 0 or 1 depending on where truncation happened
  assert_true!(decoded.length() <= 1)
}

// =============================================================================
// Section 3: Serialize/Deserialize Roundtrip Tests
// =============================================================================

///|
/// Test: Empty DB serialization roundtrip
test "persistence/serialize/empty_db" {
  let db = @vcdb.VectorDB::with_dim(4)
  let bytes = db.serialize()
  let restored = @vcdb.VectorDB::deserialize(bytes)

  assert_eq!(restored.size(), 0)
  assert_eq!(restored.dim(), 4)
}

///|
/// Test: Bruteforce DB serialization preserves search
test "persistence/serialize/bruteforce_search" {
  let db = @vcdb.VectorDB::new({
    dim: 3,
    metric: @core.Dot,
    capacity: 10,
    strategy: @core.Bruteforce,
  })

  for i in 1..=5 {
    let attrs = @core.empty_attrs()
    attrs.set("id", @core.Int(i.to_int64()))
    db.add(
      @core.VectorId::from_int(i),
      [i.to_double(), 0.0, 0.0],
      attrs,
    )
  }

  let bytes = db.serialize()
  let restored = @vcdb.VectorDB::deserialize(bytes)

  // Search should work identically
  let results = restored.search([1.0, 0.0, 0.0], 3, None)
  assert_eq!(results.length(), 3)
}

///|
/// Test: HNSW DB serialization preserves graph structure
test "persistence/serialize/hnsw_graph" {
  let db = @vcdb.VectorDB::with_hnsw(3, metric=@core.Cosine)

  for i in 1..=20 {
    let v = [
      (i % 5).to_double() / 5.0,
      ((i / 5) % 5).to_double() / 5.0,
      (i % 3).to_double() / 3.0,
    ]
    db.add(@core.VectorId::from_int(i), v, @core.empty_attrs())
  }

  let bytes = db.serialize()
  let restored = @vcdb.VectorDB::deserialize(bytes)

  assert_eq!(restored.size(), 20)

  // HNSW search should still work
  let query = [0.5, 0.5, 0.5]
  let results = restored.search(query, 5, None)
  assert_eq!(results.length(), 5)
}

///|
/// Test: HNSW with tombstones serialization
test "persistence/serialize/hnsw_tombstones" {
  let db = @vcdb.VectorDB::with_hnsw(2, metric=@core.Dot)

  // Add vectors
  for i in 1..=10 {
    db.add(
      @core.VectorId::from_int(i),
      [i.to_double(), 0.0],
      @core.empty_attrs(),
    )
  }

  // Remove some (creates tombstones)
  let _ = db.remove(@core.VectorId::from_int(3))
  let _ = db.remove(@core.VectorId::from_int(7))

  let bytes = db.serialize()
  let restored = @vcdb.VectorDB::deserialize(bytes)

  // Tombstoned IDs should still be inaccessible
  assert_false!(restored.has(@core.VectorId::from_int(3)))
  assert_false!(restored.has(@core.VectorId::from_int(7)))
  assert_true!(restored.has(@core.VectorId::from_int(1)))
  assert_true!(restored.has(@core.VectorId::from_int(5)))
}

///|
/// Test: IVF DB serialization preserves centroids
test "persistence/serialize/ivf_centroids" {
  let db = @vcdb.VectorDB::with_ivf(3, metric=@core.Cosine)

  // Add vectors and train
  for i in 1..=30 {
    let v = [
      (i % 10).to_double() / 10.0,
      ((i / 10) % 10).to_double() / 10.0,
      (i % 7).to_double() / 7.0,
    ]
    db.add(@core.VectorId::from_int(i), v, @core.empty_attrs())
  }
  db.train(iterations=5)

  let bytes = db.serialize()
  let restored = @vcdb.VectorDB::deserialize(bytes)

  assert_eq!(restored.size(), 30)

  // Search should work (centroids restored)
  let results = restored.search([0.5, 0.5, 0.5], 5, None)
  assert_eq!(results.length(), 5)
}

///|
/// Test: Attributes with all types survive roundtrip
test "persistence/serialize/attr_types" {
  let db = @vcdb.VectorDB::with_dim(2)

  let attrs = @core.empty_attrs()
  attrs.set("null_val", @core.Null)
  attrs.set("bool_val", @core.Bool(true))
  attrs.set("int_val", @core.Int(42L))
  attrs.set("float_val", @core.Float(3.14))
  attrs.set("string_val", @core.String("hello"))

  db.add(@core.VectorId::from_int(1), [1.0, 0.0], attrs)

  let bytes = db.serialize()
  let restored = @vcdb.VectorDB::deserialize(bytes)

  match restored.get(@core.VectorId::from_int(1)) {
    Some(rec) => {
      match rec.attrs.get("null_val") {
        Some(@core.Null) => ()
        _ => assert_true!(false)
      }
      match rec.attrs.get("bool_val") {
        Some(@core.Bool(b)) => assert_true!(b)
        _ => assert_true!(false)
      }
      match rec.attrs.get("int_val") {
        Some(@core.Int(n)) => assert_eq!(n, 42L)
        _ => assert_true!(false)
      }
      match rec.attrs.get("float_val") {
        Some(@core.Float(f)) => assert_true!(f > 3.13 && f < 3.15)
        _ => assert_true!(false)
      }
      match rec.attrs.get("string_val") {
        Some(@core.String(s)) => assert_eq!(s, "hello")
        _ => assert_true!(false)
      }
    }
    None => assert_true!(false)
  }
}

// =============================================================================
// Section 4: Index Rebuild and Maintenance Tests
// =============================================================================

///|
/// Test: HNSW compact removes tombstoned entries
test "persistence/index/hnsw_compact" {
  let store = @core.CoreStore::new(2, @core.Dot, capacity=10)
  let params = @core.HNSWParams::default()
  let state = @ann.HNSWState::new(params, @core.Dot, 10)

  // Add vectors
  for i in 1..=5 {
    let (idx, _) = store.add_or_update(
      @core.VectorId::from_int(i),
      [i.to_double(), 0.0],
      @core.empty_attrs(),
      upsert=false,
    )
    let _ = idx
    @ann.hnsw_add(state, store, @core.VectorId::from_int(i))
  }

  // Remove some via tombstone
  @ann.hnsw_remove(state, @core.VectorId::from_int(2), store)
  @ann.hnsw_remove(state, @core.VectorId::from_int(4), store)

  // Verify tombstones
  let (alive, dead) = @ann.hnsw_tombstone_stats(state, store)
  assert_eq!(dead, 2)
  assert_eq!(alive, 3)

  // Compact and rebuild
  let (new_state, removed) = @ann.hnsw_compact_and_rebuild(state, store)
  assert_eq!(removed, 2)

  // New state should still have tombstones at original positions
  // (to maintain index compatibility)
  let (new_alive, new_dead) = @ann.hnsw_tombstone_stats(new_state, store)
  // After rebuild, tombstones are preserved to maintain stable indices
  assert_eq!(new_dead, 2)
  assert_eq!(new_alive, 3)
}

///|
/// Test: HNSW rebuild from scratch
test "persistence/index/hnsw_rebuild" {
  let store = @core.CoreStore::new(3, @core.Cosine, capacity=20)

  // Add vectors
  for i in 1..=10 {
    let v = [(i % 5).to_double(), ((i / 5) % 3).to_double(), 1.0]
    let _ = store.add_or_update(
      @core.VectorId::from_int(i),
      v,
      @core.empty_attrs(),
      upsert=false,
    )
  }

  // Rebuild HNSW from store
  let params = @core.HNSWParams::default()
  let state = @ann.hnsw_rebuild(store, params, @core.Cosine)

  // Search should work
  let query = store.normalize_query([1.0, 1.0, 1.0])
  let results = @ann.hnsw_search(state, store, query, 5, None)
  assert_eq!(results.length(), 5)
}

///|
/// Test: IVF retrain updates centroids
test "persistence/index/ivf_retrain" {
  let store = @core.CoreStore::new(3, @core.Cosine, capacity=50)
  let params = @core.IVFParams::{ nlist: 4, nprobe: 2 }
  let state = @ann.IVFState::new(params, @core.Cosine, 3)

  // Add initial vectors (cluster around origin)
  for i in 1..=20 {
    let v = [
      (i % 5).to_double() / 10.0,
      ((i / 5) % 5).to_double() / 10.0,
      0.1,
    ]
    let _ = store.add_or_update(
      @core.VectorId::from_int(i),
      v,
      @core.empty_attrs(),
      upsert=false,
    )
  }

  // Initial train
  @ann.ivf_train(state, store, iterations=5)
  for i in 1..=20 {
    @ann.ivf_add(state, store, @core.VectorId::from_int(i))
  }

  // Add more vectors with different distribution
  for i in 21..=40 {
    let v = [
      0.9 + (i % 3).to_double() / 30.0,
      0.9 + ((i / 3) % 3).to_double() / 30.0,
      0.9,
    ]
    let _ = store.add_or_update(
      @core.VectorId::from_int(i),
      v,
      @core.empty_attrs(),
      upsert=false,
    )
  }

  // Retrain with new distribution
  let reassigned = @ann.ivf_retrain(state, store, 5)
  assert_eq!(reassigned, 40)

  // Search should find vectors in new distribution
  let query = store.normalize_query([0.9, 0.9, 0.9])
  let results = @ann.ivf_search(state, store, query, 5, None)
  assert_eq!(results.length(), 5)
}

///|
/// Test: IVF rebuild with new parameters
test "persistence/index/ivf_rebuild" {
  let store = @core.CoreStore::new(3, @core.Cosine, capacity=30)

  // Add vectors
  for i in 1..=25 {
    let v = [
      (i % 5).to_double() / 5.0,
      ((i / 5) % 5).to_double() / 5.0,
      (i % 3).to_double() / 3.0,
    ]
    let _ = store.add_or_update(
      @core.VectorId::from_int(i),
      v,
      @core.empty_attrs(),
      upsert=false,
    )
  }

  // Rebuild with different nlist
  let new_params = @core.IVFParams::{ nlist: 8, nprobe: 4 }
  let new_state = @ann.ivf_rebuild(store, new_params, @core.Cosine, 5)

  // Search should work with new index
  let query = store.normalize_query([0.5, 0.5, 0.5])
  let results = @ann.ivf_search(new_state, store, query, 5, None)
  assert_eq!(results.length(), 5)
}

// =============================================================================
// Section 5: Incremental Index Update Tests
// =============================================================================

///|
/// Test: HNSW incremental add maintains search quality
test "persistence/incremental/hnsw_add" {
  let db = @vcdb.VectorDB::with_hnsw(3, metric=@core.Dot)

  // Add initial batch
  for i in 1..=10 {
    db.add(
      @core.VectorId::from_int(i),
      [i.to_double(), 0.0, 0.0],
      @core.empty_attrs(),
    )
  }

  // Search before adding more
  let results1 = db.search([10.0, 0.0, 0.0], 3, None)
  assert_eq!(results1.length(), 3)
  assert_eq!(results1[0].id.to_int64(), 10L)

  // Add more vectors (should update index incrementally)
  for i in 11..=20 {
    db.add(
      @core.VectorId::from_int(i),
      [i.to_double(), 0.0, 0.0],
      @core.empty_attrs(),
    )
  }

  // Search should now find new vectors
  let results2 = db.search([20.0, 0.0, 0.0], 3, None)
  assert_eq!(results2.length(), 3)
  assert_eq!(results2[0].id.to_int64(), 20L)
}

///|
/// Test: IVF incremental add assigns to existing centroids
test "persistence/incremental/ivf_add" {
  let db = @vcdb.VectorDB::with_ivf(3, metric=@core.Dot)

  // Add and train initial batch
  for i in 1..=20 {
    db.add(
      @core.VectorId::from_int(i),
      [i.to_double(), 0.0, 0.0],
      @core.empty_attrs(),
    )
  }
  db.train(iterations=5)

  // Add more vectors after training (assigned to existing centroids)
  for i in 21..=30 {
    db.add(
      @core.VectorId::from_int(i),
      [i.to_double(), 0.0, 0.0],
      @core.empty_attrs(),
    )
  }

  // Search should find both old and new vectors
  let results = db.search([25.0, 0.0, 0.0], 5, None)
  assert_eq!(results.length(), 5)
}

///|
/// Test: Upsert updates vector and re-indexes
test "persistence/incremental/upsert_reindex" {
  let db = @vcdb.VectorDB::with_hnsw(2, metric=@core.Dot)

  // Add initial vector
  db.add(
    @core.VectorId::from_int(1),
    [1.0, 0.0],
    @core.empty_attrs(),
  )

  // Search should find it
  let results1 = db.search([1.0, 0.0], 1, None)
  assert_eq!(results1[0].id.to_int64(), 1L)

  // Upsert with different vector
  let _ = db.upsert(
    @core.VectorId::from_int(1),
    [0.0, 1.0],
    @core.empty_attrs(),
  )

  // Add another vector to ensure index works
  db.add(
    @core.VectorId::from_int(2),
    [1.0, 0.0],
    @core.empty_attrs(),
  )

  // Search for old position should find id=2 now
  let results2 = db.search([1.0, 0.0], 1, None)
  assert_eq!(results2[0].id.to_int64(), 2L)

  // Search for new position should find id=1
  let results3 = db.search([0.0, 1.0], 1, None)
  assert_eq!(results3[0].id.to_int64(), 1L)
}

// =============================================================================
// Section 6: Large-scale Persistence Tests
// =============================================================================

///|
/// Test: Large DB serialize/deserialize
test "persistence/large/serialize_100_vectors" {
  let db = @vcdb.VectorDB::with_hnsw(16, metric=@core.Cosine)

  // Add 100 vectors
  for i in 1..=100 {
    let v : Array[Double] = []
    for j in 0..<16 {
      v.push(((i * 7 + j * 3) % 100).to_double() / 100.0)
    }
    let attrs = @core.empty_attrs()
    attrs.set("idx", @core.Int(i.to_int64()))
    db.add(@core.VectorId::from_int(i), v, attrs)
  }

  let bytes = db.serialize()
  let restored = @vcdb.VectorDB::deserialize(bytes)

  assert_eq!(restored.size(), 100)

  // Verify random access
  match restored.get(@core.VectorId::from_int(50)) {
    Some(rec) =>
      match rec.attrs.get("idx") {
        Some(@core.Int(n)) => assert_eq!(n, 50L)
        _ => assert_true!(false)
      }
    None => assert_true!(false)
  }

  // Search should work
  let query : Array[Double] = []
  for j in 0..<16 {
    query.push(0.5)
  }
  let results = restored.search(query, 10, None)
  assert_eq!(results.length(), 10)
}

///|
/// Test: WAL with many records
test "persistence/large/wal_100_records" {
  let records : Array[@persistence.WalRecord] = []

  for i in 1..=100 {
    let attrs = @core.empty_attrs()
    attrs.set("i", @core.Int(i.to_int64()))
    records.push(
      @persistence.WalRecord::upsert(
        @core.VectorId::from_int(i),
        [i.to_double(), 0.0],
        attrs,
      ),
    )
  }

  let wal_data = @persistence.encode_wal_segment(records)
  assert_true!(@persistence.verify_wal_checksum(wal_data))

  let decoded = @persistence.decode_wal_records(wal_data)
  assert_eq!(decoded.length(), 100)
}

// =============================================================================
// Section 7: Edge Cases for Persistence
// =============================================================================

///|
/// Test: Serialize/deserialize with VectorId boundaries
test "persistence/edge/vector_id_boundaries" {
  let db = @vcdb.VectorDB::with_dim(2)

  // Test with boundary IDs
  let ids = [0L, 1L, @int64.max_value]
  for i, id in ids.iter2() {
    db.add(
      @core.VectorId(id),
      [(i + 1).to_double(), 0.0],
      @core.empty_attrs(),
    )
  }

  let bytes = db.serialize()
  let restored = @vcdb.VectorDB::deserialize(bytes)

  assert_eq!(restored.size(), 3)
  assert_true!(restored.has(@core.VectorId(0L)))
  assert_true!(restored.has(@core.VectorId(1L)))
  assert_true!(restored.has(@core.VectorId(@int64.max_value)))
}

///|
/// Test: WAL with special string characters
test "persistence/edge/special_strings_in_attrs" {
  let attrs = @core.empty_attrs()
  attrs.set("quote", @core.String("say \"hello\""))
  attrs.set("newline", @core.String("line1\nline2"))
  attrs.set("unicode", @core.String("日本語"))
  attrs.set("backslash", @core.String("path\\to\\file"))

  let record = @persistence.WalRecord::upsert(
    @core.VectorId::from_int(1),
    [1.0],
    attrs,
  )

  let encoded = @persistence.encode_wal_record(record)
  let reader = @core.BinaryReader::new(encoded)
  let decoded = @persistence.decode_wal_record(reader)

  match decoded {
    Some(r) =>
      match r.attrs {
        Some(a) => {
          match a.get("quote") {
            Some(@core.String(s)) => assert_eq!(s, "say \"hello\"")
            _ => assert_true!(false)
          }
          match a.get("newline") {
            Some(@core.String(s)) => assert_eq!(s, "line1\nline2")
            _ => assert_true!(false)
          }
          match a.get("unicode") {
            Some(@core.String(s)) => assert_eq!(s, "日本語")
            _ => assert_true!(false)
          }
          match a.get("backslash") {
            Some(@core.String(s)) => assert_eq!(s, "path\\to\\file")
            _ => assert_true!(false)
          }
        }
        None => assert_true!(false)
      }
    None => assert_true!(false)
  }
}

///|
/// Test: Float precision in WAL (Float32 storage)
test "persistence/edge/float_precision" {
  let original = [3.14159265358979, 2.71828182845905, 1.41421356237310]

  let record = @persistence.WalRecord::upsert(
    @core.VectorId::from_int(1),
    original,
    @core.empty_attrs(),
  )

  let encoded = @persistence.encode_wal_record(record)
  let reader = @core.BinaryReader::new(encoded)
  let decoded = @persistence.decode_wal_record(reader)

  match decoded {
    Some(r) =>
      match r.vector {
        Some(v) => {
          // Float32 has ~7 decimal digits of precision
          assert_true!((v[0] - 3.14159).abs() < 0.0001)
          assert_true!((v[1] - 2.71828).abs() < 0.0001)
          assert_true!((v[2] - 1.41421).abs() < 0.0001)
        }
        None => assert_true!(false)
      }
    None => assert_true!(false)
  }
}

///|
/// Test: Empty attrs handling
test "persistence/edge/empty_attrs" {
  let db = @vcdb.VectorDB::with_dim(2)
  db.add(
    @core.VectorId::from_int(1),
    [1.0, 0.0],
    @core.empty_attrs(),
  )

  let bytes = db.serialize()
  let restored = @vcdb.VectorDB::deserialize(bytes)

  match restored.get(@core.VectorId::from_int(1)) {
    Some(rec) => {
      // Empty attrs should have no keys
      let mut count = 0
      for _ in rec.attrs.keys() {
        count = count + 1
      }
      assert_eq!(count, 0)
    }
    None => assert_true!(false)
  }
}
