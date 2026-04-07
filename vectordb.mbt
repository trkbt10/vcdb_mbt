///|
/// PersistentDB[W, S] — The single source of truth for all vector database operations.
///
/// All reads and writes go through this type. Persistence is controlled
/// by the storage backends injected via type parameters:
///   W — WAL storage backend (must implement AsyncStorage)
///   S — Snapshot storage backend (must implement AsyncStorage)
///
/// For in-memory use (testing, ephemeral), inject MemoryStorage for both W and S.
/// For durable use, inject real storage backends (e.g., JsAsyncCallbackStorage,
/// NativeFileStorage).
///
/// Write operations enforce WAL-before-state ordering:
///   1. Encode WAL record (sync)
///   2. Persist WAL to storage (async, awaited)
///   3. Update in-memory engine state (sync)
///   4. Auto-checkpoint if thresholds exceeded
///
/// Read operations are synchronous — they access the in-memory engine directly.

///|
/// Default checkpoint byte threshold: 100KB.
let default_checkpoint_bytes : Int = 100 * 1024

///|
fn join_path(base : String, path : String) -> String {
  if base.length() == 0 {
    path
  } else {
    base + "/" + path
  }
}

///|
pub struct PersistentDB[W, S] {
  mut engine : VectorDB
  wal : @wal.AsyncWalRuntime[W]
  snapshot_storage : S
  base_path : String
  name : String
  checkpoint_threshold : Int
  checkpoint_bytes : Int
}

///|
/// Internal constructor — wraps an existing engine with WAL and storage.
fn[W, S] PersistentDB::wrap(
  engine : VectorDB,
  wal : @wal.AsyncWalRuntime[W],
  snapshot_storage : S,
  base_path : String,
  name : String,
  checkpoint_threshold~ : Int = 50,
  checkpoint_bytes~ : Int = default_checkpoint_bytes,
) -> PersistentDB[W, S] {
  {
    engine,
    wal,
    snapshot_storage,
    base_path,
    name,
    checkpoint_threshold,
    checkpoint_bytes,
  }
}

///|
/// Initialize from storage: load WAL + snapshot, replay, build engine.
///
/// Call sequence:
///   1. Load snapshot from snapshot_storage
///   2. Load WAL from wal_storage into in-memory buffer
///   3. Deserialize snapshot -> CoreStore (or create empty)
///   4. Replay WAL records onto CoreStore
///   5. Build VectorDB from CoreStore
pub async fn[W : @storage.AsyncStorage, S : @storage.AsyncStorage] PersistentDB::init(
  wal_storage : W,
  snapshot_storage : S,
  base_path : String,
  name : String,
  dim : Int,
  capacity : Int,
  metric? : @types.Metric = @types.Cosine,
  strategy? : @types.Strategy = @types.HNSW(@types.HNSWParams::default()),
  checkpoint_threshold? : Int = 50,
  checkpoint_bytes? : Int = default_checkpoint_bytes,
) -> PersistentDB[W, S] {
  let wal_path = join_path(base_path, @storage.collection_wal_path(name))
  let wal = @wal.AsyncWalRuntime::new(wal_storage, wal_path)

  // Step 1-2: Load WAL and snapshot
  let wal_data = wal.load()

  let data_path = join_path(base_path, @storage.collection_data_path(name))
  let has_snapshot = @storage.async_exists(
    snapshot_storage,
    data_path,
    @storage.Data,
  )
  let snapshot_data : Bytes? = if has_snapshot {
    Some(@storage.async_read(snapshot_storage, data_path, @storage.Data))
  } else {
    None
  }

  // Step 3-4: Deserialize + replay
  let options : @types.DatabaseOptions = { dim, metric, capacity, strategy }
  let engine = match snapshot_data {
    Some(data) => {
      let existing = VectorDB::deserialize(data)
      let store = existing.store
      if wal_data.length() > 0 {
        let applied = @wal.replay_wal_data(wal_data, store)
        if applied > 0 {
          VectorDB::from_store(store, options)
        } else {
          existing
        }
      } else {
        existing
      }
    }
    None =>
      if wal_data.length() > 0 {
        let store = @store.CoreStore::new(dim, metric, capacity~)
        let _ = @wal.replay_wal_data(wal_data, store)
        VectorDB::from_store(store, options)
      } else {
        VectorDB::new(options)
      }
  }

  PersistentDB::wrap(
    engine,
    wal,
    snapshot_storage,
    base_path,
    name,
    checkpoint_threshold~,
    checkpoint_bytes~,
  )
}

///|
/// Create an in-memory PersistentDB (no durable persistence).
///
/// Uses MemoryStorage for both WAL and snapshot backends.
/// Since MemoryStorage resolves all I/O synchronously, initialization
/// completes immediately — but the function is async to maintain a
/// uniform interface.
pub async fn PersistentDB::in_memory(
  dim : Int,
  metric? : @types.Metric = @types.Cosine,
  strategy? : @types.Strategy = @types.HNSW(@types.HNSWParams::default()),
  capacity? : Int = 1024,
) -> PersistentDB[@storage.MemoryStorage, @storage.MemoryStorage] {
  let storage = @storage.MemoryStorage::new()
  PersistentDB::init(
    storage,
    storage,
    "",
    "",
    dim,
    capacity,
    metric~,
    strategy~,
    checkpoint_threshold=2147483647,
    checkpoint_bytes=0,
  )
}

///|
/// Create an in-memory PersistentDB with HNSW strategy.
pub async fn PersistentDB::in_memory_hnsw(
  dim : Int,
  metric? : @types.Metric = @types.Cosine,
) -> PersistentDB[@storage.MemoryStorage, @storage.MemoryStorage] {
  PersistentDB::in_memory(
    dim,
    metric~,
    strategy=@types.HNSW(@types.HNSWParams::default()),
  )
}

///|
/// Create an in-memory PersistentDB with IVF strategy.
pub async fn PersistentDB::in_memory_ivf(
  dim : Int,
  metric? : @types.Metric = @types.Cosine,
) -> PersistentDB[@storage.MemoryStorage, @storage.MemoryStorage] {
  PersistentDB::in_memory(
    dim,
    metric~,
    strategy=@types.IVF(@types.IVFParams::default()),
  )
}

///|
/// Create an in-memory PersistentDB with Bruteforce strategy.
pub async fn PersistentDB::in_memory_bruteforce(
  dim : Int,
  metric? : @types.Metric = @types.Cosine,
) -> PersistentDB[@storage.MemoryStorage, @storage.MemoryStorage] {
  PersistentDB::in_memory(dim, metric~, strategy=@types.Bruteforce)
}

// ── WAL-before-state mutations ────────────────────────────────

///|
/// Upsert points with WAL-before-state guarantee.
///
/// Order:
///   1. Encode WAL records (sync)
///   2. Persist WAL to storage (async, awaited)
///   3. Update engine in-memory (sync)
///   4. Auto-checkpoint if thresholds exceeded
pub async fn[W : @storage.AsyncStorage, S : @storage.AsyncStorage] PersistentDB::upsert(
  self : PersistentDB[W, S],
  points : Array[(@types.VectorId, Array[Double], @types.Attrs)],
  timestamp_ns : Int64,
) -> Unit {
  // Step 1: Encode WAL records
  let records : Array[@wal.WalRecord] = points.map(fn(p) {
    let (id, vector, attrs) = p
    @wal.WalRecord::upsert(id, vector, attrs, timestamp=timestamp_ns)
  })

  // Step 2: Persist WAL (async I/O — the write-ahead guarantee)
  self.wal.append(records)

  // Step 3: Update in-memory state (only after WAL is durable)
  for p in points {
    let (id, vector, attrs) = p
    let _ = self.engine.upsert(id, vector, attrs)
  }

  // Step 4: Auto-checkpoint
  if self.should_checkpoint() {
    self.checkpoint()
  }
}

///|
/// Add a single vector. Fails if the ID already exists (not tombstoned).
///
/// This is the WAL-backed equivalent of VectorDB::add.
pub async fn[W : @storage.AsyncStorage, S : @storage.AsyncStorage] PersistentDB::add(
  self : PersistentDB[W, S],
  id : @types.VectorId,
  vector : Array[Double],
  attrs : @types.Attrs,
  timestamp_ns : Int64,
) -> Unit {
  // Step 1: Encode WAL record (upsert in WAL — add semantics enforced in-memory)
  let records = [
    @wal.WalRecord::upsert(id, vector, attrs, timestamp=timestamp_ns),
  ]

  // Step 2: Persist WAL
  self.wal.append(records)

  // Step 3: Update in-memory state
  self.engine.add(id, vector, attrs)

  // Step 4: Auto-checkpoint
  if self.should_checkpoint() {
    self.checkpoint()
  }
}

///|
/// Remove a vector with WAL-before-state guarantee.
pub async fn[W : @storage.AsyncStorage, S : @storage.AsyncStorage] PersistentDB::remove(
  self : PersistentDB[W, S],
  id : @types.VectorId,
  timestamp_ns : Int64,
) -> Bool {
  if !self.engine.has(id) {
    return false
  }

  // Step 1: Encode WAL record
  let records = [@wal.WalRecord::remove(id, timestamp=timestamp_ns)]

  // Step 2: Persist WAL
  self.wal.append(records)

  // Step 3: Update in-memory state
  let _ = self.engine.remove(id)

  // Step 4: Auto-checkpoint
  if self.should_checkpoint() {
    self.checkpoint()
  }
  true
}

///|
/// Update attributes with WAL-before-state guarantee.
pub async fn[W : @storage.AsyncStorage, S : @storage.AsyncStorage] PersistentDB::update_attrs(
  self : PersistentDB[W, S],
  id : @types.VectorId,
  attrs : @types.Attrs,
  timestamp_ns : Int64,
) -> Bool {
  if !self.engine.has(id) {
    return false
  }

  // Step 1: Encode WAL record
  let records = [@wal.WalRecord::set_attrs(id, attrs, timestamp=timestamp_ns)]

  // Step 2: Persist WAL
  self.wal.append(records)

  // Step 3: Update in-memory state
  let _ = self.engine.update_attrs(id, attrs)

  if self.should_checkpoint() {
    self.checkpoint()
  }
  true
}

// ── Read operations (no WAL needed, synchronous) ─────────────

///|
/// Search by vector similarity with optional filter expression.
pub fn[W, S] PersistentDB::search(
  self : PersistentDB[W, S],
  query : Array[Double],
  k : Int,
  filter : @filter.FilterExpr?,
) -> Array[@types.SearchHit] {
  self.engine.search_with_expr(query, k, filter, None, @filter.Auto)
}

///|
/// Search with explicit filter expression, index override, and strategy.
pub fn[W, S] PersistentDB::search_with_expr(
  self : PersistentDB[W, S],
  query : Array[Double],
  k : Int,
  expr : @filter.FilterExpr?,
  attr_index : @attr.BPTreeAttrIndex?,
  strategy : @filter.FilterStrategy,
) -> Array[@types.SearchHit] {
  self.engine.search_with_expr(query, k, expr, attr_index, strategy)
}

///|
/// Search by vector similarity with callback filter.
pub fn[W, S] PersistentDB::search_with_filter(
  self : PersistentDB[W, S],
  query : Array[Double],
  k : Int,
  filter : ((@types.VectorId, @types.Attrs) -> Bool)?,
) -> Array[@types.SearchHit] {
  self.engine.search(query, k, filter)
}

///|
/// Find the single best match.
pub fn[W, S] PersistentDB::find(
  self : PersistentDB[W, S],
  query : Array[Double],
  filter : ((@types.VectorId, @types.Attrs) -> Bool)?,
) -> @types.SearchHit? {
  self.engine.find(query, filter)
}

///|
/// Get a single vector by ID.
pub fn[W, S] PersistentDB::get(
  self : PersistentDB[W, S],
  id : @types.VectorId,
) -> @types.VectorRecord? {
  self.engine.get(id)
}

///|
/// Check if a vector exists.
pub fn[W, S] PersistentDB::has(
  self : PersistentDB[W, S],
  id : @types.VectorId,
) -> Bool {
  self.engine.has(id)
}

///|
/// Scroll through vectors in ascending ID order.
pub fn[W, S] PersistentDB::scroll(
  self : PersistentDB[W, S],
  offset? : Int64? = None,
  limit? : Int = 10,
) -> Array[(@types.VectorId, @types.VectorRecord)] {
  self.engine.scroll(offset~, limit~)
}

///|
/// Scroll with filter expression.
pub fn[W, S] PersistentDB::scroll_filtered(
  self : PersistentDB[W, S],
  expr? : @filter.FilterExpr? = None,
  offset? : Int64? = None,
  limit? : Int = 10,
) -> Array[(@types.VectorId, @types.VectorRecord)] {
  self.engine.scroll_filtered(expr~, offset~, limit~)
}

///|
/// Count vectors matching filter.
pub fn[W, S] PersistentDB::count_filtered(
  self : PersistentDB[W, S],
  expr? : @filter.FilterExpr? = None,
) -> Int {
  self.engine.count_filtered(expr~)
}

///|
/// Database size (excluding tombstones).
pub fn[W, S] PersistentDB::size(self : PersistentDB[W, S]) -> Int {
  self.engine.size()
}

///|
/// Raw size including tombstones.
pub fn[W, S] PersistentDB::raw_size(self : PersistentDB[W, S]) -> Int {
  self.engine.raw_size()
}

///|
/// Vector dimension.
pub fn[W, S] PersistentDB::dim(self : PersistentDB[W, S]) -> Int {
  self.engine.dim()
}

///|
/// Similarity metric.
pub fn[W, S] PersistentDB::metric(self : PersistentDB[W, S]) -> @types.Metric {
  self.engine.metric()
}

///|
/// ANN strategy.
pub fn[W, S] PersistentDB::strategy(self : PersistentDB[W, S]) -> @types.Strategy {
  self.engine.strategy()
}

///|
/// Access the underlying CoreStore (for advanced/distributed use).
pub fn[W, S] PersistentDB::store(self : PersistentDB[W, S]) -> @store.CoreStore {
  self.engine.store
}

///|
/// Train IVF index (IVF strategy only).
pub fn[W, S] PersistentDB::train(
  self : PersistentDB[W, S],
  iterations? : Int = 10,
) -> Unit {
  self.engine.train(iterations~)
}

// ── Serialization ────────────────────────────────────────────

///|
/// Serialize current state as snapshot bytes.
pub fn[W, S] PersistentDB::serialize_snapshot(self : PersistentDB[W, S]) -> Bytes {
  self.engine.serialize()
}

///|
/// Deserialize from snapshot bytes, wrapping with in-memory storage.
///
/// Used for loading a serialized database without persistence backends.
pub fn PersistentDB::deserialize(
  data : Bytes,
) -> PersistentDB[@storage.MemoryStorage, @storage.MemoryStorage] {
  let engine = VectorDB::deserialize(data)
  let storage = @storage.MemoryStorage::new()
  let wal = @wal.AsyncWalRuntime::new(storage, "")
  PersistentDB::wrap(
    engine,
    wal,
    storage,
    "",
    "",
    checkpoint_threshold=2147483647,
    checkpoint_bytes=0,
  )
}

///|
/// Load from snapshot bytes with explicit storage backends.
///
/// Used by gateway's load_collection to restore from a serialized snapshot
/// and attach real storage backends for subsequent WAL operations.
pub fn[S] PersistentDB::from_snapshot(
  data : Bytes,
  storage : S,
  base_path : String,
  name : String,
  checkpoint_threshold? : Int = 50,
  checkpoint_bytes? : Int = default_checkpoint_bytes,
) -> PersistentDB[S, S] {
  let engine = VectorDB::deserialize(data)
  let wal_path = join_path(base_path, @storage.collection_wal_path(name))
  let wal = @wal.AsyncWalRuntime::new(storage, wal_path)
  PersistentDB::wrap(
    engine,
    wal,
    storage,
    base_path,
    name,
    checkpoint_threshold~,
    checkpoint_bytes~,
  )
}

// ── Checkpoint & lifecycle ────────────────────────────────────

///|
fn[W, S] PersistentDB::should_checkpoint(self : PersistentDB[W, S]) -> Bool {
  self.wal.record_count() >= self.checkpoint_threshold ||
  (self.checkpoint_bytes > 0 && self.wal.byte_size() >= self.checkpoint_bytes)
}

///|
/// Checkpoint: snapshot to snapshot_storage, then truncate WAL.
/// Crash safe: snapshot-first, WAL truncate second.
pub async fn[W : @storage.AsyncStorage, S : @storage.AsyncStorage] PersistentDB::checkpoint(
  self : PersistentDB[W, S],
) -> Unit {
  // Step 1: Write snapshot (durable)
  let data = self.engine.serialize()
  let data_path = join_path(
    self.base_path,
    @storage.collection_data_path(self.name),
  )
  @storage.async_atomic_write(
    self.snapshot_storage,
    data_path,
    data,
    @storage.Data,
  )

  // Step 2: Truncate WAL (only after snapshot is confirmed durable)
  self.wal.truncate()
}

///|
/// Compact HNSW index (removes tombstones). Returns removed count.
/// Triggers checkpoint after compaction.
pub async fn[W : @storage.AsyncStorage, S : @storage.AsyncStorage] PersistentDB::compact(
  self : PersistentDB[W, S],
) -> Int {
  let (new_engine, removed) = self.engine.compact()
  if removed > 0 {
    self.engine = new_engine
    self.checkpoint()
  }
  removed
}

///|
/// Current WAL record count (for diagnostics).
pub fn[W, S] PersistentDB::wal_record_count(self : PersistentDB[W, S]) -> Int {
  self.wal.record_count()
}

///|
/// Current WAL byte size (for diagnostics).
pub fn[W, S] PersistentDB::wal_byte_size(self : PersistentDB[W, S]) -> Int {
  self.wal.byte_size()
}
