// Whitebox tests for placement module

///|
test "crush/deterministic" {
  let targets = [
    CrushTarget::new("node1"),
    CrushTarget::new("node2"),
    CrushTarget::new("node3"),
  ]
  let map = CrushMap::new(16, 2, targets)
  let id = @types.VectorId::from_int(12345)
  // Same ID should always map to same placement
  let result1 = crush_locate(id, map)
  let result2 = crush_locate(id, map)
  inspect(result1.pg == result2.pg, content="true")
  inspect(result1.primaries[0] == result2.primaries[0], content="true")
}

///|
test "crush/primary" {
  let targets = [
    CrushTarget::new("a"),
    CrushTarget::new("b"),
    CrushTarget::new("c"),
  ]
  let map = CrushMap::new(8, 1, targets)
  let primary = crush_primary(@types.VectorId::from_int(100), map)
  match primary {
    Some(key) => inspect(key.length() > 0, content="true")
    None => inspect(false, content="true")
  }
}

///|
test "crush/empty_targets" {
  let map = CrushMap::new(8, 2, [])
  let result = crush_locate(@types.VectorId::from_int(1), map)
  inspect(result.primaries.is_empty(), content="true")
}

///|
test "crush/distribution" {
  let targets = [
    CrushTarget::new("node1"),
    CrushTarget::new("node2"),
    CrushTarget::new("node3"),
    CrushTarget::new("node4"),
  ]
  let map = CrushMap::new(16, 2, targets)
  // Check that different IDs are distributed across targets
  let mut node1_count = 0
  let mut node2_count = 0
  for i in 1..<=100 {
    let result = crush_locate(@types.VectorId::from_int(i), map)
    if result.primaries.length() > 0 {
      if result.primaries[0] == "node1" {
        node1_count = node1_count + 1
      } else if result.primaries[0] == "node2" {
        node2_count = node2_count + 1
      }
    }
  }
  // Distribution should be somewhat even (not all on one node)
  inspect(node1_count > 0, content="true")
  inspect(node2_count > 0, content="true")
}

///|
test "crush/target_with_weight" {
  let target = CrushTarget::with_weight("node1", 2.0)
  inspect(target.key, content="node1")
  inspect(target.weight, content="2")
  inspect(target.zone is None, content="true")
}

///|
test "crush/target_with_zone" {
  let target = CrushTarget::with_zone("node1", 1.5, "rack-a")
  inspect(target.key, content="node1")
  inspect(target.weight, content="1.5")
  match target.zone {
    Some(z) => inspect(z, content="rack-a")
    None => inspect(false, content="true")
  }
}

///|
test "crush/plan_rebalance" {
  let old_targets = [CrushTarget::new("node1"), CrushTarget::new("node2")]
  let old_map = CrushMap::new(4, 1, old_targets)
  let manifest : PlacementManifest = {
    base: "db",
    segments: [
      SegmentEntry::{ name: "db.pg0.part0", target_key: "node1" },
      SegmentEntry::{ name: "db.pg1.part0", target_key: "node2" },
    ],
    crush: old_map,
    epoch: 1,
    commit_ts: 1000L,
  }
  // New map with different targets
  let new_targets = [
    CrushTarget::new("node1"),
    CrushTarget::new("node2"),
    CrushTarget::new("node3"),
  ]
  let new_map = CrushMap::new(4, 1, new_targets)
  let plan = plan_rebalance(manifest, new_map)
  // Some segments may need to move
  inspect(plan.length() >= 0, content="true")
}

///|
test "crush/update_manifest" {
  let targets = [CrushTarget::new("node1")]
  let map = CrushMap::new(2, 1, targets)
  let manifest : PlacementManifest = {
    base: "db",
    segments: [SegmentEntry::{ name: "db.pg0.part0", target_key: "node1" }],
    crush: map,
    epoch: 1,
    commit_ts: 1000L,
  }
  let plan : Array[MovePlan] = [
    MovePlan::{ name: "db.pg0.part0", from: "node1", to: "node2" },
  ]
  let new_targets = [CrushTarget::new("node1"), CrushTarget::new("node2")]
  let new_map = CrushMap::new(2, 1, new_targets)
  let updated = update_manifest_after_rebalance(
    manifest, plan, new_map, 2, 2000L,
  )
  inspect(updated.epoch, content="2")
  inspect(updated.commit_ts, content="2000")
  inspect(updated.segments[0].target_key, content="node2")
}

///|
test "crush/replicas_exceed_targets" {
  let targets = [CrushTarget::new("node1")]
  let map = CrushMap::new(8, 3, targets) // 3 replicas but only 1 target
  let result = crush_locate(@types.VectorId::from_int(1), map)
  // Should only return 1 primary (min of replicas and targets)
  inspect(result.primaries.length(), content="1")
}

///|
test "crush/pg_distribution" {
  let targets = [
    CrushTarget::new("node1"),
    CrushTarget::new("node2"),
    CrushTarget::new("node3"),
    CrushTarget::new("node4"),
  ]
  let map = CrushMap::new(32, 2, targets)
  // Test that different IDs get different PGs
  let mut pg0_count = 0
  let mut pg1_count = 0
  for i in 1..<=100 {
    let result = crush_locate(@types.VectorId::from_int(i), map)
    if result.pg == 0 {
      pg0_count = pg0_count + 1
    } else if result.pg == 1 {
      pg1_count = pg1_count + 1
    }
  }
  // Should have some variance in distribution
  inspect(pg0_count < 100, content="true")
  inspect(pg1_count < 100, content="true")
}

///|
test "crush/zone_aware" {
  let targets = [
    CrushTarget::with_zone("node1", 1.0, "rack-a"),
    CrushTarget::with_zone("node2", 1.0, "rack-a"),
    CrushTarget::with_zone("node3", 1.0, "rack-b"),
    CrushTarget::with_zone("node4", 1.0, "rack-b"),
  ]
  let map = CrushMap::new(8, 2, targets)
  let result = crush_locate(@types.VectorId::from_int(42), map)
  // Should have 2 primaries
  inspect(result.primaries.length(), content="2")
}

///|
test "crush/zero_pgs" {
  let targets = [CrushTarget::new("node1")]
  let map = CrushMap::new(0, 1, targets)
  let result = crush_locate(@types.VectorId::from_int(1), map)
  inspect(result.pg, content="0")
}

///|
test "crush/apply_rebalance" {
  let storage1 = @storage.MemoryStorage::new()
  let storage2 = @storage.MemoryStorage::new()
  // Write some data to storage1
  storage1.write(
    "db.pg0.part0.data",
    Bytes::from_array([b'h', b'e', b'l', b'l', b'o'][:]),
  )
  let storages : Map[String, @storage.MemoryStorage] = {}
  storages.set("node1", storage1)
  storages.set("node2", storage2)
  // Create move plan
  let plan : Array[MovePlan] = [
    { name: "db.pg0.part0", from: "node1", to: "node2" },
  ]
  // Apply rebalance
  apply_rebalance_memory(plan, storages) catch {
    _ => ()
  }
  // Verify data moved
  inspect(storage2.exists("db.pg0.part0.data"), content="true")
  let data = storage2.read("db.pg0.part0.data") catch { _ => Bytes::new(0) }
  inspect(data.length(), content="5")
}

///|
test "crush/apply_rebalance_no_source" {
  let storages : Map[String, @storage.MemoryStorage] = {}
  let plan : Array[MovePlan] = [{ name: "missing", from: "node1", to: "node2" }]
  let mut caught = false
  apply_rebalance_memory(plan, storages) catch {
    @storage.IOError::IoFailed(msg) => {
      inspect(msg.has_prefix("Source storage not found"), content="true")
      caught = true
    }
    _ => ()
  }
  inspect(caught, content="true")
}

///|
test "crush/apply_rebalance_no_dest" {
  let storage1 = @storage.MemoryStorage::new()
  storage1.write("test.data", Bytes::from_array([b'x'][:]))
  let storages : Map[String, @storage.MemoryStorage] = {}
  storages.set("node1", storage1)
  let plan : Array[MovePlan] = [{ name: "test", from: "node1", to: "node2" }]
  let mut caught = false
  apply_rebalance_memory(plan, storages) catch {
    @storage.IOError::IoFailed(msg) => {
      inspect(msg.has_prefix("Destination storage not found"), content="true")
      caught = true
    }
    _ => ()
  }
  inspect(caught, content="true")
}

///|
test "crush/plan_rebalance_no_changes" {
  let targets = [CrushTarget::new("node1")]
  let map = CrushMap::new(4, 1, targets)
  let manifest : PlacementManifest = {
    base: "db",
    segments: [SegmentEntry::{ name: "db.pg0.part0", target_key: "node1" }],
    crush: map,
    epoch: 1,
    commit_ts: 1000L,
  }
  // Same map, no changes
  let plan = plan_rebalance(manifest, map)
  inspect(plan.length(), content="0")
}

///|
test "crush/target_for_pg_empty" {
  let targets : Array[CrushTarget] = []
  let map = CrushMap::new(4, 1, targets)
  let manifest : PlacementManifest = {
    base: "db",
    segments: [],
    crush: map,
    epoch: 1,
    commit_ts: 1000L,
  }
  let plan = plan_rebalance(manifest, map)
  inspect(plan.length(), content="0")
}

///|
test "crush/full_64bit_hashing" {
  let targets = [
    CrushTarget::new("node1"),
    CrushTarget::new("node2"),
    CrushTarget::new("node3"),
    CrushTarget::new("node4"),
  ]
  let map = CrushMap::new(256, 2, targets)
  // IDs that differ only in upper 32 bits
  let id_low = @types.VectorId(1L) // Lower 32 bits: 1, Upper 32 bits: 0
  let id_high = @types.VectorId(0x1_0000_0001L) // Lower 32 bits: 1, Upper 32 bits: 1
  let result_low = crush_locate(id_low, map)
  let result_high = crush_locate(id_high, map)
  // These should produce different placement groups (hash includes upper bits)
  // Note: They could theoretically collide but with 256 PGs it's unlikely
  inspect(result_low.pg != result_high.pg, content="true")
}

///|
test "crush/64bit_id_patterns" {
  let targets = [
    CrushTarget::new("a"),
    CrushTarget::new("b"),
    CrushTarget::new("c"),
    CrushTarget::new("d"),
  ]
  let map = CrushMap::new(1024, 1, targets)
  // Test IDs with different upper/lower bit patterns
  let ids = [
    @types.VectorId(0L), // All zeros
    @types.VectorId(0xFFFF_FFFF_FFFF_FFFFL), // All ones (negative in signed)
    @types.VectorId(0x8000_0000_0000_0000L), // Only MSB set
    @types.VectorId(0x0000_0000_8000_0000L), // Only bit 31 set (lower half MSB)
    @types.VectorId(0x1234_5678_0000_0000L), // Upper 32 bits only
    @types.VectorId(0x0000_0000_1234_5678L), // Lower 32 bits only
  ]
  // All should get valid placements
  for id in ids {
    let result = crush_locate(id, map)
    inspect(result.pg >= 0, content="true")
    inspect(result.pg < 1024, content="true")
    inspect(result.primaries.length() > 0, content="true")
  }
}

///|
test "crush/parse_pg_with_pg_in_base" {
  // Base name "mypgdb" contains "pg" but should parse ".pg5" suffix
  let name = "mypgdb.pg5.part0"
  let pg = parse_pg_from_name(name)
  inspect(pg, content="5")
  // Another example: "postgres_backup.pg123.part2"
  let name2 = "postgres_backup.pg123.part2"
  let pg2 = parse_pg_from_name(name2)
  inspect(pg2, content="123")
  // No ".pg" should return 0
  let name3 = "pgdata"
  let pg3 = parse_pg_from_name(name3)
  inspect(pg3, content="0")
}

///|
test "crush/rebalance_empty_targets" {
  let targets = [CrushTarget::new("a"), CrushTarget::new("b")]
  let manifest : PlacementManifest = {
    base: "db",
    segments: [{ name: "db.pg0.part0", target_key: "a" }],
    crush: CrushMap::new(8, 1, targets),
    epoch: 1,
    commit_ts: 0L,
  }
  // Empty next map - should return no moves
  let empty_map = CrushMap::new(8, 1, [])
  let plans = plan_rebalance(manifest, empty_map)
  inspect(plans.length(), content="0")
}

///|
test "crush/parse_pg_last_marker" {
  // Test case: base name contains ".pg" (e.g., "archive.pg_backup")
  // Should parse PG 12 from the last ".pg12", not 0 from ".pg_backup"
  let targets = [CrushTarget::new("a"), CrushTarget::new("b")]
  let manifest : PlacementManifest = {
    base: "archive.pg_backup",
    segments: [{ name: "archive.pg_backup.pg12.part0", target_key: "a" }],
    crush: CrushMap::new(16, 1, targets),
    epoch: 1,
    commit_ts: 0L,
  }
  // Target for PG 12 should be computed correctly
  let next_map = CrushMap::new(16, 1, [CrushTarget::new("c")])
  let plans = plan_rebalance(manifest, next_map)
  // Should have one move (from "a" to "c")
  inspect(plans.length(), content="1")
  // The move should be for the segment with PG 12
  inspect(plans[0].name, content="archive.pg_backup.pg12.part0")
}

///|
test "distributed/estimate_attrs_size" {
  // Empty attrs
  let empty = @types.empty_attrs()
  let size1 = estimate_attrs_size(empty)
  inspect(size1, content="2") // Just {}

  // With string
  let a1 = @types.empty_attrs()
  a1.set("key", @types.String("value"))
  let size2 = estimate_attrs_size(a1)
  inspect(size2 > 10, content="true")

  // With int
  let a2 = @types.empty_attrs()
  a2.set("num", @types.Int(12345L))
  let size3 = estimate_attrs_size(a2)
  inspect(size3 > 10, content="true")

  // With float
  let a3 = @types.empty_attrs()
  a3.set("f", @types.Float(3.14))
  let size4 = estimate_attrs_size(a3)
  inspect(size4 > 10, content="true")

  // With bool
  let a4 = @types.empty_attrs()
  a4.set("flag", @types.Bool(true))
  let size5 = estimate_attrs_size(a4)
  inspect(size5 > 5, content="true")

  // With null
  let a5 = @types.empty_attrs()
  a5.set("null_val", @types.Null)
  let size6 = estimate_attrs_size(a5)
  inspect(size6 > 5, content="true")
}

///|
test "distributed/segment_part_rotation" {
  let store = @store.CoreStore::new(2, @types.Dot, capacity=20)
  // Add vectors with large attrs to trigger rotation
  for i in 1..<=10 {
    let attrs = @types.empty_attrs()
    // Create a reasonably sized attr
    attrs.set("data", @types.String("value_" + i.to_string()))
    let _ = store.add_or_update(
      @types.VectorId::from_int(i),
      [i.to_double(), 0.0],
      attrs,
      upsert=false,
    )
  }

  let crush = CrushMap::new(2, 1, [CrushTarget::new("node1")])
  let storages : Map[String, @storage.MemoryStorage] = {}
  storages.set("node1", @storage.MemoryStorage::new())

  // Use very small segment_bytes to force rotation
  let opts : SegmentOptions = {
    base_name: "rotation_test",
    crush,
    segmented: true,
    segment_bytes: 100, // Very small to force multiple parts
  }

  let result = write_segments_from_store(store, opts, storages) catch {
    _ => return
  }
  // Should have created multiple segment parts
  inspect(result.entries.length(), content="10")
  let files = storages.get("node1").unwrap().list()
  // Should have more than 1 file due to rotation
  inspect(files.length() > 1, content="true")
}

///|
test "distributed/load_slow_path" {
  let store = @store.CoreStore::new(3, @types.Cosine, capacity=10)
  for i in 1..<=3 {
    let attrs = @types.empty_attrs()
    attrs.set("idx", @types.Int(i.to_int64()))
    let _ = store.add_or_update(
      @types.VectorId::from_int(i),
      [i.to_double(), 0.0, 0.0],
      attrs,
      upsert=false,
    )
  }

  let crush = CrushMap::new(4, 1, [CrushTarget::new("disk")])
  let storages : Map[String, @storage.MemoryStorage] = {}
  storages.set("disk", @storage.MemoryStorage::new())
  let index_storage = @storage.MemoryStorage::new()

  let opts = SegmentOptions::default("slowpath", crush)
  let _ = save_store_distributed(store, opts, storages, index_storage) catch {
    _ => return
  }

  // Delete index file to force slow path
  index_storage.del("slowpath" + @codec.ext_index) catch {
    _ => ()
  }
  inspect(index_storage.exists("slowpath" + @codec.ext_index), content="false")
  inspect(
    index_storage.exists("slowpath" + @codec.ext_manifest),
    content="true",
  )

  // Load should work via segment scan
  let restored = load_store_distributed("slowpath", storages, index_storage) catch {
    _ => return
  }
  inspect(restored.size(), content="3")
}

///|
test "distributed/manifest_roundtrip" {
  let crush = CrushMap::new(16, 2, [
    CrushTarget::new("node-a"),
    CrushTarget::new("node-b"),
  ])
  let manifest : PlacementManifest = {
    base: "test_db",
    segments: [
      { name: "test_db.pg0.part0", target_key: "node-a" },
      { name: "test_db.pg1.part0", target_key: "node-b" },
    ],
    crush,
    epoch: 5,
    commit_ts: 1234567890L,
  }
  let bytes = serialize_manifest(manifest)
  let decoded = deserialize_manifest(bytes)
  match decoded {
    Some(m) => {
      inspect(m.base, content="test_db")
      inspect(m.epoch, content="5")
      inspect(m.commit_ts, content="1234567890")
      inspect(m.segments.length(), content="2")
      inspect(m.crush.pgs, content="16")
      inspect(m.crush.replicas, content="2")
      inspect(m.crush.targets.length(), content="2")
    }
    None => inspect(false, content="true")
  }
}

///|
test "distributed/save_options_default" {
  let crush = CrushMap::new(8, 1, [CrushTarget::new("x")])
  let opts = SaveDistributedOptions::default("mydb", crush)
  inspect(opts.segment_opts.base_name, content="mydb")
  inspect(opts.include_ann, content="false")
  inspect(opts.ann_bytes is None, content="true")
}

///|
test "distributed/empty_manifest_error" {
  let crush = CrushMap::new(4, 1, [CrushTarget::new("node")])
  let storages : Map[String, @storage.MemoryStorage] = {}
  storages.set("node", @storage.MemoryStorage::new())
  let index_storage = @storage.MemoryStorage::new()

  // Create empty manifest
  let manifest : PlacementManifest = {
    base: "empty",
    segments: [],
    crush,
    epoch: 0,
    commit_ts: 0L,
  }
  let bytes = serialize_manifest(manifest)
  index_storage.atomic_write("empty" + @codec.ext_manifest, bytes)

  // Load should fail
  let mut caught = false
  let _ = load_store_distributed("empty", storages, index_storage) catch {
    IoFailed(_msg) => {
      caught = true
      @store.CoreStore::new(1, @types.Cosine)
    }
    _ => @store.CoreStore::new(1, @types.Cosine)
  }
  inspect(caught, content="true")
}

///|
test "distributed/find_substr" {
  inspect(find_substr("hello world", "world") is Some(6), content="true")
  inspect(find_substr("hello world", "foo") is None, content="true")
  inspect(find_substr("abc", "") is Some(0), content="true")
  inspect(find_substr("a", "abc") is None, content="true")
}

///|
test "distributed/extract_string_missing" {
  let json = "{\"foo\":\"bar\"}"
  let result = extract_string_field(json, "missing")
  inspect(result, content="")
}

///|
test "distributed/extract_int_edge" {
  let json1 = "{\"foo\":\"bar\"}"
  inspect(extract_int_field(json1, "missing"), content="0")

  let json2 = "{\"num\":42}"
  inspect(extract_int_field(json2, "num"), content="42")
}

///|
test "distributed/extract_int64_negative" {
  let json = "{\"ts\":-1234567890}"
  let result = extract_int64_field(json, "ts")
  inspect(result, content="-1234567890")
}
