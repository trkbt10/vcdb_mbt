// Whitebox tests for filter module

///|
/// Test: FilterExpr Match compilation
test "filter/match_compile" {
  let filter = compile_filter(
    FilterExpr::Leaf(LeafExpr::Match("status", @types.String("active"))),
  )
  let attrs = @types.empty_attrs()
  attrs.set("status", @types.String("active"))
  inspect(filter(@types.VectorId::from_int(1), attrs), content="true")
  let attrs2 = @types.empty_attrs()
  attrs2.set("status", @types.String("inactive"))
  inspect(filter(@types.VectorId::from_int(2), attrs2), content="false")
}

///|
/// Test: FilterExpr Range compilation
test "filter/range_compile" {
  let range = @types.NumericRange::gt(50.0)
  let filter = compile_filter(FilterExpr::Leaf(LeafExpr::Range("score", range)))
  let attrs1 = @types.empty_attrs()
  attrs1.set("score", @types.Int(100L))
  inspect(filter(@types.VectorId::from_int(1), attrs1), content="true")
  let attrs2 = @types.empty_attrs()
  attrs2.set("score", @types.Int(30L))
  inspect(filter(@types.VectorId::from_int(2), attrs2), content="false")
}

///|
/// Test: FilterExpr Must (AND)
test "filter/must_compile" {
  let filter = compile_filter(
    FilterExpr::Must([
      FilterExpr::Leaf(LeafExpr::Match("a", @types.Bool(true))),
      FilterExpr::Leaf(LeafExpr::Match("b", @types.Bool(true))),
    ]),
  )
  let attrs1 = @types.empty_attrs()
  attrs1.set("a", @types.Bool(true))
  attrs1.set("b", @types.Bool(true))
  inspect(filter(@types.VectorId::from_int(1), attrs1), content="true")
  let attrs2 = @types.empty_attrs()
  attrs2.set("a", @types.Bool(true))
  attrs2.set("b", @types.Bool(false))
  inspect(filter(@types.VectorId::from_int(2), attrs2), content="false")
}

///|
/// Test: FilterExpr MustNot (AND NOT)
test "filter/must_not_compile" {
  let filter = compile_filter(
    FilterExpr::MustNot([
      FilterExpr::Leaf(LeafExpr::Match("banned", @types.Bool(true))),
    ]),
  )
  let attrs1 = @types.empty_attrs()
  attrs1.set("banned", @types.Bool(false))
  inspect(filter(@types.VectorId::from_int(1), attrs1), content="true")
  let attrs2 = @types.empty_attrs()
  attrs2.set("banned", @types.Bool(true))
  inspect(filter(@types.VectorId::from_int(2), attrs2), content="false")
}

///|
/// Test: FilterExpr Should (OR with min matches)
test "filter/should_compile" {
  // At least 1 of 3 conditions must match
  let filter = compile_filter(
    FilterExpr::Should(
      [
        FilterExpr::Leaf(LeafExpr::Match("a", @types.Bool(true))),
        FilterExpr::Leaf(LeafExpr::Match("b", @types.Bool(true))),
        FilterExpr::Leaf(LeafExpr::Match("c", @types.Bool(true))),
      ],
      1,
    ),
  )
  // None match
  let attrs1 = @types.empty_attrs()
  attrs1.set("a", @types.Bool(false))
  attrs1.set("b", @types.Bool(false))
  attrs1.set("c", @types.Bool(false))
  inspect(filter(@types.VectorId::from_int(1), attrs1), content="false")
  // One matches
  let attrs2 = @types.empty_attrs()
  attrs2.set("a", @types.Bool(true))
  attrs2.set("b", @types.Bool(false))
  inspect(filter(@types.VectorId::from_int(2), attrs2), content="true")
  // Test should with min=2
  let filter2 = compile_filter(
    FilterExpr::Should(
      [
        FilterExpr::Leaf(LeafExpr::Match("x", @types.Bool(true))),
        FilterExpr::Leaf(LeafExpr::Match("y", @types.Bool(true))),
      ],
      2,
    ),
  )
  let attrs3 = @types.empty_attrs()
  attrs3.set("x", @types.Bool(true))
  attrs3.set("y", @types.Bool(false))
  inspect(filter2(@types.VectorId::from_int(3), attrs3), content="false")
  let attrs4 = @types.empty_attrs()
  attrs4.set("x", @types.Bool(true))
  attrs4.set("y", @types.Bool(true))
  inspect(filter2(@types.VectorId::from_int(4), attrs4), content="true")
}

///|
/// Test: FilterExpr Exists
test "filter/exists_compile" {
  let filter = compile_filter(FilterExpr::Leaf(LeafExpr::Exists("email")))
  // Has email
  let attrs1 = @types.empty_attrs()
  attrs1.set("email", @types.String("test@example.com"))
  inspect(filter(@types.VectorId::from_int(1), attrs1), content="true")
  // Has email but null
  let attrs2 = @types.empty_attrs()
  attrs2.set("email", @types.Null)
  inspect(filter(@types.VectorId::from_int(2), attrs2), content="false")
  // No email field
  let attrs3 = @types.empty_attrs()
  attrs3.set("name", @types.String("test"))
  inspect(filter(@types.VectorId::from_int(3), attrs3), content="false")
}

///|
/// Test: FilterExpr IsNull
test "filter/is_null_compile" {
  let filter = compile_filter(FilterExpr::Leaf(LeafExpr::IsNull("deleted_at")))
  // Field doesn't exist
  let attrs1 = @types.empty_attrs()
  inspect(filter(@types.VectorId::from_int(1), attrs1), content="true")
  // Field is null
  let attrs2 = @types.empty_attrs()
  attrs2.set("deleted_at", @types.Null)
  inspect(filter(@types.VectorId::from_int(2), attrs2), content="true")
  // Field has value
  let attrs3 = @types.empty_attrs()
  attrs3.set("deleted_at", @types.String("2024-01-01"))
  inspect(filter(@types.VectorId::from_int(3), attrs3), content="false")
}

///|
/// Test: get_candidates_basic with Match filter
test "filter/get_candidates_match" {
  let index = @attr.BasicAttrIndex::new()
  let id1 = @types.VectorId::from_int(1)
  let id2 = @types.VectorId::from_int(2)
  let id3 = @types.VectorId::from_int(3)
  let attrs1 = @types.empty_attrs()
  attrs1.set("status", @types.String("active"))
  let attrs2 = @types.empty_attrs()
  attrs2.set("status", @types.String("active"))
  let attrs3 = @types.empty_attrs()
  attrs3.set("status", @types.String("inactive"))
  index.set_attrs(id1, attrs1)
  index.set_attrs(id2, attrs2)
  index.set_attrs(id3, attrs3)
  // Pre-filter with Match
  let expr = FilterExpr::match_("status", @types.String("active"))
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
  let id1 = @types.VectorId::from_int(1)
  let id2 = @types.VectorId::from_int(2)
  let id3 = @types.VectorId::from_int(3)
  let attrs1 = @types.empty_attrs()
  attrs1.set("a", @types.Bool(true))
  attrs1.set("b", @types.Bool(true))
  let attrs2 = @types.empty_attrs()
  attrs2.set("a", @types.Bool(true))
  attrs2.set("b", @types.Bool(false))
  let attrs3 = @types.empty_attrs()
  attrs3.set("a", @types.Bool(false))
  attrs3.set("b", @types.Bool(true))
  index.set_attrs(id1, attrs1)
  index.set_attrs(id2, attrs2)
  index.set_attrs(id3, attrs3)
  // Pre-filter with Must (a=true AND b=true)
  let expr = FilterExpr::must([
    FilterExpr::match_("a", @types.Bool(true)),
    FilterExpr::match_("b", @types.Bool(true)),
  ])
  let candidates = get_candidates_basic(expr, index)
  match candidates {
    Some(ids) => {
      inspect(ids.length(), content="1")
      inspect(ids[0], content="Int64Id(1)")
    }
    None => inspect(false, content="true")
  }
}

///|
/// Test: get_candidates_basic returns None for MustNot
test "filter/get_candidates_must_not" {
  let index = @attr.BasicAttrIndex::new()
  let expr = FilterExpr::must_not([
    FilterExpr::match_("banned", @types.Bool(true)),
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
  let range = @types.NumericRange::between(10.0, 20.0)
  let filter = compile_filter(FilterExpr::range("price", range))
  let attrs1 = @types.empty_attrs()
  attrs1.set("price", @types.Float(15.5))
  inspect(filter(@types.VectorId::from_int(1), attrs1), content="true")
  let attrs2 = @types.empty_attrs()
  attrs2.set("price", @types.Float(25.0))
  inspect(filter(@types.VectorId::from_int(2), attrs2), content="false")
  // Non-numeric value
  let attrs3 = @types.empty_attrs()
  attrs3.set("price", @types.String("cheap"))
  inspect(filter(@types.VectorId::from_int(3), attrs3), content="false")
}

///|
/// Test: get_candidates_basic with Should
test "filter/get_candidates_should" {
  let index = @attr.BasicAttrIndex::new()
  let id1 = @types.VectorId::from_int(1)
  let id2 = @types.VectorId::from_int(2)
  let id3 = @types.VectorId::from_int(3)
  let attrs1 = @types.empty_attrs()
  attrs1.set("cat", @types.String("A"))
  let attrs2 = @types.empty_attrs()
  attrs2.set("cat", @types.String("B"))
  let attrs3 = @types.empty_attrs()
  attrs3.set("cat", @types.String("C"))
  index.set_attrs(id1, attrs1)
  index.set_attrs(id2, attrs2)
  index.set_attrs(id3, attrs3)
  // Pre-filter with Should (cat=A OR cat=B)
  let expr = FilterExpr::should([
    FilterExpr::match_("cat", @types.String("A")),
    FilterExpr::match_("cat", @types.String("B")),
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
  let id1 = @types.VectorId::from_int(1)
  let id2 = @types.VectorId::from_int(2)
  let attrs1 = @types.empty_attrs()
  attrs1.set("email", @types.String("a@b.com"))
  let attrs2 = @types.empty_attrs()
  attrs2.set("name", @types.String("Bob"))
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
    let attrs = @types.empty_attrs()
    attrs.set("score", @types.Int(i.to_int64() * 10L))
    index.set_attrs(@types.VectorId::from_int(i), attrs)
  }
  // Range: 30 <= score <= 60
  let range = @types.NumericRange::between(30.0, 60.0)
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
        FilterExpr::match_("a", @types.Bool(true)),
        FilterExpr::match_("b", @types.Bool(true)),
      ]),
      FilterExpr::must([
        FilterExpr::match_("c", @types.Bool(true)),
        FilterExpr::match_("d", @types.Bool(true)),
      ]),
    ]),
  )
  // a=true, b=true matches first branch
  let attrs1 = @types.empty_attrs()
  attrs1.set("a", @types.Bool(true))
  attrs1.set("b", @types.Bool(true))
  inspect(filter(@types.VectorId::from_int(1), attrs1), content="true")
  // c=true, d=true matches second branch
  let attrs2 = @types.empty_attrs()
  attrs2.set("c", @types.Bool(true))
  attrs2.set("d", @types.Bool(true))
  inspect(filter(@types.VectorId::from_int(2), attrs2), content="true")
  // Nothing matches
  let attrs3 = @types.empty_attrs()
  attrs3.set("a", @types.Bool(true))
  attrs3.set("c", @types.Bool(true))
  inspect(filter(@types.VectorId::from_int(3), attrs3), content="false")
}

///|
/// Test: Match with different value types
test "filter/match_value_types" {
  // Int comparison
  let filter_int = compile_filter(FilterExpr::match_("count", @types.Int(42L)))
  let attrs1 = @types.empty_attrs()
  attrs1.set("count", @types.Int(42L))
  inspect(filter_int(@types.VectorId::from_int(1), attrs1), content="true")
  // Float comparison
  let filter_float = compile_filter(
    FilterExpr::match_("score", @types.Float(3.14)),
  )
  let attrs2 = @types.empty_attrs()
  attrs2.set("score", @types.Float(3.14))
  inspect(filter_float(@types.VectorId::from_int(2), attrs2), content="true")
  // Null comparison
  let filter_null = compile_filter(FilterExpr::match_("deleted", @types.Null))
  let attrs3 = @types.empty_attrs()
  attrs3.set("deleted", @types.Null)
  inspect(filter_null(@types.VectorId::from_int(3), attrs3), content="true")
  // Type mismatch
  let attrs4 = @types.empty_attrs()
  attrs4.set("count", @types.String("42"))
  inspect(filter_int(@types.VectorId::from_int(4), attrs4), content="false")
}

///|
/// Test: Should with min > 1 returns None for prefilter (P1 fix)
test "filter/should_min_prefilter" {
  let index = @attr.BasicAttrIndex::new()
  let id1 = @types.VectorId::from_int(1)
  let id2 = @types.VectorId::from_int(2)
  let attrs1 = @types.empty_attrs()
  attrs1.set("a", @types.Bool(true))
  attrs1.set("b", @types.Bool(true))
  let attrs2 = @types.empty_attrs()
  attrs2.set("a", @types.Bool(true))
  attrs2.set("b", @types.Bool(false))
  index.set_attrs(id1, attrs1)
  index.set_attrs(id2, attrs2)
  // Should with min=1 (OR) should return candidates
  let expr1 = FilterExpr::should([
    FilterExpr::match_("a", @types.Bool(true)),
    FilterExpr::match_("b", @types.Bool(true)),
  ])
  let candidates1 = get_candidates_basic(expr1, index)
  inspect(candidates1 is Some(_), content="true")
  // Should with min=2 should return None (cannot efficiently prefilter)
  let expr2 = FilterExpr::Should(
    [
      FilterExpr::match_("a", @types.Bool(true)),
      FilterExpr::match_("b", @types.Bool(true)),
    ],
    2,
  )
  let candidates2 = get_candidates_basic(expr2, index)
  inspect(candidates2 is None, content="true")
  // Should with min=0 should return None (matches everything, fallback to post-filter)
  let expr3 = FilterExpr::Should(
    [
      FilterExpr::match_("a", @types.Bool(true)),
      FilterExpr::match_("b", @types.Bool(true)),
    ],
    0,
  )
  let candidates3 = get_candidates_basic(expr3, index)
  inspect(candidates3 is None, content="true")
}
