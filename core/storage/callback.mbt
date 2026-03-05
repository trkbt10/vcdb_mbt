///|
/// Callback-based Storage implementation
///
/// Allows external code (e.g., TypeScript) to provide storage operations
/// via registered callbacks. This enables S3, filesystem, or any custom
/// storage backend without modifying core code.
///
/// Design:
/// - Storage adapter: just does I/O (this file)
/// - Distribution config: CrushMap in placement package
/// - Routing decisions: app layer responsibility via kind parameter

///|
/// Storage callbacks - set by external code before use
/// Each callback receives StorageKind so app can route appropriately
pub struct StorageCallbacks {
  read : (String, StorageKind) -> Bytes
  write : (String, Bytes, StorageKind) -> Unit
  exists : (String, StorageKind) -> Bool
  del : (String, StorageKind) -> Unit
  list : (StorageKind) -> Array[String]
}

///|
/// Create storage callbacks from individual functions
pub fn StorageCallbacks::new(
  read : (String, StorageKind) -> Bytes,
  write : (String, Bytes, StorageKind) -> Unit,
  exists : (String, StorageKind) -> Bool,
  del : (String, StorageKind) -> Unit,
  list : (StorageKind) -> Array[String],
) -> StorageCallbacks {
  { read, write, exists, del, list }
}

///|
/// Global callback registry (single backend - app handles routing)
let callbacks : Ref[StorageCallbacks?] = { val: None }

///|
/// Register storage callbacks
pub fn register_callbacks(cb : StorageCallbacks) -> Unit {
  callbacks.val = Some(cb)
}

///|
/// Clear registered callbacks
pub fn clear_callbacks() -> Unit {
  callbacks.val = None
}

///|
/// Check if callbacks are registered
pub fn has_callbacks() -> Bool {
  callbacks.val is Some(_)
}

///|
/// Callback-based storage that delegates to registered functions
pub struct CallbackStorage {
  // Empty struct - uses global callbacks registry
  priv _unused : Unit
}

///|
/// Create CallbackStorage
pub fn CallbackStorage::new() -> CallbackStorage {
  { _unused: () }
}

///|
fn get_callbacks() -> StorageCallbacks? {
  callbacks.val
}

///|
fn[T] with_callbacks_or(default : T, f : (StorageCallbacks) -> T) -> T {
  match get_callbacks() {
    None => default
    Some(cb) => f(cb)
  }
}

///|
fn get_callbacks_raise() -> StorageCallbacks raise IOError {
  match get_callbacks() {
    None => raise IoFailed("Storage callbacks not registered")
    Some(cb) => cb
  }
}

///|
pub fn CallbackStorage::read(
  self : CallbackStorage,
  path : String,
  kind : StorageKind,
) -> Bytes raise IOError {
  ignore(self)
  let cb = get_callbacks_raise()
  let data = (cb.read)(path, kind)
  if data.length() == 0 && not((cb.exists)(path, kind)) {
    raise NotFound(path)
  }
  data
}

///|
pub fn CallbackStorage::write(
  self : CallbackStorage,
  path : String,
  data : Bytes,
  kind : StorageKind,
) -> Unit {
  ignore(self)
  with_callbacks_or((), fn(cb) { (cb.write)(path, data, kind) })
}

///|
pub fn CallbackStorage::append(
  self : CallbackStorage,
  path : String,
  data : Bytes,
  kind : StorageKind,
) -> Unit {
  ignore(self)
  with_callbacks_or((), fn(cb) {
    let existing = if (cb.exists)(path, kind) {
      (cb.read)(path, kind)
    } else {
      Bytes::new(0)
    }
    (cb.write)(path, concat_bytes(existing, data), kind)
  })
}

///|
pub fn CallbackStorage::atomic_write(
  self : CallbackStorage,
  path : String,
  data : Bytes,
  kind : StorageKind,
) -> Unit {
  self.write(path, data, kind)
}

///|
pub fn CallbackStorage::del(
  self : CallbackStorage,
  path : String,
  kind : StorageKind,
) -> Unit raise IOError {
  ignore(self)
  let cb = get_callbacks_raise()
  if not((cb.exists)(path, kind)) {
    raise NotFound(path)
  }
  (cb.del)(path, kind)
}

///|
pub fn CallbackStorage::exists(
  self : CallbackStorage,
  path : String,
  kind : StorageKind,
) -> Bool {
  ignore(self)
  with_callbacks_or(false, fn(cb) { (cb.exists)(path, kind) })
}

///|
pub fn CallbackStorage::list(
  self : CallbackStorage,
  kind : StorageKind,
) -> Array[String] {
  ignore(self)
  with_callbacks_or([], fn(cb) { (cb.list)(kind) })
}

///|
pub impl Storage for CallbackStorage with read(self, path, kind) {
  self.read(path, kind)
}

///|
pub impl Storage for CallbackStorage with write(self, path, data, kind) {
  self.write(path, data, kind)
}

///|
pub impl Storage for CallbackStorage with append(self, path, data, kind) {
  self.append(path, data, kind)
}

///|
pub impl Storage for CallbackStorage with atomic_write(self, path, data, kind) {
  self.atomic_write(path, data, kind)
}

///|
pub impl Storage for CallbackStorage with del(self, path, kind) {
  self.del(path, kind)
}

///|
pub impl Storage for CallbackStorage with exists(self, path, kind) {
  self.exists(path, kind)
}

///|
pub impl Storage for CallbackStorage with list(self, kind) {
  self.list(kind)
}
