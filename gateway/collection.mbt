///|
/// Collection manager for multi-collection support
/// Manages multiple VectorDB instances

///|
/// Collection entry with config and database instance
pub struct Collection {
  config : CollectionConfig
  db : @vcdb.VectorDB
}

///|
/// Collection manager
pub struct CollectionManager {
  collections : Map[String, Collection]
  storage_path : String
}

///|
/// Create a new collection manager
pub fn CollectionManager::new(
  storage_path? : String = "./storage",
) -> CollectionManager {
  { collections: {}, storage_path }
}

///|
/// Create a new collection
pub fn CollectionManager::create(
  self : CollectionManager,
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
  Ok(())
}

///|
/// Get a collection by name
pub fn CollectionManager::get(
  self : CollectionManager,
  name : String,
) -> @vcdb.VectorDB? {
  match self.collections.get(name) {
    Some(c) => Some(c.db)
    None => None
  }
}

///|
/// Get collection info
pub fn CollectionManager::get_info(
  self : CollectionManager,
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
pub fn CollectionManager::delete(
  self : CollectionManager,
  name : String,
) -> Result[Unit, GatewayError] {
  if not(self.collections.contains(name)) {
    return Err(CollectionNotFound(name))
  }
  self.collections.remove(name)
  Ok(())
}

///|
/// List all collection names
pub fn CollectionManager::list(self : CollectionManager) -> Array[String] {
  let names : Array[String] = []
  for kv in self.collections {
    let (name, _) = kv
    names.push(name)
  }
  names
}

///|
/// List all collections with info
pub fn CollectionManager::list_info(
  self : CollectionManager,
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
pub fn CollectionManager::exists(
  self : CollectionManager,
  name : String,
) -> Bool {
  self.collections.contains(name)
}

///|
/// Get the number of collections
pub fn CollectionManager::count(self : CollectionManager) -> Int {
  self.collections.length()
}

///|
/// Serialize a collection to bytes (for persistence)
pub fn CollectionManager::serialize_collection(
  self : CollectionManager,
  name : String,
) -> Bytes? {
  match self.collections.get(name) {
    Some(c) => Some(c.db.serialize())
    None => None
  }
}

///|
/// Deserialize and load a collection
pub fn CollectionManager::load_collection(
  self : CollectionManager,
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
pub fn CollectionManager::export_metadata(
  self : CollectionManager,
) -> JsonValue {
  let collections : Array[JsonValue] = []
  for kv in self.collections {
    let (_, c) = kv
    collections.push(c.config.to_json())
  }
  json_object([("version", JNumber(1.0)), ("collections", JArray(collections))])
}
