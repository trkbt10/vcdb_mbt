///|
/// Tests for shard health tracking.

///|
fn make_target_keys(n : Int) -> Array[@placement.TargetKey] {
  let keys : Array[@placement.TargetKey] = []
  for i in 0..<n {
    keys.push(@placement.TargetKey::new("target-" + i.to_string()))
  }
  keys
}

///|
fn target_key(i : Int) -> @placement.TargetKey {
  @placement.TargetKey::new("target-" + i.to_string())
}

// ── ShardHealthTracker basic state ──────────────────────────────

///|
test "health: initial state all healthy" {
  let tracker = ShardHealthTracker::new(make_target_keys(4))
  for i in 0..<4 {
    @test.assert_eq(tracker.get_status(target_key(i)), Healthy)
  }
  @test.assert_eq(tracker.healthy_targets().length(), 4)
  @test.assert_eq(tracker.failed_targets().length(), 0)
}

///|
test "health: unknown target treated as Failed" {
  let tracker = ShardHealthTracker::new(make_target_keys(2))
  @test.assert_eq(
    tracker.get_status(@placement.TargetKey::new("unknown")),
    Failed,
  )
}

// ── State transitions ──────────────────────────────────────────

///|
test "health: single failure transitions to Degraded" {
  let tracker = ShardHealthTracker::new(
    make_target_keys(4),
    failure_threshold=3,
  )
  tracker.report_failure(target_key(1), 1000L, "timeout")
  @test.assert_eq(tracker.get_status(target_key(1)), Degraded)
  // Other targets unaffected
  @test.assert_eq(tracker.get_status(target_key(0)), Healthy)
  @test.assert_eq(tracker.get_status(target_key(2)), Healthy)
}

///|
test "health: consecutive failures reach threshold → Failed" {
  let tracker = ShardHealthTracker::new(
    make_target_keys(4),
    failure_threshold=3,
  )
  tracker.report_failure(target_key(2), 1000L, "error 1")
  @test.assert_eq(tracker.get_status(target_key(2)), Degraded)
  tracker.report_failure(target_key(2), 2000L, "error 2")
  @test.assert_eq(tracker.get_status(target_key(2)), Degraded)
  tracker.report_failure(target_key(2), 3000L, "error 3")
  @test.assert_eq(tracker.get_status(target_key(2)), Failed)
}

///|
test "health: success after failure resets to Healthy" {
  let tracker = ShardHealthTracker::new(
    make_target_keys(4),
    failure_threshold=3,
  )
  tracker.report_failure(target_key(1), 1000L, "err")
  tracker.report_failure(target_key(1), 2000L, "err")
  @test.assert_eq(tracker.get_status(target_key(1)), Degraded)
  tracker.report_success(target_key(1), 3000L)
  @test.assert_eq(tracker.get_status(target_key(1)), Healthy)
  // Failure count was reset
  match tracker.get_health(target_key(1)) {
    Some(h) => @test.assert_eq(h.consecutive_failures, 0)
    None => assert_true(false)
  }
}

///|
test "health: success recovers Failed target" {
  let tracker = ShardHealthTracker::new(
    make_target_keys(4),
    failure_threshold=2,
  )
  tracker.report_failure(target_key(0), 1000L, "err")
  tracker.report_failure(target_key(0), 2000L, "err")
  @test.assert_eq(tracker.get_status(target_key(0)), Failed)
  tracker.report_success(target_key(0), 5000L)
  @test.assert_eq(tracker.get_status(target_key(0)), Healthy)
}

///|
test "health: Failed stays Failed on more failures" {
  let tracker = ShardHealthTracker::new(
    make_target_keys(4),
    failure_threshold=2,
  )
  tracker.report_failure(target_key(0), 1000L, "err 1")
  tracker.report_failure(target_key(0), 2000L, "err 2")
  @test.assert_eq(tracker.get_status(target_key(0)), Failed)
  tracker.report_failure(target_key(0), 3000L, "err 3")
  @test.assert_eq(tracker.get_status(target_key(0)), Failed)
  match tracker.get_health(target_key(0)) {
    Some(h) => @test.assert_eq(h.consecutive_failures, 3)
    None => assert_true(false)
  }
}

// ── healthy_targets / failed_targets ─────────────────────────────

///|
test "health: healthy_targets excludes Failed" {
  let tracker = ShardHealthTracker::new(
    make_target_keys(4),
    failure_threshold=1,
  )
  tracker.report_failure(target_key(1), 1000L, "down")
  tracker.report_failure(target_key(3), 2000L, "down")
  @test.assert_eq(tracker.healthy_targets(), [target_key(0), target_key(2)])
  @test.assert_eq(tracker.failed_targets(), [target_key(1), target_key(3)])
}

///|
test "health: Degraded included in healthy_targets" {
  let tracker = ShardHealthTracker::new(
    make_target_keys(3),
    failure_threshold=3,
  )
  tracker.report_failure(target_key(1), 1000L, "slow")
  @test.assert_eq(tracker.get_status(target_key(1)), Degraded)
  @test.assert_eq(tracker.healthy_targets(), [
    target_key(0),
    target_key(1),
    target_key(2),
  ])
  @test.assert_eq(tracker.failed_targets(), [])
}

// ── all_health ─────────────────────────────────────────────────

///|
test "health: all_health returns sorted by target_key" {
  let tracker = ShardHealthTracker::new(make_target_keys(3))
  tracker.report_failure(target_key(2), 1000L, "err")
  let all = tracker.all_health()
  @test.assert_eq(all.length(), 3)
  @test.assert_eq(all[0].target_key, target_key(0))
  @test.assert_eq(all[1].target_key, target_key(1))
  @test.assert_eq(all[2].target_key, target_key(2))
  @test.assert_eq(all[2].status, Degraded)
}

// ── Health-aware routing ───────────────────────────────────────

///|
test "health: select_read_targets excludes Failed" {
  let map = @placement.CrushMap::new(4, 1, [
    @placement.CrushTarget::new("target-0"),
    @placement.CrushTarget::new("target-1"),
    @placement.CrushTarget::new("target-2"),
    @placement.CrushTarget::new("target-3"),
  ])
  let tracker = ShardHealthTracker::new(
    make_target_keys(4),
    failure_threshold=1,
  )
  tracker.report_failure(target_key(2), 1000L, "down")
  let targets = select_read_targets(map, tracker)
  // Should not include the failed target
  for t in targets {
    assert_true(t != target_key(2))
  }
}

///|
test "health: last_error tracks most recent error" {
  let tracker = ShardHealthTracker::new(
    make_target_keys(2),
    failure_threshold=5,
  )
  tracker.report_failure(target_key(0), 1000L, "timeout")
  tracker.report_failure(target_key(0), 2000L, "connection refused")
  match tracker.get_health(target_key(0)) {
    Some(h) => @test.assert_eq(h.last_error, Some("connection refused"))
    None => assert_true(false)
  }
}

///|
test "health: timestamps updated correctly" {
  let tracker = ShardHealthTracker::new(make_target_keys(2))
  tracker.report_success(target_key(0), 5000L)
  tracker.report_failure(target_key(0), 6000L, "err")
  match tracker.get_health(target_key(0)) {
    Some(h) => {
      @test.assert_eq(h.last_success_ts, 5000L)
      @test.assert_eq(h.last_failure_ts, 6000L)
    }
    None => assert_true(false)
  }
}
