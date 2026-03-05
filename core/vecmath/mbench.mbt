///|
/// Benchmark: dot_at with 128-dim vectors
test "bench/dot_at_128" (b : @bench.T) {
  let dim = 128
  let data = Array::make(dim, 0.5)
  let query = Array::make(dim, 0.3)
  b.bench(fn() { b.keep(dot_at(data, 0, query, dim).reinterpret_as_int64()) })
}

///|
/// Benchmark: dot_at with 256-dim vectors
test "bench/dot_at_256" (b : @bench.T) {
  let dim = 256
  let data = Array::make(dim, 0.5)
  let query = Array::make(dim, 0.3)
  b.bench(fn() { b.keep(dot_at(data, 0, query, dim).reinterpret_as_int64()) })
}

///|
/// Benchmark: dot_at with 768-dim vectors (BERT-like)
test "bench/dot_at_768" (b : @bench.T) {
  let dim = 768
  let data = Array::make(dim, 0.5)
  let query = Array::make(dim, 0.3)
  b.bench(fn() { b.keep(dot_at(data, 0, query, dim).reinterpret_as_int64()) })
}

///|
/// Benchmark: l2neg_at with 128-dim vectors
test "bench/l2neg_at_128" (b : @bench.T) {
  let dim = 128
  let data = Array::make(dim, 0.5)
  let query = Array::make(dim, 0.3)
  b.bench(fn() { b.keep(l2neg_at(data, 0, query, dim).reinterpret_as_int64()) })
}

///|
/// Benchmark: l2neg_at with 256-dim vectors
test "bench/l2neg_at_256" (b : @bench.T) {
  let dim = 256
  let data = Array::make(dim, 0.5)
  let query = Array::make(dim, 0.3)
  b.bench(fn() { b.keep(l2neg_at(data, 0, query, dim).reinterpret_as_int64()) })
}

///|
/// Benchmark: l2neg_at with 768-dim vectors
test "bench/l2neg_at_768" (b : @bench.T) {
  let dim = 768
  let data = Array::make(dim, 0.5)
  let query = Array::make(dim, 0.3)
  b.bench(fn() { b.keep(l2neg_at(data, 0, query, dim).reinterpret_as_int64()) })
}

///|
/// Benchmark: normalize_in_place with 128-dim vector
test "bench/normalize_128" (b : @bench.T) {
  let dim = 128
  let vec = Array::make(dim, 0.5)
  b.bench(fn() {
    normalize_in_place(vec)
    b.keep(vec[0].reinterpret_as_int64())
  })
}

///|
/// Benchmark: normalize_in_place with 768-dim vector
test "bench/normalize_768" (b : @bench.T) {
  let dim = 768
  let vec = Array::make(dim, 0.5)
  b.bench(fn() {
    normalize_in_place(vec)
    b.keep(vec[0].reinterpret_as_int64())
  })
}

///|
/// Benchmark: l2_norm with 128-dim vector
test "bench/l2_norm_128" (b : @bench.T) {
  let dim = 128
  let vec = Array::make(dim, 0.5)
  b.bench(fn() { b.keep(l2_norm(vec).reinterpret_as_int64()) })
}

///|
/// Benchmark: dot with 128-dim vectors
test "bench/dot_128" (b : @bench.T) {
  let dim = 128
  let a = Array::make(dim, 0.5)
  let b_ = Array::make(dim, 0.3)
  b.bench(fn() { b.keep(dot(a, b_).reinterpret_as_int64()) })
}

///|
/// Benchmark: l2_squared with 128-dim vectors
test "bench/l2_squared_128" (b : @bench.T) {
  let dim = 128
  let a = Array::make(dim, 0.5)
  let b_ = Array::make(dim, 0.3)
  b.bench(fn() { b.keep(l2_squared(a, b_).reinterpret_as_int64()) })
}

///|
/// Benchmark: cosine_similarity with 128-dim vectors
test "bench/cosine_similarity_128" (b : @bench.T) {
  let dim = 128
  let a = Array::make(dim, 0.5)
  let b_ = Array::make(dim, 0.3)
  b.bench(fn() { b.keep(cosine_similarity(a, b_).reinterpret_as_int64()) })
}
