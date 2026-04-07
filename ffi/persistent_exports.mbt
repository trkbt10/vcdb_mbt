///|
/// Persistent FFI exports — WAL-before-state durable operations.
///
/// Unlike async_exports.mbt (which returns WAL bytes for JS to persist),
/// these functions handle persistence internally:
///   1. WAL is written to wal_storage (durable)
///   2. VectorDB in-memory state is updated
///   3. Checkpoint is triggered automatically when thresholds are exceeded
///
/// JS callers must:
///   1. Register async storage callbacks via persistent_register_wal_storage /
///      persistent_register_snapshot_storage
///   2. Call persistent_init to create an instance
///   3. Use persistent_upsert etc. — each returns a Promise
///
/// Read operations (search, get, scroll) are synchronous — no Promise needed.
///
/// Mutation operations return @js_async.Promise because they involve async I/O.

///|
/// Instance storage for persistent mode.
let persistent_instances : @hashmap.HashMap[
  Int,
  @vcdb.PersistentDB[
    @storage.JsAsyncCallbackStorage,
    @storage.JsAsyncCallbackStorage,
  ],
] = @hashmap.new()

// ── Callback name derivation (SoT) ──────────────────────────
//
// All callback names are derived from instance_id via these two
// functions. register, init, and destroy MUST use these — never
// inline the prefix strings.

///|
fn wal_callback_name(instance_id : Int) -> String {
  "wal-" + instance_id.to_string()
}

///|
fn snapshot_callback_name(instance_id : Int) -> String {
  "snapshot-" + instance_id.to_string()
}

///|
fn parse_metric_name(metric : String) -> @types.Metric {
  match metric {
    "cosine" | "Cosine" => @types.Cosine
    "l2" | "L2" => @types.L2
    "dot" | "Dot" => @types.Dot
    _ => abort("Unsupported metric for persistent_init: " + metric)
  }
}

///|
fn parse_strategy_name(strategy : String) -> @types.Strategy {
  match strategy {
    "hnsw" | "HNSW" => @types.HNSW(@types.HNSWParams::default())
    "ivf" | "IVF" => @types.IVF(@types.IVFParams::default())
    "bruteforce" | "Bruteforce" => @types.Bruteforce
    _ => abort("Unsupported strategy for persistent_init: " + strategy)
  }
}

///|
/// Create JsAsyncStorageCallbacks from raw JS callback functions.
/// Adapts the Int-based kind parameter (JS side) to StorageKind (MoonBit side).
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
/// Register WAL storage callbacks for a specific instance.
/// Must be called BEFORE persistent_init.
///
/// Parameters:
///   instance_id — stable ID for this instance (e.g., FNV-1a hash of DO ID)
///   read, write, atomic_write, del, exists, list — JS functions returning Promises
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
/// Register snapshot storage callbacks for a specific instance.
/// Must be called BEFORE persistent_init.
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
/// Initialize a persistent VectorDB instance.
/// Loads WAL + snapshot from registered storage, replays, builds VectorDB.
///
/// Parameters:
///   instance_id — stable ID (same as used in register_*_storage calls)
///   collection_name — determines WAL/snapshot file names
///     (e.g., "questions" → "questions.vwal" + "questions.data.bin")
///   base_path — optional prefix path (empty string for root)
///   dim — vector dimension
///   capacity — initial capacity hint
///
/// Returns a Promise that resolves when initialization is complete.
/// The instance is then available for persistent_upsert, persistent_search, etc.
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
    let pdb = @vcdb.PersistentDB::init(
      wal_storage,
      snapshot_storage,
      base_path,
      collection_name,
      dim,
      capacity,
      metric=parse_metric_name(metric),
      strategy=parse_strategy_name(strategy),
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
] {
  match persistent_instances.get(instance_id) {
    Some(pdb) => pdb
    None =>
      abort(
        "Persistent DB instance " + instance_id.to_string() + " not initialized",
      )
  }
}

///|
/// Upsert points with WAL-before-state guarantee.
/// Each point is (id_hi, id_lo, vector, payload_json).
/// Returns a Promise that resolves when WAL is durable and state is updated.
pub fn persistent_upsert(
  instance_id : Int,
  points : Array[(Int, Int, Array[Double], String)],
  timestamp_ns : Int64,
) -> @js_async.Promise[Unit] {
  @js_async.Promise::from_async(async fn() {
    let db = get_persistent_db(instance_id)
    let typed_points : Array[(@types.VectorId, Array[Double], @types.Attrs)] = points.map(fn(
        p,
      ) {
        let (id_hi, id_lo, vector, payload_json) = p
        let vid = vid_from_pair(id_hi, id_lo)
        let attrs = parse_json_to_attrs(payload_json)
        (vid, vector, attrs)
      },
    )
    db.upsert(typed_points, timestamp_ns)
  })
}

///|
/// Remove a vector with WAL-before-state guarantee.
/// Returns a Promise that resolves to true if the vector was found and removed.
pub fn persistent_remove(
  instance_id : Int,
  id_hi : Int,
  id_lo : Int,
  timestamp_ns : Int64,
) -> @js_async.Promise[Bool] {
  @js_async.Promise::from_async(async fn() {
    let db = get_persistent_db(instance_id)
    db.remove(vid_from_pair(id_hi, id_lo), timestamp_ns)
  })
}

///|
/// Update attributes with WAL-before-state guarantee.
pub fn persistent_update_attrs(
  instance_id : Int,
  id_hi : Int,
  id_lo : Int,
  attrs_json : String,
  timestamp_ns : Int64,
) -> @js_async.Promise[Bool] {
  @js_async.Promise::from_async(async fn() {
    let db = get_persistent_db(instance_id)
    let attrs = parse_json_to_attrs(attrs_json)
    db.update_attrs(vid_from_pair(id_hi, id_lo), attrs, timestamp_ns)
  })
}

///|
/// Force a checkpoint (snapshot + WAL truncate).
pub fn persistent_checkpoint(instance_id : Int) -> @js_async.Promise[Unit] {
  @js_async.Promise::from_async(async fn() {
    let db = get_persistent_db(instance_id)
    db.checkpoint()
  })
}

///|
/// Compact HNSW index. Returns removed count.
pub fn persistent_compact(instance_id : Int) -> @js_async.Promise[Int] {
  @js_async.Promise::from_async(async fn() {
    let db = get_persistent_db(instance_id)
    db.compact()
  })
}

///|
/// Destroy a persistent instance and clear its storage callbacks.
pub fn persistent_destroy(instance_id : Int) -> Unit {
  persistent_instances.remove(instance_id)
  @storage.clear_js_async_callbacks(wal_callback_name(instance_id))
  @storage.clear_js_async_callbacks(snapshot_callback_name(instance_id))
}

// ── Synchronous read operations (no Promise needed) ──────────

///|
/// Search by vector similarity.
pub fn persistent_search(
  instance_id : Int,
  query : Array[Double],
  k : Int,
  with_payload : Bool,
  filter_json : String,
) -> Array[(Int, Int, Double, String)] {
  let db = get_persistent_db(instance_id)
  let filter = @filter.parse_filter_json(filter_json)
  let hits = db.search(query, k, filter)
  let results : Array[(Int, Int, Double, String)] = []
  for hit in hits {
    let payload_json = if with_payload {
      match db.get(hit.id) {
        Some(record) => @codec.attrs_to_json(Some(record.attrs))
        None => ""
      }
    } else {
      ""
    }
    let (hi, lo) = vid_to_pair(hit.id)
    results.push((hi, lo, hit.score, payload_json))
  }
  results
}

///|
/// Get a single vector and payload.
pub fn persistent_get(
  instance_id : Int,
  id_hi : Int,
  id_lo : Int,
  with_payload : Bool,
) -> (Bool, Array[Double], String) {
  let db = get_persistent_db(instance_id)
  let vid = vid_from_pair(id_hi, id_lo)
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
}

///|
pub fn persistent_has(instance_id : Int, id_hi : Int, id_lo : Int) -> Bool {
  get_persistent_db(instance_id).has(vid_from_pair(id_hi, id_lo))
}

///|
pub fn persistent_scroll(
  instance_id : Int,
  offset_hi : Int,
  offset_lo : Int,
  has_offset : Bool,
  limit : Int,
  with_payload : Bool,
) -> Array[(Int, Int, String)] {
  let db = get_persistent_db(instance_id)
  let offset_i64 : Int64? = if has_offset {
    Some(vid_from_pair(offset_hi, offset_lo).to_int64())
  } else {
    None
  }
  let entries = db.scroll(offset=offset_i64, limit~)
  let results : Array[(Int, Int, String)] = []
  for entry in entries {
    let (vid, record) = entry
    let payload = if with_payload {
      @codec.attrs_to_json(Some(record.attrs))
    } else {
      ""
    }
    let (hi, lo) = vid_to_pair(vid)
    results.push((hi, lo, payload))
  }
  results
}

///|
pub fn persistent_scroll_filtered(
  instance_id : Int,
  filter_json : String,
  offset_hi : Int,
  offset_lo : Int,
  has_offset : Bool,
  limit : Int,
  with_payload : Bool,
) -> Array[(Int, Int, String)] {
  let db = get_persistent_db(instance_id)
  let offset_i64 : Int64? = if has_offset {
    Some(vid_from_pair(offset_hi, offset_lo).to_int64())
  } else {
    None
  }
  let filter = @filter.parse_filter_json(filter_json)
  let entries = db.scroll_filtered(expr=filter, offset=offset_i64, limit~)
  let results : Array[(Int, Int, String)] = []
  for entry in entries {
    let (vid, record) = entry
    let payload = if with_payload {
      @codec.attrs_to_json(Some(record.attrs))
    } else {
      ""
    }
    let (hi, lo) = vid_to_pair(vid)
    results.push((hi, lo, payload))
  }
  results
}

///|
pub fn persistent_count_filtered(
  instance_id : Int,
  filter_json : String,
) -> Int {
  let db = get_persistent_db(instance_id)
  let filter = @filter.parse_filter_json(filter_json)
  db.count_filtered(expr=filter)
}

///|
pub fn persistent_db_size(instance_id : Int) -> Int {
  get_persistent_db(instance_id).size()
}

///|
pub fn persistent_db_raw_size(instance_id : Int) -> Int {
  get_persistent_db(instance_id).raw_size()
}

///|
pub fn persistent_db_dim(instance_id : Int) -> Int {
  get_persistent_db(instance_id).dim()
}
