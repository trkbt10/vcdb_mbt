///|
/// Benchmark: eval_filter simple Match
test "bench/filter_eval_match" (b : @bench.T) {
  let filter = FilterExpr::match_("category", @types.String("electronics"))
  let attrs = @types.empty_attrs()
  attrs.set("category", @types.String("electronics"))
  attrs.set("price", @types.Float(99.99))
  b.bench(fn() { b.keep(eval_filter(filter, attrs)) })
}

///|
/// Benchmark: eval_filter Range
test "bench/filter_eval_range" (b : @bench.T) {
  let range = @types.NumericRange::between(10.0, 100.0)
  let filter = FilterExpr::range("price", range)
  let attrs = @types.empty_attrs()
  attrs.set("price", @types.Float(50.0))
  b.bench(fn() { b.keep(eval_filter(filter, attrs)) })
}

///|
/// Benchmark: eval_filter Exists
test "bench/filter_eval_exists" (b : @bench.T) {
  let filter = FilterExpr::exists("optional_field")
  let attrs = @types.empty_attrs()
  attrs.set("optional_field", @types.String("present"))
  b.bench(fn() { b.keep(eval_filter(filter, attrs)) })
}

///|
/// Benchmark: eval_filter Must (AND) with 3 conditions
test "bench/filter_eval_must_3" (b : @bench.T) {
  let filter = FilterExpr::must([
    FilterExpr::match_("category", @types.String("electronics")),
    FilterExpr::range("price", @types.NumericRange::between(10.0, 500.0)),
    FilterExpr::exists("in_stock"),
  ])
  let attrs = @types.empty_attrs()
  attrs.set("category", @types.String("electronics"))
  attrs.set("price", @types.Float(99.99))
  attrs.set("in_stock", @types.Bool(true))
  b.bench(fn() { b.keep(eval_filter(filter, attrs)) })
}

///|
/// Benchmark: eval_filter MustNot (NOT)
test "bench/filter_eval_must_not" (b : @bench.T) {
  let filter = FilterExpr::must_not([
    FilterExpr::match_("status", @types.String("discontinued")),
  ])
  let attrs = @types.empty_attrs()
  attrs.set("status", @types.String("active"))
  b.bench(fn() { b.keep(eval_filter(filter, attrs)) })
}

///|
/// Benchmark: eval_filter Should (OR) with 3 conditions
test "bench/filter_eval_should_3" (b : @bench.T) {
  let filter = FilterExpr::should([
    FilterExpr::match_("category", @types.String("electronics")),
    FilterExpr::match_("category", @types.String("appliances")),
    FilterExpr::match_("category", @types.String("computers")),
  ])
  let attrs = @types.empty_attrs()
  attrs.set("category", @types.String("computers"))
  b.bench(fn() { b.keep(eval_filter(filter, attrs)) })
}

///|
/// Benchmark: eval_filter nested Must + Should
test "bench/filter_eval_nested" (b : @bench.T) {
  let filter = FilterExpr::must([
    FilterExpr::exists("name"),
    FilterExpr::should([
      FilterExpr::match_("region", @types.String("us-east")),
      FilterExpr::match_("region", @types.String("us-west")),
    ]),
  ])
  let attrs = @types.empty_attrs()
  attrs.set("name", @types.String("product"))
  attrs.set("region", @types.String("us-west"))
  b.bench(fn() { b.keep(eval_filter(filter, attrs)) })
}

///|
/// Benchmark: compile_filter and apply
test "bench/filter_compile_apply" (b : @bench.T) {
  let filter = FilterExpr::must([
    FilterExpr::match_("type", @types.String("vector")),
    FilterExpr::range("score", @types.NumericRange::gte(0.5)),
  ])
  let predicate = compile_filter(filter)
  let id = @types.VectorId::from_int(1)
  let attrs = @types.empty_attrs()
  attrs.set("type", @types.String("vector"))
  attrs.set("score", @types.Float(0.75))
  b.bench(fn() { b.keep(predicate(id, attrs)) })
}

///|
/// Benchmark: get_candidates_basic with Match
test "bench/filter_candidates_match" (b : @bench.T) {
  let index = @attr.BasicAttrIndex::new()
  for i in 0..<1000 {
    let attrs = @types.empty_attrs()
    attrs.set("category", @types.String("cat_" + (i % 10).to_string()))
    index.set_attrs(@types.VectorId::from_int(i), attrs)
  }
  let filter = FilterExpr::match_("category", @types.String("cat_5"))
  b.bench(fn() {
    match get_candidates_basic(filter, index) {
      Some(ids) => b.keep(ids.length())
      None => b.keep(0)
    }
  })
}

///|
/// Benchmark: get_candidates_basic with Must (AND)
test "bench/filter_candidates_must" (b : @bench.T) {
  let index = @attr.BasicAttrIndex::new()
  for i in 0..<1000 {
    let attrs = @types.empty_attrs()
    attrs.set("category", @types.String("cat_" + (i % 10).to_string()))
    attrs.set("region", @types.String("region_" + (i % 5).to_string()))
    index.set_attrs(@types.VectorId::from_int(i), attrs)
  }
  let filter = FilterExpr::must([
    FilterExpr::match_("category", @types.String("cat_5")),
    FilterExpr::match_("region", @types.String("region_2")),
  ])
  b.bench(fn() {
    match get_candidates_basic(filter, index) {
      Some(ids) => b.keep(ids.length())
      None => b.keep(0)
    }
  })
}

///|
/// Benchmark: intersect_ids performance
test "bench/filter_intersect_ids" (b : @bench.T) {
  let a : Array[@types.VectorId] = []
  let b_arr : Array[@types.VectorId] = []
  for i in 0..<500 {
    a.push(@types.VectorId::from_int(i * 2))
    b_arr.push(@types.VectorId::from_int(i * 3))
  }
  b.bench(fn() { b.keep(intersect_ids(a, b_arr).length()) })
}
