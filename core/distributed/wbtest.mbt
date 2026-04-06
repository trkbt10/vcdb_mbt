///|
/// Tests for distributed merge and routing.

///|
fn make_vid(n : Int) -> @types.VectorId {
  @types.VectorId::from_int(n)
}

///|
fn make_hit(id : Int, score : Double) -> @types.SearchHit {
  { id: make_vid(id), score, attrs: @types.empty_attrs() }
}

// ── merge_search tests ──────────────────────────────────────

///|
test "merge_search: single shard" {
  let results = [
    { shard_id: 0, hits: [make_hit(1, 0.9), make_hit(2, 0.8)], error: None },
  ]
  let merged = merge_search(results, 10)
  assert_eq(merged.hits.length(), 2)
  assert_eq(merged.succeeded, [0])
  assert_eq(merged.failed.length(), 0)
  // Score descending
  assert_true(merged.hits[0].score >= merged.hits[1].score)
}

///|
test "merge_search: multi-shard score merge" {
  let results = [
    { shard_id: 0, hits: [make_hit(1, 0.9), make_hit(3, 0.7)], error: None },
    { shard_id: 1, hits: [make_hit(2, 0.95), make_hit(4, 0.6)], error: None },
  ]
  let merged = merge_search(results, 3)
  assert_eq(merged.hits.length(), 3)
  // Top 3 by score: 0.95, 0.9, 0.7
  assert_eq(merged.hits[0].id, make_vid(2))
  assert_eq(merged.hits[1].id, make_vid(1))
  assert_eq(merged.hits[2].id, make_vid(3))
}

///|
test "merge_search: partial failure" {
  let results = [
    { shard_id: 0, hits: [make_hit(1, 0.9)], error: None },
    { shard_id: 1, hits: [], error: Some("timeout") },
  ]
  let merged = merge_search(results, 10)
  assert_eq(merged.hits.length(), 1)
  assert_eq(merged.succeeded, [0])
  assert_eq(merged.failed.length(), 1)
  assert_eq(merged.failed[0].0, 1)
}

///|
test "merge_search: empty results" {
  let results : Array[ShardSearchResult] = []
  let merged = merge_search(results, 10)
  assert_eq(merged.hits.length(), 0)
}

///|
test "merge_search: tie-break by ID ascending" {
  let results = [
    { shard_id: 0, hits: [make_hit(5, 0.8)], error: None },
    { shard_id: 1, hits: [make_hit(2, 0.8)], error: None },
  ]
  let merged = merge_search(results, 10)
  // Same score, lower ID first
  assert_eq(merged.hits[0].id, make_vid(2))
  assert_eq(merged.hits[1].id, make_vid(5))
}

// ── merge_scroll tests ──────────────────────────────────────

///|
test "merge_scroll: multi-shard ID merge" {
  let results = [
    {
      shard_id: 0,
      entries: [
        { id: make_vid(1), attrs: @types.empty_attrs() },
        { id: make_vid(4), attrs: @types.empty_attrs() },
      ],
      error: None,
    },
    {
      shard_id: 1,
      entries: [
        { id: make_vid(2), attrs: @types.empty_attrs() },
        { id: make_vid(3), attrs: @types.empty_attrs() },
      ],
      error: None,
    },
  ]
  let merged = merge_scroll(results, 3)
  assert_eq(merged.entries.length(), 3)
  // ID ascending: 1, 2, 3
  assert_eq(merged.entries[0].id, make_vid(1))
  assert_eq(merged.entries[1].id, make_vid(2))
  assert_eq(merged.entries[2].id, make_vid(3))
}

///|
test "merge_scroll: partial failure" {
  let results = [
    {
      shard_id: 0,
      entries: [{ id: make_vid(1), attrs: @types.empty_attrs() }],
      error: None,
    },
    { shard_id: 1, entries: [], error: Some("unavailable") },
  ]
  let merged = merge_scroll(results, 10)
  assert_eq(merged.entries.length(), 1)
  assert_eq(merged.failed.length(), 1)
}

// ── merge_count tests ───────────────────────────────────────

///|
test "merge_count: sums across shards" {
  let results = [
    { shard_id: 0, count: 100, error: None },
    { shard_id: 1, count: 200, error: None },
    { shard_id: 2, count: 50, error: None },
  ]
  let merged = merge_count(results)
  assert_eq(merged.count, 350)
  assert_eq(merged.succeeded.length(), 3)
}

///|
test "merge_count: failed shard excluded" {
  let results = [
    { shard_id: 0, count: 100, error: None },
    { shard_id: 1, count: 0, error: Some("error") },
  ]
  let merged = merge_count(results)
  assert_eq(merged.count, 100)
  assert_eq(merged.failed.length(), 1)
}

// ── router tests ────────────────────────────────────────────

///|
test "shard_for_id: deterministic" {
  let map = @placement.CrushMap::new(
    8,
    1,
    [@placement.CrushTarget::new("s0")],
  )
  let shard1 = shard_for_id(make_vid(42), map)
  let shard2 = shard_for_id(make_vid(42), map)
  assert_eq(shard1, shard2)
}

///|
test "shard_for_id: within range" {
  let map = @placement.CrushMap::new(
    8,
    1,
    [@placement.CrushTarget::new("s0")],
  )
  for i in 0..<100 {
    let shard = shard_for_id(make_vid(i), map)
    assert_true(shard >= 0 && shard < 8)
  }
}

///|
test "all_shards: returns correct count" {
  let map = @placement.CrushMap::new(
    4,
    1,
    [@placement.CrushTarget::new("s0")],
  )
  let shards = all_shards(map)
  assert_eq(shards, [0, 1, 2, 3])
}

///|
test "group_by_shard: distributes points" {
  let map = @placement.CrushMap::new(
    4,
    1,
    [@placement.CrushTarget::new("s0")],
  )
  let points : Array[(@types.VectorId, Array[Double], @types.Attrs)] = []
  for i in 0..<20 {
    points.push((make_vid(i), [1.0], @types.empty_attrs()))
  }
  let groups = group_by_shard(points, map)
  // All 20 points should be distributed across groups
  let mut total = 0
  for pg in groups.keys() {
    match groups.get(pg) {
      Some(pts) => total = total + pts.length()
      None => ()
    }
  }
  assert_eq(total, 20)
}

///|
test "group_by_shard: consistent with shard_for_id" {
  let map = @placement.CrushMap::new(
    8,
    1,
    [@placement.CrushTarget::new("s0")],
  )
  let vid = make_vid(42)
  let expected_shard = shard_for_id(vid, map)
  let points = [(vid, [1.0], @types.empty_attrs())]
  let groups = group_by_shard(points, map)
  match groups.get(expected_shard) {
    Some(pts) => assert_eq(pts.length(), 1)
    None => assert_true(false)
  }
}
