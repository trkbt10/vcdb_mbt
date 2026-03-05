///|
/// Benchmark: hash32 mixing function
test "bench/crush_hash32" (b : @bench.T) {
  b.bench(fn() {
    let mut sum = 0U
    for i in 0..<100 {
      sum = sum + hash32(i.reinterpret_as_uint())
    }
    b.keep(sum.reinterpret_as_int())
  })
}

///|
/// Benchmark: hash64_to_32
test "bench/crush_hash64_to_32" (b : @bench.T) {
  b.bench(fn() {
    let mut sum = 0U
    for i in 0..<100 {
      sum = sum + hash64_to_32(i.to_int64().reinterpret_as_uint64())
    }
    b.keep(sum.reinterpret_as_int())
  })
}

///|
/// Benchmark: crush_locate single ID (4 targets)
test "bench/crush_locate_4_targets" (b : @bench.T) {
  let targets = [
    CrushTarget::new("node1"),
    CrushTarget::new("node2"),
    CrushTarget::new("node3"),
    CrushTarget::new("node4"),
  ]
  let map = CrushMap::new(16, 2, targets)
  let id = @types.VectorId::from_int(12345)
  b.bench(fn() {
    let result = crush_locate(id, map)
    b.keep(result.pg)
  })
}

///|
/// Benchmark: crush_locate batch (100 IDs, 8 targets)
test "bench/crush_locate_batch_100" (b : @bench.T) {
  let targets : Array[CrushTarget] = []
  for i in 0..<8 {
    targets.push(CrushTarget::new("node_" + i.to_string()))
  }
  let map = CrushMap::new(32, 3, targets)
  b.bench(fn() {
    let mut sum = 0
    for i in 0..<100 {
      let result = crush_locate(@types.VectorId::from_int(i), map)
      sum = sum + result.pg
    }
    b.keep(sum)
  })
}

///|
/// Benchmark: crush_primary lookup
test "bench/crush_primary" (b : @bench.T) {
  let targets = [
    CrushTarget::new("node1"),
    CrushTarget::new("node2"),
    CrushTarget::new("node3"),
  ]
  let map = CrushMap::new(16, 1, targets)
  let id = @types.VectorId::from_int(999)
  b.bench(fn() {
    match crush_primary(id, map) {
      Some(s) => b.keep(s.length())
      None => b.keep(0)
    }
  })
}

///|
/// Benchmark: choose_primaries with 16 targets
test "bench/crush_choose_primaries" (b : @bench.T) {
  b.bench(fn() {
    let mut sum = 0
    for pg in 0..<32 {
      let indices = choose_primaries(pg, 3, 16)
      sum = sum + indices.length()
    }
    b.keep(sum)
  })
}

///|
/// Benchmark: plan_rebalance (no changes)
test "bench/crush_plan_rebalance_no_change" (b : @bench.T) {
  let targets = [
    CrushTarget::new("node1"),
    CrushTarget::new("node2"),
    CrushTarget::new("node3"),
  ]
  let crush = CrushMap::new(8, 2, targets)
  let segments : Array[SegmentEntry] = []
  for i in 0..<8 {
    let primary = match crush_primary(@types.VectorId::from_int(i), crush) {
      Some(p) => p
      None => "node1"
    }
    segments.push({
      name: "db.pg" + i.to_string() + ".part0",
      target_key: primary,
    })
  }
  let manifest : PlacementManifest = {
    base: "db",
    segments,
    crush,
    epoch: 1,
    commit_ts: 1000L,
  }
  b.bench(fn() { b.keep(plan_rebalance(manifest, crush).length()) })
}

///|
/// Benchmark: plan_rebalance (with changes)
test "bench/crush_plan_rebalance_with_change" (b : @bench.T) {
  let old_targets = [
    CrushTarget::new("node1"),
    CrushTarget::new("node2"),
    CrushTarget::new("node3"),
  ]
  let new_targets = [
    CrushTarget::new("node1"),
    CrushTarget::new("node2"),
    CrushTarget::new("node3"),
    CrushTarget::new("node4"),
  ]
  let old_crush = CrushMap::new(8, 2, old_targets)
  let new_crush = CrushMap::new(8, 2, new_targets)
  let segments : Array[SegmentEntry] = []
  for i in 0..<8 {
    let primary = match crush_primary(@types.VectorId::from_int(i), old_crush) {
      Some(p) => p
      None => "node1"
    }
    segments.push({
      name: "db.pg" + i.to_string() + ".part0",
      target_key: primary,
    })
  }
  let manifest : PlacementManifest = {
    base: "db",
    segments,
    crush: old_crush,
    epoch: 1,
    commit_ts: 1000L,
  }
  b.bench(fn() { b.keep(plan_rebalance(manifest, new_crush).length()) })
}

///|
/// Benchmark: parse_pg_from_name
test "bench/crush_parse_pg_from_name" (b : @bench.T) {
  let names = [
    "db.pg0.part0", "db.pg15.part2", "mydb.pg123.part5", "complex.name.pg42.part0",
  ]
  b.bench(fn() {
    let mut sum = 0
    for name in names {
      sum = sum + parse_pg_from_name(name)
    }
    b.keep(sum)
  })
}

///|
/// Benchmark: update_manifest_after_rebalance
test "bench/crush_update_manifest" (b : @bench.T) {
  let targets = [CrushTarget::new("node1"), CrushTarget::new("node2")]
  let crush = CrushMap::new(4, 1, targets)
  let segments : Array[SegmentEntry] = []
  for i in 0..<4 {
    segments.push({
      name: "db.pg" + i.to_string() + ".part0",
      target_key: "node1",
    })
  }
  let manifest : PlacementManifest = {
    base: "db",
    segments,
    crush,
    epoch: 1,
    commit_ts: 1000L,
  }
  let plan : Array[MovePlan] = [
    { name: "db.pg1.part0", from: "node1", to: "node2" },
    { name: "db.pg3.part0", from: "node1", to: "node2" },
  ]
  b.bench(fn() {
    let updated = update_manifest_after_rebalance(
      manifest, plan, crush, 2, 2000L,
    )
    b.keep(updated.segments.length())
  })
}
