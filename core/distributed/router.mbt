///|
/// Distributed routing.
///
/// Maps vector IDs to physical target nodes via CRUSH placement.
///
/// ## Architecture
///
/// - PG (placement group): logical data partition. CRUSH hashes vector IDs to PGs.
/// - Target: physical storage node. CRUSH maps each PG to N target nodes (replicas).
/// - Each target holds data for exactly the PGs assigned to it.
/// - Reads query one target per PG. Writes go to all targets for each PG.
///
/// Platform adapters must use these routing functions rather than
/// implementing their own hash.

///|
/// Group upsert points by target using CRUSH placement.
///
/// Each point is hashed to a PG, then the PG is mapped to target nodes.
/// With replicas > 1, each point appears in multiple target groups
/// (one per replica target for its PG).
///
/// Returns a map from target_key to the points that target should receive.
pub fn group_by_target(
  points : Array[(@types.VectorId, Array[Double], @types.Attrs)],
  crush_map : @placement.CrushMap,
) -> Map[
  @placement.TargetKey,
  Array[(@types.VectorId, Array[Double], @types.Attrs)],
] {
  let groups : Map[
    @placement.TargetKey,
    Array[(@types.VectorId, Array[Double], @types.Attrs)],
  ] = {}
  for point in points {
    let (id, _, _) = point
    let result = @placement.crush_locate(id, crush_map)
    // result.primaries contains the target keys for this PG's replicas
    for target_key in result.primaries {
      match groups.get(target_key) {
        Some(arr) => arr.push(point)
        None => groups.set(target_key, [point])
      }
    }
  }
  groups
}

///|
/// Determine which target nodes hold a specific vector ID.
///
/// Returns the ordered list of target keys from CRUSH placement.
/// All targets are equal — there is no "primary" or "fallback".
/// The caller may query any one of them for reads, or all for writes.
pub fn targets_for_id(
  id : @types.VectorId,
  crush_map : @placement.CrushMap,
) -> Array[@placement.TargetKey] {
  let result = @placement.crush_locate(id, crush_map)
  result.primaries
}

///|
/// Select one healthy target per PG for fan-out reads.
///
/// For each PG in the CRUSH map, picks the first healthy target.
/// Returns an array of target keys — one per PG that has at least
/// one healthy target. PGs with all targets failed are omitted
/// (partial results).
///
/// This ensures each PG's data is counted exactly once, with no
/// duplicate results and no division needed.
pub fn select_read_targets(
  crush_map : @placement.CrushMap,
  tracker : ShardHealthTracker,
) -> Array[@placement.TargetKey] {
  let selected : Map[@placement.TargetKey, Bool] = {} // Avoid querying same target twice
  let result : Array[@placement.TargetKey] = []
  for pg in 0..<crush_map.pgs {
    let locate = @placement.crush_locate_pg(pg, crush_map)
    let mut found = false
    for target_key in locate {
      if !found &&
        tracker.get_status(target_key) != Failed &&
        !selected.contains(target_key) {
        result.push(target_key)
        selected.set(target_key, true)
        found = true
      }
    }
    // If no unselected healthy target, allow one already selected
    // for another PG (degraded: same target queried for two PGs,
    // but better than missing an entire PG's data).
    // We do NOT push again — the target is already in `result`,
    // so the RPC will cover this PG's data too.
    if !found {
      for target_key in locate {
        if tracker.get_status(target_key) != Failed {
          if !selected.contains(target_key) {
            result.push(target_key)
            selected.set(target_key, true)
          }
          // Either way, this PG is covered by an existing target
          break
        }
      }
    }
  }
  result
}

///|
/// List all target keys in the CRUSH map.
pub fn all_targets(
  crush_map : @placement.CrushMap,
) -> Array[@placement.TargetKey] {
  crush_map.targets.map(fn(t) { t.key })
}

// ── Rebalance planning ──────────────────────────────────────

///|
/// A single vector's rebalance action.
pub(all) struct RebalanceAction {
  id : @types.VectorId
  /// Targets that need to receive this vector (new placement − old placement).
  add_to : Array[@placement.TargetKey]
  /// Targets that should remove this vector (old placement − new placement).
  remove_from : Array[@placement.TargetKey]
}

///|
/// Compute rebalance actions for a set of vector IDs.
///
/// Compares old and new CRUSH placements for each ID and returns the
/// minimal set of target transfers needed.
pub fn compute_rebalance_plan(
  ids : Array[@types.VectorId],
  old_map : @placement.CrushMap,
  new_map : @placement.CrushMap,
) -> Array[RebalanceAction] {
  let actions : Array[RebalanceAction] = []
  for id in ids {
    let old_targets = targets_for_id(id, old_map)
    let new_targets = targets_for_id(id, new_map)
    let old_set : Map[@placement.TargetKey, Bool] = {}
    let new_set : Map[@placement.TargetKey, Bool] = {}
    for t in old_targets {
      old_set.set(t, true)
    }
    for t in new_targets {
      new_set.set(t, true)
    }
    let add_to : Array[@placement.TargetKey] = []
    let remove_from : Array[@placement.TargetKey] = []
    for t in new_targets {
      if !old_set.contains(t) {
        add_to.push(t)
      }
    }
    for t in old_targets {
      if !new_set.contains(t) {
        remove_from.push(t)
      }
    }
    if !add_to.is_empty() || !remove_from.is_empty() {
      actions.push({ id, add_to, remove_from })
    }
  }
  actions
}

///|
pub(all) struct RebalanceSummary {
  affected_vectors : Int
  total_additions : Int
  total_removals : Int
}

///|
pub fn summarize_rebalance(plan : Array[RebalanceAction]) -> RebalanceSummary {
  let mut additions = 0
  let mut removals = 0
  for action in plan {
    additions = additions + action.add_to.length()
    removals = removals + action.remove_from.length()
  }
  {
    affected_vectors: plan.length(),
    total_additions: additions,
    total_removals: removals,
  }
}
