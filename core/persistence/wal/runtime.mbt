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
/// Append records to the WAL with checksum footer
pub fn[S : @storage.Storage] WalRuntime::append(
  self : WalRuntime[S],
  records : Array[WalRecord],
) -> Unit raise @storage.IOError {
  if records.is_empty() {
    return
  }
  let w = @binary.BinaryWriter::new()
  // Read existing WAL and copy only up to last decodable record
  let mut use_existing = false
  if self.storage.exists(self.path, self.kind) {
    let existing = self.storage.read(self.path, self.kind)
    // First verify checksum - if it fails, the file is corrupted
    if verify_wal_checksum(existing) {
      // Checksum valid: get safe copy length (up to last decodable record boundary)
      let safe_len = get_safe_copy_length(existing)
      if safe_len >= @codec.header_size {
        // Copy header + valid records only (excludes corrupt tail)
        for i in 0..<safe_len {
          w.push_byte(existing[i])
        }
        use_existing = true
      }
    }
    // If checksum fails, start fresh (use_existing stays false)
  }
  if not(use_existing) {
    // Write header for new/invalid/corrupted WAL
    w.push_bytes(encode_wal_header())
  }
  // Append new records
  for record in records {
    w.push_bytes(encode_wal_record(record))
  }
  // Get body and compute footer with checksum
  let body = w.concat()
  let footer = encode_wal_footer(body)
  // Write complete WAL atomically
  let final_w = @binary.BinaryWriter::new()
  final_w.push_bytes(body)
  final_w.push_bytes(footer)
  self.storage.atomic_write(self.path, final_w.concat(), self.kind)
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
  // Verify header first - reject non-WAL files
  if data.length() < @codec.header_size {
    raise @storage.IoFailed("WAL file too short")
  }
  let header_reader = @binary.BinaryReader::new(data)
  if not(verify_wal_header(header_reader)) {
    raise @storage.IoFailed("WAL header invalid")
  }
  // Verify checksum before applying records to prevent corruption
  if not(verify_wal_checksum(data)) {
    raise @storage.IoFailed("WAL checksum verification failed")
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
