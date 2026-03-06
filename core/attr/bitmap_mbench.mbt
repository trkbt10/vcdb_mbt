///|
/// Benchmark: BitmapAttrIndex set_attrs
test "bench/bitmap_set_attrs" (b : @bench.T) {
  b.bench(fn() {
    let index = BitmapAttrIndex::new()
    for i in 0..<100 {
      let attrs = @types.empty_attrs()
      attrs.set(
        "status",
        @types.String(if i % 2 == 0 { "active" } else { "inactive" }),
      )
      attrs.set("region", @types.String("region_" + (i % 5).to_string()))
      index.set_attrs(@types.VectorId::from_int(i), attrs)
    }
    b.keep(index.size())
  })
}

///|
/// Benchmark: BitmapAttrIndex eq lookup
test "bench/bitmap_eq_lookup" (b : @bench.T) {
  let index = BitmapAttrIndex::new()
  for i in 0..<1000 {
    let attrs = @types.empty_attrs()
    attrs.set(
      "status",
      @types.String(if i % 2 == 0 { "active" } else { "inactive" }),
    )
    index.set_attrs(@types.VectorId::from_int(i), attrs)
  }
  b.bench(fn() { b.keep(index.eq("status", @types.String("active")).length()) })
}
