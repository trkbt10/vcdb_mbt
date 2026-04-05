///|
/// PersistentVectorDB — the single entry point for durable vector operations.
///
/// Enforces WAL-before-state ordering:
///   1. Encode WAL record
///   2. Persist WAL to storage (awaited)
///   3. Update VectorDB in-memory state
///   4. Return success to caller
///
/// On crash between 2 and 3: WAL replay restores the operation.
/// On crash before 2: operation was never persisted, caller didn't get success.
///
/// This is the ONLY correct way to perform durable mutations.
/// Read operations (search, get, scroll) go directly to VectorDB.
///
/// Supports dual-backend storage:
///   W — WAL storage (e.g., Durable Object storage)
///   S — Snapshot storage (e.g., R2)
///
/// Target-independent: works on JS, native, and Wasm.

///|
/// Default checkpoint byte threshold: 100KB.
/// Sized to stay well within Durable Object storage per-value limits (128KB).
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
pub struct PersistentVectorDB[W, S] {
  mut db : @vcdb.VectorDB
  wal : @wal.AsyncWalRuntime[W]
  snapshot_storage : S
  base_path : String
  name : String
  checkpoint_threshold : Int
  checkpoint_bytes : Int
}

///|
pub fn[W, S] PersistentVectorDB::new(
  db : @vcdb.VectorDB,
  wal : @wal.AsyncWalRuntime[W],
  snapshot_storage : S,
  base_path : String,
  name : String,
  checkpoint_threshold? : Int = 50,
  checkpoint_bytes? : Int = default_checkpoint_bytes,
) -> PersistentVectorDB[W, S] {
  {
    db,
    wal,
    snapshot_storage,
    base_path,
    name,
    checkpoint_threshold,
    checkpoint_bytes,
  }
}

///|
/// Initialize from storage: load WAL + snapshot, replay, build VectorDB.
///
/// Call sequence:
///   1. Load snapshot from snapshot_storage
///   2. Load WAL from wal_storage into in-memory buffer
///   3. Deserialize snapshot → CoreStore (or create empty)
///   4. Replay WAL records onto CoreStore
///   5. Build VectorDB from CoreStore
pub async fn[W : @storage.AsyncStorage, S : @storage.AsyncStorage] PersistentVectorDB::init(
  wal_storage : W,
  snapshot_storage : S,
  base_path : String,
  name : String,
  dim : Int,
  capacity : Int,
  checkpoint_threshold? : Int = 50,
  checkpoint_bytes? : Int = default_checkpoint_bytes,
) -> PersistentVectorDB[W, S] {
  let wal_path = join_path(base_path, @storage.collection_wal_path(name))
  let wal = @wal.AsyncWalRuntime::new(wal_storage, wal_path)

  // Step 1-2: Load WAL and snapshot
  let wal_data = wal.load()

  let data_path = join_path(base_path, @storage.collection_data_path(name))
  let has_snapshot = @storage.async_exists(snapshot_storage, data_path, @storage.Data)
  let snapshot_data : Bytes? = if has_snapshot {
    Some(@storage.async_read(snapshot_storage, data_path, @storage.Data))
  } else {
    None
  }

  // Step 3-4: Deserialize + replay
  let options : @types.DatabaseOptions = {
    dim,
    metric: @types.Cosine,
    capacity,
    strategy: @types.HNSW(@types.HNSWParams::default()),
  }
  let db = match snapshot_data {
    Some(data) => {
      let existing = @vcdb.VectorDB::deserialize(data)
      let store = existing.store()
      if wal_data.length() > 0 {
        let applied = @wal.replay_wal_data(wal_data, store)
        if applied > 0 {
          @vcdb.VectorDB::from_store(store, options)
        } else {
          existing
        }
      } else {
        existing
      }
    }
    None => {
      if wal_data.length() > 0 {
        let store = @store.CoreStore::new(dim, @types.Cosine, capacity=capacity)
        let _ = @wal.replay_wal_data(wal_data, store)
        @vcdb.VectorDB::from_store(store, options)
      } else {
        @vcdb.VectorDB::new(options)
      }
    }
  }

  PersistentVectorDB::new(
    db,
    wal,
    snapshot_storage,
    base_path,
    name,
    checkpoint_threshold=checkpoint_threshold,
    checkpoint_bytes=checkpoint_bytes,
  )
}

// ── WAL-before-state mutations ────────────────────────────────

///|
/// Upsert points with WAL-before-state guarantee.
///
/// Order:
///   1. Encode WAL records (sync)
///   2. Persist WAL to storage (async, awaited)
///   3. Update VectorDB in-memory (sync)
///   4. Auto-checkpoint if thresholds exceeded
pub async fn[W : @storage.AsyncStorage, S : @storage.AsyncStorage] PersistentVectorDB::upsert(
  self : PersistentVectorDB[W, S],
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
    let _ = self.db.upsert(id, vector, attrs)
  }

  // Step 4: Auto-checkpoint
  if self.should_checkpoint() {
    self.checkpoint()
  }
}

///|
/// Remove a vector with WAL-before-state guarantee.
pub async fn[W : @storage.AsyncStorage, S : @storage.AsyncStorage] PersistentVectorDB::remove(
  self : PersistentVectorDB[W, S],
  id : @types.VectorId,
  timestamp_ns : Int64,
) -> Bool {
  if !self.db.has(id) {
    return false
  }

  // Step 1: Encode WAL record
  let records = [@wal.WalRecord::remove(id, timestamp=timestamp_ns)]

  // Step 2: Persist WAL
  self.wal.append(records)

  // Step 3: Update in-memory state
  let _ = self.db.remove(id)

  // Step 4: Auto-checkpoint
  if self.should_checkpoint() {
    self.checkpoint()
  }
  true
}

///|
/// Update attributes with WAL-before-state guarantee.
pub async fn[W : @storage.AsyncStorage, S : @storage.AsyncStorage] PersistentVectorDB::update_attrs(
  self : PersistentVectorDB[W, S],
  id : @types.VectorId,
  attrs : @types.Attrs,
  timestamp_ns : Int64,
) -> Bool {
  if !self.db.has(id) {
    return false
  }

  // Step 1: Encode WAL record
  let records = [@wal.WalRecord::set_attrs(id, attrs, timestamp=timestamp_ns)]

  // Step 2: Persist WAL
  self.wal.append(records)

  // Step 3: Update in-memory state
  let _ = self.db.update_attrs(id, attrs)

  if self.should_checkpoint() {
    self.checkpoint()
  }
  true
}

// ── Read operations (no WAL needed) ───────────────────────────

///|
/// Search by vector similarity.
pub fn[W, S] PersistentVectorDB::search(
  self : PersistentVectorDB[W, S],
  query : Array[Double],
  k : Int,
  filter : @filter.FilterExpr?,
) -> Array[@types.SearchHit] {
  self.db.search_with_expr(query, k, filter, None, @filter.Auto)
}

///|
/// Get a single vector by ID.
pub fn[W, S] PersistentVectorDB::get(
  self : PersistentVectorDB[W, S],
  id : @types.VectorId,
) -> @types.VectorRecord? {
  self.db.get(id)
}

///|
/// Check if a vector exists.
pub fn[W, S] PersistentVectorDB::has(
  self : PersistentVectorDB[W, S],
  id : @types.VectorId,
) -> Bool {
  self.db.has(id)
}

///|
/// Scroll through vectors in ascending ID order.
pub fn[W, S] PersistentVectorDB::scroll(
  self : PersistentVectorDB[W, S],
  offset? : Int64? = None,
  limit? : Int = 10,
) -> Array[(@types.VectorId, @types.VectorRecord)] {
  self.db.scroll(offset=offset, limit=limit)
}

///|
/// Scroll with filter expression.
pub fn[W, S] PersistentVectorDB::scroll_filtered(
  self : PersistentVectorDB[W, S],
  expr? : @filter.FilterExpr? = None,
  offset? : Int64? = None,
  limit? : Int = 10,
) -> Array[(@types.VectorId, @types.VectorRecord)] {
  self.db.scroll_filtered(expr=expr, offset=offset, limit=limit)
}

///|
/// Count vectors matching filter.
pub fn[W, S] PersistentVectorDB::count_filtered(
  self : PersistentVectorDB[W, S],
  expr? : @filter.FilterExpr? = None,
) -> Int {
  self.db.count_filtered(expr=expr)
}

///|
/// Database size (excluding tombstones).
pub fn[W, S] PersistentVectorDB::size(
  self : PersistentVectorDB[W, S],
) -> Int {
  self.db.size()
}

///|
/// Raw size including tombstones.
pub fn[W, S] PersistentVectorDB::raw_size(
  self : PersistentVectorDB[W, S],
) -> Int {
  self.db.raw_size()
}

///|
/// Vector dimension.
pub fn[W, S] PersistentVectorDB::dim(
  self : PersistentVectorDB[W, S],
) -> Int {
  self.db.dim()
}

///|
/// Serialize current state as snapshot.
pub fn[W, S] PersistentVectorDB::serialize_snapshot(
  self : PersistentVectorDB[W, S],
) -> Bytes {
  self.db.serialize()
}

///|
/// Access the underlying CoreStore (for advanced use).
pub fn[W, S] PersistentVectorDB::store(
  self : PersistentVectorDB[W, S],
) -> @store.CoreStore {
  self.db.store()
}

///|
/// Access the underlying VectorDB for direct read operations.
/// Gateway uses this for search, get, scroll — all read-only.
pub fn[W, S] PersistentVectorDB::get_underlying_db(
  self : PersistentVectorDB[W, S],
) -> @vcdb.VectorDB {
  self.db
}

// ── Checkpoint & lifecycle ────────────────────────────────────

///|
fn[W, S] PersistentVectorDB::should_checkpoint(
  self : PersistentVectorDB[W, S],
) -> Bool {
  self.wal.record_count() >= self.checkpoint_threshold ||
  (self.checkpoint_bytes > 0 && self.wal.byte_size() >= self.checkpoint_bytes)
}

///|
/// Checkpoint: snapshot to snapshot_storage, then truncate WAL.
/// Crash safe: snapshot-first, WAL truncate second.
pub async fn[W : @storage.AsyncStorage, S : @storage.AsyncStorage] PersistentVectorDB::checkpoint(
  self : PersistentVectorDB[W, S],
) -> Unit {
  // Step 1: Write snapshot (durable)
  let data = self.db.serialize()
  let data_path = join_path(
    self.base_path,
    @storage.collection_data_path(self.name),
  )
  @storage.async_atomic_write(self.snapshot_storage, data_path, data, @storage.Data)

  // Step 2: Truncate WAL (only after snapshot is confirmed durable)
  self.wal.truncate()
}

///|
/// Compact HNSW index (removes tombstones). Returns removed count.
/// Triggers checkpoint after compaction.
pub async fn[W : @storage.AsyncStorage, S : @storage.AsyncStorage] PersistentVectorDB::compact(
  self : PersistentVectorDB[W, S],
) -> Int {
  let (new_db, removed) = self.db.compact()
  if removed > 0 {
    self.db = new_db
    self.checkpoint()
  }
  removed
}

///|
/// Current WAL record count (for diagnostics).
pub fn[W, S] PersistentVectorDB::wal_record_count(
  self : PersistentVectorDB[W, S],
) -> Int {
  self.wal.record_count()
}

///|
/// Current WAL byte size (for diagnostics).
pub fn[W, S] PersistentVectorDB::wal_byte_size(
  self : PersistentVectorDB[W, S],
) -> Int {
  self.wal.byte_size()
}
