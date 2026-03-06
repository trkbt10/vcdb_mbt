///|
/// Benchmark: BPTreeAttrIndex set_attrs with many split points
test "bench/bptree_set_attrs_10k" (b : @bench.T) {
  b.bench(fn() {
    let index = BPTreeAttrIndex::new(order=32)
    for i in 0..<10000 {
      let attrs = @types.empty_attrs()
      attrs.set("score", @types.Int(i.to_int64()))
      attrs.set("bucket", @types.Int((i % 256).to_int64()))
      index.set_attrs(@types.VectorId::from_int(i), attrs)
    }
    b.keep(index.size())
  })
}

///|
/// Benchmark: BPTreeAttrIndex equality lookup after scaling
test "bench/bptree_eq_lookup_10k" (b : @bench.T) {
  let index = BPTreeAttrIndex::new(order=32)
  for i in 0..<10000 {
    let attrs = @types.empty_attrs()
    attrs.set("score", @types.Int(i.to_int64()))
    index.set_attrs(@types.VectorId::from_int(i), attrs)
  }
  b.bench(fn() { b.keep(index.eq("score", @types.Int(7777L)).length()) })
}

///|
/// Benchmark: BPTreeAttrIndex range query after scaling
test "bench/bptree_range_query_10k" (b : @bench.T) {
  let index = BPTreeAttrIndex::new(order=32)
  for i in 0..<10000 {
    let attrs = @types.empty_attrs()
    attrs.set("score", @types.Int(i.to_int64()))
    index.set_attrs(@types.VectorId::from_int(i), attrs)
  }
  let range = @types.NumericRange::between(3000.0, 6999.0)
  b.bench(fn() {
    match index.range("score", range) {
      Some(ids) => b.keep(ids.length())
      None => b.keep(0)
    }
  })
}
