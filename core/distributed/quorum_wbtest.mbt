///|
/// Tests for quorum semantics.

// ── QuorumConfig ──────────────────────────────────────────────

///|
test "quorum: strong consistency check" {
  let config = QuorumConfig::new(3, 2, 2)
  // W(2) + R(2) = 4 > N(3) → strongly consistent
  assert_eq(config.is_strongly_consistent(), true)
}

///|
test "quorum: eventual consistency check" {
  let config = QuorumConfig::new(3, 1, 1)
  // W(1) + R(1) = 2 ≤ N(3) → not strongly consistent
  assert_eq(config.is_strongly_consistent(), false)
}

///|
test "quorum: N=1 is always strongly consistent" {
  let config = QuorumConfig::new(1, 1, 1)
  assert_eq(config.is_strongly_consistent(), true)
}

///|
test "quorum: W=N, R=1 is strongly consistent" {
  let config = QuorumConfig::new(3, 3, 1)
  // 3 + 1 = 4 > 3 → strongly consistent
  assert_eq(config.is_strongly_consistent(), true)
}

// ── Write quorum evaluation ────────────────────────────────────

///|
test "quorum: write quorum met" {
  let config = QuorumConfig::new(3, 2, 2)
  let results = [
    { replica_key: "r1", success: true, error: None },
    { replica_key: "r2", success: true, error: None },
    { replica_key: "r3", success: false, error: Some("timeout") },
  ]
  let qw = evaluate_write_quorum(results, config)
  assert_eq(qw.quorum_met, true)
  assert_eq(qw.achieved, 2)
  assert_eq(qw.required, 2)
  assert_eq(qw.succeeded.length(), 2)
  assert_eq(qw.failed.length(), 1)
}

///|
test "quorum: write quorum not met" {
  let config = QuorumConfig::new(3, 2, 2)
  let results = [
    { replica_key: "r1", success: true, error: None },
    { replica_key: "r2", success: false, error: Some("err") },
    { replica_key: "r3", success: false, error: Some("err") },
  ]
  let qw = evaluate_write_quorum(results, config)
  assert_eq(qw.quorum_met, false)
  assert_eq(qw.achieved, 1)
}

///|
test "quorum: write all succeed" {
  let config = QuorumConfig::new(3, 3, 1)
  let results = [
    { replica_key: "r1", success: true, error: None },
    { replica_key: "r2", success: true, error: None },
    { replica_key: "r3", success: true, error: None },
  ]
  let qw = evaluate_write_quorum(results, config)
  assert_eq(qw.quorum_met, true)
  assert_eq(qw.achieved, 3)
  assert_eq(qw.failed.length(), 0)
}

///|
test "quorum: write with no error message" {
  let config = QuorumConfig::new(2, 1, 1)
  let results = [
    { replica_key: "r1", success: false, error: None },
    { replica_key: "r2", success: true, error: None },
  ]
  let qw = evaluate_write_quorum(results, config)
  assert_eq(qw.quorum_met, true)
  assert_eq(qw.failed[0].1, "unknown error")
}

// ── Read quorum evaluation ────────────────────────────────────

///|
test "quorum: read quorum met with consistent values" {
  let config = QuorumConfig::new(3, 2, 2)
  let data = Bytes::make(4, b'\x42')
  let results = [
    { replica_key: "r1", value: Some(data), error: None },
    { replica_key: "r2", value: Some(data), error: None },
    { replica_key: "r3", value: None, error: Some("timeout") },
  ]
  let qr = evaluate_read_quorum(results, config)
  assert_eq(qr.quorum_met, true)
  assert_eq(qr.consistent, true)
  assert_eq(qr.achieved, 2)
  match qr.value {
    Some(v) => assert_eq(v.length(), 4)
    None => assert_true(false)
  }
}

///|
test "quorum: read quorum met but inconsistent" {
  let config = QuorumConfig::new(3, 2, 2)
  let data1 = Bytes::make(4, b'\x42')
  let data2 = Bytes::make(4, b'\xFF')
  let results = [
    { replica_key: "r1", value: Some(data1), error: None },
    { replica_key: "r2", value: Some(data2), error: None },
  ]
  let qr = evaluate_read_quorum(results, config)
  assert_eq(qr.quorum_met, true)
  assert_eq(qr.consistent, false)
  // Value is None because replicas disagree
  assert_eq(qr.value, None)
}

///|
test "quorum: read quorum not met" {
  let config = QuorumConfig::new(3, 2, 2)
  let data = Bytes::make(4, b'\x42')
  let results = [
    { replica_key: "r1", value: Some(data), error: None },
    { replica_key: "r2", value: None, error: Some("err") },
    { replica_key: "r3", value: None, error: Some("err") },
  ]
  let qr = evaluate_read_quorum(results, config)
  assert_eq(qr.quorum_met, false)
  assert_eq(qr.achieved, 1)
}

///|
test "quorum: read single replica (R=1)" {
  let config = QuorumConfig::new(3, 3, 1)
  let data = Bytes::make(8, b'\x01')
  let results = [{ replica_key: "r1", value: Some(data), error: None }]
  let qr = evaluate_read_quorum(results, config)
  assert_eq(qr.quorum_met, true)
  assert_eq(qr.consistent, true)
}

///|
test "quorum: read empty results" {
  let config = QuorumConfig::new(3, 2, 2)
  let results : Array[ReplicaReadResult] = []
  let qr = evaluate_read_quorum(results, config)
  assert_eq(qr.quorum_met, false)
  assert_eq(qr.achieved, 0)
  assert_eq(qr.consistent, true) // vacuously true
}

// ── Replica selection ──────────────────────────────────────────

///|
test "quorum: select_write_replicas returns all primaries" {
  let crush = @placement.CrushMap::new(4, 3, [
    @placement.CrushTarget::new("s0"),
    @placement.CrushTarget::new("s1"),
    @placement.CrushTarget::new("s2"),
  ])
  let replicas = select_write_replicas(make_vid(42), crush)
  // With 3 targets and replicas=3, should get all 3
  assert_eq(replicas.length(), 3)
}

///|
test "quorum: select_write_replicas with single target" {
  let crush = @placement.CrushMap::new(4, 2, [@placement.CrushTarget::new("s0")])
  let replicas = select_write_replicas(make_vid(42), crush)
  // Can only have 1 replica with 1 target (replicas capped by target count)
  assert_eq(replicas.length(), 1)
  assert_eq(replicas[0], "s0")
}

///|
test "quorum: select_read_replicas excludes failed targets" {
  let crush = @placement.CrushMap::new(4, 3, [
    @placement.CrushTarget::new("s0"),
    @placement.CrushTarget::new("s1"),
    @placement.CrushTarget::new("s2"),
  ])
  // Mark s1 as failed
  let healthy = select_read_replicas(make_vid(42), crush, ["s1"])
  // Should have 2 replicas (s0, s2) since s1 is excluded
  assert_eq(healthy.length(), 2)
  for key in healthy {
    assert_true(key != "s1")
  }
}

///|
test "quorum: select_read_replicas with no failures returns all" {
  let crush = @placement.CrushMap::new(4, 3, [
    @placement.CrushTarget::new("s0"),
    @placement.CrushTarget::new("s1"),
    @placement.CrushTarget::new("s2"),
  ])
  let healthy = select_read_replicas(make_vid(42), crush, [])
  assert_eq(healthy.length(), 3)
}

///|
test "quorum: select_read_replicas with all failures returns empty" {
  let crush = @placement.CrushMap::new(4, 3, [
    @placement.CrushTarget::new("s0"),
    @placement.CrushTarget::new("s1"),
    @placement.CrushTarget::new("s2"),
  ])
  let healthy = select_read_replicas(make_vid(42), crush, ["s0", "s1", "s2"])
  assert_eq(healthy.length(), 0)
}
