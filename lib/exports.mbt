///|
/// FFI exports for JavaScript interop.
/// These functions are exported for use from JavaScript.
///

///|
/// Global instance storage
let instances : @hashmap.HashMap[Int, @vcdb.VectorDB] = @hashmap.new()

///|
/// Mutable counter for instance IDs
priv struct Counter {
  mut value : Int
}

///|
let counter : Counter = { value: 1 }

///|
/// Create a new VectorDB instance with bruteforce strategy.
/// Returns instance ID (>0) on success.
pub fn vcdb_create(dim : Int) -> Int {
  let db = @vcdb.VectorDB::with_dim(dim)
  let id = counter.value
  counter.value = counter.value + 1
  instances[id] = db
  id
}

///|
/// Create with HNSW strategy.
pub fn vcdb_create_hnsw(dim : Int) -> Int {
  let db = @vcdb.VectorDB::with_hnsw(dim)
  let id = counter.value
  counter.value = counter.value + 1
  instances[id] = db
  id
}

///|
/// Create with IVF strategy.
pub fn vcdb_create_ivf(dim : Int) -> Int {
  let db = @vcdb.VectorDB::with_ivf(dim)
  let id = counter.value
  counter.value = counter.value + 1
  instances[id] = db
  id
}

///|
/// Destroy a VectorDB instance.
pub fn vcdb_destroy(instance_id : Int) -> Unit {
  instances.remove(instance_id)
}

///|
/// Get the number of vectors.
pub fn vcdb_size(instance_id : Int) -> Int {
  match instances.get(instance_id) {
    Some(db) => db.size()
    None => -1
  }
}

///|
/// Get the dimension.
pub fn vcdb_dim(instance_id : Int) -> Int {
  match instances.get(instance_id) {
    Some(db) => db.dim()
    None => -1
  }
}

///|
/// Add a vector with empty attrs (fails if exists).
pub fn vcdb_add(
  instance_id : Int,
  vector_id : Int,
  vector : Array[Double],
) -> Int {
  match instances.get(instance_id) {
    Some(db) => {
      let id = @core.VectorId(vector_id.to_int64())
      if db.has(id) {
        return -2 // Already exists
      }
      let attrs = @core.empty_attrs()
      db.add(id, vector, attrs)
      0
    }
    None => -1
  }
}

///|
/// Upsert a vector (add or update).
pub fn vcdb_upsert(
  instance_id : Int,
  vector_id : Int,
  vector : Array[Double],
) -> Int {
  match instances.get(instance_id) {
    Some(db) => {
      let attrs = @core.empty_attrs()
      let _ = db.upsert(@core.VectorId(vector_id.to_int64()), vector, attrs)
      0
    }
    None => -1
  }
}

///|
/// Get a vector by ID. Returns (vector, found) where found is 1 if exists, 0 if not.
pub fn vcdb_get(instance_id : Int, vector_id : Int) -> (Array[Double], Int) {
  match instances.get(instance_id) {
    Some(db) =>
      match db.get(@core.VectorId(vector_id.to_int64())) {
        Some(record) => (record.vector, 1)
        None => ([], 0)
      }
    None => ([], -1)
  }
}

///|
/// Search for nearest neighbors.
/// Returns an array of (id, score) pairs.
pub fn vcdb_search(
  instance_id : Int,
  query : Array[Double],
  k : Int,
) -> Array[(Int, Double)] {
  match instances.get(instance_id) {
    Some(db) => {
      let results = db.search(query, k, None)
      let out : Array[(Int, Double)] = []
      for hit in results {
        out.push((hit.id.0.to_int(), hit.score))
      }
      out
    }
    None => []
  }
}

///|
/// Check if a vector exists. Returns 1 if exists, 0 if not, -1 on error.
pub fn vcdb_has(instance_id : Int, vector_id : Int) -> Int {
  match instances.get(instance_id) {
    Some(db) => if db.has(@core.VectorId(vector_id.to_int64())) { 1 } else { 0 }
    None => -1
  }
}

///|
/// Remove a vector. Returns 1 if removed, 0 if not found, -1 on error.
pub fn vcdb_remove(instance_id : Int, vector_id : Int) -> Int {
  match instances.get(instance_id) {
    Some(db) =>
      if db.remove(@core.VectorId(vector_id.to_int64())) {
        1
      } else {
        0
      }
    None => -1
  }
}

///|
/// Serialize the database. Returns serialized bytes.
pub fn vcdb_serialize(instance_id : Int) -> Bytes {
  match instances.get(instance_id) {
    Some(db) => db.serialize()
    None => b""
  }
}

///|
/// Deserialize a database. Returns new instance ID on success, 0 on error.
pub fn vcdb_deserialize(data : Bytes) -> Int {
  let db = @vcdb.VectorDB::deserialize(data)
  let id = counter.value
  counter.value = counter.value + 1
  instances[id] = db
  id
}

// ============================================================================
// Gateway API - single entry point for HTTP requests
// ============================================================================

///|
/// Global storage for persistence
let gateway_storage : @storage.MemoryStorage = @storage.MemoryStorage::new()

///|
/// Global collection manager for gateway API (with storage)
let gateway_manager : @gateway.CollectionManager[@storage.MemoryStorage] = @gateway.CollectionManager::with_storage(
  gateway_storage,
)

///|
/// Execute a gateway API request.
///
/// @param http_method - HTTP method (GET, POST, PUT, DELETE)
/// @param path - URL path segments as array (e.g., ["collections", "mydb", "points"])
/// @param body - Request body as JSON string
/// @returns JSON response string
pub fn gateway_request(
  http_method : String,
  path : Array[String],
  body : String,
) -> String {
  let response = @gateway.execute_request(
    gateway_manager, http_method, path, body,
  )
  response.to_json().to_string()
}

///|
/// List all files in storage (for persistence sync)
pub fn gateway_storage_list() -> Array[String] {
  gateway_storage.list()
}

///|
/// Read a file from storage
pub fn gateway_storage_read(path : String) -> Bytes {
  gateway_storage.read(path) catch {
    _ => b""
  }
}

///|
/// Write a file to storage (called from JS to sync back)
pub fn gateway_storage_write(path : String, data : Bytes) -> Unit {
  gateway_storage.write(path, data)
}

///|
/// Check if a file exists in storage
pub fn gateway_storage_exists(path : String) -> Bool {
  gateway_storage.exists(path)
}
