///|
/// Tests for partition detection and recovery.

// ── PartitionState ─────────────────────────────────────────────

///|
test "partition: initial state all connected" {
  let state = PartitionState::new(4)
  for i in 0..<4 {
    assert_eq(state.get_status(i), Connected)
    assert_eq(state.is_partitioned(i), false)
  }
  assert_eq(state.partitioned_shards().length(), 0)
}

///|
test "partition: detect and resolve" {
  let state = PartitionState::new(4)
  state.detect_partition(2, 5000L)
  assert_eq(state.get_status(2), Partitioned(5000L))
  assert_eq(state.is_partitioned(2), true)
  assert_eq(state.partitioned_shards(), [(2, 5000L)])

  state.resolve_partition(2)
  assert_eq(state.get_status(2), Connected)
  assert_eq(state.is_partitioned(2), false)
}

///|
test "partition: detect preserves original timestamp" {
  let state = PartitionState::new(4)
  state.detect_partition(1, 1000L)
  // Second detection should not change the timestamp
  state.detect_partition(1, 5000L)
  assert_eq(state.get_status(1), Partitioned(1000L))
}

///|
test "partition: multiple partitioned shards" {
  let state = PartitionState::new(4)
  state.detect_partition(0, 1000L)
  state.detect_partition(3, 2000L)
  let partitioned = state.partitioned_shards()
  assert_eq(partitioned.length(), 2)
  assert_eq(partitioned[0], (0, 1000L))
  assert_eq(partitioned[1], (3, 2000L))
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
test "partition: recovery plan for resolved shards" {
  let partition_state = PartitionState::new(4)
  let replication_state = ReplicationState::new([
    "shard-0", "shard-1", "shard-2", "shard-3",
  ])
  replication_state.primary_max_ts = 10000L
  replication_state.update_replica_position("shard-1", 5000L)
  replication_state.update_replica_position("shard-3", 3000L)

  // Shards 1 and 3 were partitioned, now resolved
  let plan = recovery_plan(partition_state, replication_state, [1, 3])
  assert_eq(plan.length(), 2)
  assert_eq(plan[0], (1, 5000L))
  assert_eq(plan[1], (3, 3000L))
}

///|
test "partition: recovery plan skips still-partitioned shards" {
  let partition_state = PartitionState::new(4)
  partition_state.detect_partition(2, 1000L)

  let replication_state = ReplicationState::new(["shard-2"])

  // Shard 2 is still partitioned
  let plan = recovery_plan(partition_state, replication_state, [2])
  assert_eq(plan.length(), 0) // Skipped because still partitioned
}

///|
test "partition: recovery plan with no resolved shards" {
  let partition_state = PartitionState::new(4)
  let replication_state = ReplicationState::new([])
  let plan = recovery_plan(partition_state, replication_state, [])
  assert_eq(plan.length(), 0)
}
