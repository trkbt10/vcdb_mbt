///|
/// Convert StorageKind to Int (used by persistent_exports and gateway_exports)
fn kind_to_int(kind : @storage.StorageKind) -> Int {
  match kind {
    @storage.Config => 0
    @storage.Index => 1
    @storage.Data => 2
  }
}

///|
/// Persistent FFI exports — WAL-before-state durable operations.
///
/// Wire format for VectorId: Bytes of exactly 16 bytes.
/// See VectorId::to_wire_bytes / VectorId::from_wire_bytes for details.
///
/// JS callers must:
///   1. Register async storage callbacks via persistent_register_wal_storage /
///      persistent_register_snapshot_storage
///   2. Call persistent_init to create an instance
///   3. Use persistent_upsert etc. — each returns a Promise
///
/// Read operations (search, get, scroll) are synchronous — no Promise needed.

///|
/// Instance storage for persistent mode.
let persistent_instances : @hashmap.HashMap[
  Int,
  @vcdb.PersistentDB[
    @storage.JsAsyncCallbackStorage,
    @storage.JsAsyncCallbackStorage,
  ],
] = @hashmap.new()

///|
/// Monotonic counter for persistent instance ID allocation.
/// SoT for instance ID generation — JS must not generate IDs independently.
priv struct PersistentCounter {
  mut value : Int
}

///|
let persistent_counter : PersistentCounter = { value: 1 }

///|
/// Allocate a unique persistent instance ID.
/// JS must call this before persistent_register_*_storage and persistent_init.
///
/// Thread safety: relies on single-threaded execution (JS event loop).
/// NOT safe for concurrent calls from multiple threads (wasm-gc shared memory,
/// native multi-threading). Use explicit instanceId in those environments.
pub fn persistent_allocate_id() -> Int {
  let id = persistent_counter.value
  persistent_counter.value = persistent_counter.value + 1
  id
}

// ── Callback name derivation (SoT) ──────────────────────────

///|
fn wal_callback_name(instance_id : Int) -> String {
  "wal-" + instance_id.to_string()
}

///|
fn snapshot_callback_name(instance_id : Int) -> String {
  "snapshot-" + instance_id.to_string()
}

///|
fn parse_metric_name(metric : String) -> @types.Metric raise Error {
  match @types.Metric::from_name(metric) {
    Some(m) => m
    None =>
      raise @storage.AsyncIOFailed(
        "Unsupported metric for persistent_init: " + metric,
      )
  }
}

///|
fn parse_strategy_name(strategy : String) -> @types.Strategy raise Error {
  match @types.Strategy::from_name(strategy) {
    Some(s) => s
    None =>
      raise @storage.AsyncIOFailed(
        "Unsupported strategy for persistent_init: " + strategy,
      )
  }
}

///|
fn make_storage_callbacks(
  read : (String, Int) -> @js_async.Promise[Bytes],
  write : (String, Bytes, Int) -> @js_async.Promise[Unit],
  atomic_write : (String, Bytes, Int) -> @js_async.Promise[Unit],
  del : (String, Int) -> @js_async.Promise[Unit],
  exists : (String, Int) -> @js_async.Promise[Bool],
  list : (Int) -> @js_async.Promise[Array[String]],
) -> @storage.JsAsyncStorageCallbacks {
  @storage.JsAsyncStorageCallbacks::new(
    fn(path, kind) { read(path, kind_to_int(kind)) },
    fn(path, data, kind) { write(path, data, kind_to_int(kind)) },
    fn(path, data, kind) { atomic_write(path, data, kind_to_int(kind)) },
    fn(path, kind) { del(path, kind_to_int(kind)) },
    fn(path, kind) { exists(path, kind_to_int(kind)) },
    fn(kind) { list(kind_to_int(kind)) },
  )
}

///|
pub fn persistent_register_wal_storage(
  instance_id : Int,
  read : (String, Int) -> @js_async.Promise[Bytes],
  write : (String, Bytes, Int) -> @js_async.Promise[Unit],
  atomic_write : (String, Bytes, Int) -> @js_async.Promise[Unit],
  del : (String, Int) -> @js_async.Promise[Unit],
  exists : (String, Int) -> @js_async.Promise[Bool],
  list : (Int) -> @js_async.Promise[Array[String]],
) -> Unit {
  @storage.register_js_async_callbacks(
    wal_callback_name(instance_id),
    make_storage_callbacks(read, write, atomic_write, del, exists, list),
  )
}

///|
pub fn persistent_register_snapshot_storage(
  instance_id : Int,
  read : (String, Int) -> @js_async.Promise[Bytes],
  write : (String, Bytes, Int) -> @js_async.Promise[Unit],
  atomic_write : (String, Bytes, Int) -> @js_async.Promise[Unit],
  del : (String, Int) -> @js_async.Promise[Unit],
  exists : (String, Int) -> @js_async.Promise[Bool],
  list : (Int) -> @js_async.Promise[Array[String]],
) -> Unit {
  @storage.register_js_async_callbacks(
    snapshot_callback_name(instance_id),
    make_storage_callbacks(read, write, atomic_write, del, exists, list),
  )
}

///|
pub fn persistent_init(
  instance_id : Int,
  collection_name : String,
  base_path : String,
  dim : Int,
  capacity : Int,
  metric : String,
  strategy : String,
) -> @js_async.Promise[Unit] {
  @js_async.Promise::from_async(async fn() {
    let wal_storage = @storage.JsAsyncCallbackStorage::new(
      wal_callback_name(instance_id),
    )
    let snapshot_storage = @storage.JsAsyncCallbackStorage::new(
      snapshot_callback_name(instance_id),
    )
    let parsed_metric = parse_metric_name(metric)
    let parsed_strategy = parse_strategy_name(strategy)
    let pdb = @vcdb.PersistentDB::init(
      wal_storage,
      snapshot_storage,
      base_path,
      collection_name,
      dim,
      capacity,
      metric=parsed_metric,
      strategy=parsed_strategy,
    )
    persistent_instances[instance_id] = pdb
  })
}

///|
fn get_persistent_db(
  instance_id : Int,
) -> @vcdb.PersistentDB[
  @storage.JsAsyncCallbackStorage,
  @storage.JsAsyncCallbackStorage,
] raise Error {
  match persistent_instances.get(instance_id) {
    Some(pdb) => pdb
    None =>
      raise @storage.AsyncIOFailed(
        "Persistent DB instance " + instance_id.to_string() + " not initialized",
      )
  }
}

///|
fn try_get_persistent_db(
  instance_id : Int,
) -> @vcdb.PersistentDB[
  @storage.JsAsyncCallbackStorage,
  @storage.JsAsyncCallbackStorage,
]? {
  persistent_instances.get(instance_id)
}

///|
/// Upsert points. Each point is (id_bytes: Bytes, vector, payload_json).
/// id_bytes must be exactly 16 bytes (wire format).
pub fn persistent_upsert(
  instance_id : Int,
  points : Array[(Bytes, Array[Double], String)],
  timestamp_ns : Int64,
) -> @js_async.Promise[Unit] {
  @js_async.Promise::from_async(async fn() {
    let db = get_persistent_db(instance_id)
    let typed_points : Array[(@types.VectorId, Array[Double], @types.Attrs)] = []
    for p in points {
      let (id_bytes, vector, payload_json) = p
      match @types.VectorId::from_wire_bytes(id_bytes) {
        Some(vid) => {
          let attrs = parse_json_to_attrs(payload_json)
          typed_points.push((vid, vector, attrs))
        }
        None =>
          raise @storage.AsyncIOFailed("persistent_upsert: invalid id_bytes")
      }
    }
    db.upsert(typed_points, timestamp_ns)
  })
}

///|
/// Remove a vector. id_bytes must be exactly 16 bytes (wire format).
pub fn persistent_remove(
  instance_id : Int,
  id_bytes : Bytes,
  timestamp_ns : Int64,
) -> @js_async.Promise[Bool] {
  @js_async.Promise::from_async(async fn() {
    let db = get_persistent_db(instance_id)
    match @types.VectorId::from_wire_bytes(id_bytes) {
      Some(vid) => db.remove(vid, timestamp_ns)
      None =>
        raise @storage.AsyncIOFailed("persistent_remove: invalid id_bytes")
    }
  })
}

///|
/// Update attributes. id_bytes must be exactly 16 bytes (wire format).
pub fn persistent_update_attrs(
  instance_id : Int,
  id_bytes : Bytes,
  attrs_json : String,
  timestamp_ns : Int64,
) -> @js_async.Promise[Bool] {
  @js_async.Promise::from_async(async fn() {
    let db = get_persistent_db(instance_id)
    match @types.VectorId::from_wire_bytes(id_bytes) {
      Some(vid) => {
        let attrs = parse_json_to_attrs(attrs_json)
        db.update_attrs(vid, attrs, timestamp_ns)
      }
      None =>
        raise @storage.AsyncIOFailed(
          "persistent_update_attrs: invalid id_bytes",
        )
    }
  })
}

///|
pub fn persistent_checkpoint(instance_id : Int) -> @js_async.Promise[Unit] {
  @js_async.Promise::from_async(async fn() {
    let db = get_persistent_db(instance_id)
    db.checkpoint()
  })
}

///|
pub fn persistent_compact(instance_id : Int) -> @js_async.Promise[Int] {
  @js_async.Promise::from_async(async fn() {
    let db = get_persistent_db(instance_id)
    db.compact()
  })
}

///|
pub fn persistent_destroy(instance_id : Int) -> Unit {
  persistent_instances.remove(instance_id)
  @storage.clear_js_async_callbacks(wal_callback_name(instance_id))
  @storage.clear_js_async_callbacks(snapshot_callback_name(instance_id))
}

// ── Synchronous read operations ──────────────────────────────

///|
/// Search by vector similarity.
/// Returns Array of (id_bytes: Bytes, score: Double, payload_json: String).
/// Each id_bytes is exactly 16 bytes in wire format.
pub fn persistent_search(
  instance_id : Int,
  query : Array[Double],
  k : Int,
  with_payload : Bool,
  filter_json : String,
) -> Array[(Bytes, Double, String)] {
  let db = match try_get_persistent_db(instance_id) {
    Some(db) => db
    None => return []
  }
  let filter = @filter.parse_filter_json(filter_json)
  let hits = db.search(query, k, filter)
  let results : Array[(Bytes, Double, String)] = []
  for hit in hits {
    let payload_json = if with_payload {
      match db.get(hit.id) {
        Some(record) => @codec.attrs_to_json(Some(record.attrs))
        None => ""
      }
    } else {
      ""
    }
    results.push(
      (@types.VectorId::to_wire_bytes(hit.id), hit.score, payload_json),
    )
  }
  results
}

///|
/// Get a single vector and payload.
/// id_bytes must be exactly 16 bytes (wire format).
/// Returns (found: Bool, vector: Array[Double], payload_json: String).
pub fn persistent_get(
  instance_id : Int,
  id_bytes : Bytes,
  with_payload : Bool,
) -> (Bool, Array[Double], String) {
  let db = match try_get_persistent_db(instance_id) {
    Some(db) => db
    None => return (false, [], "")
  }
  match @types.VectorId::from_wire_bytes(id_bytes) {
    Some(vid) =>
      match db.get(vid) {
        Some(record) => {
          let payload = if with_payload {
            @codec.attrs_to_json(Some(record.attrs))
          } else {
            ""
          }
          (true, record.vector, payload)
        }
        None => (false, [], "")
      }
    None => (false, [], "")
  }
}

///|
/// id_bytes must be exactly 16 bytes (wire format).
pub fn persistent_has(instance_id : Int, id_bytes : Bytes) -> Bool {
  match try_get_persistent_db(instance_id) {
    Some(db) =>
      match @types.VectorId::from_wire_bytes(id_bytes) {
        Some(vid) => db.has(vid)
        None => false
      }
    None => false
  }
}

///|
/// Scroll through entries.
/// offset_bytes: 16 bytes (wire format) or empty Bytes to start from beginning.
/// Returns Array of (id_bytes: Bytes, payload_json: String).
pub fn persistent_scroll(
  instance_id : Int,
  offset_bytes : Bytes,
  limit : Int,
  with_payload : Bool,
) -> Array[(Bytes, String)] {
  let db = match try_get_persistent_db(instance_id) {
    Some(db) => db
    None => return []
  }
  let offset_id : @types.VectorId? = if offset_bytes.length() == 16 {
    @types.VectorId::from_wire_bytes(offset_bytes)
  } else {
    None
  }
  let entries = db.scroll(offset=offset_id, limit~)
  entries.map(fn(entry) {
    let (vid, record) = entry
    let payload = if with_payload {
      @codec.attrs_to_json(Some(record.attrs))
    } else {
      ""
    }
    (@types.VectorId::to_wire_bytes(vid), payload)
  })
}

///|
/// Filtered scroll.
/// offset_bytes: 16 bytes (wire format) or empty Bytes to start from beginning.
pub fn persistent_scroll_filtered(
  instance_id : Int,
  filter_json : String,
  offset_bytes : Bytes,
  limit : Int,
  with_payload : Bool,
) -> Array[(Bytes, String)] {
  let db = match try_get_persistent_db(instance_id) {
    Some(db) => db
    None => return []
  }
  let offset_id : @types.VectorId? = if offset_bytes.length() == 16 {
    @types.VectorId::from_wire_bytes(offset_bytes)
  } else {
    None
  }
  let filter = @filter.parse_filter_json(filter_json)
  let entries = db.scroll_filtered(expr=filter, offset=offset_id, limit~)
  entries.map(fn(entry) {
    let (vid, record) = entry
    let payload = if with_payload {
      @codec.attrs_to_json(Some(record.attrs))
    } else {
      ""
    }
    (@types.VectorId::to_wire_bytes(vid), payload)
  })
}

///|
pub fn persistent_count_filtered(
  instance_id : Int,
  filter_json : String,
) -> Int {
  let db = match try_get_persistent_db(instance_id) {
    Some(db) => db
    None => return 0
  }
  let filter = @filter.parse_filter_json(filter_json)
  db.count_filtered(expr=filter)
}

///|
pub fn persistent_db_size(instance_id : Int) -> Int {
  match try_get_persistent_db(instance_id) {
    Some(db) => db.size()
    None => 0
  }
}

///|
pub fn persistent_db_raw_size(instance_id : Int) -> Int {
  match try_get_persistent_db(instance_id) {
    Some(db) => db.raw_size()
    None => 0
  }
}

///|
pub fn persistent_db_dim(instance_id : Int) -> Int {
  match try_get_persistent_db(instance_id) {
    Some(db) => db.dim()
    None => 0
  }
}
