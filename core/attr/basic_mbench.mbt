///|
/// Benchmark: BasicAttrIndex set_attrs (5 attrs)
test "bench/basic_set_attrs_5" (b : @bench.T) {
  let attrs = @types.empty_attrs()
  attrs.set("name", @types.String("test"))
  attrs.set("score", @types.Float(0.95))
  attrs.set("count", @types.Int(42L))
  attrs.set("active", @types.Bool(true))
  attrs.set("tag", @types.String("benchmark"))
  b.bench(fn() {
    let index = BasicAttrIndex::new()
    for i in 0..<100 {
      index.set_attrs(@types.VectorId::from_int(i), attrs)
    }
    b.keep(index.size())
  })
}

///|
/// Benchmark: BasicAttrIndex get_attrs
test "bench/basic_get_attrs" (b : @bench.T) {
  let index = BasicAttrIndex::new()
  let attrs = @types.empty_attrs()
  attrs.set("name", @types.String("test"))
  for i in 0..<1000 {
    index.set_attrs(@types.VectorId::from_int(i), attrs)
  }
  let id = @types.VectorId::from_int(500)
  b.bench(fn() { b.keep(index.get_attrs(id) is Some(_)) })
}

///|
/// Benchmark: BasicAttrIndex equality lookup
test "bench/basic_eq_lookup" (b : @bench.T) {
  let index = BasicAttrIndex::new()
  for i in 0..<1000 {
    let attrs = @types.empty_attrs()
    attrs.set("category", @types.String("cat_" + (i % 100).to_string()))
    index.set_attrs(@types.VectorId::from_int(i), attrs)
  }
  b.bench(fn() {
    b.keep(index.eq("category", @types.String("cat_50")).length())
  })
}

///|
/// Benchmark: BasicAttrIndex exists lookup
test "bench/basic_exists_lookup" (b : @bench.T) {
  let index = BasicAttrIndex::new()
  for i in 0..<1000 {
    let attrs = @types.empty_attrs()
    attrs.set("name", @types.String("test_" + i.to_string()))
    if i % 2 == 0 {
      attrs.set("optional", @types.Int(i.to_int64()))
    }
    index.set_attrs(@types.VectorId::from_int(i), attrs)
  }
  b.bench(fn() { b.keep(index.exists("optional").length()) })
}

///|
/// Benchmark: BasicAttrIndex range query
test "bench/basic_range_query" (b : @bench.T) {
  let index = BasicAttrIndex::new()
  for i in 0..<1000 {
    let attrs = @types.empty_attrs()
    attrs.set("score", @types.Float(i.to_double() / 1000.0))
    index.set_attrs(@types.VectorId::from_int(i), attrs)
  }
  let range = @types.NumericRange::between(0.3, 0.7)
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
  let attrs = @types.empty_attrs()
  attrs.set("name", @types.String("test"))
  attrs.set("score", @types.Float(0.5))
  b.bench(fn() {
    let index = BasicAttrIndex::new()
    for i in 0..<100 {
      index.set_attrs(@types.VectorId::from_int(i), attrs)
    }
    for i in 0..<100 {
      index.remove_id(@types.VectorId::from_int(i))
    }
    b.keep(index.size())
  })
}
