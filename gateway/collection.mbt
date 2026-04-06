///|
/// CollectionManager - manages multiple named PersistentVectorDB collections.
///
/// All mutations go through PersistentVectorDB, which enforces
/// WAL-before-state ordering. Read operations delegate directly.
///
/// Write operations are async (PersistentVectorDB I/O).
/// Read operations are sync (in-memory VectorDB).

///|
/// Collection entry — wraps PersistentVectorDB with its config.
pub struct Collection[S] {
  config : CollectionConfig
  pdb : @col_persist.PersistentVectorDB[S, S]
}

///|
/// Collection manager with optional storage
pub struct CollectionManager[S] {
  collections : Map[String, Collection[S]]
  storage : S?
  base_path : String
  checkpoint_threshold : Int
}

///|
/// Create without storage (in-memory only)
pub fn[S] CollectionManager::new(
  base_path? : String = "",
) -> CollectionManager[S] {
  { collections: {}, storage: None, base_path, checkpoint_threshold: 1000 }
}

///|
/// Create with storage
pub fn[S] CollectionManager::with_storage(
  storage : S,
  base_path? : String = "",
  checkpoint_threshold? : Int = 1000,
) -> CollectionManager[S] {
  { collections: {}, storage: Some(storage), base_path, checkpoint_threshold }
}

///|
fn make_path(base_path : String, path : String) -> String {
  if base_path.length() == 0 {
    path
  } else {
    base_path + "/" + path
  }
}

///|
/// Persist config to storage
async fn[S : @storage.AsyncStorage] CollectionManager::persist_config(
  self : CollectionManager[S],
  name : String,
) -> Unit {
  let storage = match self.storage {
    Some(s) => s
    None => return
  }
  let col = match self.collections.get(name) {
    Some(c) => c
    None => return
  }
  let config_path = make_path(
    self.base_path,
    @storage.collection_config_path(name),
  )
  let config_json = col.config.to_json().to_string()
  let config_bytes = Bytes::from_array(
    config_json.to_array().map(fn(c) { c.to_int().to_byte() }),
  )
  @storage.async_atomic_write(
    storage,
    config_path,
    config_bytes,
    @storage.Config,
  )
}

///|
/// Checkpoint: write snapshot and truncate WAL
pub async fn[S : @storage.AsyncStorage] CollectionManager::checkpoint(
  self : CollectionManager[S],
  name : String,
) -> Unit {
  self.persist_config(name)
  match self.collections.get(name) {
    Some(col) => col.pdb.checkpoint()
    _ => ()
  }
}

///|
/// Upsert points into a collection via PersistentVectorDB (WAL-before-state).
pub async fn[S : @storage.AsyncStorage] CollectionManager::upsert_points(
  self : CollectionManager[S],
  name : String,
  points : Array[(@types.VectorId, Array[Double], @types.Attrs)],
  timestamp_ns? : Int64 = 0L,
) -> Result[Int, GatewayError] {
  let col = match self.collections.get(name) {
    Some(c) => c
    None => return Err(CollectionNotFound(name))
  }
  let dim = col.pdb.dim()
  for p in points {
    let (_, vector, _) = p
    if vector.length() != dim {
      return Err(DimensionMismatch(expected=dim, got=vector.length()))
    }
  }
  col.pdb.upsert(points, timestamp_ns)
  Ok(points.length())
}

///|
/// Remove a point from a collection via PersistentVectorDB (WAL-before-state).
pub async fn[S : @storage.AsyncStorage] CollectionManager::remove_point(
  self : CollectionManager[S],
  name : String,
  id : @types.VectorId,
  timestamp_ns? : Int64 = 0L,
) -> Result[Unit, GatewayError] {
  let col = match self.collections.get(name) {
    Some(c) => c
    None => return Err(CollectionNotFound(name))
  }
  if !col.pdb.has(id) {
    return Err(
      NotFound("Point with id " + id.to_int64().to_string() + " not found"),
    )
  }
  let _ = col.pdb.remove(id, timestamp_ns)
  Ok(())
}

///|
pub async fn[S : @storage.AsyncStorage] CollectionManager::create(
  self : CollectionManager[S],
  config : CollectionConfig,
) -> Result[Unit, GatewayError] {
  let storage = match self.storage {
    Some(s) => s
    None =>
      // In-memory only — create a PersistentVectorDB with no-op persistence
      // This case is not supported; storage is required for PersistentVectorDB.
      return Err(StorageError("Storage backend required"))
  }
  let config_path = make_path(
    self.base_path,
    @storage.collection_config_path(config.name),
  )
  let already_exists = self.collections.contains(config.name) ||
    @storage.async_exists(storage, config_path, @storage.Config)
  if already_exists {
    return Err(CollectionExists(config.name))
  }
  let options : @types.DatabaseOptions = {
    dim: config.dim,
    metric: config.metric,
    capacity: 1024,
    strategy: config.strategy,
  }
  let db = @vcdb.VectorDB::new(options)
  let wal_path = make_path(
    self.base_path,
    @storage.collection_wal_path(config.name),
  )
  let wal = @wal.AsyncWalRuntime::new(storage, wal_path)
  let pdb = @col_persist.PersistentVectorDB::new(
    db,
    wal,
    storage,
    self.base_path,
    config.name,
    checkpoint_threshold=self.checkpoint_threshold,
  )
  let collection : Collection[S] = { config, pdb }
  self.collections[config.name] = collection
  self.persist_config(config.name)
  // Persist initial empty state
  pdb.checkpoint()
  Ok(())
}

///|
/// Get VectorDB for read operations (sync)
pub fn[S] CollectionManager::get_db(
  self : CollectionManager[S],
  name : String,
) -> @vcdb.VectorDB? {
  match self.collections.get(name) {
    Some(c) => Some(c.pdb.get_underlying_db())
    None => None
  }
}

///|
/// Load collection from storage (async)
async fn[S : @storage.AsyncStorage] CollectionManager::load_collection_from_storage(
  self : CollectionManager[S],
  name : String,
) -> Collection[S]? {
  let storage = match self.storage {
    Some(s) => s
    None => return None
  }

  // Load config
  let config_path = make_path(
    self.base_path,
    @storage.collection_config_path(name),
  )
  if !@storage.async_exists(storage, config_path, @storage.Config) {
    return None
  }
  let config_bytes = @storage.async_read(storage, config_path, @storage.Config)
  let config_str = bytes_to_string(config_bytes)
  let config = match parse_json(config_str) {
    Some(json) =>
      CollectionConfig::from_json(json).unwrap_or(
        CollectionConfig::default(name, 128),
      )
    None => return None
  }

  // Load via PersistentVectorDB::init (handles WAL + snapshot replay)
  let pdb = @col_persist.PersistentVectorDB::init(
    storage,
    storage,
    self.base_path,
    name,
    config.dim,
    1024,
    checkpoint_threshold=self.checkpoint_threshold,
  )

  Some({ config, pdb })
}

///|
fn bytes_to_string(bytes : Bytes) -> String {
  let chars : Array[Char] = []
  for i in 0..<bytes.length() {
    chars.push(bytes[i].to_int().unsafe_to_char())
  }
  String::from_array(chars)
}

///|
async fn[S : @storage.AsyncStorage] CollectionManager::remove_persisted_collection(
  self : CollectionManager[S],
  name : String,
) -> Unit {
  let storage = match self.storage {
    Some(s) => s
    None => return
  }

  // Remove config
  let config_path = make_path(
    self.base_path,
    @storage.collection_config_path(name),
  )
  if @storage.async_exists(storage, config_path, @storage.Config) {
    @storage.async_del(storage, config_path, @storage.Config)
  }

  // Remove data
  let data_path = make_path(self.base_path, @storage.collection_data_path(name))
  if @storage.async_exists(storage, data_path, @storage.Data) {
    @storage.async_del(storage, data_path, @storage.Data)
  }

  // Remove WAL
  let wal_path = make_path(self.base_path, @storage.collection_wal_path(name))
  if @storage.async_exists(storage, wal_path, @storage.Data) {
    @storage.async_del(storage, wal_path, @storage.Data)
  }
}

///|
/// Get or load a collection (async for lazy loading from storage)
pub async fn[S : @storage.AsyncStorage] CollectionManager::get(
  self : CollectionManager[S],
  name : String,
) -> @vcdb.VectorDB? {
  match self.collections.get(name) {
    Some(c) => Some(c.pdb.get_underlying_db())
    None =>
      match self.load_collection_from_storage(name) {
        Some(col) => {
          let db = col.pdb.get_underlying_db()
          self.collections[name] = col
          Some(db)
        }
        None => None
      }
  }
}

///|
pub async fn[S : @storage.AsyncStorage] CollectionManager::get_info(
  self : CollectionManager[S],
  name : String,
) -> CollectionInfo? {
  match self.collections.get(name) {
    Some(c) => Some(collection_to_info(c))
    None =>
      match self.load_collection_from_storage(name) {
        Some(col) => {
          let info = collection_to_info(col)
          self.collections[name] = col
          Some(info)
        }
        None => None
      }
  }
}

///|
fn[S] collection_to_info(c : Collection[S]) -> CollectionInfo {
  let metric_str = match c.config.metric {
    @types.Cosine => "Cosine"
    @types.L2 => "L2"
    @types.Dot => "Dot"
  }
  let strategy_str = match c.config.strategy {
    @types.Bruteforce => "Bruteforce"
    @types.HNSW(_) => "HNSW"
    @types.IVF(_) => "IVF"
  }
  {
    name: c.config.name,
    vectors_count: c.pdb.size(),
    dim: c.config.dim,
    metric: metric_str,
    strategy: strategy_str,
  }
}

///|
pub async fn[S : @storage.AsyncStorage] CollectionManager::delete(
  self : CollectionManager[S],
  name : String,
) -> Result[Unit, GatewayError] {
  if !self.collections.contains(name) {
    match self.load_collection_from_storage(name) {
      Some(col) => self.collections[name] = col
      None => return Err(CollectionNotFound(name))
    }
  }
  self.collections.remove(name)
  self.remove_persisted_collection(name)
  Ok(())
}

///|
fn config_name_from_path(path : String) -> String? {
  let suffix = ".config.json"
  if path.has_suffix(suffix) {
    Some(path.unsafe_substring(start=0, end=path.length() - suffix.length()))
  } else {
    None
  }
}

///|
pub async fn[S : @storage.AsyncStorage] CollectionManager::list(
  self : CollectionManager[S],
) -> Array[String] {
  let names : Array[String] = self.collections.keys().collect()
  let seen : Map[String, Bool] = {}
  for name in names {
    seen[name] = true
  }
  match self.storage {
    Some(storage) =>
      for path in @storage.async_list(storage, @storage.Config) {
        match config_name_from_path(path) {
          Some(name) =>
            if !seen.contains(name) {
              names.push(name)
              seen[name] = true
            }
          None => ()
        }
      }
    None => ()
  }
  names
}

///|
pub async fn[S : @storage.AsyncStorage] CollectionManager::list_info(
  self : CollectionManager[S],
) -> Array[CollectionInfo] {
  let infos : Array[CollectionInfo] = []
  for name in self.list() {
    match self.get_info(name) {
      Some(info) => infos.push(info)
      None => ()
    }
  }
  infos
}

///|
pub fn[S] CollectionManager::exists(
  self : CollectionManager[S],
  name : String,
) -> Bool {
  self.collections.contains(name)
}

///|
pub fn[S] CollectionManager::count(self : CollectionManager[S]) -> Int {
  self.collections.length()
}

///|
pub fn[S] CollectionManager::serialize_collection(
  self : CollectionManager[S],
  name : String,
) -> Bytes? {
  match self.collections.get(name) {
    Some(c) => Some(c.pdb.serialize_snapshot())
    None => None
  }
}

///|
pub fn[S] CollectionManager::load_collection(
  self : CollectionManager[S],
  config : CollectionConfig,
  data : Bytes,
  storage : S,
  base_path : String,
) -> Result[Unit, GatewayError] {
  if self.collections.contains(config.name) {
    return Err(CollectionExists(config.name))
  }
  let db = @vcdb.VectorDB::deserialize(data)
  let wal_path = make_path(base_path, @storage.collection_wal_path(config.name))
  let wal = @wal.AsyncWalRuntime::new(storage, wal_path)
  let pdb = @col_persist.PersistentVectorDB::new(
    db,
    wal,
    storage,
    base_path,
    config.name,
  )
  let collection : Collection[S] = { config, pdb }
  self.collections[config.name] = collection
  Ok(())
}

///|
pub fn[S] CollectionManager::export_metadata(
  self : CollectionManager[S],
) -> JsonValue {
  let collections : Array[JsonValue] = []
  for kv in self.collections {
    let (_, c) = kv
    collections.push(c.config.to_json())
  }
  json_object([("version", JNumber(1.0)), ("collections", JArray(collections))])
}
