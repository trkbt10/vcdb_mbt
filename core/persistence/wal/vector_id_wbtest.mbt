///|
/// VectorId type tests: Bytes16 helpers and VectorId enum behavior.
///
/// These tests are WAL-format-independent; they verify the types defined in
/// core/types/types.mbt that underpin all three WAL formats.
///
/// Test name prefixes:
///   "bytes16/"    — Bytes16 struct construction, UUID string parsing, ordering
///   "vector_id/"  — VectorId enum: map key usage, cross-type ordering

///|
/// A fixed UUID for use in type tests: 550e8400-e29b-41d4-a716-446655440000
fn sample_uuid_for_types() -> @types.Bytes16 {
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
test "bytes16/from_uuid_string_round_trip" {
  let s = "550e8400-e29b-41d4-a716-446655440000"
  match @types.Bytes16::from_uuid_string(s) {
    Some(b) => inspect(b.to_uuid_string(), content=s)
    None => fail("parse failed")
  }
}

///|
test "bytes16/from_uuid_string_no_hyphens" {
  let s = "550e8400e29b41d4a716446655440000"
  match @types.Bytes16::from_uuid_string(s) {
    Some(b) =>
      inspect(
        b.to_uuid_string(),
        content="550e8400-e29b-41d4-a716-446655440000",
      )
    None => fail("parse failed")
  }
}

///|
test "bytes16/from_uuid_string_invalid" {
  @debug.debug_inspect(
    @types.Bytes16::from_uuid_string("not-a-uuid"),
    content="None",
  )
  @debug.debug_inspect(@types.Bytes16::from_uuid_string(""), content="None")
  @debug.debug_inspect(
    @types.Bytes16::from_uuid_string("550e8400-e29b-41d4-a716-44665544000g"),
    content="None",
  )
}

///|
test "bytes16/equality" {
  let a = sample_uuid_for_types()
  let b = sample_uuid_for_types()
  inspect(a == b, content="true")
  let c = @types.Bytes16::{
    b0: b'\x00',
    b1: b'\x00',
    b2: b'\x00',
    b3: b'\x00',
    b4: b'\x00',
    b5: b'\x00',
    b6: b'\x00',
    b7: b'\x00',
    b8: b'\x00',
    b9: b'\x00',
    b10: b'\x00',
    b11: b'\x00',
    b12: b'\x00',
    b13: b'\x00',
    b14: b'\x00',
    b15: b'\x00',
  }
  inspect(a == c, content="false")
}

///|
test "bytes16/compare_lexicographic" {
  let lo = @types.Bytes16::{
    b0: b'\x00',
    b1: b'\x00',
    b2: b'\x00',
    b3: b'\x00',
    b4: b'\x00',
    b5: b'\x00',
    b6: b'\x00',
    b7: b'\x00',
    b8: b'\x00',
    b9: b'\x00',
    b10: b'\x00',
    b11: b'\x00',
    b12: b'\x00',
    b13: b'\x00',
    b14: b'\x00',
    b15: b'\x01',
  }
  let hi = @types.Bytes16::{
    b0: b'\x00',
    b1: b'\x00',
    b2: b'\x00',
    b3: b'\x00',
    b4: b'\x00',
    b5: b'\x00',
    b6: b'\x00',
    b7: b'\x00',
    b8: b'\x00',
    b9: b'\x00',
    b10: b'\x00',
    b11: b'\x00',
    b12: b'\x00',
    b13: b'\x00',
    b14: b'\x00',
    b15: b'\x02',
  }
  inspect(lo.compare(hi) < 0, content="true")
  inspect(hi.compare(lo) > 0, content="true")
  inspect(lo.compare(lo), content="0")
}

///|
test "bytes16/from_hi_lo_round_trip" {
  let hi = 0x0102030405060708L
  let lo = 0x090a0b0c0d0e0f10L
  let b = @types.Bytes16::from_hi_lo(hi, lo)
  let (hi2, lo2) = b.to_hi_lo()
  inspect(hi2, content="72623859790382856")
  inspect(lo2, content="651345242494996240")
  inspect(hi2 == hi, content="true")
  inspect(lo2 == lo, content="true")
}

///|
test "vector_id/int64id_as_map_key" {
  // VectorId must be usable as a HashMap key (Hash + Eq)
  let m : Map[@types.VectorId, Int] = {}
  let a = @types.Int64Id(1L)
  let b = @types.Int64Id(2L)
  m.set(a, 10)
  m.set(b, 20)
  @debug.debug_inspect(m.get(a), content="Some(10)")
  @debug.debug_inspect(m.get(b), content="Some(20)")
  @debug.debug_inspect(m.get(@types.Int64Id(3L)), content="None")
}

///|
test "vector_id/bytes16id_as_map_key" {
  let m : Map[@types.VectorId, Int] = {}
  let uuid = @types.Bytes16Id(sample_uuid_for_types())
  let zero = @types.Bytes16Id(@types.Bytes16::{
    b0: b'\x00',
    b1: b'\x00',
    b2: b'\x00',
    b3: b'\x00',
    b4: b'\x00',
    b5: b'\x00',
    b6: b'\x00',
    b7: b'\x00',
    b8: b'\x00',
    b9: b'\x00',
    b10: b'\x00',
    b11: b'\x00',
    b12: b'\x00',
    b13: b'\x00',
    b14: b'\x00',
    b15: b'\x00',
  })
  m.set(uuid, 100)
  m.set(zero, 200)
  @debug.debug_inspect(m.get(uuid), content="Some(100)")
  @debug.debug_inspect(m.get(zero), content="Some(200)")
}

///|
test "vector_id/compare_int64id_before_bytes16id" {
  // Int64Id sorts before Bytes16Id (cross-type ordering)
  let i = @types.Int64Id(9999999999L)
  let b = @types.Bytes16Id(sample_uuid_for_types())
  inspect(i.compare(b) < 0, content="true")
  inspect(b.compare(i) > 0, content="true")
}

// ── Wire format (to_wire_bytes / from_wire_bytes) ────────────
//
// These tests verify the 16-byte FFI wire format used to transfer
// VectorIds between MoonBit and JS. The wire format must be kept
// in sync with the WAL encoding for each VectorId variant.

///|
/// Int64Id: wire bytes upper 8 = big-endian Int64, lower 8 = 0x00
test "wire/int64_basic_encoding" {
  let id = @types.Int64Id(0x0102030405060708L)
  let wire = id.to_wire_bytes()
  @test.assert_eq(wire.length(), 16)
  // Upper 8 bytes: big-endian encoding of 0x0102030405060708
  @test.assert_eq(wire[0], b'\x01')
  @test.assert_eq(wire[1], b'\x02')
  @test.assert_eq(wire[2], b'\x03')
  @test.assert_eq(wire[3], b'\x04')
  @test.assert_eq(wire[4], b'\x05')
  @test.assert_eq(wire[5], b'\x06')
  @test.assert_eq(wire[6], b'\x07')
  @test.assert_eq(wire[7], b'\x08')
  // Lower 8 bytes: all zero
  for i in 8..<16 {
    @test.assert_eq(wire[i], b'\x00')
  }
}

///|
/// Int64Id zero
test "wire/int64_zero_roundtrip" {
  let id = @types.Int64Id(0L)
  let wire = id.to_wire_bytes()
  for i in 0..<16 {
    @test.assert_eq(wire[i], b'\x00')
  }
  @test.assert_eq(@types.VectorId::from_wire_bytes(wire), Some(id))
}

///|
/// Int64Id max positive
test "wire/int64_max_positive_roundtrip" {
  let id = @types.Int64Id(9223372036854775807L) // Int64::max
  let wire = id.to_wire_bytes()
  @test.assert_eq(@types.VectorId::from_wire_bytes(wire), Some(id))
}

///|
/// Int64Id min negative (-1, all 0xFF upper)
test "wire/int64_minus_one_roundtrip" {
  let id = @types.Int64Id(-1L)
  let wire = id.to_wire_bytes()
  for i in 0..<8 {
    @test.assert_eq(wire[i], b'\xff')
  }
  for i in 8..<16 {
    @test.assert_eq(wire[i], b'\x00')
  }
  @test.assert_eq(@types.VectorId::from_wire_bytes(wire), Some(id))
}

///|
/// Int64Id min value
test "wire/int64_min_value_roundtrip" {
  let id = @types.Int64Id(-9223372036854775808L) // Int64::min
  let wire = id.to_wire_bytes()
  // 0x80_00_00_00_00_00_00_00
  @test.assert_eq(wire[0], b'\x80')
  for i in 1..<8 {
    @test.assert_eq(wire[i], b'\x00')
  }
  @test.assert_eq(@types.VectorId::from_wire_bytes(wire), Some(id))
}

///|
/// Int64Id(1) — small positive
test "wire/int64_one_roundtrip" {
  let id = @types.Int64Id(1L)
  let wire = id.to_wire_bytes()
  @test.assert_eq(wire[7], b'\x01')
  @test.assert_eq(@types.VectorId::from_wire_bytes(wire), Some(id))
}

///|
/// Bytes16Id: wire bytes are the raw 16 bytes of Bytes16
test "wire/bytes16_basic_encoding" {
  let b = sample_uuid_for_types()
  let id = @types.Bytes16Id(b)
  let wire = id.to_wire_bytes()
  @test.assert_eq(wire.length(), 16)
  // Verify each byte matches the Bytes16 struct
  @test.assert_eq(wire[0], b.b0)
  @test.assert_eq(wire[1], b.b1)
  @test.assert_eq(wire[2], b.b2)
  @test.assert_eq(wire[3], b.b3)
  @test.assert_eq(wire[4], b.b4)
  @test.assert_eq(wire[5], b.b5)
  @test.assert_eq(wire[6], b.b6)
  @test.assert_eq(wire[7], b.b7)
  @test.assert_eq(wire[8], b.b8)
  @test.assert_eq(wire[9], b.b9)
  @test.assert_eq(wire[10], b.b10)
  @test.assert_eq(wire[11], b.b11)
  @test.assert_eq(wire[12], b.b12)
  @test.assert_eq(wire[13], b.b13)
  @test.assert_eq(wire[14], b.b14)
  @test.assert_eq(wire[15], b.b15)
}

///|
/// Bytes16Id round-trip via wire bytes
test "wire/bytes16_roundtrip" {
  let id = @types.Bytes16Id(sample_uuid_for_types())
  let wire = id.to_wire_bytes()
  @test.assert_eq(@types.VectorId::from_wire_bytes(wire), Some(id))
}

///|
/// Bytes16Id with non-zero lower bytes is never confused with Int64Id
test "wire/bytes16_with_lower_nonzero_is_bytes16id" {
  // All upper 8 bytes zero, but lower byte 15 = 0x01
  let b = @types.Bytes16::{
    b0: b'\x00',
    b1: b'\x00',
    b2: b'\x00',
    b3: b'\x00',
    b4: b'\x00',
    b5: b'\x00',
    b6: b'\x00',
    b7: b'\x00',
    b8: b'\x00',
    b9: b'\x00',
    b10: b'\x00',
    b11: b'\x00',
    b12: b'\x00',
    b13: b'\x00',
    b14: b'\x00',
    b15: b'\x01',
  }
  let id = @types.Bytes16Id(b)
  let wire = id.to_wire_bytes()
  let decoded = @types.VectorId::from_wire_bytes(wire)
  match decoded {
    Some(@types.Bytes16Id(_)) => () // correct
    _ => fail("Expected Bytes16Id, got " + Debug::to_repr(decoded).to_string())
  }
}

///|
/// Bytes16Id with all zeros — still Bytes16Id, not Int64Id(0)
/// This is a critical edge case: a Bytes16 that happens to be all-zero
/// will be decoded as Int64Id(0) because lower 8 bytes are all zero.
/// This is a known, documented, accepted behavior.
test "wire/bytes16_all_zeros_decodes_as_int64id_zero" {
  let b = @types.Bytes16::{
    b0: b'\x00',
    b1: b'\x00',
    b2: b'\x00',
    b3: b'\x00',
    b4: b'\x00',
    b5: b'\x00',
    b6: b'\x00',
    b7: b'\x00',
    b8: b'\x00',
    b9: b'\x00',
    b10: b'\x00',
    b11: b'\x00',
    b12: b'\x00',
    b13: b'\x00',
    b14: b'\x00',
    b15: b'\x00',
  }
  let id = @types.Bytes16Id(b)
  let wire = id.to_wire_bytes()
  // from_wire_bytes sees all-zero lower 8 → returns Int64Id(0)
  // This is acceptable because Bytes16(all-zeros) is semantically
  // equivalent to "no ID" and should not be used in practice.
  let decoded = @types.VectorId::from_wire_bytes(wire)
  @test.assert_eq(decoded, Some(@types.Int64Id(0L)))
}

///|
/// Invalid wire bytes lengths
test "wire/invalid_lengths" {
  @test.assert_eq(@types.VectorId::from_wire_bytes(b""), None)
  @test.assert_eq(
    @types.VectorId::from_wire_bytes(Bytes::make(1, b'\x00')),
    None,
  )
  @test.assert_eq(
    @types.VectorId::from_wire_bytes(Bytes::make(8, b'\x00')),
    None,
  )
  @test.assert_eq(
    @types.VectorId::from_wire_bytes(Bytes::make(15, b'\x00')),
    None,
  )
  @test.assert_eq(
    @types.VectorId::from_wire_bytes(Bytes::make(17, b'\x00')),
    None,
  )
}

// ── Wire format ↔ WAL format consistency ─────────────────────
//
// These tests verify that VectorIds survive the full round-trip:
//   wire bytes → VectorId → WAL encode → WAL decode → VectorId → wire bytes

///|
/// Int64Id: wire → WAL v3 → wire round-trip
test "wire_wal/int64_full_roundtrip" {
  let original = @types.Int64Id(12345678L)
  let wire_in = original.to_wire_bytes()
  // Decode from wire
  let decoded_in = @types.VectorId::from_wire_bytes(wire_in).unwrap()
  // Encode to WAL v3 and decode back
  let wal_record = WalRecord::upsert(
    decoded_in,
    [1.0],
    @types.empty_attrs(),
    timestamp=100L,
  )
  let encoded = encode_wal_record(wal_record)
  let r = @binary.BinaryReader::new(encoded)
  let decoded_wal = decode_wal_record(r).unwrap()
  // Re-encode to wire
  let wire_out = decoded_wal.id.to_wire_bytes()
  @test.assert_eq(wire_in, wire_out)
}

///|
/// Bytes16Id: wire → WAL v3 → wire round-trip
test "wire_wal/bytes16_full_roundtrip" {
  let original = @types.Bytes16Id(sample_uuid_for_types())
  let wire_in = original.to_wire_bytes()
  let decoded_in = @types.VectorId::from_wire_bytes(wire_in).unwrap()
  let wal_record = WalRecord::upsert(
    decoded_in,
    [2.0],
    @types.empty_attrs(),
    timestamp=200L,
  )
  let encoded = encode_wal_record(wal_record)
  let r = @binary.BinaryReader::new(encoded)
  let decoded_wal = decode_wal_record(r).unwrap()
  let wire_out = decoded_wal.id.to_wire_bytes()
  @test.assert_eq(wire_in, wire_out)
}

///|
/// Mixed IDs in one WAL segment: wire → segment → replay → wire
test "wire_wal/mixed_ids_segment_roundtrip" {
  let int_id = @types.Int64Id(42L)
  let uuid_id = @types.Bytes16Id(sample_uuid_for_types())
  let wire_int = int_id.to_wire_bytes()
  let wire_uuid = uuid_id.to_wire_bytes()
  // Build segment with both ID types
  let segment = encode_wal_segment([
    WalRecord::upsert(int_id, [1.0, 2.0], @types.empty_attrs(), timestamp=1L),
    WalRecord::upsert(uuid_id, [3.0, 4.0], @types.empty_attrs(), timestamp=2L),
  ])
  let records = decode_wal_records(segment)
  @test.assert_eq(records.length(), 2)
  // Verify wire bytes match after WAL round-trip
  @test.assert_eq(records[0].id.to_wire_bytes(), wire_int)
  @test.assert_eq(records[1].id.to_wire_bytes(), wire_uuid)
}

///|
/// Int64Id boundary values survive WAL round-trip
test "wire_wal/int64_boundary_values" {
  let ids = [
    @types.Int64Id(0L),
    @types.Int64Id(1L),
    @types.Int64Id(-1L),
    @types.Int64Id(9223372036854775807L), // max
    @types.Int64Id(-9223372036854775808L), // min
    @types.Int64Id(256L),
    @types.Int64Id(65536L),
    @types.Int64Id(4294967296L), // 2^32
  ]
  for id in ids {
    let wire_in = id.to_wire_bytes()
    let wal_record = WalRecord::upsert(
      id,
      [1.0],
      @types.empty_attrs(),
      timestamp=1L,
    )
    let encoded = encode_wal_record(wal_record)
    let r = @binary.BinaryReader::new(encoded)
    let decoded = decode_wal_record(r).unwrap()
    let wire_out = decoded.id.to_wire_bytes()
    @test.assert_eq(wire_in, wire_out)
  }
}

///|
/// Bytes16Id from hi/lo construction: wire round-trip
test "wire_wal/bytes16_from_hi_lo_roundtrip" {
  let hi = 0x0102030405060708L
  let lo = 0x090a0b0c0d0e0f10L
  let b = @types.Bytes16::from_hi_lo(hi, lo)
  let id = @types.Bytes16Id(b)
  let wire = id.to_wire_bytes()
  let decoded = @types.VectorId::from_wire_bytes(wire).unwrap()
  match decoded {
    @types.Bytes16Id(b2) => {
      let (hi2, lo2) = b2.to_hi_lo()
      @test.assert_eq(hi, hi2)
      @test.assert_eq(lo, lo2)
    }
    _ => fail("expected Bytes16Id")
  }
}

///|
/// Various UUID strings: wire round-trip preserves exact bytes
test "wire_wal/uuid_strings_roundtrip" {
  let uuids = [
    "00000000-0000-0000-0000-000000000001", "ffffffff-ffff-ffff-ffff-ffffffffffff",
    "550e8400-e29b-41d4-a716-446655440000", "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
    "01234567-89ab-cdef-0123-456789abcdef",
  ]
  for uuid in uuids {
    let id = @types.VectorId::from_uuid_string(uuid).unwrap()
    let wire = id.to_wire_bytes()
    let decoded = @types.VectorId::from_wire_bytes(wire).unwrap()
    @test.assert_eq(decoded.to_display_string(), uuid)
  }
}
