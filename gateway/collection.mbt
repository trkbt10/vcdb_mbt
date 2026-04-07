///|
/// CollectionManager - manages multiple named PersistentVectorDB collections.
///
/// All mutations go through PersistentVectorDB, which enforces
/// WAL-before-state ordering. Read operations delegate directly.
///
/// Write operations are async (PersistentVectorDB I/O).
/// Read operations are sync (in-memory VectorDB).

///|
/// Collection entry — wraps VectorDB with its config.
pub struct Collection[S] {
  config : CollectionConfig
  db : @vcdb.PersistentDB[S, S]
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
fn invalid_collection_config_error(
  name : String,
  message : String,
) -> GatewayError {
  StorageError("Invalid collection config for " + name + ": " + message)
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
    Some(col) => col.db.checkpoint()
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
  let dim = col.db.dim()
  for p in points {
    let (_, vector, _) = p
    if vector.length() != dim {
      return Err(DimensionMismatch(expected=dim, got=vector.length()))
    }
  }
  col.db.upsert(points, timestamp_ns)
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
  if !col.db.has(id) {
    return Err(
      NotFound("Point with id " + id.to_int64().to_string() + " not found"),
    )
  }
  let _ = col.db.remove(id, timestamp_ns)
  Ok(())
}

///|
pub async fn[S : @storage.AsyncStorage] CollectionManager::create(
  self : CollectionManager[S],
  config : CollectionConfig,
) -> Result[Unit, GatewayError] {
  try {
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
    let db = @vcdb.PersistentDB::init(
      storage,
      storage,
      self.base_path,
      config.name,
      config.dim,
      1024,
      metric=config.metric,
      strategy=config.strategy,
      checkpoint_threshold=self.checkpoint_threshold,
    )
    let collection : Collection[S] = { config, db }
    self.collections[config.name] = collection
    self.persist_config(config.name)
    // Persist initial empty state
    db.checkpoint()
    Ok(())
  } catch {
    @storage.AsyncIOFailed(msg) => Err(StorageError(msg))
    e => abort(e.to_string())
  }
}

///|
/// Get VectorDB for read operations (sync)
pub fn[S] CollectionManager::get_db(
  self : CollectionManager[S],
  name : String,
) -> @vcdb.PersistentDB[S, S]? {
  match self.collections.get(name) {
    Some(c) => Some(c.db)
    None => None
  }
}

///|
/// Load collection from storage (async)
async fn[S : @storage.AsyncStorage] CollectionManager::load_collection_from_storage(
  self : CollectionManager[S],
  name : String,
) -> Result[Collection[S]?, GatewayError] {
  try {
    let storage = match self.storage {
      Some(s) => s
      None => return Ok(None)
    }

    // Load config
    let config_path = make_path(
      self.base_path,
      @storage.collection_config_path(name),
    )
    if !@storage.async_exists(storage, config_path, @storage.Config) {
      return Ok(None)
    }
    let config_bytes = @storage.async_read(
      storage,
      config_path,
      @storage.Config,
    )
    let config_str = bytes_to_string(config_bytes)
    let config = match parse_json(config_str) {
      Some(json) =>
        match CollectionConfig::from_json(json) {
          Ok(parsed) => { ..parsed, name, }
          Err(msg) => return Err(invalid_collection_config_error(name, msg))
        }
      None =>
        return Err(
          invalid_collection_config_error(name, "config is not valid JSON"),
        )
    }

    // Load via VectorDB::init (handles WAL + snapshot replay)
    let db = @vcdb.PersistentDB::init(
      storage,
      storage,
      self.base_path,
      name,
      config.dim,
      1024,
      metric=config.metric,
      strategy=config.strategy,
      checkpoint_threshold=self.checkpoint_threshold,
    )

    Ok(Some({ config, db }))
  } catch {
    @storage.AsyncIOFailed(msg) => Err(StorageError(msg))
    e => abort(e.to_string())
  }
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
) -> Result[@vcdb.PersistentDB[S, S], GatewayError] {
  match self.collections.get(name) {
    Some(c) => Ok(c.db)
    None =>
      match self.load_collection_from_storage(name) {
        Ok(Some(col)) => {
          let db = col.db
          self.collections[name] = col
          Ok(db)
        }
        Ok(None) => Err(CollectionNotFound(name))
        Err(err) => Err(err)
      }
  }
}

///|
pub async fn[S : @storage.AsyncStorage] CollectionManager::get_info(
  self : CollectionManager[S],
  name : String,
) -> Result[CollectionInfo, GatewayError] {
  match self.collections.get(name) {
    Some(c) => Ok(collection_to_info(c))
    None =>
      match self.load_collection_from_storage(name) {
        Ok(Some(col)) => {
          let info = collection_to_info(col)
          self.collections[name] = col
          Ok(info)
        }
        Ok(None) => Err(CollectionNotFound(name))
        Err(err) => Err(err)
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
    vectors_count: c.db.size(),
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
      Ok(Some(col)) => self.collections[name] = col
      Ok(None) => return Err(CollectionNotFound(name))
      Err(err) => return Err(err)
    }
  }
  try {
    self.collections.remove(name)
    self.remove_persisted_collection(name)
    Ok(())
  } catch {
    @storage.AsyncIOFailed(msg) => Err(StorageError(msg))
    e => abort(e.to_string())
  }
}

///|
fn config_name_from_path(base_path : String, path : String) -> String? {
  let relative_path = if base_path.length() == 0 {
    path
  } else {
    let prefix = base_path + "/"
    if path.has_prefix(prefix) {
      path.unsafe_substring(start=prefix.length(), end=path.length())
    } else {
      path
    }
  }
  let suffix = ".config.json"
  if relative_path.has_suffix(suffix) {
    Some(
      relative_path.unsafe_substring(
        start=0,
        end=relative_path.length() - suffix.length(),
      ),
    )
  } else {
    None
  }
}

///|
pub async fn[S : @storage.AsyncStorage] CollectionManager::list(
  self : CollectionManager[S],
) -> Result[Array[String], GatewayError] {
  let names : Array[String] = self.collections.keys().collect()
  let seen : Map[String, Bool] = {}
  for name in names {
    seen[name] = true
  }
  try {
    match self.storage {
      Some(storage) =>
        for path in @storage.async_list(storage, @storage.Config) {
          match config_name_from_path(self.base_path, path) {
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
    Ok(names)
  } catch {
    @storage.AsyncIOFailed(msg) => Err(StorageError(msg))
    e => abort(e.to_string())
  }
}

///|
pub async fn[S : @storage.AsyncStorage] CollectionManager::list_info(
  self : CollectionManager[S],
) -> Result[Array[CollectionInfo], GatewayError] {
  let infos : Array[CollectionInfo] = []
  let names = match self.list() {
    Ok(values) => values
    Err(err) => return Err(err)
  }
  for name in names {
    match self.get_info(name) {
      Ok(info) => infos.push(info)
      Err(err) => return Err(err)
    }
  }
  Ok(infos)
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
    Some(c) => Some(c.db.serialize_snapshot())
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
  let db = @vcdb.PersistentDB::from_snapshot(
    data, storage, base_path, config.name,
  )
  let collection : Collection[S] = { config, db }
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
