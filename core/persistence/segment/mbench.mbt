///|
/// Benchmark: SegmentWriter append single record (dim=64)
test "bench/segment_write_single" (b : @bench.T) {
  let id = @core.VectorId::from_int(1)
  let vector = Array::make(64, 0.5)
  let attrs = @core.empty_attrs()
  attrs.set("name", @core.String("test"))
  b.bench(fn() {
    let writer = SegmentWriter::new("bench_seg")
    let ptr = writer.append(id, vector, attrs)
    b.keep(ptr.length)
  })
}

///|
/// Benchmark: SegmentWriter append 100 records
test "bench/segment_write_100" (b : @bench.T) {
  let vector = Array::make(64, 0.5)
  let attrs = @core.empty_attrs()
  attrs.set("idx", @core.Int(0L))
  b.bench(fn() {
    let writer = SegmentWriter::new("bench_seg")
    for i in 0..<100 {
      let id = @core.VectorId::from_int(i)
      let _ = writer.append(id, vector, attrs)
    }
    b.keep(writer.to_bytes().length())
  })
}

///|
/// Benchmark: SegmentReader read single record
test "bench/segment_read_single" (b : @bench.T) {
  let writer = SegmentWriter::new("bench_seg")
  let id = @core.VectorId::from_int(1)
  let vector = Array::make(64, 0.5)
  let attrs = @core.empty_attrs()
  attrs.set("name", @core.String("test"))
  let ptr = writer.append(id, vector, attrs)
  let bytes = writer.to_bytes()
  let reader = SegmentReader::from_bytes("bench_seg", bytes).unwrap()
  b.bench(fn() { b.keep(reader.read_at(ptr.offset, ptr.length) is Some(_)) })
}

///|
/// Benchmark: SegmentReader collect 100 records
test "bench/segment_collect_100" (b : @bench.T) {
  let writer = SegmentWriter::new("bench_seg")
  let vector = Array::make(64, 0.5)
  for i in 0..<100 {
    let id = @core.VectorId::from_int(i)
    let attrs = @core.empty_attrs()
    attrs.set("idx", @core.Int(i.to_int64()))
    let _ = writer.append(id, vector, attrs)
  }
  let bytes = writer.to_bytes()
  let reader = SegmentReader::from_bytes("bench_seg", bytes).unwrap()
  b.bench(fn() { b.keep(reader.collect().length()) })
}

///|
/// Benchmark: string_to_utf8_segment short string
test "bench/utf8_encode_short" (b : @bench.T) {
  let s = "hello world"
  b.bench(fn() { b.keep(string_to_utf8_segment(s).length()) })
}

///|
/// Benchmark: utf8_to_string_segment short string
test "bench/utf8_decode_short" (b : @bench.T) {
  let s = "hello world"
  let bytes = string_to_utf8_segment(s)
  b.bench(fn() { b.keep(utf8_to_string_segment(bytes).length()) })
}

///|
/// Benchmark: JSON attrs encoding (5 fields)
test "bench/json_attrs_encode" (b : @bench.T) {
  let attrs = @core.empty_attrs()
  attrs.set("name", @core.String("test"))
  attrs.set("score", @core.Float(0.95))
  attrs.set("count", @core.Int(42L))
  attrs.set("active", @core.Bool(true))
  attrs.set("tag", @core.String("benchmark"))
  b.bench(fn() {
    let bytes = encode_attrs_for_segment(attrs)
    b.keep(bytes.length())
  })
}

///|
/// Benchmark: JSON attrs decoding (5 fields)
test "bench/json_attrs_decode" (b : @bench.T) {
  let attrs = @core.empty_attrs()
  attrs.set("name", @core.String("test"))
  attrs.set("score", @core.Float(0.95))
  attrs.set("count", @core.Int(42L))
  attrs.set("active", @core.Bool(true))
  attrs.set("tag", @core.String("benchmark"))
  let bytes = encode_attrs_for_segment(attrs)
  b.bench(fn() {
    let decoded = decode_attrs_from_segment(bytes)
    b.keep(decoded.keys().length())
  })
}
