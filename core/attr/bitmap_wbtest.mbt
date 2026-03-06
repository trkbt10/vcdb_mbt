///|
/// BitmapAttrIndex equality
test "attr/bitmap_eq" {
  let index = BitmapAttrIndex::new()
  let attrs1 = @types.empty_attrs()
  attrs1.set("status", @types.String("active"))
  let attrs2 = @types.empty_attrs()
  attrs2.set("status", @types.String("inactive"))
  index.set_attrs(@types.VectorId::from_int(1), attrs1)
  index.set_attrs(@types.VectorId::from_int(2), attrs2)
  let active = index.eq("status", @types.String("active"))
  inspect(active.length(), content="1")
}

///|
/// BitmapAttrIndex remove_id
test "attr/bitmap_remove_id" {
  let index = BitmapAttrIndex::new()
  let id1 = @types.VectorId::from_int(1)
  let id2 = @types.VectorId::from_int(2)
  let attrs1 = @types.empty_attrs()
  attrs1.set("status", @types.String("active"))
  let attrs2 = @types.empty_attrs()
  attrs2.set("status", @types.String("active"))
  index.set_attrs(id1, attrs1)
  index.set_attrs(id2, attrs2)
  inspect(index.eq("status", @types.String("active")).length(), content="2")
  index.remove_id(id1)
  inspect(index.eq("status", @types.String("active")).length(), content="1")
}

///|
/// BitmapAttrIndex exists query
test "bitmap/exists" {
  let index = BitmapAttrIndex::new()
  let attrs = @types.empty_attrs()
  attrs.set("active", @types.Bool(true))
  index.set_attrs(@types.VectorId::from_int(1), attrs)
  inspect(index.exists("active").length(), content="1")
  inspect(index.exists("missing").length(), content="0")
}

///|
/// BitmapAttrIndex get_attrs
test "bitmap/get_attrs" {
  let index = BitmapAttrIndex::new()
  let attrs = @types.empty_attrs()
  attrs.set("tag", @types.String("test"))
  index.set_attrs(@types.VectorId::from_int(1), attrs)
  let retrieved = index.get_attrs(@types.VectorId::from_int(1))
  inspect(retrieved is Some(_), content="true")
  inspect(
    index.get_attrs(@types.VectorId::from_int(99)) is None,
    content="true",
  )
}

///|
/// BitmapAttrIndex range always returns None
test "bitmap/range" {
  let index = BitmapAttrIndex::new()
  let range = @types.NumericRange::between(0.0, 100.0)
  let result = index.range("any", range)
  inspect(result is None, content="true")
}

///|
/// BitmapAttrIndex stores a defensive copy of attrs
test "bitmap/attrs_defensive_copy" {
  let index = BitmapAttrIndex::new()
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
