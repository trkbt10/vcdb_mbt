///|
/// Tests for distributed merge, routing, and rebalance.

///|
fn make_vid(n : Int) -> @types.VectorId {
  @types.VectorId::from_int(n)
}

///|
fn make_hit(id : Int, score : Double) -> @types.SearchHit {
  { id: make_vid(id), score, attrs: @types.empty_attrs() }
}

///|
fn tk(s : String) -> @placement.TargetKey {
  @placement.TargetKey::new(s)
}

// ── merge_search tests ──────────────────────────────────────

///|
test "merge_search: single target" {
  let results = [
    {
      target_key: tk("t0"),
      hits: [make_hit(1, 0.9), make_hit(2, 0.8)],
      error: None,
    },
  ]
  let merged = merge_search(results, 10)
  assert_eq(merged.hits.length(), 2)
  assert_eq(merged.succeeded, [tk("t0")])
  assert_eq(merged.failed.length(), 0)
  assert_true(merged.hits[0].score >= merged.hits[1].score)
}

///|
test "merge_search: multi-target score merge" {
  let results = [
    {
      target_key: tk("t0"),
      hits: [make_hit(1, 0.9), make_hit(3, 0.7)],
      error: None,
    },
    {
      target_key: tk("t1"),
      hits: [make_hit(2, 0.95), make_hit(4, 0.6)],
      error: None,
    },
  ]
  let merged = merge_search(results, 3)
  assert_eq(merged.hits.length(), 3)
  assert_eq(merged.hits[0].id, make_vid(2))
  assert_eq(merged.hits[1].id, make_vid(1))
  assert_eq(merged.hits[2].id, make_vid(3))
}

///|
test "merge_search: partial failure" {
  let results = [
    { target_key: tk("t0"), hits: [make_hit(1, 0.9)], error: None },
    { target_key: tk("t1"), hits: [], error: Some("timeout") },
  ]
  let merged = merge_search(results, 10)
  assert_eq(merged.hits.length(), 1)
  assert_eq(merged.succeeded, [tk("t0")])
  assert_eq(merged.failed.length(), 1)
  assert_eq(merged.failed[0].0, tk("t1"))
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
    { target_key: tk("t0"), hits: [make_hit(5, 0.8)], error: None },
    { target_key: tk("t1"), hits: [make_hit(2, 0.8)], error: None },
  ]
  let merged = merge_search(results, 10)
  assert_eq(merged.hits[0].id, make_vid(2))
  assert_eq(merged.hits[1].id, make_vid(5))
}

///|
test "merge_search: deduplicates same ID from multiple targets" {
  let results = [
    {
      target_key: tk("t0"),
      hits: [make_hit(1, 0.9), make_hit(2, 0.7)],
      error: None,
    },
    {
      target_key: tk("t1"),
      hits: [make_hit(1, 0.89), make_hit(3, 0.8)],
      error: None,
    },
  ]
  let merged = merge_search(results, 10)
  assert_eq(merged.hits.length(), 3)
  assert_eq(merged.hits[0].id, make_vid(1))
  assert_true(merged.hits[0].score > 0.89)
}

// ── merge_scroll tests ──────────────────────────────────────

///|
test "merge_scroll: multi-target ID merge" {
  let results = [
    {
      target_key: tk("t0"),
      entries: [
        { id: make_vid(1), attrs: @types.empty_attrs() },
        { id: make_vid(4), attrs: @types.empty_attrs() },
      ],
      error: None,
    },
    {
      target_key: tk("t1"),
      entries: [
        { id: make_vid(2), attrs: @types.empty_attrs() },
        { id: make_vid(3), attrs: @types.empty_attrs() },
      ],
      error: None,
    },
  ]
  let merged = merge_scroll(results, 3)
  assert_eq(merged.entries.length(), 3)
  assert_eq(merged.entries[0].id, make_vid(1))
  assert_eq(merged.entries[1].id, make_vid(2))
  assert_eq(merged.entries[2].id, make_vid(3))
}

///|
test "merge_scroll: deduplicates same ID" {
  let results = [
    {
      target_key: tk("t0"),
      entries: [
        { id: make_vid(1), attrs: @types.empty_attrs() },
        { id: make_vid(3), attrs: @types.empty_attrs() },
      ],
      error: None,
    },
    {
      target_key: tk("t1"),
      entries: [
        { id: make_vid(1), attrs: @types.empty_attrs() },
        { id: make_vid(2), attrs: @types.empty_attrs() },
      ],
      error: None,
    },
  ]
  let merged = merge_scroll(results, 10)
  assert_eq(merged.entries.length(), 3)
}

///|
test "merge_scroll: partial failure" {
  let results = [
    {
      target_key: tk("t0"),
      entries: [{ id: make_vid(1), attrs: @types.empty_attrs() }],
      error: None,
    },
    { target_key: tk("t1"), entries: [], error: Some("unavailable") },
  ]
  let merged = merge_scroll(results, 10)
  assert_eq(merged.entries.length(), 1)
  assert_eq(merged.failed.length(), 1)
}

// ── merge_count tests ───────────────────────────────────────

///|
test "merge_count: sums across targets" {
  let results = [
    { target_key: tk("t0"), count: 100, error: None },
    { target_key: tk("t1"), count: 200, error: None },
    { target_key: tk("t2"), count: 50, error: None },
  ]
  let merged = merge_count(results)
  assert_eq(merged.count, 350)
  assert_eq(merged.succeeded.length(), 3)
}

///|
test "merge_count: failed target excluded" {
  let results = [
    { target_key: tk("t0"), count: 100, error: None },
    { target_key: tk("t1"), count: 0, error: Some("error") },
  ]
  let merged = merge_count(results)
  assert_eq(merged.count, 100)
  assert_eq(merged.failed.length(), 1)
}

// ── router tests (target-key based) ─────────────────────────

///|
test "targets_for_id: returns target keys" {
  let targets = [
    @placement.CrushTarget::new("node-a"),
    @placement.CrushTarget::new("node-b"),
    @placement.CrushTarget::new("node-c"),
    @placement.CrushTarget::new("node-d"),
  ]
  let map = @placement.CrushMap::new(8, 2, targets)
  let result = targets_for_id(make_vid(42), map)
  assert_eq(result.length(), 2)
}

///|
test "targets_for_id: deterministic" {
  let targets = [
    @placement.CrushTarget::new("node-a"),
    @placement.CrushTarget::new("node-b"),
    @placement.CrushTarget::new("node-c"),
  ]
  let map = @placement.CrushMap::new(8, 2, targets)
  let r1 = targets_for_id(make_vid(42), map)
  let r2 = targets_for_id(make_vid(42), map)
  assert_eq(r1, r2)
}

///|
test "targets_for_id: single replica returns one target" {
  let targets = [
    @placement.CrushTarget::new("node-a"),
    @placement.CrushTarget::new("node-b"),
  ]
  let map = @placement.CrushMap::new(4, 1, targets)
  let result = targets_for_id(make_vid(42), map)
  assert_eq(result.length(), 1)
}

///|
test "group_by_target: distributes points across targets" {
  let targets = [
    @placement.CrushTarget::new("node-a"),
    @placement.CrushTarget::new("node-b"),
    @placement.CrushTarget::new("node-c"),
    @placement.CrushTarget::new("node-d"),
  ]
  let map = @placement.CrushMap::new(8, 1, targets)
  let points : Array[(@types.VectorId, Array[Double], @types.Attrs)] = []
  for i in 0..<20 {
    points.push((make_vid(i), [1.0], @types.empty_attrs()))
  }
  let groups = group_by_target(points, map)
  let mut total = 0
  for key in groups.keys() {
    match groups.get(key) {
      Some(pts) => total = total + pts.length()
      None => ()
    }
  }
  assert_eq(total, 20)
}

///|
test "group_by_target: with replicas, each point appears N times" {
  let targets = [
    @placement.CrushTarget::new("node-a"),
    @placement.CrushTarget::new("node-b"),
    @placement.CrushTarget::new("node-c"),
    @placement.CrushTarget::new("node-d"),
  ]
  let map = @placement.CrushMap::new(8, 3, targets)
  let points : Array[(@types.VectorId, Array[Double], @types.Attrs)] = []
  for i in 0..<10 {
    points.push((make_vid(i), [1.0], @types.empty_attrs()))
  }
  let groups = group_by_target(points, map)
  let mut total = 0
  for key in groups.keys() {
    match groups.get(key) {
      Some(pts) => total = total + pts.length()
      None => ()
    }
  }
  assert_eq(total, 30)
}

///|
test "group_by_target: consistent with targets_for_id" {
  let targets = [
    @placement.CrushTarget::new("node-a"),
    @placement.CrushTarget::new("node-b"),
    @placement.CrushTarget::new("node-c"),
  ]
  let map = @placement.CrushMap::new(8, 2, targets)
  let vid = make_vid(42)
  let expected_targets = targets_for_id(vid, map)
  let points = [(vid, [1.0], @types.empty_attrs())]
  let groups = group_by_target(points, map)
  for expected_key in expected_targets {
    match groups.get(expected_key) {
      Some(pts) => assert_true(pts.length() >= 1)
      None => assert_true(false)
    }
  }
}

// ── select_read_targets tests ───────────────────────────────

///|
test "select_read_targets: one target per PG" {
  let targets = [
    @placement.CrushTarget::new("node-a"),
    @placement.CrushTarget::new("node-b"),
    @placement.CrushTarget::new("node-c"),
  ]
  let map = @placement.CrushMap::new(4, 2, targets)
  let tracker = ShardHealthTracker::new(targets.map(fn(t) { t.key }))
  let read_targets = select_read_targets(map, tracker)
  assert_true(read_targets.length() <= 4)
  assert_true(read_targets.length() >= 1)
}

///|
test "select_read_targets: skips failed targets" {
  let targets = [
    @placement.CrushTarget::new("node-a"),
    @placement.CrushTarget::new("node-b"),
    @placement.CrushTarget::new("node-c"),
  ]
  let map = @placement.CrushMap::new(4, 2, targets)
  let tracker = ShardHealthTracker::new(targets.map(fn(t) { t.key }))
  tracker.report_failure(tk("node-a"), 1L, "down")
  tracker.report_failure(tk("node-a"), 2L, "down")
  tracker.report_failure(tk("node-a"), 3L, "down")
  let read_targets = select_read_targets(map, tracker)
  for key in read_targets {
    assert_true(key != tk("node-a"))
  }
}

///|
test "select_read_targets: does not duplicate surviving fallback target" {
  let targets = [
    @placement.CrushTarget::new("node-a"),
    @placement.CrushTarget::new("node-b"),
  ]
  let map = @placement.CrushMap::new(8, 2, targets)
  let tracker = ShardHealthTracker::new(
    targets.map(fn(t) { t.key }),
    failure_threshold=1,
  )
  tracker.report_failure(tk("node-a"), 1L, "down")
  let read_targets = select_read_targets(map, tracker)
  assert_eq(read_targets, [tk("node-b")])
}

// ── rebalance tests ─────────────────────────────────────────

///|
test "compute_rebalance_plan: no change when config identical" {
  let targets = [
    @placement.CrushTarget::new("node-a"),
    @placement.CrushTarget::new("node-b"),
  ]
  let old_map = @placement.CrushMap::new(4, 1, targets)
  let new_map = @placement.CrushMap::new(4, 1, targets)
  let ids : Array[@types.VectorId] = []
  for i in 0..<20 {
    ids.push(make_vid(i))
  }
  let plan = compute_rebalance_plan(ids, old_map, new_map)
  assert_eq(plan.length(), 0)
}

///|
test "compute_rebalance_plan: adding target produces moves" {
  let old_targets = [
    @placement.CrushTarget::new("node-a"),
    @placement.CrushTarget::new("node-b"),
  ]
  let new_targets = [
    @placement.CrushTarget::new("node-a"),
    @placement.CrushTarget::new("node-b"),
    @placement.CrushTarget::new("node-c"),
  ]
  let old_map = @placement.CrushMap::new(8, 1, old_targets)
  let new_map = @placement.CrushMap::new(8, 1, new_targets)
  let ids : Array[@types.VectorId] = []
  for i in 0..<100 {
    ids.push(make_vid(i))
  }
  let plan = compute_rebalance_plan(ids, old_map, new_map)
  assert_true(plan.length() > 0)
}

///|
test "compute_rebalance_plan: increasing replicas adds targets" {
  let targets = [
    @placement.CrushTarget::new("node-a"),
    @placement.CrushTarget::new("node-b"),
    @placement.CrushTarget::new("node-c"),
  ]
  let old_map = @placement.CrushMap::new(8, 1, targets)
  let new_map = @placement.CrushMap::new(8, 3, targets)
  let ids : Array[@types.VectorId] = []
  for i in 0..<50 {
    ids.push(make_vid(i))
  }
  let plan = compute_rebalance_plan(ids, old_map, new_map)
  assert_eq(plan.length(), 50)
  let summary = summarize_rebalance(plan)
  assert_eq(summary.total_additions, 100)
  assert_eq(summary.total_removals, 0)
}
