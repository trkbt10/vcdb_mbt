///|
/// Async rebalancing — executes move plans using AsyncStorage with
/// progress tracking and crash resumability.
///
/// Uses the same MovePlan type and plan_rebalance function from crush.mbt.
/// The only difference from sync apply_rebalance is:
///   - Uses AsyncStorage trait instead of Storage trait
///   - Tracks progress after each move (for UI feedback / monitoring)
///   - Returns remaining moves for crash resumability

///|
/// Rebalance lifecycle phase.
pub(all) enum RebalancePhase {
  /// Plan has been computed but no moves started.
  Planning
  /// Copying data between targets. (completed, total)
  Copying(Int, Int)
  /// All copies done, updating manifest.
  Updating
  /// Rebalance complete.
  Complete
  /// Rebalance failed with error.
  Failed(String)
} derive(Eq)

///|
pub impl Show for RebalancePhase with output(self, logger) {
  match self {
    Planning => logger.write_string("Planning")
    Copying(completed, total) => {
      logger.write_string("Copying(")
      Show::output(completed, logger)
      logger.write_string(", ")
      Show::output(total, logger)
      logger.write_string(")")
    }
    Updating => logger.write_string("Updating")
    Complete => logger.write_string("Complete")
    Failed(msg) => {
      logger.write_string("Failed(")
      Show::output(msg, logger)
      logger.write_string(")")
    }
  }
}

///|
/// Progress snapshot for a rebalance operation.
pub(all) struct RebalanceProgress {
  phase : RebalancePhase
  moves_total : Int
  moves_completed : Int
  bytes_moved : Int64
}

///|
pub impl Show for RebalanceProgress with output(self, logger) {
  logger.write_string("{ phase: ")
  Show::output(self.phase, logger)
  logger.write_string(", moves_total: ")
  Show::output(self.moves_total, logger)
  logger.write_string(", moves_completed: ")
  Show::output(self.moves_completed, logger)
  logger.write_string(", bytes_moved: ")
  Show::output(self.bytes_moved, logger)
  logger.write_string(" }")
}

///|
/// Mutable state for an async rebalance operation.
///
/// Created from plan_rebalance output. Tracks which moves have been
/// completed, enabling crash resumability: on restart, call
/// remaining_moves() to get un-executed moves.
pub struct AsyncRebalanceState {
  plan : Array[MovePlan]
  mut moves_completed : Int
  mut bytes_moved : Int64
  mut phase : RebalancePhase
  manifest : PlacementManifest
  new_crush : CrushMap
  new_epoch : Int
  new_ts : Int64
}

///|
/// Create a rebalance state from an existing manifest and new CRUSH map.
///
/// Internally calls plan_rebalance (SoT in crush.mbt) to compute moves.
pub fn AsyncRebalanceState::new(
  manifest : PlacementManifest,
  new_crush : CrushMap,
  new_epoch : Int,
  new_ts : Int64,
) -> AsyncRebalanceState {
  let plan = plan_rebalance(manifest, new_crush)
  {
    plan,
    moves_completed: 0,
    bytes_moved: 0L,
    phase: Planning,
    manifest,
    new_crush,
    new_epoch,
    new_ts,
  }
}

///|
/// Create a rebalance state from an explicit move plan.
///
/// Use this for crash recovery: provide the remaining moves from
/// a previous incomplete rebalance.
pub fn AsyncRebalanceState::from_plan(
  plan : Array[MovePlan],
  manifest : PlacementManifest,
  new_crush : CrushMap,
  new_epoch : Int,
  new_ts : Int64,
) -> AsyncRebalanceState {
  {
    plan,
    moves_completed: 0,
    bytes_moved: 0L,
    phase: Planning,
    manifest,
    new_crush,
    new_epoch,
    new_ts,
  }
}

///|
/// Get current progress snapshot.
pub fn AsyncRebalanceState::progress(
  self : AsyncRebalanceState,
) -> RebalanceProgress {
  {
    phase: self.phase,
    moves_total: self.plan.length(),
    moves_completed: self.moves_completed,
    bytes_moved: self.bytes_moved,
  }
}

///|
/// Whether the rebalance is complete (all moves executed).
pub fn AsyncRebalanceState::is_complete(self : AsyncRebalanceState) -> Bool {
  self.moves_completed >= self.plan.length()
}

///|
/// Return the moves that have not yet been executed.
///
/// Used for crash resumability: serialize these, and on restart
/// create a new state via from_plan with only these moves.
pub fn AsyncRebalanceState::remaining_moves(
  self : AsyncRebalanceState,
) -> Array[MovePlan] {
  let remaining : Array[MovePlan] = []
  for i = self.moves_completed; i < self.plan.length(); i = i + 1 {
    remaining.push(self.plan[i])
  }
  remaining
}

///|
/// Execute all moves using async storage.
///
/// Processes moves sequentially (one at a time) to minimize disruption.
/// Updates progress after each successful move. On failure, sets phase
/// to Failed and raises AsyncIOError — caller can inspect
/// remaining_moves() to resume from where it stopped.
///
/// Returns the updated manifest on success.
pub async fn[S : @storage.AsyncStorage] async_apply_rebalance(
  state : AsyncRebalanceState,
  storages : Map[TargetKey, S],
) -> PlacementManifest raise @storage.AsyncIOError {
  if state.plan.is_empty() {
    state.phase = Complete
    return update_manifest_after_rebalance(
      state.manifest,
      state.plan,
      state.new_crush,
      state.new_epoch,
      state.new_ts,
    )
  }

  state.phase = Copying(0, state.plan.length())

  for i = state.moves_completed; i < state.plan.length(); i = i + 1 {
    let mv = state.plan[i]

    // Lookup storages
    let from_storage = match storages.get(mv.from) {
      Some(s) => s
      None => {
        let msg = "Source storage not found: " + mv.from.to_string()
        state.phase = Failed(msg)
        raise @storage.AsyncIOFailed(msg)
      }
    }
    let to_storage = match storages.get(mv.to) {
      Some(s) => s
      None => {
        let msg = "Destination storage not found: " + mv.to.to_string()
        state.phase = Failed(msg)
        raise @storage.AsyncIOFailed(msg)
      }
    }

    // Read from source (async)
    let segment_path = mv.name + @codec.ext_segment
    let data = @storage.async_read(from_storage, segment_path, @storage.Data) catch {
      _ => {
        let err = "Failed to read " +
          segment_path +
          " from " +
          mv.from.to_string()
        state.phase = Failed(err)
        raise @storage.AsyncIOFailed(err)
      }
    }

    // Write to destination (async)
    @storage.async_atomic_write(to_storage, segment_path, data, @storage.Data) catch {
      _ => {
        let err = "Failed to write " + segment_path + " to " + mv.to.to_string()
        state.phase = Failed(err)
        raise @storage.AsyncIOFailed(err)
      }
    }

    // Delete from source (async, best-effort — failure here does not abort)
    try {
      let source_has = @storage.async_exists(
        from_storage,
        segment_path,
        @storage.Data,
      )
      if source_has {
        @storage.async_del(from_storage, segment_path, @storage.Data)
      }
    } catch {
      _ => () // Best-effort: copy already succeeded, ignore cleanup failure
    }

    // Update progress
    state.moves_completed = i + 1
    state.bytes_moved = state.bytes_moved + data.length().to_int64()
    state.phase = Copying(state.moves_completed, state.plan.length())
  }

  // All moves done — update manifest
  state.phase = Updating
  let new_manifest = update_manifest_after_rebalance(
    state.manifest,
    state.plan,
    state.new_crush,
    state.new_epoch,
    state.new_ts,
  )
  state.phase = Complete
  new_manifest
}
