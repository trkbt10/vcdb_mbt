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
  inspect(@types.Bytes16::from_uuid_string("not-a-uuid"), content="None")
  inspect(@types.Bytes16::from_uuid_string(""), content="None")
  inspect(
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
  inspect(m.get(a), content="Some(10)")
  inspect(m.get(b), content="Some(20)")
  inspect(m.get(@types.Int64Id(3L)), content="None")
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
  inspect(m.get(uuid), content="Some(100)")
  inspect(m.get(zero), content="Some(200)")
}

///|
test "vector_id/compare_int64id_before_bytes16id" {
  // Int64Id sorts before Bytes16Id (cross-type ordering)
  let i = @types.Int64Id(9999999999L)
  let b = @types.Bytes16Id(sample_uuid_for_types())
  inspect(i.compare(b) < 0, content="true")
  inspect(b.compare(i) > 0, content="true")
}
