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
/// - ULID-style IDs (monotone timestamp + random suffix) distribute across shards
/// - UUID v4 IDs distribute across shards
/// - Mixed Int64Id + Bytes16Id batches route correctly
/// - TransportPoint serialisation survives a shard round-trip with Bytes16Id

///|
/// Construct a ULID-style Bytes16 from a 48-bit ms timestamp and an 80-bit
/// random value.
///
/// ULID layout (128 bits, big-endian):
///   [b0..b5]   48-bit millisecond timestamp (bits 127 down to 80)
///   [b6..b15]  80-bit random payload (bits 79 down to 0)
///
/// The 80-bit random part is passed as two values:
///   rand_hi: UInt — only the low 16 bits are used (bits 79–64 of the payload)
///   rand_lo: UInt64 — the low 64 bits of the payload (bits 63–0)
///
/// Callers must not pass values outside [0, 0xFFFF] in rand_hi; upper bits
/// are masked away to make the truncation explicit rather than silent.
fn ulid_bytes(
  ts_ms : UInt64,
  rand_hi : UInt,
  rand_lo : UInt64,
) -> @types.Bytes16 {
  // Bytes 0-5: 48-bit big-endian timestamp
  let b0 = ((ts_ms >> 40) & 0xFFUL).to_int().to_byte()
  let b1 = ((ts_ms >> 32) & 0xFFUL).to_int().to_byte()
  let b2 = ((ts_ms >> 24) & 0xFFUL).to_int().to_byte()
  let b3 = ((ts_ms >> 16) & 0xFFUL).to_int().to_byte()
  let b4 = ((ts_ms >> 8) & 0xFFUL).to_int().to_byte()
  let b5 = (ts_ms & 0xFFUL).to_int().to_byte()
  // Bytes 6-7: top 16 bits of the 80-bit random payload (bits 79–64), big-endian.
  // Mask to 16 bits: only bits[15:8] → b6, bits[7:0] → b7.
  let hi16 = rand_hi & 0xFFFFU
  let b6 = ((hi16 >> 8) & 0xFFU).reinterpret_as_int().to_byte()
  let b7 = (hi16 & 0xFFU).reinterpret_as_int().to_byte()
  // Bytes 8-15: bottom 64 bits of the 80-bit random payload, big-endian
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

// ── determinism ────────────────────────────────────────────────────────────

///|
test "ulid/shard_routing_is_deterministic" {
  let map = make_cluster(16, 1)
  let id = @types.Bytes16Id(
    ulid_bytes(1_700_000_000_000UL, 0xABCDU, 0x0102030405060708UL),
  )
  // Same ID must always route to the same shard
  let shard_a = shard_for_id(id, map)
  let shard_b = shard_for_id(id, map)
  let shard_c = shard_for_id(id, map)
  assert_eq(shard_a, shard_b)
  assert_eq(shard_b, shard_c)
  assert_true(shard_a >= 0 && shard_a < 16)
}

///|
test "uuid/shard_routing_is_deterministic" {
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
  let s1 = shard_for_id(id, map)
  let s2 = shard_for_id(id, map)
  assert_eq(s1, s2)
  assert_true(s1 >= 0 && s1 < 16)
}

// ── distribution ───────────────────────────────────────────────────────────

///|
test "ulid/same_timestamp_different_random_distributes_across_shards" {
  // All IDs share the same 48-bit ms timestamp but differ in the random part.
  // This models a burst of writes within a single millisecond.
  // They must still distribute across multiple shards (not all pile onto one).
  let map = make_cluster(16, 1)
  let ts = 1_700_000_000_000UL
  let shard_set : Map[Int, Bool] = {}
  for i in 0UL..<64UL {
    let id = @types.Bytes16Id(ulid_bytes(ts, 0U, i * 0x0102030405060708UL))
    let shard = shard_for_id(id, map)
    shard_set.set(shard, true)
  }
  // With 64 distinct random suffixes and 16 PGs, we expect > 1 unique shard
  assert_true(shard_set.length() > 1)
}

///|
test "ulid/monotone_timestamps_distribute_across_shards" {
  // Sequential ms timestamps (monotone, as ULID guarantees).
  // They must spread across shards, not cluster on one node.
  let map = make_cluster(16, 1)
  let shard_counts : Map[Int, Int] = {}
  for i in 0..<16 {
    // Initialise counters
    shard_counts.set(i, 0)
  }
  let base_ts = 1_700_000_000_000UL
  for i in 0UL..<100UL {
    let id = @types.Bytes16Id(ulid_bytes(base_ts + i, 0xDEADU, i))
    let shard = shard_for_id(id, map)
    match shard_counts.get(shard) {
      Some(c) => shard_counts.set(shard, c + 1)
      None => shard_counts.set(shard, 1)
    }
  }
  // No single shard should receive all 100 IDs
  let mut max_load = 0
  for _, count in shard_counts {
    if count > max_load {
      max_load = count
    }
  }
  assert_true(max_load < 100)
  // At least 2 distinct shards must be used
  let mut used_shards = 0
  for _, count in shard_counts {
    if count > 0 {
      used_shards = used_shards + 1
    }
  }
  assert_true(used_shards >= 2)
}

///|
test "uuid/random_ids_distribute_across_shards" {
  // 64 distinct UUID v4 style IDs (all bytes vary) must hit multiple shards.
  let map = make_cluster(16, 1)
  let shard_set : Map[Int, Bool] = {}
  // Generate 64 pseudo-random UUIDs by varying all bytes deterministically.
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
      b6: (((iv ^ (iv >> 7)) & 0x4FUL) | 0x40UL).to_int().to_byte(), // version 4
      b7: ((iv ^ (iv >> 11)) & 0xFFUL).to_int().to_byte(),
      b8: (((iv ^ (iv >> 3)) & 0x3FUL) | 0x80UL).to_int().to_byte(), // variant 10xx
      b9: ((iv ^ (iv >> 19)) & 0xFFUL).to_int().to_byte(),
      b10: ((iv + 1UL) & 0xFFUL).to_int().to_byte(),
      b11: ((iv + 2UL) & 0xFFUL).to_int().to_byte(),
      b12: ((iv + 3UL) & 0xFFUL).to_int().to_byte(),
      b13: ((iv + 4UL) & 0xFFUL).to_int().to_byte(),
      b14: ((iv + 5UL) & 0xFFUL).to_int().to_byte(),
      b15: ((iv + 6UL) & 0xFFUL).to_int().to_byte(),
    }
    let shard = shard_for_id(@types.Bytes16Id(b), map)
    shard_set.set(shard, true)
  }
  assert_true(shard_set.length() > 1)
}

// ── group_by_shard ─────────────────────────────────────────────────────────

///|
test "ulid/group_by_shard_all_points_accounted" {
  let map = make_cluster(8, 1)
  let ts = 1_700_000_000_000UL
  let points : Array[(@types.VectorId, Array[Double], @types.Attrs)] = []
  for i in 0UL..<50UL {
    let id = @types.Bytes16Id(ulid_bytes(ts, 0U, i))
    points.push((id, [1.0, 0.0], @types.empty_attrs()))
  }
  let groups = group_by_shard(points, map)
  let mut total = 0
  for _, pts in groups {
    total = total + pts.length()
  }
  // Every point must appear in exactly one shard group
  assert_eq(total, 50)
}

///|
test "ulid/group_by_shard_consistent_with_shard_for_id" {
  // group_by_shard must agree with shard_for_id for every individual ID.
  let map = make_cluster(8, 1)
  let ts = 1_700_000_000_001UL
  let ids : Array[@types.VectorId] = []
  let points : Array[(@types.VectorId, Array[Double], @types.Attrs)] = []
  for i in 0UL..<20UL {
    let id = @types.Bytes16Id(ulid_bytes(ts, 0xCAFEU, i))
    ids.push(id)
    points.push((id, [i.to_double(), 0.0], @types.empty_attrs()))
  }
  let groups = group_by_shard(points, map)
  for id in ids {
    let expected_shard = shard_for_id(id, map)
    match groups.get(expected_shard) {
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
test "mixed/group_by_shard_int64id_and_bytes16id" {
  // A batch containing both Int64Id and Bytes16Id must route correctly.
  let map = make_cluster(8, 1)
  let ts = 1_700_000_000_002UL
  let points : Array[(@types.VectorId, Array[Double], @types.Attrs)] = []
  // 10 legacy Int64Id points
  for i in 0..<10 {
    points.push((@types.Int64Id(i.to_int64()), [1.0], @types.empty_attrs()))
  }
  // 10 Bytes16Id (ULID) points
  for i in 0UL..<10UL {
    let id = @types.Bytes16Id(ulid_bytes(ts, 0xBEEFU, i))
    points.push((id, [2.0], @types.empty_attrs()))
  }
  let groups = group_by_shard(points, map)
  let mut total = 0
  for _, pts in groups {
    total = total + pts.length()
  }
  assert_eq(total, 20)
  // Verify each ID lands in the group predicted by shard_for_id
  for p in points {
    let (id, _, _) = p
    let expected = shard_for_id(id, map)
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
test "ulid/replicas_for_id_returns_correct_count" {
  // With 2 replicas, replicas_for_id must return 2 target keys.
  let map = make_cluster(16, 2)
  let id = @types.Bytes16Id(
    ulid_bytes(1_700_000_000_000UL, 0xABU, 0x123456789ABCDEF0UL),
  )
  let replicas = replicas_for_id(id, map)
  assert_eq(replicas.length(), 2)
  // Both replica keys must be non-empty and distinct
  assert_true(replicas[0].length() > 0)
  assert_true(replicas[1].length() > 0)
  assert_true(replicas[0] != replicas[1])
}

///|
test "ulid/shard_for_id_with_health_returns_none_when_failed" {
  let map = make_cluster(16, 1)
  let id = @types.Bytes16Id(
    ulid_bytes(1_700_000_000_000UL, 0xFFU, 0xFFFFFFFFFFFFFFFFUL),
  )
  let target_shard = shard_for_id(id, map)
  // failure_threshold=1 so a single report_failure immediately marks as Failed
  let tracker = ShardHealthTracker::new(16, failure_threshold=1)
  tracker.report_failure(target_shard, 1_000_000_000L, "simulated failure")
  let result = shard_for_id_with_health(id, map, tracker)
  assert_true(result is None)
}

///|
test "ulid/shard_for_id_with_health_returns_some_when_healthy" {
  let map = make_cluster(16, 1)
  let id = @types.Bytes16Id(ulid_bytes(1_700_000_000_000UL, 0x01U, 0x01UL))
  let tracker = ShardHealthTracker::new(16)
  // All shards healthy by default
  match shard_for_id_with_health(id, map, tracker) {
    Some(shard) => assert_true(shard >= 0 && shard < 16)
    None => assert_true(false)
  }
}

// ── cross-shard independence ────────────────────────────────────────────────

///|
test "ulid/different_ids_can_map_to_different_shards" {
  // Two ULIDs that differ only in the last byte must be treated
  // as independent keys — they may or may not share a shard, but
  // the routing must be stable and within range.
  let map = make_cluster(16, 1)
  let ts = 1_700_000_000_000UL
  let a = @types.Bytes16Id(ulid_bytes(ts, 0U, 1UL))
  let b = @types.Bytes16Id(ulid_bytes(ts, 0U, 2UL))
  let sa = shard_for_id(a, map)
  let sb = shard_for_id(b, map)
  assert_true(sa >= 0 && sa < 16)
  assert_true(sb >= 0 && sb < 16)
  // Run again to confirm determinism even for differing IDs
  assert_eq(shard_for_id(a, map), sa)
  assert_eq(shard_for_id(b, map), sb)
}

///|
test "uuid/distinct_uuids_each_map_to_valid_shard" {
  let map = make_cluster(32, 1)
  // A selection of well-known UUIDs (nil, max, sample v4)
  let uuids = [
    "00000000-0000-0000-0000-000000000000", "ffffffff-ffff-ffff-ffff-ffffffffffff",
    "550e8400-e29b-41d4-a716-446655440000", "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
    "6ba7b811-9dad-11d1-80b4-00c04fd430c8",
  ]
  for s in uuids {
    match @types.VectorId::from_uuid_string(s) {
      Some(id) => {
        let shard = shard_for_id(id, map)
        assert_true(shard >= 0 && shard < 32)
      }
      None => assert_true(false)
    }
  }
}

// ── TransportPoint round-trip over shard boundary ──────────────────────────

///|
test "ulid/transport_point_jsonl_round_trip" {
  // Simulates a shard transport: serialise a point with a ULID id on the
  // sender side and deserialise it on the receiver side.
  let id = @types.Bytes16Id(
    ulid_bytes(1_700_000_000_042UL, 0xCAFEU, 0xDEADBEEFCAFE1234UL),
  )
  let attrs = @types.empty_attrs()
  attrs.set("label", @types.String("ulid-point"))
  attrs.set("score", @types.Float(0.99))
  let point = TransportPoint::{ id, vector: [0.1, 0.2, 0.3], attrs }

  // Sender serialises
  let line = point.to_jsonl()

  // Receiver deserialises
  match TransportPoint::from_jsonl(line) {
    None => assert_true(false)
    Some(restored) => {
      assert_eq(restored.id, id)
      assert_eq(restored.vector.length(), 3)
      assert_eq(restored.attrs.get("label"), Some(@types.String("ulid-point")))
      assert_eq(restored.attrs.get("score"), Some(@types.Float(0.99)))
      // Routing on receiver side must match sender side routing
      let map = make_cluster(16, 1)
      assert_eq(shard_for_id(restored.id, map), shard_for_id(id, map))
    }
  }
}

///|
test "uuid/transport_point_jsonl_round_trip" {
  // Same as above but with a UUID v4 style ID
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
          assert_eq(restored.id, id)
          let map = make_cluster(8, 1)
          assert_eq(shard_for_id(restored.id, map), shard_for_id(id, map))
        }
      }
    }
  }
}

///|
test "mixed/transport_point_int64id_and_bytes16id_both_survive_jsonl" {
  let map = make_cluster(8, 1)
  // Int64Id point
  let p_int = TransportPoint::{
    id: @types.Int64Id(42L),
    vector: [1.0],
    attrs: @types.empty_attrs(),
  }
  // Bytes16Id point
  let ulid_id = @types.Bytes16Id(ulid_bytes(1_700_000_000_000UL, 0U, 99UL))
  let p_ulid = TransportPoint::{
    id: ulid_id,
    vector: [2.0],
    attrs: @types.empty_attrs(),
  }

  let r_int = TransportPoint::from_jsonl(p_int.to_jsonl()).unwrap()
  let r_ulid = TransportPoint::from_jsonl(p_ulid.to_jsonl()).unwrap()

  assert_eq(r_int.id, p_int.id)
  assert_eq(r_ulid.id, p_ulid.id)
  assert_eq(shard_for_id(r_int.id, map), shard_for_id(p_int.id, map))
  assert_eq(shard_for_id(r_ulid.id, map), shard_for_id(p_ulid.id, map))
}
