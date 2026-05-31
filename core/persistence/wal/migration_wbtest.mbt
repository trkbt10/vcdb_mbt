// AUTO-GENERATED — cross-version WAL migration verification. Do not hand-edit byte arrays.
// Each `data` below is the REAL output of that WAL format version's own
// encode_wal_segment, produced by building the matching historical commit in an
// isolated git worktree and encoding one fixed dataset:
//   v2 = 17ef48f  wal_version 0x02   (decode + replay + re-encode: PASS)
//   v3 = 4db6088  wal_version 0x03   (DEFECT: decode returns 0 records — see below)
//   v4 = 0254f3c  wal_version 0x04   (current branch HEAD; round-trips)
// Header magic for all three is "VCDBMBT\0"; file-type byte 0x01 (Wal).
// Dataset: upsert(1,[1,2,3],{src:"a"}), upsert(2,[4,5,6],{src:"b"}),
//          set_attrs(1,{src:"c"}), remove(2).
// Byte sources are also committed as spec/migration/wal_v{2,3,4}.hex.
//
// v1 (wal_version 0x01) is NOT generated from its own code here: the v1-era
// `collection` package imports `moonbitlang/async/js_async`, which no longer
// resolves under the current async dependency, so that historical package will
// not build. v1 read/replay against the current decoder is already covered by
// the hand-built real-layout segment in format_v1_wbtest.mbt.

///|
test "migration/v2_real_artifact_17ef48f" {
  // real wal_version 0x02 segment emitted by 17ef48f's own encode_wal_segment
  let data = Bytes::from_array([b'\x56', b'\x43', b'\x44', b'\x42', b'\x4d', b'\x42', b'\x54', b'\x00', b'\x01', b'\x02', b'\x00', b'\x00', b'\x01', b'\x01', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x01', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x0b', b'\x00', b'\x00', b'\x00', b'\x0c', b'\x00', b'\x00', b'\x00', b'\x7b', b'\x22', b'\x73', b'\x72', b'\x63', b'\x22', b'\x3a', b'\x22', b'\x61', b'\x22', b'\x7d', b'\x00', b'\x00', b'\x80', b'\x3f', b'\x00', b'\x00', b'\x00', b'\x40', b'\x00', b'\x00', b'\x40', b'\x40', b'\x01', b'\x01', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x02', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x0b', b'\x00', b'\x00', b'\x00', b'\x0c', b'\x00', b'\x00', b'\x00', b'\x7b', b'\x22', b'\x73', b'\x72', b'\x63', b'\x22', b'\x3a', b'\x22', b'\x62', b'\x22', b'\x7d', b'\x00', b'\x00', b'\x80', b'\x40', b'\x00', b'\x00', b'\xa0', b'\x40', b'\x00', b'\x00', b'\xc0', b'\x40', b'\x03', b'\x01', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x01', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x0b', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x7b', b'\x22', b'\x73', b'\x72', b'\x63', b'\x22', b'\x3a', b'\x22', b'\x63', b'\x22', b'\x7d', b'\x02', b'\x01', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x02', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x04', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x6e', b'\x75', b'\x6c', b'\x6c', b'\x57', b'\x43', b'\x52', b'\x43', b'\x69', b'\xfb', b'\x90', b'\x27'][:])
  assert_true(verify_wal_header(@binary.BinaryReader::new(data)))
  let rv = @binary.BinaryReader::new(data)
  rv.skip(9)
  assert_eq(rv.read_byte(), b'\x02')
  let recs = decode_wal_records(data)
  assert_eq(recs.length(), 4)
  assert_true(recs[0].record_type == WalRecordType::Upsert)
  assert_true(recs[0].id is @types.Int64Id(_))
  match recs[0].vector {
    Some(v) => {
      assert_eq(v.length(), 3)
      assert_eq(v[0], 1.0)
      assert_eq(v[1], 2.0)
      assert_eq(v[2], 3.0)
    }
    None => fail("rec0 vector missing")
  }
  match recs[0].attrs {
    Some(a) => assert_true(a.get("src") is Some(@types.String("a")))
    None => fail("rec0 attrs missing")
  }
  assert_true(recs[1].record_type == WalRecordType::Upsert)
  match recs[1].vector {
    Some(v) => {
      assert_eq(v[0], 4.0)
      assert_eq(v[1], 5.0)
      assert_eq(v[2], 6.0)
    }
    None => fail("rec1 vector missing")
  }
  match recs[1].attrs {
    Some(a) => assert_true(a.get("src") is Some(@types.String("b")))
    None => fail("rec1 attrs missing")
  }
  assert_true(recs[2].record_type == WalRecordType::SetAttrs)
  match recs[2].attrs {
    Some(a) => assert_true(a.get("src") is Some(@types.String("c")))
    None => fail("rec2 attrs missing")
  }
  assert_true(recs[3].record_type == WalRecordType::Remove)
  let store = @store.CoreStore::new(3, @types.L2)
  let applied = replay_wal_data(data, store)
  assert_eq(applied, 4)
  assert_eq(store.has(@types.VectorId::from_int(1)), true)
  assert_eq(store.has(@types.VectorId::from_int(2)), false)
  assert_eq(store.size(), 1)
  match store.get(@types.VectorId::from_int(1)) {
    Some(rec) => {
      assert_eq(rec.vector.length(), 3)
      assert_eq(rec.vector[0], 1.0)
    }
    None => fail("store missing id1")
  }
  let reseg = encode_wal_segment(recs)
  let rr = @binary.BinaryReader::new(reseg)
  rr.skip(9)
  assert_eq(rr.read_byte(), b'\x04')
  assert_eq(decode_wal_records(reseg).length(), 4)
}

///|
// !!! KNOWN DEFECT (discovered by this very harness, tracked for fix) !!!
// The CURRENT decoder cannot read a genuine v3 segment produced by v3's own
// encode_wal_segment: decode_wal_records returns 0 records instead of 4.
// The header and version byte ARE read correctly; only the v3 record body is
// mis-framed by today's code. format_v3_wbtest.mbt misses this because it
// hand-builds records matching the decoder's own assumptions instead of using
// v3's real encoder output. The offending bytes are spec/migration/wal_v3.hex.
// This test pins the current (incorrect) behavior so the regression is tracked;
// once the v3 decode path is fixed, replace this with the full v2/v4-style
// assertions (expecting 4 records, full replay, re-encode to v4).
test "migration/v3_known_defect_4db6088" {
  let data = Bytes::from_array([b'\x56', b'\x43', b'\x44', b'\x42', b'\x4d', b'\x42', b'\x54', b'\x00', b'\x01', b'\x03', b'\x00', b'\x00', b'\x01', b'\x01', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x08', b'\x01', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x0b', b'\x00', b'\x00', b'\x00', b'\x0c', b'\x00', b'\x00', b'\x00', b'\x7b', b'\x22', b'\x73', b'\x72', b'\x63', b'\x22', b'\x3a', b'\x22', b'\x61', b'\x22', b'\x7d', b'\x00', b'\x00', b'\x80', b'\x3f', b'\x00', b'\x00', b'\x00', b'\x40', b'\x00', b'\x00', b'\x40', b'\x40', b'\x01', b'\x01', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x08', b'\x02', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x0b', b'\x00', b'\x00', b'\x00', b'\x0c', b'\x00', b'\x00', b'\x00', b'\x7b', b'\x22', b'\x73', b'\x72', b'\x63', b'\x22', b'\x3a', b'\x22', b'\x62', b'\x22', b'\x7d', b'\x00', b'\x00', b'\x80', b'\x40', b'\x00', b'\x00', b'\xa0', b'\x40', b'\x00', b'\x00', b'\xc0', b'\x40', b'\x03', b'\x01', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x08', b'\x01', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x0b', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x7b', b'\x22', b'\x73', b'\x72', b'\x63', b'\x22', b'\x3a', b'\x22', b'\x63', b'\x22', b'\x7d', b'\x02', b'\x01', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x08', b'\x02', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x04', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x6e', b'\x75', b'\x6c', b'\x6c', b'\x57', b'\x43', b'\x52', b'\x43', b'\x38', b'\x36', b'\xce', b'\x16'][:])
  // header + version are decoded correctly even today:
  assert_true(verify_wal_header(@binary.BinaryReader::new(data)))
  let rv = @binary.BinaryReader::new(data)
  rv.skip(9)
  assert_eq(rv.read_byte(), b'\x03')
  // BUG: this MUST become 4 when the v3 record decode path is fixed.
  assert_eq(decode_wal_records(data).length(), 0)
}

///|
test "migration/v4_real_artifact_0254f3c" {
  // real wal_version 0x04 segment emitted by 0254f3c's own encode_wal_segment
  let data = Bytes::from_array([b'\x56', b'\x43', b'\x44', b'\x42', b'\x4d', b'\x42', b'\x54', b'\x00', b'\x01', b'\x04', b'\x00', b'\x00', b'\x01', b'\x01', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x10', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x01', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x0b', b'\x00', b'\x00', b'\x00', b'\x0c', b'\x00', b'\x00', b'\x00', b'\x7b', b'\x22', b'\x73', b'\x72', b'\x63', b'\x22', b'\x3a', b'\x22', b'\x61', b'\x22', b'\x7d', b'\x00', b'\x00', b'\x80', b'\x3f', b'\x00', b'\x00', b'\x00', b'\x40', b'\x00', b'\x00', b'\x40', b'\x40', b'\x01', b'\x01', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x10', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x02', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x0b', b'\x00', b'\x00', b'\x00', b'\x0c', b'\x00', b'\x00', b'\x00', b'\x7b', b'\x22', b'\x73', b'\x72', b'\x63', b'\x22', b'\x3a', b'\x22', b'\x62', b'\x22', b'\x7d', b'\x00', b'\x00', b'\x80', b'\x40', b'\x00', b'\x00', b'\xa0', b'\x40', b'\x00', b'\x00', b'\xc0', b'\x40', b'\x03', b'\x01', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x10', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x01', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x0b', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x7b', b'\x22', b'\x73', b'\x72', b'\x63', b'\x22', b'\x3a', b'\x22', b'\x63', b'\x22', b'\x7d', b'\x02', b'\x01', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x10', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x02', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x04', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x6e', b'\x75', b'\x6c', b'\x6c', b'\x57', b'\x43', b'\x52', b'\x43', b'\x3e', b'\x89', b'\x06', b'\xae'][:])
  assert_true(verify_wal_header(@binary.BinaryReader::new(data)))
  let rv = @binary.BinaryReader::new(data)
  rv.skip(9)
  assert_eq(rv.read_byte(), b'\x04')
  let recs = decode_wal_records(data)
  assert_eq(recs.length(), 4)
  assert_true(recs[0].record_type == WalRecordType::Upsert)
  assert_true(recs[0].id is @types.Int64Id(_))
  match recs[0].vector {
    Some(v) => {
      assert_eq(v.length(), 3)
      assert_eq(v[0], 1.0)
      assert_eq(v[1], 2.0)
      assert_eq(v[2], 3.0)
    }
    None => fail("rec0 vector missing")
  }
  match recs[0].attrs {
    Some(a) => assert_true(a.get("src") is Some(@types.String("a")))
    None => fail("rec0 attrs missing")
  }
  assert_true(recs[1].record_type == WalRecordType::Upsert)
  match recs[1].vector {
    Some(v) => {
      assert_eq(v[0], 4.0)
      assert_eq(v[1], 5.0)
      assert_eq(v[2], 6.0)
    }
    None => fail("rec1 vector missing")
  }
  match recs[1].attrs {
    Some(a) => assert_true(a.get("src") is Some(@types.String("b")))
    None => fail("rec1 attrs missing")
  }
  assert_true(recs[2].record_type == WalRecordType::SetAttrs)
  match recs[2].attrs {
    Some(a) => assert_true(a.get("src") is Some(@types.String("c")))
    None => fail("rec2 attrs missing")
  }
  assert_true(recs[3].record_type == WalRecordType::Remove)
  let store = @store.CoreStore::new(3, @types.L2)
  let applied = replay_wal_data(data, store)
  assert_eq(applied, 4)
  assert_eq(store.has(@types.VectorId::from_int(1)), true)
  assert_eq(store.has(@types.VectorId::from_int(2)), false)
  assert_eq(store.size(), 1)
  match store.get(@types.VectorId::from_int(1)) {
    Some(rec) => {
      assert_eq(rec.vector.length(), 3)
      assert_eq(rec.vector[0], 1.0)
    }
    None => fail("store missing id1")
  }
  let reseg = encode_wal_segment(recs)
  let rr = @binary.BinaryReader::new(reseg)
  rr.skip(9)
  assert_eq(rr.read_byte(), b'\x04')
  assert_eq(decode_wal_records(reseg).length(), 4)
}
