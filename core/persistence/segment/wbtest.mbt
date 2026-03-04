// Whitebox tests for segment module

///|
test "index_file/decode_metric_all" {
  inspect(decode_metric(0) == @core.Cosine, content="true")
  inspect(decode_metric(1) == @core.L2, content="true")
  inspect(decode_metric(2) == @core.Dot, content="true")
  // Unknown codes default to Cosine
  inspect(decode_metric(99) == @core.Cosine, content="true")
}

///|
test "index_file/encode_metric_all" {
  inspect(encode_metric(@core.Cosine), content="0")
  inspect(encode_metric(@core.L2), content="1")
  inspect(encode_metric(@core.Dot), content="2")
}

///|
test "index_file/encode_strategy_all" {
  inspect(encode_strategy(@core.Bruteforce), content="0")
  inspect(encode_strategy(@core.HNSW(@core.HNSWParams::default())), content="1")
  inspect(encode_strategy(@core.IVF({ nlist: 4, nprobe: 2 })), content="2")
}

///|
test "index_file/decode_strategy_type" {
  inspect(decode_strategy_type(0), content="0")
  inspect(decode_strategy_type(1), content="1")
  inspect(decode_strategy_type(2), content="2")
}

///|
test "index_file/header_from_store" {
  let store = @core.CoreStore::new(4, @core.L2, capacity=10)
  for i in 1..<=3 {
    let _ = store.add_or_update(
      @core.VectorId::from_int(i),
      [1.0, 2.0, 3.0, 4.0],
      @core.empty_attrs(),
      upsert=false,
    )
  }
  let header = IndexHeader::from_store(
    store,
    @core.IVF({ nlist: 8, nprobe: 2 }),
    true,
  )
  inspect(header.metric_code, content="1") // L2
  inspect(header.dim, content="4")
  inspect(header.count, content="3")
  inspect(header.strategy_code, content="2") // IVF
  inspect(header.has_ann, content="true")
}

///|
test "index_file/utf8_segment_names" {
  let header : IndexHeader = {
    metric_code: 0,
    dim: 2,
    count: 2,
    strategy_code: 0,
    has_ann: false,
  }
  // Test segment names with various UTF-8 encodings
  let entries = [
    IndexEntry::{
      id: @core.VectorId::from_int(1),
      ptr: DataPointer::{
        segment: "日本語セグメント",
        offset: 8,
        length: 32,
      },
    },
    IndexEntry::{
      id: @core.VectorId::from_int(2),
      ptr: DataPointer::{ segment: "emoji_🎉_test", offset: 8, length: 48 },
    },
  ]
  let bytes = encode_index_file(header, entries, None)
  let decoded = decode_index_file(bytes)
  match decoded {
    Some(d) => {
      inspect(d.entries[0].ptr.segment, content="日本語セグメント")
      inspect(d.entries[1].ptr.segment, content="emoji_🎉_test")
    }
    None => inspect(false, content="true")
  }
}

///|
test "index_file/empty_entries" {
  let header : IndexHeader = {
    metric_code: 2,
    dim: 10,
    count: 0,
    strategy_code: 1,
    has_ann: false,
  }
  let entries : Array[IndexEntry] = []
  let bytes = encode_index_file(header, entries, None)
  let decoded = decode_index_file(bytes)
  match decoded {
    Some(d) => {
      inspect(d.header.count, content="0")
      inspect(d.entries.length(), content="0")
    }
    None => inspect(false, content="true")
  }
}

///|
test "index_file/truncated_entry" {
  let header : IndexHeader = {
    metric_code: 0,
    dim: 2,
    count: 1,
    strategy_code: 0,
    has_ann: false,
  }
  let entries = [
    IndexEntry::{
      id: @core.VectorId::from_int(1),
      ptr: DataPointer::{ segment: "test", offset: 8, length: 32 },
    },
  ]
  let bytes = encode_index_file(header, entries, None)
  // Truncate to cut off part of the entry
  let w = @binary.BinaryWriter::new()
  for i in 0..<40 {
    // Only copy first 40 bytes (header + part of entry)
    if i < bytes.length() {
      w.push_byte(bytes[i])
    }
  }
  let truncated = w.concat()
  let decoded = decode_index_file(truncated)
  // Should decode header but have 0 complete entries
  match decoded {
    Some(d) => inspect(d.entries.length(), content="0")
    None => inspect(false, content="true")
  }
}

// =============================================================================
// Coverage improvement tests - distributed.mbt
// =============================================================================
