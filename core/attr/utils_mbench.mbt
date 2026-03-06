///|
/// Benchmark: attr_value_to_key conversion
test "bench/attr_value_to_key" (b : @bench.T) {
  let values : Array[@types.AttrValue] = [
    @types.String("test"),
    @types.Int(42L),
    @types.Float(3.14),
    @types.Bool(true),
    @types.Null,
  ]
  b.bench(fn() {
    let mut total = 0
    for v in values {
      total = total + attr_value_to_key(v).length()
    }
    b.keep(total)
  })
}
