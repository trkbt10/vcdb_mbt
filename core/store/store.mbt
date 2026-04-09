///|
/// CoreStore: contiguous vector storage + id mapping.
/// Provides a compact foundation for both bruteforce and approximate search.
/// Normalizes vectors for cosine metric, maintains id->index mapping,
/// and supports O(1) compaction on remove.
pub struct CoreStore {
  dim : Int
  metric : @types.Metric
  mut ids : Array[@types.VectorId]
  mut data : Array[Double] // flattened: data[i*dim..(i+1)*dim] is vector i
  mut attrs : Array[@types.Attrs]
  pos : Map[@types.VectorId, Int] // id -> index mapping
  mut capacity : Int
  mut count : Int
}

///|
/// Create a new CoreStore
pub fn CoreStore::new(
  dim : Int,
  metric : @types.Metric,
  capacity? : Int = 1024,
) -> CoreStore {
  guard dim > 0 else { abort("dim must be positive") }
  let cap = if capacity < 1 { 1 } else { capacity }
  {
    dim,
    metric,
    ids: Array::make(cap, @types.Int64Id(0L)),
    data: Array::make(cap * dim, 0.0),
    attrs: Array::make(cap, @types.empty_attrs()),
    pos: {},
    capacity: cap,
    count: 0,
  }
}

///|
/// Get the current size (number of vectors)
pub fn CoreStore::size(self : CoreStore) -> Int {
  self.count
}

///|
/// Get the current capacity
pub fn CoreStore::capacity(self : CoreStore) -> Int {
  self.capacity
}

///|
/// Check if an id exists in the store
pub fn CoreStore::has(self : CoreStore, id : @types.VectorId) -> Bool {
  self.pos.contains(id)
}

///|
/// Ensure capacity for additional elements
pub fn CoreStore::ensure_capacity(self : CoreStore, extra : Int) -> Bool {
  if self.count + extra <= self.capacity {
    return false
  }
  // Grow capacity
  let mut new_cap = self.capacity
  while new_cap < self.count + extra {
    new_cap = new_cap * 2
  }
  // Resize ids
  let new_ids = Array::make(new_cap, @types.Int64Id(0L))
  for i in 0..<self.count {
    new_ids[i] = self.ids[i]
  }
  self.ids = new_ids
  // Resize data
  let new_data = Array::make(new_cap * self.dim, 0.0)
  for i in 0..<(self.count * self.dim) {
    new_data[i] = self.data[i]
  }
  self.data = new_data
  // Resize attrs
  let new_attrs = Array::make(new_cap, @types.empty_attrs())
  for i in 0..<self.count {
    new_attrs[i] = self.attrs[i]
  }
  self.attrs = new_attrs
  self.capacity = new_cap
  true
}

///|
/// Write vector at index, normalizing for cosine metric
fn CoreStore::write_vector_at(
  self : CoreStore,
  index : Int,
  vector : Array[Double],
) -> Unit {
  let base = index * self.dim
  for i in 0..<self.dim {
    self.data[base + i] = vector[i]
  }
  // Auto-normalize for cosine metric
  if self.metric == @types.Cosine {
    let mut sum = 0.0
    for i in 0..<self.dim {
      let v = self.data[base + i]
      sum = sum + v * v
    }
    let inv = if sum > 0.0 { 1.0 / sum.sqrt() } else { 1.0 }
    for i in 0..<self.dim {
      self.data[base + i] = self.data[base + i] * inv
    }
  }
}

///|
/// Get index for an id
pub fn CoreStore::get_index(self : CoreStore, id : @types.VectorId) -> Int? {
  self.pos.get(id)
}

///|
/// Get vector and attrs by index
pub fn CoreStore::get_by_index(
  self : CoreStore,
  index : Int,
) -> @types.VectorRecord {
  let base = index * self.dim
  let vec = Array::make(self.dim, 0.0)
  for i in 0..<self.dim {
    vec[i] = self.data[base + i]
  }
  { vector: vec, attrs: self.attrs[index] }
}

///|
/// Get vector ID by index.
pub fn CoreStore::id_at(self : CoreStore, index : Int) -> @types.VectorId? {
  if index < 0 || index >= self.count {
    None
  } else {
    Some(self.ids[index])
  }
}

///|
/// Get vector and attrs by id
pub fn CoreStore::get(
  self : CoreStore,
  id : @types.VectorId,
) -> @types.VectorRecord? {
  match self.get_index(id) {
    Some(idx) => Some(self.get_by_index(idx))
    None => None
  }
}

///|
/// Add or update a vector. Returns (index, created).
/// If upsert is false and id exists, raises error.
pub fn CoreStore::add_or_update(
  self : CoreStore,
  id : @types.VectorId,
  vector : Array[Double],
  attrs : @types.Attrs,
  upsert? : Bool = false,
) -> (Int, Bool) {
  guard vector.length() == self.dim else {
    abort(
      "dim mismatch: got " +
      vector.length().to_string() +
      ", want " +
      self.dim.to_string(),
    )
  }
  match self.get_index(id) {
    Some(idx) => {
      guard upsert else {
        abort("id already exists: " + id.to_display_string())
      }
      self.write_vector_at(idx, vector)
      self.attrs[idx] = attrs.copy() // Defensive copy to prevent external mutation
      (idx, false)
    }
    None => {
      let _ = self.ensure_capacity(1)
      let idx = self.count
      self.ids[idx] = id
      self.attrs[idx] = attrs.copy() // Defensive copy to prevent external mutation
      self.pos.set(id, idx)
      self.write_vector_at(idx, vector)
      self.count = self.count + 1
      (idx, true)
    }
  }
}

///|
/// Move info returned by remove
pub struct MoveInfo {
  moved_id : @types.VectorId?
  moved_from : Int?
  moved_to : Int?
} derive(Show)

///|
/// Remove a vector by id. Returns move info if compaction occurred.
pub fn CoreStore::remove_by_id(
  self : CoreStore,
  id : @types.VectorId,
) -> MoveInfo? {
  match self.get_index(id) {
    None => None
    Some(idx) => {
      let last = self.count - 1
      if idx != last {
        // Swap with last element
        self.ids[idx] = self.ids[last]
        self.attrs[idx] = self.attrs[last]
        let src_base = last * self.dim
        let dst_base = idx * self.dim
        for i in 0..<self.dim {
          self.data[dst_base + i] = self.data[src_base + i]
        }
        let moved_id = self.ids[idx]
        self.pos.set(moved_id, idx)
        self.pos.remove(id)
        self.count = self.count - 1
        Some({
          moved_id: Some(moved_id),
          moved_from: Some(last),
          moved_to: Some(idx),
        })
      } else {
        self.pos.remove(id)
        self.count = self.count - 1
        Some({ moved_id: None, moved_from: None, moved_to: None })
      }
    }
  }
}

///|
/// Update only attrs for an id. Returns true if updated.
pub fn CoreStore::update_attrs(
  self : CoreStore,
  id : @types.VectorId,
  attrs : @types.Attrs,
) -> Bool {
  match self.get_index(id) {
    Some(idx) => {
      self.attrs[idx] = attrs.copy() // Defensive copy to prevent external mutation
      true
    }
    None => false
  }
}

///|
/// Shrink backing arrays to fit current count
pub fn CoreStore::shrink_to_fit(self : CoreStore) -> Unit {
  let n = if self.count < 1 { 1 } else { self.count }
  if n >= self.capacity {
    return
  }
  // Shrink ids
  let new_ids = Array::make(n, @types.Int64Id(0L))
  for i in 0..<self.count {
    new_ids[i] = self.ids[i]
  }
  self.ids = new_ids
  // Shrink data
  let new_data = Array::make(n * self.dim, 0.0)
  for i in 0..<(self.count * self.dim) {
    new_data[i] = self.data[i]
  }
  self.data = new_data
  // Shrink attrs
  let new_attrs = Array::make(n, @types.empty_attrs())
  for i in 0..<self.count {
    new_attrs[i] = self.attrs[i]
  }
  self.attrs = new_attrs
  self.capacity = n
}

///|
/// Normalize query vector for cosine metric
pub fn CoreStore::normalize_query(
  self : CoreStore,
  q : Array[Double],
) -> Array[Double] {
  if self.metric != @types.Cosine {
    return q
  }
  @vecmath.normalize(q)
}

///|
/// Serialize CoreStore to bytes
pub fn CoreStore::serialize(self : CoreStore) -> Bytes {
  let w = @binary.BinaryWriter::new()
  // Write header: dim, metric, count
  w.push_u32(self.dim.reinterpret_as_uint())
  w.push_u32(
    match self.metric {
      @types.Cosine => 0U
      @types.L2 => 1U
      @types.Dot => 2U
    },
  )
  w.push_u32(self.count.reinterpret_as_uint())
  // Write ids: tag(1) + payload(8 or 16 bytes)
  // tag 0x00 = Int64Id (8 bytes), tag 0x01 = Bytes16Id (16 bytes)
  for i in 0..<self.count {
    match self.ids[i] {
      @types.Int64Id(v) => {
        w.push_byte(b'\x00')
        w.push_u64(v.reinterpret_as_uint64())
      }
      @types.Bytes16Id(b) => {
        w.push_byte(b'\x01')
        w.push_byte(b.b0)
        w.push_byte(b.b1)
        w.push_byte(b.b2)
        w.push_byte(b.b3)
        w.push_byte(b.b4)
        w.push_byte(b.b5)
        w.push_byte(b.b6)
        w.push_byte(b.b7)
        w.push_byte(b.b8)
        w.push_byte(b.b9)
        w.push_byte(b.b10)
        w.push_byte(b.b11)
        w.push_byte(b.b12)
        w.push_byte(b.b13)
        w.push_byte(b.b14)
        w.push_byte(b.b15)
      }
    }
  }
  // Write data
  for i in 0..<(self.count * self.dim) {
    w.push_f64(self.data[i])
  }
  // Write attrs: for each attr, write number of entries, then key-value pairs
  for i in 0..<self.count {
    let attrs = self.attrs[i]
    let keys = attrs.keys()
    w.push_u32(keys.length().reinterpret_as_uint())
    for key in keys {
      // Write key as chars (each char as u32)
      let key_chars = key.to_array()
      w.push_u32(key_chars.length().reinterpret_as_uint())
      for c in key_chars {
        w.push_u32(c.to_uint())
      }
      // Write value type and value
      match attrs.get(key) {
        None => w.push_u32(0U)
        Some(@types.Null) => w.push_u32(0U)
        Some(@types.Bool(b)) => {
          w.push_u32(1U)
          w.push_u32(if b { 1U } else { 0U })
        }
        Some(@types.AttrValue::Int(n)) => {
          w.push_u32(2U)
          w.push_i64(n)
        }
        Some(@types.Float(f)) => {
          w.push_u32(3U)
          w.push_f64(f)
        }
        Some(@types.AttrValue::String(s)) => {
          w.push_u32(4U)
          let s_chars = s.to_array()
          w.push_u32(s_chars.length().reinterpret_as_uint())
          for c in s_chars {
            w.push_u32(c.to_uint())
          }
        }
      }
    }
  }
  w.concat()
}

///|
/// Deserialize CoreStore from bytes
pub fn CoreStore::deserialize(data : Bytes) -> CoreStore {
  let r = @binary.BinaryReader::new(data)
  // Read header
  let dim = r.read_u32().reinterpret_as_int()
  let metric = match r.read_u32() {
    0U => @types.Cosine
    1U => @types.L2
    _ => @types.Dot
  }
  let count = r.read_u32().reinterpret_as_int()
  let store = CoreStore::new(dim, metric, capacity=count)
  // Read ids: tag(1) + payload(8 or 16 bytes)
  for i in 0..<count {
    let tag = r.read_byte()
    let id = match tag {
      b'\x01' => {
        let b0 = r.read_byte()
        let b1 = r.read_byte()
        let b2 = r.read_byte()
        let b3 = r.read_byte()
        let b4 = r.read_byte()
        let b5 = r.read_byte()
        let b6 = r.read_byte()
        let b7 = r.read_byte()
        let b8 = r.read_byte()
        let b9 = r.read_byte()
        let b10 = r.read_byte()
        let b11 = r.read_byte()
        let b12 = r.read_byte()
        let b13 = r.read_byte()
        let b14 = r.read_byte()
        let b15 = r.read_byte()
        @types.Bytes16Id(
          @types.Bytes16::{
            b0, b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12, b13, b14,
            b15,
          },
        )
      }
      // tag 0x00 (Int64Id) or unknown (treat as Int64Id for forward compat)
      _ => @types.Int64Id(r.read_u64().reinterpret_as_int64())
    }
    store.ids[i] = id
    store.pos.set(id, i)
  }
  // Read data
  for i in 0..<(count * dim) {
    store.data[i] = r.read_f64()
  }
  // Read attrs
  for i in 0..<count {
    let attrs = @types.empty_attrs()
    let num_entries = r.read_u32().reinterpret_as_int()
    for _ in 0..<num_entries {
      // Read key as chars
      let key_len = r.read_u32().reinterpret_as_int()
      let key_chars : Array[Char] = []
      for _ in 0..<key_len {
        key_chars.push(r.read_u32().reinterpret_as_int().unsafe_to_char())
      }
      let key = String::from_array(key_chars[:])
      // Read value
      let value_type = r.read_u32()
      let value : @types.AttrValue = match value_type {
        0U => @types.Null
        1U => @types.Bool(r.read_u32() != 0U)
        2U => @types.AttrValue::Int(r.read_i64())
        3U => @types.Float(r.read_f64())
        _ => {
          let s_len = r.read_u32().reinterpret_as_int()
          let s_chars : Array[Char] = []
          for _ in 0..<s_len {
            s_chars.push(r.read_u32().reinterpret_as_int().unsafe_to_char())
          }
          @types.AttrValue::String(String::from_array(s_chars[:]))
        }
      }
      attrs.set(key, value)
    }
    store.attrs[i] = attrs
  }
  store.count = count
  store
}
