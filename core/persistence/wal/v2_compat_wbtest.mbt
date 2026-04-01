///|
/// WAL v2 format compatibility tests

///|
test "v2/encode_decode_with_timestamp" {
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
test "v2/timestamp_zero_is_valid" {
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
    Some(rec) => {
      // timestamp=0 but flags still has has_timestamp bit set (v2 format)
      inspect(rec.timestamp, content="0")
    }
    None => inspect(false, content="true")
  }
}

///|
test "v2/segment_roundtrip_with_timestamps" {
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
test "v2/filter_by_timestamp" {
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
test "v2/filter_includes_v1_records" {
  // v1 records have timestamp=0, should always be included
  let records = [
    WalRecord::upsert(
      @types.VectorId::from_int(1),
      [1.0],
      @types.empty_attrs(),
      timestamp=0L, // v1-style (no timestamp)
    ),
    WalRecord::upsert(
      @types.VectorId::from_int(2),
      [2.0],
      @types.empty_attrs(),
      timestamp=500L, // v2 with timestamp
    ),
  ]
  let segment = encode_wal_segment(records)
  // Filter at timestamp 100 — v1 record (ts=0) always included,
  // v2 record (ts=500) excluded
  let filtered = filter_wal_by_timestamp(segment, 100L)
  inspect(filtered.length(), content="1")
  inspect(filtered[0].id.to_int64(), content="1")
}

///|
test "v2/max_wal_timestamp" {
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
test "v2/max_wal_timestamp_empty" {
  let segment = encode_wal_segment([])
  let max_ts = max_wal_timestamp(segment)
  inspect(max_ts, content="0")
}

///|
test "v2/merge_preserves_timestamps" {
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
test "v2/replay_with_cutoff" {
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
test "v2/replay_no_cutoff_includes_all" {
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

///|
test "v2/header_version_is_v2" {
  let header = encode_wal_header()
  let r = @binary.BinaryReader::new(header)
  inspect(verify_wal_header(r), content="true")
  // Header: magic(8) + type(1) + version(1) + reserved(2)
  // Position 8 = file type (WAL=0x01), position 9 = version
  inspect(header[9], content="b'\\x02'")
}

///|
test "v2/v1_header_still_accepted" {
  // Manually create a v1 header
  let w = @binary.BinaryWriter::new()
  @codec.encode_header(w, @codec.Wal, b'\x01')
  let v1_header = w.concat()
  let r = @binary.BinaryReader::new(v1_header)
  inspect(verify_wal_header(r), content="true")
}

///|
test "v2/v1_record_decode_gives_zero_timestamp" {
  // Manually encode a v1-style record (flags=0x00, no timestamp)
  let w = @binary.BinaryWriter::new()
  // Type: Upsert
  w.push_byte(b'\x01')
  // Reserved/Flags: 0x00 (v1 style)
  w.push_byte(b'\x00')
  // ID
  w.push_u64(42UL)
  // AttrsLen=0, VectorLen=4 (1 float)
  w.push_u32(0U)
  w.push_u32(4U)
  // Vector: 1.0 as f32
  w.push_f32(1.0)
  let data = w.concat()
  let r = @binary.BinaryReader::new(data)
  let decoded = decode_wal_record(r)
  match decoded {
    Some(rec) => {
      inspect(rec.timestamp, content="0")
      inspect(rec.id.to_int64(), content="42")
      inspect(rec.record_type == WalRecordType::Upsert, content="true")
      match rec.vector {
        Some(v) => inspect(v.length(), content="1")
        None => inspect(false, content="true")
      }
    }
    None => inspect(false, content="true")
  }
}
