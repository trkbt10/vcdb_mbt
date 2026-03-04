// Whitebox tests for filter module

///|
/// Test: FilterExpr Match compilation
test "filter/match_compile" {
  let filter = compile_filter(
    FilterExpr::Leaf(LeafExpr::Match("status", @core.String("active"))),
  )
  let attrs = @core.empty_attrs()
  attrs.set("status", @core.String("active"))
  inspect(filter(@core.VectorId::from_int(1), attrs), content="true")
  let attrs2 = @core.empty_attrs()
  attrs2.set("status", @core.String("inactive"))
  inspect(filter(@core.VectorId::from_int(2), attrs2), content="false")
}

///|
/// Test: FilterExpr Range compilation
test "filter/range_compile" {
  let range = @core.NumericRange::gt(50.0)
  let filter = compile_filter(FilterExpr::Leaf(LeafExpr::Range("score", range)))
  let attrs1 = @core.empty_attrs()
  attrs1.set("score", @core.Int(100L))
  inspect(filter(@core.VectorId::from_int(1), attrs1), content="true")
  let attrs2 = @core.empty_attrs()
  attrs2.set("score", @core.Int(30L))
  inspect(filter(@core.VectorId::from_int(2), attrs2), content="false")
}

///|
/// Test: FilterExpr Must (AND)
test "filter/must_compile" {
  let filter = compile_filter(
    FilterExpr::Must([
      FilterExpr::Leaf(LeafExpr::Match("a", @core.Bool(true))),
      FilterExpr::Leaf(LeafExpr::Match("b", @core.Bool(true))),
    ]),
  )
  let attrs1 = @core.empty_attrs()
  attrs1.set("a", @core.Bool(true))
  attrs1.set("b", @core.Bool(true))
  inspect(filter(@core.VectorId::from_int(1), attrs1), content="true")
  let attrs2 = @core.empty_attrs()
  attrs2.set("a", @core.Bool(true))
  attrs2.set("b", @core.Bool(false))
  inspect(filter(@core.VectorId::from_int(2), attrs2), content="false")
}

///|
/// Test: FilterExpr MustNot (AND NOT)
test "filter/must_not_compile" {
  let filter = compile_filter(
    FilterExpr::MustNot([
      FilterExpr::Leaf(LeafExpr::Match("banned", @core.Bool(true))),
    ]),
  )
  let attrs1 = @core.empty_attrs()
  attrs1.set("banned", @core.Bool(false))
  inspect(filter(@core.VectorId::from_int(1), attrs1), content="true")
  let attrs2 = @core.empty_attrs()
  attrs2.set("banned", @core.Bool(true))
  inspect(filter(@core.VectorId::from_int(2), attrs2), content="false")
}

///|
/// Test: FilterExpr Should (OR with min matches)
test "filter/should_compile" {
  // At least 1 of 3 conditions must match
  let filter = compile_filter(
    FilterExpr::Should(
      [
        FilterExpr::Leaf(LeafExpr::Match("a", @core.Bool(true))),
        FilterExpr::Leaf(LeafExpr::Match("b", @core.Bool(true))),
        FilterExpr::Leaf(LeafExpr::Match("c", @core.Bool(true))),
      ],
      1,
    ),
  )
  // None match
  let attrs1 = @core.empty_attrs()
  attrs1.set("a", @core.Bool(false))
  attrs1.set("b", @core.Bool(false))
  attrs1.set("c", @core.Bool(false))
  inspect(filter(@core.VectorId::from_int(1), attrs1), content="false")
  // One matches
  let attrs2 = @core.empty_attrs()
  attrs2.set("a", @core.Bool(true))
  attrs2.set("b", @core.Bool(false))
  inspect(filter(@core.VectorId::from_int(2), attrs2), content="true")
  // Test should with min=2
  let filter2 = compile_filter(
    FilterExpr::Should(
      [
        FilterExpr::Leaf(LeafExpr::Match("x", @core.Bool(true))),
        FilterExpr::Leaf(LeafExpr::Match("y", @core.Bool(true))),
      ],
      2,
    ),
  )
  let attrs3 = @core.empty_attrs()
  attrs3.set("x", @core.Bool(true))
  attrs3.set("y", @core.Bool(false))
  inspect(filter2(@core.VectorId::from_int(3), attrs3), content="false")
  let attrs4 = @core.empty_attrs()
  attrs4.set("x", @core.Bool(true))
  attrs4.set("y", @core.Bool(true))
  inspect(filter2(@core.VectorId::from_int(4), attrs4), content="true")
}

///|
/// Test: FilterExpr Exists
test "filter/exists_compile" {
  let filter = compile_filter(FilterExpr::Leaf(LeafExpr::Exists("email")))
  // Has email
  let attrs1 = @core.empty_attrs()
  attrs1.set("email", @core.String("test@example.com"))
  inspect(filter(@core.VectorId::from_int(1), attrs1), content="true")
  // Has email but null
  let attrs2 = @core.empty_attrs()
  attrs2.set("email", @core.Null)
  inspect(filter(@core.VectorId::from_int(2), attrs2), content="false")
  // No email field
  let attrs3 = @core.empty_attrs()
  attrs3.set("name", @core.String("test"))
  inspect(filter(@core.VectorId::from_int(3), attrs3), content="false")
}

///|
/// Test: FilterExpr IsNull
test "filter/is_null_compile" {
  let filter = compile_filter(FilterExpr::Leaf(LeafExpr::IsNull("deleted_at")))
  // Field doesn't exist
  let attrs1 = @core.empty_attrs()
  inspect(filter(@core.VectorId::from_int(1), attrs1), content="true")
  // Field is null
  let attrs2 = @core.empty_attrs()
  attrs2.set("deleted_at", @core.Null)
  inspect(filter(@core.VectorId::from_int(2), attrs2), content="true")
  // Field has value
  let attrs3 = @core.empty_attrs()
  attrs3.set("deleted_at", @core.String("2024-01-01"))
  inspect(filter(@core.VectorId::from_int(3), attrs3), content="false")
}

///|
/// Test: get_candidates_basic with Match filter
test "filter/get_candidates_match" {
  let index = @attr.BasicAttrIndex::new()
  let id1 = @core.VectorId::from_int(1)
  let id2 = @core.VectorId::from_int(2)
  let id3 = @core.VectorId::from_int(3)
  let attrs1 = @core.empty_attrs()
  attrs1.set("status", @core.String("active"))
  let attrs2 = @core.empty_attrs()
  attrs2.set("status", @core.String("active"))
  let attrs3 = @core.empty_attrs()
  attrs3.set("status", @core.String("inactive"))
  index.set_attrs(id1, attrs1)
  index.set_attrs(id2, attrs2)
  index.set_attrs(id3, attrs3)
  // Pre-filter with Match
  let expr = FilterExpr::match_("status", @core.String("active"))
  let candidates = get_candidates_basic(expr, index)
  match candidates {
    Some(ids) => inspect(ids.length(), content="2")
    None => inspect(false, content="true")
  }
}

///|
/// Test: get_candidates_basic with Must (AND)
test "filter/get_candidates_must" {
  let index = @attr.BasicAttrIndex::new()
  let id1 = @core.VectorId::from_int(1)
  let id2 = @core.VectorId::from_int(2)
  let id3 = @core.VectorId::from_int(3)
  let attrs1 = @core.empty_attrs()
  attrs1.set("a", @core.Bool(true))
  attrs1.set("b", @core.Bool(true))
  let attrs2 = @core.empty_attrs()
  attrs2.set("a", @core.Bool(true))
  attrs2.set("b", @core.Bool(false))
  let attrs3 = @core.empty_attrs()
  attrs3.set("a", @core.Bool(false))
  attrs3.set("b", @core.Bool(true))
  index.set_attrs(id1, attrs1)
  index.set_attrs(id2, attrs2)
  index.set_attrs(id3, attrs3)
  // Pre-filter with Must (a=true AND b=true)
  let expr = FilterExpr::must([
    FilterExpr::match_("a", @core.Bool(true)),
    FilterExpr::match_("b", @core.Bool(true)),
  ])
  let candidates = get_candidates_basic(expr, index)
  match candidates {
    Some(ids) => {
      inspect(ids.length(), content="1")
      inspect(ids[0].to_int64(), content="1")
    }
    None => inspect(false, content="true")
  }
}

///|
/// Test: get_candidates_basic returns None for MustNot
test "filter/get_candidates_must_not" {
  let index = @attr.BasicAttrIndex::new()
  let expr = FilterExpr::must_not([
    FilterExpr::match_("banned", @core.Bool(true)),
  ])
  // MustNot cannot be efficiently pre-filtered
  let candidates = get_candidates_basic(expr, index)
  inspect(candidates is None, content="true")
}

///|
/// Test: get_candidates_basic returns None for IsNull
test "filter/get_candidates_is_null" {
  let index = @attr.BasicAttrIndex::new()
  let expr = FilterExpr::is_null("deleted_at")
  // IsNull cannot be efficiently pre-filtered
  let candidates = get_candidates_basic(expr, index)
  inspect(candidates is None, content="true")
}

///|
/// Test: Range filter with Float values
test "filter/range_float" {
  let range = @core.NumericRange::between(10.0, 20.0)
  let filter = compile_filter(FilterExpr::range("price", range))
  let attrs1 = @core.empty_attrs()
  attrs1.set("price", @core.Float(15.5))
  inspect(filter(@core.VectorId::from_int(1), attrs1), content="true")
  let attrs2 = @core.empty_attrs()
  attrs2.set("price", @core.Float(25.0))
  inspect(filter(@core.VectorId::from_int(2), attrs2), content="false")
  // Non-numeric value
  let attrs3 = @core.empty_attrs()
  attrs3.set("price", @core.String("cheap"))
  inspect(filter(@core.VectorId::from_int(3), attrs3), content="false")
}

///|
/// Test: get_candidates_basic with Should
test "filter/get_candidates_should" {
  let index = @attr.BasicAttrIndex::new()
  let id1 = @core.VectorId::from_int(1)
  let id2 = @core.VectorId::from_int(2)
  let id3 = @core.VectorId::from_int(3)
  let attrs1 = @core.empty_attrs()
  attrs1.set("cat", @core.String("A"))
  let attrs2 = @core.empty_attrs()
  attrs2.set("cat", @core.String("B"))
  let attrs3 = @core.empty_attrs()
  attrs3.set("cat", @core.String("C"))
  index.set_attrs(id1, attrs1)
  index.set_attrs(id2, attrs2)
  index.set_attrs(id3, attrs3)
  // Pre-filter with Should (cat=A OR cat=B)
  let expr = FilterExpr::should([
    FilterExpr::match_("cat", @core.String("A")),
    FilterExpr::match_("cat", @core.String("B")),
  ])
  let candidates = get_candidates_basic(expr, index)
  match candidates {
    Some(ids) => inspect(ids.length(), content="2")
    None => inspect(false, content="true")
  }
}

///|
/// Test: get_candidates_basic with Exists
test "filter/get_candidates_exists" {
  let index = @attr.BasicAttrIndex::new()
  let id1 = @core.VectorId::from_int(1)
  let id2 = @core.VectorId::from_int(2)
  let attrs1 = @core.empty_attrs()
  attrs1.set("email", @core.String("a@b.com"))
  let attrs2 = @core.empty_attrs()
  attrs2.set("name", @core.String("Bob"))
  index.set_attrs(id1, attrs1)
  index.set_attrs(id2, attrs2)
  // Pre-filter with Exists
  let expr = FilterExpr::exists("email")
  let candidates = get_candidates_basic(expr, index)
  match candidates {
    Some(ids) => inspect(ids.length(), content="1")
    None => inspect(false, content="true")
  }
}

///|
/// Test: get_candidates_basic with Range
test "filter/get_candidates_range" {
  let index = @attr.BasicAttrIndex::new()
  for i in 1..<=10 {
    let attrs = @core.empty_attrs()
    attrs.set("score", @core.Int(i.to_int64() * 10L))
    index.set_attrs(@core.VectorId::from_int(i), attrs)
  }
  // Range: 30 <= score <= 60
  let range = @core.NumericRange::between(30.0, 60.0)
  let expr = FilterExpr::range("score", range)
  let candidates = get_candidates_basic(expr, index)
  match candidates {
    Some(ids) => inspect(ids.length(), content="4") // 30, 40, 50, 60
    None => inspect(false, content="true")
  }
}

///|
/// Test: Filter with nested Must and Should
test "filter/nested_expressions" {
  // (a AND b) OR (c AND d) -> Should([Must([a,b]), Must([c,d])], 1)
  let filter = compile_filter(
    FilterExpr::should([
      FilterExpr::must([
        FilterExpr::match_("a", @core.Bool(true)),
        FilterExpr::match_("b", @core.Bool(true)),
      ]),
      FilterExpr::must([
        FilterExpr::match_("c", @core.Bool(true)),
        FilterExpr::match_("d", @core.Bool(true)),
      ]),
    ]),
  )
  // a=true, b=true matches first branch
  let attrs1 = @core.empty_attrs()
  attrs1.set("a", @core.Bool(true))
  attrs1.set("b", @core.Bool(true))
  inspect(filter(@core.VectorId::from_int(1), attrs1), content="true")
  // c=true, d=true matches second branch
  let attrs2 = @core.empty_attrs()
  attrs2.set("c", @core.Bool(true))
  attrs2.set("d", @core.Bool(true))
  inspect(filter(@core.VectorId::from_int(2), attrs2), content="true")
  // Nothing matches
  let attrs3 = @core.empty_attrs()
  attrs3.set("a", @core.Bool(true))
  attrs3.set("c", @core.Bool(true))
  inspect(filter(@core.VectorId::from_int(3), attrs3), content="false")
}

///|
/// Test: Match with different value types
test "filter/match_value_types" {
  // Int comparison
  let filter_int = compile_filter(FilterExpr::match_("count", @core.Int(42L)))
  let attrs1 = @core.empty_attrs()
  attrs1.set("count", @core.Int(42L))
  inspect(filter_int(@core.VectorId::from_int(1), attrs1), content="true")
  // Float comparison
  let filter_float = compile_filter(
    FilterExpr::match_("score", @core.Float(3.14)),
  )
  let attrs2 = @core.empty_attrs()
  attrs2.set("score", @core.Float(3.14))
  inspect(filter_float(@core.VectorId::from_int(2), attrs2), content="true")
  // Null comparison
  let filter_null = compile_filter(FilterExpr::match_("deleted", @core.Null))
  let attrs3 = @core.empty_attrs()
  attrs3.set("deleted", @core.Null)
  inspect(filter_null(@core.VectorId::from_int(3), attrs3), content="true")
  // Type mismatch
  let attrs4 = @core.empty_attrs()
  attrs4.set("count", @core.String("42"))
  inspect(filter_int(@core.VectorId::from_int(4), attrs4), content="false")
}

///|
/// Test: Should with min > 1 returns None for prefilter (P1 fix)
test "filter/should_min_prefilter" {
  let index = @attr.BasicAttrIndex::new()
  let id1 = @core.VectorId::from_int(1)
  let id2 = @core.VectorId::from_int(2)
  let attrs1 = @core.empty_attrs()
  attrs1.set("a", @core.Bool(true))
  attrs1.set("b", @core.Bool(true))
  let attrs2 = @core.empty_attrs()
  attrs2.set("a", @core.Bool(true))
  attrs2.set("b", @core.Bool(false))
  index.set_attrs(id1, attrs1)
  index.set_attrs(id2, attrs2)
  // Should with min=1 (OR) should return candidates
  let expr1 = FilterExpr::should([
    FilterExpr::match_("a", @core.Bool(true)),
    FilterExpr::match_("b", @core.Bool(true)),
  ])
  let candidates1 = get_candidates_basic(expr1, index)
  inspect(candidates1 is Some(_), content="true")
  // Should with min=2 should return None (cannot efficiently prefilter)
  let expr2 = FilterExpr::Should(
    [
      FilterExpr::match_("a", @core.Bool(true)),
      FilterExpr::match_("b", @core.Bool(true)),
    ],
    2,
  )
  let candidates2 = get_candidates_basic(expr2, index)
  inspect(candidates2 is None, content="true")
  // Should with min=0 should return None (matches everything, fallback to post-filter)
  let expr3 = FilterExpr::Should(
    [
      FilterExpr::match_("a", @core.Bool(true)),
      FilterExpr::match_("b", @core.Bool(true)),
    ],
    0,
  )
  let candidates3 = get_candidates_basic(expr3, index)
  inspect(candidates3 is None, content="true")
}
