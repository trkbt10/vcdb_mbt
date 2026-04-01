///|
/// WAL Runtime - manages append, replay, and truncate operations
pub struct WalRuntime[S] {
  storage : S
  path : String
  kind : @storage.StorageKind
}

///|
/// Create a new WAL runtime with any Storage backend
pub fn[S] WalRuntime::new(
  storage : S,
  path : String,
  kind? : @storage.StorageKind = Data,
) -> WalRuntime[S] {
  { storage, path, kind }
}

///|
/// Get the WAL file path
pub fn[S] WalRuntime::path(self : WalRuntime[S]) -> String {
  self.path
}

///|
/// Get safe copy length - up to the last decodable record boundary
/// Returns header length (12) if no records are decodable
fn get_safe_copy_length(data : Bytes) -> Int {
  if data.length() < @codec.header_size {
    return 0
  }
  let r = @binary.BinaryReader::new(data)
  // Verify header first
  if not(verify_wal_header(r)) {
    return 0
  }
  // Calculate body length (without footer)
  let body_len = wal_body_length(data)
  // Track position after last successful decode
  let mut last_valid_pos = @codec.header_size // After header
  while r.position() < body_len {
    match decode_wal_record(r) {
      None => break // Stop at first malformed record
      Some(_) => last_valid_pos = r.position()
    }
  }
  last_valid_pos
}

///|
/// Append records to the WAL with checksum footer.
/// Delegates merge logic to format.mbt's merge_wal (the SoT).
pub fn[S : @storage.Storage] WalRuntime::append(
  self : WalRuntime[S],
  records : Array[WalRecord],
) -> Unit raise @storage.IOError {
  if records.is_empty() {
    return
  }
  let existing = if self.storage.exists(self.path, self.kind) {
    self.storage.read(self.path, self.kind)
  } else {
    Bytes::new(0)
  }
  let new_segment = encode_wal_segment(records)
  let merged = merge_wal(existing, new_segment)
  self.storage.atomic_write(self.path, merged, self.kind)
}

///|
/// Replay WAL records into a CoreStore
/// Returns the number of records applied
pub fn[S : @storage.Storage] WalRuntime::replay_into(
  self : WalRuntime[S],
  store : @store.CoreStore,
) -> Int raise @storage.IOError {
  if not(self.storage.exists(self.path, self.kind)) {
    return 0
  }
  let data = self.storage.read(self.path, self.kind)
  replay_wal_data(data, store)
}

///|
/// Replay WAL binary data into a CoreStore (no Storage dependency).
/// This is the SoT for WAL replay logic. Used by:
/// - WalRuntime::replay_into (reads from Storage, then delegates here)
/// - JS async gateway (passes WAL bytes directly)
/// - AsyncWalRuntime::replay_into (reads from AsyncStorage, then delegates here)
///
/// Returns the number of records applied. Returns 0 for empty/invalid data.
pub fn replay_wal_data(data : Bytes, store : @store.CoreStore) -> Int {
  if data.length() < @codec.header_size {
    return 0
  }
  let header_reader = @binary.BinaryReader::new(data)
  if not(verify_wal_header(header_reader)) {
    return 0
  }
  if not(verify_wal_checksum(data)) {
    return 0
  }
  let records = decode_wal_records(data)
  let mut applied = 0
  for record in records {
    match record.record_type {
      Upsert =>
        match record.vector {
          None => ()
          Some(vector) => {
            let attrs = match record.attrs {
              None => @types.empty_attrs()
              Some(a) => a
            }
            let _ = store.add_or_update(record.id, vector, attrs, upsert=true)
            applied = applied + 1
          }
        }
      Remove => {
        let _ = store.remove_by_id(record.id)
        applied = applied + 1
      }
      SetAttrs =>
        match record.attrs {
          None => ()
          Some(attrs) => {
            let _ = store.update_attrs(record.id, attrs)
            applied = applied + 1
          }
        }
    }
  }
  applied
}

///|
/// Truncate (clear) the WAL
pub fn[S : @storage.Storage] WalRuntime::truncate(
  self : WalRuntime[S],
) -> Unit {
  if self.storage.exists(self.path, self.kind) {
    // Write empty WAL with just header
    self.storage.atomic_write(self.path, encode_wal_header(), self.kind) catch {
      _ => ()
    }
  }
}

///|
/// Get WAL size in bytes
pub fn[S : @storage.Storage] WalRuntime::size(self : WalRuntime[S]) -> Int {
  if self.storage.exists(self.path, self.kind) {
    self.storage.read(self.path, self.kind).length() catch {
      _ => 0
    }
  } else {
    0
  }
}

///|
/// Check if WAL exists
pub fn[S : @storage.Storage] WalRuntime::exists(
  self : WalRuntime[S],
) -> Bool {
  self.storage.exists(self.path, self.kind)
}

///|
/// Count records in the WAL without replaying
pub fn[S : @storage.Storage] WalRuntime::record_count(
  self : WalRuntime[S],
) -> Int {
  if not(self.storage.exists(self.path, self.kind)) {
    return 0
  }
  let data = self.storage.read(self.path, self.kind) catch { _ => return 0 }
  decode_wal_records(data).length()
}
