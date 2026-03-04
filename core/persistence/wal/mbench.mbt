///|
/// Benchmark: Encode single WAL upsert record (dim=64)
test "bench/wal_encode_upsert_64" (b : @bench.T) {
  let id = @core.VectorId::from_int(12345)
  let vector = Array::make(64, 0.5)
  let attrs = @core.empty_attrs()
  attrs.set("name", @core.String("test"))
  attrs.set("score", @core.Float(0.95))
  let record = WalRecord::upsert(id, vector, attrs)
  b.bench(fn() { b.keep(encode_wal_record(record).length()) })
}

///|
/// Benchmark: Decode single WAL upsert record (dim=64)
test "bench/wal_decode_upsert_64" (b : @bench.T) {
  let id = @core.VectorId::from_int(12345)
  let vector = Array::make(64, 0.5)
  let attrs = @core.empty_attrs()
  attrs.set("name", @core.String("test"))
  attrs.set("score", @core.Float(0.95))
  let record = WalRecord::upsert(id, vector, attrs)
  let bytes = encode_wal_record(record)
  b.bench(fn() {
    let r = @binary.BinaryReader::new(bytes)
    b.keep(decode_wal_record(r) is Some(_))
  })
}

///|
/// Benchmark: Encode 100 WAL records to segment
test "bench/wal_encode_segment_100" (b : @bench.T) {
  let records : Array[WalRecord] = []
  for i in 0..<100 {
    let id = @core.VectorId::from_int(i)
    let vector = Array::make(64, i.to_double() / 100.0)
    let attrs = @core.empty_attrs()
    attrs.set("idx", @core.Int(i.to_int64()))
    records.push(WalRecord::upsert(id, vector, attrs))
  }
  b.bench(fn() { b.keep(encode_wal_segment(records).length()) })
}

///|
/// Benchmark: Decode 100 WAL records from segment
test "bench/wal_decode_segment_100" (b : @bench.T) {
  let records : Array[WalRecord] = []
  for i in 0..<100 {
    let id = @core.VectorId::from_int(i)
    let vector = Array::make(64, i.to_double() / 100.0)
    let attrs = @core.empty_attrs()
    attrs.set("idx", @core.Int(i.to_int64()))
    records.push(WalRecord::upsert(id, vector, attrs))
  }
  let bytes = encode_wal_segment(records)
  b.bench(fn() { b.keep(decode_wal_records(bytes).length()) })
}

///|
/// Benchmark: Encode WAL remove record
test "bench/wal_encode_remove" (b : @bench.T) {
  let id = @core.VectorId::from_int(999)
  let record = WalRecord::remove(id)
  b.bench(fn() { b.keep(encode_wal_record(record).length()) })
}

///|
/// Benchmark: WAL header encoding
test "bench/wal_encode_header" (b : @bench.T) {
  b.bench(fn() { b.keep(encode_wal_header().length()) })
}

///|
/// Benchmark: WAL checksum verification
test "bench/wal_verify_checksum" (b : @bench.T) {
  let records : Array[WalRecord] = []
  for i in 0..<50 {
    let id = @core.VectorId::from_int(i)
    let vector = Array::make(32, 0.5)
    records.push(WalRecord::upsert(id, vector, @core.empty_attrs()))
  }
  let bytes = encode_wal_segment(records)
  b.bench(fn() { b.keep(verify_wal_checksum(bytes)) })
}

///|
/// Benchmark: Encode upsert with large attrs (10 fields)
test "bench/wal_encode_large_attrs" (b : @bench.T) {
  let id = @core.VectorId::from_int(1)
  let vector = Array::make(64, 0.5)
  let attrs = @core.empty_attrs()
  for i in 0..<10 {
    attrs.set("field_" + i.to_string(), @core.String("value_" + i.to_string()))
  }
  let record = WalRecord::upsert(id, vector, attrs)
  b.bench(fn() { b.keep(encode_wal_record(record).length()) })
}
