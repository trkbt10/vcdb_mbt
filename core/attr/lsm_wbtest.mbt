///|
/// LSMAttrIndex memtable operations
test "attr/lsm_memtable" {
  let index = LSMAttrIndex::new()
  let attrs = @types.empty_attrs()
  attrs.set("key", @types.String("value"))
  index.set_attrs(@types.VectorId::from_int(1), attrs)
  let result = index.eq("key", @types.String("value"))
  inspect(result.length(), content="1")
  inspect(index.memtable_size() > 0, content="true")
}

///|
/// LSMAttrIndex remove_id
test "attr/lsm_remove_id" {
  let index = LSMAttrIndex::new()
  let id1 = @types.VectorId::from_int(1)
  let id2 = @types.VectorId::from_int(2)
  let attrs1 = @types.empty_attrs()
  attrs1.set("tag", @types.String("test"))
  let attrs2 = @types.empty_attrs()
  attrs2.set("tag", @types.String("test"))
  index.set_attrs(id1, attrs1)
  index.set_attrs(id2, attrs2)
  inspect(index.eq("tag", @types.String("test")).length(), content="2")
  index.remove_id(id1)
  inspect(index.eq("tag", @types.String("test")).length(), content="1")
}

///|
/// LSMAttrIndex exists query
test "lsm/exists" {
  let index = LSMAttrIndex::new()
  let attrs = @types.empty_attrs()
  attrs.set("email", @types.String("test@test.com"))
  index.set_attrs(@types.VectorId::from_int(1), attrs)
  inspect(index.exists("email").length(), content="1")
  inspect(index.exists("missing").length(), content="0")
}

///|
/// LSMAttrIndex range query
test "lsm/range" {
  let index = LSMAttrIndex::new()
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
/// LSMAttrIndex size
test "lsm/size" {
  let index = LSMAttrIndex::new()
  inspect(index.size(), content="0")
  let attrs = @types.empty_attrs()
  attrs.set("key", @types.String("value"))
  index.set_attrs(@types.VectorId::from_int(1), attrs)
  index.set_attrs(@types.VectorId::from_int(2), attrs)
  inspect(index.size(), content="2")
}

///|
/// LSMAttrIndex should_flush
test "lsm/should_flush" {
  let index = LSMAttrIndex::new(flush_threshold=2)
  inspect(index.should_flush(), content="false")
  let attrs1 = @types.empty_attrs()
  attrs1.set("key", @types.String("value1"))
  index.set_attrs(@types.VectorId::from_int(1), attrs1)
  let attrs2 = @types.empty_attrs()
  attrs2.set("key", @types.String("value2"))
  index.set_attrs(@types.VectorId::from_int(2), attrs2)
  inspect(index.memtable_size() >= 2, content="true")
}

///|
/// LSMAttrIndex clear_memtable
test "lsm/clear_memtable" {
  let index = LSMAttrIndex::new()
  let attrs = @types.empty_attrs()
  attrs.set("key", @types.String("value"))
  index.set_attrs(@types.VectorId::from_int(1), attrs)
  inspect(index.memtable_size() > 0, content="true")
  index.clear_memtable()
  inspect(index.memtable_size(), content="0")
  inspect(index.size(), content="1")
  inspect(
    index.get_attrs(@types.VectorId::from_int(1)) is Some(_),
    content="true",
  )
}

///|
/// LSMAttrIndex get_attrs
test "lsm/get_attrs" {
  let index = LSMAttrIndex::new()
  inspect(index.get_attrs(@types.VectorId::from_int(1)) is None, content="true")
  let attrs = @types.empty_attrs()
  attrs.set("name", @types.String("test"))
  attrs.set("count", @types.Int(42L))
  index.set_attrs(@types.VectorId::from_int(1), attrs)
  match index.get_attrs(@types.VectorId::from_int(1)) {
    Some(a) =>
      match a.get("name") {
        Some(@types.String(s)) => inspect(s, content="test")
        _ => inspect(false, content="true")
      }
    None => inspect(false, content="true")
  }
}

///|
/// LSMAttrIndex update_attrs replaces old values
test "lsm/update_attrs" {
  let index = LSMAttrIndex::new()
  let id = @types.VectorId::from_int(1)
  let attrs1 = @types.empty_attrs()
  attrs1.set("status", @types.String("old"))
  index.set_attrs(id, attrs1)
  inspect(index.eq("status", @types.String("old")).length(), content="1")
  let attrs2 = @types.empty_attrs()
  attrs2.set("status", @types.String("new"))
  index.set_attrs(id, attrs2)
  inspect(index.eq("status", @types.String("old")).length(), content="0")
  inspect(index.eq("status", @types.String("new")).length(), content="1")
}

///|
/// LSMAttrIndex handles Unicode attribute keys
test "lsm/unicode_attr_keys" {
  let index = LSMAttrIndex::new()
  let id1 = @types.VectorId::from_int(1)
  let id2 = @types.VectorId::from_int(2)
  let attrs1 = @types.empty_attrs()
  attrs1.set("name", @types.Bool(true))
  let attrs2 = @types.empty_attrs()
  attrs2.set("名前", @types.Bool(true))
  index.set_attrs(id1, attrs1)
  index.set_attrs(id2, attrs2)
  let r1 = index.eq("name", @types.Bool(true))
  inspect(r1.length(), content="1")
  let r2 = index.eq("名前", @types.Bool(true))
  inspect(r2.length(), content="1")
  let e1 = index.exists("name")
  inspect(e1.length(), content="1")
  let e2 = index.exists("名前")
  inspect(e2.length(), content="1")
}

///|
/// LSMAttrIndex stores a defensive copy of attrs
test "lsm/attrs_defensive_copy" {
  let index = LSMAttrIndex::new()
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
}
