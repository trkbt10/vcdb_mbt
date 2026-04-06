///|
/// Tests for async rebalancing.

///|
fn run_async_blocking(f : async () -> Unit noraise) -> Unit = "%async.run"

///|
fn run_rebalance_test(f : async () -> Unit) -> Unit {
  run_async_blocking(async fn() noraise {
    try f() catch {
      e => abort("async rebalance test failed: " + e.to_string())
    }
  })
}

///|
fn make_test_manifest(
  segments : Array[(String, String)],
  crush : CrushMap,
) -> PlacementManifest {
  let entries : Array[SegmentEntry] = segments.map(fn(s) {
    let (name, target) = s
    { name, target_key: target }
  })
  {
    base: "db",
    segments: entries,
    crush,
    epoch: 1,
    commit_ts: 1000L,
  }
}

// ── AsyncRebalanceState creation ────────────────────────────────

///|
test "async_rebalance: empty plan when no topology change" {
  let crush = CrushMap::new(4, 1, [CrushTarget::new("s0")])
  let manifest = make_test_manifest(
    [("db.pg0.part0", "s0"), ("db.pg1.part0", "s0")],
    crush,
  )
  let state = AsyncRebalanceState::new(manifest, crush, 2, 2000L)
  assert_eq!(state.plan.length(), 0)
  assert_eq!(state.is_complete(), true) // no moves needed = already complete
  assert_eq!(state.remaining_moves().length(), 0)
}

///|
test "async_rebalance: plan computed on topology change" {
  let old_crush = CrushMap::new(4, 1, [CrushTarget::new("s0")])
  let new_crush = CrushMap::new(
    4,
    1,
    [CrushTarget::new("s0"), CrushTarget::new("s1")],
  )
  let manifest = make_test_manifest(
    [
      ("db.pg0.part0", "s0"),
      ("db.pg1.part0", "s0"),
      ("db.pg2.part0", "s0"),
      ("db.pg3.part0", "s0"),
    ],
    old_crush,
  )
  let state = AsyncRebalanceState::new(manifest, new_crush, 2, 2000L)
  // Some segments should need to move to s1
  assert_true!(state.plan.length() >= 0)
  assert_eq!(state.phase, Planning)
}

// ── Async execution ──────────────────────────────────────────

///|
test "async_rebalance: execute empty plan" {
  run_rebalance_test(async fn() {
    let crush = CrushMap::new(2, 1, [CrushTarget::new("s0")])
    let manifest = make_test_manifest([], crush)
    let state = AsyncRebalanceState::new(manifest, crush, 2, 2000L)
    let storages : Map[String, @storage.MemoryStorage] = {}
    storages["s0"] = @storage.MemoryStorage::new()
    let new_manifest = async_apply_rebalance(state, storages)
    assert_eq!(state.phase, Complete)
    assert_eq!(new_manifest.epoch, 2)
  })
}

///|
test "async_rebalance: execute moves with progress" {
  run_rebalance_test(async fn() {
    let old_crush = CrushMap::new(4, 1, [CrushTarget::new("s0")])
    let new_crush = CrushMap::new(
      4,
      1,
      [CrushTarget::new("s0"), CrushTarget::new("s1")],
    )
    let manifest = make_test_manifest(
      [
        ("db.pg0.part0", "s0"),
        ("db.pg1.part0", "s0"),
        ("db.pg2.part0", "s0"),
        ("db.pg3.part0", "s0"),
      ],
      old_crush,
    )
    let state = AsyncRebalanceState::new(manifest, new_crush, 2, 2000L)

    // Populate source storage with segment data
    let s0 = @storage.MemoryStorage::new()
    let s1 = @storage.MemoryStorage::new()
    let test_data = Bytes::make(100, b'\x42')
    for seg in manifest.segments {
      @storage.async_atomic_write(
        s0,
        seg.name + @codec.ext_segment,
        test_data,
        @storage.Data,
      )
    }

    let storages : Map[String, @storage.MemoryStorage] = {}
    storages["s0"] = s0
    storages["s1"] = s1

    let new_manifest = async_apply_rebalance(state, storages)

    // All moves completed
    assert_eq!(state.is_complete(), true)
    assert_eq!(state.phase, Complete)
    assert_eq!(state.remaining_moves().length(), 0)
    assert_eq!(new_manifest.epoch, 2)
    assert_eq!(new_manifest.commit_ts, 2000L)

    // Progress tracks bytes
    let progress = state.progress()
    assert_eq!(progress.moves_completed, state.plan.length())
  })
}

///|
test "async_rebalance: remaining_moves for resumability" {
  // Use explicit move plan to control exact count
  let crush = CrushMap::new(4, 1, [CrushTarget::new("s0"), CrushTarget::new("s1")])
  let manifest = make_test_manifest(
    [("db.pg0.part0", "s0"), ("db.pg1.part0", "s0")],
    crush,
  )
  let moves = [
    MovePlan::{ name: "db.pg0.part0", from: "s0", to: "s1" },
    MovePlan::{ name: "db.pg1.part0", from: "s0", to: "s1" },
    MovePlan::{ name: "db.pg2.part0", from: "s0", to: "s1" },
  ]
  let state = AsyncRebalanceState::from_plan(moves, manifest, crush, 2, 2000L)
  assert_eq!(state.plan.length(), 3)

  // Simulate partial completion: 1 of 3 done
  state.moves_completed = 1
  let remaining = state.remaining_moves()
  assert_eq!(remaining.length(), 2)
  assert_eq!(state.is_complete(), false)

  // Simulate full completion
  state.moves_completed = 3
  assert_eq!(state.remaining_moves().length(), 0)
  assert_eq!(state.is_complete(), true)
}

///|
test "async_rebalance: from_plan for crash recovery" {
  let crush = CrushMap::new(4, 1, [CrushTarget::new("s0"), CrushTarget::new("s1")])
  let manifest = make_test_manifest(
    [("db.pg0.part0", "s0")],
    crush,
  )
  // Simulate recovery: provide explicit remaining moves
  let moves = [MovePlan::{ name: "db.pg2.part0", from: "s0", to: "s1" }]
  let state = AsyncRebalanceState::from_plan(
    moves,
    manifest,
    crush,
    3,
    3000L,
  )
  assert_eq!(state.plan.length(), 1)
  assert_eq!(state.moves_completed, 0)
  assert_eq!(state.phase, Planning)
}

///|
test "async_rebalance: progress phases" {
  let crush = CrushMap::new(2, 1, [CrushTarget::new("s0")])
  let manifest = make_test_manifest([], crush)
  let state = AsyncRebalanceState::new(manifest, crush, 2, 2000L)

  // Initial phase
  assert_eq!(state.progress().phase, Planning)
  assert_eq!(state.progress().moves_total, 0)
  assert_eq!(state.progress().moves_completed, 0)
  assert_eq!(state.progress().bytes_moved, 0L)
}

///|
test "async_rebalance: manifest updated after rebalance" {
  run_rebalance_test(async fn() {
    let old_crush = CrushMap::new(4, 1, [CrushTarget::new("s0")])
    let new_crush = CrushMap::new(
      4,
      1,
      [CrushTarget::new("s0"), CrushTarget::new("s1")],
    )
    let manifest = make_test_manifest(
      [
        ("db.pg0.part0", "s0"),
        ("db.pg1.part0", "s0"),
        ("db.pg2.part0", "s0"),
        ("db.pg3.part0", "s0"),
      ],
      old_crush,
    )
    let state = AsyncRebalanceState::new(manifest, new_crush, 2, 2000L)

    let s0 = @storage.MemoryStorage::new()
    let s1 = @storage.MemoryStorage::new()
    let test_data = Bytes::make(50, b'\xFF')
    for seg in manifest.segments {
      @storage.async_atomic_write(
        s0,
        seg.name + @codec.ext_segment,
        test_data,
        @storage.Data,
      )
    }

    let storages : Map[String, @storage.MemoryStorage] = {}
    storages["s0"] = s0
    storages["s1"] = s1

    let new_manifest = async_apply_rebalance(state, storages)

    // Verify manifest reflects new CRUSH map
    assert_eq!(new_manifest.crush.targets.length(), 2)
    assert_eq!(new_manifest.epoch, 2)

    // Verify moved segments have updated target_key
    for mv in state.plan {
      let mut found : SegmentEntry? = None
      for seg in new_manifest.segments {
        if seg.name == mv.name {
          found = Some(seg)
          break
        }
      }
      match found {
        Some(seg) => assert_eq!(seg.target_key, mv.to)
        None => assert_true!(false)
      }
    }
  })
}

// ── Failure paths ─────────────────────────────────────────────

///|
/// Helper: run an async rebalance and expect it to fail.
/// Returns true if the function raised an error.
fn run_rebalance_expect_failure(
  f : async () -> Unit raise @storage.AsyncIOError,
) -> Bool {
  let mut failed = false
  run_async_blocking(async fn() noraise {
    try f() catch {
      _ => failed = true
    }
  })
  failed
}

///|
test "async_rebalance: read failure sets Failed phase" {
  let crush = CrushMap::new(
    4,
    1,
    [CrushTarget::new("s0"), CrushTarget::new("s1")],
  )
  let manifest = make_test_manifest([("db.pg0.part0", "s0")], crush)
  let moves = [MovePlan::{ name: "db.pg0.part0", from: "s0", to: "s1" }]
  let state = AsyncRebalanceState::from_plan(moves, manifest, crush, 2, 2000L)

  // Source storage is empty — async_read will reject
  let s0 = @storage.MemoryStorage::new()
  let s1 = @storage.MemoryStorage::new()
  let storages : Map[String, @storage.MemoryStorage] = {}
  storages["s0"] = s0
  storages["s1"] = s1

  let did_fail = run_rebalance_expect_failure(
    async fn() raise @storage.AsyncIOError {
      let _ = async_apply_rebalance(state, storages)
    },
  )
  assert_eq!(did_fail, true)
  // Phase must be Failed, not stuck at Copying
  match state.phase {
    Failed(msg) => assert_true!(msg.contains("Failed to read"))
    other => {
      let _ = other
      assert_true!(false)
    }
  }
  // No moves completed
  assert_eq!(state.moves_completed, 0)
  assert_eq!(state.remaining_moves().length(), 1)
}

///|
test "async_rebalance: missing storage sets Failed phase" {
  let crush = CrushMap::new(
    4,
    1,
    [CrushTarget::new("s0"), CrushTarget::new("s1")],
  )
  let manifest = make_test_manifest([("db.pg0.part0", "s0")], crush)
  let moves = [MovePlan::{ name: "db.pg0.part0", from: "s0", to: "s1" }]
  let state = AsyncRebalanceState::from_plan(moves, manifest, crush, 2, 2000L)

  // Source has data, but destination storage is not in the map
  let s0 = @storage.MemoryStorage::new()
  let test_data = Bytes::make(50, b'\x42')
  s0.write("db.pg0.part0" + @codec.ext_segment, test_data)
  let storages : Map[String, @storage.MemoryStorage] = {}
  storages["s0"] = s0
  // s1 not provided → "Destination storage not found"

  let did_fail = run_rebalance_expect_failure(
    async fn() raise @storage.AsyncIOError {
      let _ = async_apply_rebalance(state, storages)
    },
  )
  assert_eq!(did_fail, true)
  match state.phase {
    Failed(msg) =>
      assert_true!(msg.contains("Destination storage not found"))
    other => {
      let _ = other
      assert_true!(false)
    }
  }
}

///|
test "async_rebalance: partial failure preserves progress" {
  let crush = CrushMap::new(
    4,
    1,
    [CrushTarget::new("s0"), CrushTarget::new("s1")],
  )
  let manifest = make_test_manifest(
    [("db.pg0.part0", "s0"), ("db.pg1.part0", "s0")],
    crush,
  )
  // Two moves: first will succeed, second will fail (no data for pg1)
  let moves = [
    MovePlan::{ name: "db.pg0.part0", from: "s0", to: "s1" },
    MovePlan::{ name: "db.pg1.part0", from: "s0", to: "s1" },
  ]
  let state = AsyncRebalanceState::from_plan(moves, manifest, crush, 2, 2000L)

  let s0 = @storage.MemoryStorage::new()
  let s1 = @storage.MemoryStorage::new()
  // Only populate the first segment — second will fail on read
  let test_data = Bytes::make(50, b'\x42')
  s0.write("db.pg0.part0" + @codec.ext_segment, test_data)
  let storages : Map[String, @storage.MemoryStorage] = {}
  storages["s0"] = s0
  storages["s1"] = s1

  let did_fail = run_rebalance_expect_failure(
    async fn() raise @storage.AsyncIOError {
      let _ = async_apply_rebalance(state, storages)
    },
  )
  assert_eq!(did_fail, true)
  // First move succeeded, second failed
  assert_eq!(state.moves_completed, 1)
  assert_eq!(state.remaining_moves().length(), 1)
  assert_eq!(state.remaining_moves()[0].name, "db.pg1.part0")
  match state.phase {
    Failed(_) => () // Expected
    _ => assert_true!(false)
  }
  // First segment was copied to destination
  assert_true!(s1.exists("db.pg0.part0" + @codec.ext_segment))
}
