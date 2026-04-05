///|
/// Async WAL Runtime — in-memory buffered, awaits storage on write.
///
/// Maintains an in-memory WAL buffer:
///   - load() reads WAL from storage into the buffer (once)
///   - append() merges in-memory then writes (no read needed)
///   - truncate() resets the buffer and writes empty header
///
/// Uses target-independent AsyncStorage trait (via %async.suspend).
/// Works on JS, native, and Wasm targets.

///|
pub struct AsyncWalRuntime[S] {
  storage : S
  path : String
  kind : @storage.StorageKind
  /// In-memory WAL buffer. Empty until load() is called.
  mut data : Bytes
  /// Number of records appended since last truncate.
  mut record_count : Int
  /// Whether load() has been called.
  mut loaded : Bool
}

///|
pub fn[S] AsyncWalRuntime::new(
  storage : S,
  path : String,
  kind? : @storage.StorageKind = Data,
) -> AsyncWalRuntime[S] {
  { storage, path, kind, data: Bytes::new(0), record_count: 0, loaded: false }
}

///|
/// Load WAL data from storage into the in-memory buffer.
/// Must be called once before append/truncate. Idempotent.
/// Returns the WAL data bytes (for callers that need it, e.g., replay).
pub async fn[S : @storage.AsyncStorage] AsyncWalRuntime::load(
  self : AsyncWalRuntime[S],
) -> Bytes {
  if self.loaded {
    return self.data
  }
  let file_exists = @storage.async_exists(self.storage, self.path, self.kind)
  if file_exists {
    self.data = @storage.async_read(self.storage, self.path, self.kind)
    // Count existing records so record_count is accurate after recovery
    self.record_count = decode_wal_records(self.data).length()
  }
  self.loaded = true
  self.data
}

///|
/// Append records to the WAL.
/// Merges in-memory (no read from storage), then writes to storage.
/// Delegates merge logic to format.mbt's merge_wal (the SoT).
pub async fn[S : @storage.AsyncStorage] AsyncWalRuntime::append(
  self : AsyncWalRuntime[S],
  records : Array[WalRecord],
) -> Unit {
  if records.is_empty() {
    return
  }
  let new_segment = encode_wal_segment(records)
  // Synchronous in-memory merge
  self.data = merge_wal(self.data, new_segment)
  self.record_count = self.record_count + records.length()
  // Persist to storage
  @storage.async_atomic_write(self.storage, self.path, self.data, self.kind)
}

///|
/// Replay WAL records into a CoreStore. Returns number of records applied.
/// Delegates replay logic to replay_wal_data (SoT in runtime.mbt).
///
/// Uses in-memory buffer if loaded, otherwise reads from storage.
pub async fn[S : @storage.AsyncStorage] AsyncWalRuntime::replay_into(
  self : AsyncWalRuntime[S],
  store : @store.CoreStore,
) -> Int {
  let data = if self.loaded {
    self.data
  } else {
    let file_exists = @storage.async_exists(self.storage, self.path, self.kind)
    if !file_exists {
      return 0
    }
    @storage.async_read(self.storage, self.path, self.kind)
  }
  if data.length() == 0 {
    return 0
  }
  replay_wal_data(data, store)
}

///|
/// Truncate the WAL — reset in-memory buffer and write empty header.
pub async fn[S : @storage.AsyncStorage] AsyncWalRuntime::truncate(
  self : AsyncWalRuntime[S],
) -> Unit {
  let header = encode_wal_header()
  self.data = header
  self.record_count = 0
  @storage.async_atomic_write(self.storage, self.path, header, self.kind)
}

///|
/// Number of records in the current WAL buffer (since last truncate).
pub fn[S] AsyncWalRuntime::record_count(
  self : AsyncWalRuntime[S],
) -> Int {
  self.record_count
}

///|
/// Current WAL data size in bytes (for byte-size checkpoint decisions).
pub fn[S] AsyncWalRuntime::byte_size(
  self : AsyncWalRuntime[S],
) -> Int {
  self.data.length()
}

///|
/// Check if WAL exists on storage.
pub async fn[S : @storage.AsyncStorage] AsyncWalRuntime::async_exists(
  self : AsyncWalRuntime[S],
) -> Bool {
  @storage.async_exists(self.storage, self.path, self.kind)
}

///|
/// Get the WAL file path.
pub fn[S] AsyncWalRuntime::path(self : AsyncWalRuntime[S]) -> String {
  self.path
}

///|
/// Whether load() has been called.
pub fn[S] AsyncWalRuntime::is_loaded(self : AsyncWalRuntime[S]) -> Bool {
  self.loaded
}
