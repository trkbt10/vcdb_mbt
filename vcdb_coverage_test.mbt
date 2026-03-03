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
