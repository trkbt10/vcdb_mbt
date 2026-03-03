///|
/// Comprehensive tests for CRUSH-based distributed storage
/// Tests segmentation, placement, and distributed save/load

// =============================================================================
// Section 1: Segment Writer/Reader Tests
// =============================================================================

///|
/// Test: Segment writer creates valid segment
test "distributed/segment/writer_basic" {
  let writer = @persistence.SegmentWriter::new("test.pg0.part0")

  let attrs = @core.empty_attrs()
  attrs.set("name", @core.String("v1"))

  let ptr = writer.append(@core.VectorId::from_int(1), [1.0, 2.0, 3.0], attrs)

  assert_eq!(ptr.segment, "test.pg0.part0")
  assert_eq!(ptr.offset, 8) // After 8-byte header
  assert_true!(ptr.length > 0)

  let bytes = writer.to_bytes()
  assert_true!(bytes.length() > 8)
}

///|
/// Test: Segment reader reads back written data
test "distributed/segment/roundtrip" {
  let writer = @persistence.SegmentWriter::new("test.pg0.part0")

  let attrs1 = @core.empty_attrs()
  attrs1.set("idx", @core.Int(1L))
  let _ = writer.append(@core.VectorId::from_int(1), [1.0, 0.0], attrs1)

  let attrs2 = @core.empty_attrs()
  attrs2.set("idx", @core.Int(2L))
  let _ = writer.append(@core.VectorId::from_int(2), [0.0, 1.0], attrs2)

  let bytes = writer.to_bytes()

  let reader = @persistence.SegmentReader::from_bytes("test.pg0.part0", bytes)
  assert_true!(reader.is_some())

  let records = reader.unwrap().collect()
  assert_eq!(records.length(), 2)

  // Check first record
  let (id1, vec1, a1) = records[0]
  assert_eq!(id1.to_int64(), 1L)
  assert_eq!(vec1.length(), 2)
  assert_eq!(vec1[0], 1.0)
  match a1.get("idx") {
    Some(@core.Int(n)) => assert_eq!(n, 1L)
    _ => assert_true!(false)
  }

  // Check second record
  let (id2, vec2, _) = records[1]
  assert_eq!(id2.to_int64(), 2L)
  assert_eq!(vec2[1], 1.0)
}

///|
/// Test: Segment reader handles invalid data
test "distributed/segment/invalid_magic" {
  let bad_data = Bytes::from_array([b'B', b'A', b'D', b'!', 0, 0, 0, 1][:])
  let reader = @persistence.SegmentReader::from_bytes("bad", bad_data)
  assert_true!(reader.is_none())
}

///|
/// Test: Segment reader handles empty segment (header only)
test "distributed/segment/empty_segment" {
  let writer = @persistence.SegmentWriter::new("empty.pg0.part0")
  let bytes = writer.to_bytes()

  let reader = @persistence.SegmentReader::from_bytes("empty.pg0.part0", bytes)
  assert_true!(reader.is_some())

  let records = reader.unwrap().collect()
  assert_eq!(records.length(), 0)
}

// =============================================================================
// Section 2: CRUSH Placement with Segmentation Tests
// =============================================================================

///|
/// Test: Write segments distributes data by CRUSH placement
test "distributed/crush/write_segments" {
  let store = @core.CoreStore::new(3, @core.Cosine, capacity=10)

  // Add vectors
  for i in 1..=5 {
    let attrs = @core.empty_attrs()
    attrs.set("i", @core.Int(i.to_int64()))
    let _ = store.add_or_update(
      @core.VectorId::from_int(i),
      [i.to_double(), 0.0, 0.0],
      attrs,
      upsert=false,
    )
  }

  // Create CRUSH map with 2 targets
  let crush = @persistence.CrushMap::new(
    4, // 4 placement groups
    1, // 1 replica
    [
      @persistence.CrushTarget::new("storage-a"),
      @persistence.CrushTarget::new("storage-b"),
    ],
  )

  // Create storages
  let storages : Map[String, @persistence.MemoryStorage] = {}
  storages.set("storage-a", @persistence.MemoryStorage::new())
  storages.set("storage-b", @persistence.MemoryStorage::new())

  let opts = @persistence.SegmentOptions::default("test", crush)
  let result = @persistence.write_segments_from_store!(store, opts, storages)

  // Should have some entries
  assert_eq!(result.entries.length(), 5)
  assert_eq!(result.count, 5)
  assert_eq!(result.dim, 3)

  // Manifest should have segments
  assert_true!(result.manifest.segments.length() > 0)

  // At least one storage should have data
  let a_files = storages.get("storage-a").unwrap().list()
  let b_files = storages.get("storage-b").unwrap().list()
  assert_true!(a_files.length() > 0 || b_files.length() > 0)
}

///|
/// Test: Read segments from manifest
test "distributed/crush/read_segments" {
  // Create store and write segments
  let store = @core.CoreStore::new(2, @core.Cosine, capacity=10)
  for i in 1..=3 {
    let attrs = @core.empty_attrs()
    attrs.set("value", @core.Int(i.to_int64() * 10L))
    let _ = store.add_or_update(
      @core.VectorId::from_int(i),
      [i.to_double(), (10 - i).to_double()],
      attrs,
      upsert=false,
    )
  }

  let crush = @persistence.CrushMap::new(
    2,
    1,
    [@persistence.CrushTarget::new("local")],
  )

  let storages : Map[String, @persistence.MemoryStorage] = {}
  storages.set("local", @persistence.MemoryStorage::new())

  let opts = @persistence.SegmentOptions::default("mydb", crush)
  let result = @persistence.write_segments_from_store!(store, opts, storages)

  // Read back
  let records = @persistence.read_segments_from_manifest!(result.manifest, storages)
  assert_eq!(records.length(), 3)

  // Verify each record
  for record in records {
    let (id, vec, attrs) = record
    assert_true!(id.to_int64() >= 1L && id.to_int64() <= 3L)
    assert_eq!(vec.length(), 2)
    match attrs.get("value") {
      Some(@core.Int(_)) => ()
      _ => assert_true!(false)
    }
  }
}

// =============================================================================
// Section 3: Distributed Save/Load Tests
// =============================================================================

///|
/// Test: Save and load store distributed
test "distributed/store/save_load_roundtrip" {
  // Create store with data
  let store = @core.CoreStore::new(3, @core.Cosine, capacity=20)
  for i in 1..=10 {
    let attrs = @core.empty_attrs()
    attrs.set("name", @core.String("item-" + i.to_string()))
    attrs.set("score", @core.Float(i.to_double() / 10.0))
    let _ = store.add_or_update(
      @core.VectorId::from_int(i),
      [i.to_double(), (i * 2).to_double(), (i * 3).to_double()],
      attrs,
      upsert=false,
    )
  }

  // Setup distributed storage
  let crush = @persistence.CrushMap::new(
    8,
    1,
    [
      @persistence.CrushTarget::new("s3-us"),
      @persistence.CrushTarget::new("s3-eu"),
      @persistence.CrushTarget::new("s3-asia"),
    ],
  )

  let data_storages : Map[String, @persistence.MemoryStorage] = {}
  data_storages.set("s3-us", @persistence.MemoryStorage::new())
  data_storages.set("s3-eu", @persistence.MemoryStorage::new())
  data_storages.set("s3-asia", @persistence.MemoryStorage::new())
  let index_storage = @persistence.MemoryStorage::new()

  let opts = @persistence.SegmentOptions::default("distributed-db", crush)

  // Save
  let _ = @persistence.save_store_distributed!(store, opts, data_storages, index_storage)

  // Verify index files exist
  assert_true!(index_storage.exists("distributed-db.manifest.json"))
  assert_true!(index_storage.exists("distributed-db.index"))

  // Load from fast path (index file)
  let restored = @persistence.load_store_distributed!(
    "distributed-db",
    data_storages,
    index_storage,
  )

  assert_eq!(restored.size(), 10)

  // Verify data
  for i in 1..=10 {
    let id = @core.VectorId::from_int(i)
    assert_true!(restored.has(id))
    match restored.get(id) {
      Some(rec) =>
        match rec.attrs.get("name") {
          Some(@core.String(s)) => assert_eq!(s, "item-" + i.to_string())
          _ => assert_true!(false)
        }
      None => assert_true!(false)
    }
  }
}

///|
/// Test: Load from segments (slow path)
test "distributed/store/load_from_segments" {
  // Create store with data
  let store = @core.CoreStore::new(2, @core.Cosine, capacity=10)
  for i in 1..=5 {
    let attrs = @core.empty_attrs()
    attrs.set("x", @core.Int(i.to_int64()))
    let _ = store.add_or_update(
      @core.VectorId::from_int(i),
      [i.to_double(), 0.0],
      attrs,
      upsert=false,
    )
  }

  // Setup storage
  let crush = @persistence.CrushMap::new(
    4,
    1,
    [@persistence.CrushTarget::new("disk")],
  )
  let data_storages : Map[String, @persistence.MemoryStorage] = {}
  data_storages.set("disk", @persistence.MemoryStorage::new())
  let index_storage = @persistence.MemoryStorage::new()

  let opts = @persistence.SegmentOptions::default("slowpath-db", crush)
  let _ = @persistence.save_store_distributed!(store, opts, data_storages, index_storage)

  // Delete the .index file to force slow path
  index_storage.del!("slowpath-db.index")
  assert_false!(index_storage.exists("slowpath-db.index"))
  assert_true!(index_storage.exists("slowpath-db.manifest.json"))

  // Load should work via segments
  let restored = @persistence.load_store_distributed!(
    "slowpath-db",
    data_storages,
    index_storage,
  )

  assert_eq!(restored.size(), 5)
}

// =============================================================================
// Section 4: Rebalance Tests
// =============================================================================

///|
/// Test: Plan rebalance when targets change
test "distributed/rebalance/plan" {
  // Initial CRUSH map
  let crush1 = @persistence.CrushMap::new(
    4,
    1,
    [
      @persistence.CrushTarget::new("A"),
      @persistence.CrushTarget::new("B"),
    ],
  )

  // Create manifest with segments
  let manifest = @persistence.PlacementManifest::{
    base: "test",
    segments: [
      { name: "test.pg0.part0", target_key: "A" },
      { name: "test.pg1.part0", target_key: "B" },
      { name: "test.pg2.part0", target_key: "A" },
      { name: "test.pg3.part0", target_key: "B" },
    ],
    crush: crush1,
    epoch: 1,
    commit_ts: 1000L,
  }

  // New CRUSH map with additional target
  let crush2 = @persistence.CrushMap::new(
    4,
    1,
    [
      @persistence.CrushTarget::new("A"),
      @persistence.CrushTarget::new("B"),
      @persistence.CrushTarget::new("C"),
    ],
  )

  let plan = @persistence.plan_rebalance(manifest, crush2)

  // Some segments may need to move
  // The exact moves depend on the hash function
  // Just verify the plan is valid
  for mv in plan {
    assert_true!(mv.from == "A" || mv.from == "B")
    assert_true!(mv.to == "A" || mv.to == "B" || mv.to == "C")
    assert_true!(mv.from != mv.to)
  }
}

///|
/// Test: Apply rebalance moves data
test "distributed/rebalance/apply" {
  // Create storages
  let storages : Map[String, @persistence.MemoryStorage] = {}
  storages.set("A", @persistence.MemoryStorage::new())
  storages.set("B", @persistence.MemoryStorage::new())

  // Add data to A
  storages.get("A").unwrap().write("seg1.data", Bytes::from_array([b'\x01', b'\x02', b'\x03'][:]))

  // Plan to move from A to B
  let plan = [
    @persistence.MovePlan::{ name: "seg1", from: "A", to: "B" },
  ]

  // Apply
  @persistence.apply_rebalance_memory!(plan, storages)

  // Data should be in B now
  assert_true!(storages.get("B").unwrap().exists("seg1.data"))
  // And removed from A
  assert_false!(storages.get("A").unwrap().exists("seg1.data"))
}

// =============================================================================
// Section 5: Distribution Uniformity Tests
// =============================================================================

///|
/// Test: CRUSH distributes across targets roughly uniformly
test "distributed/crush/uniform_distribution" {
  let crush = @persistence.CrushMap::new(
    64, // Many PGs for better distribution
    1,
    [
      @persistence.CrushTarget::new("t0"),
      @persistence.CrushTarget::new("t1"),
      @persistence.CrushTarget::new("t2"),
      @persistence.CrushTarget::new("t3"),
    ],
  )

  let counts : Map[String, Int] = {}
  counts.set("t0", 0)
  counts.set("t1", 0)
  counts.set("t2", 0)
  counts.set("t3", 0)

  // Place 1000 vectors
  for i in 1..=1000 {
    let result = @persistence.crush_locate(@core.VectorId::from_int(i), crush)
    let target = result.primaries[0]
    counts.set(target, counts.get(target).or(0) + 1)
  }

  // Each target should have roughly 250 (25%)
  // Allow 15% deviation
  for key in counts.keys() {
    let count = counts.get(key).or(0)
    assert_true!(count > 150) // At least 15%
    assert_true!(count < 400) // At most 40%
  }
}

///|
/// Test: Same ID always maps to same target
test "distributed/crush/deterministic" {
  let crush = @persistence.CrushMap::new(
    32,
    1,
    [
      @persistence.CrushTarget::new("X"),
      @persistence.CrushTarget::new("Y"),
      @persistence.CrushTarget::new("Z"),
    ],
  )

  // Check determinism
  for i in 1..=100 {
    let id = @core.VectorId::from_int(i * 1000)
    let r1 = @persistence.crush_locate(id, crush)
    let r2 = @persistence.crush_locate(id, crush)
    assert_eq!(r1.pg, r2.pg)
    assert_eq!(r1.primaries[0], r2.primaries[0])
  }
}

// =============================================================================
// Section 6: Edge Cases
// =============================================================================

///|
/// Test: Empty store save/load
test "distributed/edge/empty_store" {
  let store = @core.CoreStore::new(3, @core.Cosine, capacity=10)

  let crush = @persistence.CrushMap::new(
    4,
    1,
    [@persistence.CrushTarget::new("solo")],
  )

  let storages : Map[String, @persistence.MemoryStorage] = {}
  storages.set("solo", @persistence.MemoryStorage::new())
  let index_storage = @persistence.MemoryStorage::new()

  let opts = @persistence.SegmentOptions::default("empty", crush)
  let _ = @persistence.save_store_distributed!(store, opts, storages, index_storage)

  // Should be loadable
  let restored = @persistence.load_store_distributed!(
    "empty",
    storages,
    index_storage,
  )
  assert_eq!(restored.size(), 0)
}

///|
/// Test: Single target CRUSH map
test "distributed/edge/single_target" {
  let crush = @persistence.CrushMap::new(
    8,
    1,
    [@persistence.CrushTarget::new("only")],
  )

  // All IDs should map to "only"
  for i in 1..=100 {
    let result = @persistence.crush_locate(@core.VectorId::from_int(i), crush)
    assert_eq!(result.primaries.length(), 1)
    assert_eq!(result.primaries[0], "only")
  }
}

///|
/// Test: CRUSH with no targets
test "distributed/edge/no_targets" {
  let crush = @persistence.CrushMap::new(8, 1, [])

  let result = @persistence.crush_locate(@core.VectorId::from_int(1), crush)
  assert_eq!(result.primaries.length(), 0)
}

///|
/// Test: Large vector dimensions
test "distributed/edge/large_dim" {
  let dim = 512
  let store = @core.CoreStore::new(dim, @core.Cosine, capacity=10)

  let vec : Array[Double] = []
  for i in 0..<dim {
    vec.push(i.to_double() / dim.to_double())
  }
  let _ = store.add_or_update(
    @core.VectorId::from_int(1),
    vec,
    @core.empty_attrs(),
    upsert=false,
  )

  let crush = @persistence.CrushMap::new(
    4,
    1,
    [@persistence.CrushTarget::new("big")],
  )

  let storages : Map[String, @persistence.MemoryStorage] = {}
  storages.set("big", @persistence.MemoryStorage::new())
  let index_storage = @persistence.MemoryStorage::new()

  let opts = @persistence.SegmentOptions::default("largedim", crush)
  let _ = @persistence.save_store_distributed!(store, opts, storages, index_storage)

  let restored = @persistence.load_store_distributed!(
    "largedim",
    storages,
    index_storage,
  )
  assert_eq!(restored.size(), 1)
  assert_eq!(restored.dim, 512)
}

///|
/// Test: Replicas > 1
test "distributed/edge/multiple_replicas" {
  let crush = @persistence.CrushMap::new(
    8,
    3, // 3 replicas
    [
      @persistence.CrushTarget::new("r1"),
      @persistence.CrushTarget::new("r2"),
      @persistence.CrushTarget::new("r3"),
      @persistence.CrushTarget::new("r4"),
    ],
  )

  let result = @persistence.crush_locate(@core.VectorId::from_int(42), crush)
  assert_eq!(result.primaries.length(), 3)

  // All primaries should be different
  assert_true!(result.primaries[0] != result.primaries[1])
  assert_true!(result.primaries[1] != result.primaries[2])
  assert_true!(result.primaries[0] != result.primaries[2])
}

// =============================================================================
// Section 7: Manifest Serialization Tests
// =============================================================================

// =============================================================================
// Section 8: Index File Tests
// =============================================================================

///|
/// Test: Index file encode/decode roundtrip
test "distributed/index_file/roundtrip" {
  let header = @persistence.IndexHeader::{
    metric_code: 0, // Cosine
    dim: 3,
    count: 2,
    strategy_code: 1, // HNSW
    has_ann: false,
  }

  let entries = [
    @persistence.IndexEntry::{
      id: @core.VectorId::from_int(1),
      ptr: @persistence.DataPointer::{
        segment: "db.pg0.part0",
        offset: 8,
        length: 32,
      },
    },
    @persistence.IndexEntry::{
      id: @core.VectorId::from_int(2),
      ptr: @persistence.DataPointer::{
        segment: "db.pg1.part0",
        offset: 8,
        length: 48,
      },
    },
  ]

  let bytes = @persistence.encode_index_file(header, entries, None)
  assert_true!(bytes.length() > 36) // header(16) + info(20)

  let decoded = @persistence.decode_index_file(bytes)
  assert_true!(decoded.is_some())

  let d = decoded.unwrap()
  assert_eq!(d.header.dim, 3)
  assert_eq!(d.header.count, 2)
  assert_eq!(d.header.metric_code, 0)
  assert_eq!(d.header.strategy_code, 1)
  assert_false!(d.header.has_ann)

  assert_eq!(d.entries.length(), 2)
  assert_eq!(d.entries[0].id.to_int64(), 1L)
  assert_eq!(d.entries[0].ptr.segment, "db.pg0.part0")
  assert_eq!(d.entries[1].id.to_int64(), 2L)
}

///|
/// Test: Index file with ANN bytes
test "distributed/index_file/with_ann" {
  let header = @persistence.IndexHeader::{
    metric_code: 2, // Dot
    dim: 4,
    count: 1,
    strategy_code: 1, // HNSW
    has_ann: true,
  }

  let entries = [
    @persistence.IndexEntry::{
      id: @core.VectorId::from_int(42),
      ptr: @persistence.DataPointer::{
        segment: "test.pg0.part0",
        offset: 16,
        length: 64,
      },
    },
  ]

  // Simulated ANN bytes
  let ann_bytes = Bytes::from_array(
    [b'\x01', b'\x02', b'\x03', b'\x04', b'\x05', b'\x06', b'\x07', b'\x08'][:],
  )

  let bytes = @persistence.encode_index_file(header, entries, Some(ann_bytes))

  let decoded = @persistence.decode_index_file(bytes)
  assert_true!(decoded.is_some())

  let d = decoded.unwrap()
  assert_true!(d.header.has_ann)
  assert_true!(d.ann.is_some())
  assert_eq!(d.ann.unwrap().length(), 8)
}

///|
/// Test: Index file with 64-bit vector IDs
test "distributed/index_file/64bit_ids" {
  let header = @persistence.IndexHeader::{
    metric_code: 0,
    dim: 2,
    count: 2,
    strategy_code: 0,
    has_ann: false,
  }

  // Use large 64-bit IDs
  let large_id1 = @core.VectorId(0x100000001L) // > 32-bit
  let large_id2 = @core.VectorId(@int64.max_value)

  let entries = [
    @persistence.IndexEntry::{
      id: large_id1,
      ptr: @persistence.DataPointer::{ segment: "seg1", offset: 8, length: 20 },
    },
    @persistence.IndexEntry::{
      id: large_id2,
      ptr: @persistence.DataPointer::{ segment: "seg2", offset: 8, length: 20 },
    },
  ]

  let bytes = @persistence.encode_index_file(header, entries, None)
  let decoded = @persistence.decode_index_file(bytes).unwrap()

  assert_eq!(decoded.entries[0].id.to_int64(), 0x100000001L)
  assert_eq!(decoded.entries[1].id.to_int64(), @int64.max_value)
}

///|
/// Test: Invalid index file magic
test "distributed/index_file/invalid_magic" {
  let bad_bytes = Bytes::from_array(
    [b'B', b'A', b'D', b'!', 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
      0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0][:],
  )
  let decoded = @persistence.decode_index_file(bad_bytes)
  assert_true!(decoded.is_none())
}

///|
/// Test: Save and load with ANN bytes
test "distributed/index_file/save_load_with_ann" {
  let store = @core.CoreStore::new(3, @core.Cosine, capacity=10)
  for i in 1..=5 {
    let _ = store.add_or_update(
      @core.VectorId::from_int(i),
      [i.to_double(), 0.0, 0.0],
      @core.empty_attrs(),
      upsert=false,
    )
  }

  let crush = @persistence.CrushMap::new(
    4,
    1,
    [@persistence.CrushTarget::new("node")],
  )

  let data_storages : Map[String, @persistence.MemoryStorage] = {}
  data_storages.set("node", @persistence.MemoryStorage::new())
  let index_storage = @persistence.MemoryStorage::new()

  // Simulated ANN bytes
  let ann_bytes = Bytes::from_array(
    [b'\xAA', b'\xBB', b'\xCC', b'\xDD'][:],
  )

  let opts = @persistence.SegmentOptions::default("ann-test", crush)
  let _ = @persistence.save_store_distributed_with_ann!(
    store,
    opts,
    data_storages,
    index_storage,
    @core.HNSW(@core.HNSWParams::default()),
    Some(ann_bytes),
  )

  // Load and verify ANN bytes are preserved
  let result = @persistence.load_store_distributed_full!(
    "ann-test",
    data_storages,
    index_storage,
  )

  assert_eq!(result.store.size(), 5)
  assert_true!(result.header.has_ann)
  assert_true!(result.ann_bytes.is_some())
  assert_eq!(result.ann_bytes.unwrap().length(), 4)
}

///|
/// Test: Manifest roundtrip through JSON
test "distributed/manifest/json_roundtrip" {
  let store = @core.CoreStore::new(2, @core.Cosine, capacity=10)
  let _ = store.add_or_update(
    @core.VectorId::from_int(1),
    [1.0, 0.0],
    @core.empty_attrs(),
    upsert=false,
  )

  let crush = @persistence.CrushMap::new(
    16,
    2,
    [
      @persistence.CrushTarget::new("node-a"),
      @persistence.CrushTarget::new("node-b"),
    ],
  )

  let storages : Map[String, @persistence.MemoryStorage] = {}
  storages.set("node-a", @persistence.MemoryStorage::new())
  storages.set("node-b", @persistence.MemoryStorage::new())
  let index_storage = @persistence.MemoryStorage::new()

  let opts = @persistence.SegmentOptions::default("jsontest", crush)
  let manifest = @persistence.save_store_distributed!(store, opts, storages, index_storage)

  // Manifest should be valid
  assert_eq!(manifest.base, "jsontest")
  assert_true!(manifest.segments.length() > 0)
  assert_eq!(manifest.crush.pgs, 16)
  assert_eq!(manifest.crush.replicas, 2)
  assert_eq!(manifest.crush.targets.length(), 2)
}
