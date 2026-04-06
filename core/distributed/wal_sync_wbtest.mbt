///|
/// Tests for WAL shipping and replica synchronization.

///|
fn make_wal_record(
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
fn make_test_wal(records : Array[@wal.WalRecord]) -> Bytes {
  @wal.encode_wal_segment(records)
}

// ── extract_wal_since ──────────────────────────────────────────

///|
test "wal_sync: extract all records from timestamp 0" {
  let records = [
    make_wal_record(1, 1000L, [1.0, 2.0]),
    make_wal_record(2, 2000L, [3.0, 4.0]),
    make_wal_record(3, 3000L, [5.0, 6.0]),
  ]
  let wal = make_test_wal(records)
  let shipment = extract_wal_since(wal, 0L, 0)
  assert_eq(shipment.record_count, 3)
  assert_eq(shipment.from_ts, 0L)
  assert_eq(shipment.to_ts, 3000L)
  assert_eq(shipment.source_shard, 0)
}

///|
test "wal_sync: extract records after specific timestamp" {
  let records = [
    make_wal_record(1, 1000L, [1.0]),
    make_wal_record(2, 2000L, [2.0]),
    make_wal_record(3, 3000L, [3.0]),
  ]
  let wal = make_test_wal(records)
  let shipment = extract_wal_since(wal, 1000L, 0)
  // Only records with ts > 1000 (i.e., 2000 and 3000)
  assert_eq(shipment.record_count, 2)
  assert_eq(shipment.to_ts, 3000L)
}

///|
test "wal_sync: extract with no new records" {
  let records = [make_wal_record(1, 1000L, [1.0])]
  let wal = make_test_wal(records)
  let shipment = extract_wal_since(wal, 5000L, 0)
  assert_eq(shipment.record_count, 0)
  assert_eq(shipment.to_ts, 5000L)
}

///|
test "wal_sync: extract from empty WAL" {
  let wal = @wal.encode_wal_header()
  let shipment = extract_wal_since(wal, 0L, 0)
  assert_eq(shipment.record_count, 0)
}

// ── apply_wal_shipment ─────────────────────────────────────────

///|
test "wal_sync: apply shipment to empty replica" {
  let records = [
    make_wal_record(1, 1000L, [1.0]),
    make_wal_record(2, 2000L, [2.0]),
  ]
  let primary_wal = make_test_wal(records)
  let shipment = extract_wal_since(primary_wal, 0L, 0)

  let empty_wal = Bytes::new(0)
  let merged = apply_wal_shipment(empty_wal, shipment)

  // Merged WAL should contain the shipped records
  let decoded = @wal.decode_wal_records(merged)
  assert_eq(decoded.length(), 2)
}

///|
test "wal_sync: apply shipment merges with existing" {
  let existing_records = [make_wal_record(1, 1000L, [1.0])]
  let existing_wal = make_test_wal(existing_records)

  let new_records = [
    make_wal_record(2, 2000L, [2.0]),
    make_wal_record(3, 3000L, [3.0]),
  ]
  let new_wal = make_test_wal(new_records)
  let shipment : WalShipment = {
    source_shard: 0,
    from_ts: 1000L,
    to_ts: 3000L,
    data: new_wal,
    record_count: 2,
  }

  let merged = apply_wal_shipment(existing_wal, shipment)
  let decoded = @wal.decode_wal_records(merged)
  assert_eq(decoded.length(), 3)
}

// ── ReplicationState ───────────────────────────────────────────

///|
test "wal_sync: replication state initial positions" {
  let state = ReplicationState::new(["r1", "r2", "r3"])
  assert_eq(state.replica_position("r1"), 0L)
  assert_eq(state.replica_position("r2"), 0L)
  assert_eq(state.replica_position("unknown"), 0L)
}

///|
test "wal_sync: update and query replica position" {
  let state = ReplicationState::new(["r1", "r2"])
  state.update_replica_position("r1", 5000L)
  assert_eq(state.replica_position("r1"), 5000L)
  assert_eq(state.replica_position("r2"), 0L)
}

///|
test "wal_sync: replication lag computation" {
  let state = ReplicationState::new(["r1", "r2"])
  state.primary_max_ts = 10000L
  state.update_replica_position("r1", 8000L)
  state.update_replica_position("r2", 10000L)

  let lags = state.compute_replication_lag()
  assert_eq(lags.length(), 2)
  // r1 has 2000ns lag
  assert_eq(lags[0].replica_key, "r1")
  assert_eq(lags[0].lag_ns, 2000L)
  // r2 is caught up
  assert_eq(lags[1].replica_key, "r2")
  assert_eq(lags[1].lag_ns, 0L)
}

///|
test "wal_sync: is_replica_caught_up" {
  let state = ReplicationState::new(["r1", "r2"])
  state.primary_max_ts = 10000L
  state.update_replica_position("r1", 9500L)
  state.update_replica_position("r2", 5000L)

  // r1 within tolerance of 1000ns
  assert_eq(state.is_replica_caught_up("r1", 1000L), true)
  // r2 not within tolerance
  assert_eq(state.is_replica_caught_up("r2", 1000L), false)
  // Unknown replica is never caught up
  assert_eq(state.is_replica_caught_up("unknown", 1000L), false)
}

///|
test "wal_sync: update_primary_ts from WAL data" {
  let records = [
    make_wal_record(1, 1000L, [1.0]),
    make_wal_record(2, 5000L, [2.0]),
    make_wal_record(3, 3000L, [3.0]),
  ]
  let wal = make_test_wal(records)
  let state = ReplicationState::new(["r1"])
  state.update_primary_ts(wal)
  assert_eq(state.primary_max_ts, 5000L)
}
