///|
/// Benchmark: Vector addition - Bruteforce (100 vectors)
test "bench/add_bruteforce" (b : @bench.T) {
  let v = Array::make(128, 0.5)
  b.bench(fn() {
    let db = VectorEngine::with_dim(128)
    for i in 0..<100 {
      db.add(@types.VectorId::from_int(i), v, @types.empty_attrs())
    }
    b.keep(db.size())
  })
}

///|
/// Benchmark: Vector addition - HNSW
test "bench/add_hnsw" (b : @bench.T) {
  let db = VectorEngine::with_hnsw(128, metric=@types.Cosine)
  let v = Array::make(128, 0.5)
  let mut i = 0
  b.bench(fn() {
    i = i + 1
    db.add(@types.VectorId::from_int(i), v, @types.empty_attrs())
    b.keep(db.size())
  })
}

///|
/// Benchmark: Search on 1000 vectors - Bruteforce
test "bench/search_bruteforce_1k" (b : @bench.T) {
  let db = VectorEngine::with_dim(128)
  let v = Array::make(128, 0.5)
  for i in 0..<1000 {
    db.add(@types.VectorId::from_int(i), v, @types.empty_attrs())
  }
  let q = Array::make(128, 0.6)
  b.bench(fn() { b.keep(db.search(q, 10, None).length()) })
}

///|
/// Benchmark: Search on 1000 vectors - HNSW
test "bench/search_hnsw_1k" (b : @bench.T) {
  let db = VectorEngine::with_hnsw(128, metric=@types.Cosine)
  let v = Array::make(128, 0.5)
  for i in 0..<1000 {
    db.add(@types.VectorId::from_int(i), v, @types.empty_attrs())
  }
  let q = Array::make(128, 0.6)
  b.bench(fn() { b.keep(db.search(q, 10, None).length()) })
}

///|
/// Benchmark: dot_at for dim=128
test "bench/dot_at_128" (b : @bench.T) {
  let data = Array::make(128, 0.5)
  let q = Array::make(128, 0.6)
  b.bench(fn() { b.keep(@vecmath.dot_at(data, 0, q, 128)) })
}

///|
/// Benchmark: l2neg_at for dim=128
test "bench/l2neg_at_128" (b : @bench.T) {
  let data = Array::make(128, 0.5)
  let q = Array::make(128, 0.6)
  b.bench(fn() { b.keep(@vecmath.l2neg_at(data, 0, q, 128)) })
}

///|
/// Benchmark: normalize_in_place dim=128
test "bench/normalize_128" (b : @bench.T) {
  let v = Array::make(128, 0.5)
  b.bench(fn() {
    @vecmath.normalize_in_place(v)
    b.keep(v[0])
  })
}

///|
/// Benchmark: Serialization 100 vectors
test "bench/serialize_100" (b : @bench.T) {
  let db = VectorEngine::with_dim(64)
  for i in 0..<100 {
    let v = Array::make(64, i.to_double() / 100.0)
    db.add(@types.VectorId::from_int(i), v, @types.empty_attrs())
  }
  b.bench(fn() { b.keep(db.serialize().length()) })
}

///|
/// Benchmark: Deserialization 100 vectors
test "bench/deserialize_100" (b : @bench.T) {
  let db = VectorEngine::with_dim(64)
  for i in 0..<100 {
    let v = Array::make(64, i.to_double() / 100.0)
    db.add(@types.VectorId::from_int(i), v, @types.empty_attrs())
  }
  let bytes = db.serialize()
  b.bench(fn() { b.keep(VectorEngine::deserialize(bytes).size()) })
}

///|
/// Benchmark: Get by ID
test "bench/get_by_id" (b : @bench.T) {
  let db = VectorEngine::with_dim(64)
  for i in 0..<1000 {
    let v = Array::make(64, i.to_double() / 1000.0)
    db.add(@types.VectorId::from_int(i), v, @types.empty_attrs())
  }
  let id = @types.VectorId::from_int(500)
  b.bench(fn() { b.keep(db.get(id) is Some(_)) })
}

///|
/// Benchmark: Has check
test "bench/has_check" (b : @bench.T) {
  let db = VectorEngine::with_dim(64)
  for i in 0..<1000 {
    let v = Array::make(64, i.to_double() / 1000.0)
    db.add(@types.VectorId::from_int(i), v, @types.empty_attrs())
  }
  let id = @types.VectorId::from_int(500)
  b.bench(fn() { b.keep(db.has(id)) })
}

///|
/// Benchmark: Search on 10000 vectors - Bruteforce
test "bench/search_bruteforce_10k" (b : @bench.T) {
  let db = VectorEngine::with_dim(64)
  let v = Array::make(64, 0.5)
  for i in 0..<10000 {
    db.add(@types.VectorId::from_int(i), v, @types.empty_attrs())
  }
  let q = Array::make(64, 0.6)
  b.bench(fn() { b.keep(db.search(q, 10, None).length()) })
}

///|
/// Benchmark: Search on 10000 vectors - HNSW
test "bench/search_hnsw_10k" (b : @bench.T) {
  let db = VectorEngine::with_hnsw(64, metric=@types.Cosine)
  let v = Array::make(64, 0.5)
  for i in 0..<10000 {
    db.add(@types.VectorId::from_int(i), v, @types.empty_attrs())
  }
  let q = Array::make(64, 0.6)
  b.bench(fn() { b.keep(db.search(q, 10, None).length()) })
}

///|
/// Benchmark: dot_at for dim=64
test "bench/dot_at_64" (b : @bench.T) {
  let data = Array::make(64, 0.5)
  let q = Array::make(64, 0.6)
  b.bench(fn() { b.keep(@vecmath.dot_at(data, 0, q, 64)) })
}

///|
/// Benchmark: HNSW search with k=100
test "bench/search_hnsw_1k_k100" (b : @bench.T) {
  let db = VectorEngine::with_hnsw(64, metric=@types.Cosine)
  let v = Array::make(64, 0.5)
  for i in 0..<1000 {
    db.add(@types.VectorId::from_int(i), v, @types.empty_attrs())
  }
  let q = Array::make(64, 0.6)
  b.bench(fn() { b.keep(db.search(q, 100, None).length()) })
}
