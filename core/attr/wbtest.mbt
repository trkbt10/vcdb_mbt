// Whitebox tests for attr module

///|
/// Test: BasicAttrIndex equality queries
test "attr/basic_eq" {
  let index = BasicAttrIndex::new()
  let id1 = @types.VectorId::from_int(1)
  let id2 = @types.VectorId::from_int(2)
  let id3 = @types.VectorId::from_int(3)
  // Set attrs
  let attrs1 = @types.empty_attrs()
  attrs1.set("category", @types.String("A"))
  attrs1.set("score", @types.Int(100L))
  let attrs2 = @types.empty_attrs()
  attrs2.set("category", @types.String("B"))
  attrs2.set("score", @types.Int(200L))
  let attrs3 = @types.empty_attrs()
  attrs3.set("category", @types.String("A"))
  attrs3.set("score", @types.Int(150L))
  index.set_attrs(id1, attrs1)
  index.set_attrs(id2, attrs2)
  index.set_attrs(id3, attrs3)
  // Query eq
  let result_a = index.eq("category", @types.String("A"))
  inspect(result_a.length(), content="2")
  let result_b = index.eq("category", @types.String("B"))
  inspect(result_b.length(), content="1")
  inspect(result_b[0].to_int64(), content="2")
}

///|
/// Test: BasicAttrIndex range queries
test "attr/basic_range" {
  let index = BasicAttrIndex::new()
  for i in 1..<=10 {
    let attrs = @types.empty_attrs()
    attrs.set("value", @types.Int(i.to_int64() * 10L))
    index.set_attrs(@types.VectorId::from_int(i), attrs)
  }
  // Range: 30 <= value <= 70 (inclusive bounds by default)
  let range = @types.NumericRange::between(30.0, 70.0)
  let result = index.range("value", range)
  match result {
    Some(ids) => inspect(ids.length(), content="5") // 30, 40, 50, 60, 70
    None => inspect(false, content="true")
  }
}

///|
/// Test: BasicAttrIndex exists queries
test "attr/basic_exists" {
  let index = BasicAttrIndex::new()
  let attrs1 = @types.empty_attrs()
  attrs1.set("name", @types.String("Alice"))
  let attrs2 = @types.empty_attrs()
  attrs2.set("age", @types.Int(30L))
  index.set_attrs(@types.VectorId::from_int(1), attrs1)
  index.set_attrs(@types.VectorId::from_int(2), attrs2)
  // Exists query
  let with_name = index.exists("name")
  inspect(with_name.length(), content="1")
  let with_age = index.exists("age")
  inspect(with_age.length(), content="1")
}

///|
/// Test: BitmapAttrIndex equality
test "attr/bitmap_eq" {
  let index = BitmapAttrIndex::new()
  let attrs1 = @types.empty_attrs()
  attrs1.set("status", @types.String("active"))
  let attrs2 = @types.empty_attrs()
  attrs2.set("status", @types.String("inactive"))
  index.set_attrs(@types.VectorId::from_int(1), attrs1)
  index.set_attrs(@types.VectorId::from_int(2), attrs2)
  let active = index.eq("status", @types.String("active"))
  inspect(active.length(), content="1")
}

///|
/// Test: BPTreeAttrIndex operations
test "attr/bptree_operations" {
  let index = BPTreeAttrIndex::new()
  let attrs = @types.empty_attrs()
  attrs.set("priority", @types.Int(5L))
  index.set_attrs(@types.VectorId::from_int(1), attrs)
  // Eq query
  let result = index.eq("priority", @types.Int(5L))
  inspect(result.length(), content="1")
  // Get attrs
  let retrieved = index.get_attrs(@types.VectorId::from_int(1))
  inspect(retrieved is Some(_), content="true")
}

///|
/// Test: LSMAttrIndex memtable operations
test "attr/lsm_memtable" {
  let index = LSMAttrIndex::new()
  let attrs = @types.empty_attrs()
  attrs.set("key", @types.String("value"))
  index.set_attrs(@types.VectorId::from_int(1), attrs)
  // Query
  let result = index.eq("key", @types.String("value"))
  inspect(result.length(), content="1")
  // Check memtable size
  inspect(index.memtable_size() > 0, content="true")
}

///|
/// Test: BasicAttrIndex remove_id
test "attr/basic_remove_id" {
  let index = BasicAttrIndex::new()
  let id1 = @types.VectorId::from_int(1)
  let id2 = @types.VectorId::from_int(2)
  let attrs1 = @types.empty_attrs()
  attrs1.set("category", @types.String("A"))
  attrs1.set("score", @types.Int(100L))
  let attrs2 = @types.empty_attrs()
  attrs2.set("category", @types.String("A"))
  attrs2.set("score", @types.Int(200L))
  index.set_attrs(id1, attrs1)
  index.set_attrs(id2, attrs2)
  // Verify both exist
  inspect(index.eq("category", @types.String("A")).length(), content="2")
  // Remove id1
  index.remove_id(id1)
  // Verify id1 is removed
  inspect(index.eq("category", @types.String("A")).length(), content="1")
  inspect(index.exists("score").length(), content="1")
  inspect(index.get_attrs(id1) is None, content="true")
  inspect(index.get_attrs(id2) is Some(_), content="true")
}

///|
/// Test: BitmapAttrIndex remove_id
test "attr/bitmap_remove_id" {
  let index = BitmapAttrIndex::new()
  let id1 = @types.VectorId::from_int(1)
  let id2 = @types.VectorId::from_int(2)
  let attrs1 = @types.empty_attrs()
  attrs1.set("status", @types.String("active"))
  let attrs2 = @types.empty_attrs()
  attrs2.set("status", @types.String("active"))
  index.set_attrs(id1, attrs1)
  index.set_attrs(id2, attrs2)
  inspect(index.eq("status", @types.String("active")).length(), content="2")
  // Remove id1
  index.remove_id(id1)
  inspect(index.eq("status", @types.String("active")).length(), content="1")
}

///|
/// Test: BPTreeAttrIndex remove_id
test "attr/bptree_remove_id" {
  let index = BPTreeAttrIndex::new()
  let id1 = @types.VectorId::from_int(1)
  let attrs = @types.empty_attrs()
  attrs.set("key", @types.String("value"))
  index.set_attrs(id1, attrs)
  inspect(index.get_attrs(id1) is Some(_), content="true")
  // Remove
  index.remove_id(id1)
  inspect(index.get_attrs(id1) is None, content="true")
}

///|
/// Test: LSMAttrIndex remove_id
test "attr/lsm_remove_id" {
  let index = LSMAttrIndex::new()
  let id1 = @types.VectorId::from_int(1)
  let id2 = @types.VectorId::from_int(2)
  let attrs1 = @types.empty_attrs()
  attrs1.set("tag", @types.String("test"))
  let attrs2 = @types.empty_attrs()
  attrs2.set("tag", @types.String("test"))
  index.set_attrs(id1, attrs1)
  index.set_attrs(id2, attrs2)
  inspect(index.eq("tag", @types.String("test")).length(), content="2")
  // Remove id1
  index.remove_id(id1)
  inspect(index.eq("tag", @types.String("test")).length(), content="1")
}

///|
/// Test: remove_int64_swap utility function
test "attr/remove_int64_swap" {
  let arr : Array[Int64] = [1L, 2L, 3L, 4L, 5L]
  // Remove middle element
  inspect(remove_int64_swap(arr, 3L), content="true")
  inspect(arr.length(), content="4")
  // Remove non-existent element
  inspect(remove_int64_swap(arr, 99L), content="false")
  inspect(arr.length(), content="4")
  // Remove last element
  inspect(remove_int64_swap(arr, 5L), content="true")
  inspect(arr.length(), content="3")
}

///|
/// Test: remove_num_entry_swap utility function
test "attr/remove_num_entry_swap" {
  let arr : Array[NumEntry] = [
    NumEntry::{ value: 1.0, id: 10L },
    NumEntry::{ value: 2.0, id: 20L },
    NumEntry::{ value: 3.0, id: 30L },
  ]
  // Remove by id
  inspect(remove_num_entry_swap(arr, 20L), content="true")
  inspect(arr.length(), content="2")
  // Non-existent id
  inspect(remove_num_entry_swap(arr, 99L), content="false")
  inspect(arr.length(), content="2")
}

///|
/// Test: BloomFilter create and query
test "sstable/bloom_filter" {
  let keys = [
    Bytes::from_array([b'a', b'b', b'c'][:]),
    Bytes::from_array([b'd', b'e', b'f'][:]),
    Bytes::from_array([b'g', b'h', b'i'][:]),
  ]
  let bloom = BloomFilter::create(keys, 0.01)
  // Keys in filter should return true
  inspect(
    bloom.might_contain(Bytes::from_array([b'a', b'b', b'c'][:])),
    content="true",
  )
  inspect(
    bloom.might_contain(Bytes::from_array([b'd', b'e', b'f'][:])),
    content="true",
  )
  // Key not in filter should (likely) return false
  let not_in = Bytes::from_array([b'x', b'y', b'z'][:])
  // May have false positives, but unlikely with low false positive rate
  let _ = bloom.might_contain(not_in) // Just ensure it doesn't crash
}

///|
/// Test: BloomFilter empty keys
test "sstable/bloom_filter_empty" {
  let bloom = BloomFilter::create([], 0.01)
  inspect(bloom.hash_count, content="1")
  inspect(bloom.bit_count, content="8")
}

///|
/// Test: BloomFilter encode/decode
test "sstable/bloom_filter_roundtrip" {
  let keys = [Bytes::from_array([b't', b'e', b's', b't'][:])]
  let bloom = BloomFilter::create(keys, 0.01)
  let encoded = bloom.encode()
  let decoded = BloomFilter::decode(encoded)
  match decoded {
    Some(b) => {
      inspect(b.hash_count == bloom.hash_count, content="true")
      inspect(b.bit_count == bloom.bit_count, content="true")
      inspect(
        b.might_contain(Bytes::from_array([b't', b'e', b's', b't'][:])),
        content="true",
      )
    }
    None => inspect(false, content="true")
  }
}

///|
/// Test: SSTableRecord encode/decode
test "sstable/record_roundtrip" {
  let record : SSTableRecord = {
    key: Bytes::from_array([b'k', b'e', b'y'][:]),
    value: Bytes::from_array([b'v', b'a', b'l', b'u', b'e'][:]),
  }
  let encoded = record.encode()
  match SSTableRecord::decode(encoded, 0) {
    Some((decoded, bytes_read)) => {
      inspect(decoded.key.length(), content="3")
      inspect(decoded.value.length(), content="5")
      inspect(bytes_read, content="16") // 4 + 4 + 3 + 5
    }
    None => inspect(false, content="true")
  }
}

///|
/// Test: SSTableRecord decode invalid
test "sstable/record_decode_invalid" {
  // Too short
  let short_buf = Bytes::from_array([b'\x00', b'\x00'][:])
  inspect(SSTableRecord::decode(short_buf, 0) is None, content="true")
  // Offset beyond buffer
  let buf = Bytes::from_array(
    [b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00'][:],
  )
  inspect(SSTableRecord::decode(buf, 100) is None, content="true")
}

///|
/// Test: SSTableFooter encode/decode
test "sstable/footer_roundtrip" {
  let footer : SSTableFooter = {
    magic: 0x54535341U,
    version: 1U,
    data_offset: 0,
    data_size: 100,
    index_offset: 100,
    index_size: 50,
    bloom_offset: 150,
    bloom_size: 20,
  }
  let encoded = footer.encode()
  inspect(encoded.length(), content="32")
  // Create buffer with footer at the end
  let buf_arr : FixedArray[Byte] = FixedArray::make(64, b'\x00')
  for i in 0..<32 {
    buf_arr[32 + i] = encoded[i]
  }
  let buf = Bytes::from_array(buf_arr)
  match SSTableFooter::decode(buf) {
    Some(f) => {
      inspect(f.magic == 0x54535341U, content="true")
      inspect(f.version == 1U, content="true")
      inspect(f.data_size, content="100")
    }
    None => inspect(false, content="true")
  }
}

///|
/// Test: SSTableFooter decode invalid magic
test "sstable/footer_invalid_magic" {
  let buf = Bytes::from_array(FixedArray::make(32, b'\x00'))
  inspect(SSTableFooter::decode(buf) is None, content="true")
}

///|
/// Test: SSTable build and read
test "sstable/build_read" {
  let records : Array[SSTableRecord] = [
    { key: Bytes::from_array([b'a'][:]), value: Bytes::from_array([b'1'][:]) },
    { key: Bytes::from_array([b'b'][:]), value: Bytes::from_array([b'2'][:]) },
    { key: Bytes::from_array([b'c'][:]), value: Bytes::from_array([b'3'][:]) },
  ]
  let bytes = SSTable::build(records, 2)
  inspect(bytes.length() > 0, content="true")
  match SSTable::read(bytes) {
    Some(table) => {
      inspect(table.records.length(), content="3")
      inspect(table.index.length() > 0, content="true")
      inspect(table.bloom is Some(_), content="true")
    }
    None => inspect(false, content="true")
  }
}

///|
/// Test: SSTable find
test "sstable/find" {
  let records : Array[SSTableRecord] = [
    {
      key: Bytes::from_array([b'a', b'a', b'a'][:]),
      value: Bytes::from_array([b'1'][:]),
    },
    {
      key: Bytes::from_array([b'b', b'b', b'b'][:]),
      value: Bytes::from_array([b'2'][:]),
    },
    {
      key: Bytes::from_array([b'c', b'c', b'c'][:]),
      value: Bytes::from_array([b'3'][:]),
    },
  ]
  let bytes = SSTable::build(records, 1)
  match SSTable::read(bytes) {
    Some(table) => {
      // Find existing key
      let found = table.find(Bytes::from_array([b'b', b'b', b'b'][:]))
      match found {
        Some(r) => inspect(r.value[0] == b'2', content="true")
        None => inspect(false, content="true")
      }
      // Find non-existing key (bloom should reject quickly)
      let not_found = table.find(Bytes::from_array([b'x', b'x', b'x'][:]))
      inspect(not_found is None, content="true")
    }
    None => inspect(false, content="true")
  }
}

///|
/// Test: SSTable with empty records
test "sstable/empty_records" {
  let records : Array[SSTableRecord] = []
  let bytes = SSTable::build(records, 1)
  match SSTable::read(bytes) {
    Some(table) => inspect(table.records.length(), content="0")
    None => inspect(false, content="true")
  }
}

///|
/// Test: BPTreeAttrIndex range with Int values
test "bptree/range_int" {
  let index = BPTreeAttrIndex::new()
  for i in 1..<=10 {
    let attrs = @types.empty_attrs()
    attrs.set("score", @types.Int(i.to_int64() * 10L))
    index.set_attrs(@types.VectorId::from_int(i), attrs)
  }
  // Range: 30 <= score <= 70
  let range = @types.NumericRange::between(30.0, 70.0)
  let result = index.range("score", range)
  match result {
    Some(ids) => inspect(ids.length(), content="5") // 30, 40, 50, 60, 70
    None => inspect(false, content="true")
  }
}

///|
/// Test: BPTreeAttrIndex range with Float values
test "bptree/range_float" {
  let index = BPTreeAttrIndex::new()
  for i in 1..<=10 {
    let attrs = @types.empty_attrs()
    attrs.set("price", @types.Float(i.to_double() * 1.5))
    index.set_attrs(@types.VectorId::from_int(i), attrs)
  }
  // Range: 3.0 <= price <= 9.0
  let range = @types.NumericRange::between(3.0, 9.0)
  let result = index.range("price", range)
  match result {
    Some(ids) => inspect(ids.length() >= 3, content="true")
    None => inspect(false, content="true")
  }
}

///|
/// Test: BPTreeAttrIndex eq with various types
test "bptree/eq_types" {
  let index = BPTreeAttrIndex::new()
  // Int
  let attrs1 = @types.empty_attrs()
  attrs1.set("num", @types.Int(42L))
  index.set_attrs(@types.VectorId::from_int(1), attrs1)
  // Float
  let attrs2 = @types.empty_attrs()
  attrs2.set("num", @types.Float(3.14))
  index.set_attrs(@types.VectorId::from_int(2), attrs2)
  // String
  let attrs3 = @types.empty_attrs()
  attrs3.set("name", @types.String("test"))
  index.set_attrs(@types.VectorId::from_int(3), attrs3)
  // Bool
  let attrs4 = @types.empty_attrs()
  attrs4.set("flag", @types.Bool(true))
  index.set_attrs(@types.VectorId::from_int(4), attrs4)
  // Null
  let attrs5 = @types.empty_attrs()
  attrs5.set("empty", @types.Null)
  index.set_attrs(@types.VectorId::from_int(5), attrs5)
  // Query
  inspect(index.eq("num", @types.Int(42L)).length(), content="1")
  inspect(index.eq("name", @types.String("test")).length(), content="1")
  inspect(index.eq("flag", @types.Bool(true)).length(), content="1")
  inspect(index.eq("empty", @types.Null).length(), content="1")
}

///|
/// Test: BPTreeAttrIndex exists query
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
/// Test: BPTreeAttrIndex update attrs
test "bptree/update_attrs" {
  let index = BPTreeAttrIndex::new()
  let id = @types.VectorId::from_int(1)
  // Set initial attrs
  let attrs1 = @types.empty_attrs()
  attrs1.set("status", @types.String("active"))
  index.set_attrs(id, attrs1)
  inspect(index.eq("status", @types.String("active")).length(), content="1")
  // Update attrs
  let attrs2 = @types.empty_attrs()
  attrs2.set("status", @types.String("inactive"))
  index.set_attrs(id, attrs2)
  // Old value should not be found
  inspect(index.eq("status", @types.String("active")).length(), content="0")
  // New value should be found
  inspect(index.eq("status", @types.String("inactive")).length(), content="1")
}

///|
/// Test: BPTreeAttrIndex size
test "bptree/size" {
  let index = BPTreeAttrIndex::new()
  inspect(index.size(), content="0")
  for i in 1..<=5 {
    index.set_attrs(@types.VectorId::from_int(i), @types.empty_attrs())
  }
  inspect(index.size(), content="5")
}

///|
/// Test: BPTreeAttrIndex range with non-existent key
test "bptree/range_empty" {
  let index = BPTreeAttrIndex::new()
  let range = @types.NumericRange::between(0.0, 100.0)
  let result = index.range("nonexistent", range)
  match result {
    Some(ids) => inspect(ids.length(), content="0")
    None => inspect(false, content="true")
  }
}

///|
/// Test: LSMAttrIndex exists query
test "lsm/exists" {
  let index = LSMAttrIndex::new()
  let attrs = @types.empty_attrs()
  attrs.set("email", @types.String("test@test.com"))
  index.set_attrs(@types.VectorId::from_int(1), attrs)
  inspect(index.exists("email").length(), content="1")
  inspect(index.exists("missing").length(), content="0")
}

///|
/// Test: LSMAttrIndex range query
test "lsm/range" {
  let index = LSMAttrIndex::new()
  for i in 1..<=10 {
    let attrs = @types.empty_attrs()
    attrs.set("value", @types.Int(i.to_int64() * 10L))
    index.set_attrs(@types.VectorId::from_int(i), attrs)
  }
  let range = @types.NumericRange::between(30.0, 70.0)
  let result = index.range("value", range)
  match result {
    Some(ids) => inspect(ids.length(), content="5")
    None => inspect(false, content="true")
  }
}

///|
/// Test: BitmapAttrIndex exists query
test "bitmap/exists" {
  let index = BitmapAttrIndex::new()
  let attrs = @types.empty_attrs()
  attrs.set("active", @types.Bool(true))
  index.set_attrs(@types.VectorId::from_int(1), attrs)
  inspect(index.exists("active").length(), content="1")
  inspect(index.exists("missing").length(), content="0")
}

///|
/// Test: BitmapAttrIndex get_attrs
test "bitmap/get_attrs" {
  let index = BitmapAttrIndex::new()
  let attrs = @types.empty_attrs()
  attrs.set("tag", @types.String("test"))
  index.set_attrs(@types.VectorId::from_int(1), attrs)
  let retrieved = index.get_attrs(@types.VectorId::from_int(1))
  inspect(retrieved is Some(_), content="true")
  inspect(
    index.get_attrs(@types.VectorId::from_int(99)) is None,
    content="true",
  )
}

///|
/// Test: LSMAttrIndex size
test "lsm/size" {
  let index = LSMAttrIndex::new()
  inspect(index.size(), content="0")
  let attrs = @types.empty_attrs()
  attrs.set("key", @types.String("value"))
  index.set_attrs(@types.VectorId::from_int(1), attrs)
  index.set_attrs(@types.VectorId::from_int(2), attrs)
  inspect(index.size(), content="2")
}

///|
/// Test: LSMAttrIndex should_flush
test "lsm/should_flush" {
  let index = LSMAttrIndex::new(flush_threshold=2)
  inspect(index.should_flush(), content="false")
  // Add entries to trigger flush threshold
  let attrs1 = @types.empty_attrs()
  attrs1.set("key", @types.String("value1"))
  index.set_attrs(@types.VectorId::from_int(1), attrs1)
  let attrs2 = @types.empty_attrs()
  attrs2.set("key", @types.String("value2"))
  index.set_attrs(@types.VectorId::from_int(2), attrs2)
  // Memtable size should trigger flush
  inspect(index.memtable_size() >= 2, content="true")
}

///|
/// Test: LSMAttrIndex clear_memtable
test "lsm/clear_memtable" {
  let index = LSMAttrIndex::new()
  let attrs = @types.empty_attrs()
  attrs.set("key", @types.String("value"))
  index.set_attrs(@types.VectorId::from_int(1), attrs)
  inspect(index.memtable_size() > 0, content="true")
  index.clear_memtable()
  inspect(index.memtable_size(), content="0")
  // Data should still exist
  inspect(index.size(), content="1")
  inspect(
    index.get_attrs(@types.VectorId::from_int(1)) is Some(_),
    content="true",
  )
}

///|
/// Test: LSMAttrIndex get_attrs
test "lsm/get_attrs" {
  let index = LSMAttrIndex::new()
  // Non-existent
  inspect(index.get_attrs(@types.VectorId::from_int(1)) is None, content="true")
  // Add and retrieve
  let attrs = @types.empty_attrs()
  attrs.set("name", @types.String("test"))
  attrs.set("count", @types.Int(42L))
  index.set_attrs(@types.VectorId::from_int(1), attrs)
  match index.get_attrs(@types.VectorId::from_int(1)) {
    Some(a) =>
      match a.get("name") {
        Some(@types.String(s)) => inspect(s, content="test")
        _ => inspect(false, content="true")
      }
    None => inspect(false, content="true")
  }
}

///|
/// Test: LSMAttrIndex update attrs replaces old
test "lsm/update_attrs" {
  let index = LSMAttrIndex::new()
  let id = @types.VectorId::from_int(1)
  // Set initial attrs
  let attrs1 = @types.empty_attrs()
  attrs1.set("status", @types.String("old"))
  index.set_attrs(id, attrs1)
  inspect(index.eq("status", @types.String("old")).length(), content="1")
  // Update attrs
  let attrs2 = @types.empty_attrs()
  attrs2.set("status", @types.String("new"))
  index.set_attrs(id, attrs2)
  // Old value should not be found
  inspect(index.eq("status", @types.String("old")).length(), content="0")
  // New value should be found
  inspect(index.eq("status", @types.String("new")).length(), content="1")
}

///|
/// Test: BasicAttrIndex size
test "basic/size" {
  let index = BasicAttrIndex::new()
  inspect(index.size(), content="0")
  index.set_attrs(@types.VectorId::from_int(1), @types.empty_attrs())
  index.set_attrs(@types.VectorId::from_int(2), @types.empty_attrs())
  inspect(index.size(), content="2")
}

///|
/// Test: BasicAttrIndex range with Float values
test "basic/range_float" {
  let index = BasicAttrIndex::new()
  for i in 1..<=10 {
    let attrs = @types.empty_attrs()
    attrs.set("price", @types.Float(i.to_double() * 1.5))
    index.set_attrs(@types.VectorId::from_int(i), attrs)
  }
  // Range: 3.0 <= price <= 9.0
  let range = @types.NumericRange::between(3.0, 9.0)
  let result = index.range("price", range)
  match result {
    Some(ids) => inspect(ids.length() >= 3, content="true")
    None => inspect(false, content="true")
  }
}

///|
/// Test: BitmapAttrIndex range (returns None)
test "bitmap/range" {
  let index = BitmapAttrIndex::new()
  let range = @types.NumericRange::between(0.0, 100.0)
  let result = index.range("any", range)
  inspect(result is None, content="true")
}

///|
/// Test: attr_value_to_key disambiguates types (P2 fix)
test "attr/key_type_disambiguation" {
  // Int(1), Float(1.0), String("1") should produce different keys
  let key_int = attr_value_to_key(@types.Int(1L))
  let key_float = attr_value_to_key(@types.Float(1.0))
  let key_string = attr_value_to_key(@types.String("1"))
  // All should be different
  inspect(key_int != key_float, content="true")
  inspect(key_int != key_string, content="true")
  inspect(key_float != key_string, content="true")
  // Check type prefixes
  inspect(key_int.has_prefix("I:"), content="true")
  inspect(key_float.has_prefix("F:"), content="true")
  inspect(key_string.has_prefix("S:"), content="true")
  // Bool and Null also have prefixes
  let key_bool = attr_value_to_key(@types.Bool(true))
  let key_null = attr_value_to_key(@types.Null)
  inspect(key_bool.has_prefix("B:"), content="true")
  inspect(key_null.has_prefix("N:"), content="true")
}

///|
/// Test: BasicAttrIndex correctly distinguishes types (P2 fix)
test "basic/type_disambiguation" {
  let index = BasicAttrIndex::new()
  let id1 = @types.VectorId::from_int(1)
  let id2 = @types.VectorId::from_int(2)
  let id3 = @types.VectorId::from_int(3)
  // Set same "value" but different types
  let attrs1 = @types.empty_attrs()
  attrs1.set("val", @types.Int(1L))
  let attrs2 = @types.empty_attrs()
  attrs2.set("val", @types.Float(1.0))
  let attrs3 = @types.empty_attrs()
  attrs3.set("val", @types.String("1"))
  index.set_attrs(id1, attrs1)
  index.set_attrs(id2, attrs2)
  index.set_attrs(id3, attrs3)
  // Querying for Int(1) should only find id1
  let result_int = index.eq("val", @types.Int(1L))
  inspect(result_int.length(), content="1")
  inspect(result_int[0].to_int64(), content="1")
  // Querying for Float(1.0) should only find id2
  let result_float = index.eq("val", @types.Float(1.0))
  inspect(result_float.length(), content="1")
  inspect(result_float[0].to_int64(), content="2")
  // Querying for String("1") should only find id3
  let result_string = index.eq("val", @types.String("1"))
  inspect(result_string.length(), content="1")
  inspect(result_string[0].to_int64(), content="3")
}

///|
/// Test: BPTree handles Unicode strings correctly
test "bptree/unicode_strings" {
  let index = BPTreeAttrIndex::new()
  let id1 = @types.VectorId::from_int(1)
  let id2 = @types.VectorId::from_int(2)
  let id3 = @types.VectorId::from_int(3)
  // Add entries with Unicode vs ASCII that would collide with truncation
  let attrs1 = @types.empty_attrs()
  attrs1.set("name", @types.String("hello")) // ASCII
  let attrs2 = @types.empty_attrs()
  attrs2.set("name", @types.String("héllo")) // Unicode é (0xE9)
  let attrs3 = @types.empty_attrs()
  attrs3.set("name", @types.String("日本語")) // Japanese
  index.set_attrs(id1, attrs1)
  index.set_attrs(id2, attrs2)
  index.set_attrs(id3, attrs3)
  // Each should be distinct
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
/// Test: LSM handles Unicode attribute keys correctly
test "lsm/unicode_attr_keys" {
  let index = LSMAttrIndex::new()
  let id1 = @types.VectorId::from_int(1)
  let id2 = @types.VectorId::from_int(2)
  // Add with Unicode vs ASCII attr keys
  let attrs1 = @types.empty_attrs()
  attrs1.set("name", @types.Bool(true))
  let attrs2 = @types.empty_attrs()
  attrs2.set("名前", @types.Bool(true)) // Japanese for "name"
  index.set_attrs(id1, attrs1)
  index.set_attrs(id2, attrs2)
  // Each should be distinct
  let r1 = index.eq("name", @types.Bool(true))
  inspect(r1.length(), content="1")
  let r2 = index.eq("名前", @types.Bool(true))
  inspect(r2.length(), content="1")
  // exists should also be distinct
  let e1 = index.exists("name")
  inspect(e1.length(), content="1")
  let e2 = index.exists("名前")
  inspect(e2.length(), content="1")
}

///|
/// Test: SSTable::read returns None for corrupted footer bounds
test "sstable/read_invalid_bounds" {
  // Create a valid SSTable first
  let records : Array[SSTableRecord] = [
    { key: b"key1", value: b"val1" },
    { key: b"key2", value: b"val2" },
  ]
  let valid_data = SSTable::build(records, 1)
  // Corrupt the footer by modifying section sizes to exceed buffer
  // Footer is last 32 bytes, data_size is at offset 12 from footer start
  let corrupted : FixedArray[Byte] = FixedArray::make(
    valid_data.length(),
    b'\x00',
  )
  for i in 0..<valid_data.length() {
    corrupted[i] = valid_data[i]
  }
  // Set data_size to a very large value (overwrite bytes at footer + 12)
  let footer_start = valid_data.length() - 32
  corrupted[footer_start + 12] = b'\xFF'
  corrupted[footer_start + 13] = b'\xFF'
  corrupted[footer_start + 14] = b'\xFF'
  corrupted[footer_start + 15] = b'\x7F' // Large positive int
  let corrupted_bytes = Bytes::from_array(corrupted)
  // Should return None instead of panicking
  let result = SSTable::read(corrupted_bytes)
  inspect(result is None, content="true")
}

///|
/// Test: BasicAttrIndex stores defensive copy of attrs
test "basic/attrs_defensive_copy" {
  let index = BasicAttrIndex::new()
  let id = @types.VectorId::from_int(1)
  let attrs = @types.empty_attrs()
  attrs.set("tag", @types.String("A"))
  index.set_attrs(id, attrs)
  // Mutate the original attrs after storing
  attrs.set("tag", @types.String("B"))
  // get_attrs should still return "A"
  match index.get_attrs(id) {
    None => inspect(false, content="true") // Should not reach here
    Some(stored) =>
      match stored.get("tag") {
        Some(@types.String(s)) => inspect(s, content="A")
        _ => inspect(false, content="true") // Should not reach here
      }
  }
  // eq query should also still find "A"
  let results = index.eq("tag", @types.String("A"))
  inspect(results.length(), content="1")
}

///|
/// Test: BitmapAttrIndex stores defensive copy of attrs
test "bitmap/attrs_defensive_copy" {
  let index = BitmapAttrIndex::new()
  let id = @types.VectorId::from_int(1)
  let attrs = @types.empty_attrs()
  attrs.set("tag", @types.String("A"))
  index.set_attrs(id, attrs)
  // Mutate the original attrs after storing
  attrs.set("tag", @types.String("B"))
  // get_attrs should still return "A"
  match index.get_attrs(id) {
    None => inspect(false, content="true")
    Some(stored) =>
      match stored.get("tag") {
        Some(@types.String(s)) => inspect(s, content="A")
        _ => inspect(false, content="true")
      }
  }
}

///|
/// Test: BPTreeAttrIndex stores defensive copy of attrs
test "bptree/attrs_defensive_copy" {
  let index = BPTreeAttrIndex::new()
  let id = @types.VectorId::from_int(1)
  let attrs = @types.empty_attrs()
  attrs.set("tag", @types.String("A"))
  index.set_attrs(id, attrs)
  // Mutate the original attrs after storing
  attrs.set("tag", @types.String("B"))
  // get_attrs should still return "A"
  match index.get_attrs(id) {
    None => inspect(false, content="true")
    Some(stored) =>
      match stored.get("tag") {
        Some(@types.String(s)) => inspect(s, content="A")
        _ => inspect(false, content="true")
      }
  }
}

///|
/// Test: LSMAttrIndex stores defensive copy of attrs
test "lsm/attrs_defensive_copy" {
  let index = LSMAttrIndex::new()
  let id = @types.VectorId::from_int(1)
  let attrs = @types.empty_attrs()
  attrs.set("tag", @types.String("A"))
  index.set_attrs(id, attrs)
  // Mutate the original attrs after storing
  attrs.set("tag", @types.String("B"))
  // get_attrs should still return "A"
  match index.get_attrs(id) {
    None => inspect(false, content="true")
    Some(stored) =>
      match stored.get("tag") {
        Some(@types.String(s)) => inspect(s, content="A")
        _ => inspect(false, content="true")
      }
  }
}
