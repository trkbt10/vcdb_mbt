///|
/// CollectionManager - manages multiple VectorDB collections
///
/// Simple storage: uses single Storage for all data.
/// Distributed storage: app layer handles routing via placement/io.mbt functions.

///|
/// Collection entry
pub struct Collection {
  config : CollectionConfig
  db : @vcdb.VectorDB
}

///|
/// Collection manager with optional storage
pub struct CollectionManager[S] {
  collections : Map[String, Collection]
  storage : S?
  base_path : String
}

///|
/// Create without storage (in-memory only)
pub fn[S : @storage.Storage] CollectionManager::new(
  base_path? : String = "",
) -> CollectionManager[S] {
  { collections: {}, storage: None, base_path }
}

///|
/// Create with storage
pub fn[S : @storage.Storage] CollectionManager::with_storage(
  storage : S,
  base_path? : String = "",
) -> CollectionManager[S] {
  { collections: {}, storage: Some(storage), base_path }
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

  // Save config
  let config_path = make_path(
    self.base_path,
    @storage.collection_config_path(name),
  )
  let config_json = col.config.to_json().to_string()
  let config_bytes = Bytes::from_array(
    config_json.to_array().map(fn(c) { c.to_int().to_byte() }),
  )
  storage.write(config_path, config_bytes, @storage.Config) catch {
    _ => ()
  }

  // Save data
  let data_path = make_path(self.base_path, @storage.collection_data_path(name))
  let data = col.db.serialize()
  storage.write(data_path, data, @storage.Data) catch {
    _ => ()
  }
}

///|
fn[S : @storage.Storage] CollectionManager::load_collection_from_storage(
  self : CollectionManager[S],
  name : String,
) -> Collection? {
  let storage = match self.storage {
    Some(s) => s
    None => return None
  }

  // Load config
  let config_path = make_path(
    self.base_path,
    @storage.collection_config_path(name),
  )
  let config_bytes = storage.read(config_path, @storage.Config) catch {
    _ => return None
  }
  let config_str = bytes_to_string(config_bytes)
  let config = match parse_json(config_str) {
    Some(json) =>
      CollectionConfig::from_json(json).unwrap_or(
        CollectionConfig::default(name, 128),
      )
    None => return None
  }

  // Load data
  let data_path = make_path(self.base_path, @storage.collection_data_path(name))
  let data = storage.read(data_path, @storage.Data) catch { _ => return None }
  let db = @vcdb.VectorDB::deserialize(data)
  Some({ config, db })
}

///|
fn bytes_to_string(bytes : Bytes) -> String {
  let chars : Array[Char] = []
  for i in 0..<bytes.length() {
    chars.push(Char::from_int(bytes[i].to_int()))
  }
  String::from_array(chars)
}

///|
fn[S : @storage.Storage] CollectionManager::remove_persisted_collection(
  self : CollectionManager[S],
  name : String,
) -> Unit {
  let storage = match self.storage {
    Some(s) => s
    None => return
  }

  let config_path = make_path(
    self.base_path,
    @storage.collection_config_path(name),
  )
  let data_path = make_path(self.base_path, @storage.collection_data_path(name))

  if storage.exists(config_path, @storage.Config) {
    storage.del(config_path, @storage.Config) catch {
      _ => ()
    }
  }
  if storage.exists(data_path, @storage.Data) {
    storage.del(data_path, @storage.Data) catch {
      _ => ()
    }
  }
}

///|
pub fn[S : @storage.Storage] CollectionManager::create(
  self : CollectionManager[S],
  config : CollectionConfig,
) -> Result[Unit, GatewayError] {
  if self.collections.contains(config.name) {
    return Err(CollectionExists(config.name))
  }
  let options : @types.DatabaseOptions = {
    dim: config.dim,
    metric: config.metric,
    capacity: 1024,
    strategy: config.strategy,
  }
  let db = @vcdb.VectorDB::new(options)
  let collection : Collection = { config, db }
  self.collections[config.name] = collection
  self.persist_collection(config.name)
  Ok(())
}

///|
pub fn[S : @storage.Storage] CollectionManager::get(
  self : CollectionManager[S],
  name : String,
) -> @vcdb.VectorDB? {
  match self.collections.get(name) {
    Some(c) => Some(c.db)
    None =>
      match self.load_collection_from_storage(name) {
        Some(col) => {
          self.collections[name] = col
          Some(col.db)
        }
        None => None
      }
  }
}

///|
pub fn[S : @storage.Storage] CollectionManager::get_info(
  self : CollectionManager[S],
  name : String,
) -> CollectionInfo? {
  match self.collections.get(name) {
    Some(c) => {
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
pub fn[S : @storage.Storage] CollectionManager::delete(
  self : CollectionManager[S],
  name : String,
) -> Result[Unit, GatewayError] {
  if not(self.collections.contains(name)) {
    return Err(CollectionNotFound(name))
  }
  self.collections.remove(name)
  self.remove_persisted_collection(name)
  Ok(())
}

///|
pub fn[S : @storage.Storage] CollectionManager::notify_modified(
  self : CollectionManager[S],
  name : String,
) -> Unit {
  self.persist_collection(name)
}

///|
pub fn[S : @storage.Storage] CollectionManager::list(
  self : CollectionManager[S],
) -> Array[String] {
  self.collections.keys().collect()
}

///|
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
pub fn[S : @storage.Storage] CollectionManager::exists(
  self : CollectionManager[S],
  name : String,
) -> Bool {
  self.collections.contains(name)
}

///|
pub fn[S : @storage.Storage] CollectionManager::count(
  self : CollectionManager[S],
) -> Int {
  self.collections.length()
}

///|
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
