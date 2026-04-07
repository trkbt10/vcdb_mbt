///|
/// Gateway FFI exports — JS-only (uses @js_async.Promise).
///
/// All operations go through PersistentVectorDB's WAL-before-state ordering
/// via the async CollectionManager.

///|
/// Global storage for gateway (in-memory, implements both Storage and AsyncStorage)
let gateway_storage : @storage.MemoryStorage = @storage.MemoryStorage::new()

///|
/// Manager with MemoryStorage
let gateway_manager : @gateway.CollectionManager[@storage.MemoryStorage] = @gateway.CollectionManager::with_storage(
  gateway_storage,
)

///|
/// Execute gateway request (async — returns Promise in JS).
pub fn gateway_request(
  http_method : String,
  path : Array[String],
  body : String,
) -> @js_async.Promise[String] {
  @js_async.Promise::from_async(async fn() {
    let response = @gateway.execute_request(
      gateway_manager, http_method, path, body,
    )
    response.to_json().stringify()
  })
}

///|
/// Register storage callbacks (no-op — use persistent_* API for external storage).
/// Retained for export symbol backward compatibility.
pub fn gateway_register_storage(
  _read_fn : (String, Int) -> Bytes,
  _write_fn : (String, Bytes, Int) -> Unit,
  _exists_fn : (String, Int) -> Bool,
  _del_fn : (String, Int) -> Unit,
  _list_fn : (Int) -> Array[String],
) -> Unit {
  // Use persistent_register_wal_storage / persistent_register_snapshot_storage instead.
}

///|
pub fn gateway_clear_storage_callbacks() -> Unit {
  // No-op — CallbackStorage removed
}

///|
pub fn gateway_storage_list(_kind : Int) -> Array[String] {
  gateway_storage.list()
}

///|
pub fn gateway_storage_read(
  path : String,
  _kind : Int,
) -> Bytes raise @storage.IOError {
  gateway_storage.read(path)
}

///|
pub fn gateway_storage_write(path : String, data : Bytes, _kind : Int) -> Unit {
  gateway_storage.write(path, data)
}

///|
pub fn gateway_storage_exists(path : String, _kind : Int) -> Bool {
  gateway_storage.exists(path)
}
