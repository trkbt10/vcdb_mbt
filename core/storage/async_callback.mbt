///|
fn run_async(f : async () -> Unit noraise) -> Unit = "%async.run"

///|
/// Async Callback-based Storage implementation for JS environments.
///
/// Wraps JS Promise-returning callbacks into the target-independent
/// AsyncStorage trait (continuation-passing style).
///
/// JS FFI registers Promise-returning functions. This adapter uses
/// Promise.then() to bridge to the continuation callbacks, avoiding
/// the need for async fn in trait impl bodies.
///
/// Supports multiple named instances for dual-backend patterns:
///   - "wal-{instance_id}" → WAL storage (e.g., Durable Object storage)
///   - "snapshot-{instance_id}" → Snapshot storage (e.g., R2)
/// Name derivation is centralized in persistent_exports.mbt
/// (wal_callback_name / snapshot_callback_name).
///
/// JS target only (uses @js_async.Promise for JS interop).

///|
/// JS-specific async storage callbacks — each returns a Promise.
pub struct JsAsyncStorageCallbacks {
  read : (String, StorageKind) -> @js_async.Promise[Bytes]
  write : (String, Bytes, StorageKind) -> @js_async.Promise[Unit]
  atomic_write : (String, Bytes, StorageKind) -> @js_async.Promise[Unit]
  del : (String, StorageKind) -> @js_async.Promise[Unit]
  exists : (String, StorageKind) -> @js_async.Promise[Bool]
  list : (StorageKind) -> @js_async.Promise[Array[String]]
}

///|
pub fn JsAsyncStorageCallbacks::new(
  read : (String, StorageKind) -> @js_async.Promise[Bytes],
  write : (String, Bytes, StorageKind) -> @js_async.Promise[Unit],
  atomic_write : (String, Bytes, StorageKind) -> @js_async.Promise[Unit],
  del : (String, StorageKind) -> @js_async.Promise[Unit],
  exists : (String, StorageKind) -> @js_async.Promise[Bool],
  list : (StorageKind) -> @js_async.Promise[Array[String]],
) -> JsAsyncStorageCallbacks {
  { read, write, atomic_write, del, exists, list }
}

///|
/// Named callback registry for multiple JS async storage backends.
let js_async_callbacks : @hashmap.HashMap[String, JsAsyncStorageCallbacks] = @hashmap.new()

///|
pub fn register_js_async_callbacks(
  name : String,
  cb : JsAsyncStorageCallbacks,
) -> Unit {
  js_async_callbacks[name] = cb
}

///|
pub fn clear_js_async_callbacks(name : String) -> Unit {
  js_async_callbacks.remove(name)
}

///|
pub fn has_js_async_callbacks(name : String) -> Bool {
  js_async_callbacks.contains(name)
}

///|
/// JS async callback storage, bound to a named backend.
/// Implements the target-independent AsyncStorage trait by bridging
/// JS Promises through the continuation-passing interface.
pub struct JsAsyncCallbackStorage {
  name : String
}

///|
pub fn JsAsyncCallbackStorage::new(name : String) -> JsAsyncCallbackStorage {
  { name, }
}

///|
fn JsAsyncCallbackStorage::get_callbacks(
  self : JsAsyncCallbackStorage,
) -> Result[JsAsyncStorageCallbacks, String] {
  match js_async_callbacks.get(self.name) {
    Some(cb) => Ok(cb)
    None => Err("JS async storage callbacks not registered: " + self.name)
  }
}

// ── Helper: bridge JS Promise to continuation-passing ──
// We use run_async + Promise::wait() inside a spawned coroutine,
// then call the continuation from within that coroutine.

///|
fn[T] await_promise(
  promise : @js_async.Promise[T],
  resolve : (T) -> Unit,
  reject : (String) -> Unit,
) -> Unit {
  fn local_run() {
    run_async(fn() {
      try {
        let result = promise.wait()
        resolve(result)
      } catch {
        err => reject(err.to_string())
      }
    })
  }

  local_run()
}

///|
fn await_promise_unit(
  promise : @js_async.Promise[Unit],
  resolve : () -> Unit,
  reject : (String) -> Unit,
) -> Unit {
  fn local_run() {
    run_async(fn() {
      try {
        promise.wait()
        resolve()
      } catch {
        err => reject(err.to_string())
      }
    })
  }

  local_run()
}

///|
pub impl AsyncStorage for JsAsyncCallbackStorage with async_read(
  self,
  path,
  kind,
  resolve,
  reject,
) {
  let cb = match self.get_callbacks() {
    Ok(cb) => cb
    Err(msg) => return reject(msg)
  }
  await_promise((cb.read)(path, kind), resolve, reject)
}

///|
pub impl AsyncStorage for JsAsyncCallbackStorage with async_write(
  self,
  path,
  data,
  kind,
  resolve,
  reject,
) {
  let cb = match self.get_callbacks() {
    Ok(cb) => cb
    Err(msg) => return reject(msg)
  }
  await_promise_unit((cb.write)(path, data, kind), resolve, reject)
}

///|
pub impl AsyncStorage for JsAsyncCallbackStorage with async_atomic_write(
  self,
  path,
  data,
  kind,
  resolve,
  reject,
) {
  let cb = match self.get_callbacks() {
    Ok(cb) => cb
    Err(msg) => return reject(msg)
  }
  await_promise_unit((cb.atomic_write)(path, data, kind), resolve, reject)
}

///|
pub impl AsyncStorage for JsAsyncCallbackStorage with async_del(
  self,
  path,
  kind,
  resolve,
  reject,
) {
  let cb = match self.get_callbacks() {
    Ok(cb) => cb
    Err(msg) => return reject(msg)
  }
  await_promise_unit((cb.del)(path, kind), resolve, reject)
}

///|
pub impl AsyncStorage for JsAsyncCallbackStorage with async_exists(
  self,
  path,
  kind,
  resolve,
  reject,
) {
  let cb = match self.get_callbacks() {
    Ok(cb) => cb
    Err(msg) => return reject(msg)
  }
  await_promise((cb.exists)(path, kind), resolve, reject)
}

///|
pub impl AsyncStorage for JsAsyncCallbackStorage with async_list(
  self,
  kind,
  resolve,
  reject,
) {
  let cb = match self.get_callbacks() {
    Ok(cb) => cb
    Err(msg) => return reject(msg)
  }
  await_promise((cb.list)(kind), resolve, reject)
}
