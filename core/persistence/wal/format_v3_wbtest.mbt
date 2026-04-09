///|
/// WAL v3 format tests.
///
/// v3 format (wal_version=0x03):
///   Records: Type(1) + Flags(1) + Timestamp(8) + IDLen(1) + ID(IDLen bytes) + AttrsLen(4) + VectorLen(4) + Attrs + Vector
///   Has timestamp. Has IDLen byte. Supports Int64Id (IDLen=8) and Bytes16Id (IDLen=16).
///
/// Key difference from v2: the IDLen byte is present before the ID payload.
/// Flag bit 1 (0x02 = has_128bit_id) distinguishes Bytes16Id from Int64Id within v3.
///
/// Test name prefixes:
///   "v3/"  — v3-specific features (Bytes16Id, IDLen, header version)

///|
/// A fixed UUID for use across v3 tests: 550e8400-e29b-41d4-a716-446655440000
fn sample_uuid() -> @types.Bytes16 {
  @types.Bytes16::{
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
}

///|
test "v3/header_version_is_v3" {
  let header = encode_wal_header()
  let r = @binary.BinaryReader::new(header)
  inspect(verify_wal_header(r), content="true")
  // Header: magic(8) + type(1) + version(1) + reserved(2)
  // Position 8 = file type (WAL=0x01), position 9 = version
  inspect(header[9], content="b'\\x03'")
}

///|
test "v3/bytes16id_encode_decode_roundtrip" {
  let id = @types.Bytes16Id(sample_uuid())
  let record = WalRecord::upsert(id, [1.0, 2.0, 3.0], @types.empty_attrs(), timestamp=999L)
  let encoded = encode_wal_record(record)
  let r = @binary.BinaryReader::new(encoded)
  match decode_wal_record(r) {
    Some(rec) => {
      inspect(rec.timestamp, content="999")
      match rec.id {
        @types.Int64Id(_) => fail("expected Bytes16Id")
        @types.Bytes16Id(b) =>
          inspect(b.to_uuid_string(), content="550e8400-e29b-41d4-a716-446655440000")
      }
      match rec.vector {
        Some(v) => inspect(v.length(), content="3")
        None => fail("vector missing")
      }
    }
    None => fail("decode returned None")
  }
}

///|
test "v3/bytes16id_segment_roundtrip" {
  let id = @types.Bytes16Id(sample_uuid())
  let record = WalRecord::upsert(id, [9.0], @types.empty_attrs(), timestamp=12345L)
  let segment = encode_wal_segment([record])
  let records = decode_wal_records(segment)
  inspect(records.length(), content="1")
  match records[0].id {
    @types.Int64Id(_) => fail("expected Bytes16Id")
    @types.Bytes16Id(b) =>
      inspect(b.to_uuid_string(), content="550e8400-e29b-41d4-a716-446655440000")
  }
}

///|
test "v3/bytes16id_replay_into_store" {
  let store = @store.CoreStore::new(1, @types.L2)
  let uuid = sample_uuid()
  let id = @types.Bytes16Id(uuid)
  let segment = encode_wal_segment([
    WalRecord::upsert(id, [7.0], @types.empty_attrs(), timestamp=1L),
  ])
  let applied = replay_wal_data(segment, store)
  inspect(applied, content="1")
  inspect(store.size(), content="1")
  match store.get(@types.Bytes16Id(uuid)) {
    Some(rec) => inspect(rec.vector[0], content="7")
    None => fail("Bytes16Id not found in store")
  }
}

///|
test "v3/mixed_int64id_and_bytes16id_in_one_segment" {
  let store = @store.CoreStore::new(2, @types.L2)
  let int_id = @types.Int64Id(42L)
  let uuid_id = @types.Bytes16Id(sample_uuid())
  let segment = encode_wal_segment([
    WalRecord::upsert(int_id, [1.0, 2.0], @types.empty_attrs(), timestamp=1L),
    WalRecord::upsert(uuid_id, [3.0, 4.0], @types.empty_attrs(), timestamp=2L),
  ])
  let applied = replay_wal_data(segment, store)
  inspect(applied, content="2")
  inspect(store.size(), content="2")
  // Both IDs must be retrievable
  match store.get(int_id) {
    Some(rec) => inspect(rec.vector[0], content="1")
    None => fail("Int64Id not found")
  }
  match store.get(uuid_id) {
    Some(rec) => inspect(rec.vector[0], content="3")
    None => fail("Bytes16Id not found")
  }
}

///|
test "v3/bytes16id_remove_record" {
  let store = @store.CoreStore::new(1, @types.L2)
  let uuid_id = @types.Bytes16Id(sample_uuid())
  let segment = encode_wal_segment([
    WalRecord::upsert(uuid_id, [1.0], @types.empty_attrs(), timestamp=1L),
    WalRecord::remove(uuid_id, timestamp=2L),
  ])
  let applied = replay_wal_data(segment, store)
  inspect(applied, content="2")
  inspect(store.size(), content="0")
}
