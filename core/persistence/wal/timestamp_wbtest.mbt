///|
/// WAL timestamp field behavior tests.
///
/// These tests verify the timestamp field semantics regardless of WAL format version.
/// All records here are encoded in the current (v3) format.
///
/// Timestamp semantics:
///   - Int64 nanoseconds since Unix epoch
///   - 0 means "no timestamp" (v1 compatibility contract) — always included by filter
///   - filter_wal_by_timestamp includes records where timestamp == 0 OR timestamp <= cutoff
///
/// Test name prefix: "timestamp/"

///|
test "timestamp/encode_decode_int64id" {
  let record = WalRecord::upsert(
    @types.VectorId::from_int(1),
    [1.0, 2.0],
    @types.empty_attrs(),
    timestamp=1000000L,
  )
  let encoded = encode_wal_record(record)
  let r = @binary.BinaryReader::new(encoded)
  let decoded = decode_wal_record(r)
  match decoded {
    Some(rec) => {
      inspect(rec.timestamp, content="1000000")
      inspect(rec.id.to_int64(), content="1")
      inspect(rec.record_type == WalRecordType::Upsert, content="true")
    }
    None => inspect(false, content="true")
  }
}

///|
test "timestamp/zero_value_is_valid" {
  let record = WalRecord::upsert(
    @types.VectorId::from_int(1),
    [1.0],
    @types.empty_attrs(),
    timestamp=0L,
  )
  let encoded = encode_wal_record(record)
  let r = @binary.BinaryReader::new(encoded)
  let decoded = decode_wal_record(r)
  match decoded {
    Some(rec) =>
      // In v3, has_timestamp flag is always set; timestamp field value 0 is valid
      inspect(rec.timestamp, content="0")
    None => inspect(false, content="true")
  }
}

///|
test "timestamp/segment_roundtrip_all_record_types" {
  let records = [
    WalRecord::upsert(
      @types.VectorId::from_int(1),
      [1.0],
      @types.empty_attrs(),
      timestamp=100L,
    ),
    WalRecord::remove(@types.VectorId::from_int(2), timestamp=200L),
    WalRecord::set_attrs(
      @types.VectorId::from_int(3),
      @types.empty_attrs(),
      timestamp=300L,
    ),
  ]
  let segment = encode_wal_segment(records)
  inspect(verify_wal_checksum(segment), content="true")
  let decoded = decode_wal_records(segment)
  inspect(decoded.length(), content="3")
  inspect(decoded[0].timestamp, content="100")
  inspect(decoded[1].timestamp, content="200")
  inspect(decoded[2].timestamp, content="300")
}

///|
test "timestamp/filter_by_cutoff" {
  let records = [
    WalRecord::upsert(
      @types.VectorId::from_int(1),
      [1.0],
      @types.empty_attrs(),
      timestamp=100L,
    ),
    WalRecord::upsert(
      @types.VectorId::from_int(2),
      [2.0],
      @types.empty_attrs(),
      timestamp=200L,
    ),
    WalRecord::upsert(
      @types.VectorId::from_int(3),
      [3.0],
      @types.empty_attrs(),
      timestamp=300L,
    ),
  ]
  let segment = encode_wal_segment(records)
  // Filter at timestamp 200 — should include records at 100 and 200
  let filtered = filter_wal_by_timestamp(segment, 200L)
  inspect(filtered.length(), content="2")
  inspect(filtered[0].id.to_int64(), content="1")
  inspect(filtered[1].id.to_int64(), content="2")
}

///|
test "timestamp/filter_always_includes_zero_timestamp" {
  // Records with timestamp=0 are always included regardless of cutoff.
  // This matches the WAL v1 compatibility contract: v1 records had no timestamp
  // field and are replayed as timestamp=0. When decoded through decode_wal_records
  // from a v1 segment they arrive with timestamp=0, meaning "no timestamp — always
  // include". New v3 records can also carry timestamp=0 (explicit zero), and the
  // filter must treat them the same way.
  let records = [
    WalRecord::upsert(
      @types.VectorId::from_int(1),
      [1.0],
      @types.empty_attrs(),
      timestamp=0L, // explicit zero — always included by filter
    ),
    WalRecord::upsert(
      @types.VectorId::from_int(2),
      [2.0],
      @types.empty_attrs(),
      timestamp=500L,
    ),
  ]
  let segment = encode_wal_segment(records)
  // cutoff=100: record with ts=0 always included; record with ts=500 excluded
  let filtered = filter_wal_by_timestamp(segment, 100L)
  inspect(filtered.length(), content="1")
  inspect(filtered[0].id.to_int64(), content="1")
}

///|
test "timestamp/max_wal_timestamp" {
  let records = [
    WalRecord::upsert(
      @types.VectorId::from_int(1),
      [1.0],
      @types.empty_attrs(),
      timestamp=100L,
    ),
    WalRecord::upsert(
      @types.VectorId::from_int(2),
      [2.0],
      @types.empty_attrs(),
      timestamp=500L,
    ),
    WalRecord::remove(@types.VectorId::from_int(3), timestamp=300L),
  ]
  let segment = encode_wal_segment(records)
  let max_ts = max_wal_timestamp(segment)
  inspect(max_ts, content="500")
}

///|
test "timestamp/max_wal_timestamp_empty_segment" {
  let segment = encode_wal_segment([])
  let max_ts = max_wal_timestamp(segment)
  inspect(max_ts, content="0")
}

///|
test "timestamp/merge_preserves_timestamps" {
  let seg1 = encode_wal_segment([
    WalRecord::upsert(
      @types.VectorId::from_int(1),
      [1.0],
      @types.empty_attrs(),
      timestamp=100L,
    ),
  ])
  let seg2 = encode_wal_segment([
    WalRecord::upsert(
      @types.VectorId::from_int(2),
      [2.0],
      @types.empty_attrs(),
      timestamp=200L,
    ),
  ])
  let merged = merge_wal(seg1, seg2)
  let records = decode_wal_records(merged)
  inspect(records.length(), content="2")
  inspect(records[0].timestamp, content="100")
  inspect(records[1].timestamp, content="200")
  inspect(verify_wal_checksum(merged), content="true")
}

///|
test "timestamp/replay_with_cutoff" {
  let records = [
    WalRecord::upsert(
      @types.VectorId::from_int(1),
      [1.0, 0.0],
      @types.empty_attrs(),
      timestamp=100L,
    ),
    WalRecord::upsert(
      @types.VectorId::from_int(2),
      [0.0, 1.0],
      @types.empty_attrs(),
      timestamp=200L,
    ),
    WalRecord::upsert(
      @types.VectorId::from_int(3),
      [1.0, 1.0],
      @types.empty_attrs(),
      timestamp=300L,
    ),
  ]
  let segment = encode_wal_segment(records)
  // Replay with cutoff at 200 — only ids 1 and 2
  let store = @store.CoreStore::new(2, @types.Cosine)
  let applied = replay_wal_data(segment, store, cutoff_ts=200L)
  inspect(applied, content="2")
  inspect(store.size(), content="2")
  inspect(store.has(@types.VectorId::from_int(1)), content="true")
  inspect(store.has(@types.VectorId::from_int(2)), content="true")
  inspect(store.has(@types.VectorId::from_int(3)), content="false")
}

///|
test "timestamp/replay_no_cutoff_includes_all" {
  let records = [
    WalRecord::upsert(
      @types.VectorId::from_int(1),
      [1.0],
      @types.empty_attrs(),
      timestamp=100L,
    ),
    WalRecord::upsert(
      @types.VectorId::from_int(2),
      [2.0],
      @types.empty_attrs(),
      timestamp=200L,
    ),
  ]
  let segment = encode_wal_segment(records)
  let store = @store.CoreStore::new(1, @types.Cosine)
  // cutoff_ts=0 means no filter (default)
  let applied = replay_wal_data(segment, store)
  inspect(applied, content="2")
  inspect(store.size(), content="2")
}
