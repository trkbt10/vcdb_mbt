///|
/// Async WAL Runtime — awaits each storage operation to completion.
///
/// Unlike the sync WalRuntime (which relies on CachedStorage buffering),
/// this version ensures WAL data is truly persisted before returning.
/// Each read/write goes through AsyncStorage and is awaited via Promise::wait().

///|
pub struct AsyncWalRuntime[S] {
  storage : S
  path : String
  kind : @storage.StorageKind
}

///|
pub fn[S] AsyncWalRuntime::new(
  storage : S,
  path : String,
  kind? : @storage.StorageKind = Data,
) -> AsyncWalRuntime[S] {
  { storage, path, kind }
}

///|
/// Append records to the WAL. Awaits persistence to storage.
/// Append records to the WAL. Delegates merge to format.mbt's merge_wal (SoT).
pub async fn[S : @storage.AsyncStorage] AsyncWalRuntime::append(
  self : AsyncWalRuntime[S],
  records : Array[WalRecord],
) -> Unit {
  if records.is_empty() {
    return
  }
  let existing = if self.storage.exists(self.path, self.kind).wait() {
    self.storage.read(self.path, self.kind).wait()
  } else {
    Bytes::new(0)
  }
  let new_segment = encode_wal_segment(records)
  let merged = merge_wal(existing, new_segment)
  self.storage.atomic_write(self.path, merged, self.kind).wait()
}

///|
/// Replay WAL records into a CoreStore. Returns number of records applied.
/// Delegates replay logic to replay_wal_data (SoT in runtime.mbt).
pub async fn[S : @storage.AsyncStorage] AsyncWalRuntime::replay_into(
  self : AsyncWalRuntime[S],
  store : @store.CoreStore,
) -> Int {
  let file_exists = self.storage.exists(self.path, self.kind).wait()
  if not(file_exists) {
    return 0
  }
  let data = self.storage.read(self.path, self.kind).wait()
  replay_wal_data(data, store)
}

///|
/// Truncate the WAL. Awaits persistence.
pub async fn[S : @storage.AsyncStorage] AsyncWalRuntime::truncate(
  self : AsyncWalRuntime[S],
) -> Unit {
  let file_exists = self.storage.exists(self.path, self.kind).wait()
  if file_exists {
    self.storage.atomic_write(self.path, encode_wal_header(), self.kind).wait()
  }
}

///|
/// Count records in the WAL without replaying.
pub async fn[S : @storage.AsyncStorage] AsyncWalRuntime::record_count(
  self : AsyncWalRuntime[S],
) -> Int {
  let file_exists = self.storage.exists(self.path, self.kind).wait()
  if not(file_exists) {
    return 0
  }
  let data = self.storage.read(self.path, self.kind).wait()
  decode_wal_records(data).length()
}

///|
/// Check if WAL exists.
pub async fn[S : @storage.AsyncStorage] AsyncWalRuntime::async_exists(
  self : AsyncWalRuntime[S],
) -> Bool {
  self.storage.exists(self.path, self.kind).wait()
}

///|
/// Get the WAL file path.
pub fn[S] AsyncWalRuntime::path(self : AsyncWalRuntime[S]) -> String {
  self.path
}
