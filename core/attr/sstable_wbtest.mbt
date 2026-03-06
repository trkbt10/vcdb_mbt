///|
/// BloomFilter create and query
test "sstable/bloom_filter" {
  let keys = [
    Bytes::from_array([b'a', b'b', b'c'][:]),
    Bytes::from_array([b'd', b'e', b'f'][:]),
    Bytes::from_array([b'g', b'h', b'i'][:]),
  ]
  let bloom = BloomFilter::create(keys, 0.01)
  inspect(
    bloom.might_contain(Bytes::from_array([b'a', b'b', b'c'][:])),
    content="true",
  )
  inspect(
    bloom.might_contain(Bytes::from_array([b'd', b'e', b'f'][:])),
    content="true",
  )
  let not_in = Bytes::from_array([b'x', b'y', b'z'][:])
  let _ = bloom.might_contain(not_in)
}

///|
/// BloomFilter empty keys
test "sstable/bloom_filter_empty" {
  let bloom = BloomFilter::create([], 0.01)
  inspect(bloom.hash_count, content="1")
  inspect(bloom.bit_count, content="8")
}

///|
/// BloomFilter encode/decode
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
/// SSTableRecord encode/decode
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
      inspect(bytes_read, content="16")
    }
    None => inspect(false, content="true")
  }
}

///|
/// SSTableRecord decode invalid
test "sstable/record_decode_invalid" {
  let short_buf = Bytes::from_array([b'\x00', b'\x00'][:])
  inspect(SSTableRecord::decode(short_buf, 0) is None, content="true")
  let buf = Bytes::from_array(
    [b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00'][:],
  )
  inspect(SSTableRecord::decode(buf, 100) is None, content="true")
}

///|
/// SSTableFooter encode/decode
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
/// SSTableFooter decode invalid magic
test "sstable/footer_invalid_magic" {
  let buf = Bytes::from_array(FixedArray::make(32, b'\x00'))
  inspect(SSTableFooter::decode(buf) is None, content="true")
}

///|
/// SSTable build and read
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
/// SSTable find
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
      let found = table.find(Bytes::from_array([b'b', b'b', b'b'][:]))
      match found {
        Some(r) => inspect(r.value[0] == b'2', content="true")
        None => inspect(false, content="true")
      }
      let not_found = table.find(Bytes::from_array([b'x', b'x', b'x'][:]))
      inspect(not_found is None, content="true")
    }
    None => inspect(false, content="true")
  }
}

///|
/// SSTable with empty records
test "sstable/empty_records" {
  let records : Array[SSTableRecord] = []
  let bytes = SSTable::build(records, 1)
  match SSTable::read(bytes) {
    Some(table) => inspect(table.records.length(), content="0")
    None => inspect(false, content="true")
  }
}

///|
/// SSTable::read returns None for corrupted footer bounds
test "sstable/read_invalid_bounds" {
  let records : Array[SSTableRecord] = [
    { key: b"key1", value: b"val1" },
    { key: b"key2", value: b"val2" },
  ]
  let valid_data = SSTable::build(records, 1)
  let corrupted : FixedArray[Byte] = FixedArray::make(
    valid_data.length(),
    b'\x00',
  )
  for i in 0..<valid_data.length() {
    corrupted[i] = valid_data[i]
  }
  let footer_start = valid_data.length() - 32
  corrupted[footer_start + 12] = b'\xFF'
  corrupted[footer_start + 13] = b'\xFF'
  corrupted[footer_start + 14] = b'\xFF'
  corrupted[footer_start + 15] = b'\x7F'
  let corrupted_bytes = Bytes::from_array(corrupted)
  let result = SSTable::read(corrupted_bytes)
  inspect(result is None, content="true")
}
