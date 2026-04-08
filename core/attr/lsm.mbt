///|
/// LSM Tree Attribute Index
/// Write-optimized with memtable for fast writes and optional persistence.

///|
/// Memtable entry
priv struct MemtableEntry {
  _key : Bytes
  value : Array[Int64]? // None = tombstone
  _seq : Int // Sequence number for ordering
}

///|
/// Memtable structure
struct Memtable {
  entries : Map[String, MemtableEntry]
  mut size : Int
  mut next_seq : Int
}

///|
/// Create a new memtable
fn Memtable::new() -> Memtable {
  { entries: {}, size: 0, next_seq: 0 }
}

///|
/// LSM Index
pub struct LSMAttrIndex {
  memtable : Memtable // Value memtable
  exists_memtable : Memtable // Existence memtable
  data : Map[Int64, @types.Attrs] // Direct attrs storage
  flush_threshold : Int // Auto-flush threshold (default 1000)
}

///|
/// Create a new LSM attribute index
pub fn LSMAttrIndex::new(flush_threshold? : Int = 1000) -> LSMAttrIndex {
  {
    memtable: Memtable::new(),
    exists_memtable: Memtable::new(),
    data: {},
    flush_threshold,
  }
}

///|
/// Convert bytes to hex string for map key
fn lsm_bytes_to_hex(b : Bytes) -> String {
  let hex_chars = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
  ]
  let chars : Array[Char] = []
  for i in 0..<b.length() {
    let high = (b[i].to_int() >> 4) & 0xF
    let low = b[i].to_int() & 0xF
    chars.push(hex_chars[high])
    chars.push(hex_chars[low])
  }
  String::from_array(chars)
}

///|
/// Encode memtable key: attrKey + 0x00 + encoded value
fn lsm_encode_memtable_key(
  attr_key : String,
  value : @types.AttrValue,
) -> Bytes {
  let w = @binary.BinaryWriter::new()
  // Write attr_key as full UTF-8 to preserve Unicode
  w.push_bytes(@utf8.encode(attr_key.view()))
  // Separator
  w.push_byte(b'\x00')
  // Write encoded value
  w.push_bytes(encode_attr_value(value))
  w.concat()
}

///|
/// Encode exists key: 0xFF + "exists" + 0x00 + attrKey
fn lsm_encode_exists_key(attr_key : String) -> Bytes {
  let w = @binary.BinaryWriter::new()
  w.push_byte(b'\xFF')
  w.push_bytes(@utf8.encode("exists".view()))
  w.push_byte(b'\x00')
  // Write attr_key as full UTF-8 to preserve Unicode
  w.push_bytes(@utf8.encode(attr_key.view()))
  w.concat()
}

///|
/// Insert or update value in memtable
fn memtable_put(mt : Memtable, key : Bytes, value : Array[Int64]?) -> Unit {
  let key_str = lsm_bytes_to_hex(key)
  let seq = mt.next_seq
  mt.next_seq = seq + 1
  match mt.entries.get(key_str) {
    None => {
      mt.entries.set(key_str, { _key: key, value, _seq: seq })
      mt.size = mt.size + 1
    }
    Some(_) =>
      // Update existing
      mt.entries.set(key_str, { _key: key, value, _seq: seq })
  }
}

///|
/// Lookup value in memtable
fn memtable_get(mt : Memtable, key : Bytes) -> Array[Int64]?? {
  let key_str = lsm_bytes_to_hex(key)
  match mt.entries.get(key_str) {
    None => None
    Some(entry) => Some(entry.value)
  }
}

///|
/// Add ID to posting list in memtable
fn memtable_add_id(mt : Memtable, key : Bytes, id : Int64) -> Unit {
  let key_str = lsm_bytes_to_hex(key)
  match mt.entries.get(key_str) {
    None => memtable_put(mt, key, Some([id]))
    Some(entry) =>
      match entry.value {
        None => memtable_put(mt, key, Some([id]))
        Some(list) => {
          // Check if id already exists
          let mut found = false
          for existing in list {
            if existing == id {
              found = true
              break
            }
          }
          if !found {
            list.push(id)
          }
        }
      }
  }
}

///|
/// Remove ID from posting list in memtable
fn memtable_remove_id(mt : Memtable, key : Bytes, id : Int64) -> Unit {
  let key_str = lsm_bytes_to_hex(key)
  match mt.entries.get(key_str) {
    None => ()
    Some(entry) =>
      match entry.value {
        None => ()
        Some(list) => {
          let _ = remove_int64_swap(list, id)
          // Mark as tombstone if empty
          if list.is_empty() {
            memtable_put(mt, key, None)
          }
        }
      }
  }
}

///|
/// Set attributes for an ID
pub fn LSMAttrIndex::set_attrs(
  self : LSMAttrIndex,
  id : @types.VectorId,
  attrs : @types.Attrs,
) -> Unit {
  let id_val = id.to_int64()
  // Remove old attrs
  match self.data.get(id_val) {
    None => ()
    Some(old_attrs) =>
      for_each_attr(old_attrs, fn(key, value) {
        let mem_key = lsm_encode_memtable_key(key, value)
        memtable_remove_id(self.memtable, mem_key, id_val)
        let exists_key = lsm_encode_exists_key(key)
        memtable_remove_id(self.exists_memtable, exists_key, id_val)
      })
  }
  // Add new attrs
  for_each_attr(attrs, fn(key, value) {
    let mem_key = lsm_encode_memtable_key(key, value)
    memtable_add_id(self.memtable, mem_key, id_val)
    let exists_key = lsm_encode_exists_key(key)
    memtable_add_id(self.exists_memtable, exists_key, id_val)
  })
  // Store attrs (defensive copy to prevent external mutation)
  self.data.set(id_val, attrs.copy())
}

///|
/// Get attributes for an ID
pub fn LSMAttrIndex::get_attrs(
  self : LSMAttrIndex,
  id : @types.VectorId,
) -> @types.Attrs? {
  self.data.get(id.to_int64())
}

///|
/// Remove an ID from the index
pub fn LSMAttrIndex::remove_id(
  self : LSMAttrIndex,
  id : @types.VectorId,
) -> Unit {
  let id_val = id.to_int64()
  match self.data.get(id_val) {
    None => ()
    Some(old_attrs) => {
      for_each_attr(old_attrs, fn(key, value) {
        let mem_key = lsm_encode_memtable_key(key, value)
        memtable_remove_id(self.memtable, mem_key, id_val)
        let exists_key = lsm_encode_exists_key(key)
        memtable_remove_id(self.exists_memtable, exists_key, id_val)
      })
      self.data.remove(id_val)
    }
  }
}

///|
/// Find IDs where key equals value
pub fn LSMAttrIndex::eq(
  self : LSMAttrIndex,
  key : String,
  value : @types.AttrValue,
) -> Array[@types.VectorId] {
  let mem_key = lsm_encode_memtable_key(key, value)
  match memtable_get(self.memtable, mem_key) {
    None => []
    Some(value_opt) =>
      match value_opt {
        None => [] // Tombstone
        Some(list) => ids_to_vector_ids(list)
      }
  }
}

///|
/// Find IDs where key exists
pub fn LSMAttrIndex::exists(
  self : LSMAttrIndex,
  key : String,
) -> Array[@types.VectorId] {
  let exists_key = lsm_encode_exists_key(key)
  match memtable_get(self.exists_memtable, exists_key) {
    None => []
    Some(value_opt) =>
      match value_opt {
        None => []
        Some(list) => ids_to_vector_ids(list)
      }
  }
}

///|
/// Find IDs matching a numeric range
/// Note: Range queries scan through all entries - not optimal for large datasets
pub fn LSMAttrIndex::range(
  self : LSMAttrIndex,
  key : String,
  range : @types.NumericRange,
) -> Array[@types.VectorId]? {
  // Scan through data for matching numeric values
  let result : Array[@types.VectorId] = []
  let seen : Map[Int64, Bool] = {}
  for entry in self.data {
    let (id_val, attrs) = entry
    match attrs.get(key) {
      None => continue
      Some(value) =>
        match attr_value_to_number(value) {
          None => continue
          Some(num) =>
            if range.matches(num) && !seen.contains(id_val) {
              seen.set(id_val, true)
              result.push(@types.VectorId(id_val))
            }
        }
    }
  }
  Some(result)
}

///|
/// Get the number of indexed IDs
pub fn LSMAttrIndex::size(self : LSMAttrIndex) -> Int {
  self.data.length()
}

///|
/// Get memtable size (for flush threshold checking)
pub fn LSMAttrIndex::memtable_size(self : LSMAttrIndex) -> Int {
  self.memtable.size
}

///|
/// Check if memtable should be flushed
pub fn LSMAttrIndex::should_flush(self : LSMAttrIndex) -> Bool {
  self.memtable.size >= self.flush_threshold
}

///|
/// Clear memtable (for manual flush)
pub fn LSMAttrIndex::clear_memtable(self : LSMAttrIndex) -> Unit {
  self.memtable.entries.clear()
  self.memtable.size = 0
  self.exists_memtable.entries.clear()
  self.exists_memtable.size = 0
}
