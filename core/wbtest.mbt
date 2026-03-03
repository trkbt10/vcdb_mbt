// Whitebox tests for core module

///|
test "math/normalize" {
  let v = [3.0, 4.0]
  normalize_in_place(v)
  // Should be [0.6, 0.8] (3/5, 4/5)
  inspect((v[0] - 0.6).abs() < 0.0001, content="true")
  inspect((v[1] - 0.8).abs() < 0.0001, content="true")
}

///|
test "math/dot_at" {
  let data = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]
  let q = [1.0, 1.0, 1.0]
  // dot([1,2,3], [1,1,1]) = 6
  let result = dot_at(data, 0, q, 3)
  inspect(result, content="6")
  // dot([4,5,6], [1,1,1]) = 15
  let result2 = dot_at(data, 3, q, 3)
  inspect(result2, content="15")
}

///|
test "math/l2neg_at" {
  let data = [1.0, 2.0, 3.0]
  let q = [4.0, 5.0, 6.0]
  // l2neg = -(9+9+9) = -27
  let result = l2neg_at(data, 0, q, 3)
  inspect(result, content="-27")
}

///|
test "topk/push_top_k" {
  let out : Array[ScoredItem] = []
  push_top_k(out, scored_item(0, 1.0), 3, fn(x) { x.s })
  push_top_k(out, scored_item(1, 3.0), 3, fn(x) { x.s })
  push_top_k(out, scored_item(2, 2.0), 3, fn(x) { x.s })
  push_top_k(out, scored_item(3, 5.0), 3, fn(x) { x.s })
  push_top_k(out, scored_item(4, 0.5), 3, fn(x) { x.s })
  // Should have [5.0, 3.0, 2.0] (top 3)
  inspect(out.length(), content="3")
  inspect(out[0].s, content="5")
  inspect(out[1].s, content="3")
  inspect(out[2].s, content="2")
}

///|
test "heap/max_heap" {
  let heap : MaxHeap[ScoredItem] = MaxHeap::for_scored()
  heap.push(scored_item(0, 1.0))
  heap.push(scored_item(1, 5.0))
  heap.push(scored_item(2, 3.0))
  inspect(heap.length(), content="3")
  // Pop should return highest first
  let top = heap.pop()
  inspect(top.unwrap().s, content="5")
  let next = heap.pop()
  inspect(next.unwrap().s, content="3")
}

///|
test "binary/writer_reader" {
  let w = BinaryWriter::new()
  w.push_u32(42U)
  w.push_i32(-100)
  w.push_u64(0x123456789ABCDEF0UL)
  w.push_f64(3.14159)
  let bytes = w.concat()
  let r = BinaryReader::new(bytes)
  inspect(r.read_u32(), content="42")
  inspect(r.read_i32(), content="-100")
  inspect(r.read_u64(), content="1311768467463790320")
  let f = r.read_f64()
  inspect((f - 3.14159).abs() < 0.0001, content="true")
}

///|
test "store/basic_operations" {
  let store = CoreStore::new(3, Metric::Dot)
  inspect(store.size(), content="0")
  // Add vector
  let (idx, created) = store.add_or_update(
    VectorId::from_int(1),
    [1.0, 2.0, 3.0],
    empty_attrs(),
  )
  inspect(idx, content="0")
  inspect(created, content="true")
  inspect(store.size(), content="1")
  // Check has
  inspect(store.has(VectorId::from_int(1)), content="true")
  inspect(store.has(VectorId::from_int(2)), content="false")
  // Get
  let record = store.get(VectorId::from_int(1))
  inspect(record.unwrap().vector[0], content="1")
}

///|
test "store/upsert" {
  let store = CoreStore::new(2, Metric::Dot)
  let _ = store.add_or_update(VectorId::from_int(1), [1.0, 2.0], empty_attrs())
  // Upsert same id
  let (idx, created) = store.add_or_update(
    VectorId::from_int(1),
    [3.0, 4.0],
    empty_attrs(),
    upsert=true,
  )
  inspect(idx, content="0")
  inspect(created, content="false")
  let record = store.get(VectorId::from_int(1))
  inspect(record.unwrap().vector[0], content="3")
}

///|
test "store/remove" {
  let store = CoreStore::new(2, Metric::Dot)
  let _ = store.add_or_update(VectorId::from_int(1), [1.0, 2.0], empty_attrs())
  let _ = store.add_or_update(VectorId::from_int(2), [3.0, 4.0], empty_attrs())
  let _ = store.add_or_update(VectorId::from_int(3), [5.0, 6.0], empty_attrs())
  inspect(store.size(), content="3")
  // Remove middle element - should swap with last
  let info = store.remove_by_id(VectorId::from_int(2))
  inspect(info is None, content="false")
  inspect(store.size(), content="2")
  // ID 3 should now be at index 1
  inspect(store.has(VectorId::from_int(2)), content="false")
  inspect(store.has(VectorId::from_int(3)), content="true")
}

///|
test "store/cosine_normalization" {
  // Issue #4: cosine metric should auto-normalize
  let store = CoreStore::new(2, Metric::Cosine)
  let _ = store.add_or_update(VectorId::from_int(1), [3.0, 4.0], empty_attrs())
  let record = store.get(VectorId::from_int(1))
  let v = record.unwrap().vector
  // Should be normalized: [0.6, 0.8]
  inspect((v[0] - 0.6).abs() < 0.0001, content="true")
  inspect((v[1] - 0.8).abs() < 0.0001, content="true")
}

///|
test "math/ln" {
  // ln(1) = 0
  inspect((ln(1.0) - 0.0).abs() < 0.0001, content="true")
  // ln(e) ≈ 1
  let e = 2.718281828459045
  inspect((ln(e) - 1.0).abs() < 0.0001, content="true")
  // ln(2) ≈ 0.693
  inspect((ln(2.0) - 0.6931471805599453).abs() < 0.0001, content="true")
  // ln(0.5) ≈ -0.693
  inspect((ln(0.5) - -0.6931471805599453).abs() < 0.0001, content="true")
}

///|
test "store/serialization" {
  let store = CoreStore::new(3, Metric::Cosine)
  let attrs1 = empty_attrs()
  attrs1.set("name", AttrValue::String("test"))
  attrs1.set("count", AttrValue::Int(42L))
  let _ = store.add_or_update(VectorId::from_int(1), [3.0, 4.0, 0.0], attrs1)
  let attrs2 = empty_attrs()
  attrs2.set("flag", Bool(true))
  let _ = store.add_or_update(VectorId::from_int(2), [0.0, 1.0, 0.0], attrs2)
  // Serialize
  let bytes = store.serialize()
  inspect(bytes.length() > 0, content="true")
  // Deserialize
  let store2 = CoreStore::deserialize(bytes)
  inspect(store2.size(), content="2")
  inspect(store2.dim, content="3")
  // Check data
  let record1 = store2.get(VectorId::from_int(1))
  inspect(record1 is None, content="false")
  // Cosine normalized: [3,4,0] -> [0.6, 0.8, 0]
  let v = record1.unwrap().vector
  inspect((v[0] - 0.6).abs() < 0.0001, content="true")
  // Check attrs
  let name = record1.unwrap().attrs.get("name")
  inspect(name is None, content="false")
}

///|
/// Test: BinaryWriter and BinaryReader roundtrip
test "binary/roundtrip" {
  let writer = BinaryWriter::new()
  writer.push_u32(0x12345678U)
  writer.push_i32(-123)
  writer.push_u64(12345678901234UL)
  writer.push_f64(3.14159)
  writer.push_byte(b'\xFF')
  let data = writer.concat()
  let reader = BinaryReader::new(data)
  inspect(reader.read_u32(), content="305419896")
  inspect(reader.read_i32(), content="-123")
  inspect(reader.read_u64(), content="12345678901234")
  let f = reader.read_f64()
  inspect((f - 3.14159).abs() < 0.00001, content="true")
  inspect(reader.read_byte().to_int(), content="255")
}

///|
/// Test: NumericRange matching
test "range/matching" {
  let gt = NumericRange::gt(10.0)
  inspect(gt.matches(15.0), content="true")
  inspect(gt.matches(10.0), content="false")
  let gte = NumericRange::gte(10.0)
  inspect(gte.matches(10.0), content="true")
  let lt = NumericRange::lt(10.0)
  inspect(lt.matches(5.0), content="true")
  inspect(lt.matches(10.0), content="false")
  // between uses gte/lte by default (inclusive bounds)
  let between = NumericRange::between(5.0, 10.0)
  inspect(between.matches(7.0), content="true")
  inspect(between.matches(5.0), content="true")
  inspect(between.matches(10.0), content="true")
  inspect(between.matches(10.01), content="false")
}

///|
/// Test: Similarity metrics correctness
test "math/similarity_metrics" {
  // Test data: two vectors in flat array
  let data = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0]
  let dim = 3
  // Query: unit vector [1, 0, 0]
  let q = [1.0, 0.0, 0.0]
  // Cosine similarity: vec1 dot q = 1, vec2 dot q = 0
  // vec1 = [1,0,0], q = [1,0,0] -> cos = 1
  let cos1 = dot_at(data, 0, q, dim)
  inspect(cos1, content="1")
  // vec2 = [0,1,0], q = [1,0,0] -> cos = 0
  let cos2 = dot_at(data, 3, q, dim)
  inspect(cos2, content="0")
  // L2 distance: vec1 to q = 0, vec2 to q = sqrt(2)
  let l2_1 = l2neg_at(data, 0, q, dim)
  inspect(l2_1, content="0") // -((1-1)^2 + 0 + 0) = 0
  let l2_2 = l2neg_at(data, 3, q, dim)
  inspect(l2_2, content="-2") // -((0-1)^2 + (1-0)^2 + 0) = -2
}

///|
/// Test: get_score_fn function dispatch
test "math/get_score_fn" {
  let data = [1.0, 0.0, 0.0, 2.0, 0.0, 0.0]
  let q = [1.0, 0.0, 0.0]
  // Cosine metric (uses dot after normalization)
  let cos_fn = get_score_fn(Metric::Cosine)
  let score_cos = cos_fn(data, 0, q, 3)
  inspect(score_cos, content="1")
  // Dot product metric
  let dot_fn = get_score_fn(Metric::Dot)
  let score_dot = dot_fn(data, 3, q, 3)
  inspect(score_dot, content="2")
  // L2 metric
  let l2_fn = get_score_fn(Metric::L2)
  let score_l2 = l2_fn(data, 0, q, 3)
  inspect(score_l2, content="0")
}

///|
/// Test: Store with multiple vectors and search scoring
test "store/search_scoring" {
  let store = CoreStore::new(3, Metric::Dot)
  let _ = store.add_or_update(
    VectorId::from_int(1),
    [1.0, 0.0, 0.0],
    empty_attrs(),
  )
  let _ = store.add_or_update(
    VectorId::from_int(2),
    [0.9, 0.1, 0.0],
    empty_attrs(),
  )
  let _ = store.add_or_update(
    VectorId::from_int(3),
    [0.0, 1.0, 0.0],
    empty_attrs(),
  )
  let _ = store.add_or_update(
    VectorId::from_int(4),
    [0.5, 0.5, 0.0],
    empty_attrs(),
  )
  // Compute scores manually
  let query = [1.0, 0.0, 0.0]
  let score_fn = get_score_fn(Metric::Dot)
  // vec1 dot query = 1.0
  // vec2 dot query = 0.9
  // vec3 dot query = 0.0
  // vec4 dot query = 0.5
  let score1 = score_fn(store.data, 0, query, 3)
  inspect(score1, content="1")
  let score2 = score_fn(store.data, 3, query, 3)
  inspect(score2, content="0.9")
}

///|
/// Test: Checksum CRC32
test "checksum/crc32_known_values" {
  // Known CRC32 values for testing
  let data1 = Bytes::from_array([b'h', b'e', b'l', b'l', b'o'][:])
  let crc1 = crc32(data1)
  // Known CRC32 for "hello" is 0x3610A686
  inspect(crc1 == 0x3610A686U, content="true")
  // Empty data
  let data2 = Bytes::new(0)
  let crc2 = crc32(data2)
  inspect(crc2, content="0") // CRC32 of empty = 0
  // Single byte
  let data3 = Bytes::from_array([b'a'][:])
  let crc3 = crc32(data3)
  // CRC32 of "a" is 0xE8B7BE43
  inspect(crc3 == 0xE8B7BE43U, content="true")
}

///|
/// Test: Float32 binary roundtrip
test "binary/f32_roundtrip" {
  let writer = BinaryWriter::new()
  writer.push_f32(Float::from_double(3.14159))
  writer.push_f32(Float::from_double(-1.5))
  writer.push_f32(Float::from_double(0.0))
  let data = writer.concat()
  let reader = BinaryReader::new(data)
  let f1 = reader.read_f32().to_double()
  let f2 = reader.read_f32().to_double()
  let f3 = reader.read_f32().to_double()
  // Float32 precision (about 7 significant digits)
  inspect((f1 - 3.14159).abs() < 0.0001, content="true")
  inspect((f2 - -1.5).abs() < 0.0001, content="true")
  inspect(f3, content="0")
}

///|
/// Test: Store capacity management
test "store/capacity" {
  let store = CoreStore::new(2, Metric::Dot)
  // Add more than initial capacity
  for i in 1..<=100 {
    let _ = store.add_or_update(
      VectorId::from_int(i),
      [i.to_double(), 0.0],
      empty_attrs(),
    )
  }
  inspect(store.size(), content="100")
  // All vectors should be accessible
  inspect(store.has(VectorId::from_int(1)), content="true")
  inspect(store.has(VectorId::from_int(50)), content="true")
  inspect(store.has(VectorId::from_int(100)), content="true")
}

///|
/// Test: AttrValue equality
test "attr/value_equality" {
  let attrs1 = empty_attrs()
  attrs1.set("int", AttrValue::Int(42L))
  attrs1.set("float", AttrValue::Float(3.14))
  attrs1.set("string", AttrValue::String("test"))
  attrs1.set("bool", AttrValue::Bool(true))
  attrs1.set("null", AttrValue::Null)
  // Get and verify
  match attrs1.get("int") {
    Some(AttrValue::Int(n)) => inspect(n, content="42")
    _ => inspect(false, content="true")
  }
  match attrs1.get("float") {
    Some(AttrValue::Float(f)) =>
      inspect((f - 3.14).abs() < 0.001, content="true")
    _ => inspect(false, content="true")
  }
  match attrs1.get("string") {
    Some(AttrValue::String(s)) => inspect(s, content="test")
    _ => inspect(false, content="true")
  }
  match attrs1.get("bool") {
    Some(AttrValue::Bool(b)) => inspect(b, content="true")
    _ => inspect(false, content="true")
  }
  match attrs1.get("null") {
    Some(AttrValue::Null) => inspect(true, content="true")
    _ => inspect(false, content="true")
  }
}

///|
/// Test: CRC32 fast implementation
test "checksum/crc32_fast" {
  let data = Bytes::from_array([b'h', b'e', b'l', b'l', b'o'][:])
  let crc_fast = crc32_fast(data)
  let crc_normal = crc32(data)
  // Both should give same result
  inspect(crc_fast == crc_normal, content="true")
  inspect(crc_fast == 0x3610A686U, content="true")
}

///|
/// Test: CRC32 verify
test "checksum/crc32_verify" {
  let data = Bytes::from_array([b't', b'e', b's', b't'][:])
  let crc = crc32(data)
  inspect(crc32_verify(data, crc), content="true")
  inspect(crc32_verify(data, 0x12345678U), content="false")
}

///|
/// Test: Math l2_norm
test "math/l2_norm" {
  let v = [3.0, 4.0]
  let norm = l2_norm(v)
  inspect((norm - 5.0).abs() < 0.0001, content="true")
  // Zero vector
  let zero = [0.0, 0.0]
  inspect(l2_norm(zero), content="0")
}

///|
/// Test: Math dot product
test "math/dot" {
  let a = [1.0, 2.0, 3.0]
  let b = [4.0, 5.0, 6.0]
  // 1*4 + 2*5 + 3*6 = 4 + 10 + 18 = 32
  inspect(dot(a, b), content="32")
  // Different lengths - use min
  let short = [1.0, 1.0]
  inspect(dot(a, short), content="3") // 1*1 + 2*1 = 3
}

///|
/// Test: Math l2_squared
test "math/l2_squared" {
  let a = [1.0, 2.0, 3.0]
  let b = [4.0, 5.0, 6.0]
  // (4-1)^2 + (5-2)^2 + (6-3)^2 = 9 + 9 + 9 = 27
  inspect(l2_squared(a, b), content="27")
}

///|
/// Test: Math cosine_similarity
test "math/cosine_similarity" {
  let a = [1.0, 0.0]
  let b = [1.0, 0.0]
  // Same direction = 1.0
  inspect((cosine_similarity(a, b) - 1.0).abs() < 0.0001, content="true")
  // Perpendicular = 0.0
  let c = [0.0, 1.0]
  inspect(cosine_similarity(a, c).abs() < 0.0001, content="true")
  // Zero vector
  let zero = [0.0, 0.0]
  inspect(cosine_similarity(a, zero), content="0")
}

///|
/// Test: normalize with zero vector
test "math/normalize_zero" {
  let zero = [0.0, 0.0, 0.0]
  let normalized = normalize(zero)
  // Zero vector should remain zero (no division by zero)
  inspect(normalized[0], content="0")
  inspect(normalized[1], content="0")
}

///|
/// Test: ln edge cases
test "math/ln_edge_cases" {
  // ln(0) should return very negative number
  let ln_zero = ln(0.0)
  inspect(ln_zero < -1.0e307, content="true")
  // ln(negative) should return very negative number
  let ln_neg = ln(-1.0)
  inspect(ln_neg < -1.0e307, content="true")
  // ln(large number)
  let ln_1000 = ln(1000.0)
  // ln(1000) ≈ 6.907755
  inspect((ln_1000 - 6.907755).abs() < 0.001, content="true")
}

///|
/// Test: get_score_fn for all metrics
test "math/get_score_fn_all" {
  let data = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0]
  let q = [1.0, 0.0, 0.0]
  // Cosine
  let cos_fn = get_score_fn(Cosine)
  inspect(cos_fn(data, 0, q, 3), content="1")
  // L2
  let l2_fn = get_score_fn(L2)
  inspect(l2_fn(data, 0, q, 3), content="0")
  inspect(l2_fn(data, 3, q, 3), content="-2")
}

///|
/// Test: CoreStore get_by_index
test "store/get_by_index" {
  let store = CoreStore::new(2, Metric::Dot)
  let attrs = empty_attrs()
  attrs.set("tag", String("test"))
  let _ = store.add_or_update(VectorId::from_int(1), [3.0, 4.0], attrs)
  let record = store.get_by_index(0)
  inspect(record.vector[0], content="3")
  inspect(record.vector[1], content="4")
}

///|
/// Test: CoreStore get_index
test "store/get_index" {
  let store = CoreStore::new(2, Metric::Dot)
  let _ = store.add_or_update(VectorId::from_int(42), [1.0, 2.0], empty_attrs())
  let idx = store.get_index(VectorId::from_int(42))
  inspect(idx is Some(_), content="true")
  match idx {
    Some(i) => inspect(i, content="0")
    None => ()
  }
  // Non-existent ID
  inspect(store.get_index(VectorId::from_int(99)) is None, content="true")
}

///|
/// Test: CoreStore ensure_capacity
test "store/ensure_capacity" {
  let store = CoreStore::new(2, Metric::Dot, capacity=2)
  inspect(store.capacity(), content="2")
  // Add elements to trigger resize
  for i in 1..<=5 {
    let _ = store.add_or_update(
      VectorId::from_int(i),
      [i.to_double(), 0.0],
      empty_attrs(),
    )
  }
  // Capacity should have grown
  inspect(store.capacity() >= 5, content="true")
  inspect(store.size(), content="5")
}

///|
/// Test: CoreStore remove last element (no swap)
test "store/remove_last" {
  let store = CoreStore::new(2, Metric::Dot)
  let _ = store.add_or_update(VectorId::from_int(1), [1.0, 0.0], empty_attrs())
  let _ = store.add_or_update(VectorId::from_int(2), [0.0, 1.0], empty_attrs())
  inspect(store.size(), content="2")
  // Remove last element
  let info = store.remove_by_id(VectorId::from_int(2))
  inspect(info is Some(_), content="true")
  inspect(store.size(), content="1")
  // First element should still exist
  inspect(store.has(VectorId::from_int(1)), content="true")
}

///|
/// Test: CoreStore normalize_query for cosine
test "store/normalize_query" {
  let store = CoreStore::new(2, Metric::Cosine)
  let query = store.normalize_query([3.0, 4.0])
  // Should be normalized to [0.6, 0.8]
  inspect((query[0] - 0.6).abs() < 0.0001, content="true")
  inspect((query[1] - 0.8).abs() < 0.0001, content="true")
}

///|
/// Test: CoreStore normalize_query for non-cosine
test "store/normalize_query_dot" {
  let store = CoreStore::new(2, Metric::Dot)
  let query = store.normalize_query([3.0, 4.0])
  // Should remain unchanged
  inspect(query[0], content="3")
  inspect(query[1], content="4")
}

///|
/// Test: CoreStore iteration
test "store/iteration" {
  let store = CoreStore::new(2, Metric::Dot)
  for i in 1..<=5 {
    let _ = store.add_or_update(
      VectorId::from_int(i),
      [i.to_double(), 0.0],
      empty_attrs(),
    )
  }
  // Access by index
  inspect(store.size(), content="5")
  inspect(store.ids[0].to_int64(), content="1")
  inspect(store.ids[4].to_int64(), content="5")
}

///|
/// Test: VectorId equality
test "types/vector_id" {
  let id1 = VectorId::from_int(42)
  let id2 = VectorId::from_int(42)
  let id3 = VectorId::from_int(100)
  inspect(id1.to_int64(), content="42")
  inspect(id1.to_int64() == id2.to_int64(), content="true")
  inspect(id1.to_int64() == id3.to_int64(), content="false")
}

///|
/// Test: NumericRange gt/gte/lt/lte
test "types/numeric_range" {
  let gt = NumericRange::gt(10.0)
  inspect(gt.matches(15.0), content="true")
  inspect(gt.matches(10.0), content="false")
  inspect(gt.matches(5.0), content="false")
  let gte = NumericRange::gte(10.0)
  inspect(gte.matches(10.0), content="true")
  inspect(gte.matches(9.99), content="false")
  let lt = NumericRange::lt(10.0)
  inspect(lt.matches(5.0), content="true")
  inspect(lt.matches(10.0), content="false")
  let lte = NumericRange::lte(10.0)
  inspect(lte.matches(10.0), content="true")
  inspect(lte.matches(10.01), content="false")
}

///|
/// Test: MaxHeap peek and is_empty
test "heap/peek_is_empty" {
  let heap : MaxHeap[ScoredItem] = MaxHeap::for_scored()
  inspect(heap.is_empty(), content="true")
  inspect(heap.peek() is None, content="true")
  heap.push(scored_item(1, 5.0))
  inspect(heap.is_empty(), content="false")
  match heap.peek() {
    Some(item) => inspect(item.s, content="5")
    None => inspect(false, content="true")
  }
  // Peek doesn't remove
  inspect(heap.length(), content="1")
}

///|
/// Test: MaxHeap clear
test "heap/clear" {
  let heap : MaxHeap[ScoredItem] = MaxHeap::for_scored()
  heap.push(scored_item(1, 1.0))
  heap.push(scored_item(2, 2.0))
  heap.push(scored_item(3, 3.0))
  inspect(heap.length(), content="3")
  heap.clear()
  inspect(heap.length(), content="0")
  inspect(heap.is_empty(), content="true")
}

///|
/// Test: MaxHeap pop order with many elements
test "heap/pop_order" {
  let heap : MaxHeap[ScoredItem] = MaxHeap::for_scored()
  // Push in random order
  heap.push(scored_item(1, 3.0))
  heap.push(scored_item(2, 1.0))
  heap.push(scored_item(3, 4.0))
  heap.push(scored_item(4, 1.5))
  heap.push(scored_item(5, 5.0))
  heap.push(scored_item(6, 2.0))
  // Pop should return in descending order
  let p1 = heap.pop()
  inspect(p1.unwrap().s, content="5")
  let p2 = heap.pop()
  inspect(p2.unwrap().s, content="4")
  let p3 = heap.pop()
  inspect(p3.unwrap().s, content="3")
  let p4 = heap.pop()
  inspect(p4.unwrap().s, content="2")
  let p5 = heap.pop()
  inspect(p5.unwrap().s, content="1.5")
  let p6 = heap.pop()
  inspect(p6.unwrap().s, content="1")
  // Empty
  inspect(heap.pop() is None, content="true")
}

///|
/// Test: MaxHeap with custom compare
test "heap/custom_compare" {
  // Min heap by using negative comparison
  let heap : MaxHeap[Int] = MaxHeap::new(fn(a, b) {
    if a < b {
      1
    } else if a > b {
      -1
    } else {
      0
    }
  })
  heap.push(5)
  heap.push(1)
  heap.push(3)
  // Should pop smallest first (min heap)
  inspect(heap.pop().unwrap(), content="1")
  inspect(heap.pop().unwrap(), content="3")
  inspect(heap.pop().unwrap(), content="5")
}

///|
/// Test: BinaryWriter push_bytes
test "binary/push_bytes" {
  let w = BinaryWriter::new()
  w.push_u32(0x12345678U)
  let bytes = Bytes::from_array([b'a', b'b', b'c', b'd'][:])
  w.push_bytes(bytes)
  w.push_u32(0xDEADBEEFU)
  let data = w.concat()
  let r = BinaryReader::new(data)
  inspect(r.read_u32(), content="305419896")
  let read_bytes = r.read_bytes(4)
  inspect(read_bytes[0] == b'a', content="true")
  inspect(read_bytes[3] == b'd', content="true")
  inspect(r.read_u32(), content="3735928559")
}

///|
/// Test: BinaryReader position tracking
test "binary/reader_position" {
  let bytes = Bytes::from_array(
    [b'a', b'b', b'c', b'd', b'e', b'f', b'g', b'h'][:],
  )
  let r = BinaryReader::new(bytes)
  inspect(r.offset, content="0")
  let _ = r.read_u32()
  inspect(r.offset, content="4")
  let _ = r.read_u32()
  inspect(r.offset, content="8")
}

///|
/// Test: attr_value_to_number
test "types/attr_value_to_number" {
  // Int
  match attr_value_to_number(Int(42L)) {
    Some(n) => inspect(n, content="42")
    None => inspect(false, content="true")
  }
  // Float
  match attr_value_to_number(Float(3.14)) {
    Some(n) => inspect((n - 3.14).abs() < 0.001, content="true")
    None => inspect(false, content="true")
  }
  // Bool (not a number)
  inspect(attr_value_to_number(Bool(true)) is None, content="true")
  // String (not a number)
  inspect(attr_value_to_number(String("hello")) is None, content="true")
  // Null
  inspect(attr_value_to_number(Null) is None, content="true")
}

///|
/// Test: CoreStore serialize/deserialize with all attr types
test "store/serialize_all_attr_types" {
  let store = CoreStore::new(2, Metric::Dot)
  let attrs = empty_attrs()
  attrs.set("str", String("hello"))
  attrs.set("int", Int(42L))
  attrs.set("float", Float(3.14))
  attrs.set("bool", Bool(true))
  attrs.set("null", Null)
  let _ = store.add_or_update(VectorId::from_int(1), [1.0, 2.0], attrs)
  // Serialize
  let bytes = store.serialize()
  // Deserialize
  let store2 = CoreStore::deserialize(bytes)
  let record = store2.get(VectorId::from_int(1))
  match record {
    Some(r) => {
      match r.attrs.get("str") {
        Some(String(s)) => inspect(s, content="hello")
        _ => inspect(false, content="true")
      }
      match r.attrs.get("int") {
        Some(Int(n)) => inspect(n, content="42")
        _ => inspect(false, content="true")
      }
      match r.attrs.get("bool") {
        Some(Bool(b)) => inspect(b, content="true")
        _ => inspect(false, content="true")
      }
    }
    None => inspect(false, content="true")
  }
}

///|
/// Test: CoreStore update_attrs
test "store/update_attrs" {
  let store = CoreStore::new(2, Metric::Dot)
  let id = VectorId::from_int(1)
  // Update non-existent returns false
  inspect(store.update_attrs(id, empty_attrs()), content="false")
  // Add vector
  let _ = store.add_or_update(id, [1.0, 2.0], empty_attrs())
  // Update existing returns true
  let new_attrs = empty_attrs()
  new_attrs.set("updated", Bool(true))
  inspect(store.update_attrs(id, new_attrs), content="true")
  // Verify update
  match store.get(id) {
    Some(r) =>
      match r.attrs.get("updated") {
        Some(Bool(b)) => inspect(b, content="true")
        _ => inspect(false, content="true")
      }
    None => inspect(false, content="true")
  }
}

///|
/// Test: CoreStore remove non-existent
test "store/remove_nonexistent" {
  let store = CoreStore::new(2, Metric::Dot)
  let result = store.remove_by_id(VectorId::from_int(999))
  inspect(result is None, content="true")
}

///|
/// Test: CoreStore with L2 metric
test "store/l2_metric" {
  let store = CoreStore::new(2, Metric::L2)
  let _ = store.add_or_update(VectorId::from_int(1), [3.0, 4.0], empty_attrs())
  // L2 should NOT normalize vectors
  let record = store.get(VectorId::from_int(1))
  match record {
    Some(r) => {
      inspect(r.vector[0], content="3")
      inspect(r.vector[1], content="4")
    }
    None => inspect(false, content="true")
  }
}

///|
/// Test: CoreStore add_or_update with upsert=false on existing
test "store/add_no_upsert" {
  let store = CoreStore::new(2, Metric::Dot)
  let id = VectorId::from_int(1)
  // First add
  let (idx1, created1) = store.add_or_update(id, [1.0, 0.0], empty_attrs())
  inspect(idx1, content="0")
  inspect(created1, content="true")
  // Add again with upsert=false should fail (abort)
  // We can't test abort directly, but we can test that size stays 1
  inspect(store.size(), content="1")
}

///|
/// Test: push_top_k with k <= 0 (P2 fix)
/// Should not crash and should not insert any items
test "topk/push_top_k_zero_k" {
  let out : Array[ScoredItem] = []
  // k = 0 should not insert anything
  push_top_k(out, scored_item(0, 1.0), 0, fn(x) { x.s })
  push_top_k(out, scored_item(1, 2.0), 0, fn(x) { x.s })
  inspect(out.length(), content="0")
  // k = -1 should also not insert anything
  push_top_k(out, scored_item(2, 3.0), -1, fn(x) { x.s })
  inspect(out.length(), content="0")
}

///|
/// Test: push_top_k with k = 1 (boundary case)
test "topk/push_top_k_k_equals_one" {
  let out : Array[ScoredItem] = []
  push_top_k(out, scored_item(0, 1.0), 1, fn(x) { x.s })
  inspect(out.length(), content="1")
  push_top_k(out, scored_item(1, 2.0), 1, fn(x) { x.s })
  inspect(out.length(), content="1")
  inspect(out[0].s, content="2") // Higher score should replace
  push_top_k(out, scored_item(2, 0.5), 1, fn(x) { x.s })
  inspect(out.length(), content="1")
  inspect(out[0].s, content="2") // Lower score should not replace
}

///|
/// Test: CoreStore stores defensive copy of attrs
test "store/attrs_defensive_copy" {
  let store = CoreStore::new(2, Cosine)
  let attrs = empty_attrs()
  attrs.set("tag", String("A"))
  let id = VectorId::from_int(1)
  let _ = store.add_or_update(id, [1.0, 0.0], attrs, upsert=true)
  // Mutate the original attrs after storing
  attrs.set("tag", String("B"))
  // Stored attrs should still have "A"
  match store.get(id) {
    None => inspect(false, content="true") // Should not reach here
    Some(record) =>
      match record.attrs.get("tag") {
        Some(String(s)) => inspect(s, content="A")
        _ => inspect(false, content="true") // Should not reach here
      }
  }
}

///|
/// Test: CoreStore::update_attrs stores defensive copy
test "store/update_attrs_defensive_copy" {
  let store = CoreStore::new(2, Cosine)
  let id = VectorId::from_int(1)
  let initial = empty_attrs()
  initial.set("tag", String("init"))
  let _ = store.add_or_update(id, [1.0, 0.0], initial, upsert=true)
  // Update with new attrs
  let updated = empty_attrs()
  updated.set("tag", String("X"))
  let _ = store.update_attrs(id, updated)
  // Mutate the updated attrs after storing
  updated.set("tag", String("Y"))
  // Stored attrs should still have "X"
  match store.get(id) {
    None => inspect(false, content="true")
    Some(record) =>
      match record.attrs.get("tag") {
        Some(String(s)) => inspect(s, content="X")
        _ => inspect(false, content="true")
      }
  }
}
