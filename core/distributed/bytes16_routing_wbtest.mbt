///|
/// Distributed routing tests for Bytes16Id (UUID / ULID-style IDs).
///
/// ULID structure (128 bits, big-endian):
///   [0..5]   48-bit millisecond timestamp
///   [6..15]  80-bit random payload
///
/// UUID v4 structure (128 bits):
///   All fields randomised, version nibble = 0x4, variant bits = 0b10xx
///
/// These tests verify that:
/// - Bytes16Id routes deterministically through CRUSH
/// - ULID-style IDs (monotone timestamp + random suffix) distribute across targets
/// - UUID v4 IDs distribute across targets
/// - Mixed Int64Id + Bytes16Id batches route correctly
/// - TransportPoint serialisation survives a target round-trip with Bytes16Id

///|
/// Construct a ULID-style Bytes16 from a 48-bit ms timestamp and an 80-bit
/// random value.
fn ulid_bytes(
  ts_ms : UInt64,
  rand_hi : UInt,
  rand_lo : UInt64,
) -> @types.Bytes16 {
  let b0 = ((ts_ms >> 40) & 0xFFUL).to_int().to_byte()
  let b1 = ((ts_ms >> 32) & 0xFFUL).to_int().to_byte()
  let b2 = ((ts_ms >> 24) & 0xFFUL).to_int().to_byte()
  let b3 = ((ts_ms >> 16) & 0xFFUL).to_int().to_byte()
  let b4 = ((ts_ms >> 8) & 0xFFUL).to_int().to_byte()
  let b5 = (ts_ms & 0xFFUL).to_int().to_byte()
  let hi16 = rand_hi & 0xFFFFU
  let b6 = ((hi16 >> 8) & 0xFFU).reinterpret_as_int().to_byte()
  let b7 = (hi16 & 0xFFU).reinterpret_as_int().to_byte()
  let b8 = ((rand_lo >> 56) & 0xFFUL).to_int().to_byte()
  let b9 = ((rand_lo >> 48) & 0xFFUL).to_int().to_byte()
  let b10 = ((rand_lo >> 40) & 0xFFUL).to_int().to_byte()
  let b11 = ((rand_lo >> 32) & 0xFFUL).to_int().to_byte()
  let b12 = ((rand_lo >> 24) & 0xFFUL).to_int().to_byte()
  let b13 = ((rand_lo >> 16) & 0xFFUL).to_int().to_byte()
  let b14 = ((rand_lo >> 8) & 0xFFUL).to_int().to_byte()
  let b15 = (rand_lo & 0xFFUL).to_int().to_byte()
  @types.Bytes16::{
    b0,
    b1,
    b2,
    b3,
    b4,
    b5,
    b6,
    b7,
    b8,
    b9,
    b10,
    b11,
    b12,
    b13,
    b14,
    b15,
  }
}

///|
/// Standard 4-node, 16-PG cluster map used by most tests.
fn make_cluster(pgs : Int, replicas : Int) -> @placement.CrushMap {
  @placement.CrushMap::new(pgs, replicas, [
    @placement.CrushTarget::new("shard-0"),
    @placement.CrushTarget::new("shard-1"),
    @placement.CrushTarget::new("shard-2"),
    @placement.CrushTarget::new("shard-3"),
  ])
}

///|
/// Helper: get placement group for an ID (replaces old shard_for_id).
fn pg_for_id(id : @types.VectorId, map : @placement.CrushMap) -> Int {
  @placement.crush_locate(id, map).pg
}

///|
/// Helper: get targets for an ID (replaces old replicas_for_id).
fn test_targets_for_id(
  id : @types.VectorId,
  map : @placement.CrushMap,
) -> Array[@placement.TargetKey] {
  targets_for_id(id, map)
}

///|
/// Helper: group by PG (replaces old group_by_shard).
fn group_by_pg(
  points : Array[(@types.VectorId, Array[Double], @types.Attrs)],
  map : @placement.CrushMap,
) -> Map[Int, Array[(@types.VectorId, Array[Double], @types.Attrs)]] {
  let groups : Map[Int, Array[(@types.VectorId, Array[Double], @types.Attrs)]] = {}
  for point in points {
    let (id, _, _) = point
    let pg = pg_for_id(id, map)
    match groups.get(pg) {
      Some(arr) => arr.push(point)
      None => groups.set(pg, [point])
    }
  }
  groups
}

// ── determinism ────────────────────────────────────────────────────────────

///|
test "ulid/routing_is_deterministic" {
  let map = make_cluster(16, 1)
  let id = @types.Bytes16Id(
    ulid_bytes(1_700_000_000_000UL, 0xABCDU, 0x0102030405060708UL),
  )
  // Same ID must always route to the same PG
  let pg_a = pg_for_id(id, map)
  let pg_b = pg_for_id(id, map)
  let pg_c = pg_for_id(id, map)
  @test.assert_eq(pg_a, pg_b)
  @test.assert_eq(pg_b, pg_c)
  assert_true(pg_a >= 0 && pg_a < 16)
}

///|
test "uuid/routing_is_deterministic" {
  let map = make_cluster(16, 1)
  // UUID v4: 550e8400-e29b-41d4-a716-446655440000
  let id = @types.Bytes16Id(@types.Bytes16::{
    b0: b'\x55',
    b1: b'\x0e',
    b2: b'\x84',
    b3: b'\x00',
    b4: b'\xe2',
    b5: b'\x9b',
    b6: b'\x41',
    b7: b'\xd4',
    b8: b'\xa7',
    b9: b'\x16',
    b10: b'\x44',
    b11: b'\x66',
    b12: b'\x55',
    b13: b'\x44',
    b14: b'\x00',
    b15: b'\x00',
  })
  let s1 = pg_for_id(id, map)
  let s2 = pg_for_id(id, map)
  @test.assert_eq(s1, s2)
  assert_true(s1 >= 0 && s1 < 16)
}

// ── distribution ───────────────────────────────────────────────────────────

///|
test "ulid/same_timestamp_different_random_distributes_across_targets" {
  let map = make_cluster(16, 1)
  let ts = 1_700_000_000_000UL
  let pg_set : Map[Int, Bool] = {}
  for i in 0UL..<64UL {
    let id = @types.Bytes16Id(ulid_bytes(ts, 0U, i * 0x0102030405060708UL))
    let pg = pg_for_id(id, map)
    pg_set.set(pg, true)
  }
  assert_true(pg_set.length() > 1)
}

///|
test "ulid/monotone_timestamps_distribute_across_targets" {
  let map = make_cluster(16, 1)
  let pg_counts : Map[Int, Int] = {}
  for i in 0..<16 {
    pg_counts.set(i, 0)
  }
  let base_ts = 1_700_000_000_000UL
  for i in 0UL..<100UL {
    let id = @types.Bytes16Id(ulid_bytes(base_ts + i, 0xDEADU, i))
    let pg = pg_for_id(id, map)
    match pg_counts.get(pg) {
      Some(c) => pg_counts.set(pg, c + 1)
      None => pg_counts.set(pg, 1)
    }
  }
  let mut max_load = 0
  for _, count in pg_counts {
    if count > max_load {
      max_load = count
    }
  }
  assert_true(max_load < 100)
  let mut used = 0
  for _, count in pg_counts {
    if count > 0 {
      used = used + 1
    }
  }
  assert_true(used >= 2)
}

///|
test "uuid/random_ids_distribute_across_targets" {
  let map = make_cluster(16, 1)
  let pg_set : Map[Int, Bool] = {}
  for i in 0..<64 {
    let iv = i.to_uint64()
    let b = @types.Bytes16::{
      b0: ((iv * 6364136223846793005UL + 1442695040888963407UL) & 0xFFUL)
      .to_int()
      .to_byte(),
      b1: ((iv * 2862933555777941757UL + 3037000493UL) & 0xFFUL)
      .to_int()
      .to_byte(),
      b2: ((iv * 1442695040888963407UL) & 0xFFUL).to_int().to_byte(),
      b3: ((iv * 6364136223846793005UL) & 0xFFUL).to_int().to_byte(),
      b4: ((iv ^ (iv >> 17)) & 0xFFUL).to_int().to_byte(),
      b5: ((iv ^ (iv >> 13)) & 0xFFUL).to_int().to_byte(),
      b6: (((iv ^ (iv >> 7)) & 0x4FUL) | 0x40UL).to_int().to_byte(),
      b7: ((iv ^ (iv >> 11)) & 0xFFUL).to_int().to_byte(),
      b8: (((iv ^ (iv >> 3)) & 0x3FUL) | 0x80UL).to_int().to_byte(),
      b9: ((iv ^ (iv >> 19)) & 0xFFUL).to_int().to_byte(),
      b10: ((iv + 1UL) & 0xFFUL).to_int().to_byte(),
      b11: ((iv + 2UL) & 0xFFUL).to_int().to_byte(),
      b12: ((iv + 3UL) & 0xFFUL).to_int().to_byte(),
      b13: ((iv + 4UL) & 0xFFUL).to_int().to_byte(),
      b14: ((iv + 5UL) & 0xFFUL).to_int().to_byte(),
      b15: ((iv + 6UL) & 0xFFUL).to_int().to_byte(),
    }
    let pg = pg_for_id(@types.Bytes16Id(b), map)
    pg_set.set(pg, true)
  }
  assert_true(pg_set.length() > 1)
}

// ── group_by_target ─────────────────────────────────────────────────────────

///|
test "ulid/group_by_target_all_points_accounted" {
  let map = make_cluster(8, 1)
  let ts = 1_700_000_000_000UL
  let points : Array[(@types.VectorId, Array[Double], @types.Attrs)] = []
  for i in 0UL..<50UL {
    let id = @types.Bytes16Id(ulid_bytes(ts, 0U, i))
    points.push((id, [1.0, 0.0], @types.empty_attrs()))
  }
  let groups = group_by_target(points, map)
  let mut total = 0
  for _, pts in groups {
    total = total + pts.length()
  }
  // Every point must appear in exactly one target group
  @test.assert_eq(total, 50)
}

///|
test "ulid/group_by_pg_consistent_with_pg_for_id" {
  let map = make_cluster(8, 1)
  let ts = 1_700_000_000_001UL
  let ids : Array[@types.VectorId] = []
  let points : Array[(@types.VectorId, Array[Double], @types.Attrs)] = []
  for i in 0UL..<20UL {
    let id = @types.Bytes16Id(ulid_bytes(ts, 0xCAFEU, i))
    ids.push(id)
    points.push((id, [i.to_double(), 0.0], @types.empty_attrs()))
  }
  let groups = group_by_pg(points, map)
  for id in ids {
    let expected_pg = pg_for_id(id, map)
    match groups.get(expected_pg) {
      Some(pts) => {
        let found = pts.any(fn(p) {
          let (pid, _, _) = p
          pid == id
        })
        assert_true(found)
      }
      None => assert_true(false)
    }
  }
}

///|
test "mixed/group_by_pg_int64id_and_bytes16id" {
  let map = make_cluster(8, 1)
  let ts = 1_700_000_000_002UL
  let points : Array[(@types.VectorId, Array[Double], @types.Attrs)] = []
  for i in 0..<10 {
    points.push((@types.Int64Id(i.to_int64()), [1.0], @types.empty_attrs()))
  }
  for i in 0UL..<10UL {
    let id = @types.Bytes16Id(ulid_bytes(ts, 0xBEEFU, i))
    points.push((id, [2.0], @types.empty_attrs()))
  }
  let groups = group_by_pg(points, map)
  let mut total = 0
  for _, pts in groups {
    total = total + pts.length()
  }
  @test.assert_eq(total, 20)
  for p in points {
    let (id, _, _) = p
    let expected = pg_for_id(id, map)
    match groups.get(expected) {
      Some(pts) => {
        let found = pts.any(fn(q) {
          let (qid, _, _) = q
          qid == id
        })
        assert_true(found)
      }
      None => assert_true(false)
    }
  }
}

// ── replica routing ────────────────────────────────────────────────────────

///|
test "ulid/targets_for_id_returns_correct_count" {
  let map = make_cluster(16, 2)
  let id = @types.Bytes16Id(
    ulid_bytes(1_700_000_000_000UL, 0xABU, 0x123456789ABCDEF0UL),
  )
  let replicas = test_targets_for_id(id, map)
  @test.assert_eq(replicas.length(), 2)
  // Both replica keys must be distinct
  assert_true(replicas[0] != replicas[1])
}

///|
test "ulid/health_aware_routing_excludes_failed" {
  let map = make_cluster(16, 1)
  let id = @types.Bytes16Id(
    ulid_bytes(1_700_000_000_000UL, 0xFFU, 0xFFFFFFFFFFFFFFFFUL),
  )
  let target_keys = map.targets.map(fn(t) { t.key })
  let tracker = ShardHealthTracker::new(target_keys, failure_threshold=1)
  // Fail the target that owns this ID
  let id_targets = test_targets_for_id(id, map)
  if id_targets.length() > 0 {
    tracker.report_failure(id_targets[0], 1_000_000_000L, "simulated failure")
  }
  // select_read_targets should exclude the failed target
  let read_targets = select_read_targets(map, tracker)
  for t in read_targets {
    assert_true(tracker.get_status(t) != Failed)
  }
}

///|
test "ulid/health_aware_routing_returns_targets_when_healthy" {
  let map = make_cluster(16, 1)
  let target_keys = map.targets.map(fn(t) { t.key })
  let tracker = ShardHealthTracker::new(target_keys)
  // All targets healthy by default
  let read_targets = select_read_targets(map, tracker)
  assert_true(read_targets.length() > 0)
}

// ── cross-target independence ────────────────────────────────────────────────

///|
test "ulid/different_ids_can_map_to_different_pgs" {
  let map = make_cluster(16, 1)
  let ts = 1_700_000_000_000UL
  let a = @types.Bytes16Id(ulid_bytes(ts, 0U, 1UL))
  let b = @types.Bytes16Id(ulid_bytes(ts, 0U, 2UL))
  let sa = pg_for_id(a, map)
  let sb = pg_for_id(b, map)
  assert_true(sa >= 0 && sa < 16)
  assert_true(sb >= 0 && sb < 16)
  // Determinism
  @test.assert_eq(pg_for_id(a, map), sa)
  @test.assert_eq(pg_for_id(b, map), sb)
}

///|
test "uuid/distinct_uuids_each_map_to_valid_pg" {
  let map = make_cluster(32, 1)
  let uuids = [
    "00000000-0000-0000-0000-000000000000", "ffffffff-ffff-ffff-ffff-ffffffffffff",
    "550e8400-e29b-41d4-a716-446655440000", "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
    "6ba7b811-9dad-11d1-80b4-00c04fd430c8",
  ]
  for s in uuids {
    match @types.VectorId::from_uuid_string(s) {
      Some(id) => {
        let pg = pg_for_id(id, map)
        assert_true(pg >= 0 && pg < 32)
      }
      None => assert_true(false)
    }
  }
}

// ── TransportPoint round-trip over target boundary ──────────────────────────

///|
test "ulid/transport_point_jsonl_round_trip" {
  let id = @types.Bytes16Id(
    ulid_bytes(1_700_000_000_042UL, 0xCAFEU, 0xDEADBEEFCAFE1234UL),
  )
  let attrs = @types.empty_attrs()
  attrs.set("label", @types.String("ulid-point"))
  attrs.set("score", @types.Float(0.99))
  let point = TransportPoint::{ id, vector: [0.1, 0.2, 0.3], attrs }

  let line = point.to_jsonl()
  match TransportPoint::from_jsonl(line) {
    None => assert_true(false)
    Some(restored) => {
      @test.assert_eq(restored.id, id)
      @test.assert_eq(restored.vector.length(), 3)
      @test.assert_eq(
        restored.attrs.get("label"),
        Some(@types.String("ulid-point")),
      )
      @test.assert_eq(restored.attrs.get("score"), Some(@types.Float(0.99)))
      let map = make_cluster(16, 1)
      @test.assert_eq(pg_for_id(restored.id, map), pg_for_id(id, map))
    }
  }
}

///|
test "uuid/transport_point_jsonl_round_trip" {
  match
    @types.VectorId::from_uuid_string("550e8400-e29b-41d4-a716-446655440000") {
    None => assert_true(false)
    Some(id) => {
      let point = TransportPoint::{
        id,
        vector: [1.0, 2.0],
        attrs: @types.empty_attrs(),
      }
      let line = point.to_jsonl()
      match TransportPoint::from_jsonl(line) {
        None => assert_true(false)
        Some(restored) => {
          @test.assert_eq(restored.id, id)
          let map = make_cluster(8, 1)
          @test.assert_eq(pg_for_id(restored.id, map), pg_for_id(id, map))
        }
      }
    }
  }
}

///|
test "mixed/transport_point_int64id_and_bytes16id_both_survive_jsonl" {
  let map = make_cluster(8, 1)
  let p_int = TransportPoint::{
    id: @types.Int64Id(42L),
    vector: [1.0],
    attrs: @types.empty_attrs(),
  }
  let ulid_id = @types.Bytes16Id(ulid_bytes(1_700_000_000_000UL, 0U, 99UL))
  let p_ulid = TransportPoint::{
    id: ulid_id,
    vector: [2.0],
    attrs: @types.empty_attrs(),
  }

  let r_int = TransportPoint::from_jsonl(p_int.to_jsonl()).unwrap()
  let r_ulid = TransportPoint::from_jsonl(p_ulid.to_jsonl()).unwrap()

  @test.assert_eq(r_int.id, p_int.id)
  @test.assert_eq(r_ulid.id, p_ulid.id)
  @test.assert_eq(pg_for_id(r_int.id, map), pg_for_id(p_int.id, map))
  @test.assert_eq(pg_for_id(r_ulid.id, map), pg_for_id(p_ulid.id, map))
}
