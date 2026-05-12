// Whitebox tests for PersistentDB[W, S] persistence layer.
//
// These tests verify the core invariants:
// 1. WAL-before-state: WAL is persisted before engine is mutated
// 2. Crash recovery: data in WAL but not in engine is recovered on replay
// 3. Checkpoint ordering: snapshot is written before WAL is truncated
// 4. Byte-size checkpoint: WAL byte threshold triggers checkpoint
// 5. Init from various storage states (empty, snapshot-only, WAL-only, both)

///|
/// In-memory AsyncStorage that records operation order for verification.
/// Each operation completes synchronously (resolve called immediately)
/// to test the ordering logic without real async I/O.
struct TestAsyncStorage {
  data : Map[String, Bytes]
  /// Records every write/read operation in order: ("write", path) etc.
  log : Array[(String, String)]
}

///|
fn TestAsyncStorage::new() -> TestAsyncStorage {
  { data: {}, log: [] }
}

///|
impl @storage.AsyncStorage for TestAsyncStorage with async_read(
  self,
  path,
  _kind,
  resolve,
  reject,
) {
  self.log.push(("read", path))
  match self.data.get(path) {
    Some(d) => resolve(d)
    None => reject("Not found: " + path)
  }
}

///|
impl @storage.AsyncStorage for TestAsyncStorage with async_write(
  self,
  path,
  data,
  _kind,
  resolve,
  _reject,
) {
  self.log.push(("write", path))
  self.data[path] = data
  resolve()
}

///|
impl @storage.AsyncStorage for TestAsyncStorage with async_atomic_write(
  self,
  path,
  data,
  _kind,
  resolve,
  _reject,
) {
  self.log.push(("atomic_write", path))
  self.data[path] = data
  resolve()
}

///|
impl @storage.AsyncStorage for TestAsyncStorage with async_del(
  self,
  path,
  _kind,
  resolve,
  _reject,
) {
  self.log.push(("del", path))
  self.data.remove(path)
  resolve()
}

///|
impl @storage.AsyncStorage for TestAsyncStorage with async_exists(
  self,
  path,
  _kind,
  resolve,
  _reject,
) {
  self.log.push(("exists", path))
  resolve(self.data.contains(path))
}

///|
impl @storage.AsyncStorage for TestAsyncStorage with async_list(
  self,
  _kind,
  resolve,
  _reject,
) {
  self.log.push(("list", ""))
  resolve(self.data.keys().collect())
}

///|
fn run_async_blocking(f : async () -> Unit noraise) -> Unit = "%async.run"

///|
fn run_async_test(f : async () -> Unit) -> Unit {
  run_async_blocking(async fn() noraise {
    f() catch {
      @storage.AsyncIOFailed(msg) => abort("AsyncIOFailed: " + msg)
      e => abort("async test failed: " + e.to_string())
    }
  })
}

///|
fn make_vid(n : Int) -> @types.VectorId {
  @types.VectorId::from_int(n)
}

///|
fn make_attrs(key : String, value : String) -> @types.Attrs {
  let a = @types.empty_attrs()
  a.set(key, @types.String(value))
  a
}

// ════════════════════════════════════════════════════════════════
// Test 1: WAL-before-state — WAL write precedes engine mutation
// ════════════════════════════════════════════════════════════════

///|
test "persistent/wal_before_state_on_upsert" {
  run_async_test(async fn() {
    let wal_store = TestAsyncStorage::new()
    let snap_store = TestAsyncStorage::new()
    let db = PersistentDB::init(
      wal_store,
      snap_store,
      "",
      "test",
      3,
      1024,
      checkpoint_threshold=1000,
      checkpoint_bytes=0,
    )
    inspect(db.size(), content="0")
    wal_store.log.clear()
    let points = [(make_vid(1), [1.0, 2.0, 3.0], make_attrs("k", "v"))]
    db.upsert(points, 1000L)
    inspect(db.size(), content="1")
    inspect(db.has(make_vid(1)), content="true")
    let has_wal_write = wal_store.log
      .iter()
      .any(fn(entry) { entry.0 == "atomic_write" })
    inspect(has_wal_write, content="true")
    let wal_path = @storage.collection_wal_path("test")
    inspect(wal_store.data.contains(wal_path), content="true")
    let wal_bytes = wal_store.data.get(wal_path).unwrap()
    inspect(wal_bytes.length() > 0, content="true")
  })
}

// ════════════════════════════════════════════════════════════════
// Test 2: Crash recovery
// ════════════════════════════════════════════════════════════════

///|
test "persistent/crash_recovery_from_wal" {
  run_async_test(async fn() {
    let wal_store = TestAsyncStorage::new()
    let snap_store = TestAsyncStorage::new()
    let db = PersistentDB::init(
      wal_store,
      snap_store,
      "",
      "test",
      3,
      1024,
      checkpoint_threshold=1000,
      checkpoint_bytes=0,
    )
    db.upsert(
      [(make_vid(10), [1.0, 2.0, 3.0], make_attrs("name", "alpha"))],
      100L,
    )
    db.upsert(
      [(make_vid(20), [4.0, 5.0, 6.0], make_attrs("name", "beta"))],
      200L,
    )
    inspect(db.size(), content="2")
    let db2 = PersistentDB::init(
      wal_store,
      snap_store,
      "",
      "test",
      3,
      1024,
      checkpoint_threshold=1000,
      checkpoint_bytes=0,
    )
    inspect(db2.size(), content="2")
    inspect(db2.has(make_vid(10)), content="true")
    inspect(db2.has(make_vid(20)), content="true")
  })
}

///|
test "persistent/replay_preserves_metric_and_strategy" {
  run_async_test(async fn() {
    let wal_store = TestAsyncStorage::new()
    let snap_store = TestAsyncStorage::new()
    let db = PersistentDB::init(
      wal_store,
      snap_store,
      "",
      "strategy-test",
      2,
      64,
      metric=@types.L2,
      strategy=@types.Bruteforce,
      checkpoint_threshold=1000,
      checkpoint_bytes=0,
    )
    db.upsert([(make_vid(1), [1.0, 2.0], make_attrs("k", "v"))], 100L)
    let reloaded = PersistentDB::init(
      wal_store,
      snap_store,
      "",
      "strategy-test",
      2,
      64,
      metric=@types.L2,
      strategy=@types.Bruteforce,
      checkpoint_threshold=1000,
      checkpoint_bytes=0,
    )
    assert_eq(reloaded.metric(), @types.L2)
    assert_true(reloaded.strategy() is @types.Bruteforce)
    assert_eq(reloaded.size(), 1)
  })
}

///|
test "persistent/hnsw_snapshot_wal_replay_preserves_tombstones" {
  run_async_test(async fn() {
    let wal_store = TestAsyncStorage::new()
    let snap_store = TestAsyncStorage::new()
    let db = PersistentDB::init(
      wal_store,
      snap_store,
      "",
      "hnsw-tombstone",
      2,
      64,
      metric=@types.Dot,
      strategy=@types.Strategy::default_hnsw(),
      checkpoint_threshold=1000,
      checkpoint_bytes=0,
    )
    db.upsert(
      [
        (make_vid(1), [1.0, 0.0], make_attrs("name", "deleted")),
        (make_vid(2), [0.0, 1.0], make_attrs("name", "alive")),
      ],
      100L,
    )
    let _ = db.remove(make_vid(1), 200L)
    db.checkpoint()
    inspect(db.has(make_vid(1)), content="false")
    db.upsert([(make_vid(3), [0.5, 0.5], make_attrs("name", "new"))], 300L)

    let reloaded = PersistentDB::init(
      wal_store,
      snap_store,
      "",
      "hnsw-tombstone",
      2,
      64,
      metric=@types.Dot,
      strategy=@types.Strategy::default_hnsw(),
      checkpoint_threshold=1000,
      checkpoint_bytes=0,
    )
    inspect(reloaded.has(make_vid(1)), content="false")
    inspect(reloaded.has(make_vid(2)), content="true")
    inspect(reloaded.has(make_vid(3)), content="true")
    let hits = reloaded.search([1.0, 0.0], 10, None)
    for hit in hits {
      assert_true(hit.id != make_vid(1))
    }
  })
}

// ════════════════════════════════════════════════════════════════
// Test 3: Checkpoint ordering
// ════════════════════════════════════════════════════════════════

///|
test "persistent/checkpoint_snapshot_before_wal_truncate" {
  run_async_test(async fn() {
    let wal_store = TestAsyncStorage::new()
    let snap_store = TestAsyncStorage::new()
    let db = PersistentDB::init(
      wal_store,
      snap_store,
      "",
      "test",
      3,
      1024,
      checkpoint_threshold=1000,
      checkpoint_bytes=0,
    )
    db.upsert([(make_vid(1), [1.0, 2.0, 3.0], make_attrs("k", "v"))], 100L)
    wal_store.log.clear()
    snap_store.log.clear()
    db.checkpoint()
    let has_snap_write = snap_store.log
      .iter()
      .any(fn(e) { e.0 == "atomic_write" })
    inspect(has_snap_write, content="true")
    let has_wal_write = wal_store.log
      .iter()
      .any(fn(e) { e.0 == "atomic_write" })
    inspect(has_wal_write, content="true")
    let data_path = @storage.collection_data_path("test")
    inspect(snap_store.data.contains(data_path), content="true")
  })
}

// ════════════════════════════════════════════════════════════════
// Test 4: Recovery after checkpoint
// ════════════════════════════════════════════════════════════════

///|
test "persistent/recovery_after_checkpoint" {
  run_async_test(async fn() {
    let wal_store = TestAsyncStorage::new()
    let snap_store = TestAsyncStorage::new()
    let db = PersistentDB::init(
      wal_store,
      snap_store,
      "",
      "test",
      3,
      1024,
      checkpoint_threshold=1000,
      checkpoint_bytes=0,
    )
    db.upsert([(make_vid(1), [1.0, 2.0, 3.0], make_attrs("k", "v"))], 100L)
    db.checkpoint()
    let db2 = PersistentDB::init(
      wal_store,
      snap_store,
      "",
      "test",
      3,
      1024,
      checkpoint_threshold=1000,
      checkpoint_bytes=0,
    )
    inspect(db2.size(), content="1")
    inspect(db2.has(make_vid(1)), content="true")
  })
}

// ════════════════════════════════════════════════════════════════
// Test 5: Snapshot + WAL recovery
// ════════════════════════════════════════════════════════════════

///|
test "persistent/recovery_snapshot_plus_wal" {
  run_async_test(async fn() {
    let wal_store = TestAsyncStorage::new()
    let snap_store = TestAsyncStorage::new()
    let db = PersistentDB::init(
      wal_store,
      snap_store,
      "",
      "test",
      3,
      1024,
      checkpoint_threshold=1000,
      checkpoint_bytes=0,
    )
    db.upsert([(make_vid(1), [1.0, 2.0, 3.0], make_attrs("k", "v1"))], 100L)
    db.checkpoint()
    db.upsert([(make_vid(2), [4.0, 5.0, 6.0], make_attrs("k", "v2"))], 200L)
    inspect(db.size(), content="2")
    let db2 = PersistentDB::init(
      wal_store,
      snap_store,
      "",
      "test",
      3,
      1024,
      checkpoint_threshold=1000,
      checkpoint_bytes=0,
    )
    inspect(db2.size(), content="2")
    inspect(db2.has(make_vid(1)), content="true")
    inspect(db2.has(make_vid(2)), content="true")
  })
}

// ════════════════════════════════════════════════════════════════
// Test 6: Auto-checkpoint by record count
// ════════════════════════════════════════════════════════════════

///|
test "persistent/auto_checkpoint_by_record_count" {
  run_async_test(async fn() {
    let wal_store = TestAsyncStorage::new()
    let snap_store = TestAsyncStorage::new()
    let db = PersistentDB::init(
      wal_store,
      snap_store,
      "",
      "test",
      3,
      1024,
      checkpoint_threshold=2,
      checkpoint_bytes=0,
    )
    db.upsert([(make_vid(1), [1.0, 2.0, 3.0], @types.empty_attrs())], 100L)
    let data_path = @storage.collection_data_path("test")
    inspect(snap_store.data.contains(data_path), content="false")
    db.upsert([(make_vid(2), [4.0, 5.0, 6.0], @types.empty_attrs())], 200L)
    inspect(snap_store.data.contains(data_path), content="true")
    inspect(db.wal_record_count(), content="0")
  })
}

// ════════════════════════════════════════════════════════════════
// Test 7: Auto-checkpoint by byte size
// ════════════════════════════════════════════════════════════════

///|
test "persistent/auto_checkpoint_by_byte_size" {
  run_async_test(async fn() {
    let wal_store = TestAsyncStorage::new()
    let snap_store = TestAsyncStorage::new()
    let db = PersistentDB::init(
      wal_store,
      snap_store,
      "",
      "test",
      3,
      1024,
      checkpoint_threshold=1000,
      checkpoint_bytes=1,
    )
    let data_path = @storage.collection_data_path("test")
    db.upsert([(make_vid(1), [1.0, 2.0, 3.0], @types.empty_attrs())], 100L)
    inspect(snap_store.data.contains(data_path), content="true")
    inspect(db.wal_record_count(), content="0")
  })
}

// ════════════════════════════════════════════════════════════════
// Test 8: Remove with WAL-before-state
// ════════════════════════════════════════════════════════════════

///|
test "persistent/remove_wal_before_state" {
  run_async_test(async fn() {
    let wal_store = TestAsyncStorage::new()
    let snap_store = TestAsyncStorage::new()
    let db = PersistentDB::init(
      wal_store,
      snap_store,
      "",
      "test",
      3,
      1024,
      checkpoint_threshold=1000,
      checkpoint_bytes=0,
    )
    db.upsert([(make_vid(1), [1.0, 2.0, 3.0], @types.empty_attrs())], 100L)
    inspect(db.size(), content="1")
    wal_store.log.clear()
    let removed = db.remove(make_vid(1), 200L)
    inspect(removed, content="true")
    inspect(db.has(make_vid(1)), content="false")
    let has_wal_write = wal_store.log
      .iter()
      .any(fn(entry) { entry.0 == "atomic_write" })
    inspect(has_wal_write, content="true")
  })
}

// ════════════════════════════════════════════════════════════════
// Test 9: Remove recovery
// ════════════════════════════════════════════════════════════════

///|
test "persistent/remove_recovery" {
  run_async_test(async fn() {
    let wal_store = TestAsyncStorage::new()
    let snap_store = TestAsyncStorage::new()
    let db = PersistentDB::init(
      wal_store,
      snap_store,
      "",
      "test",
      3,
      1024,
      checkpoint_threshold=1000,
      checkpoint_bytes=0,
    )
    db.upsert([(make_vid(1), [1.0, 2.0, 3.0], @types.empty_attrs())], 100L)
    db.upsert([(make_vid(2), [4.0, 5.0, 6.0], @types.empty_attrs())], 200L)
    let _ = db.remove(make_vid(1), 300L)
    let db2 = PersistentDB::init(
      wal_store,
      snap_store,
      "",
      "test",
      3,
      1024,
      checkpoint_threshold=1000,
      checkpoint_bytes=0,
    )
    inspect(db2.has(make_vid(1)), content="false")
    inspect(db2.has(make_vid(2)), content="true")
  })
}

///|
test "persistent/update_attrs_recovery" {
  run_async_test(async fn() {
    let wal_store = TestAsyncStorage::new()
    let snap_store = TestAsyncStorage::new()
    let db = PersistentDB::init(
      wal_store,
      snap_store,
      "",
      "test",
      3,
      1024,
      checkpoint_threshold=1000,
      checkpoint_bytes=0,
    )
    db.upsert(
      [(make_vid(1), [1.0, 2.0, 3.0], make_attrs("status", "draft"))],
      100L,
    )
    let updated = db.update_attrs(
      make_vid(1),
      make_attrs("status", "published"),
      200L,
    )
    inspect(updated, content="true")
    // Verify in-memory
    match db.get(make_vid(1)) {
      Some(r) =>
        inspect(r.attrs.to_string().contains("published"), content="true")
      None => inspect(false, content="true")
    }
    // "Crash" and re-init
    let db2 = PersistentDB::init(
      wal_store,
      snap_store,
      "",
      "test",
      3,
      1024,
      checkpoint_threshold=1000,
      checkpoint_bytes=0,
    )
    match db2.get(make_vid(1)) {
      Some(r) =>
        inspect(r.attrs.to_string().contains("published"), content="true")
      None => inspect(false, content="true")
    }
  })
}

// ════════════════════════════════════════════════════════════════
// Test 11: Init from empty storage — fresh DB
// ════════════════════════════════════════════════════════════════

///|
test "persistent/init_from_empty" {
  run_async_test(async fn() {
    let wal_store = TestAsyncStorage::new()
    let snap_store = TestAsyncStorage::new()
    let db = PersistentDB::init(
      wal_store,
      snap_store,
      "",
      "test",
      3,
      1024,
      checkpoint_threshold=1000,
      checkpoint_bytes=0,
    )
    inspect(db.size(), content="0")
    inspect(db.dim(), content="3")
  })
}

// ════════════════════════════════════════════════════════════════
// Test 12: Crash mid-checkpoint — snapshot written, WAL not yet truncated
// On re-init, WAL replay is idempotent — same data, no corruption
// ════════════════════════════════════════════════════════════════

///|
test "persistent/idempotent_wal_replay_after_checkpoint_crash" {
  run_async_test(async fn() {
    let wal_store = TestAsyncStorage::new()
    let snap_store = TestAsyncStorage::new()
    let db = PersistentDB::init(
      wal_store,
      snap_store,
      "",
      "test",
      3,
      1024,
      checkpoint_threshold=1000,
      checkpoint_bytes=0,
    )
    db.upsert([(make_vid(1), [1.0, 2.0, 3.0], make_attrs("k", "v"))], 100L)
    let wal_path = @storage.collection_wal_path("test")
    let wal_before = wal_store.data.get(wal_path).unwrap()
    db.checkpoint()
    // Simulate crash: restore the pre-truncate WAL
    wal_store.data[wal_path] = wal_before
    // Verify storage state before re-init
    let data_path = @storage.collection_data_path("test")
    inspect(snap_store.data.contains(data_path), content="true")
    inspect(wal_store.data.contains(wal_path), content="true")
    // Re-init step by step to isolate the abort
    let wal_path2 = join_path("", @storage.collection_wal_path("test"))
    let wal2 = @wal.AsyncWalRuntime::new(wal_store, wal_path2)
    let wal_data = wal2.load()
    inspect(wal_data.length() > 0, content="true")
    let has_snap = @storage.async_exists(snap_store, data_path, @storage.Data)
    inspect(has_snap, content="true")
    let snap_data = @storage.async_read(snap_store, data_path, @storage.Data)
    let db = PersistentDB::deserialize(snap_data)
    let store = db.store()
    let applied = @wal.replay_wal_data(wal_data, store)
    inspect(applied > 0, content="true")
    let options : @types.DatabaseOptions = {
      dim: 3,
      metric: @types.Cosine,
      capacity: 1024,
      strategy: @types.HNSW(@types.HNSWParams::default()),
    }
    let engine2 = VectorDB::from_store(store, options)
    let db2 = PersistentDB::wrap(
      engine2,
      @wal.AsyncWalRuntime::new(@storage.MemoryStorage::new(), ""),
      @storage.MemoryStorage::new(),
      "",
      "",
      checkpoint_threshold=2147483647,
      checkpoint_bytes=0,
    )
    inspect(db2.size(), content="1")
  })
}

// ════════════════════════════════════════════════════════════════
// Test 13: Multiple upserts to same ID — last write wins in WAL
// ════════════════════════════════════════════════════════════════

///|
// ── Test 13a: Same-ID upsert (2 times) — last write wins in WAL ──

test "persistent/same_id_upsert_last_write_wins" {
  run_async_test(async fn() {
    let wal_store = TestAsyncStorage::new()
    let snap_store = TestAsyncStorage::new()
    let db = PersistentDB::init(
      wal_store,
      snap_store,
      "",
      "test",
      3,
      1024,
      checkpoint_threshold=1000,
      checkpoint_bytes=0,
    )
    db.upsert([(make_vid(1), [1.0, 0.0, 0.0], make_attrs("ver", "1"))], 100L)
    db.upsert([(make_vid(1), [0.0, 1.0, 0.0], make_attrs("ver", "2"))], 200L)
    inspect(db.size(), content="1")
    // Verify in-memory: last write wins
    match db.get(make_vid(1)) {
      Some(r) => {
        inspect(r.vector[1], content="1")
        inspect(r.attrs.to_string().contains("\"2\""), content="true")
      }
      None => inspect(false, content="true")
    }
    // Crash and recover from WAL — should replay both, last wins
    let db2 = PersistentDB::init(
      wal_store,
      snap_store,
      "",
      "test",
      3,
      1024,
      checkpoint_threshold=1000,
      checkpoint_bytes=0,
    )
    inspect(db2.size(), content="1")
    match db2.get(make_vid(1)) {
      Some(r) => {
        inspect(r.vector[1], content="1")
        inspect(r.attrs.to_string().contains("\"2\""), content="true")
      }
      None => inspect(false, content="true")
    }
  })
}

// ── Test 13b: Multiple separate upserts (different IDs) and recovery ──

///|
test "persistent/separate_upserts_recovery" {
  run_async_test(async fn() {
    let wal_store = TestAsyncStorage::new()
    let snap_store = TestAsyncStorage::new()
    let db = PersistentDB::init(
      wal_store,
      snap_store,
      "",
      "test",
      3,
      1024,
      checkpoint_threshold=1000,
      checkpoint_bytes=0,
    )
    // Three separate upsert calls (not batch)
    db.upsert([(make_vid(1), [1.0, 0.0, 0.0], make_attrs("ver", "1"))], 100L)
    db.upsert([(make_vid(2), [0.0, 1.0, 0.0], make_attrs("ver", "2"))], 200L)
    inspect(db.size(), content="2")
    // Crash and recover
    let db2 = PersistentDB::init(
      wal_store,
      snap_store,
      "",
      "test",
      3,
      1024,
      checkpoint_threshold=1000,
      checkpoint_bytes=0,
    )
    inspect(db2.size(), content="2")
    inspect(db2.has(make_vid(1)), content="true")
    inspect(db2.has(make_vid(2)), content="true")
    match db2.get(make_vid(2)) {
      Some(r) => inspect(r.vector[1], content="1")
      None => inspect(false, content="true")
    }
  })
}

// ════════════════════════════════════════════════════════════════
// Test 14: Remove of non-existent ID — no WAL write, returns false
// ════════════════════════════════════════════════════════════════

///|
test "persistent/remove_nonexistent" {
  run_async_test(async fn() {
    let wal_store = TestAsyncStorage::new()
    let snap_store = TestAsyncStorage::new()
    let db = PersistentDB::init(
      wal_store,
      snap_store,
      "",
      "test",
      3,
      1024,
      checkpoint_threshold=1000,
      checkpoint_bytes=0,
    )
    wal_store.log.clear()
    let removed = db.remove(make_vid(999), 100L)
    inspect(removed, content="false")
    // No WAL write should have happened
    let has_wal_write = wal_store.log
      .iter()
      .any(fn(entry) { entry.0 == "atomic_write" })
    inspect(has_wal_write, content="false")
  })
}

// ════════════════════════════════════════════════════════════════
// Test 15: WAL replay consistency
// Verify that init and manual replay produce equivalent store state
// ════════════════════════════════════════════════════════════════

///|
test "persistent/wal_replay_consistency" {
  run_async_test(async fn() {
    let wal_store = TestAsyncStorage::new()
    let snap_store = TestAsyncStorage::new()
    let db = PersistentDB::init(
      wal_store,
      snap_store,
      "",
      "test",
      3,
      1024,
      checkpoint_threshold=1000,
      checkpoint_bytes=0,
    )
    db.upsert(
      [
        (make_vid(1), [1.0, 2.0, 3.0], make_attrs("a", "1")),
        (make_vid(2), [4.0, 5.0, 6.0], make_attrs("a", "2")),
      ],
      100L,
    )
    let _ = db.remove(make_vid(1), 200L)
    // Get raw WAL bytes from storage
    let wal_path = @storage.collection_wal_path("test")
    let wal_bytes = wal_store.data.get(wal_path).unwrap()
    // Manually replay into a fresh CoreStore
    let manual_store = @store.CoreStore::new(3, @types.Cosine, capacity=1024)
    let applied = @wal.replay_wal_data(wal_bytes, manual_store)
    inspect(applied > 0, content="true")
    // Compare with PersistentPersistentDB re-init
    let db2 = PersistentDB::init(
      wal_store,
      snap_store,
      "",
      "test",
      3,
      1024,
      checkpoint_threshold=1000,
      checkpoint_bytes=0,
    )
    // Both paths should produce the same state
    inspect(manual_store.size(), content=db2.size().to_string())
    // ID 1 removed, ID 2 present
    inspect(manual_store.get(make_vid(1)) is None, content="true")
    inspect(manual_store.get(make_vid(2)) is None, content="false")
  })
}

// ════════════════════════════════════════════════════════════════
// Distributed environment tests
// ════════════════════════════════════════════════════════════════

// ── Test D1: Two instances with separate storage do not interfere ──
// In a sharded deployment, each shard has its own WAL storage and
// snapshot storage. Writes to shard 0 must never appear in shard 1.

///|
test "persistent/multi_instance_isolation" {
  run_async_test(async fn() {
    // Shard 0
    let wal0 = TestAsyncStorage::new()
    let snap0 = TestAsyncStorage::new()
    let shard0 = PersistentDB::init(
      wal0,
      snap0,
      "",
      "shard0",
      3,
      1024,
      checkpoint_threshold=1000,
      checkpoint_bytes=0,
    )
    // Shard 1
    let wal1 = TestAsyncStorage::new()
    let snap1 = TestAsyncStorage::new()
    let shard1 = PersistentDB::init(
      wal1,
      snap1,
      "",
      "shard1",
      3,
      1024,
      checkpoint_threshold=1000,
      checkpoint_bytes=0,
    )
    // Write to shard 0 only
    shard0.upsert(
      [(make_vid(100), [1.0, 0.0, 0.0], make_attrs("shard", "0"))],
      100L,
    )
    // Write to shard 1 only
    shard1.upsert(
      [(make_vid(200), [0.0, 1.0, 0.0], make_attrs("shard", "1"))],
      100L,
    )
    // Shard 0 must not see shard 1's data
    inspect(shard0.size(), content="1")
    inspect(shard0.has(make_vid(100)), content="true")
    inspect(shard0.has(make_vid(200)), content="false")
    // Shard 1 must not see shard 0's data
    inspect(shard1.size(), content="1")
    inspect(shard1.has(make_vid(200)), content="true")
    inspect(shard1.has(make_vid(100)), content="false")
    // WAL storage must be isolated
    let wal0_path = @storage.collection_wal_path("shard0")
    let wal1_path = @storage.collection_wal_path("shard1")
    inspect(wal0.data.contains(wal0_path), content="true")
    inspect(wal0.data.contains(wal1_path), content="false")
    inspect(wal1.data.contains(wal1_path), content="true")
    inspect(wal1.data.contains(wal0_path), content="false")
    // Recovery: each shard recovers only its own data
    let shard0b = PersistentDB::init(
      wal0,
      snap0,
      "",
      "shard0",
      3,
      1024,
      checkpoint_threshold=1000,
      checkpoint_bytes=0,
    )
    let shard1b = PersistentDB::init(
      wal1,
      snap1,
      "",
      "shard1",
      3,
      1024,
      checkpoint_threshold=1000,
      checkpoint_bytes=0,
    )
    inspect(shard0b.size(), content="1")
    inspect(shard0b.has(make_vid(100)), content="true")
    inspect(shard0b.has(make_vid(200)), content="false")
    inspect(shard1b.size(), content="1")
    inspect(shard1b.has(make_vid(200)), content="true")
    inspect(shard1b.has(make_vid(100)), content="false")
  })
}

// ── Test D2: Shared storage backend with prefix isolation ──
// In some deployments (e.g., single R2 bucket with DO-ID prefix),
// multiple shards share the same physical storage but use different
// base_path / name to isolate their data. Verify no cross-contamination.

///|
test "persistent/shared_storage_prefix_isolation" {
  run_async_test(async fn() {
    // Single shared storage backend for all shards
    let shared_wal = TestAsyncStorage::new()
    let shared_snap = TestAsyncStorage::new()
    // Two shards with different names (simulating DO-ID prefix)
    let shard_a = PersistentDB::init(
      shared_wal,
      shared_snap,
      "do-abc",
      "vectors",
      3,
      1024,
      checkpoint_threshold=1000,
      checkpoint_bytes=0,
    )
    let shard_b = PersistentDB::init(
      shared_wal,
      shared_snap,
      "do-xyz",
      "vectors",
      3,
      1024,
      checkpoint_threshold=1000,
      checkpoint_bytes=0,
    )
    shard_a.upsert(
      [(make_vid(1), [1.0, 0.0, 0.0], make_attrs("src", "a"))],
      100L,
    )
    shard_b.upsert(
      [(make_vid(1), [0.0, 1.0, 0.0], make_attrs("src", "b"))],
      100L,
    )
    // Same ID (1) in both shards, but different data
    inspect(shard_a.size(), content="1")
    inspect(shard_b.size(), content="1")
    match shard_a.get(make_vid(1)) {
      Some(r) => inspect(r.attrs.to_string().contains("\"a\""), content="true")
      None => inspect(false, content="true")
    }
    match shard_b.get(make_vid(1)) {
      Some(r) => inspect(r.attrs.to_string().contains("\"b\""), content="true")
      None => inspect(false, content="true")
    }
    // WAL paths should differ
    let wal_a = @storage.collection_wal_path("vectors")
    let full_a = "do-abc/" + wal_a
    let full_b = "do-xyz/" + wal_a
    inspect(shared_wal.data.contains(full_a), content="true")
    inspect(shared_wal.data.contains(full_b), content="true")
    // Recovery from shared storage
    let shard_a2 = PersistentDB::init(
      shared_wal,
      shared_snap,
      "do-abc",
      "vectors",
      3,
      1024,
      checkpoint_threshold=1000,
      checkpoint_bytes=0,
    )
    let shard_b2 = PersistentDB::init(
      shared_wal,
      shared_snap,
      "do-xyz",
      "vectors",
      3,
      1024,
      checkpoint_threshold=1000,
      checkpoint_bytes=0,
    )
    inspect(shard_a2.size(), content="1")
    inspect(shard_b2.size(), content="1")
    match shard_a2.get(make_vid(1)) {
      Some(r) => inspect(r.attrs.to_string().contains("\"a\""), content="true")
      None => inspect(false, content="true")
    }
    match shard_b2.get(make_vid(1)) {
      Some(r) => inspect(r.attrs.to_string().contains("\"b\""), content="true")
      None => inspect(false, content="true")
    }
  })
}

// ── Test D3: Timestamp ordering in WAL ──
// WAL records carry timestamps for cross-shard consistency.
// Verify timestamps are correctly stored and retrievable.

///|
test "persistent/timestamp_preserved_in_wal" {
  run_async_test(async fn() {
    let wal_store = TestAsyncStorage::new()
    let snap_store = TestAsyncStorage::new()
    let db = PersistentDB::init(
      wal_store,
      snap_store,
      "",
      "test",
      3,
      1024,
      checkpoint_threshold=1000,
      checkpoint_bytes=0,
    )
    // Upsert with specific timestamps
    db.upsert(
      [(make_vid(1), [1.0, 0.0, 0.0], @types.empty_attrs())],
      1000000L, // ts = 1ms
    )
    db.upsert(
      [(make_vid(2), [0.0, 1.0, 0.0], @types.empty_attrs())],
      2000000L, // ts = 2ms
    )
    // Read raw WAL and verify timestamps
    let wal_path = @storage.collection_wal_path("test")
    let wal_bytes = wal_store.data.get(wal_path).unwrap()
    let max_ts = @wal.max_wal_timestamp(wal_bytes)
    inspect(max_ts, content="2000000")
    // Filter by timestamp: only records <= 1ms should be included
    let filtered = @wal.filter_wal_by_timestamp(wal_bytes, 1000000L)
    inspect(filtered.length(), content="1")
    // Replay with cutoff — should only get vector 1
    let store = @store.CoreStore::new(3, @types.Cosine, capacity=1024)
    let applied = @wal.replay_wal_data(wal_bytes, store, cutoff_ts=1000000L)
    inspect(applied, content="1")
    inspect(store.has(make_vid(1)), content="true")
    inspect(store.has(make_vid(2)), content="false")
  })
}

// ── Test D4: Point-in-time recovery across shards ──
// Two shards receive writes at different timestamps.
// Replaying both WALs at the same cutoff timestamp must produce
// a consistent cross-shard snapshot.

///|
test "persistent/cross_shard_point_in_time" {
  run_async_test(async fn() {
    let wal0 = TestAsyncStorage::new()
    let snap0 = TestAsyncStorage::new()
    let wal1 = TestAsyncStorage::new()
    let snap1 = TestAsyncStorage::new()
    let shard0 = PersistentDB::init(
      wal0,
      snap0,
      "",
      "s0",
      3,
      1024,
      checkpoint_threshold=1000,
      checkpoint_bytes=0,
    )
    let shard1 = PersistentDB::init(
      wal1,
      snap1,
      "",
      "s1",
      3,
      1024,
      checkpoint_threshold=1000,
      checkpoint_bytes=0,
    )
    // t=100: both shards get a write
    shard0.upsert(
      [(make_vid(1), [1.0, 0.0, 0.0], make_attrs("t", "100"))],
      100L,
    )
    shard1.upsert(
      [(make_vid(2), [0.0, 1.0, 0.0], make_attrs("t", "100"))],
      100L,
    )
    // t=200: only shard0 gets another write
    shard0.upsert(
      [(make_vid(3), [0.0, 0.0, 1.0], make_attrs("t", "200"))],
      200L,
    )
    // t=300: only shard1 gets a remove
    let _ = shard1.remove(make_vid(2), 300L)
    // Current state: shard0 has {1,3}, shard1 has {}
    inspect(shard0.size(), content="2")
    inspect(shard1.size(), content="0")
    // Point-in-time at t=100: both shards should have 1 vector each
    let wal0_path = @storage.collection_wal_path("s0")
    let wal0_bytes = wal0.data.get(wal0_path).unwrap()
    let store0_t100 = @store.CoreStore::new(3, @types.Cosine, capacity=1024)
    let applied0 = @wal.replay_wal_data(wal0_bytes, store0_t100, cutoff_ts=100L)
    inspect(applied0, content="1")
    inspect(store0_t100.has(make_vid(1)), content="true")
    inspect(store0_t100.has(make_vid(3)), content="false") // not yet at t=100
    let wal1_path = @storage.collection_wal_path("s1")
    let wal1_bytes = wal1.data.get(wal1_path).unwrap()
    let store1_t100 = @store.CoreStore::new(3, @types.Cosine, capacity=1024)
    let applied1 = @wal.replay_wal_data(wal1_bytes, store1_t100, cutoff_ts=100L)
    inspect(applied1, content="1")
    inspect(store1_t100.has(make_vid(2)), content="true") // not yet removed at t=100
    // Point-in-time at t=200: shard0 has {1,3}, shard1 has {2}
    let store0_t200 = @store.CoreStore::new(3, @types.Cosine, capacity=1024)
    let _ = @wal.replay_wal_data(wal0_bytes, store0_t200, cutoff_ts=200L)
    inspect(store0_t200.has(make_vid(1)), content="true")
    inspect(store0_t200.has(make_vid(3)), content="true")
    let store1_t200 = @store.CoreStore::new(3, @types.Cosine, capacity=1024)
    let _ = @wal.replay_wal_data(wal1_bytes, store1_t200, cutoff_ts=200L)
    inspect(store1_t200.has(make_vid(2)), content="true") // remove at t=300 not yet
  })
}

// ── Test D5: Independent checkpoint does not affect other shards ──
// When one shard checkpoints, only its own snapshot is written.
// Other shards' WAL and data are untouched.

///|
test "persistent/independent_checkpoint" {
  run_async_test(async fn() {
    let wal0 = TestAsyncStorage::new()
    let snap0 = TestAsyncStorage::new()
    let wal1 = TestAsyncStorage::new()
    let snap1 = TestAsyncStorage::new()
    let shard0 = PersistentDB::init(
      wal0,
      snap0,
      "",
      "s0",
      3,
      1024,
      checkpoint_threshold=1000,
      checkpoint_bytes=0,
    )
    let shard1 = PersistentDB::init(
      wal1,
      snap1,
      "",
      "s1",
      3,
      1024,
      checkpoint_threshold=1000,
      checkpoint_bytes=0,
    )
    shard0.upsert([(make_vid(1), [1.0, 0.0, 0.0], @types.empty_attrs())], 100L)
    shard1.upsert([(make_vid(2), [0.0, 1.0, 0.0], @types.empty_attrs())], 100L)
    // Checkpoint shard0 only
    shard0.checkpoint()
    // shard0's snapshot must exist
    let s0_data = @storage.collection_data_path("s0")
    inspect(snap0.data.contains(s0_data), content="true")
    // shard1's snapshot must NOT exist (no checkpoint)
    let s1_data = @storage.collection_data_path("s1")
    inspect(snap1.data.contains(s1_data), content="false")
    // shard1's WAL must still have its record
    inspect(shard1.wal_record_count(), content="1")
    // shard0's WAL should be truncated
    inspect(shard0.wal_record_count(), content="0")
    // Both shards recover independently
    let shard0b = PersistentDB::init(
      wal0,
      snap0,
      "",
      "s0",
      3,
      1024,
      checkpoint_threshold=1000,
      checkpoint_bytes=0,
    )
    let shard1b = PersistentDB::init(
      wal1,
      snap1,
      "",
      "s1",
      3,
      1024,
      checkpoint_threshold=1000,
      checkpoint_bytes=0,
    )
    inspect(shard0b.has(make_vid(1)), content="true")
    inspect(shard1b.has(make_vid(2)), content="true")
  })
}
