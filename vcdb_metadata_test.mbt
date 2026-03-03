// Comprehensive Metadata, Filter, and Index Tests
// Tests all attribute types, filter expressions, and index strategies

// =============================================================================
// Section 1: AttrValue Type Coverage
// =============================================================================

///|
/// Test: All AttrValue types storage and retrieval
test "meta/attrvalue/all_types" {
  let db = @vcdb.VectorDB::with_dim(2)
  let attrs = @core.empty_attrs()

  // Set all types
  attrs.set("null_val", @core.Null)
  attrs.set("bool_true", @core.Bool(true))
  attrs.set("bool_false", @core.Bool(false))
  attrs.set("int_pos", @core.Int(42L))
  attrs.set("int_neg", @core.Int(-100L))
  attrs.set("int_zero", @core.Int(0L))
  attrs.set("int_max", @core.Int(9223372036854775807L))
  attrs.set("float_pos", @core.Float(3.14159))
  attrs.set("float_neg", @core.Float(-2.71828))
  attrs.set("float_zero", @core.Float(0.0))
  attrs.set("string_normal", @core.String("hello world"))
  attrs.set("string_empty", @core.String(""))
  attrs.set("string_unicode", @core.String("日本語テスト"))
  attrs.set("string_special", @core.String("a\tb\nc"))

  db.add(@core.VectorId::from_int(1), [1.0, 0.0], attrs)

  // Retrieve and verify
  let record = db.get(@core.VectorId::from_int(1)).unwrap()
  let a = record.attrs

  // Null
  match a.get("null_val") {
    Some(@core.Null) => inspect(true, content="true")
    _ => inspect(false, content="true")
  }

  // Booleans
  match a.get("bool_true") {
    Some(@core.Bool(b)) => inspect(b, content="true")
    _ => inspect(false, content="true")
  }
  match a.get("bool_false") {
    Some(@core.Bool(b)) => inspect(b, content="false")
    _ => inspect(false, content="true")
  }

  // Integers
  match a.get("int_pos") {
    Some(@core.Int(n)) => inspect(n, content="42")
    _ => inspect(false, content="true")
  }
  match a.get("int_neg") {
    Some(@core.Int(n)) => inspect(n, content="-100")
    _ => inspect(false, content="true")
  }
  match a.get("int_zero") {
    Some(@core.Int(n)) => inspect(n, content="0")
    _ => inspect(false, content="true")
  }

  // Floats
  match a.get("float_pos") {
    Some(@core.Float(f)) => inspect((f - 3.14159).abs() < 0.00001, content="true")
    _ => inspect(false, content="true")
  }

  // Strings
  match a.get("string_normal") {
    Some(@core.String(s)) => inspect(s, content="hello world")
    _ => inspect(false, content="true")
  }
  match a.get("string_empty") {
    Some(@core.String(s)) => inspect(s, content="")
    _ => inspect(false, content="true")
  }
  match a.get("string_unicode") {
    Some(@core.String(s)) => inspect(s, content="日本語テスト")
    _ => inspect(false, content="true")
  }
}

///|
/// Test: Attrs operations (get, set, keys, size, clear, copy)
test "meta/attrs/operations" {
  let attrs = @core.empty_attrs()

  // Initially empty
  inspect(attrs.is_empty(), content="true")
  inspect(attrs.size(), content="0")

  // Set values
  attrs.set("a", @core.Int(1L))
  attrs.set("b", @core.Int(2L))
  attrs.set("c", @core.Int(3L))

  inspect(attrs.is_empty(), content="false")
  inspect(attrs.size(), content="3")

  // Keys
  let keys = attrs.keys()
  inspect(keys.length(), content="3")

  // Copy is independent
  let copied = attrs.copy()
  copied.set("d", @core.Int(4L))
  inspect(attrs.size(), content="3")  // Original unchanged
  inspect(copied.size(), content="4")

  // Clear
  attrs.clear()
  inspect(attrs.is_empty(), content="true")
  inspect(attrs.size(), content="0")
}

///|
/// Test: Attrs update (set same key with different value)
test "meta/attrs/update" {
  let db = @vcdb.VectorDB::with_dim(2)
  let attrs = @core.empty_attrs()
  attrs.set("version", @core.Int(1L))
  db.add(@core.VectorId::from_int(1), [1.0, 0.0], attrs)

  // Update attrs using update_attrs
  let new_attrs = @core.empty_attrs()
  new_attrs.set("version", @core.Int(2L))
  new_attrs.set("updated", @core.Bool(true))
  let _ = db.update_attrs(@core.VectorId::from_int(1), new_attrs)

  let record = db.get(@core.VectorId::from_int(1)).unwrap()
  match record.attrs.get("version") {
    Some(@core.Int(v)) => inspect(v, content="2")
    _ => inspect(false, content="true")
  }
  match record.attrs.get("updated") {
    Some(@core.Bool(b)) => inspect(b, content="true")
    _ => inspect(false, content="true")
  }
}

///|
/// Test: Non-existent key returns None
test "meta/attrs/missing_key" {
  let attrs = @core.empty_attrs()
  attrs.set("exists", @core.Int(1L))

  inspect(attrs.get("exists") is Some(_), content="true")
  inspect(attrs.get("missing") is None, content="true")
}

// =============================================================================
// Section 2: NumericRange Tests
// =============================================================================

///|
/// Test: NumericRange.gt (greater than)
test "meta/range/gt" {
  let range = @core.NumericRange::gt(5.0)
  inspect(range.matches(6.0), content="true")
  inspect(range.matches(5.5), content="true")
  inspect(range.matches(5.0), content="false")  // Not >5
  inspect(range.matches(4.0), content="false")
}

///|
/// Test: NumericRange.gte (greater than or equal)
test "meta/range/gte" {
  let range = @core.NumericRange::gte(5.0)
  inspect(range.matches(6.0), content="true")
  inspect(range.matches(5.0), content="true")   // Equal is OK
  inspect(range.matches(4.999), content="false")
}

///|
/// Test: NumericRange.lt (less than)
test "meta/range/lt" {
  let range = @core.NumericRange::lt(5.0)
  inspect(range.matches(4.0), content="true")
  inspect(range.matches(4.999), content="true")
  inspect(range.matches(5.0), content="false")  // Not <5
  inspect(range.matches(6.0), content="false")
}

///|
/// Test: NumericRange.lte (less than or equal)
test "meta/range/lte" {
  let range = @core.NumericRange::lte(5.0)
  inspect(range.matches(4.0), content="true")
  inspect(range.matches(5.0), content="true")   // Equal is OK
  inspect(range.matches(5.001), content="false")
}

///|
/// Test: NumericRange.between (inclusive by default)
test "meta/range/between_inclusive" {
  let range = @core.NumericRange::between(10.0, 20.0)
  inspect(range.matches(9.99), content="false")
  inspect(range.matches(10.0), content="true")  // Lower bound inclusive
  inspect(range.matches(15.0), content="true")
  inspect(range.matches(20.0), content="true")  // Upper bound inclusive
  inspect(range.matches(20.01), content="false")
}

///|
/// Test: NumericRange.between (exclusive bounds)
test "meta/range/between_exclusive" {
  let range = @core.NumericRange::between(10.0, 20.0, lower_inclusive=false, upper_inclusive=false)
  inspect(range.matches(10.0), content="false")  // Lower exclusive
  inspect(range.matches(10.001), content="true")
  inspect(range.matches(15.0), content="true")
  inspect(range.matches(19.999), content="true")
  inspect(range.matches(20.0), content="false")  // Upper exclusive
}

///|
/// Test: NumericRange.empty (no bounds)
test "meta/range/empty" {
  let range = @core.NumericRange::empty()
  inspect(range.matches(-1000000.0), content="true")
  inspect(range.matches(0.0), content="true")
  inspect(range.matches(1000000.0), content="true")
}

// =============================================================================
// Section 3: FilterExpr Leaf Tests
// =============================================================================

///|
/// Test: FilterExpr.match_ with various types
test "meta/filter/match_types" {
  let db = @vcdb.VectorDB::with_dim(2)

  // Add vector with various attr types
  let attrs = @core.empty_attrs()
  attrs.set("str", @core.String("hello"))
  attrs.set("num", @core.Int(42L))
  attrs.set("flag", @core.Bool(true))
  attrs.set("score", @core.Float(3.14))
  db.add(@core.VectorId::from_int(1), [1.0, 0.0], attrs)

  // Add another vector for comparison
  let attrs2 = @core.empty_attrs()
  attrs2.set("str", @core.String("world"))
  attrs2.set("num", @core.Int(99L))
  db.add(@core.VectorId::from_int(2), [0.0, 1.0], attrs2)

  // Match string
  let filter_str = @filter.compile_filter(@filter.FilterExpr::match_("str", @core.String("hello")))
  inspect(filter_str(@core.VectorId::from_int(1), attrs), content="true")
  inspect(filter_str(@core.VectorId::from_int(2), attrs2), content="false")

  // Match int
  let filter_int = @filter.compile_filter(@filter.FilterExpr::match_("num", @core.Int(42L)))
  inspect(filter_int(@core.VectorId::from_int(1), attrs), content="true")
  inspect(filter_int(@core.VectorId::from_int(2), attrs2), content="false")

  // Match bool
  let filter_bool = @filter.compile_filter(@filter.FilterExpr::match_("flag", @core.Bool(true)))
  inspect(filter_bool(@core.VectorId::from_int(1), attrs), content="true")
}

///|
/// Test: FilterExpr.exists
test "meta/filter/exists" {
  let attrs1 = @core.empty_attrs()
  attrs1.set("name", @core.String("test"))
  attrs1.set("value", @core.Null)  // Null doesn't count as "exists"

  let attrs2 = @core.empty_attrs()
  // No "name" key

  let filter = @filter.compile_filter(@filter.FilterExpr::exists("name"))
  inspect(filter(@core.VectorId::from_int(1), attrs1), content="true")
  inspect(filter(@core.VectorId::from_int(2), attrs2), content="false")

  // Null value should NOT pass exists
  let filter_value = @filter.compile_filter(@filter.FilterExpr::exists("value"))
  inspect(filter_value(@core.VectorId::from_int(1), attrs1), content="false")
}

///|
/// Test: FilterExpr.is_null
test "meta/filter/is_null" {
  let attrs1 = @core.empty_attrs()
  attrs1.set("value", @core.Null)

  let attrs2 = @core.empty_attrs()
  attrs2.set("value", @core.Int(42L))

  let attrs3 = @core.empty_attrs()  // No "value" key at all

  let filter = @filter.compile_filter(@filter.FilterExpr::is_null("value"))
  inspect(filter(@core.VectorId::from_int(1), attrs1), content="true")   // Explicit null
  inspect(filter(@core.VectorId::from_int(2), attrs2), content="false")  // Has value
  inspect(filter(@core.VectorId::from_int(3), attrs3), content="true")   // Missing = null
}

///|
/// Test: FilterExpr.range
test "meta/filter/range" {
  let attrs = @core.empty_attrs()
  attrs.set("score", @core.Int(75L))

  // score >= 70 AND score <= 80
  let range = @core.NumericRange::between(70.0, 80.0)
  let filter = @filter.compile_filter(@filter.FilterExpr::range("score", range))
  inspect(filter(@core.VectorId::from_int(1), attrs), content="true")

  // score > 80
  let range_fail = @core.NumericRange::gt(80.0)
  let filter_fail = @filter.compile_filter(@filter.FilterExpr::range("score", range_fail))
  inspect(filter_fail(@core.VectorId::from_int(1), attrs), content="false")
}

///|
/// Test: FilterExpr.range with Float value
test "meta/filter/range_float" {
  let attrs = @core.empty_attrs()
  attrs.set("price", @core.Float(19.99))

  let range = @core.NumericRange::between(10.0, 20.0)
  let filter = @filter.compile_filter(@filter.FilterExpr::range("price", range))
  inspect(filter(@core.VectorId::from_int(1), attrs), content="true")
}

// =============================================================================
// Section 4: FilterExpr Compound Tests (Must/MustNot/Should)
// =============================================================================

///|
/// Test: Must (AND) - all conditions must match
test "meta/filter/must_all_match" {
  let attrs = @core.empty_attrs()
  attrs.set("active", @core.Bool(true))
  attrs.set("score", @core.Int(90L))
  attrs.set("category", @core.String("A"))

  let expr = @filter.FilterExpr::must([
    @filter.FilterExpr::match_("active", @core.Bool(true)),
    @filter.FilterExpr::range("score", @core.NumericRange::gte(80.0)),
    @filter.FilterExpr::match_("category", @core.String("A")),
  ])

  let filter = @filter.compile_filter(expr)
  inspect(filter(@core.VectorId::from_int(1), attrs), content="true")
}

///|
/// Test: Must (AND) - one condition fails
test "meta/filter/must_one_fails" {
  let attrs = @core.empty_attrs()
  attrs.set("active", @core.Bool(true))
  attrs.set("score", @core.Int(70L))  // Below threshold
  attrs.set("category", @core.String("A"))

  let expr = @filter.FilterExpr::must([
    @filter.FilterExpr::match_("active", @core.Bool(true)),
    @filter.FilterExpr::range("score", @core.NumericRange::gte(80.0)),  // Fails
    @filter.FilterExpr::match_("category", @core.String("A")),
  ])

  let filter = @filter.compile_filter(expr)
  inspect(filter(@core.VectorId::from_int(1), attrs), content="false")
}

///|
/// Test: MustNot (AND NOT) - none can match
test "meta/filter/must_not" {
  let attrs = @core.empty_attrs()
  attrs.set("status", @core.String("active"))
  attrs.set("type", @core.String("premium"))

  // NOT (status="deleted" OR type="banned")
  let expr = @filter.FilterExpr::must_not([
    @filter.FilterExpr::match_("status", @core.String("deleted")),
    @filter.FilterExpr::match_("type", @core.String("banned")),
  ])

  let filter = @filter.compile_filter(expr)
  inspect(filter(@core.VectorId::from_int(1), attrs), content="true")  // Neither matches

  // Now test with a matching condition
  let attrs_deleted = @core.empty_attrs()
  attrs_deleted.set("status", @core.String("deleted"))
  attrs_deleted.set("type", @core.String("premium"))
  inspect(filter(@core.VectorId::from_int(2), attrs_deleted), content="false")  // status matches
}

///|
/// Test: Should (OR) - at least one must match
test "meta/filter/should_or" {
  let attrs = @core.empty_attrs()
  attrs.set("category", @core.String("B"))

  let expr = @filter.FilterExpr::should([
    @filter.FilterExpr::match_("category", @core.String("A")),
    @filter.FilterExpr::match_("category", @core.String("B")),
    @filter.FilterExpr::match_("category", @core.String("C")),
  ], min=1)

  let filter = @filter.compile_filter(expr)
  inspect(filter(@core.VectorId::from_int(1), attrs), content="true")  // B matches
}

///|
/// Test: Should with min=2 - at least 2 must match
test "meta/filter/should_min2" {
  let attrs1 = @core.empty_attrs()
  attrs1.set("tag1", @core.Bool(true))
  attrs1.set("tag2", @core.Bool(true))
  attrs1.set("tag3", @core.Bool(false))

  let attrs2 = @core.empty_attrs()
  attrs2.set("tag1", @core.Bool(true))
  attrs2.set("tag2", @core.Bool(false))
  attrs2.set("tag3", @core.Bool(false))

  let expr = @filter.FilterExpr::should([
    @filter.FilterExpr::match_("tag1", @core.Bool(true)),
    @filter.FilterExpr::match_("tag2", @core.Bool(true)),
    @filter.FilterExpr::match_("tag3", @core.Bool(true)),
  ], min=2)

  let filter = @filter.compile_filter(expr)
  inspect(filter(@core.VectorId::from_int(1), attrs1), content="true")   // 2 match
  inspect(filter(@core.VectorId::from_int(2), attrs2), content="false")  // Only 1 matches
}

///|
/// Test: Nested compound expressions
test "meta/filter/nested_compound" {
  let attrs = @core.empty_attrs()
  attrs.set("status", @core.String("active"))
  attrs.set("tier", @core.String("gold"))
  attrs.set("score", @core.Int(85L))

  // (status="active" AND tier="gold") OR score >= 90
  let expr = @filter.FilterExpr::should([
    @filter.FilterExpr::must([
      @filter.FilterExpr::match_("status", @core.String("active")),
      @filter.FilterExpr::match_("tier", @core.String("gold")),
    ]),
    @filter.FilterExpr::range("score", @core.NumericRange::gte(90.0)),
  ], min=1)

  let filter = @filter.compile_filter(expr)
  inspect(filter(@core.VectorId::from_int(1), attrs), content="true")  // First branch matches

  // Test second branch
  let attrs2 = @core.empty_attrs()
  attrs2.set("status", @core.String("inactive"))
  attrs2.set("tier", @core.String("silver"))
  attrs2.set("score", @core.Int(95L))  // High score
  inspect(filter(@core.VectorId::from_int(2), attrs2), content="true")  // Second branch matches

  // Neither branch
  let attrs3 = @core.empty_attrs()
  attrs3.set("status", @core.String("inactive"))
  attrs3.set("tier", @core.String("silver"))
  attrs3.set("score", @core.Int(50L))
  inspect(filter(@core.VectorId::from_int(3), attrs3), content="false")
}

///|
/// Test: Deeply nested expression
test "meta/filter/deeply_nested" {
  let attrs = @core.empty_attrs()
  attrs.set("a", @core.Bool(true))
  attrs.set("b", @core.Bool(true))
  attrs.set("c", @core.Bool(false))
  attrs.set("d", @core.Int(50L))

  // ((a AND b) OR c) AND NOT (d > 100)
  let expr = @filter.FilterExpr::must([
    @filter.FilterExpr::should([
      @filter.FilterExpr::must([
        @filter.FilterExpr::match_("a", @core.Bool(true)),
        @filter.FilterExpr::match_("b", @core.Bool(true)),
      ]),
      @filter.FilterExpr::match_("c", @core.Bool(true)),
    ], min=1),
    @filter.FilterExpr::must_not([
      @filter.FilterExpr::range("d", @core.NumericRange::gt(100.0)),
    ]),
  ])

  let filter = @filter.compile_filter(expr)
  inspect(filter(@core.VectorId::from_int(1), attrs), content="true")
}

// =============================================================================
// Section 5: BasicAttrIndex Tests
// =============================================================================

///|
/// Test: BasicAttrIndex set and get
test "meta/index/basic_set_get" {
  let index = @attr.BasicAttrIndex::new()

  let id1 = @core.VectorId::from_int(1)
  let attrs1 = @core.empty_attrs()
  attrs1.set("name", @core.String("alice"))
  attrs1.set("age", @core.Int(30L))

  index.set_attrs(id1, attrs1)

  let retrieved = index.get_attrs(id1)
  match retrieved {
    Some(a) => {
      match a.get("name") {
        Some(@core.String(s)) => inspect(s, content="alice")
        _ => inspect(false, content="true")
      }
    }
    None => inspect(false, content="true")
  }
}

///|
/// Test: BasicAttrIndex equality lookup
test "meta/index/basic_eq" {
  let index = @attr.BasicAttrIndex::new()

  // Add multiple items with same category
  for i in 1..<=5 {
    let attrs = @core.empty_attrs()
    attrs.set("category", @core.String("A"))
    index.set_attrs(@core.VectorId::from_int(i), attrs)
  }
  for i in 6..<=10 {
    let attrs = @core.empty_attrs()
    attrs.set("category", @core.String("B"))
    index.set_attrs(@core.VectorId::from_int(i), attrs)
  }

  let cat_a = index.eq("category", @core.String("A"))
  let cat_b = index.eq("category", @core.String("B"))
  let cat_c = index.eq("category", @core.String("C"))

  inspect(cat_a.length(), content="5")
  inspect(cat_b.length(), content="5")
  inspect(cat_c.length(), content="0")
}

///|
/// Test: BasicAttrIndex exists lookup
test "meta/index/basic_exists" {
  let index = @attr.BasicAttrIndex::new()

  let attrs1 = @core.empty_attrs()
  attrs1.set("name", @core.String("test"))
  attrs1.set("optional", @core.Int(1L))

  let attrs2 = @core.empty_attrs()
  attrs2.set("name", @core.String("test2"))
  // No "optional" key

  index.set_attrs(@core.VectorId::from_int(1), attrs1)
  index.set_attrs(@core.VectorId::from_int(2), attrs2)

  let has_optional = index.exists("optional")
  let has_name = index.exists("name")
  let has_missing = index.exists("missing")

  inspect(has_optional.length(), content="1")
  inspect(has_name.length(), content="2")
  inspect(has_missing.length(), content="0")
}

///|
/// Test: BasicAttrIndex range query
test "meta/index/basic_range" {
  let index = @attr.BasicAttrIndex::new()

  for i in 1..<=100 {
    let attrs = @core.empty_attrs()
    attrs.set("score", @core.Int(i.to_int64()))
    index.set_attrs(@core.VectorId::from_int(i), attrs)
  }

  // Range: score >= 50 AND score <= 60
  let range = @core.NumericRange::between(50.0, 60.0)
  let results = index.range("score", range)

  match results {
    Some(ids) => inspect(ids.length(), content="11")  // 50, 51, ..., 60
    None => inspect(false, content="true")
  }
}

///|
/// Test: BasicAttrIndex remove
test "meta/index/basic_remove" {
  let index = @attr.BasicAttrIndex::new()

  let attrs = @core.empty_attrs()
  attrs.set("tag", @core.String("test"))

  let id = @core.VectorId::from_int(1)
  index.set_attrs(id, attrs)

  inspect(index.size(), content="1")
  inspect(index.eq("tag", @core.String("test")).length(), content="1")

  index.remove_id(id)

  inspect(index.size(), content="0")
  inspect(index.eq("tag", @core.String("test")).length(), content="0")
}

///|
/// Test: BasicAttrIndex update (replace attrs)
test "meta/index/basic_update" {
  let index = @attr.BasicAttrIndex::new()
  let id = @core.VectorId::from_int(1)

  // Initial attrs
  let attrs1 = @core.empty_attrs()
  attrs1.set("status", @core.String("pending"))
  index.set_attrs(id, attrs1)

  inspect(index.eq("status", @core.String("pending")).length(), content="1")
  inspect(index.eq("status", @core.String("active")).length(), content="0")

  // Update attrs
  let attrs2 = @core.empty_attrs()
  attrs2.set("status", @core.String("active"))
  index.set_attrs(id, attrs2)

  inspect(index.eq("status", @core.String("pending")).length(), content="0")
  inspect(index.eq("status", @core.String("active")).length(), content="1")
}

// =============================================================================
// Section 6: PreFilter vs PostFilter Integration Tests
// =============================================================================

///|
/// Test: PreFilter search with index
test "meta/strategy/prefilter" {
  let db = @vcdb.VectorDB::with_dim(2)
  let index = @attr.BasicAttrIndex::new()

  // Add 100 vectors, 20% in category "rare"
  for i in 1..<=100 {
    let attrs = @core.empty_attrs()
    let category = if i <= 20 { "rare" } else { "common" }
    attrs.set("category", @core.String(category))
    attrs.set("id", @core.Int(i.to_int64()))

    let id = @core.VectorId::from_int(i)
    db.add(id, [i.to_double() / 100.0, 1.0 - i.to_double() / 100.0], attrs)
    index.set_attrs(id, attrs)
  }

  // PreFilter: only "rare" category
  let expr = @filter.FilterExpr::match_("category", @core.String("rare"))
  let results = db.search_with_expr(
    [0.5, 0.5],
    10,
    Some(expr),
    Some(index),
    @filter.PreFilter,
  )

  // Should get at most 10 results from rare (20 total rare)
  inspect(results.length() <= 10, content="true")

  // All results should be rare
  for hit in results {
    match hit.attrs.get("category") {
      Some(@core.String(s)) => inspect(s, content="rare")
      _ => inspect(false, content="true")
    }
  }
}

///|
/// Test: PostFilter search
test "meta/strategy/postfilter" {
  let db = @vcdb.VectorDB::with_dim(2)

  for i in 1..<=50 {
    let attrs = @core.empty_attrs()
    attrs.set("even", @core.Bool(i % 2 == 0))
    db.add(
      @core.VectorId::from_int(i),
      [i.to_double() / 50.0, 1.0 - i.to_double() / 50.0],
      attrs,
    )
  }

  // PostFilter: only even IDs
  let expr = @filter.FilterExpr::match_("even", @core.Bool(true))
  let results = db.search_with_expr(
    [1.0, 0.0],
    10,
    Some(expr),
    None,  // No index, will use post-filter
    @filter.PostFilter,
  )

  // All results should have even=true
  for hit in results {
    match hit.attrs.get("even") {
      Some(@core.Bool(b)) => inspect(b, content="true")
      _ => inspect(false, content="true")
    }
  }
}

///|
/// Test: Auto strategy chooses correctly
test "meta/strategy/auto" {
  let db = @vcdb.VectorDB::with_dim(2)
  let index = @attr.BasicAttrIndex::new()

  // Add 100 vectors, only 5 with rare=true
  for i in 1..<=100 {
    let attrs = @core.empty_attrs()
    let is_rare = i <= 5
    attrs.set("rare", @core.Bool(is_rare))

    let id = @core.VectorId::from_int(i)
    db.add(id, [i.to_double() / 100.0, 1.0 - i.to_double() / 100.0], attrs)
    index.set_attrs(id, attrs)
  }

  // Auto should choose PreFilter (5% selectivity < 50%)
  let expr = @filter.FilterExpr::match_("rare", @core.Bool(true))
  let results = db.search_with_expr(
    [0.5, 0.5],
    10,
    Some(expr),
    Some(index),
    @filter.Auto,
  )

  // Should find all 5 rare items
  inspect(results.length(), content="5")
}

///|
/// Test: Prefilter and Postfilter return same results
test "meta/strategy/consistency" {
  let db = @vcdb.VectorDB::with_dim(2)
  let index = @attr.BasicAttrIndex::new()

  for i in 1..<=30 {
    let attrs = @core.empty_attrs()
    attrs.set("group", @core.String(if i <= 10 { "A" } else if i <= 20 { "B" } else { "C" }))

    let id = @core.VectorId::from_int(i)
    db.add(id, [i.to_double() / 30.0, 1.0 - i.to_double() / 30.0], attrs)
    index.set_attrs(id, attrs)
  }

  let expr = @filter.FilterExpr::match_("group", @core.String("B"))
  let query = [0.5, 0.5]

  let pre_results = db.search_with_expr(query, 5, Some(expr), Some(index), @filter.PreFilter)
  let post_results = db.search_with_expr(query, 5, Some(expr), None, @filter.PostFilter)

  // Same number of results
  inspect(pre_results.length() == post_results.length(), content="true")

  // Same IDs (may be in different order if scores are equal)
  let pre_ids : Array[Int64] = pre_results.iter().map(fn(h) { h.id.to_int64() }).collect()
  let post_ids : Array[Int64] = post_results.iter().map(fn(h) { h.id.to_int64() }).collect()

  // Sort and compare
  pre_ids.sort()
  post_ids.sort()
  let mut same = true
  for i in 0..<pre_ids.length() {
    if pre_ids[i] != post_ids[i] {
      same = false
      break
    }
  }
  inspect(same, content="true")
}

// =============================================================================
// Section 7: Complex Filter with Search Integration
// =============================================================================

///|
/// Test: Multi-attribute filter with vector search
test "meta/integration/multi_attr_search" {
  let db = @vcdb.VectorDB::with_dim(3)
  let index = @attr.BasicAttrIndex::new()

  // E-commerce products
  let products = [
    (1, "iPhone 15", "electronics", 999.0, true),
    (2, "Galaxy S24", "electronics", 899.0, true),
    (3, "Pixel 8", "electronics", 699.0, false),  // Out of stock
    (4, "MacBook Pro", "electronics", 2499.0, true),
    (5, "T-Shirt", "clothing", 29.0, true),
    (6, "Jeans", "clothing", 79.0, true),
    (7, "Sneakers", "footwear", 149.0, true),
    (8, "Boots", "footwear", 199.0, false),  // Out of stock
  ]

  for product in products {
    let (id, name, category, price, in_stock) = product
    let attrs = @core.empty_attrs()
    attrs.set("name", @core.String(name))
    attrs.set("category", @core.String(category))
    attrs.set("price", @core.Float(price))
    attrs.set("in_stock", @core.Bool(in_stock))

    // Vector based on category (electronics=high x, clothing=high y, footwear=high z)
    let vec = match category {
      "electronics" => [0.9, 0.1, 0.0]
      "clothing" => [0.1, 0.9, 0.0]
      _ => [0.1, 0.1, 0.8]
    }

    let vid = @core.VectorId::from_int(id)
    db.add(vid, vec, attrs)
    index.set_attrs(vid, attrs)
  }

  // Find: electronics, price <= 1000, in_stock
  let expr = @filter.FilterExpr::must([
    @filter.FilterExpr::match_("category", @core.String("electronics")),
    @filter.FilterExpr::range("price", @core.NumericRange::lte(1000.0)),
    @filter.FilterExpr::match_("in_stock", @core.Bool(true)),
  ])

  let results = db.search_with_expr(
    [1.0, 0.0, 0.0],  // Looking for electronics
    10,
    Some(expr),
    Some(index),
    @filter.PreFilter,
  )

  // Should find iPhone and Galaxy (Pixel is out of stock, MacBook too expensive)
  inspect(results.length(), content="2")

  let names : Array[String] = []
  for hit in results {
    match hit.attrs.get("name") {
      Some(@core.String(s)) => names.push(s)
      _ => ()
    }
  }
  inspect(names.contains("iPhone 15"), content="true")
  inspect(names.contains("Galaxy S24"), content="true")
}

///|
/// Test: Should filter with prefilter
test "meta/integration/should_prefilter" {
  let db = @vcdb.VectorDB::with_dim(2)
  let index = @attr.BasicAttrIndex::new()

  for i in 1..<=30 {
    let attrs = @core.empty_attrs()
    let tag = match i % 3 {
      0 => "red"
      1 => "green"
      _ => "blue"
    }
    attrs.set("color", @core.String(tag))

    let id = @core.VectorId::from_int(i)
    db.add(id, [i.to_double() / 30.0, 1.0 - i.to_double() / 30.0], attrs)
    index.set_attrs(id, attrs)
  }

  // color = "red" OR color = "blue"
  let expr = @filter.FilterExpr::should([
    @filter.FilterExpr::match_("color", @core.String("red")),
    @filter.FilterExpr::match_("color", @core.String("blue")),
  ], min=1)

  let results = db.search_with_expr(
    [0.5, 0.5],
    20,
    Some(expr),
    Some(index),
    @filter.PreFilter,
  )

  // 30 items: 10 red, 10 green, 10 blue. Should find 20 (red + blue)
  inspect(results.length(), content="20")

  for hit in results {
    match hit.attrs.get("color") {
      Some(@core.String(s)) => inspect(s == "red" || s == "blue", content="true")
      _ => inspect(false, content="true")
    }
  }
}

// =============================================================================
// Section 8: Serialization with Metadata
// =============================================================================

///|
/// Test: Serialize/deserialize preserves all attr types
test "meta/serialize/all_types" {
  let db = @vcdb.VectorDB::with_dim(2)

  let attrs = @core.empty_attrs()
  attrs.set("null_val", @core.Null)
  attrs.set("bool_val", @core.Bool(true))
  attrs.set("int_val", @core.Int(12345L))
  attrs.set("float_val", @core.Float(3.14159))
  attrs.set("string_val", @core.String("hello world"))

  db.add(@core.VectorId::from_int(1), [1.0, 0.0], attrs)

  // Serialize
  let bytes = db.serialize()

  // Deserialize
  let db2 = @vcdb.VectorDB::deserialize(bytes)
  let record = db2.get(@core.VectorId::from_int(1)).unwrap()
  let a = record.attrs

  match a.get("null_val") {
    Some(@core.Null) => inspect(true, content="true")
    _ => inspect(false, content="true")
  }
  match a.get("bool_val") {
    Some(@core.Bool(b)) => inspect(b, content="true")
    _ => inspect(false, content="true")
  }
  match a.get("int_val") {
    Some(@core.Int(n)) => inspect(n, content="12345")
    _ => inspect(false, content="true")
  }
  match a.get("float_val") {
    Some(@core.Float(f)) => inspect((f - 3.14159).abs() < 0.00001, content="true")
    _ => inspect(false, content="true")
  }
  match a.get("string_val") {
    Some(@core.String(s)) => inspect(s, content="hello world")
    _ => inspect(false, content="true")
  }
}

///|
/// Test: Serialize/deserialize with many attrs per vector
test "meta/serialize/many_attrs" {
  let db = @vcdb.VectorDB::with_dim(2)

  let attrs = @core.empty_attrs()
  for i in 0..<50 {
    attrs.set("key_\{i}", @core.Int(i.to_int64()))
  }

  db.add(@core.VectorId::from_int(1), [1.0, 0.0], attrs)

  let bytes = db.serialize()
  let db2 = @vcdb.VectorDB::deserialize(bytes)

  let record = db2.get(@core.VectorId::from_int(1)).unwrap()
  inspect(record.attrs.size(), content="50")

  match record.attrs.get("key_25") {
    Some(@core.Int(n)) => inspect(n, content="25")
    _ => inspect(false, content="true")
  }
}

// =============================================================================
// Section 9: Edge Cases
// =============================================================================

///|
/// Test: Empty attrs
test "meta/edge/empty_attrs" {
  let db = @vcdb.VectorDB::with_dim(2)
  db.add(@core.VectorId::from_int(1), [1.0, 0.0], @core.empty_attrs())

  let record = db.get(@core.VectorId::from_int(1)).unwrap()
  inspect(record.attrs.is_empty(), content="true")
  inspect(record.attrs.size(), content="0")
}

///|
/// Test: Very long string attr
test "meta/edge/long_string" {
  let db = @vcdb.VectorDB::with_dim(2)

  // Create a 10000 character string
  let mut long_str = ""
  for _ in 0..<1000 {
    long_str = long_str + "0123456789"
  }

  let attrs = @core.empty_attrs()
  attrs.set("long", @core.String(long_str))

  db.add(@core.VectorId::from_int(1), [1.0, 0.0], attrs)

  let record = db.get(@core.VectorId::from_int(1)).unwrap()
  match record.attrs.get("long") {
    Some(@core.String(s)) => inspect(s.length(), content="10000")
    _ => inspect(false, content="true")
  }
}

///|
/// Test: Special characters in attr key and value
test "meta/edge/special_chars" {
  let db = @vcdb.VectorDB::with_dim(2)

  let attrs = @core.empty_attrs()
  attrs.set("key with spaces", @core.String("value with spaces"))
  attrs.set("key.with.dots", @core.String("dots.in.value"))
  attrs.set("key:colon", @core.String("colon:value"))
  attrs.set("emoji_key", @core.String("🎉🚀💯"))

  db.add(@core.VectorId::from_int(1), [1.0, 0.0], attrs)

  let record = db.get(@core.VectorId::from_int(1)).unwrap()

  match record.attrs.get("key with spaces") {
    Some(@core.String(s)) => inspect(s, content="value with spaces")
    _ => inspect(false, content="true")
  }
  match record.attrs.get("emoji_key") {
    Some(@core.String(s)) => inspect(s, content="🎉🚀💯")
    _ => inspect(false, content="true")
  }
}

///|
/// Test: Filter on non-existent attribute key
test "meta/edge/filter_missing_key" {
  let db = @vcdb.VectorDB::with_dim(2)

  let attrs = @core.empty_attrs()
  attrs.set("existing", @core.String("value"))
  db.add(@core.VectorId::from_int(1), [1.0, 0.0], attrs)

  // Filter for non-existent key
  let filter = @filter.compile_filter(@filter.FilterExpr::match_("nonexistent", @core.String("any")))
  inspect(filter(@core.VectorId::from_int(1), attrs), content="false")
}

///|
/// Test: Range query on non-numeric attribute
test "meta/edge/range_on_string" {
  let attrs = @core.empty_attrs()
  attrs.set("name", @core.String("test"))  // Not numeric

  let range = @core.NumericRange::gte(0.0)
  let filter = @filter.compile_filter(@filter.FilterExpr::range("name", range))
  inspect(filter(@core.VectorId::from_int(1), attrs), content="false")
}

///|
/// Test: Large number of attrs in index
test "meta/edge/large_index" {
  let index = @attr.BasicAttrIndex::new()

  // Add 1000 items
  for i in 1..<=1000 {
    let attrs = @core.empty_attrs()
    attrs.set("id", @core.Int(i.to_int64()))
    attrs.set("mod10", @core.Int((i % 10).to_int64()))
    attrs.set("mod100", @core.Int((i % 100).to_int64()))

    index.set_attrs(@core.VectorId::from_int(i), attrs)
  }

  inspect(index.size(), content="1000")

  // Query: mod10 = 5
  let results = index.eq("mod10", @core.Int(5L))
  inspect(results.length(), content="100")  // 5, 15, 25, ..., 995

  // Range: id between 500 and 510
  let range = @core.NumericRange::between(500.0, 510.0)
  match index.range("id", range) {
    Some(ids) => inspect(ids.length(), content="11")
    None => inspect(false, content="true")
  }
}
