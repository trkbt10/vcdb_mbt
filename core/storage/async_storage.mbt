///|
/// Async Storage trait for JS environments (Durable Objects, IndexedDB, etc.)
///
/// Unlike the synchronous Storage trait, every operation returns a Promise
/// that resolves when the I/O is truly complete. This ensures WAL writes
/// are durable before proceeding — no CachedStorage needed.

///|
/// Async storage trait — JS target only.
/// All operations return Promise so callers can await actual persistence.
pub(open) trait AsyncStorage {
  read(Self, String, StorageKind) -> @js_async.Promise[Bytes]
  write(Self, String, Bytes, StorageKind) -> @js_async.Promise[Unit]
  atomic_write(Self, String, Bytes, StorageKind) -> @js_async.Promise[Unit]
  del(Self, String, StorageKind) -> @js_async.Promise[Unit]
  exists(Self, String, StorageKind) -> @js_async.Promise[Bool]
  list(Self, StorageKind) -> @js_async.Promise[Array[String]]
}
