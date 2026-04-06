///|
/// Async primitives — bound to MoonBit's built-in coroutine system.
/// These work on ALL targets (JS, native, Wasm).
fn run_async(f : async () -> Unit noraise) -> Unit = "%async.run"

///|
async fn[T, E : Error] suspend(
  f : ((T) -> Unit, (E) -> Unit) -> Unit,
) -> T raise E = "%async.suspend"

///|
/// Async Storage trait — target-independent asynchronous storage abstraction.
///
/// Unlike the synchronous Storage trait, operations complete asynchronously
/// via MoonBit's native async/await mechanism (`%async.suspend`).
/// This works on ALL targets: JS (via Promise bridge), native (via event loop),
/// Wasm (via host callbacks).
///
/// For JS environments, the FFI layer converts JS Promises into suspend/resume.
/// For native environments, the FFI layer converts C callbacks into suspend/resume.
/// The persistence layer (WAL, snapshots, DualAsyncPersistence) is target-agnostic.
///
/// Each method takes a callback pair (resolve, reject) to signal completion.
/// The async fn wrappers in the runtime use %async.suspend to await these.

///|
/// Async storage trait — all targets.
/// All operations return results via MoonBit's async/await mechanism.
/// Implementors must call the provided continuation when I/O completes.
pub(open) trait AsyncStorage {
  /// Read file contents. Calls resolve with data, or reject on error.
  /// Missing files must reject rather than resolving empty Bytes.
  async_read(Self, String, StorageKind, (Bytes) -> Unit, (String) -> Unit) -> Unit
  /// Write data to file (overwrites existing).
  async_write(Self, String, Bytes, StorageKind, () -> Unit, (String) -> Unit) -> Unit
  /// Atomic write (same as write for most backends, but guarantees atomicity).
  async_atomic_write(
    Self,
    String,
    Bytes,
    StorageKind,
    () -> Unit,
    (String) -> Unit,
  ) -> Unit
  /// Delete file.
  async_del(Self, String, StorageKind, () -> Unit, (String) -> Unit) -> Unit
  /// Check if file exists.
  async_exists(Self, String, StorageKind, (Bool) -> Unit, (String) -> Unit) -> Unit
  /// List all files for a given kind. Rejects on backend failures.
  async_list(Self, StorageKind, (Array[String]) -> Unit, (String) -> Unit) -> Unit
}

///|
/// Error type for async storage operations.
pub(all) suberror AsyncIOError {
  AsyncIOFailed(String)
}

///|
/// Convenience async wrappers that use %async.suspend to bridge
/// callback-based AsyncStorage trait to MoonBit async/await.

///|
pub async fn[S : AsyncStorage] async_read(
  storage : S,
  path : String,
  kind : StorageKind,
) -> Bytes {
  suspend(fn(resolve, reject) {
    storage.async_read(path, kind, resolve, fn(err) {
      reject(AsyncIOFailed(err))
    })
  })
}

///|
pub async fn[S : AsyncStorage] async_write(
  storage : S,
  path : String,
  data : Bytes,
  kind : StorageKind,
) -> Unit {
  suspend(fn(resolve, reject) {
    storage.async_write(path, data, kind, fn() { resolve(()) }, fn(err) {
      reject(AsyncIOFailed(err))
    })
  })
}

///|
pub async fn[S : AsyncStorage] async_atomic_write(
  storage : S,
  path : String,
  data : Bytes,
  kind : StorageKind,
) -> Unit {
  suspend(fn(resolve, reject) {
    storage.async_atomic_write(path, data, kind, fn() { resolve(()) }, fn(err) {
      reject(AsyncIOFailed(err))
    })
  })
}

///|
pub async fn[S : AsyncStorage] async_del(
  storage : S,
  path : String,
  kind : StorageKind,
) -> Unit {
  suspend(fn(resolve, reject) {
    storage.async_del(path, kind, fn() { resolve(()) }, fn(err) {
      reject(AsyncIOFailed(err))
    })
  })
}

///|
pub async fn[S : AsyncStorage] async_exists(
  storage : S,
  path : String,
  kind : StorageKind,
) -> Bool {
  suspend(fn(resolve, reject) {
    storage.async_exists(path, kind, resolve, fn(err) {
      reject(AsyncIOFailed(err))
    })
  })
}

///|
pub async fn[S : AsyncStorage] async_list(
  storage : S,
  kind : StorageKind,
) -> Array[String] {
  suspend(fn(resolve, reject) {
    storage.async_list(kind, resolve, fn(err) { reject(AsyncIOFailed(err)) })
  })
}
