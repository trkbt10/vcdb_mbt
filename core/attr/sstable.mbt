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
  let w = @binary.BinaryWriter::new()
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
  let r = @binary.BinaryReader::new(buf)
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
  let w = @binary.BinaryWriter::new()
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
  let r = @binary.BinaryReader::new(buf)
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
  let w = @binary.BinaryWriter::new()
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
  let r = @binary.BinaryReader::new(buf)
  let hash_count = r.read_u32().reinterpret_as_int()
  let bit_count = r.read_u32().reinterpret_as_int()
  let bits = r.read_bytes(buf.length() - 8)
  Some({ bits, hash_count, bit_count })
}

///|
/// Encode sparse index entries to bytes
fn encode_index(entries : Array[SparseIndexEntry]) -> Bytes {
  let w = @binary.BinaryWriter::new()
  for entry in entries {
    w.push_u32(entry.key.length().reinterpret_as_uint())
    w.push_u32(entry.offset.reinterpret_as_uint())
    w.push_bytes(entry.key)
  }
  w.concat()
}

///|
/// Decode sparse index from a byte range [start, end)
fn decode_index_in_range(
  buf : Bytes,
  start : Int,
  end : Int,
) -> Array[SparseIndexEntry] {
  let entries : Array[SparseIndexEntry] = []
  if start < 0 || end < start || end > buf.length() {
    return entries
  }
  let r = @binary.BinaryReader::new(buf)
  r.skip(start)
  while r.position() + 8 <= end {
    let key_len = r.read_u32().reinterpret_as_int()
    let offset = r.read_u32().reinterpret_as_int()
    if key_len < 0 || r.position() + key_len > end {
      break
    }
    let key = r.read_bytes(key_len)
    entries.push({ key, offset })
  }
  entries
}

///|
/// Decode data records from a byte range [start, end)
fn decode_records_in_range(
  buf : Bytes,
  start : Int,
  end : Int,
) -> Array[SSTableRecord]? {
  if start < 0 || end < start || end > buf.length() {
    return None
  }
  let records : Array[SSTableRecord] = []
  let r = @binary.BinaryReader::new(buf)
  r.skip(start)
  while r.position() < end {
    if r.position() + 8 > end {
      return None
    }
    let key_len = r.read_u32().reinterpret_as_int()
    let val_len = r.read_u32().reinterpret_as_int()
    if key_len < 0 || val_len < 0 || r.position() + key_len + val_len > end {
      return None
    }
    let key = r.read_bytes(key_len)
    let value = r.read_bytes(val_len)
    records.push({ key, value })
  }
  Some(records)
}

///|
/// Build an SSTable from sorted records
pub fn SSTable::build(
  records : Array[SSTableRecord],
  index_interval : Int,
) -> Bytes {
  // Guard against zero/negative interval to prevent division by zero
  let interval = if index_interval <= 0 { 1 } else { index_interval }
  let data_w = @binary.BinaryWriter::new()
  let index_entries : Array[SparseIndexEntry] = []
  let keys : Array[Bytes] = []
  let mut data_offset = 0
  for i, record in records {
    // Add to sparse index every N records
    if i % interval == 0 {
      index_entries.push({ key: record.key, offset: data_offset })
    }
    keys.push(record.key)
    let key_len = record.key.length()
    let value_len = record.value.length()
    data_w.push_u32(key_len.reinterpret_as_uint())
    data_w.push_u32(value_len.reinterpret_as_uint())
    data_w.push_bytes(record.key)
    data_w.push_bytes(record.value)
    data_offset = data_offset + 8 + key_len + value_len
  }
  let data_section = data_w.concat()
  // Build bloom filter
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
  let result_w = @binary.BinaryWriter::new()
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
  let records = match
    decode_records_in_range(buf, footer.data_offset, data_end) {
    None => return None
    Some(rs) => rs
  }
  // Decode index section
  let index = decode_index_in_range(buf, footer.index_offset, index_end)
  // Decode bloom filter
  let bloom = if footer.bloom_size >= 8 {
    let r = @binary.BinaryReader::new(buf)
    r.skip(footer.bloom_offset)
    let hash_count = r.read_u32().reinterpret_as_int()
    let bit_count = r.read_u32().reinterpret_as_int()
    let bits_len = bloom_end - r.position()
    if bits_len < 0 || r.position() + bits_len > bloom_end {
      None
    } else {
      Some({ bits: r.read_bytes(bits_len), hash_count, bit_count })
    }
  } else {
    None
  }
  Some({ records, index, bloom, footer })
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
  let record_len = self.records.length()
  if record_len == 0 {
    return None
  }
  // If no sparse index, binary search across all records
  if self.index.is_empty() {
    let pos = lower_bound_records(self.records, key, 0, record_len)
    return if pos < record_len && compare_bytes(self.records[pos].key, key) == 0 {
      Some(self.records[pos])
    } else {
      None
    }
  }
  // Find sparse-index range and search only inside its covered records.
  let sparse_floor = floor_sparse_index(self.index, key)
  let range_start = lower_bound_records(
    self.records,
    self.index[sparse_floor].key,
    0,
    record_len,
  )
  let range_end = if sparse_floor + 1 < self.index.length() {
    lower_bound_records(
      self.records,
      self.index[sparse_floor + 1].key,
      range_start,
      record_len,
    )
  } else {
    record_len
  }
  let pos = lower_bound_records(self.records, key, range_start, range_end)
  if pos < range_end && compare_bytes(self.records[pos].key, key) == 0 {
    Some(self.records[pos])
  } else {
    None
  }
}

///|
/// Returns last sparse-index position whose key is <= target.
fn floor_sparse_index(index : Array[SparseIndexEntry], target : Bytes) -> Int {
  let mut lo = 0
  let mut hi = index.length() - 1
  let mut best = 0
  while lo <= hi {
    let mid = (lo + hi) / 2
    let cmp = compare_bytes(index[mid].key, target)
    if cmp <= 0 {
      best = mid
      lo = mid + 1
    } else {
      hi = mid - 1
    }
  }
  best
}

///|
/// Lower-bound search on `records[start..<end]`.
fn lower_bound_records(
  records : Array[SSTableRecord],
  key : Bytes,
  start : Int,
  end : Int,
) -> Int {
  let mut lo = start
  let mut hi = end
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    if compare_bytes(records[mid].key, key) < 0 {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  lo
}
