///|
/// Collection manager for multi-collection support
/// Manages multiple VectorDB instances with optional persistence
///
/// Generic over Storage trait - allows pluggable storage backends

///|
/// Collection entry with config and database instance
pub struct Collection {
  config : CollectionConfig
  db : @vcdb.VectorDB
}

///|
/// Collection manager with pluggable storage backend
pub struct CollectionManager[S] {
  collections : Map[String, Collection]
  storage : S?
  base_path : String
}

///|
/// Create a new collection manager without storage
pub fn[S : @storage.Storage] CollectionManager::new(
  base_path? : String = "",
) -> CollectionManager[S] {
  { collections: {}, storage: None, base_path }
}

///|
/// Create a new collection manager with storage
pub fn[S : @storage.Storage] CollectionManager::with_storage(
  storage : S,
  base_path? : String = "",
) -> CollectionManager[S] {
  { collections: {}, storage: Some(storage), base_path }
}

///|
/// Get path for collection data
fn collection_data_path(base_path : String, name : String) -> String {
  if base_path.length() == 0 {
    name + "/data.json"
  } else {
    base_path + "/" + name + "/data.json"
  }
}

///|
/// Get path for collection config
fn collection_config_path(base_path : String, name : String) -> String {
  if base_path.length() == 0 {
    name + "/config.json"
  } else {
    base_path + "/" + name + "/config.json"
  }
}

///|
/// Persist a collection to storage
fn[S : @storage.Storage] CollectionManager::persist_collection(
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

  // Save config as JSON
  let config_path = collection_config_path(self.base_path, name)
  let config_json = col.config.to_json().to_string()
  let config_bytes = Bytes::from_array(
    config_json.to_array().map(fn(c) { c.to_int().to_byte() }),
  )
  S::write(storage, config_path, config_bytes) catch {
    _ => ()
  }

  // Save data as binary
  let data_path = collection_data_path(self.base_path, name)
  let data = col.db.serialize()
  S::write(storage, data_path, data) catch {
    _ => ()
  }
}

///|
/// Remove persisted collection data
fn[S : @storage.Storage] CollectionManager::remove_persisted_collection(
  self : CollectionManager[S],
  name : String,
) -> Unit {
  let storage = match self.storage {
    Some(s) => s
    None => return
  }

  let config_path = collection_config_path(self.base_path, name)
  let data_path = collection_data_path(self.base_path, name)

  if S::exists(storage, config_path) {
    S::del(storage, config_path) catch {
      _ => ()
    }
  }
  if S::exists(storage, data_path) {
    S::del(storage, data_path) catch {
      _ => ()
    }
  }
}

///|
/// Create a new collection
pub fn[S : @storage.Storage] CollectionManager::create(
  self : CollectionManager[S],
  config : CollectionConfig,
) -> Result[Unit, GatewayError] {
  if self.collections.contains(config.name) {
    return Err(CollectionExists(config.name))
  }
  let options : @core.DatabaseOptions = {
    dim: config.dim,
    metric: config.metric,
    capacity: 1024,
    strategy: config.strategy,
  }
  let db = @vcdb.VectorDB::new(options)
  let collection : Collection = { config, db }
  self.collections[config.name] = collection

  // Auto-persist
  self.persist_collection(config.name)

  Ok(())
}

///|
/// Get a collection by name
pub fn[S : @storage.Storage] CollectionManager::get(
  self : CollectionManager[S],
  name : String,
) -> @vcdb.VectorDB? {
  match self.collections.get(name) {
    Some(c) => Some(c.db)
    None => None
  }
}

///|
/// Get collection info
pub fn[S : @storage.Storage] CollectionManager::get_info(
  self : CollectionManager[S],
  name : String,
) -> CollectionInfo? {
  match self.collections.get(name) {
    Some(c) => {
      let metric_str = match c.config.metric {
        @core.Cosine => "Cosine"
        @core.L2 => "L2"
        @core.Dot => "Dot"
      }
      let strategy_str = match c.config.strategy {
        @core.Bruteforce => "Bruteforce"
        @core.HNSW(_) => "HNSW"
        @core.IVF(_) => "IVF"
      }
      Some({
        name: c.config.name,
        vectors_count: c.db.size(),
        dim: c.config.dim,
        metric: metric_str,
        strategy: strategy_str,
      })
    }
    None => None
  }
}

///|
/// Delete a collection
pub fn[S : @storage.Storage] CollectionManager::delete(
  self : CollectionManager[S],
  name : String,
) -> Result[Unit, GatewayError] {
  if not(self.collections.contains(name)) {
    return Err(CollectionNotFound(name))
  }
  self.collections.remove(name)

  // Remove persisted data
  self.remove_persisted_collection(name)

  Ok(())
}

///|
/// Notify that a collection was modified (for persistence)
pub fn[S : @storage.Storage] CollectionManager::notify_modified(
  self : CollectionManager[S],
  name : String,
) -> Unit {
  self.persist_collection(name)
}

///|
/// List all collection names
pub fn[S : @storage.Storage] CollectionManager::list(
  self : CollectionManager[S],
) -> Array[String] {
  let names : Array[String] = []
  for kv in self.collections {
    let (name, _) = kv
    names.push(name)
  }
  names
}

///|
/// List all collections with info
pub fn[S : @storage.Storage] CollectionManager::list_info(
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
/// Check if a collection exists
pub fn[S : @storage.Storage] CollectionManager::exists(
  self : CollectionManager[S],
  name : String,
) -> Bool {
  self.collections.contains(name)
}

///|
/// Get the number of collections
pub fn[S : @storage.Storage] CollectionManager::count(
  self : CollectionManager[S],
) -> Int {
  self.collections.length()
}

///|
/// Serialize a collection to bytes (for persistence)
pub fn[S : @storage.Storage] CollectionManager::serialize_collection(
  self : CollectionManager[S],
  name : String,
) -> Bytes? {
  match self.collections.get(name) {
    Some(c) => Some(c.db.serialize())
    None => None
  }
}

///|
/// Deserialize and load a collection
pub fn[S : @storage.Storage] CollectionManager::load_collection(
  self : CollectionManager[S],
  config : CollectionConfig,
  data : Bytes,
) -> Result[Unit, GatewayError] {
  if self.collections.contains(config.name) {
    return Err(CollectionExists(config.name))
  }
  let db = @vcdb.VectorDB::deserialize(data)
  let collection : Collection = { config, db }
  self.collections[config.name] = collection
  Ok(())
}

///|
/// Export collections metadata as JSON
pub fn[S : @storage.Storage] CollectionManager::export_metadata(
  self : CollectionManager[S],
) -> JsonValue {
  let collections : Array[JsonValue] = []
  for kv in self.collections {
    let (_, c) = kv
    collections.push(c.config.to_json())
  }
  json_object([("version", JNumber(1.0)), ("collections", JArray(collections))])
}
