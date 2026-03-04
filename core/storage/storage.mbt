///|
/// IO Error types for storage operations
pub(all) suberror IOError {
  NotFound(String)
  PermissionDenied(String)
  IoFailed(String)
}

///|
/// Storage trait - abstraction for file-like storage operations
pub trait Storage {
  read(Self, String) -> Bytes raise IOError
  write(Self, String, Bytes) -> Unit raise IOError
  append(Self, String, Bytes) -> Unit raise IOError
  atomic_write(Self, String, Bytes) -> Unit raise IOError
  del(Self, String) -> Unit raise IOError
  exists(Self, String) -> Bool
  list(Self) -> Array[String]
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
    Some(existing) => {
      // Concatenate existing and new data using BinaryWriter
      let w = @binary.BinaryWriter::new()
      w.push_bytes(existing)
      w.push_bytes(data)
      self.data.set(path, w.concat())
    }
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
pub impl Storage for MemoryStorage with read(self, path) {
  self.read(path)
}

///|
pub impl Storage for MemoryStorage with write(self, path, data) {
  self.write(path, data)
}

///|
pub impl Storage for MemoryStorage with append(self, path, data) {
  self.append(path, data)
}

///|
pub impl Storage for MemoryStorage with atomic_write(self, path, data) {
  self.atomic_write(path, data)
}

///|
pub impl Storage for MemoryStorage with del(self, path) {
  self.del(path)
}

///|
pub impl Storage for MemoryStorage with exists(self, path) {
  self.exists(path)
}

///|
pub impl Storage for MemoryStorage with list(self) {
  self.list()
}
