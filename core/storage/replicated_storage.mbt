///|
/// Replicated async storage — writes to primary + replicas.
///
/// Implements AsyncStorage by delegating all operations to a primary
/// storage backend, with optional replication to additional backends.
///
/// Write operations (write, atomic_write, del) are sent to all backends.
/// The operation resolves when `write_quorum` backends have acknowledged.
/// Read operations go to the primary only (read-local).
///
/// Each storage in a VectorDB (WAL, snapshot) can independently be a
/// ReplicatedStorage with its own replica set and quorum config.
///
/// When replicas is empty and write_quorum is 1, this is a transparent
/// passthrough to the primary — equivalent to using the primary directly.

///|
/// Replication configuration for a single storage backend.
pub(all) struct ReplicationConfig {
  /// Minimum number of successful writes before resolving (including primary).
  /// Must be >= 1 (primary always writes).
  /// Default: 1 (primary only, fire-and-forget to replicas).
  write_quorum : Int
}

///|
pub fn ReplicationConfig::default() -> ReplicationConfig {
  { write_quorum: 1 }
}

///|
/// Create a strict replication config requiring all replicas to ack.
pub fn ReplicationConfig::all(replica_count : Int) -> ReplicationConfig {
  { write_quorum: replica_count + 1 }
}

///|
/// Create a majority quorum config.
pub fn ReplicationConfig::majority(replica_count : Int) -> ReplicationConfig {
  let total = replica_count + 1 // +1 for primary
  { write_quorum: total / 2 + 1 }
}

///|
/// Replicated storage backend.
///
/// T is the underlying AsyncStorage implementation (e.g., JsAsyncCallbackStorage,
/// MemoryStorage, NativeFileStorage).
///
/// Invariants:
///   - Primary always receives every operation.
///   - Replicas receive write/del operations only.
///   - Reads go to primary only (read-local semantics).
///   - write_quorum <= 1 + replicas.length()
pub struct ReplicatedStorage[T] {
  primary : T
  replicas : Array[T]
  config : ReplicationConfig
}

///|
/// Create a replicated storage with no replicas (passthrough).
pub fn[T] ReplicatedStorage::local_only(storage : T) -> ReplicatedStorage[T] {
  { primary: storage, replicas: [], config: ReplicationConfig::default() }
}

///|
/// Create a replicated storage with replicas and custom config.
pub fn[T] ReplicatedStorage::new(
  primary : T,
  replicas : Array[T],
  config? : ReplicationConfig = ReplicationConfig::default(),
) -> ReplicatedStorage[T] {
  { primary, replicas, config }
}

///|
/// Create a replicated storage requiring all backends to ack.
pub fn[T] ReplicatedStorage::with_all_ack(
  primary : T,
  replicas : Array[T],
) -> ReplicatedStorage[T] {
  { primary, config: ReplicationConfig::all(replicas.length()), replicas }
}

///|
/// Number of total backends (primary + replicas).
pub fn[T] ReplicatedStorage::backend_count(self : ReplicatedStorage[T]) -> Int {
  1 + self.replicas.length()
}

// ── AsyncStorage implementation ─────────────────────────────────
//
// Read operations: primary only.
// Write operations: fan-out to primary + all replicas, resolve when
// write_quorum backends have acknowledged.

///|
pub impl[T : AsyncStorage] AsyncStorage for ReplicatedStorage[T] with fn async_read(
  self,
  path,
  kind,
  resolve,
  reject,
) {
  // Read from primary only.
  self.primary.async_read(path, kind, resolve, reject)
}

///|
pub impl[T : AsyncStorage] AsyncStorage for ReplicatedStorage[T] with fn async_write(
  self,
  path,
  data,
  kind,
  resolve,
  reject,
) {
  if self.replicas.is_empty() {
    // Fast path: no replication.
    self.primary.async_write(path, data, kind, resolve, reject)
    return
  }
  let state = QuorumState::new(
    self.config.write_quorum,
    self.backend_count(),
    resolve,
    reject,
  )
  self.primary.async_write(path, data, kind, fn() { state.on_success() }, fn(
    err,
  ) {
    state.on_failure(err)
  })
  for replica in self.replicas {
    replica.async_write(path, data, kind, fn() { state.on_success() }, fn(err) {
      state.on_failure(err)
    })
  }
}

///|
pub impl[T : AsyncStorage] AsyncStorage for ReplicatedStorage[T] with fn async_atomic_write(
  self,
  path,
  data,
  kind,
  resolve,
  reject,
) {
  if self.replicas.is_empty() {
    self.primary.async_atomic_write(path, data, kind, resolve, reject)
    return
  }
  let state = QuorumState::new(
    self.config.write_quorum,
    self.backend_count(),
    resolve,
    reject,
  )
  self.primary.async_atomic_write(
    path,
    data,
    kind,
    fn() { state.on_success() },
    fn(err) { state.on_failure(err) },
  )
  for replica in self.replicas {
    replica.async_atomic_write(path, data, kind, fn() { state.on_success() }, fn(
      err,
    ) {
      state.on_failure(err)
    })
  }
}

///|
pub impl[T : AsyncStorage] AsyncStorage for ReplicatedStorage[T] with fn async_del(
  self,
  path,
  kind,
  resolve,
  reject,
) {
  if self.replicas.is_empty() {
    self.primary.async_del(path, kind, resolve, reject)
    return
  }
  let state = QuorumState::new(
    self.config.write_quorum,
    self.backend_count(),
    resolve,
    reject,
  )
  self.primary.async_del(path, kind, fn() { state.on_success() }, fn(err) {
    state.on_failure(err)
  })
  for replica in self.replicas {
    replica.async_del(path, kind, fn() { state.on_success() }, fn(err) {
      state.on_failure(err)
    })
  }
}

///|
pub impl[T : AsyncStorage] AsyncStorage for ReplicatedStorage[T] with fn async_exists(
  self,
  path,
  kind,
  resolve,
  reject,
) {
  // Read from primary only.
  self.primary.async_exists(path, kind, resolve, reject)
}

///|
pub impl[T : AsyncStorage] AsyncStorage for ReplicatedStorage[T] with fn async_list(
  self,
  kind,
  resolve,
  reject,
) {
  // Read from primary only.
  self.primary.async_list(kind, resolve, reject)
}

// ── Quorum tracking ─────────────────────────────────────────────
//
// Tracks ack/nack counts for a single fan-out operation.
// Calls resolve once write_quorum successes are reached.
// Calls reject if enough failures make quorum impossible.

///|
priv struct QuorumState {
  required : Int
  backends : Int
  mut succeeded : Int
  mut failed : Int
  mut resolved : Bool
  resolve : () -> Unit
  reject : (String) -> Unit
  mut last_error : String
}

///|
fn QuorumState::new(
  required : Int,
  backends : Int,
  resolve : () -> Unit,
  reject : (String) -> Unit,
) -> QuorumState {
  {
    required,
    backends,
    succeeded: 0,
    failed: 0,
    resolved: false,
    resolve,
    reject,
    last_error: "",
  }
}

///|
fn QuorumState::on_success(self : QuorumState) -> Unit {
  if self.resolved {
    return
  }
  self.succeeded += 1
  if self.succeeded >= self.required {
    self.resolved = true
    (self.resolve)()
  }
}

///|
fn QuorumState::on_failure(self : QuorumState, err : String) -> Unit {
  if self.resolved {
    return
  }
  self.failed += 1
  self.last_error = err
  // Remaining = backends - succeeded - failed
  let remaining = self.backends - self.succeeded - self.failed
  if self.succeeded + remaining < self.required {
    // Quorum is no longer achievable.
    self.resolved = true
    (self.reject)("Write quorum not met: " + self.last_error)
  }
}
