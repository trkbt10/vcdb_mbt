///|
/// SSTable (Sorted String Table) storage format for LSM index
/// Per TypeScript spec:
/// - File sections: data, index, bloom, footer
/// - Record encoding: keyLen u32, valLen u32, key bytes, val bytes

///|
/// SSTable magic number: 'ASST' (0x54535341)
let sstable_magic : UInt = 0x54535341U

///|
/// Current SSTable format version
let sstable_version : UInt = 1U

///|
/// Footer size in bytes
let footer_size : Int = 32

///|
/// SSTable record
pub struct SSTableRecord {
  key : Bytes
  value : Bytes
}

///|
/// Sparse index entry
pub struct SparseIndexEntry {
  key : Bytes
  offset : Int
}

///|
/// SSTable footer structure
pub struct SSTableFooter {
  magic : UInt
  version : UInt
  data_offset : Int
  data_size : Int
  index_offset : Int
  index_size : Int
  bloom_offset : Int
  bloom_size : Int
}

///|
/// Bloom filter for fast negative lookups
pub struct BloomFilter {
  bits : Bytes
  hash_count : Int
  bit_count : Int
}

///|
/// Decoded SSTable structure (in-memory)
pub struct SSTable {
  records : Array[SSTableRecord]
  index : Array[SparseIndexEntry]
  bloom : BloomFilter?
  footer : SSTableFooter
}

///|
/// FNV-1a hash function
fn fnv1a(data : Bytes, seed : UInt) -> UInt {
  let mut hash = seed
  for i in 0..<data.length() {
    hash = hash ^ data[i].to_uint()
    // FNV prime 0x01000193 using multiplication
    hash = hash * 0x01000193U
  }
  hash
}

///|
/// FNV-1a hash with default seed
fn fnv1a_default(data : Bytes) -> UInt {
  fnv1a(data, 0x811c9dc5U)
}

///|
/// Create a bloom filter from a set of keys
pub fn BloomFilter::create(
  keys : Array[Bytes],
  false_positive_rate : Double,
) -> BloomFilter {
  let n = keys.length()
  if n == 0 {
    return { bits: Bytes::new(1), hash_count: 1, bit_count: 8 }
  }
  // Calculate optimal size and hash count
  // m = -n * ln(p) / (ln(2)^2)
  let ln2 = 0.693147180559945
  let m = (-n.to_double() * @math.ln(false_positive_rate) / (ln2 * ln2))
    .ceil()
    .to_int()
  let k = @cmp.maximum(1.0, (m.to_double() / n.to_double() * ln2).round()).to_int()
  let byte_count = (m + 7) / 8
  let bits_arr : FixedArray[Byte] = FixedArray::make(byte_count, b'\x00')
  for key in keys {
    let h1 = fnv1a_default(key)
    let h2 = fnv1a(key, 0x811c9dc5U ^ 0x12345678U)
    for i in 0..<k {
      let h = ((h1.reinterpret_as_int() + i * h2.reinterpret_as_int()).abs() % m).reinterpret_as_uint()
      let byte_idx = h.reinterpret_as_int() / 8
      let bit_idx = h.reinterpret_as_int() % 8
      bits_arr[byte_idx] = (bits_arr[byte_idx].to_int() | (1 << bit_idx)).to_byte()
    }
  }
  { bits: Bytes::from_array(bits_arr), hash_count: k, bit_count: m }
}

///|
/// Check if a key might be in the bloom filter
pub fn BloomFilter::might_contain(self : BloomFilter, key : Bytes) -> Bool {
  let m = self.bit_count
  let h1 = fnv1a_default(key)
  let h2 = fnv1a(key, 0x811c9dc5U ^ 0x12345678U)
  for i in 0..<self.hash_count {
    let h = ((h1.reinterpret_as_int() + i * h2.reinterpret_as_int()).abs() % m).reinterpret_as_uint()
    let byte_idx = h.reinterpret_as_int() / 8
    let bit_idx = h.reinterpret_as_int() % 8
    if (self.bits[byte_idx].to_int() & (1 << bit_idx)) == 0 {
      return false
    }
  }
  true
}

///|
/// Encode a single record to bytes
pub fn SSTableRecord::encode(self : SSTableRecord) -> Bytes {
  let w = @core.BinaryWriter::new()
  w.push_u32(self.key.length().reinterpret_as_uint())
  w.push_u32(self.value.length().reinterpret_as_uint())
  w.push_bytes(self.key)
  w.push_bytes(self.value)
  w.concat()
}

///|
/// Decode a single record from bytes at given offset
pub fn SSTableRecord::decode(
  buf : Bytes,
  offset : Int,
) -> (SSTableRecord, Int)? {
  if offset + 8 > buf.length() {
    return None
  }
  let r = @core.BinaryReader::new(buf)
  r.skip(offset)
  let key_len = r.read_u32().reinterpret_as_int()
  let val_len = r.read_u32().reinterpret_as_int()
  if offset + 8 + key_len + val_len > buf.length() {
    return None
  }
  let key = r.read_bytes(key_len)
  let value = r.read_bytes(val_len)
  Some(({ key, value }, 8 + key_len + val_len))
}

///|
/// Encode footer to bytes
pub fn SSTableFooter::encode(self : SSTableFooter) -> Bytes {
  let w = @core.BinaryWriter::new()
  w.push_u32(self.magic)
  w.push_u32(self.version)
  w.push_u32(self.data_offset.reinterpret_as_uint())
  w.push_u32(self.data_size.reinterpret_as_uint())
  w.push_u32(self.index_offset.reinterpret_as_uint())
  w.push_u32(self.index_size.reinterpret_as_uint())
  w.push_u32(self.bloom_offset.reinterpret_as_uint())
  w.push_u32(self.bloom_size.reinterpret_as_uint())
  w.concat()
}

///|
/// Decode footer from bytes
pub fn SSTableFooter::decode(buf : Bytes) -> SSTableFooter? {
  if buf.length() < footer_size {
    return None
  }
  let offset = buf.length() - footer_size
  let r = @core.BinaryReader::new(buf)
  r.skip(offset)
  let magic = r.read_u32()
  if magic != sstable_magic {
    return None
  }
  Some({
    magic,
    version: r.read_u32(),
    data_offset: r.read_u32().reinterpret_as_int(),
    data_size: r.read_u32().reinterpret_as_int(),
    index_offset: r.read_u32().reinterpret_as_int(),
    index_size: r.read_u32().reinterpret_as_int(),
    bloom_offset: r.read_u32().reinterpret_as_int(),
    bloom_size: r.read_u32().reinterpret_as_int(),
  })
}

///|
/// Encode bloom filter to bytes
pub fn BloomFilter::encode(self : BloomFilter) -> Bytes {
  let w = @core.BinaryWriter::new()
  w.push_u32(self.hash_count.reinterpret_as_uint())
  w.push_u32(self.bit_count.reinterpret_as_uint())
  w.push_bytes(self.bits)
  w.concat()
}

///|
/// Decode bloom filter from bytes
pub fn BloomFilter::decode(buf : Bytes) -> BloomFilter? {
  if buf.length() < 8 {
    return None
  }
  let r = @core.BinaryReader::new(buf)
  let hash_count = r.read_u32().reinterpret_as_int()
  let bit_count = r.read_u32().reinterpret_as_int()
  let bits = r.read_bytes(buf.length() - 8)
  Some({ bits, hash_count, bit_count })
}

///|
/// Encode sparse index entries to bytes
fn encode_index(entries : Array[SparseIndexEntry]) -> Bytes {
  let w = @core.BinaryWriter::new()
  for entry in entries {
    w.push_u32(entry.key.length().reinterpret_as_uint())
    w.push_u32(entry.offset.reinterpret_as_uint())
    w.push_bytes(entry.key)
  }
  w.concat()
}

///|
/// Decode sparse index from bytes
fn decode_index(buf : Bytes) -> Array[SparseIndexEntry] {
  let entries : Array[SparseIndexEntry] = []
  let r = @core.BinaryReader::new(buf)
  while r.remaining() >= 8 {
    let key_len = r.read_u32().reinterpret_as_int()
    let offset = r.read_u32().reinterpret_as_int()
    if r.remaining() < key_len {
      break
    }
    let key = r.read_bytes(key_len)
    entries.push({ key, offset })
  }
  entries
}

///|
/// Build an SSTable from sorted records
pub fn SSTable::build(
  records : Array[SSTableRecord],
  index_interval : Int,
) -> Bytes {
  // Guard against zero/negative interval to prevent division by zero
  let interval = if index_interval <= 0 { 1 } else { index_interval }
  let data_parts : Array[Bytes] = []
  let index_entries : Array[SparseIndexEntry] = []
  let mut data_offset = 0
  for i, record in records {
    // Add to sparse index every N records
    if i % interval == 0 {
      index_entries.push({ key: record.key, offset: data_offset })
    }
    let encoded = record.encode()
    data_parts.push(encoded)
    data_offset = data_offset + encoded.length()
  }
  // Concatenate data section
  let data_w = @core.BinaryWriter::new()
  for part in data_parts {
    data_w.push_bytes(part)
  }
  let data_section = data_w.concat()
  // Build bloom filter
  let keys = records.map(fn(r) { r.key })
  let bloom = BloomFilter::create(keys, 0.01)
  let bloom_section = bloom.encode()
  // Encode index
  let index_section = encode_index(index_entries)
  // Build footer
  let footer : SSTableFooter = {
    magic: sstable_magic,
    version: sstable_version,
    data_offset: 0,
    data_size: data_section.length(),
    index_offset: data_section.length(),
    index_size: index_section.length(),
    bloom_offset: data_section.length() + index_section.length(),
    bloom_size: bloom_section.length(),
  }
  let footer_section = footer.encode()
  // Combine all sections
  let result_w = @core.BinaryWriter::new()
  result_w.push_bytes(data_section)
  result_w.push_bytes(index_section)
  result_w.push_bytes(bloom_section)
  result_w.push_bytes(footer_section)
  result_w.concat()
}

///|
/// Read an SSTable from bytes
pub fn SSTable::read(buf : Bytes) -> SSTable? {
  let footer = match SSTableFooter::decode(buf) {
    None => return None
    Some(f) => f
  }
  // Validate all section bounds before any slicing
  let buf_len = buf.length()
  let data_end = footer.data_offset + footer.data_size
  let index_end = footer.index_offset + footer.index_size
  let bloom_end = footer.bloom_offset + footer.bloom_size
  if footer.data_offset < 0 ||
    data_end > buf_len ||
    footer.index_offset < 0 ||
    index_end > buf_len ||
    footer.bloom_offset < 0 ||
    bloom_end > buf_len {
    return None
  }
  // Decode data section
  let records : Array[SSTableRecord] = []
  let mut offset = footer.data_offset
  while offset < data_end {
    match SSTableRecord::decode(buf, offset) {
      None => return None
      Some((record, bytes_read)) => {
        records.push(record)
        offset = offset + bytes_read
      }
    }
  }
  // Decode index section
  let index_buf = slice_bytes(buf, footer.index_offset, index_end)
  let index = decode_index(index_buf)
  // Decode bloom filter
  let bloom = if footer.bloom_size > 0 {
    let bloom_buf = slice_bytes(buf, footer.bloom_offset, bloom_end)
    BloomFilter::decode(bloom_buf)
  } else {
    None
  }
  Some({ records, index, bloom, footer })
}

///|
/// Slice bytes helper
fn slice_bytes(buf : Bytes, start : Int, end : Int) -> Bytes {
  let len = end - start
  let result : FixedArray[Byte] = FixedArray::make(len, b'\x00')
  for i in 0..<len {
    result[i] = buf[start + i]
  }
  Bytes::from_array(result)
}

///|
/// Compare two byte arrays lexicographically
fn compare_bytes(a : Bytes, b : Bytes) -> Int {
  let min_len = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<min_len {
    if a[i].to_int() < b[i].to_int() {
      return -1
    }
    if a[i].to_int() > b[i].to_int() {
      return 1
    }
  }
  if a.length() < b.length() {
    -1
  } else if a.length() > b.length() {
    1
  } else {
    0
  }
}

///|
/// Find a record in SSTable by key
pub fn SSTable::find(self : SSTable, key : Bytes) -> SSTableRecord? {
  // Check bloom filter first
  match self.bloom {
    Some(bloom) => if not(bloom.might_contain(key)) { return None }
    None => ()
  }
  // If no sparse index, linear scan
  if self.index.is_empty() {
    return linear_search_records(self.records, key, 0)
  }
  // Binary search in sparse index
  let mut lo = 0
  let mut hi = self.index.length() - 1
  let mut start_idx = 0
  while lo <= hi {
    let mid = (lo + hi) / 2
    let cmp = compare_bytes(self.index[mid].key, key)
    if cmp <= 0 {
      start_idx = mid
      lo = mid + 1
    } else {
      hi = mid - 1
    }
  }
  // Find the record index that corresponds to this sparse index entry
  let index_key = self.index[start_idx].key
  let mut record_start_idx = 0
  for i in 0..<self.records.length() {
    if compare_bytes(self.records[i].key, index_key) == 0 {
      record_start_idx = i
      break
    }
  }
  linear_search_records(self.records, key, record_start_idx)
}

///|
/// Linear search for a key in records starting from start_idx
fn linear_search_records(
  records : Array[SSTableRecord],
  key : Bytes,
  start_idx : Int,
) -> SSTableRecord? {
  for i = start_idx; i < records.length(); i = i + 1 {
    let cmp = compare_bytes(records[i].key, key)
    if cmp == 0 {
      return Some(records[i])
    }
    if cmp > 0 {
      break
    }
  }
  None
}
