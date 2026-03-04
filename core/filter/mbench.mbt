///|
/// Benchmark: eval_filter simple Match
test "bench/filter_eval_match" (b : @bench.T) {
  let filter = FilterExpr::match_("category", @core.String("electronics"))
  let attrs = @core.empty_attrs()
  attrs.set("category", @core.String("electronics"))
  attrs.set("price", @core.Float(99.99))
  b.bench(fn() { b.keep(eval_filter(filter, attrs)) })
}

///|
/// Benchmark: eval_filter Range
test "bench/filter_eval_range" (b : @bench.T) {
  let range = @core.NumericRange::between(10.0, 100.0)
  let filter = FilterExpr::range("price", range)
  let attrs = @core.empty_attrs()
  attrs.set("price", @core.Float(50.0))
  b.bench(fn() { b.keep(eval_filter(filter, attrs)) })
}

///|
/// Benchmark: eval_filter Exists
test "bench/filter_eval_exists" (b : @bench.T) {
  let filter = FilterExpr::exists("optional_field")
  let attrs = @core.empty_attrs()
  attrs.set("optional_field", @core.String("present"))
  b.bench(fn() { b.keep(eval_filter(filter, attrs)) })
}

///|
/// Benchmark: eval_filter Must (AND) with 3 conditions
test "bench/filter_eval_must_3" (b : @bench.T) {
  let filter = FilterExpr::must([
    FilterExpr::match_("category", @core.String("electronics")),
    FilterExpr::range("price", @core.NumericRange::between(10.0, 500.0)),
    FilterExpr::exists("in_stock"),
  ])
  let attrs = @core.empty_attrs()
  attrs.set("category", @core.String("electronics"))
  attrs.set("price", @core.Float(99.99))
  attrs.set("in_stock", @core.Bool(true))
  b.bench(fn() { b.keep(eval_filter(filter, attrs)) })
}

///|
/// Benchmark: eval_filter MustNot (NOT)
test "bench/filter_eval_must_not" (b : @bench.T) {
  let filter = FilterExpr::must_not([
    FilterExpr::match_("status", @core.String("discontinued")),
  ])
  let attrs = @core.empty_attrs()
  attrs.set("status", @core.String("active"))
  b.bench(fn() { b.keep(eval_filter(filter, attrs)) })
}

///|
/// Benchmark: eval_filter Should (OR) with 3 conditions
test "bench/filter_eval_should_3" (b : @bench.T) {
  let filter = FilterExpr::should([
    FilterExpr::match_("category", @core.String("electronics")),
    FilterExpr::match_("category", @core.String("appliances")),
    FilterExpr::match_("category", @core.String("computers")),
  ])
  let attrs = @core.empty_attrs()
  attrs.set("category", @core.String("computers"))
  b.bench(fn() { b.keep(eval_filter(filter, attrs)) })
}

///|
/// Benchmark: eval_filter nested Must + Should
test "bench/filter_eval_nested" (b : @bench.T) {
  let filter = FilterExpr::must([
    FilterExpr::exists("name"),
    FilterExpr::should([
      FilterExpr::match_("region", @core.String("us-east")),
      FilterExpr::match_("region", @core.String("us-west")),
    ]),
  ])
  let attrs = @core.empty_attrs()
  attrs.set("name", @core.String("product"))
  attrs.set("region", @core.String("us-west"))
  b.bench(fn() { b.keep(eval_filter(filter, attrs)) })
}

///|
/// Benchmark: compile_filter and apply
test "bench/filter_compile_apply" (b : @bench.T) {
  let filter = FilterExpr::must([
    FilterExpr::match_("type", @core.String("vector")),
    FilterExpr::range("score", @core.NumericRange::gte(0.5)),
  ])
  let predicate = compile_filter(filter)
  let id = @core.VectorId::from_int(1)
  let attrs = @core.empty_attrs()
  attrs.set("type", @core.String("vector"))
  attrs.set("score", @core.Float(0.75))
  b.bench(fn() { b.keep(predicate(id, attrs)) })
}

///|
/// Benchmark: get_candidates_basic with Match
test "bench/filter_candidates_match" (b : @bench.T) {
  let index = @attr.BasicAttrIndex::new()
  for i in 0..<1000 {
    let attrs = @core.empty_attrs()
    attrs.set("category", @core.String("cat_" + (i % 10).to_string()))
    index.set_attrs(@core.VectorId::from_int(i), attrs)
  }
  let filter = FilterExpr::match_("category", @core.String("cat_5"))
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
    let attrs = @core.empty_attrs()
    attrs.set("category", @core.String("cat_" + (i % 10).to_string()))
    attrs.set("region", @core.String("region_" + (i % 5).to_string()))
    index.set_attrs(@core.VectorId::from_int(i), attrs)
  }
  let filter = FilterExpr::must([
    FilterExpr::match_("category", @core.String("cat_5")),
    FilterExpr::match_("region", @core.String("region_2")),
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
  let a : Array[@core.VectorId] = []
  let b_arr : Array[@core.VectorId] = []
  for i in 0..<500 {
    a.push(@core.VectorId::from_int(i * 2))
    b_arr.push(@core.VectorId::from_int(i * 3))
  }
  b.bench(fn() { b.keep(intersect_ids(a, b_arr).length()) })
}
