///|
/// Tests for partition detection and recovery.

///|
fn ptk(s : String) -> @placement.TargetKey {
  @placement.TargetKey::new(s)
}

// ── PartitionState ─────────────────────────────────────────────

///|
test "partition: initial state all connected" {
  let keys = [ptk("a"), ptk("b"), ptk("c"), ptk("d")]
  let state = PartitionState::new(keys)
  for key in keys {
    assert_eq(state.get_status(key), Connected)
    assert_eq(state.is_partitioned(key), false)
  }
  assert_eq(state.partitioned_targets().length(), 0)
}

///|
test "partition: detect and resolve" {
  let keys = [ptk("a"), ptk("b"), ptk("c"), ptk("d")]
  let state = PartitionState::new(keys)
  state.detect_partition(ptk("c"), 5000L)
  assert_eq(state.get_status(ptk("c")), Partitioned(5000L))
  assert_eq(state.is_partitioned(ptk("c")), true)
  assert_eq(state.partitioned_targets(), [(ptk("c"), 5000L)])

  state.resolve_partition(ptk("c"))
  assert_eq(state.get_status(ptk("c")), Connected)
  assert_eq(state.is_partitioned(ptk("c")), false)
}

///|
test "partition: detect preserves original timestamp" {
  let keys = [ptk("a"), ptk("b"), ptk("c"), ptk("d")]
  let state = PartitionState::new(keys)
  state.detect_partition(ptk("b"), 1000L)
  // Second detection should not change the timestamp
  state.detect_partition(ptk("b"), 5000L)
  assert_eq(state.get_status(ptk("b")), Partitioned(1000L))
}

///|
test "partition: multiple partitioned targets" {
  let keys = [ptk("a"), ptk("b"), ptk("c"), ptk("d")]
  let state = PartitionState::new(keys)
  state.detect_partition(ptk("a"), 1000L)
  state.detect_partition(ptk("d"), 2000L)
  let partitioned = state.partitioned_targets()
  assert_eq(partitioned.length(), 2)
  assert_eq(partitioned[0], (ptk("a"), 1000L))
  assert_eq(partitioned[1], (ptk("d"), 2000L))
}

// ── LWW conflict resolution ────────────────────────────────────

///|
fn make_upsert_record(
  id : Int,
  ts : Int64,
  vector : Array[Double],
) -> @wal.WalRecord {
  @wal.WalRecord::upsert(
    @types.VectorId::from_int(id),
    vector,
    @types.empty_attrs(),
    timestamp=ts,
  )
}

///|
test "partition: LWW remote wins (higher timestamp)" {
  let local_records = [make_upsert_record(1, 1000L, [1.0])]
  let remote = [make_upsert_record(1, 2000L, [2.0])]
  let (merged, conflicts) = resolve_conflicts_lww(local_records, remote)
  assert_eq(merged.length(), 1)
  assert_eq(conflicts.length(), 1)
  assert_eq(conflicts[0].resolution, KeepRemote)
  assert_eq(conflicts[0].remote_ts, 2000L)
}

///|
test "partition: LWW local wins (higher timestamp)" {
  let local_records = [make_upsert_record(1, 3000L, [1.0])]
  let remote = [make_upsert_record(1, 1000L, [2.0])]
  let (merged, conflicts) = resolve_conflicts_lww(local_records, remote)
  assert_eq(merged.length(), 1)
  assert_eq(conflicts.length(), 1)
  assert_eq(conflicts[0].resolution, KeepLocal)
}

///|
test "partition: LWW tie-break same timestamp" {
  let local_records = [make_upsert_record(1, 1000L, [1.0])]
  let remote = [make_upsert_record(1, 1000L, [2.0])]
  let (merged, conflicts) = resolve_conflicts_lww(local_records, remote)
  assert_eq(merged.length(), 1)
  assert_eq(conflicts.length(), 1)
  assert_eq(conflicts[0].resolution, TieBreakById)
}

///|
test "partition: no conflicts (disjoint IDs)" {
  let local_records = [make_upsert_record(1, 1000L, [1.0])]
  let remote = [make_upsert_record(2, 2000L, [2.0])]
  let (merged, conflicts) = resolve_conflicts_lww(local_records, remote)
  assert_eq(merged.length(), 2)
  assert_eq(conflicts.length(), 0)
}

///|
test "partition: mixed conflicts and non-conflicts" {
  let local_records = [
    make_upsert_record(1, 1000L, [1.0]),
    make_upsert_record(2, 3000L, [2.0]),
    make_upsert_record(3, 1000L, [3.0]),
  ]
  let remote = [
    make_upsert_record(1, 2000L, [1.5]), // conflict: remote wins
    make_upsert_record(4, 4000L, [4.0]), // remote only
  ]
  let (merged, conflicts) = resolve_conflicts_lww(local_records, remote)
  assert_eq(merged.length(), 4) // IDs 1,2,3,4
  assert_eq(conflicts.length(), 1) // Only ID 1
  assert_eq(conflicts[0].resolution, KeepRemote)
}

// ── merge_divergent_wals ───────────────────────────────────────

///|
test "partition: merge divergent WALs" {
  // Base records (before divergence)
  let base = [
    make_upsert_record(1, 1000L, [1.0]),
    make_upsert_record(2, 2000L, [2.0]),
  ]

  // Local adds record 3 after divergence at ts=2000
  let local_records : Array[@wal.WalRecord] = []
  for r in base {
    local_records.push(r)
  }
  local_records.push(make_upsert_record(3, 3000L, [3.0]))
  let local_wal = @wal.encode_wal_segment(local_records)

  // Remote modifies record 1 after divergence at ts=2000
  let remote_records : Array[@wal.WalRecord] = []
  for r in base {
    remote_records.push(r)
  }
  remote_records.push(make_upsert_record(1, 4000L, [1.5]))
  let remote_wal = @wal.encode_wal_segment(remote_records)

  let (merged_wal, conflicts) = merge_divergent_wals(
    local_wal, remote_wal, 2000L,
  )

  // Merged should have: base (2 records) + record 3 (local) + record 1 update (remote wins)
  let decoded = @wal.decode_wal_records(merged_wal)
  assert_true(decoded.length() >= 3)

  // One conflict: ID 1 was modified by remote (ts=4000 > local ts=N/A for post-diverge)
  // Actually: local has ID 3 (ts=3000), remote has ID 1 (ts=4000). No overlap in diverged → no conflicts
  assert_eq(conflicts.length(), 0)
}

///|
test "partition: merge divergent WALs with conflict" {
  // Both sides modify ID 5 after divergence
  let base = [make_upsert_record(1, 1000L, [1.0])]

  let local_records : Array[@wal.WalRecord] = []
  for r in base {
    local_records.push(r)
  }
  local_records.push(make_upsert_record(5, 3000L, [5.0]))
  let local_wal = @wal.encode_wal_segment(local_records)

  let remote_records : Array[@wal.WalRecord] = []
  for r in base {
    remote_records.push(r)
  }
  remote_records.push(make_upsert_record(5, 4000L, [5.5]))
  let remote_wal = @wal.encode_wal_segment(remote_records)

  let (merged_wal, conflicts) = merge_divergent_wals(
    local_wal, remote_wal, 1000L,
  )

  let decoded = @wal.decode_wal_records(merged_wal)
  // Base (1 record) + merged divergent (1 record, remote wins)
  assert_eq(decoded.length(), 2)
  assert_eq(conflicts.length(), 1)
  assert_eq(conflicts[0].resolution, KeepRemote)
}

// ── Recovery plan ─────────────────────────────────────────────

///|
test "partition: recovery plan for resolved targets" {
  let target_keys = [ptk("t-0"), ptk("t-1"), ptk("t-2"), ptk("t-3")]
  let partition_state = PartitionState::new(target_keys)
  let replication_state = ReplicationState::new(["t-0", "t-1", "t-2", "t-3"])
  replication_state.primary_max_ts = 10000L
  replication_state.update_replica_position("t-1", 5000L)
  replication_state.update_replica_position("t-3", 3000L)

  // Targets 1 and 3 were partitioned, now resolved
  let plan = recovery_plan(partition_state, replication_state, [
    ptk("t-1"),
    ptk("t-3"),
  ])
  assert_eq(plan.length(), 2)
  assert_eq(plan[0], (ptk("t-1"), 5000L))
  assert_eq(plan[1], (ptk("t-3"), 3000L))
}

///|
test "partition: recovery plan skips still-partitioned targets" {
  let target_keys = [ptk("t-0"), ptk("t-1"), ptk("t-2"), ptk("t-3")]
  let partition_state = PartitionState::new(target_keys)
  partition_state.detect_partition(ptk("t-2"), 1000L)

  let replication_state = ReplicationState::new(["t-2"])

  // Target 2 is still partitioned
  let plan = recovery_plan(partition_state, replication_state, [ptk("t-2")])
  assert_eq(plan.length(), 0) // Skipped because still partitioned
}

///|
test "partition: recovery plan with no resolved targets" {
  let target_keys = [ptk("t-0"), ptk("t-1"), ptk("t-2"), ptk("t-3")]
  let partition_state = PartitionState::new(target_keys)
  let replication_state = ReplicationState::new([])
  let plan : Array[(@placement.TargetKey, Int64)] = recovery_plan(
    partition_state,
    replication_state,
    [],
  )
  assert_eq(plan.length(), 0)
}
