///|
/// BasicAttrIndex equality queries
test "attr/basic_eq" {
  let index = BasicAttrIndex::new()
  let id1 = @types.VectorId::from_int(1)
  let id2 = @types.VectorId::from_int(2)
  let id3 = @types.VectorId::from_int(3)
  let attrs1 = @types.empty_attrs()
  attrs1.set("category", @types.String("A"))
  attrs1.set("score", @types.Int(100L))
  let attrs2 = @types.empty_attrs()
  attrs2.set("category", @types.String("B"))
  attrs2.set("score", @types.Int(200L))
  let attrs3 = @types.empty_attrs()
  attrs3.set("category", @types.String("A"))
  attrs3.set("score", @types.Int(150L))
  index.set_attrs(id1, attrs1)
  index.set_attrs(id2, attrs2)
  index.set_attrs(id3, attrs3)
  let result_a = index.eq("category", @types.String("A"))
  inspect(result_a.length(), content="2")
  let result_b = index.eq("category", @types.String("B"))
  inspect(result_b.length(), content="1")
  inspect(result_b[0], content="Int64Id(2)")
}

///|
/// BasicAttrIndex range queries
test "attr/basic_range" {
  let index = BasicAttrIndex::new()
  for i in 1..<=10 {
    let attrs = @types.empty_attrs()
    attrs.set("value", @types.Int(i.to_int64() * 10L))
    index.set_attrs(@types.VectorId::from_int(i), attrs)
  }
  let range = @types.NumericRange::between(30.0, 70.0)
  match index.range("value", range) {
    Some(ids) => inspect(ids.length(), content="5")
    None => inspect(false, content="true")
  }
}

///|
/// BasicAttrIndex exists queries
test "attr/basic_exists" {
  let index = BasicAttrIndex::new()
  let attrs1 = @types.empty_attrs()
  attrs1.set("name", @types.String("Alice"))
  let attrs2 = @types.empty_attrs()
  attrs2.set("age", @types.Int(30L))
  index.set_attrs(@types.VectorId::from_int(1), attrs1)
  index.set_attrs(@types.VectorId::from_int(2), attrs2)
  inspect(index.exists("name").length(), content="1")
  inspect(index.exists("age").length(), content="1")
}

///|
/// BasicAttrIndex remove_id
test "attr/basic_remove_id" {
  let index = BasicAttrIndex::new()
  let id1 = @types.VectorId::from_int(1)
  let id2 = @types.VectorId::from_int(2)
  let attrs1 = @types.empty_attrs()
  attrs1.set("category", @types.String("A"))
  attrs1.set("score", @types.Int(100L))
  let attrs2 = @types.empty_attrs()
  attrs2.set("category", @types.String("A"))
  attrs2.set("score", @types.Int(200L))
  index.set_attrs(id1, attrs1)
  index.set_attrs(id2, attrs2)
  inspect(index.eq("category", @types.String("A")).length(), content="2")
  index.remove_id(id1)
  inspect(index.eq("category", @types.String("A")).length(), content="1")
  inspect(index.exists("score").length(), content="1")
  inspect(index.get_attrs(id1) is None, content="true")
  inspect(index.get_attrs(id2) is Some(_), content="true")
}

///|
/// BasicAttrIndex size
test "basic/size" {
  let index = BasicAttrIndex::new()
  inspect(index.size(), content="0")
  index.set_attrs(@types.VectorId::from_int(1), @types.empty_attrs())
  index.set_attrs(@types.VectorId::from_int(2), @types.empty_attrs())
  inspect(index.size(), content="2")
}

///|
/// BasicAttrIndex float range queries
test "basic/range_float" {
  let index = BasicAttrIndex::new()
  for i in 1..<=10 {
    let attrs = @types.empty_attrs()
    attrs.set("price", @types.Float(i.to_double() * 1.5))
    index.set_attrs(@types.VectorId::from_int(i), attrs)
  }
  let range = @types.NumericRange::between(3.0, 9.0)
  match index.range("price", range) {
    Some(ids) => inspect(ids.length() >= 3, content="true")
    None => inspect(false, content="true")
  }
}

///|
/// BasicAttrIndex distinguishes attribute value types
test "basic/type_disambiguation" {
  let index = BasicAttrIndex::new()
  let id1 = @types.VectorId::from_int(1)
  let id2 = @types.VectorId::from_int(2)
  let id3 = @types.VectorId::from_int(3)
  let attrs1 = @types.empty_attrs()
  attrs1.set("val", @types.Int(1L))
  let attrs2 = @types.empty_attrs()
  attrs2.set("val", @types.Float(1.0))
  let attrs3 = @types.empty_attrs()
  attrs3.set("val", @types.String("1"))
  index.set_attrs(id1, attrs1)
  index.set_attrs(id2, attrs2)
  index.set_attrs(id3, attrs3)
  let result_int = index.eq("val", @types.Int(1L))
  inspect(result_int.length(), content="1")
  inspect(result_int[0], content="Int64Id(1)")
  let result_float = index.eq("val", @types.Float(1.0))
  inspect(result_float.length(), content="1")
  inspect(result_float[0], content="Int64Id(2)")
  let result_string = index.eq("val", @types.String("1"))
  inspect(result_string.length(), content="1")
  inspect(result_string[0], content="Int64Id(3)")
}

///|
/// BasicAttrIndex stores a defensive copy of attrs
test "basic/attrs_defensive_copy" {
  let index = BasicAttrIndex::new()
  let id = @types.VectorId::from_int(1)
  let attrs = @types.empty_attrs()
  attrs.set("tag", @types.String("A"))
  index.set_attrs(id, attrs)
  attrs.set("tag", @types.String("B"))
  match index.get_attrs(id) {
    None => inspect(false, content="true")
    Some(stored) =>
      match stored.get("tag") {
        Some(@types.String(s)) => inspect(s, content="A")
        _ => inspect(false, content="true")
      }
  }
  let results = index.eq("tag", @types.String("A"))
  inspect(results.length(), content="1")
}

///|
/// Bytes16Id works in BasicAttrIndex: set, get, eq, exists, remove, range
test "basic/bytes16id_full_operations" {
  let index = BasicAttrIndex::new()
  let uuid_id = @types.VectorId::from_uuid_string(
    "550e8400-e29b-41d4-a716-446655440000",
  ).unwrap()
  let int_id = @types.VectorId::from_int(1)
  let attrs_uuid = @types.empty_attrs()
  attrs_uuid.set("type", @types.String("product"))
  attrs_uuid.set("score", @types.Int(90L))
  let attrs_int = @types.empty_attrs()
  attrs_int.set("type", @types.String("product"))
  attrs_int.set("score", @types.Int(50L))
  index.set_attrs(uuid_id, attrs_uuid)
  index.set_attrs(int_id, attrs_int)
  // Size
  inspect(index.size(), content="2")
  // Get
  inspect(index.get_attrs(uuid_id) is Some(_), content="true")
  // Eq
  inspect(index.eq("type", @types.String("product")).length(), content="2")
  // Exists
  inspect(index.exists("score").length(), content="2")
  // Range
  match index.range("score", @types.NumericRange::between(80.0, 100.0)) {
    Some(ids) => inspect(ids.length(), content="1")
    None => inspect(false, content="true")
  }
  // Remove Bytes16Id
  index.remove_id(uuid_id)
  inspect(index.size(), content="1")
  inspect(index.eq("type", @types.String("product")).length(), content="1")
}
