///|
/// WAL v2 format tests.
///
/// v2 format (wal_version=0x02):
///   Records: Type(1) + Flags(1) + Timestamp(8) + ID(8) + AttrsLen(4) + VectorLen(4) + Attrs + Vector
///   Has timestamp. No IDLen byte. Always Int64Id.
///
/// Key difference from v3: the ID field has no preceding IDLen byte in v2.
/// The v3 reader handles this by checking the version byte from the WAL header.
///
/// Test name prefixes:
///   "compat/v2/"  — v3 reader correctly decodes v2-format segments

///|
/// Build a raw v2 WAL segment (header v2 + v2-style record + no footer).
/// v2 record layout: Type(1) + Flags(1) + Timestamp(8) + ID(8) + AttrsLen(4) + VectorLen(4) + Vector
fn make_v2_segment(id : Int64, ts : Int64, vec : Array[Float]) -> Bytes {
  let w = @binary.BinaryWriter::new()
  // v2 header
  @codec.encode_header(w, @codec.Wal, b'\x02')
  // v2 record
  w.push_byte(b'\x01') // Upsert
  w.push_byte(b'\x01') // flags: has_timestamp (no IDLen byte in v2)
  w.push_i64(ts)
  w.push_u64(id.reinterpret_as_uint64())
  w.push_u32(0U) // AttrsLen
  w.push_u32((vec.length() * 4).reinterpret_as_uint()) // VectorLen
  for v in vec {
    w.push_f32(v)
  }
  w.concat()
}

///|
test "compat/v2_header_accepted_by_v3_reader" {
  // verify_wal_header accepts v1, v2, and v3
  let data = make_v2_segment(1L, 0L, [1.0])
  let r = @binary.BinaryReader::new(data)
  inspect(verify_wal_header(r), content="true")
}

///|
test "compat/v2_segment_decoded_as_int64id" {
  // A v2 WAL segment must decode its ID as Int64Id (no IDLen byte in v2).
  let data = make_v2_segment(99L, 1_000_000L, [1.0, 2.0])
  let records = decode_wal_records(data)
  inspect(records.length(), content="1")
  let rec = records[0]
  match rec.id {
    @types.Int64Id(v) => inspect(v, content="99")
    @types.Bytes16Id(_) => fail("expected Int64Id")
  }
  inspect(rec.timestamp, content="1000000")
}

///|
test "compat/v2_segment_negative_id" {
  // Negative Int64 must survive v2 round-trip (signed bit preservation).
  let neg_id = -1L
  let data = make_v2_segment(neg_id, 0L, [3.14])
  let records = decode_wal_records(data)
  inspect(records.length(), content="1")
  match records[0].id {
    @types.Int64Id(v) => inspect(v, content="-1")
    @types.Bytes16Id(_) => fail("expected Int64Id")
  }
}

///|
test "compat/v2_segment_max_int64_id" {
  let max_id = 9223372036854775807L // Int64 max
  let data = make_v2_segment(max_id, 0L, [0.0])
  let records = decode_wal_records(data)
  inspect(records.length(), content="1")
  match records[0].id {
    @types.Int64Id(v) => inspect(v, content="9223372036854775807")
    @types.Bytes16Id(_) => fail("expected Int64Id")
  }
}

///|
test "compat/v2_segment_replay_into_store" {
  // A v2 WAL can be replayed into a CoreStore.
  let store = @store.CoreStore::new(1, @types.L2)
  let data = make_v2_segment(7L, 500L, [1.0])
  let applied = replay_wal_data(data, store)
  inspect(applied, content="1")
  inspect(store.size(), content="1")
  match store.get(@types.Int64Id(7L)) {
    Some(rec) => inspect(rec.vector[0], content="1")
    None => fail("id 7 not found")
  }
}

///|
test "compat/v2_bytes16id_merge_with_v3_segment" {
  // merge_wal re-encodes v2 records in v3 format and accepts v3 Bytes16Id records.
  // The merged output is valid v3 and contains both IDs.
  let v2_data = make_v2_segment(10L, 100L, [1.0])
  // Build a v3 segment with a Bytes16Id
  let uuid = @types.Bytes16::{
    b0: b'\x55',
    b1: b'\x0e',
    b2: b'\x84',
    b3: b'\x00',
    b4: b'\xe2',
    b5: b'\x9b',
    b6: b'\x41',
    b7: b'\xd4',
    b8: b'\xa7',
    b9: b'\x16',
    b10: b'\x44',
    b11: b'\x66',
    b12: b'\x55',
    b13: b'\x44',
    b14: b'\x00',
    b15: b'\x00',
  }
  let v3_record = WalRecord::upsert(
    @types.Bytes16Id(uuid),
    [2.0],
    @types.empty_attrs(),
    timestamp=200L,
  )
  let v3_segment = encode_wal_segment([v3_record])
  let merged = merge_wal(v2_data, v3_segment)
  let records = decode_wal_records(merged)
  // v2 record (Int64Id=10) + v3 record (Bytes16Id) both present
  inspect(records.length(), content="2")
  let ids = records.map(fn(r) {
    match r.id {
      @types.Int64Id(v) => v.to_string()
      @types.Bytes16Id(b) => b.to_uuid_string()
    }
  })
  inspect(ids.contains("10"), content="true")
  inspect(ids.contains("550e8400-e29b-41d4-a716-446655440000"), content="true")
}
