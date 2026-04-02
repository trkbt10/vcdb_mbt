///|
/// FFI exports for JavaScript interop.
///
/// All vector IDs are passed as (hi: Int, lo: Int) pairs — never as Double.
/// This is the only way to construct/extract VectorIds in the FFI.
/// Double-based paths are structurally impossible.

///|
/// Global instance storage
let instances : @hashmap.HashMap[Int, @vcdb.VectorDB] = @hashmap.new()

///|
priv struct Counter {
  mut value : Int
}

///|
let counter : Counter = { value: 1 }

///|
/// Construct a VectorId from hi/lo Int pair (SoT for ID construction).
fn vid_from_pair(hi : Int, lo : Int) -> @types.VectorId {
  let hi64 = hi.to_int64()
  let lo64 = lo.to_int64().land(0xFFFFFFFFL)
  @types.VectorId(hi64.lsl(32).lor(lo64))
}

///|
/// Extract hi/lo pair from VectorId (SoT for ID extraction).
fn vid_to_pair(id : @types.VectorId) -> (Int, Int) {
  let v = id.to_int64()
  let hi = v.lsr(32).to_int()
  let lo = v.to_int()
  (hi, lo)
}

///|
pub fn vcdb_create(dim : Int) -> Int {
  let db = @vcdb.VectorDB::with_dim(dim)
  let id = counter.value
  counter.value = counter.value + 1
  instances[id] = db
  id
}

///|
pub fn vcdb_create_hnsw(dim : Int) -> Int {
  let db = @vcdb.VectorDB::with_hnsw(dim)
  let id = counter.value
  counter.value = counter.value + 1
  instances[id] = db
  id
}

///|
pub fn vcdb_create_ivf(dim : Int) -> Int {
  let db = @vcdb.VectorDB::with_ivf(dim)
  let id = counter.value
  counter.value = counter.value + 1
  instances[id] = db
  id
}

///|
pub fn vcdb_destroy(instance_id : Int) -> Unit {
  instances.remove(instance_id)
}

///|
pub fn vcdb_size(instance_id : Int) -> Int {
  match instances.get(instance_id) {
    Some(db) => db.size()
    None => -1
  }
}

///|
pub fn vcdb_dim(instance_id : Int) -> Int {
  match instances.get(instance_id) {
    Some(db) => db.dim()
    None => -1
  }
}

///|
pub fn vcdb_add(
  instance_id : Int,
  id_hi : Int,
  id_lo : Int,
  vector : Array[Double],
) -> Int {
  match instances.get(instance_id) {
    Some(db) => {
      let id = vid_from_pair(id_hi, id_lo)
      if db.has(id) {
        return -2
      }
      let attrs = @types.empty_attrs()
      db.add(id, vector, attrs)
      0
    }
    None => -1
  }
}

///|
pub fn vcdb_upsert(
  instance_id : Int,
  id_hi : Int,
  id_lo : Int,
  vector : Array[Double],
) -> Int {
  match instances.get(instance_id) {
    Some(db) => {
      let attrs = @types.empty_attrs()
      let _ = db.upsert(vid_from_pair(id_hi, id_lo), vector, attrs)
      0
    }
    None => -1
  }
}

///|
pub fn vcdb_get(
  instance_id : Int,
  id_hi : Int,
  id_lo : Int,
) -> (Array[Double], Int) {
  match instances.get(instance_id) {
    Some(db) =>
      match db.get(vid_from_pair(id_hi, id_lo)) {
        Some(record) => (record.vector, 1)
        None => ([], 0)
      }
    None => ([], -1)
  }
}

///|
pub fn vcdb_search(
  instance_id : Int,
  query : Array[Double],
  k : Int,
) -> Array[(Int, Int, Double)] {
  match instances.get(instance_id) {
    Some(db) => {
      let results = db.search(query, k, None)
      let out : Array[(Int, Int, Double)] = []
      for hit in results {
        let (hi, lo) = vid_to_pair(hit.id)
        out.push((hi, lo, hit.score))
      }
      out
    }
    None => []
  }
}

///|
pub fn vcdb_has(instance_id : Int, id_hi : Int, id_lo : Int) -> Int {
  match instances.get(instance_id) {
    Some(db) =>
      if db.has(vid_from_pair(id_hi, id_lo)) {
        1
      } else {
        0
      }
    None => -1
  }
}

///|
pub fn vcdb_remove(instance_id : Int, id_hi : Int, id_lo : Int) -> Int {
  match instances.get(instance_id) {
    Some(db) =>
      if db.remove(vid_from_pair(id_hi, id_lo)) {
        1
      } else {
        0
      }
    None => -1
  }
}

///|
pub fn vcdb_serialize(instance_id : Int) -> Bytes {
  match instances.get(instance_id) {
    Some(db) => db.serialize()
    None => b""
  }
}

///|
pub fn vcdb_deserialize(data : Bytes) -> Int {
  let db = @vcdb.VectorDB::deserialize(data)
  let id = counter.value
  counter.value = counter.value + 1
  instances[id] = db
  id
}

// ============================================================================
// Gateway API
// ============================================================================

///|
/// Global storage (MemoryStorage or CallbackStorage based on registration)
let gateway_memory_storage : @storage.MemoryStorage = @storage.MemoryStorage::new()

///|
/// Manager with MemoryStorage
let gateway_manager_memory : @gateway.CollectionManager[@storage.MemoryStorage] = @gateway.CollectionManager::with_storage(
  gateway_memory_storage,
)

///|
/// Callback storage instance
let gateway_callback_storage : @storage.CallbackStorage = @storage.CallbackStorage::new()

///|
/// Manager with CallbackStorage (used when callbacks registered)
let gateway_manager_callback : @gateway.CollectionManager[
  @storage.CallbackStorage,
] = @gateway.CollectionManager::with_storage(gateway_callback_storage)

///|
/// Convert Int to StorageKind (0=Config, 1=Index, 2=Data)
fn int_to_kind(kind : Int) -> @storage.StorageKind {
  match kind {
    0 => @storage.Config
    1 => @storage.Index
    _ => @storage.Data
  }
}

///|
/// Convert StorageKind to Int
fn kind_to_int(kind : @storage.StorageKind) -> Int {
  match kind {
    @storage.Config => 0
    @storage.Index => 1
    @storage.Data => 2
  }
}

///|
/// Execute gateway request
pub fn gateway_request(
  http_method : String,
  path : Array[String],
  body : String,
) -> String {
  let response = if @storage.has_callbacks() {
    @gateway.execute_request(gateway_manager_callback, http_method, path, body)
  } else {
    @gateway.execute_request(gateway_manager_memory, http_method, path, body)
  }
  response.to_json().to_string()
}

// ============================================================================
// Storage Registration (app handles routing via kind parameter)
// ============================================================================

///|
/// Register storage callbacks
/// kind parameter: 0=Config, 1=Index, 2=Data
pub fn gateway_register_storage(
  read_fn : (String, Int) -> Bytes,
  write_fn : (String, Bytes, Int) -> Unit,
  exists_fn : (String, Int) -> Bool,
  del_fn : (String, Int) -> Unit,
  list_fn : (Int) -> Array[String],
) -> Unit {
  let callbacks = @storage.StorageCallbacks::new(
    fn(path, kind) { read_fn(path, kind_to_int(kind)) },
    fn(path, data, kind) { write_fn(path, data, kind_to_int(kind)) },
    fn(path, kind) { exists_fn(path, kind_to_int(kind)) },
    fn(path, kind) { del_fn(path, kind_to_int(kind)) },
    fn(kind) { list_fn(kind_to_int(kind)) },
  )
  @storage.register_callbacks(callbacks)
}

///|
/// Clear storage callbacks
pub fn gateway_clear_storage_callbacks() -> Unit {
  @storage.clear_callbacks()
}

///|
/// Check if callbacks registered
pub fn gateway_has_storage_callbacks() -> Bool {
  @storage.has_callbacks()
}

// ============================================================================
// Direct Storage Access (for app-level routing in distributed mode)
// kind: 0=Config, 1=Index, 2=Data
// ============================================================================

///|
pub fn gateway_storage_list(kind : Int) -> Array[String] {
  let k = int_to_kind(kind)
  if @storage.has_callbacks() {
    gateway_callback_storage.list(k)
  } else {
    gateway_memory_storage.list()
  }
}

///|
pub fn gateway_storage_read(path : String, kind : Int) -> Bytes {
  let k = int_to_kind(kind)
  if @storage.has_callbacks() {
    gateway_callback_storage.read(path, k) catch {
      _ => b""
    }
  } else {
    gateway_memory_storage.read(path) catch {
      _ => b""
    }
  }
}

///|
pub fn gateway_storage_write(path : String, data : Bytes, kind : Int) -> Unit {
  let k = int_to_kind(kind)
  if @storage.has_callbacks() {
    gateway_callback_storage.write(path, data, k)
  } else {
    gateway_memory_storage.write(path, data)
  }
}

///|
pub fn gateway_storage_exists(path : String, kind : Int) -> Bool {
  let k = int_to_kind(kind)
  if @storage.has_callbacks() {
    gateway_callback_storage.exists(path, k)
  } else {
    gateway_memory_storage.exists(path)
  }
}
