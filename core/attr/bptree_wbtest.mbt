///|
/// BPTreeAttrIndex basic operations
test "attr/bptree_operations" {
  let index = BPTreeAttrIndex::new()
  let attrs = @types.empty_attrs()
  attrs.set("priority", @types.Int(5L))
  index.set_attrs(@types.VectorId::from_int(1), attrs)
  let result = index.eq("priority", @types.Int(5L))
  inspect(result.length(), content="1")
  let retrieved = index.get_attrs(@types.VectorId::from_int(1))
  inspect(retrieved is Some(_), content="true")
}

///|
/// BPTreeAttrIndex remove_id
test "attr/bptree_remove_id" {
  let index = BPTreeAttrIndex::new()
  let id1 = @types.VectorId::from_int(1)
  let attrs = @types.empty_attrs()
  attrs.set("key", @types.String("value"))
  index.set_attrs(id1, attrs)
  inspect(index.get_attrs(id1) is Some(_), content="true")
  index.remove_id(id1)
  inspect(index.get_attrs(id1) is None, content="true")
}

///|
/// Root leaf split creates two linked leaves
test "bptree/root_leaf_split" {
  let tree = BPTree::new(2)
  bptree_insert(tree, encode_attr_value(@types.Int(10L)), 10L)
  bptree_insert(tree, encode_attr_value(@types.Int(20L)), 20L)
  bptree_insert(tree, encode_attr_value(@types.Int(30L)), 30L)
  inspect(tree.root_idx != 0, content="true")
  match tree.nodes[tree.root_idx] {
    Leaf(_, _) => inspect(false, content="true")
    Branch(entries, rightmost) => {
      inspect(entries.length(), content="1")
      let left_idx = entries[0].child_idx
      inspect(rightmost >= 0, content="true")
      match tree.nodes[left_idx] {
        Leaf(left_entries, next) => {
          inspect(left_entries.length(), content="1")
          inspect(next == rightmost, content="true")
        }
        _ => inspect(false, content="true")
      }
      match tree.nodes[rightmost] {
        Leaf(right_entries, next) => {
          inspect(right_entries.length(), content="2")
          inspect(next, content="-1")
        }
        _ => inspect(false, content="true")
      }
    }
  }
  inspect(
    bptree_lookup(tree, encode_attr_value(@types.Int(10L))) is Some(_),
    content="true",
  )
  inspect(
    bptree_lookup(tree, encode_attr_value(@types.Int(20L))) is Some(_),
    content="true",
  )
  inspect(
    bptree_lookup(tree, encode_attr_value(@types.Int(30L))) is Some(_),
    content="true",
  )
}

///|
/// Branch split propagates to a new root
test "bptree/branch_split_propagation" {
  let tree = BPTree::new(2)
  for i in 1..<=5 {
    bptree_insert(
      tree,
      encode_attr_value(@types.Int(i.to_int64() * 10L)),
      i.to_int64(),
    )
  }
  match tree.nodes[tree.root_idx] {
    Leaf(_, _) => inspect(false, content="true")
    Branch(root_entries, rightmost) => {
      inspect(root_entries.length(), content="1")
      let left_branch_idx = root_entries[0].child_idx
      inspect(rightmost >= 0, content="true")
      match tree.nodes[left_branch_idx] {
        Branch(left_entries, left_rightmost) => {
          inspect(left_entries.length(), content="1")
          inspect(left_rightmost >= 0, content="true")
        }
        _ => inspect(false, content="true")
      }
      match tree.nodes[rightmost] {
        Branch(right_entries, right_rightmost) => {
          inspect(right_entries.length(), content="1")
          inspect(right_rightmost >= 0, content="true")
        }
        _ => inspect(false, content="true")
      }
    }
  }
  let range = @types.NumericRange::between(10.0, 50.0)
  let result = bptree_range(tree, None, None, range)
  inspect(result.length(), content="5")
}

///|
/// Public BPTreeAttrIndex works with aggressive splitting
test "bptree/small_order_attr_index" {
  let index = BPTreeAttrIndex::new(order=2)
  for i in 1..<=10 {
    let attrs = @types.empty_attrs()
    attrs.set("score", @types.Int(i.to_int64() * 10L))
    attrs.set("group", @types.String("g" + i.to_string()))
    index.set_attrs(@types.VectorId::from_int(i), attrs)
  }
  inspect(index.eq("score", @types.Int(50L)).length(), content="1")
  inspect(index.eq("group", @types.String("g10")).length(), content="1")
  inspect(index.exists("score").length(), content="10")
  let range = @types.NumericRange::between(30.0, 70.0)
  match index.range("score", range) {
    Some(ids) => inspect(ids.length(), content="5")
    None => inspect(false, content="true")
  }
}

///|
/// B+ tree remains correct after many leaf and branch splits
test "bptree/scale_many_splits" {
  let total = 2048
  let index = BPTreeAttrIndex::new(order=8)
  for i in 1..<=total {
    let attrs = @types.empty_attrs()
    attrs.set("score", @types.Int(i.to_int64()))
    attrs.set("bucket", @types.Int((i % 16).to_int64()))
    index.set_attrs(@types.VectorId::from_int(i), attrs)
  }
  inspect(index.size(), content="2048")
  inspect(index.eq("score", @types.Int(1024L)).length(), content="1")
  inspect(index.eq("bucket", @types.Int(7L)).length(), content="128")
  let range = @types.NumericRange::between(500.0, 1500.0)
  match index.range("score", range) {
    Some(ids) => inspect(ids.length(), content="1001")
    None => inspect(false, content="true")
  }
  match index.field_trees.get("score") {
    None => inspect(false, content="true")
    Some(tree) => {
      inspect(tree.nodes.length() > 100, content="true")
      inspect(bptree_height(tree) >= 4, content="true")
      inspect(bptree_count_leaf_entries(tree), content="2048")
    }
  }
}

///|
/// BPTreeAttrIndex serialize/deserialize preserves split state and queries
test "bptree/serialize_roundtrip" {
  let index = BPTreeAttrIndex::new(order=4)
  for i in 0..<64 {
    let id = @types.VectorId::from_int(i + 1)
    let attrs = @types.empty_attrs()
    attrs.set("score", @types.Int(i.to_int64() * 10L))
    attrs.set("group", @types.String("g" + (i % 4).to_string()))
    index.set_attrs(id, attrs)
  }
  let roundtripped = BPTreeAttrIndex::deserialize(index.serialize())
  inspect(roundtripped.size(), content="64")
  inspect(roundtripped.eq("group", @types.String("g3")).length(), content="16")
  inspect(roundtripped.exists("score").length(), content="64")
  let range = @types.NumericRange::between(100.0, 190.0)
  match roundtripped.range("score", range) {
    Some(found) => inspect(found.length(), content="10")
    None => inspect(false, content="true")
  }
  match roundtripped.field_trees.get("score") {
    None => inspect(false, content="true")
    Some(tree) => {
      inspect(tree.nodes.length() > 1, content="true")
      inspect(bptree_height(tree) >= 2, content="true")
    }
  }
}

///|
/// BPTreeAttrIndex int range queries
test "bptree/range_int" {
  let index = BPTreeAttrIndex::new()
  for i in 1..<=10 {
    let attrs = @types.empty_attrs()
    attrs.set("score", @types.Int(i.to_int64() * 10L))
    index.set_attrs(@types.VectorId::from_int(i), attrs)
  }
  let range = @types.NumericRange::between(30.0, 70.0)
  match index.range("score", range) {
    Some(ids) => inspect(ids.length(), content="5")
    None => inspect(false, content="true")
  }
}

///|
/// BPTreeAttrIndex float range queries
test "bptree/range_float" {
  let index = BPTreeAttrIndex::new()
  for i in 1..<=10 {
    let attrs = @types.empty_attrs()
    attrs.set("price", @types.Float(i.to_double() * 1.5))
    index.set_attrs(@types.VectorId::from_int(i), attrs)
  }
  let range = @types.NumericRange::between(3.0, 9.0)
  match index.range("price", range) {
    Some(ids) => inspect(ids.length() >= 3, content="true")
    None => inspect(false, content="true")
  }
}

///|
/// BPTreeAttrIndex equality with various types
test "bptree/eq_types" {
  let index = BPTreeAttrIndex::new()
  let attrs1 = @types.empty_attrs()
  attrs1.set("num", @types.Int(42L))
  index.set_attrs(@types.VectorId::from_int(1), attrs1)
  let attrs2 = @types.empty_attrs()
  attrs2.set("num", @types.Float(3.14))
  index.set_attrs(@types.VectorId::from_int(2), attrs2)
  let attrs3 = @types.empty_attrs()
  attrs3.set("name", @types.String("test"))
  index.set_attrs(@types.VectorId::from_int(3), attrs3)
  let attrs4 = @types.empty_attrs()
  attrs4.set("flag", @types.Bool(true))
  index.set_attrs(@types.VectorId::from_int(4), attrs4)
  let attrs5 = @types.empty_attrs()
  attrs5.set("empty", @types.Null)
  index.set_attrs(@types.VectorId::from_int(5), attrs5)
  inspect(index.eq("num", @types.Int(42L)).length(), content="1")
  inspect(index.eq("name", @types.String("test")).length(), content="1")
  inspect(index.eq("flag", @types.Bool(true)).length(), content="1")
  inspect(index.eq("empty", @types.Null).length(), content="1")
}

///|
/// BPTreeAttrIndex exists query
test "bptree/exists" {
  let index = BPTreeAttrIndex::new()
  let attrs1 = @types.empty_attrs()
  attrs1.set("email", @types.String("a@b.com"))
  let attrs2 = @types.empty_attrs()
  attrs2.set("phone", @types.String("123"))
  index.set_attrs(@types.VectorId::from_int(1), attrs1)
  index.set_attrs(@types.VectorId::from_int(2), attrs2)
  inspect(index.exists("email").length(), content="1")
  inspect(index.exists("phone").length(), content="1")
  inspect(index.exists("missing").length(), content="0")
}

///|
/// BPTreeAttrIndex update_attrs
test "bptree/update_attrs" {
  let index = BPTreeAttrIndex::new()
  let id = @types.VectorId::from_int(1)
  let attrs1 = @types.empty_attrs()
  attrs1.set("status", @types.String("active"))
  index.set_attrs(id, attrs1)
  inspect(index.eq("status", @types.String("active")).length(), content="1")
  let attrs2 = @types.empty_attrs()
  attrs2.set("status", @types.String("inactive"))
  index.set_attrs(id, attrs2)
  inspect(index.eq("status", @types.String("active")).length(), content="0")
  inspect(index.eq("status", @types.String("inactive")).length(), content="1")
}

///|
/// BPTreeAttrIndex size
test "bptree/size" {
  let index = BPTreeAttrIndex::new()
  inspect(index.size(), content="0")
  for i in 1..<=5 {
    index.set_attrs(@types.VectorId::from_int(i), @types.empty_attrs())
  }
  inspect(index.size(), content="5")
}

///|
/// BPTreeAttrIndex range with non-existent key
test "bptree/range_empty" {
  let index = BPTreeAttrIndex::new()
  let range = @types.NumericRange::between(0.0, 100.0)
  match index.range("nonexistent", range) {
    Some(ids) => inspect(ids.length(), content="0")
    None => inspect(false, content="true")
  }
}

///|
/// BPTree handles Unicode strings correctly
test "bptree/unicode_strings" {
  let index = BPTreeAttrIndex::new()
  let id1 = @types.VectorId::from_int(1)
  let id2 = @types.VectorId::from_int(2)
  let id3 = @types.VectorId::from_int(3)
  let attrs1 = @types.empty_attrs()
  attrs1.set("name", @types.String("hello"))
  let attrs2 = @types.empty_attrs()
  attrs2.set("name", @types.String("héllo"))
  let attrs3 = @types.empty_attrs()
  attrs3.set("name", @types.String("日本語"))
  index.set_attrs(id1, attrs1)
  index.set_attrs(id2, attrs2)
  index.set_attrs(id3, attrs3)
  let r1 = index.eq("name", @types.String("hello"))
  inspect(r1.length(), content="1")
  inspect(r1[0].to_int64(), content="1")
  let r2 = index.eq("name", @types.String("héllo"))
  inspect(r2.length(), content="1")
  inspect(r2[0].to_int64(), content="2")
  let r3 = index.eq("name", @types.String("日本語"))
  inspect(r3.length(), content="1")
  inspect(r3[0].to_int64(), content="3")
}

///|
/// BPTreeAttrIndex stores a defensive copy of attrs
test "bptree/attrs_defensive_copy" {
  let index = BPTreeAttrIndex::new()
  let id = @types.VectorId::from_int(1)
  let attrs = @types.empty_attrs()
  attrs.set("tag", @types.String("A"))
  index.set_attrs(id, attrs)
  attrs.set("tag", @types.String("B"))
  match index.get_attrs(id) {
    None => inspect(false, content="true")
    Some(stored) =>
      match stored.get("tag") {
        Some(@types.String(s)) => inspect(s, content="A")
        _ => inspect(false, content="true")
      }
  }
}
