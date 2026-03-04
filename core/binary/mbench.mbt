///|
/// Benchmark: crc32 small data (32 bytes)
test "bench/crc32_32_bytes" (b : @bench.T) {
  let data = Bytes::make(32, b'\x5A')
  b.bench(fn() { b.keep(crc32(data).reinterpret_as_int()) })
}

///|
/// Benchmark: crc32 medium data (256 bytes)
test "bench/crc32_256_bytes" (b : @bench.T) {
  let data = Bytes::make(256, b'\x5A')
  b.bench(fn() { b.keep(crc32(data).reinterpret_as_int()) })
}

///|
/// Benchmark: crc32 large data (4KB)
test "bench/crc32_4kb" (b : @bench.T) {
  let data = Bytes::make(4096, b'\x5A')
  b.bench(fn() { b.keep(crc32(data).reinterpret_as_int()) })
}

///|
/// Benchmark: crc32_fast small data (32 bytes)
test "bench/crc32_fast_32_bytes" (b : @bench.T) {
  let data = Bytes::make(32, b'\x5A')
  b.bench(fn() { b.keep(crc32_fast(data).reinterpret_as_int()) })
}

///|
/// Benchmark: crc32_fast medium data (256 bytes)
test "bench/crc32_fast_256_bytes" (b : @bench.T) {
  let data = Bytes::make(256, b'\x5A')
  b.bench(fn() { b.keep(crc32_fast(data).reinterpret_as_int()) })
}

///|
/// Benchmark: crc32_fast large data (4KB)
test "bench/crc32_fast_4kb" (b : @bench.T) {
  let data = Bytes::make(4096, b'\x5A')
  b.bench(fn() { b.keep(crc32_fast(data).reinterpret_as_int()) })
}

///|
/// Benchmark: crc32_verify
test "bench/crc32_verify" (b : @bench.T) {
  let data = Bytes::make(128, b'\xAB')
  let expected = crc32(data)
  b.bench(fn() { b.keep(crc32_verify(data, expected)) })
}

///|
/// Benchmark: BinaryWriter push operations
test "bench/binary_writer_push" (b : @bench.T) {
  b.bench(fn() {
    let w = BinaryWriter::new()
    for i in 0..<100 {
      w.push_u32(i.reinterpret_as_uint())
      w.push_u64(i.to_int64().reinterpret_as_uint64())
      w.push_f32(Float::from_double(i.to_double()))
    }
    b.keep(w.concat().length())
  })
}

///|
/// Benchmark: BinaryWriter push_bytes
test "bench/binary_writer_push_bytes" (b : @bench.T) {
  let chunk = Bytes::make(64, b'\xCC')
  b.bench(fn() {
    let w = BinaryWriter::new()
    for _ in 0..<50 {
      w.push_bytes(chunk)
    }
    b.keep(w.concat().length())
  })
}

///|
/// Benchmark: BinaryReader sequential reads
test "bench/binary_reader_sequential" (b : @bench.T) {
  let w = BinaryWriter::new()
  for i in 0..<100 {
    w.push_u32(i.reinterpret_as_uint())
    w.push_u64(i.to_int64().reinterpret_as_uint64())
    w.push_f32(Float::from_double(i.to_double()))
  }
  let data = w.concat()
  b.bench(fn() {
    let r = BinaryReader::new(data)
    let mut sum = 0
    for _ in 0..<100 {
      sum = sum + r.read_u32().reinterpret_as_int()
      sum = sum + r.read_u64().reinterpret_as_int64().to_int()
      sum = sum + r.read_f32().to_double().to_int()
    }
    b.keep(sum)
  })
}

///|
/// Benchmark: BinaryReader read_bytes
test "bench/binary_reader_read_bytes" (b : @bench.T) {
  let w = BinaryWriter::new()
  for _ in 0..<50 {
    w.push_bytes(Bytes::make(64, b'\xDD'))
  }
  let data = w.concat()
  b.bench(fn() {
    let r = BinaryReader::new(data)
    let mut total = 0
    for _ in 0..<50 {
      let chunk = r.read_bytes(64)
      total = total + chunk.length()
    }
    b.keep(total)
  })
}

///|
/// Benchmark: BinaryReader skip
test "bench/binary_reader_skip" (b : @bench.T) {
  let data = Bytes::make(1000, b'\xEE')
  b.bench(fn() {
    let r = BinaryReader::new(data)
    for _ in 0..<50 {
      r.skip(20)
    }
    b.keep(r.remaining())
  })
}
