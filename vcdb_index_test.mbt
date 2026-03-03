// Comprehensive Index Tests for Bitmap, B+Tree, and LSM indexes
// Tests all index implementations beyond BasicAttrIndex

// =============================================================================
// Section 1: BitmapAttrIndex Tests
// =============================================================================

///|
/// Test: BitmapAttrIndex basic set and get
test "index/bitmap/set_get" {
  let index = @attr.BitmapAttrIndex::new()

  let id = @core.VectorId::from_int(1)
  let attrs = @core.empty_attrs()
  attrs.set("name", @core.String("test"))
  attrs.set("count", @core.Int(42L))

  index.set_attrs(id, attrs)

  match index.get_attrs(id) {
    Some(a) => {
      match a.get("name") {
        Some(@core.String(s)) => inspect(s, content="test")
        _ => inspect(false, content="true")
      }
      match a.get("count") {
        Some(@core.Int(n)) => inspect(n, content="42")
        _ => inspect(false, content="true")
      }
    }
    None => inspect(false, content="true")
  }
}

///|
/// Test: BitmapAttrIndex equality lookup
test "index/bitmap/eq" {
  let index = @attr.BitmapAttrIndex::new()

  // Add items with categories (low cardinality - perfect for bitmap)
  for i in 1..<=10 {
    let attrs = @core.empty_attrs()
    let category = if i <= 3 { "A" } else if i <= 7 { "B" } else { "C" }
    attrs.set("category", @core.String(category))
    index.set_attrs(@core.VectorId::from_int(i), attrs)
  }

  inspect(index.eq("category", @core.String("A")).length(), content="3")
  inspect(index.eq("category", @core.String("B")).length(), content="4")
  inspect(index.eq("category", @core.String("C")).length(), content="3")
  inspect(index.eq("category", @core.String("D")).length(), content="0")
}

///|
/// Test: BitmapAttrIndex exists lookup
test "index/bitmap/exists" {
  let index = @attr.BitmapAttrIndex::new()

  let attrs1 = @core.empty_attrs()
  attrs1.set("required", @core.String("yes"))
  attrs1.set("optional", @core.Int(1L))

  let attrs2 = @core.empty_attrs()
  attrs2.set("required", @core.String("yes"))
  // No "optional" key

  index.set_attrs(@core.VectorId::from_int(1), attrs1)
  index.set_attrs(@core.VectorId::from_int(2), attrs2)

  inspect(index.exists("required").length(), content="2")
  inspect(index.exists("optional").length(), content="1")
  inspect(index.exists("missing").length(), content="0")
}

///|
/// Test: BitmapAttrIndex range not supported
test "index/bitmap/range_not_supported" {
  let index = @attr.BitmapAttrIndex::new()

  let attrs = @core.empty_attrs()
  attrs.set("score", @core.Int(50L))
  index.set_attrs(@core.VectorId::from_int(1), attrs)

  let range = @core.NumericRange::gte(0.0)
  let result = index.range("score", range)

  // Should return None (not supported)
  inspect(result is None, content="true")
}

///|
/// Test: BitmapAttrIndex remove
test "index/bitmap/remove" {
  let index = @attr.BitmapAttrIndex::new()

  let attrs = @core.empty_attrs()
  attrs.set("tag", @core.String("test"))

  let id = @core.VectorId::from_int(1)
  index.set_attrs(id, attrs)

  inspect(index.size(), content="1")
  inspect(index.eq("tag", @core.String("test")).length(), content="1")

  index.remove_id(id)

  inspect(index.size(), content="0")
  inspect(index.eq("tag", @core.String("test")).length(), content="0")
  inspect(index.get_attrs(id) is None, content="true")
}

///|
/// Test: BitmapAttrIndex update (replace attrs)
test "index/bitmap/update" {
  let index = @attr.BitmapAttrIndex::new()
  let id = @core.VectorId::from_int(1)

  // Initial attrs
  let attrs1 = @core.empty_attrs()
  attrs1.set("status", @core.String("draft"))
  index.set_attrs(id, attrs1)

  inspect(index.eq("status", @core.String("draft")).length(), content="1")

  // Update attrs
  let attrs2 = @core.empty_attrs()
  attrs2.set("status", @core.String("published"))
  index.set_attrs(id, attrs2)

  // Old value should be removed from index
  inspect(index.eq("status", @core.String("draft")).length(), content="0")
  inspect(index.eq("status", @core.String("published")).length(), content="1")
}

///|
/// Test: BitmapAttrIndex with boolean values
test "index/bitmap/boolean_index" {
  let index = @attr.BitmapAttrIndex::new()

  for i in 1..<=20 {
    let attrs = @core.empty_attrs()
    attrs.set("active", @core.Bool(i % 2 == 0))
    attrs.set("premium", @core.Bool(i <= 5))
    index.set_attrs(@core.VectorId::from_int(i), attrs)
  }

  inspect(index.eq("active", @core.Bool(true)).length(), content="10")
  inspect(index.eq("active", @core.Bool(false)).length(), content="10")
  inspect(index.eq("premium", @core.Bool(true)).length(), content="5")
  inspect(index.eq("premium", @core.Bool(false)).length(), content="15")
}

///|
/// Test: BitmapAttrIndex size
test "index/bitmap/size" {
  let index = @attr.BitmapAttrIndex::new()

  inspect(index.size(), content="0")

  for i in 1..<=50 {
    let attrs = @core.empty_attrs()
    attrs.set("id", @core.Int(i.to_int64()))
    index.set_attrs(@core.VectorId::from_int(i), attrs)
  }

  inspect(index.size(), content="50")
}

// =============================================================================
// Section 2: BPTreeAttrIndex Tests
// =============================================================================

///|
/// Test: BPTreeAttrIndex basic set and get
test "index/bptree/set_get" {
  let index = @attr.BPTreeAttrIndex::new()

  let id = @core.VectorId::from_int(1)
  let attrs = @core.empty_attrs()
  attrs.set("name", @core.String("test"))
  attrs.set("score", @core.Int(100L))

  index.set_attrs(id, attrs)

  match index.get_attrs(id) {
    Some(a) => {
      match a.get("name") {
        Some(@core.String(s)) => inspect(s, content="test")
        _ => inspect(false, content="true")
      }
      match a.get("score") {
        Some(@core.Int(n)) => inspect(n, content="100")
        _ => inspect(false, content="true")
      }
    }
    None => inspect(false, content="true")
  }
}

///|
/// Test: BPTreeAttrIndex equality lookup
test "index/bptree/eq" {
  let index = @attr.BPTreeAttrIndex::new()

  // Add items
  for i in 1..<=20 {
    let attrs = @core.empty_attrs()
    let tier = if i <= 5 { "gold" } else if i <= 15 { "silver" } else { "bronze" }
    attrs.set("tier", @core.String(tier))
    index.set_attrs(@core.VectorId::from_int(i), attrs)
  }

  inspect(index.eq("tier", @core.String("gold")).length(), content="5")
  inspect(index.eq("tier", @core.String("silver")).length(), content="10")
  inspect(index.eq("tier", @core.String("bronze")).length(), content="5")
  inspect(index.eq("tier", @core.String("platinum")).length(), content="0")
}

///|
/// Test: BPTreeAttrIndex exists lookup
test "index/bptree/exists" {
  let index = @attr.BPTreeAttrIndex::new()

  let attrs1 = @core.empty_attrs()
  attrs1.set("field_a", @core.Int(1L))
  attrs1.set("field_b", @core.Int(2L))

  let attrs2 = @core.empty_attrs()
  attrs2.set("field_a", @core.Int(3L))
  // No field_b

  index.set_attrs(@core.VectorId::from_int(1), attrs1)
  index.set_attrs(@core.VectorId::from_int(2), attrs2)

  inspect(index.exists("field_a").length(), content="2")
  inspect(index.exists("field_b").length(), content="1")
  inspect(index.exists("field_c").length(), content="0")
}

///|
/// Test: BPTreeAttrIndex range query with integers
test "index/bptree/range_int" {
  let index = @attr.BPTreeAttrIndex::new()

  for i in 1..<=100 {
    let attrs = @core.empty_attrs()
    attrs.set("value", @core.Int(i.to_int64()))
    index.set_attrs(@core.VectorId::from_int(i), attrs)
  }

  // Range: value >= 50 AND value <= 60
  let range = @core.NumericRange::between(50.0, 60.0)
  match index.range("value", range) {
    Some(ids) => inspect(ids.length(), content="11")
    None => inspect(false, content="true")
  }
}

///|
/// Test: BPTreeAttrIndex range query with floats
test "index/bptree/range_float" {
  let index = @attr.BPTreeAttrIndex::new()

  for i in 1..<=50 {
    let attrs = @core.empty_attrs()
    attrs.set("price", @core.Float(i.to_double() * 0.5))  // 0.5, 1.0, 1.5, ...
    index.set_attrs(@core.VectorId::from_int(i), attrs)
  }

  // Range: price >= 10.0 AND price <= 15.0
  let range = @core.NumericRange::between(10.0, 15.0)
  match index.range("price", range) {
    Some(ids) => {
      // 10.0, 10.5, 11.0, ..., 15.0 = 11 values
      inspect(ids.length(), content="11")
    }
    None => inspect(false, content="true")
  }
}

///|
/// Test: BPTreeAttrIndex range with negative numbers
test "index/bptree/range_negative" {
  let index = @attr.BPTreeAttrIndex::new()

  for i in -10..<=10 {
    let attrs = @core.empty_attrs()
    attrs.set("temp", @core.Int(i.to_int64()))
    index.set_attrs(@core.VectorId::from_int(i + 100), attrs)
  }

  // Range: temp >= -5 AND temp <= 5
  let range = @core.NumericRange::between(-5.0, 5.0)
  match index.range("temp", range) {
    Some(ids) => inspect(ids.length(), content="11")  // -5 to 5 = 11
    None => inspect(false, content="true")
  }
}

///|
/// Test: BPTreeAttrIndex remove
test "index/bptree/remove" {
  let index = @attr.BPTreeAttrIndex::new()

  let attrs = @core.empty_attrs()
  attrs.set("key", @core.String("value"))
  attrs.set("num", @core.Int(42L))

  let id = @core.VectorId::from_int(1)
  index.set_attrs(id, attrs)

  inspect(index.size(), content="1")
  inspect(index.eq("key", @core.String("value")).length(), content="1")

  index.remove_id(id)

  inspect(index.size(), content="0")
  inspect(index.eq("key", @core.String("value")).length(), content="0")
  inspect(index.exists("num").length(), content="0")
}

///|
/// Test: BPTreeAttrIndex update
test "index/bptree/update" {
  let index = @attr.BPTreeAttrIndex::new()
  let id = @core.VectorId::from_int(1)

  let attrs1 = @core.empty_attrs()
  attrs1.set("version", @core.Int(1L))
  index.set_attrs(id, attrs1)

  inspect(index.eq("version", @core.Int(1L)).length(), content="1")

  let attrs2 = @core.empty_attrs()
  attrs2.set("version", @core.Int(2L))
  index.set_attrs(id, attrs2)

  inspect(index.eq("version", @core.Int(1L)).length(), content="0")
  inspect(index.eq("version", @core.Int(2L)).length(), content="1")
}

///|
/// Test: BPTreeAttrIndex with small order (more splitting)
test "index/bptree/small_order" {
  let index = @attr.BPTreeAttrIndex::new(order=4)

  // Add many items to trigger node operations
  for i in 1..<=100 {
    let attrs = @core.empty_attrs()
    attrs.set("id", @core.Int(i.to_int64()))
    index.set_attrs(@core.VectorId::from_int(i), attrs)
  }

  inspect(index.size(), content="100")

  // Verify lookups still work
  inspect(index.eq("id", @core.Int(50L)).length(), content="1")
  inspect(index.eq("id", @core.Int(999L)).length(), content="0")
}

///|
/// Test: BPTreeAttrIndex preserves order in encoding
test "index/bptree/order_preserving" {
  let index = @attr.BPTreeAttrIndex::new()

  // Add items with specific order
  let values = [-100L, -10L, -1L, 0L, 1L, 10L, 100L]
  for i, v in values.iter2() {
    let attrs = @core.empty_attrs()
    attrs.set("num", @core.Int(v))
    index.set_attrs(@core.VectorId::from_int(i), attrs)
  }

  // Each should be found
  for v in values {
    inspect(index.eq("num", @core.Int(v)).length(), content="1")
  }

  // Range should find correct subset
  let range = @core.NumericRange::between(-10.0, 10.0)
  match index.range("num", range) {
    Some(ids) => inspect(ids.length(), content="5")  // -10, -1, 0, 1, 10
    None => inspect(false, content="true")
  }
}

// =============================================================================
// Section 3: LSMAttrIndex Tests
// =============================================================================

///|
/// Test: LSMAttrIndex basic set and get
test "index/lsm/set_get" {
  let index = @attr.LSMAttrIndex::new()

  let id = @core.VectorId::from_int(1)
  let attrs = @core.empty_attrs()
  attrs.set("name", @core.String("test"))
  attrs.set("value", @core.Int(42L))

  index.set_attrs(id, attrs)

  match index.get_attrs(id) {
    Some(a) => {
      match a.get("name") {
        Some(@core.String(s)) => inspect(s, content="test")
        _ => inspect(false, content="true")
      }
      match a.get("value") {
        Some(@core.Int(n)) => inspect(n, content="42")
        _ => inspect(false, content="true")
      }
    }
    None => inspect(false, content="true")
  }
}

///|
/// Test: LSMAttrIndex equality lookup
test "index/lsm/eq" {
  let index = @attr.LSMAttrIndex::new()

  for i in 1..<=15 {
    let attrs = @core.empty_attrs()
    let status = if i <= 5 { "active" } else if i <= 10 { "pending" } else { "done" }
    attrs.set("status", @core.String(status))
    index.set_attrs(@core.VectorId::from_int(i), attrs)
  }

  inspect(index.eq("status", @core.String("active")).length(), content="5")
  inspect(index.eq("status", @core.String("pending")).length(), content="5")
  inspect(index.eq("status", @core.String("done")).length(), content="5")
  inspect(index.eq("status", @core.String("unknown")).length(), content="0")
}

///|
/// Test: LSMAttrIndex exists lookup
test "index/lsm/exists" {
  let index = @attr.LSMAttrIndex::new()

  let attrs1 = @core.empty_attrs()
  attrs1.set("a", @core.Int(1L))
  attrs1.set("b", @core.Int(2L))

  let attrs2 = @core.empty_attrs()
  attrs2.set("a", @core.Int(3L))

  index.set_attrs(@core.VectorId::from_int(1), attrs1)
  index.set_attrs(@core.VectorId::from_int(2), attrs2)

  inspect(index.exists("a").length(), content="2")
  inspect(index.exists("b").length(), content="1")
  inspect(index.exists("c").length(), content="0")
}

///|
/// Test: LSMAttrIndex range query
test "index/lsm/range" {
  let index = @attr.LSMAttrIndex::new()

  for i in 1..<=100 {
    let attrs = @core.empty_attrs()
    attrs.set("score", @core.Int(i.to_int64()))
    index.set_attrs(@core.VectorId::from_int(i), attrs)
  }

  // Range: score >= 40 AND score <= 50
  let range = @core.NumericRange::between(40.0, 50.0)
  match index.range("score", range) {
    Some(ids) => inspect(ids.length(), content="11")
    None => inspect(false, content="true")
  }
}

///|
/// Test: LSMAttrIndex remove
test "index/lsm/remove" {
  let index = @attr.LSMAttrIndex::new()

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
/// Test: LSMAttrIndex update
test "index/lsm/update" {
  let index = @attr.LSMAttrIndex::new()
  let id = @core.VectorId::from_int(1)

  let attrs1 = @core.empty_attrs()
  attrs1.set("state", @core.String("old"))
  index.set_attrs(id, attrs1)

  inspect(index.eq("state", @core.String("old")).length(), content="1")

  let attrs2 = @core.empty_attrs()
  attrs2.set("state", @core.String("new"))
  index.set_attrs(id, attrs2)

  inspect(index.eq("state", @core.String("old")).length(), content="0")
  inspect(index.eq("state", @core.String("new")).length(), content="1")
}

///|
/// Test: LSMAttrIndex memtable size tracking
test "index/lsm/memtable_size" {
  let index = @attr.LSMAttrIndex::new(flush_threshold=10)

  inspect(index.memtable_size(), content="0")
  inspect(index.should_flush(), content="false")

  for i in 1..<=5 {
    let attrs = @core.empty_attrs()
    attrs.set("key\{i}", @core.Int(i.to_int64()))
    index.set_attrs(@core.VectorId::from_int(i), attrs)
  }

  // Each unique key-value pair adds to memtable
  inspect(index.memtable_size() > 0, content="true")
}

///|
/// Test: LSMAttrIndex should_flush threshold
test "index/lsm/flush_threshold" {
  let index = @attr.LSMAttrIndex::new(flush_threshold=5)

  // Add many unique key-value pairs
  for i in 1..<=10 {
    let attrs = @core.empty_attrs()
    attrs.set("unique_key_\{i}", @core.String("value_\{i}"))
    index.set_attrs(@core.VectorId::from_int(i), attrs)
  }

  // Should eventually exceed threshold
  inspect(index.should_flush(), content="true")
}

///|
/// Test: LSMAttrIndex clear_memtable
test "index/lsm/clear_memtable" {
  let index = @attr.LSMAttrIndex::new()

  for i in 1..<=10 {
    let attrs = @core.empty_attrs()
    attrs.set("data", @core.Int(i.to_int64()))
    index.set_attrs(@core.VectorId::from_int(i), attrs)
  }

  inspect(index.memtable_size() > 0, content="true")

  index.clear_memtable()

  inspect(index.memtable_size(), content="0")

  // Data should still be accessible (stored separately)
  inspect(index.size(), content="10")
}

///|
/// Test: LSMAttrIndex with float values
test "index/lsm/float_values" {
  let index = @attr.LSMAttrIndex::new()

  let attrs = @core.empty_attrs()
  attrs.set("price", @core.Float(19.99))
  attrs.set("discount", @core.Float(0.15))

  index.set_attrs(@core.VectorId::from_int(1), attrs)

  inspect(index.eq("price", @core.Float(19.99)).length(), content="1")

  let range = @core.NumericRange::between(15.0, 25.0)
  match index.range("price", range) {
    Some(ids) => inspect(ids.length(), content="1")
    None => inspect(false, content="true")
  }
}

// =============================================================================
// Section 4: Cross-Index Comparison Tests
// =============================================================================

///|
/// Test: All indexes return same results for eq
test "index/compare/eq_consistency" {
  let basic = @attr.BasicAttrIndex::new()
  let bitmap = @attr.BitmapAttrIndex::new()
  let bptree = @attr.BPTreeAttrIndex::new()
  let lsm = @attr.LSMAttrIndex::new()

  // Add same data to all indexes
  for i in 1..<=20 {
    let attrs = @core.empty_attrs()
    let category = if i % 3 == 0 { "A" } else if i % 3 == 1 { "B" } else { "C" }
    attrs.set("cat", @core.String(category))

    let id = @core.VectorId::from_int(i)
    basic.set_attrs(id, attrs)
    bitmap.set_attrs(id, attrs)
    bptree.set_attrs(id, attrs)
    lsm.set_attrs(id, attrs)
  }

  // All should return same count
  let basic_count = basic.eq("cat", @core.String("A")).length()
  let bitmap_count = bitmap.eq("cat", @core.String("A")).length()
  let bptree_count = bptree.eq("cat", @core.String("A")).length()
  let lsm_count = lsm.eq("cat", @core.String("A")).length()

  inspect(basic_count, content="6")
  inspect(bitmap_count == basic_count, content="true")
  inspect(bptree_count == basic_count, content="true")
  inspect(lsm_count == basic_count, content="true")
}

///|
/// Test: All indexes return same results for exists
test "index/compare/exists_consistency" {
  let basic = @attr.BasicAttrIndex::new()
  let bitmap = @attr.BitmapAttrIndex::new()
  let bptree = @attr.BPTreeAttrIndex::new()
  let lsm = @attr.LSMAttrIndex::new()

  for i in 1..<=10 {
    let attrs = @core.empty_attrs()
    attrs.set("always", @core.Int(i.to_int64()))
    if i <= 5 {
      attrs.set("sometimes", @core.Bool(true))
    }

    let id = @core.VectorId::from_int(i)
    basic.set_attrs(id, attrs)
    bitmap.set_attrs(id, attrs)
    bptree.set_attrs(id, attrs)
    lsm.set_attrs(id, attrs)
  }

  // exists("always") should return 10 for all
  inspect(basic.exists("always").length(), content="10")
  inspect(bitmap.exists("always").length(), content="10")
  inspect(bptree.exists("always").length(), content="10")
  inspect(lsm.exists("always").length(), content="10")

  // exists("sometimes") should return 5 for all
  inspect(basic.exists("sometimes").length(), content="5")
  inspect(bitmap.exists("sometimes").length(), content="5")
  inspect(bptree.exists("sometimes").length(), content="5")
  inspect(lsm.exists("sometimes").length(), content="5")
}

///|
/// Test: Range queries across supporting indexes
test "index/compare/range_consistency" {
  let basic = @attr.BasicAttrIndex::new()
  let bptree = @attr.BPTreeAttrIndex::new()
  let lsm = @attr.LSMAttrIndex::new()
  // Note: Bitmap doesn't support range

  for i in 1..<=50 {
    let attrs = @core.empty_attrs()
    attrs.set("num", @core.Int(i.to_int64()))

    let id = @core.VectorId::from_int(i)
    basic.set_attrs(id, attrs)
    bptree.set_attrs(id, attrs)
    lsm.set_attrs(id, attrs)
  }

  let range = @core.NumericRange::between(20.0, 30.0)

  let basic_result = basic.range("num", range)
  let bptree_result = bptree.range("num", range)
  let lsm_result = lsm.range("num", range)

  // All should return 11 results (20-30 inclusive)
  match basic_result {
    Some(ids) => inspect(ids.length(), content="11")
    None => inspect(false, content="true")
  }
  match bptree_result {
    Some(ids) => inspect(ids.length(), content="11")
    None => inspect(false, content="true")
  }
  match lsm_result {
    Some(ids) => inspect(ids.length(), content="11")
    None => inspect(false, content="true")
  }
}

///|
/// Test: Remove consistency across indexes
test "index/compare/remove_consistency" {
  let basic = @attr.BasicAttrIndex::new()
  let bitmap = @attr.BitmapAttrIndex::new()
  let bptree = @attr.BPTreeAttrIndex::new()
  let lsm = @attr.LSMAttrIndex::new()

  // Add same data
  for i in 1..<=10 {
    let attrs = @core.empty_attrs()
    attrs.set("val", @core.Int(i.to_int64()))

    let id = @core.VectorId::from_int(i)
    basic.set_attrs(id, attrs)
    bitmap.set_attrs(id, attrs)
    bptree.set_attrs(id, attrs)
    lsm.set_attrs(id, attrs)
  }

  // Remove id=5 from all
  let id5 = @core.VectorId::from_int(5)
  basic.remove_id(id5)
  bitmap.remove_id(id5)
  bptree.remove_id(id5)
  lsm.remove_id(id5)

  // All should have size 9
  inspect(basic.size(), content="9")
  inspect(bitmap.size(), content="9")
  inspect(bptree.size(), content="9")
  inspect(lsm.size(), content="9")

  // eq for val=5 should return empty
  inspect(basic.eq("val", @core.Int(5L)).length(), content="0")
  inspect(bitmap.eq("val", @core.Int(5L)).length(), content="0")
  inspect(bptree.eq("val", @core.Int(5L)).length(), content="0")
  inspect(lsm.eq("val", @core.Int(5L)).length(), content="0")
}

// =============================================================================
// Section 5: Edge Cases
// =============================================================================

///|
/// Test: Empty index operations
test "index/edge/empty_operations" {
  let bitmap = @attr.BitmapAttrIndex::new()
  let bptree = @attr.BPTreeAttrIndex::new()
  let lsm = @attr.LSMAttrIndex::new()

  // All empty
  inspect(bitmap.size(), content="0")
  inspect(bptree.size(), content="0")
  inspect(lsm.size(), content="0")

  // eq on empty should return empty
  inspect(bitmap.eq("key", @core.String("val")).length(), content="0")
  inspect(bptree.eq("key", @core.String("val")).length(), content="0")
  inspect(lsm.eq("key", @core.String("val")).length(), content="0")

  // exists on empty should return empty
  inspect(bitmap.exists("key").length(), content="0")
  inspect(bptree.exists("key").length(), content="0")
  inspect(lsm.exists("key").length(), content="0")
}

///|
/// Test: Unicode keys and values in all indexes
test "index/edge/unicode" {
  let bitmap = @attr.BitmapAttrIndex::new()
  let bptree = @attr.BPTreeAttrIndex::new()
  let lsm = @attr.LSMAttrIndex::new()

  let attrs = @core.empty_attrs()
  attrs.set("名前", @core.String("田中太郎"))
  attrs.set("emoji", @core.String("🎉🚀"))

  let id = @core.VectorId::from_int(1)
  bitmap.set_attrs(id, attrs)
  bptree.set_attrs(id, attrs)
  lsm.set_attrs(id, attrs)

  // All should find the values
  inspect(bitmap.eq("名前", @core.String("田中太郎")).length(), content="1")
  inspect(bptree.eq("名前", @core.String("田中太郎")).length(), content="1")
  inspect(lsm.eq("名前", @core.String("田中太郎")).length(), content="1")

  inspect(bitmap.exists("emoji").length(), content="1")
  inspect(bptree.exists("emoji").length(), content="1")
  inspect(lsm.exists("emoji").length(), content="1")
}

///|
/// Test: Large number of unique values
test "index/edge/many_unique_values" {
  let bptree = @attr.BPTreeAttrIndex::new()

  // Add 500 items with unique values
  for i in 1..<=500 {
    let attrs = @core.empty_attrs()
    attrs.set("id", @core.Int(i.to_int64()))
    attrs.set("tag", @core.String("tag_\{i}"))
    bptree.set_attrs(@core.VectorId::from_int(i), attrs)
  }

  inspect(bptree.size(), content="500")

  // Spot check some values
  inspect(bptree.eq("id", @core.Int(250L)).length(), content="1")
  inspect(bptree.eq("tag", @core.String("tag_100")).length(), content="1")
  inspect(bptree.exists("id").length(), content="500")
}

///|
/// Test: Null values handling
test "index/edge/null_values" {
  let bitmap = @attr.BitmapAttrIndex::new()
  let bptree = @attr.BPTreeAttrIndex::new()
  let lsm = @attr.LSMAttrIndex::new()

  let attrs = @core.empty_attrs()
  attrs.set("nullable", @core.Null)
  attrs.set("present", @core.String("yes"))

  let id = @core.VectorId::from_int(1)
  bitmap.set_attrs(id, attrs)
  bptree.set_attrs(id, attrs)
  lsm.set_attrs(id, attrs)

  // Null is a valid value
  inspect(bitmap.eq("nullable", @core.Null).length(), content="1")
  inspect(bptree.eq("nullable", @core.Null).length(), content="1")
  inspect(lsm.eq("nullable", @core.Null).length(), content="1")

  // exists should also find it
  inspect(bitmap.exists("nullable").length(), content="1")
  inspect(bptree.exists("nullable").length(), content="1")
  inspect(lsm.exists("nullable").length(), content="1")
}

///|
/// Test: Same ID added multiple times (update behavior)
test "index/edge/repeated_updates" {
  let bptree = @attr.BPTreeAttrIndex::new()
  let id = @core.VectorId::from_int(1)

  // Update same ID 10 times
  for i in 1..<=10 {
    let attrs = @core.empty_attrs()
    attrs.set("version", @core.Int(i.to_int64()))
    bptree.set_attrs(id, attrs)
  }

  // Should only have 1 entry
  inspect(bptree.size(), content="1")

  // Should have final version
  inspect(bptree.eq("version", @core.Int(10L)).length(), content="1")
  inspect(bptree.eq("version", @core.Int(5L)).length(), content="0")
}
