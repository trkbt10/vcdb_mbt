///|
/// Tests for shard health tracking.

// ── ShardHealthTracker basic state ──────────────────────────────

///|
test "health: initial state all healthy" {
  let tracker = ShardHealthTracker::new(4)
  for i in 0..<4 {
    assert_eq(tracker.get_status(i), Healthy)
  }
  assert_eq(tracker.healthy_shards().length(), 4)
  assert_eq(tracker.failed_shards().length(), 0)
}

///|
test "health: unknown shard treated as Failed" {
  let tracker = ShardHealthTracker::new(2)
  assert_eq(tracker.get_status(99), Failed)
}

// ── State transitions ──────────────────────────────────────────

///|
test "health: single failure transitions to Degraded" {
  let tracker = ShardHealthTracker::new(4, failure_threshold=3)
  tracker.report_failure(1, 1000L, "timeout")
  assert_eq(tracker.get_status(1), Degraded)
  // Other shards unaffected
  assert_eq(tracker.get_status(0), Healthy)
  assert_eq(tracker.get_status(2), Healthy)
}

///|
test "health: consecutive failures reach threshold → Failed" {
  let tracker = ShardHealthTracker::new(4, failure_threshold=3)
  tracker.report_failure(2, 1000L, "error 1")
  assert_eq(tracker.get_status(2), Degraded)
  tracker.report_failure(2, 2000L, "error 2")
  assert_eq(tracker.get_status(2), Degraded)
  tracker.report_failure(2, 3000L, "error 3")
  assert_eq(tracker.get_status(2), Failed)
}

///|
test "health: success after failure resets to Healthy" {
  let tracker = ShardHealthTracker::new(4, failure_threshold=3)
  tracker.report_failure(1, 1000L, "err")
  tracker.report_failure(1, 2000L, "err")
  assert_eq(tracker.get_status(1), Degraded)
  tracker.report_success(1, 3000L)
  assert_eq(tracker.get_status(1), Healthy)
  // Failure count was reset
  match tracker.get_health(1) {
    Some(h) => assert_eq(h.consecutive_failures, 0)
    None => assert_true(false)
  }
}

///|
test "health: success recovers Failed shard" {
  let tracker = ShardHealthTracker::new(4, failure_threshold=2)
  tracker.report_failure(0, 1000L, "err")
  tracker.report_failure(0, 2000L, "err")
  assert_eq(tracker.get_status(0), Failed)
  tracker.report_success(0, 5000L)
  assert_eq(tracker.get_status(0), Healthy)
}

///|
test "health: Failed stays Failed on more failures" {
  let tracker = ShardHealthTracker::new(4, failure_threshold=2)
  tracker.report_failure(0, 1000L, "err 1")
  tracker.report_failure(0, 2000L, "err 2")
  assert_eq(tracker.get_status(0), Failed)
  tracker.report_failure(0, 3000L, "err 3")
  assert_eq(tracker.get_status(0), Failed)
  match tracker.get_health(0) {
    Some(h) => assert_eq(h.consecutive_failures, 3)
    None => assert_true(false)
  }
}

// ── healthy_shards / failed_shards ─────────────────────────────

///|
test "health: healthy_shards excludes Failed" {
  let tracker = ShardHealthTracker::new(4, failure_threshold=1)
  tracker.report_failure(1, 1000L, "down")
  tracker.report_failure(3, 2000L, "down")
  assert_eq(tracker.healthy_shards(), [0, 2])
  assert_eq(tracker.failed_shards(), [1, 3])
}

///|
test "health: Degraded included in healthy_shards" {
  let tracker = ShardHealthTracker::new(3, failure_threshold=3)
  tracker.report_failure(1, 1000L, "slow")
  assert_eq(tracker.get_status(1), Degraded)
  assert_eq(tracker.healthy_shards(), [0, 1, 2])
  assert_eq(tracker.failed_shards(), [])
}

// ── all_health ─────────────────────────────────────────────────

///|
test "health: all_health returns sorted by shard_id" {
  let tracker = ShardHealthTracker::new(3)
  tracker.report_failure(2, 1000L, "err")
  let all = tracker.all_health()
  assert_eq(all.length(), 3)
  assert_eq(all[0].shard_id, 0)
  assert_eq(all[1].shard_id, 1)
  assert_eq(all[2].shard_id, 2)
  assert_eq(all[2].status, Degraded)
}

// ── Health-aware routing ───────────────────────────────────────

///|
test "health: healthy_shards_for_fanout excludes Failed" {
  let map = @placement.CrushMap::new(4, 1, [@placement.CrushTarget::new("s0")])
  let tracker = ShardHealthTracker::new(4, failure_threshold=1)
  tracker.report_failure(2, 1000L, "down")
  let shards = healthy_shards_for_fanout(map, tracker)
  assert_eq(shards, [0, 1, 3])
}

///|
test "health: shard_for_id_with_health returns None for Failed" {
  let map = @placement.CrushMap::new(4, 1, [@placement.CrushTarget::new("s0")])
  let tracker = ShardHealthTracker::new(4, failure_threshold=1)
  // Find which shard owns ID 42
  let pg = shard_for_id(make_vid(42), map)
  // Fail that shard
  tracker.report_failure(pg, 1000L, "down")
  // Should return None now
  let result = shard_for_id_with_health(make_vid(42), map, tracker)
  assert_eq(result, None)
}

///|
test "health: shard_for_id_with_health returns Some for Healthy" {
  let map = @placement.CrushMap::new(4, 1, [@placement.CrushTarget::new("s0")])
  let tracker = ShardHealthTracker::new(4)
  let result = shard_for_id_with_health(make_vid(42), map, tracker)
  match result {
    Some(pg) => assert_eq(pg, shard_for_id(make_vid(42), map))
    None => assert_true(false)
  }
}

///|
test "health: last_error tracks most recent error" {
  let tracker = ShardHealthTracker::new(2, failure_threshold=5)
  tracker.report_failure(0, 1000L, "timeout")
  tracker.report_failure(0, 2000L, "connection refused")
  match tracker.get_health(0) {
    Some(h) => assert_eq(h.last_error, Some("connection refused"))
    None => assert_true(false)
  }
}

///|
test "health: timestamps updated correctly" {
  let tracker = ShardHealthTracker::new(2)
  tracker.report_success(0, 5000L)
  tracker.report_failure(0, 6000L, "err")
  match tracker.get_health(0) {
    Some(h) => {
      assert_eq(h.last_success_ts, 5000L)
      assert_eq(h.last_failure_ts, 6000L)
    }
    None => assert_true(false)
  }
}
