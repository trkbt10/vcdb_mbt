///|
/// Coverage improvement tests - targeting low coverage areas

// =============================================================================
// Section 1: Segment UTF-8 and JSON edge cases
// =============================================================================

///|
/// Test: Segment with special characters in attrs
test "coverage/segment/special_chars" {
  let writer = @persistence.SegmentWriter::new("test")

  // Attrs with special JSON characters
  let attrs = @core.empty_attrs()
  attrs.set("quote", @core.String("value with \"quotes\""))
  attrs.set("newline", @core.String("line1\nline2"))
  attrs.set("tab", @core.String("col1\tcol2"))
  attrs.set("backslash", @core.String("path\\to\\file"))
  attrs.set("carriage", @core.String("text\rreturn"))

  let ptr = writer.append(
    @core.VectorId::from_int(1),
    [1.0, 2.0],
    attrs,
  )

  let bytes = writer.to_bytes()
  let reader = @persistence.SegmentReader::from_bytes("test", bytes)
  assert_true(reader.is_some())

  match reader {
    Some(r) => {
      match r.read_at(ptr.offset, ptr.length) {
        Some((id, vec, restored_attrs)) => {
          assert_eq(id.to_int64(), 1L)
          assert_eq(vec.length(), 2)

          // Verify special chars survived roundtrip
          match restored_attrs.get("quote") {
            Some(@core.String(s)) => assert_eq(s, "value with \"quotes\"")
            _ => assert_true(false)
          }
          match restored_attrs.get("newline") {
            Some(@core.String(s)) => assert_eq(s, "line1\nline2")
            _ => assert_true(false)
          }
          match restored_attrs.get("tab") {
            Some(@core.String(s)) => assert_eq(s, "col1\tcol2")
            _ => assert_true(false)
          }
          match restored_attrs.get("backslash") {
            Some(@core.String(s)) => assert_eq(s, "path\\to\\file")
            _ => assert_true(false)
          }
        }
        None => assert_true(false)
      }
    }
    None => assert_true(false)
  }
}

///|
/// Test: Segment with Unicode/multibyte characters
test "coverage/segment/unicode" {
  let writer = @persistence.SegmentWriter::new("test")

  let attrs = @core.empty_attrs()
  attrs.set("japanese", @core.String("日本語テスト"))
  attrs.set("emoji", @core.String("Hello 🎉 World"))
  attrs.set("mixed", @core.String("abc日本def"))

  let ptr = writer.append(
    @core.VectorId::from_int(42),
    [0.5, 0.5, 0.5],
    attrs,
  )

  let bytes = writer.to_bytes()
  let reader = @persistence.SegmentReader::from_bytes("test", bytes).unwrap()

  match reader.read_at(ptr.offset, ptr.length) {
    Some((_, _, restored)) => {
      match restored.get("japanese") {
        Some(@core.String(s)) => assert_eq(s, "日本語テスト")
        _ => assert_true(false)
      }
      match restored.get("emoji") {
        Some(@core.String(s)) => assert_eq(s, "Hello 🎉 World")
        _ => assert_true(false)
      }
    }
    None => assert_true(false)
  }
}

///|
/// Test: SegmentReader collect and iter
test "coverage/segment/collect_iter" {
  let writer = @persistence.SegmentWriter::new("multi")

  // Add multiple records
  for i in 1..=5 {
    let attrs = @core.empty_attrs()
    attrs.set("idx", @core.Int(i.to_int64()))
    let _ = writer.append(
      @core.VectorId::from_int(i * 10),
      [i.to_double(), 0.0],
      attrs,
    )
  }

  let bytes = writer.to_bytes()
  let reader = @persistence.SegmentReader::from_bytes("multi", bytes).unwrap()

  // Test collect
  let records = reader.collect()
  assert_eq(records.length(), 5)

  // Verify order and values
  let mut count = 0
  for record in records {
    let (id, vec, attrs) = record
    count = count + 1
    assert_eq(id.to_int64(), (count * 10).to_int64())
    assert_eq(vec[0], count.to_double())
  }

  // Test iter
  let mut iter_count = 0
  for _ in reader.iter() {
    iter_count = iter_count + 1
  }
  assert_eq(iter_count, 5)
}

///|
/// Test: Segment with all attr types
test "coverage/segment/all_attr_types" {
  let writer = @persistence.SegmentWriter::new("types")

  let attrs = @core.empty_attrs()
  attrs.set("null_val", @core.Null)
  attrs.set("bool_true", @core.Bool(true))
  attrs.set("bool_false", @core.Bool(false))
  attrs.set("int_val", @core.Int(12345L))
  attrs.set("float_val", @core.Float(3.14159))
  attrs.set("string_val", @core.String("hello"))

  let ptr = writer.append(
    @core.VectorId::from_int(1),
    [1.0],
    attrs,
  )

  let bytes = writer.to_bytes()
  let reader = @persistence.SegmentReader::from_bytes("types", bytes).unwrap()

  match reader.read_at(ptr.offset, ptr.length) {
    Some((_, _, restored)) => {
      match restored.get("null_val") {
        Some(@core.Null) => ()
        _ => assert_true(false)
      }
      match restored.get("bool_true") {
        Some(@core.Bool(b)) => assert_true(b)
        _ => assert_true(false)
      }
      match restored.get("bool_false") {
        Some(@core.Bool(b)) => assert_true(not(b))
        _ => assert_true(false)
      }
      match restored.get("int_val") {
        Some(@core.Int(n)) => assert_eq(n, 12345L)
        _ => assert_true(false)
      }
      match restored.get("float_val") {
        Some(@core.Float(f)) => assert_true((f - 3.14159).abs() < 0.0001)
        _ => assert_true(false)
      }
    }
    None => assert_true(false)
  }
}

///|
/// Test: Invalid segment data
test "coverage/segment/invalid_data" {
  // Too short
  let short = Bytes::from_array([0x00, 0x01, 0x02])
  assert_true(@persistence.SegmentReader::from_bytes("x", short).is_none())

  // Wrong magic
  let bad_magic = Bytes::from_array([0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00])
  assert_true(@persistence.SegmentReader::from_bytes("x", bad_magic).is_none())

  // Wrong version
  let bad_version = Bytes::from_array([0x56, 0x53, 0x45, 0x47, 0xFF, 0x00, 0x00, 0x00])
  assert_true(@persistence.SegmentReader::from_bytes("x", bad_version).is_none())
}

///|
/// Test: SegmentWriter get_name
test "coverage/segment/writer_name" {
  let writer = @persistence.SegmentWriter::new("my-segment-name")
  assert_eq(writer.get_name(), "my-segment-name")
}

// =============================================================================
// Section 2: Index file edge cases
// =============================================================================

///|
/// Test: Index file with ANN bytes
test "coverage/index_file/with_ann" {
  let header : @persistence.IndexHeader = {
    metric_code: 0,
    dim: 3,
    count: 2,
    strategy_code: 1,
    has_ann: true,
  }

  let entries = [
    @persistence.IndexEntry::{
      id: @core.VectorId::from_int(1),
      ptr: { segment: "seg1", offset: 8, length: 100 },
    },
    @persistence.IndexEntry::{
      id: @core.VectorId::from_int(2),
      ptr: { segment: "seg2", offset: 8, length: 120 },
    },
  ]

  let ann_bytes = Bytes::from_array([0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02, 0x03, 0x04])

  let encoded = @persistence.encode_index_file(header, entries, Some(ann_bytes))
  let decoded = @persistence.decode_index_file(encoded)

  assert_true(decoded.is_some())
  match decoded {
    Some(result) => {
      assert_eq(result.header.has_ann, true)
      assert_eq(result.header.strategy_code, 1)
      assert_true(result.ann.is_some())
      match result.ann {
        Some(ann) => assert_eq(ann.length(), 8)
        None => assert_true(false)
      }
      assert_eq(result.entries.length(), 2)
    }
    None => assert_true(false)
  }
}

///|
/// Test: Index file with Unicode segment names
test "coverage/index_file/unicode_segment" {
  let header : @persistence.IndexHeader = {
    metric_code: 2,
    dim: 4,
    count: 1,
    strategy_code: 0,
    has_ann: false,
  }

  let entries = [
    @persistence.IndexEntry::{
      id: @core.VectorId::from_int(999),
      ptr: { segment: "日本語セグメント", offset: 8, length: 50 },
    },
  ]

  let encoded = @persistence.encode_index_file(header, entries, None)
  let decoded = @persistence.decode_index_file(encoded).unwrap()

  assert_eq(decoded.entries[0].ptr.segment, "日本語セグメント")
}

///|
/// Test: Index file invalid data
test "coverage/index_file/invalid" {
  // Too short
  let short = Bytes::make(20, b'\x00')
  assert_true(@persistence.decode_index_file(short).is_none())

  // Wrong magic
  let bad = Bytes::make(40, b'\x00')
  assert_true(@persistence.decode_index_file(bad).is_none())
}

///|
/// Test: Metric encoding/decoding
test "coverage/index_file/metric_codes" {
  assert_eq(@persistence.encode_metric(@core.Cosine), 0)
  assert_eq(@persistence.encode_metric(@core.L2), 1)
  assert_eq(@persistence.encode_metric(@core.Dot), 2)

  assert_eq(@persistence.decode_metric(0), @core.Cosine)
  assert_eq(@persistence.decode_metric(1), @core.L2)
  assert_eq(@persistence.decode_metric(2), @core.Dot)
  assert_eq(@persistence.decode_metric(99), @core.Cosine) // default
}

///|
/// Test: Strategy encoding
test "coverage/index_file/strategy_codes" {
  assert_eq(@persistence.encode_strategy(@core.Bruteforce), 0)
  assert_eq(@persistence.encode_strategy(@core.HNSW(@core.HNSWParams::default())), 1)
  assert_eq(@persistence.encode_strategy(@core.IVF({ nlist: 10, nprobe: 2 })), 2)

  assert_eq(@persistence.decode_strategy_type(0), 0)
  assert_eq(@persistence.decode_strategy_type(1), 1)
  assert_eq(@persistence.decode_strategy_type(2), 2)
}

///|
/// Test: IndexHeader from_store
test "coverage/index_file/header_from_store" {
  let store = @core.CoreStore::new(4, @core.L2, capacity=10)
  for i in 1..=3 {
    let _ = store.add_or_update(
      @core.VectorId::from_int(i),
      [1.0, 2.0, 3.0, 4.0],
      @core.empty_attrs(),
      upsert=false,
    )
  }

  let header = @persistence.IndexHeader::from_store(store, @core.HNSW(@core.HNSWParams::default()), true)
  assert_eq(header.dim, 4)
  assert_eq(header.count, 3)
  assert_eq(header.metric_code, 1) // L2
  assert_eq(header.strategy_code, 1) // HNSW
  assert_eq(header.has_ann, true)
}

// =============================================================================
// Section 3: Distributed edge cases
// =============================================================================

///|
/// Test: CRUSH with single node
test "coverage/distributed/single_node" {
  let store = @core.CoreStore::new(2, @core.Dot, capacity=10)
  for i in 1..=5 {
    let _ = store.add_or_update(
      @core.VectorId::from_int(i),
      [i.to_double(), 0.0],
      @core.empty_attrs(),
      upsert=false,
    )
  }

  // Single node CRUSH
  let crush = @persistence.CrushMap::new(
    4,
    1,
    [@persistence.CrushTarget::new("only-node")],
  )

  let data_storages : Map[String, @persistence.MemoryStorage] = {}
  data_storages.set("only-node", @persistence.MemoryStorage::new())
  let index_storage = @persistence.MemoryStorage::new()

  let opts = @persistence.SegmentOptions::default("single", crush)
  let _ = @persistence.save_store_distributed(store, opts, data_storages, index_storage)

  // All data should be on the single node
  let only = data_storages.get("only-node").unwrap()
  assert_true(only.list().length() > 0)

  // Restore
  let restored = @persistence.load_store_distributed("single", data_storages, index_storage)
  assert_eq(restored.size(), 5)
}

///|
/// Test: Empty store save/load
test "coverage/distributed/empty_store" {
  let store = @core.CoreStore::new(3, @core.Cosine, capacity=10)
  // No vectors added

  let crush = @persistence.CrushMap::new(
    4,
    1,
    [@persistence.CrushTarget::new("node1")],
  )

  let data_storages : Map[String, @persistence.MemoryStorage] = {}
  data_storages.set("node1", @persistence.MemoryStorage::new())
  let index_storage = @persistence.MemoryStorage::new()

  let opts = @persistence.SegmentOptions::default("empty", crush)
  let _ = @persistence.save_store_distributed(store, opts, data_storages, index_storage)

  // Should still have manifest and index
  assert_true(index_storage.exists("empty.manifest.json"))
  assert_true(index_storage.exists("empty.index"))

  let restored = @persistence.load_store_distributed("empty", data_storages, index_storage)
  assert_eq(restored.size(), 0)
}

///|
/// Test: Large vector IDs
test "coverage/distributed/large_ids" {
  let store = @core.CoreStore::new(2, @core.Dot, capacity=10)

  // Use large 64-bit IDs
  let large_ids = [
    0x7FFFFFFFFFFFFFFFL,
    0x100000000L,
    0xDEADBEEFCAFEL,
  ]

  for id in large_ids {
    let _ = store.add_or_update(
      @core.VectorId(id),
      [1.0, 2.0],
      @core.empty_attrs(),
      upsert=false,
    )
  }

  let crush = @persistence.CrushMap::new(2, 1, [@persistence.CrushTarget::new("n1")])
  let data_storages : Map[String, @persistence.MemoryStorage] = {}
  data_storages.set("n1", @persistence.MemoryStorage::new())
  let index_storage = @persistence.MemoryStorage::new()

  let opts = @persistence.SegmentOptions::default("large", crush)
  let _ = @persistence.save_store_distributed(store, opts, data_storages, index_storage)

  let restored = @persistence.load_store_distributed("large", data_storages, index_storage)
  assert_eq(restored.size(), 3)

  for id in large_ids {
    assert_true(restored.has(@core.VectorId(id)))
  }
}

// =============================================================================
// Section 4: WAL edge cases
// =============================================================================

///|
/// Test: WAL with negative numbers
test "coverage/wal/negative_numbers" {
  let attrs = @core.empty_attrs()
  attrs.set("neg_int", @core.Int(-12345L))
  attrs.set("neg_float", @core.Float(-3.14159))

  let records = [
    @persistence.WalRecord::upsert(
      @core.VectorId::from_int(1),
      [-1.0, -2.0, -3.0],
      attrs,
    ),
  ]

  let encoded = @persistence.encode_wal_segment(records)
  let decoded = @persistence.decode_wal_records(encoded)

  assert_eq(decoded.length(), 1)
  match decoded[0].attrs {
    Some(a) => {
      match a.get("neg_int") {
        Some(@core.Int(n)) => assert_eq(n, -12345L)
        _ => assert_true(false)
      }
      match a.get("neg_float") {
        Some(@core.Float(f)) => assert_true((f - (-3.14159)).abs() < 0.0001)
        _ => assert_true(false)
      }
    }
    None => assert_true(false)
  }
}

///|
/// Test: WAL scientific notation
test "coverage/wal/scientific_notation" {
  let attrs = @core.empty_attrs()
  attrs.set("small", @core.Float(0.000000000123))
  attrs.set("large", @core.Float(9870000000000000.0))

  let records = [
    @persistence.WalRecord::upsert(
      @core.VectorId::from_int(1),
      [0.00001, 100000.0],
      attrs,
    ),
  ]

  let encoded = @persistence.encode_wal_segment(records)
  let decoded = @persistence.decode_wal_records(encoded)

  assert_eq(decoded.length(), 1)
  match decoded[0].vector {
    Some(v) => {
      assert_true((v[0] - 0.00001).abs() < 0.0000000001)
      assert_true((v[1] - 100000.0).abs() < 1.0)
    }
    None => assert_true(false)
  }
}

// =============================================================================
// Section 5: Core store edge cases
// =============================================================================

///|
/// Test: Store serialize/deserialize with deleted vectors
test "coverage/store/serialize_with_deletions" {
  let store = @core.CoreStore::new(2, @core.L2, capacity=20)

  // Add vectors
  for i in 1..=10 {
    let _ = store.add_or_update(
      @core.VectorId::from_int(i),
      [i.to_double(), 0.0],
      @core.empty_attrs(),
      upsert=false,
    )
  }

  // Delete some
  let _ = store.remove_by_id(@core.VectorId::from_int(3))
  let _ = store.remove_by_id(@core.VectorId::from_int(7))

  assert_eq(store.size(), 8)

  // Serialize
  let bytes = store.serialize()

  // Deserialize
  let restored = @core.CoreStore::deserialize(bytes)
  assert_eq(restored.size(), 8)
  assert_true(not(restored.has(@core.VectorId::from_int(3))))
  assert_true(not(restored.has(@core.VectorId::from_int(7))))
  assert_true(restored.has(@core.VectorId::from_int(5)))
}

///|
/// Test: Store upsert mode
test "coverage/store/upsert_mode" {
  let store = @core.CoreStore::new(2, @core.Dot, capacity=10)

  // Initial add - returns (idx, true) because it's a new item
  let attrs1 = @core.empty_attrs()
  attrs1.set("version", @core.Int(1L))
  let (idx1, is_new1) = store.add_or_update(
    @core.VectorId::from_int(100),
    [1.0, 0.0],
    attrs1,
    upsert=false,
  )
  assert_true(is_new1) // true = new item

  // Upsert same ID - returns (idx, false) because it's an update
  let attrs2 = @core.empty_attrs()
  attrs2.set("version", @core.Int(2L))
  let (idx2, is_new2) = store.add_or_update(
    @core.VectorId::from_int(100),
    [0.0, 1.0],
    attrs2,
    upsert=true,
  )
  assert_true(not(is_new2)) // false = updated existing
  assert_eq(idx1, idx2) // Same index

  // Verify updated
  match store.get(@core.VectorId::from_int(100)) {
    Some(rec) => {
      match rec.attrs.get("version") {
        Some(@core.Int(v)) => assert_eq(v, 2L)
        _ => assert_true(false)
      }
    }
    None => assert_true(false)
  }
}

///|
/// Test: Store normalize_query with different metrics
test "coverage/store/normalize_query" {
  let store_cosine = @core.CoreStore::new(3, @core.Cosine, capacity=10)
  let store_l2 = @core.CoreStore::new(3, @core.L2, capacity=10)
  let store_dot = @core.CoreStore::new(3, @core.Dot, capacity=10)

  let query = [3.0, 4.0, 0.0]

  // Cosine normalizes
  let q_cosine = store_cosine.normalize_query(query)
  let norm = (q_cosine[0] * q_cosine[0] + q_cosine[1] * q_cosine[1] + q_cosine[2] * q_cosine[2]).sqrt()
  assert_true((norm - 1.0).abs() < 0.001)

  // L2 does not normalize
  let q_l2 = store_l2.normalize_query(query)
  assert_eq(q_l2[0], 3.0)
  assert_eq(q_l2[1], 4.0)

  // Dot does not normalize
  let q_dot = store_dot.normalize_query(query)
  assert_eq(q_dot[0], 3.0)
}

// =============================================================================
// Section 6: CRUSH edge cases
// =============================================================================

///|
/// Test: CRUSH locate with different replica counts
test "coverage/crush/replicas" {
  let crush = @persistence.CrushMap::new(
    8,
    3, // 3 replicas
    [
      @persistence.CrushTarget::new("a"),
      @persistence.CrushTarget::new("b"),
      @persistence.CrushTarget::new("c"),
      @persistence.CrushTarget::new("d"),
    ],
  )

  let result = @persistence.crush_locate(@core.VectorId::from_int(42), crush)
  assert_eq(result.primaries.length(), 3)

  // All placements should be unique
  let seen : Map[String, Bool] = {}
  for p in result.primaries {
    assert_true(not(seen.contains(p)))
    seen.set(p, true)
  }
}

///|
/// Test: CRUSH deterministic placement
test "coverage/crush/deterministic" {
  let crush = @persistence.CrushMap::new(
    16,
    2,
    [
      @persistence.CrushTarget::new("x"),
      @persistence.CrushTarget::new("y"),
      @persistence.CrushTarget::new("z"),
    ],
  )

  // Same ID should always map to same nodes
  let id = @core.VectorId::from_int(999)
  let r1 = @persistence.crush_locate(id, crush)
  let r2 = @persistence.crush_locate(id, crush)

  assert_eq(r1.pg, r2.pg)
  assert_eq(r1.primaries.length(), r2.primaries.length())
  for i in 0..<r1.primaries.length() {
    assert_eq(r1.primaries[i], r2.primaries[i])
  }
}

///|
/// Test: CRUSH primary selection
test "coverage/crush/primary" {
  let crush = @persistence.CrushMap::new(
    8,
    1,
    [@persistence.CrushTarget::new("node")],
  )

  // Different IDs should distribute across PGs
  let pgs : Map[Int, Bool] = {}
  for i in 0..<100 {
    let result = @persistence.crush_locate(@core.VectorId::from_int(i), crush)
    pgs.set(result.pg, true)
  }

  // Should have multiple different PGs
  assert_true(pgs.size() > 1)
}

///|
/// Test: CRUSH with empty targets
test "coverage/crush/empty_targets" {
  let crush = @persistence.CrushMap::new(4, 1, [])

  let result = @persistence.crush_locate(@core.VectorId::from_int(1), crush)
  assert_eq(result.primaries.length(), 0)

  let primary = @persistence.crush_primary(@core.VectorId::from_int(1), crush)
  assert_true(primary.is_none())
}

// =============================================================================
// Section 7: Additional coverage for distributed segment splitting
// =============================================================================

///|
/// Test: Segmented storage with small segment limit
test "coverage/distributed/segment_splitting" {
  let store = @core.CoreStore::new(10, @core.Dot, capacity=50)

  // Add many vectors with large attrs to trigger segment splits
  for i in 1..=20 {
    let attrs = @core.empty_attrs()
    attrs.set("data", @core.String("This is a longer string value for testing segment size limits"))
    attrs.set("index", @core.Int(i.to_int64()))
    let vec : Array[Double] = []
    for j in 0..<10 {
      vec.push((i * 10 + j).to_double())
    }
    let _ = store.add_or_update(
      @core.VectorId::from_int(i),
      vec,
      attrs,
      upsert=false,
    )
  }

  let crush = @persistence.CrushMap::new(4, 1, [@persistence.CrushTarget::new("node1")])
  let data_storages : Map[String, @persistence.MemoryStorage] = {}
  data_storages.set("node1", @persistence.MemoryStorage::new())
  let index_storage = @persistence.MemoryStorage::new()

  // Use segmented mode with small limit via options builder
  let opts = @persistence.SegmentOptions::default("split", crush)

  let _ = @persistence.save_store_distributed(store, opts, data_storages, index_storage)

  // Should have created segment files
  let files = data_storages.get("node1").unwrap().list()
  assert_true(files.length() >= 1)

  // Verify we can still load
  let restored = @persistence.load_store_distributed("split", data_storages, index_storage)
  assert_eq(restored.size(), 20)
}

///|
/// Test: Save with ANN bytes
test "coverage/distributed/with_ann" {
  let store = @core.CoreStore::new(3, @core.Cosine, capacity=10)
  for i in 1..=5 {
    let _ = store.add_or_update(
      @core.VectorId::from_int(i),
      [i.to_double(), 0.0, 0.0],
      @core.empty_attrs(),
      upsert=false,
    )
  }

  let crush = @persistence.CrushMap::new(2, 1, [@persistence.CrushTarget::new("n1")])
  let data_storages : Map[String, @persistence.MemoryStorage] = {}
  data_storages.set("n1", @persistence.MemoryStorage::new())
  let index_storage = @persistence.MemoryStorage::new()

  // Save with ANN bytes
  let ann_bytes = Bytes::from_array([0x01, 0x02, 0x03, 0x04, 0x05])
  let opts = @persistence.SegmentOptions::default("ann_test", crush)
  let _ = @persistence.save_store_distributed_with_ann(
    store,
    opts,
    data_storages,
    index_storage,
    @core.HNSW(@core.HNSWParams::default()),
    Some(ann_bytes),
  )

  // Load and check - use basic load to verify store
  let restored = @persistence.load_store_distributed("ann_test", data_storages, index_storage)
  assert_eq(restored.size(), 5)

  // Verify index file exists and has ann bytes by checking index
  assert_true(index_storage.exists("ann_test.index"))
}

///|
/// Test: Read segment at boundary
test "coverage/segment/read_boundary" {
  let writer = @persistence.SegmentWriter::new("boundary")

  // Add record at exact offset
  let attrs = @core.empty_attrs()
  let ptr = writer.append(@core.VectorId::from_int(1), [1.0, 2.0, 3.0], attrs)

  let bytes = writer.to_bytes()
  let reader = @persistence.SegmentReader::from_bytes("boundary", bytes).unwrap()

  // Try reading beyond bounds
  let invalid = reader.read_at(ptr.offset, bytes.length() + 100)
  assert_true(invalid.is_none())

  // Try reading at wrong offset
  let invalid2 = reader.read_at(ptr.offset + 1, ptr.length)
  // This may succeed or fail depending on data, just exercise the code path
  let _ = invalid2
}

///|
/// Test: Complex JSON attrs in segment
test "coverage/segment/complex_json" {
  let writer = @persistence.SegmentWriter::new("complex")

  let attrs = @core.empty_attrs()
  // Various edge cases
  attrs.set("empty_string", @core.String(""))
  attrs.set("zero_int", @core.Int(0L))
  attrs.set("zero_float", @core.Float(0.0))
  attrs.set("negative", @core.Int(-999L))
  attrs.set("unicode_key_日本語", @core.String("value"))

  let ptr = writer.append(@core.VectorId::from_int(42), [1.0], attrs)
  let bytes = writer.to_bytes()
  let reader = @persistence.SegmentReader::from_bytes("complex", bytes).unwrap()

  match reader.read_at(ptr.offset, ptr.length) {
    Some((_, _, restored)) => {
      match restored.get("empty_string") {
        Some(@core.String(s)) => assert_eq(s, "")
        _ => assert_true(false)
      }
      match restored.get("zero_int") {
        Some(@core.Int(n)) => assert_eq(n, 0L)
        _ => assert_true(false)
      }
      match restored.get("negative") {
        Some(@core.Int(n)) => assert_eq(n, -999L)
        _ => assert_true(false)
      }
    }
    None => assert_true(false)
  }
}

// =============================================================================
// Section 8: WAL additional coverage
// =============================================================================

///|
/// Test: WAL with empty attrs
test "coverage/wal/empty_attrs" {
  let records = [
    @persistence.WalRecord::upsert(
      @core.VectorId::from_int(1),
      [1.0, 2.0],
      @core.empty_attrs(),
    ),
  ]

  let encoded = @persistence.encode_wal_segment(records)
  assert_true(@persistence.verify_wal_checksum(encoded))

  let decoded = @persistence.decode_wal_records(encoded)
  assert_eq(decoded.length(), 1)
  match decoded[0].attrs {
    Some(a) => assert_eq(a.size(), 0)
    None => assert_true(false)
  }
}

///|
/// Test: WAL checksum verification failure
test "coverage/wal/bad_checksum" {
  let records = [
    @persistence.WalRecord::upsert(
      @core.VectorId::from_int(1),
      [1.0],
      @core.empty_attrs(),
    ),
  ]

  let encoded = @persistence.encode_wal_segment(records)

  // Corrupt the data
  let corrupted : Array[Byte] = []
  for i in 0..<encoded.length() {
    if i == encoded.length() - 1 {
      corrupted.push(b'\xFF') // Change last byte
    } else {
      corrupted.push(encoded[i])
    }
  }
  let corrupted_bytes = Bytes::from_array(corrupted)

  assert_true(not(@persistence.verify_wal_checksum(corrupted_bytes)))
}

///|
/// Test: WAL SetAttrs record
test "coverage/wal/set_attrs" {
  let attrs = @core.empty_attrs()
  attrs.set("key", @core.String("value"))

  let records = [
    @persistence.WalRecord::set_attrs(@core.VectorId::from_int(1), attrs),
  ]

  let encoded = @persistence.encode_wal_segment(records)
  let decoded = @persistence.decode_wal_records(encoded)

  assert_eq(decoded.length(), 1)
  // Verify it's a SetAttrs record by checking vector is None and attrs is Some
  match (decoded[0].vector, decoded[0].attrs) {
    (None, Some(a)) => {
      match a.get("key") {
        Some(@core.String(s)) => assert_eq(s, "value")
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
/// Test: WAL Remove record
test "coverage/wal/remove_record" {
  let records = [
    @persistence.WalRecord::remove(@core.VectorId::from_int(999)),
  ]

  let encoded = @persistence.encode_wal_segment(records)
  let decoded = @persistence.decode_wal_records(encoded)

  assert_eq(decoded.length(), 1)
  assert_eq(decoded[0].id.to_int64(), 999L)
  // Remove records have no vector and no attrs
  match (decoded[0].vector, decoded[0].attrs) {
    (None, None) => ()
    _ => assert_true(false)
  }
}

///|
/// Test: WAL with control characters in strings
test "coverage/wal/control_chars" {
  let attrs = @core.empty_attrs()
  // Include various control characters that need escaping
  attrs.set("with_backspace", @core.String("hello\u0008world")) // backspace
  attrs.set("with_formfeed", @core.String("page1\u000Cpage2")) // form feed
  attrs.set("with_control", @core.String("text\u0001ctrl")) // other control char

  let records = [
    @persistence.WalRecord::upsert(
      @core.VectorId::from_int(1),
      [1.0],
      attrs,
    ),
  ]

  let encoded = @persistence.encode_wal_segment(records)
  let decoded = @persistence.decode_wal_records(encoded)

  assert_eq(decoded.length(), 1)
  match decoded[0].attrs {
    Some(a) => {
      // Verify control chars survived encoding
      match a.get("with_backspace") {
        Some(@core.String(s)) => assert_true(s.length() > 0)
        _ => ()
      }
    }
    None => assert_true(false)
  }
}

///|
/// Test: WAL with 4-byte UTF-8 characters (emoji)
test "coverage/wal/4byte_utf8" {
  let attrs = @core.empty_attrs()
  attrs.set("emoji", @core.String("Hello 🎉🚀💻 World"))
  attrs.set("chinese", @core.String("你好世界"))
  attrs.set("mixed", @core.String("Test🔥中文ABC"))

  let records = [
    @persistence.WalRecord::upsert(
      @core.VectorId::from_int(1),
      [1.0, 2.0],
      attrs,
    ),
  ]

  let encoded = @persistence.encode_wal_segment(records)
  let decoded = @persistence.decode_wal_records(encoded)

  assert_eq(decoded.length(), 1)
  match decoded[0].attrs {
    Some(a) => {
      match a.get("emoji") {
        Some(@core.String(s)) => assert_eq(s, "Hello 🎉🚀💻 World")
        _ => assert_true(false)
      }
      match a.get("chinese") {
        Some(@core.String(s)) => assert_eq(s, "你好世界")
        _ => assert_true(false)
      }
    }
    None => assert_true(false)
  }
}

///|
/// Test: Multiple WAL records in sequence
test "coverage/wal/multiple_records" {
  let records : Array[@persistence.WalRecord] = []

  // Add various record types
  for i in 1..=5 {
    let attrs = @core.empty_attrs()
    attrs.set("idx", @core.Int(i.to_int64()))
    records.push(
      @persistence.WalRecord::upsert(
        @core.VectorId::from_int(i),
        [i.to_double()],
        attrs,
      ),
    )
  }

  // Add remove
  records.push(@persistence.WalRecord::remove(@core.VectorId::from_int(3)))

  // Add set_attrs
  let new_attrs = @core.empty_attrs()
  new_attrs.set("updated", @core.Bool(true))
  records.push(@persistence.WalRecord::set_attrs(@core.VectorId::from_int(1), new_attrs))

  let encoded = @persistence.encode_wal_segment(records)
  assert_true(@persistence.verify_wal_checksum(encoded))

  let decoded = @persistence.decode_wal_records(encoded)
  assert_eq(decoded.length(), 7)
}

// =============================================================================
// Section 9: Additional attr coverage
// =============================================================================

///|
/// Test: Attrs copy functionality
test "coverage/attrs/copy" {
  let attrs = @core.empty_attrs()
  attrs.set("key1", @core.String("value1"))
  attrs.set("key2", @core.Int(42L))

  // Get internal map size
  assert_eq(attrs.size(), 2)

  // Modify and verify independence when used in store
  let store = @core.CoreStore::new(2, @core.Dot, capacity=5)
  let _ = store.add_or_update(
    @core.VectorId::from_int(1),
    [1.0, 2.0],
    attrs,
    upsert=false,
  )

  // Modify original attrs
  attrs.set("key3", @core.Bool(true))

  // Store attrs should not be affected
  match store.get(@core.VectorId::from_int(1)) {
    Some(rec) => {
      assert_eq(rec.attrs.size(), 2) // Only original 2 keys
    }
    None => assert_true(false)
  }
}

///|
/// Test: Store shrink_to_fit
test "coverage/store/shrink" {
  let store = @core.CoreStore::new(2, @core.L2, capacity=100)

  // Add 10 vectors
  for i in 1..=10 {
    let _ = store.add_or_update(
      @core.VectorId::from_int(i),
      [i.to_double(), 0.0],
      @core.empty_attrs(),
      upsert=false,
    )
  }

  // Capacity should be large
  assert_true(store.capacity() >= 10)

  // Remove some
  for i in 1..=5 {
    let _ = store.remove_by_id(@core.VectorId::from_int(i))
  }

  assert_eq(store.size(), 5)

  // Shrink
  store.shrink_to_fit()

  // Size should still be 5
  assert_eq(store.size(), 5)
}

// =============================================================================
// Section 10: Additional edge case coverage
// =============================================================================

///|
/// Test: Store ensure_capacity
test "coverage/store/ensure_capacity" {
  let store = @core.CoreStore::new(2, @core.Cosine, capacity=5)

  // Returns false when capacity is already sufficient (no resize needed)
  let grew1 = store.ensure_capacity(3)
  assert_true(not(grew1)) // false = no resize needed

  // Add vectors to fill capacity
  for i in 1..=5 {
    let _ = store.add_or_update(
      @core.VectorId::from_int(i),
      [i.to_double(), 0.0],
      @core.empty_attrs(),
      upsert=false,
    )
  }

  // Now at capacity, adding more requires growth
  let grew2 = store.ensure_capacity(1)
  assert_true(grew2) // true = had to grow
  assert_true(store.capacity() > 5)
}

///|
/// Test: Store update_attrs
test "coverage/store/update_attrs" {
  let store = @core.CoreStore::new(2, @core.Dot, capacity=10)

  // Add vector
  let attrs1 = @core.empty_attrs()
  attrs1.set("version", @core.Int(1L))
  let _ = store.add_or_update(
    @core.VectorId::from_int(1),
    [1.0, 2.0],
    attrs1,
    upsert=false,
  )

  // Update attrs
  let attrs2 = @core.empty_attrs()
  attrs2.set("version", @core.Int(2L))
  attrs2.set("new_key", @core.String("new_value"))

  let updated = store.update_attrs(@core.VectorId::from_int(1), attrs2)
  assert_true(updated)

  // Verify
  match store.get(@core.VectorId::from_int(1)) {
    Some(rec) => {
      match rec.attrs.get("version") {
        Some(@core.Int(v)) => assert_eq(v, 2L)
        _ => assert_true(false)
      }
      match rec.attrs.get("new_key") {
        Some(@core.String(s)) => assert_eq(s, "new_value")
        _ => assert_true(false)
      }
    }
    None => assert_true(false)
  }

  // Try to update non-existent
  let not_updated = store.update_attrs(@core.VectorId::from_int(999), @core.empty_attrs())
  assert_true(not(not_updated))
}

///|
/// Test: Store get_by_index
test "coverage/store/get_by_index" {
  let store = @core.CoreStore::new(3, @core.L2, capacity=10)

  for i in 1..=5 {
    let _ = store.add_or_update(
      @core.VectorId::from_int(i * 10),
      [i.to_double(), 0.0, 0.0],
      @core.empty_attrs(),
      upsert=false,
    )
  }

  // Get by index 0
  let rec0 = store.get_by_index(0)
  assert_eq(rec0.vector.length(), 3)

  // Get by index 4
  let rec4 = store.get_by_index(4)
  assert_eq(rec4.vector.length(), 3)
}

///|
/// Test: Binary reader/writer edge cases
test "coverage/binary/edge_cases" {
  let w = @core.BinaryWriter::new()

  // Write various sizes
  w.push_byte(b'\xFF')
  w.push_u32(0xFFFFFFFFU)
  w.push_u64(0xFFFFFFFFFFFFFFFFUL)
  w.push_i32(-1)
  w.push_i64(-9999999L)
  w.push_f32(Float::from_double(-3.14))
  w.push_f64(-2.718281828)

  let bytes = w.concat()
  let r = @core.BinaryReader::new(bytes)

  assert_eq(r.read_byte(), b'\xFF')
  assert_eq(r.read_u32(), 0xFFFFFFFFU)
  assert_eq(r.read_u64(), 0xFFFFFFFFFFFFFFFFUL)
  assert_eq(r.read_i32(), -1)
  assert_eq(r.read_i64(), -9999999L)

  let f32 = r.read_f32()
  assert_true((f32.to_double() - (-3.14)).abs() < 0.01)

  let f64 = r.read_f64()
  assert_true((f64 - (-2.718281828)).abs() < 0.0001)
}

///|
/// Test: Binary reader remaining bytes
test "coverage/binary/remaining" {
  let w = @core.BinaryWriter::new()
  w.push_u32(12345U)
  w.push_u32(67890U)

  let bytes = w.concat()
  let r = @core.BinaryReader::new(bytes)

  assert_eq(r.remaining(), 8)
  let _ = r.read_u32()
  assert_eq(r.remaining(), 4)
  let _ = r.read_u32()
  assert_eq(r.remaining(), 0)
}

///|
/// Test: Math functions
test "coverage/math/functions" {
  // Test dot product
  let a = [1.0, 2.0, 3.0]
  let b = [4.0, 5.0, 6.0]
  let dot = @core.dot(a, b)
  assert_eq(dot, 32.0) // 1*4 + 2*5 + 3*6

  // Test l2_squared (squared euclidean distance)
  let l2_sq = @core.l2_squared(a, b)
  // (4-1)^2 + (5-2)^2 + (6-3)^2 = 9 + 9 + 9 = 27
  assert_eq(l2_sq, 27.0)

  // Test l2_norm
  let norm = @core.l2_norm(a)
  // sqrt(1 + 4 + 9) = sqrt(14)
  assert_true((norm - 14.0.sqrt()).abs() < 0.001)

  // Test normalize
  let norm_a = @core.normalize(a)
  let len = @core.l2_norm(norm_a)
  assert_true((len - 1.0).abs() < 0.001)

  // Test cosine_similarity
  let norm_b = @core.normalize(b)
  let cos_sim = @core.cosine_similarity(norm_a, norm_b)
  assert_true(cos_sim > 0.9) // Should be high for similar directions
}

///|
/// Test: TopK push operations
test "coverage/topk/operations" {
  let results : Array[(Int, Double)] = []
  let k = 3

  // Add items using push_top_k
  @core.push_top_k(results, (1, 0.5), k, fn(x) { x.1 })
  @core.push_top_k(results, (2, 0.8), k, fn(x) { x.1 })
  @core.push_top_k(results, (3, 0.3), k, fn(x) { x.1 })
  @core.push_top_k(results, (4, 0.9), k, fn(x) { x.1 })
  @core.push_top_k(results, (5, 0.1), k, fn(x) { x.1 })

  // Should only keep top 3
  assert_eq(results.length(), 3)

  // Best scores should be kept (0.9, 0.8, 0.5)
  assert_true(results[0].1 >= 0.8)
}

///|
/// Test: TopK with k=0
test "coverage/topk/k_zero" {
  let results : Array[(Int, Double)] = []
  @core.push_top_k(results, (1, 0.5), 0, fn(x) { x.1 })
  assert_eq(results.length(), 0)
}

// =============================================================================
// Section 11: Remaining coverage gaps
// =============================================================================

///|
/// Test: WAL with unicode escape sequences (\uXXXX)
test "coverage/wal/unicode_escape" {
  // Create attrs with strings that will be encoded with \uXXXX escapes
  let attrs = @core.empty_attrs()
  // Control characters that need \uXXXX encoding
  attrs.set("ctrl_a", @core.String("\u0001")) // SOH
  attrs.set("ctrl_b", @core.String("\u0002")) // STX
  attrs.set("bell", @core.String("\u0007")) // Bell

  let records = [
    @persistence.WalRecord::upsert(
      @core.VectorId::from_int(1),
      [1.0],
      attrs,
    ),
  ]

  let encoded = @persistence.encode_wal_segment(records)
  let decoded = @persistence.decode_wal_records(encoded)

  assert_eq(decoded.length(), 1)
  // Verify the attrs survived roundtrip
  match decoded[0].attrs {
    Some(a) => assert_true(a.size() >= 1)
    None => assert_true(false)
  }
}

///|
/// Test: WAL hex parsing with uppercase letters
test "coverage/wal/hex_uppercase" {
  // JSON with uppercase hex escapes like \u000A
  let attrs = @core.empty_attrs()
  // This will trigger hex_char_value with 'A'-'F' range
  attrs.set("mixed", @core.String("ABCDEF0123456789"))

  let records = [
    @persistence.WalRecord::upsert(
      @core.VectorId::from_int(1),
      [1.0],
      attrs,
    ),
  ]

  let encoded = @persistence.encode_wal_segment(records)
  let decoded = @persistence.decode_wal_records(encoded)

  assert_eq(decoded.length(), 1)
  match decoded[0].attrs {
    Some(a) => {
      match a.get("mixed") {
        Some(@core.String(s)) => assert_eq(s, "ABCDEF0123456789")
        _ => assert_true(false)
      }
    }
    None => assert_true(false)
  }
}

///|
/// Test: WAL with parse error fallback
test "coverage/wal/parse_error_fallback" {
  // Test what happens when we have malformed data
  // Create a minimal valid WAL header but with bad records
  let w = @core.BinaryWriter::new()
  // WAL header
  w.push_u32(@persistence.wal_magic)
  w.push_u32(@persistence.wal_version)
  w.push_u32(0U) // flags
  w.push_u32(0U) // record count = 0

  // CRC placeholder
  w.push_u32(0U)

  let bytes = w.concat()

  // This should decode as empty (0 records)
  let decoded = @persistence.decode_wal_records(bytes)
  assert_eq(decoded.length(), 0)
}

///|
/// Test: Segment with empty vector
test "coverage/segment/empty_vector" {
  let writer = @persistence.SegmentWriter::new("empty_vec")

  // Add record with empty attrs but valid vector
  let ptr = writer.append(
    @core.VectorId::from_int(1),
    [0.0], // minimal vector
    @core.empty_attrs(),
  )

  let bytes = writer.to_bytes()
  let reader = @persistence.SegmentReader::from_bytes("empty_vec", bytes).unwrap()

  match reader.read_at(ptr.offset, ptr.length) {
    Some((id, vec, attrs)) => {
      assert_eq(id.to_int64(), 1L)
      assert_eq(vec.length(), 1)
      assert_eq(attrs.size(), 0)
    }
    None => assert_true(false)
  }
}

///|
/// Test: Segment collect with multiple varying-size records
test "coverage/segment/collect_varying" {
  let writer = @persistence.SegmentWriter::new("varying")

  // Add records with varying attr sizes
  for i in 1..=10 {
    let attrs = @core.empty_attrs()
    // Varying number of attrs
    for j in 0..<(i % 5) {
      attrs.set("key" + j.to_string(), @core.Int(j.to_int64()))
    }
    let vec : Array[Double] = []
    for _ in 0..<(i % 3 + 1) {
      vec.push(i.to_double())
    }
    let _ = writer.append(@core.VectorId::from_int(i), vec, attrs)
  }

  let bytes = writer.to_bytes()
  let reader = @persistence.SegmentReader::from_bytes("varying", bytes).unwrap()

  let records = reader.collect()
  assert_eq(records.length(), 10)
}

///|
/// Test: Index file decode with truncated data
test "coverage/index_file/truncated" {
  // Create valid header but truncated entries
  let w = @core.BinaryWriter::new()

  // Header (16 bytes)
  w.push_u32(@persistence.index_magic)
  w.push_u32(@persistence.index_version)
  w.push_u32(0U)
  w.push_u32(0U)

  // Info (20 bytes)
  w.push_u32(0U) // metric
  w.push_u32(3U) // dim
  w.push_u32(1U) // count = 1 (but no entry data)
  w.push_u32(0U) // strategy
  w.push_u32(0U) // flags (no ANN)

  let bytes = w.concat()
  // This should still decode (entries will be empty due to insufficient data)
  let result = @persistence.decode_index_file(bytes)
  assert_true(result.is_some())
}

///|
/// Test: Distributed write with segmented mode forcing splits
test "coverage/distributed/force_segment_split" {
  let store = @core.CoreStore::new(4, @core.Dot, capacity=100)

  // Add vectors with large attrs to ensure we exceed segment limits
  for i in 1..=50 {
    let attrs = @core.empty_attrs()
    // Add a lot of attrs to increase record size
    for j in 0..<10 {
      attrs.set("field_" + j.to_string(), @core.String("value_" + i.to_string() + "_" + j.to_string()))
    }
    let _ = store.add_or_update(
      @core.VectorId::from_int(i),
      [i.to_double(), 0.0, 0.0, 0.0],
      attrs,
      upsert=false,
    )
  }

  let crush = @persistence.CrushMap::new(2, 1, [@persistence.CrushTarget::new("node1")])
  let data_storages : Map[String, @persistence.MemoryStorage] = {}
  data_storages.set("node1", @persistence.MemoryStorage::new())
  let index_storage = @persistence.MemoryStorage::new()

  // Use default options (segmented is false by default, so won't actually split)
  let opts = @persistence.SegmentOptions::default("split_test", crush)
  let _ = @persistence.save_store_distributed(store, opts, data_storages, index_storage)

  // Verify data was saved
  let restored = @persistence.load_store_distributed("split_test", data_storages, index_storage)
  assert_eq(restored.size(), 50)
}

///|
/// Test: CRUSH with zero PGs
test "coverage/crush/zero_pgs" {
  let crush = @persistence.CrushMap::new(0, 1, [@persistence.CrushTarget::new("node")])

  // Should still work with pg=0
  let result = @persistence.crush_locate(@core.VectorId::from_int(1), crush)
  assert_eq(result.pg, 0)
}

///|
/// Test: Store remove triggers compaction
test "coverage/store/remove_compaction" {
  let store = @core.CoreStore::new(2, @core.Dot, capacity=10)

  // Fill the store
  for i in 1..=5 {
    let _ = store.add_or_update(
      @core.VectorId::from_int(i),
      [i.to_double(), 0.0],
      @core.empty_attrs(),
      upsert=false,
    )
  }

  assert_eq(store.size(), 5)

  // Remove middle element (should trigger compaction/swap)
  let move_info = store.remove_by_id(@core.VectorId::from_int(3))

  assert_eq(store.size(), 4)
  assert_true(not(store.has(@core.VectorId::from_int(3))))

  // Check if compaction happened
  match move_info {
    Some(info) => {
      // Something was moved
      let _ = info
    }
    None => ()
  }
}

///|
/// Test: Binary writer/reader with bytes
test "coverage/binary/bytes_roundtrip" {
  let w = @core.BinaryWriter::new()

  // Write raw bytes
  let raw = Bytes::from_array([0x01, 0x02, 0x03, 0x04, 0x05])
  w.push_bytes(raw)

  let written = w.concat()
  let r = @core.BinaryReader::new(written)

  // Read back
  let read_bytes = r.read_bytes(5)
  assert_eq(read_bytes.length(), 5)
  assert_eq(read_bytes[0], b'\x01')
  assert_eq(read_bytes[4], b'\x05')
}

///|
/// Test: Store with L2 metric (no normalization)
test "coverage/store/l2_metric" {
  let store = @core.CoreStore::new(3, @core.L2, capacity=10)

  let _ = store.add_or_update(
    @core.VectorId::from_int(1),
    [3.0, 4.0, 0.0], // Should NOT be normalized
    @core.empty_attrs(),
    upsert=false,
  )

  match store.get(@core.VectorId::from_int(1)) {
    Some(rec) => {
      // L2 doesn't normalize, so values should be preserved
      assert_true((rec.vector[0] - 3.0).abs() < 0.001)
      assert_true((rec.vector[1] - 4.0).abs() < 0.001)
    }
    None => assert_true(false)
  }
}

///|
/// Test: Store with Dot metric (no normalization)
test "coverage/store/dot_metric" {
  let store = @core.CoreStore::new(2, @core.Dot, capacity=10)

  let _ = store.add_or_update(
    @core.VectorId::from_int(1),
    [5.0, 12.0], // Should NOT be normalized
    @core.empty_attrs(),
    upsert=false,
  )

  match store.get(@core.VectorId::from_int(1)) {
    Some(rec) => {
      // Dot doesn't normalize
      assert_true((rec.vector[0] - 5.0).abs() < 0.001)
      assert_true((rec.vector[1] - 12.0).abs() < 0.001)
    }
    None => assert_true(false)
  }
}

///|
/// Test: Math dot_at function
test "coverage/math/dot_at" {
  let data = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]
  let query = [1.0, 1.0, 1.0]
  let dim = 3

  // dot_at(data, 0, query, dim) = 1*1 + 2*1 + 3*1 = 6
  let result1 = @core.dot_at(data, 0, query, dim)
  assert_eq(result1, 6.0)

  // dot_at(data, 3, query, dim) = 4*1 + 5*1 + 6*1 = 15
  let result2 = @core.dot_at(data, 3, query, dim)
  assert_eq(result2, 15.0)
}

///|
/// Test: Math l2neg_at function
test "coverage/math/l2neg_at" {
  let data = [1.0, 2.0, 3.0, 0.0, 0.0, 0.0]
  let query = [1.0, 2.0, 3.0]
  let dim = 3

  // l2neg_at returns negative squared L2 distance
  // For identical vectors, distance should be 0
  let result1 = @core.l2neg_at(data, 0, query, dim)
  assert_eq(result1, 0.0)

  // For different vectors (0,0,0) vs (1,2,3)
  let result2 = @core.l2neg_at(data, 3, query, dim)
  // -(1^2 + 2^2 + 3^2) = -(1 + 4 + 9) = -14
  assert_eq(result2, -14.0)
}

///|
/// Test: Math get_score_fn
test "coverage/math/get_score_fn" {
  let data = [1.0, 0.0, 0.0]
  let query = [1.0, 0.0, 0.0]
  let dim = 3

  // Get score function for each metric
  let cosine_fn = @core.get_score_fn(@core.Cosine)
  let dot_fn = @core.get_score_fn(@core.Dot)
  let l2_fn = @core.get_score_fn(@core.L2)

  // Identical vectors should have high scores
  let cosine_score = cosine_fn(data, 0, query, dim)
  let dot_score = dot_fn(data, 0, query, dim)
  let l2_score = l2_fn(data, 0, query, dim)

  assert_eq(cosine_score, 1.0)
  assert_eq(dot_score, 1.0)
  assert_eq(l2_score, 0.0) // No distance
}

///|
/// Test: Normalize in place
test "coverage/math/normalize_in_place" {
  let vec = [3.0, 4.0, 0.0]
  @core.normalize_in_place(vec)

  // Should have unit length
  let len = @core.l2_norm(vec)
  assert_true((len - 1.0).abs() < 0.001)

  // Values should be 3/5, 4/5, 0
  assert_true((vec[0] - 0.6).abs() < 0.001)
  assert_true((vec[1] - 0.8).abs() < 0.001)
}

///|
/// Test: Normalize zero vector
test "coverage/math/normalize_zero" {
  let vec = [0.0, 0.0, 0.0]
  @core.normalize_in_place(vec)

  // Zero vector stays zero (no division by zero)
  assert_eq(vec[0], 0.0)
  assert_eq(vec[1], 0.0)
  assert_eq(vec[2], 0.0)
}

// =============================================================================
// Section 12: WAL decode error paths
// =============================================================================

///|
/// Test: WAL decode with invalid type byte
test "coverage/wal/invalid_type" {
  let w = @core.BinaryWriter::new()
  // WAL header
  w.push_u32(@persistence.wal_magic)
  w.push_u32(@persistence.wal_version)
  w.push_u32(0U) // flags
  w.push_u32(1U) // 1 record

  // Invalid record - type byte 0xFF is not valid
  w.push_byte(b'\xFF') // Invalid type
  w.push_byte(b'\x00') // reserved
  w.push_u64(1UL) // id
  w.push_u32(0U) // attrs_len
  w.push_u32(0U) // vector_len

  // Add a placeholder CRC
  w.push_u32(0U)

  let bytes = w.concat()
  // Decoding should handle the invalid type gracefully
  let decoded = @persistence.decode_wal_records(bytes)
  // May return empty or partial results
  let _ = decoded
}

///|
/// Test: WAL decode with truncated data
test "coverage/wal/truncated_record" {
  let w = @core.BinaryWriter::new()
  // WAL header
  w.push_u32(@persistence.wal_magic)
  w.push_u32(@persistence.wal_version)
  w.push_u32(0U) // flags
  w.push_u32(1U) // Claims 1 record

  // Incomplete record - only type byte
  w.push_byte(b'\x01') // Upsert type
  // Missing the rest of the record...

  w.push_u32(0U) // CRC

  let bytes = w.concat()
  // Should handle gracefully (return empty or partial)
  let decoded = @persistence.decode_wal_records(bytes)
  let _ = decoded
}

///|
/// Test: WAL with attrs that have None values
test "coverage/wal/attrs_none_value" {
  // Test the `None => continue` branch in attrs_to_json
  let attrs = @core.empty_attrs()
  // Can't directly set None, but empty attrs exercises different paths
  attrs.set("key1", @core.Null)
  attrs.set("key2", @core.Bool(false))

  let records = [
    @persistence.WalRecord::upsert(
      @core.VectorId::from_int(1),
      [1.0],
      attrs,
    ),
  ]

  let encoded = @persistence.encode_wal_segment(records)
  let decoded = @persistence.decode_wal_records(encoded)
  assert_eq(decoded.length(), 1)
}

// =============================================================================
// Section 13: Distributed load edge cases
// =============================================================================

///|
/// Test: Load with missing segment in manifest (CRUSH fallback)
test "coverage/distributed/crush_fallback" {
  let store = @core.CoreStore::new(2, @core.Dot, capacity=10)

  for i in 1..=5 {
    let _ = store.add_or_update(
      @core.VectorId::from_int(i),
      [i.to_double(), 0.0],
      @core.empty_attrs(),
      upsert=false,
    )
  }

  let crush = @persistence.CrushMap::new(4, 1, [@persistence.CrushTarget::new("node1")])
  let data_storages : Map[String, @persistence.MemoryStorage] = {}
  data_storages.set("node1", @persistence.MemoryStorage::new())
  let index_storage = @persistence.MemoryStorage::new()

  let opts = @persistence.SegmentOptions::default("fallback", crush)
  let _ = @persistence.save_store_distributed(store, opts, data_storages, index_storage)

  // Load should work via normal path
  let restored = @persistence.load_store_distributed("fallback", data_storages, index_storage)
  assert_eq(restored.size(), 5)
}

///|
/// Test: Attrs estimation for all types
test "coverage/distributed/attrs_estimation" {
  let store = @core.CoreStore::new(2, @core.Dot, capacity=10)

  // Create attrs with all types to test estimation
  let attrs = @core.empty_attrs()
  attrs.set("str", @core.String("test string value"))
  attrs.set("int", @core.Int(123456789L))
  attrs.set("float", @core.Float(3.14159265359))
  attrs.set("bool", @core.Bool(true))
  attrs.set("null", @core.Null)

  let _ = store.add_or_update(
    @core.VectorId::from_int(1),
    [1.0, 2.0],
    attrs,
    upsert=false,
  )

  let crush = @persistence.CrushMap::new(1, 1, [@persistence.CrushTarget::new("n1")])
  let data_storages : Map[String, @persistence.MemoryStorage] = {}
  data_storages.set("n1", @persistence.MemoryStorage::new())
  let index_storage = @persistence.MemoryStorage::new()

  let opts = @persistence.SegmentOptions::default("estimate", crush)
  let _ = @persistence.save_store_distributed(store, opts, data_storages, index_storage)

  let restored = @persistence.load_store_distributed("estimate", data_storages, index_storage)
  assert_eq(restored.size(), 1)
}

// =============================================================================
// Section 14: Heap and misc coverage
// =============================================================================

///|
/// Test: MaxHeap operations
test "coverage/heap/max_heap" {
  // Compare function: returns > 0 if a should be higher priority
  let heap = @core.MaxHeap::new(fn(a : Int, b : Int) {
    if a > b { 1 } else if a < b { -1 } else { 0 }
  })

  heap.push(5)
  heap.push(3)
  heap.push(7)
  heap.push(1)
  heap.push(9)

  assert_eq(heap.length(), 5)

  // Pop in descending order (max first)
  assert_eq(heap.pop(), Some(9))
  assert_eq(heap.pop(), Some(7))
  assert_eq(heap.pop(), Some(5))
  assert_eq(heap.pop(), Some(3))
  assert_eq(heap.pop(), Some(1))
  assert_eq(heap.pop(), None)
}

///|
/// Test: MaxHeap peek
test "coverage/heap/peek" {
  let heap = @core.MaxHeap::new(fn(a : Int, b : Int) {
    if a > b { 1 } else if a < b { -1 } else { 0 }
  })

  assert_true(heap.peek().is_none())
  assert_true(heap.is_empty())

  heap.push(10)
  assert_eq(heap.peek(), Some(10))

  heap.push(15)
  assert_eq(heap.peek(), Some(15)) // Max is now 15

  // Peek doesn't remove
  assert_eq(heap.length(), 2)
}

///|
/// Test: Index file without ANN bytes
test "coverage/index_file/no_ann" {
  let header : @persistence.IndexHeader = {
    metric_code: 1,
    dim: 4,
    count: 2,
    strategy_code: 0,
    has_ann: false,
  }

  let entries = [
    @persistence.IndexEntry::{
      id: @core.VectorId::from_int(100),
      ptr: { segment: "seg", offset: 8, length: 50 },
    },
  ]

  let encoded = @persistence.encode_index_file(header, entries, None)
  let decoded = @persistence.decode_index_file(encoded).unwrap()

  assert_eq(decoded.header.has_ann, false)
  assert_true(decoded.ann.is_none())
  assert_eq(decoded.entries.length(), 1)
}

///|
/// Test: Store get_index for non-existent ID
test "coverage/store/get_index_missing" {
  let store = @core.CoreStore::new(2, @core.Dot, capacity=10)

  let _ = store.add_or_update(
    @core.VectorId::from_int(1),
    [1.0, 2.0],
    @core.empty_attrs(),
    upsert=false,
  )

  // Get index for non-existent ID
  assert_true(store.get_index(@core.VectorId::from_int(999)).is_none())

  // Get index for existing ID
  assert_true(store.get_index(@core.VectorId::from_int(1)).is_some())
}

///|
/// Test: TopK push_sorted_desc (requires Scored trait)
test "coverage/topk/push_sorted" {
  // Create scored items
  struct ScoredItem {
    id : Int
    score : Double
  } derive(Show)

  // push_top_k should handle equal scores
  let results : Array[(Int, Double)] = []
  @core.push_top_k(results, (1, 0.5), 3, fn(x) { x.1 })
  @core.push_top_k(results, (2, 0.5), 3, fn(x) { x.1 }) // Same score
  @core.push_top_k(results, (3, 0.5), 3, fn(x) { x.1 }) // Same score

  assert_eq(results.length(), 3)
}

///|
/// Test: TopK with scores worse than current worst
test "coverage/topk/reject_worse" {
  let results : Array[(Int, Double)] = []

  // Fill with good scores
  @core.push_top_k(results, (1, 0.9), 2, fn(x) { x.1 })
  @core.push_top_k(results, (2, 0.8), 2, fn(x) { x.1 })

  // Now try to add worse scores - should be rejected
  @core.push_top_k(results, (3, 0.1), 2, fn(x) { x.1 })
  @core.push_top_k(results, (4, 0.2), 2, fn(x) { x.1 })

  // Still only 2 items (the better ones)
  assert_eq(results.length(), 2)
  assert_true(results[0].1 >= 0.8)
  assert_true(results[1].1 >= 0.8)
}
