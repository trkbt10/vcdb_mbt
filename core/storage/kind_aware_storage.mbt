///|
/// Kind-aware memory storage — TEST UTILITY.
///
/// Unlike MemoryStorage (which ignores kind), this stores data
/// in separate maps per StorageKind, enabling tests to verify
/// that operations route to the correct kind.
///
/// Not intended for production use. Prefer MemoryStorage for
/// general in-memory usage or CallbackStorage for external backends.
pub struct KindAwareStorage {
  config : Map[String, Bytes]
  index : Map[String, Bytes]
  data : Map[String, Bytes]
}

///|
pub fn KindAwareStorage::new() -> KindAwareStorage {
  { config: {}, index: {}, data: {} }
}

///|
fn KindAwareStorage::map_for(self : KindAwareStorage, kind : StorageKind) -> Map[String, Bytes] {
  match kind {
    Config => self.config
    Index => self.index
    Data => self.data
  }
}

///|
/// List files stored under a specific kind
pub fn KindAwareStorage::list_kind(
  self : KindAwareStorage,
  kind : StorageKind,
) -> Array[String] {
  self.map_for(kind).keys().collect()
}

///|
pub impl Storage for KindAwareStorage with read(self, path, kind) {
  match self.map_for(kind).get(path) {
    None => raise NotFound(path)
    Some(data) => data
  }
}

///|
pub impl Storage for KindAwareStorage with write(self, path, data, kind) {
  self.map_for(kind).set(path, data)
}

///|
pub impl Storage for KindAwareStorage with append(self, path, data, kind) {
  match self.map_for(kind).get(path) {
    None => self.map_for(kind).set(path, data)
    Some(existing) => self.map_for(kind).set(path, concat_bytes(existing, data))
  }
}

///|
pub impl Storage for KindAwareStorage with atomic_write(self, path, data, kind) {
  self.map_for(kind).set(path, data)
}

///|
pub impl Storage for KindAwareStorage with del(self, path, kind) {
  if self.map_for(kind).contains(path) {
    self.map_for(kind).remove(path)
  } else {
    raise NotFound(path)
  }
}

///|
pub impl Storage for KindAwareStorage with exists(self, path, kind) {
  self.map_for(kind).contains(path)
}

///|
pub impl Storage for KindAwareStorage with list(self, kind) {
  self.map_for(kind).keys().collect()
}

///|
/// AsyncStorage implementation for KindAwareStorage.
/// Like MemoryStorage, resolve is called synchronously.
pub impl AsyncStorage for KindAwareStorage with async_read(self, path, kind, resolve, reject) {
  match self.map_for(kind).get(path) {
    None => reject("Not found: " + path)
    Some(data) => resolve(data)
  }
}

///|
pub impl AsyncStorage for KindAwareStorage with async_write(self, path, data, kind, resolve, _reject) {
  self.map_for(kind).set(path, data)
  resolve()
}

///|
pub impl AsyncStorage for KindAwareStorage with async_atomic_write(self, path, data, kind, resolve, _reject) {
  self.map_for(kind).set(path, data)
  resolve()
}

///|
pub impl AsyncStorage for KindAwareStorage with async_del(self, path, kind, resolve, reject) {
  if self.map_for(kind).contains(path) {
    self.map_for(kind).remove(path)
    resolve()
  } else {
    reject("Not found: " + path)
  }
}

///|
pub impl AsyncStorage for KindAwareStorage with async_exists(self, path, kind, resolve, _reject) {
  resolve(self.map_for(kind).contains(path))
}

///|
pub impl AsyncStorage for KindAwareStorage with async_list(self, kind, resolve, _reject) {
  resolve(self.map_for(kind).keys().collect())
}
