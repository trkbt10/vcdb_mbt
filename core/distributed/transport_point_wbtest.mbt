///|
test "transport_point/jsonl_roundtrip_ascii" {
  let attrs = @types.empty_attrs()
  attrs.set("title", @types.String("hello world"))
  attrs.set("count", @types.Int(42L))
  let point = TransportPoint::{
    id: @types.VectorId::from_int64(123L),
    vector: [1.0, 2.0, 3.0],
    attrs,
  }
  let line = point.to_jsonl()
  let restored = TransportPoint::from_jsonl(line)
  assert_false(restored is None)
  let r = restored.unwrap()
  assert_eq(r.id, point.id)
  assert_eq(r.vector, point.vector)
  assert_eq(r.attrs.get("title"), Some(@types.String("hello world")))
  assert_eq(r.attrs.get("count"), Some(@types.Int(42L)))
}

///|
test "transport_point/jsonl_roundtrip_unicode" {
  let attrs = @types.empty_attrs()
  attrs.set(
    "title",
    @types.String("犬の空中散歩が可能なエアマットの作り方"),
  )
  attrs.set("category", @types.String("生活"))
  attrs.set("emoji", @types.String("🐕"))
  let point = TransportPoint::{
    id: @types.VectorId::from_int64(999L),
    vector: [0.5, -0.3, 0.8],
    attrs,
  }
  let line = point.to_jsonl()
  let restored = TransportPoint::from_jsonl(line)
  assert_false(restored is None)
  let r = restored.unwrap()
  assert_eq(r.id, point.id)
  assert_eq(r.vector, point.vector)
  assert_eq(
    r.attrs.get("title"),
    Some(
      @types.String("犬の空中散歩が可能なエアマットの作り方"),
    ),
  )
  assert_eq(r.attrs.get("category"), Some(@types.String("生活")))
  assert_eq(r.attrs.get("emoji"), Some(@types.String("🐕")))
}

///|
test "transport_point/jsonl_roundtrip_hi_lo_id" {
  let attrs = @types.empty_attrs()
  attrs.set("v", @types.String("test"))
  // ID with non-zero hi part
  let id = @types.VectorId::from_int64(0x0001000200030004L)
  let point = TransportPoint::{ id, vector: [1.0], attrs }
  let line = point.to_jsonl()
  let restored = TransportPoint::from_jsonl(line).unwrap()
  assert_eq(restored.id.to_int64(), 0x0001000200030004L)
}

///|
test "transport_point/from_jsonl_rejects_invalid" {
  assert_true(TransportPoint::from_jsonl("") is None)
  assert_true(TransportPoint::from_jsonl("{}") is None)
  assert_true(TransportPoint::from_jsonl("{\"id\":{}}") is None)
  assert_true(
    TransportPoint::from_jsonl("{\"id\":{\"hi\":0,\"lo\":0}}") is None,
  )
  // Missing vector
  assert_true(
    TransportPoint::from_jsonl("{\"id\":{\"hi\":0,\"lo\":1},\"payload\":{}}")
    is None,
  )
}

///|
test "transport_point/jsonl_empty_payload" {
  let point = TransportPoint::{
    id: @types.VectorId::from_int64(1L),
    vector: [1.0],
    attrs: @types.empty_attrs(),
  }
  let line = point.to_jsonl()
  let restored = TransportPoint::from_jsonl(line).unwrap()
  assert_eq(restored.attrs.size(), 0)
}
