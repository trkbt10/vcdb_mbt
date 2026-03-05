///|
/// IO Error types for storage operations
pub(all) suberror IOError {
  NotFound(String)
  PermissionDenied(String)
  IoFailed(String)
}

///|
/// Storage kind - tells app what type of data is being stored
/// App uses this to route to appropriate backend (e.g., index→DynamoDB, data→S3)
pub(all) enum StorageKind {
  Config // Collection configuration (.config.json)
  Index // Index structures, manifests (.index, .manifest.json)
  Data // Vector data, segments (.data.bin, segment files)
}

///|
/// Storage trait - abstraction for file-like storage operations
/// kind parameter allows app to route different data types to different backends
pub trait Storage {
  read(Self, String, StorageKind) -> Bytes raise IOError
  write(Self, String, Bytes, StorageKind) -> Unit raise IOError
  append(Self, String, Bytes, StorageKind) -> Unit raise IOError
  atomic_write(Self, String, Bytes, StorageKind) -> Unit raise IOError
  del(Self, String, StorageKind) -> Unit raise IOError
  exists(Self, String, StorageKind) -> Bool
  list(Self, StorageKind) -> Array[String]
}

///|
/// Memory-based storage implementation for testing and in-memory use cases
pub struct MemoryStorage {
  data : Map[String, Bytes]
}

///|
/// Create a new empty MemoryStorage
pub fn MemoryStorage::new() -> MemoryStorage {
  { data: {} }
}

///|
/// Read file contents
pub fn MemoryStorage::read(
  self : MemoryStorage,
  path : String,
) -> Bytes raise IOError {
  match self.data.get(path) {
    None => raise NotFound(path)
    Some(data) => data
  }
}

///|
/// Write file contents (overwrites)
pub fn MemoryStorage::write(
  self : MemoryStorage,
  path : String,
  data : Bytes,
) -> Unit {
  self.data.set(path, data)
}

///|
/// Append data to file
pub fn MemoryStorage::append(
  self : MemoryStorage,
  path : String,
  data : Bytes,
) -> Unit {
  match self.data.get(path) {
    None => self.data.set(path, data)
    Some(existing) => self.data.set(path, concat_bytes(existing, data))
  }
}

///|
/// Atomic write (same as write for in-memory implementation)
pub fn MemoryStorage::atomic_write(
  self : MemoryStorage,
  path : String,
  data : Bytes,
) -> Unit {
  self.data.set(path, data)
}

///|
/// Delete a file
pub fn MemoryStorage::del(
  self : MemoryStorage,
  path : String,
) -> Unit raise IOError {
  if self.data.contains(path) {
    self.data.remove(path)
  } else {
    raise NotFound(path)
  }
}

///|
/// Check if a file exists
pub fn MemoryStorage::exists(self : MemoryStorage, path : String) -> Bool {
  self.data.contains(path)
}

///|
/// List all files
pub fn MemoryStorage::list(self : MemoryStorage) -> Array[String] {
  self.data.keys().collect()
}

///|
/// Clear all files
pub fn MemoryStorage::clear(self : MemoryStorage) -> Unit {
  self.data.clear()
}

///|
/// Storage trait implementation for MemoryStorage
/// MemoryStorage ignores kind - stores all data in single map
pub impl Storage for MemoryStorage with read(self, path, _kind) {
  self.read(path)
}

///|
pub impl Storage for MemoryStorage with write(self, path, data, _kind) {
  self.write(path, data)
}

///|
pub impl Storage for MemoryStorage with append(self, path, data, _kind) {
  self.append(path, data)
}

///|
pub impl Storage for MemoryStorage with atomic_write(self, path, data, _kind) {
  self.atomic_write(path, data)
}

///|
pub impl Storage for MemoryStorage with del(self, path, _kind) {
  self.del(path)
}

///|
pub impl Storage for MemoryStorage with exists(self, path, _kind) {
  self.exists(path)
}

///|
pub impl Storage for MemoryStorage with list(self, _kind) {
  self.list()
}
