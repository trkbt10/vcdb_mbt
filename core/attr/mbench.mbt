///|
/// Benchmark: BasicAttrIndex set_attrs (5 attrs)
test "bench/basic_set_attrs_5" (b : @bench.T) {
  let attrs = @core.empty_attrs()
  attrs.set("name", @core.String("test"))
  attrs.set("score", @core.Float(0.95))
  attrs.set("count", @core.Int(42L))
  attrs.set("active", @core.Bool(true))
  attrs.set("tag", @core.String("benchmark"))
  b.bench(fn() {
    let index = BasicAttrIndex::new()
    for i in 0..<100 {
      index.set_attrs(@core.VectorId::from_int(i), attrs)
    }
    b.keep(index.size())
  })
}

///|
/// Benchmark: BasicAttrIndex get_attrs
test "bench/basic_get_attrs" (b : @bench.T) {
  let index = BasicAttrIndex::new()
  let attrs = @core.empty_attrs()
  attrs.set("name", @core.String("test"))
  for i in 0..<1000 {
    index.set_attrs(@core.VectorId::from_int(i), attrs)
  }
  let id = @core.VectorId::from_int(500)
  b.bench(fn() { b.keep(index.get_attrs(id) is Some(_)) })
}

///|
/// Benchmark: BasicAttrIndex equality lookup (high cardinality)
test "bench/basic_eq_lookup" (b : @bench.T) {
  let index = BasicAttrIndex::new()
  for i in 0..<1000 {
    let attrs = @core.empty_attrs()
    attrs.set("category", @core.String("cat_" + (i % 100).to_string()))
    index.set_attrs(@core.VectorId::from_int(i), attrs)
  }
  b.bench(fn() { b.keep(index.eq("category", @core.String("cat_50")).length()) })
}

///|
/// Benchmark: BasicAttrIndex exists lookup
test "bench/basic_exists_lookup" (b : @bench.T) {
  let index = BasicAttrIndex::new()
  for i in 0..<1000 {
    let attrs = @core.empty_attrs()
    attrs.set("name", @core.String("test_" + i.to_string()))
    if i % 2 == 0 {
      attrs.set("optional", @core.Int(i.to_int64()))
    }
    index.set_attrs(@core.VectorId::from_int(i), attrs)
  }
  b.bench(fn() { b.keep(index.exists("optional").length()) })
}

///|
/// Benchmark: BasicAttrIndex range query
test "bench/basic_range_query" (b : @bench.T) {
  let index = BasicAttrIndex::new()
  for i in 0..<1000 {
    let attrs = @core.empty_attrs()
    attrs.set("score", @core.Float(i.to_double() / 1000.0))
    index.set_attrs(@core.VectorId::from_int(i), attrs)
  }
  let range = @core.NumericRange::between(0.3, 0.7)
  b.bench(fn() {
    match index.range("score", range) {
      Some(ids) => b.keep(ids.length())
      None => b.keep(0)
    }
  })
}

///|
/// Benchmark: BasicAttrIndex remove_id
test "bench/basic_remove_id" (b : @bench.T) {
  let attrs = @core.empty_attrs()
  attrs.set("name", @core.String("test"))
  attrs.set("score", @core.Float(0.5))
  b.bench(fn() {
    let index = BasicAttrIndex::new()
    for i in 0..<100 {
      index.set_attrs(@core.VectorId::from_int(i), attrs)
    }
    for i in 0..<100 {
      index.remove_id(@core.VectorId::from_int(i))
    }
    b.keep(index.size())
  })
}

///|
/// Benchmark: BitmapAttrIndex set_attrs (low cardinality)
test "bench/bitmap_set_attrs" (b : @bench.T) {
  b.bench(fn() {
    let index = BitmapAttrIndex::new()
    for i in 0..<100 {
      let attrs = @core.empty_attrs()
      attrs.set("status", @core.String(if i % 2 == 0 { "active" } else { "inactive" }))
      attrs.set("region", @core.String("region_" + (i % 5).to_string()))
      index.set_attrs(@core.VectorId::from_int(i), attrs)
    }
    b.keep(index.size())
  })
}

///|
/// Benchmark: BitmapAttrIndex eq lookup (low cardinality)
test "bench/bitmap_eq_lookup" (b : @bench.T) {
  let index = BitmapAttrIndex::new()
  for i in 0..<1000 {
    let attrs = @core.empty_attrs()
    attrs.set("status", @core.String(if i % 2 == 0 { "active" } else { "inactive" }))
    index.set_attrs(@core.VectorId::from_int(i), attrs)
  }
  b.bench(fn() { b.keep(index.eq("status", @core.String("active")).length()) })
}

///|
/// Benchmark: attr_value_to_key conversion
test "bench/attr_value_to_key" (b : @bench.T) {
  let values : Array[@core.AttrValue] = [
    @core.String("test"),
    @core.Int(42L),
    @core.Float(3.14),
    @core.Bool(true),
    @core.Null,
  ]
  b.bench(fn() {
    let mut total = 0
    for v in values {
      total = total + attr_value_to_key(v).length()
    }
    b.keep(total)
  })
}
