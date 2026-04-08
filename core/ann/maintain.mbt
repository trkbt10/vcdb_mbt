///|
/// Maintenance operations for ANN indices
/// - HNSW compaction: Remove deleted entries and rebuild the graph
/// - IVF retraining: Recompute centroids and reassign vectors

///|
/// Compact HNSW index by removing tombstoned entries and rebuilding
/// Returns the number of removed entries
pub fn hnsw_compact_and_rebuild(
  state : HNSWState,
  store : @store.CoreStore,
) -> (HNSWState, Int) {
  let n = store.size()
  if n == 0 {
    return (state, 0)
  }
  // Count alive vectors
  let mut alive = 0
  for i in 0..<n {
    if i >= state.tombstone.length() || !state.tombstone[i] {
      alive = alive + 1
    }
  }
  if alive == n {
    return (state, 0)
  }
  // Create new HNSW state (use default seed 42 for rebuild)
  let new_state = HNSWState::new(
    @types.HNSWParams::{
      m: state.m,
      ef_construction: state.ef_construction,
      ef_search: state.ef_search,
      level_mult: state.level_mult,
      seed: 42UL,
      allow_replace_deleted: state.allow_replace_deleted,
    },
    state.metric,
    if alive > 0 {
      alive
    } else {
      1
    },
  )
  // Re-add non-tombstoned vectors, mark skipped as tombstoned
  for i in 0..<n {
    if i < state.tombstone.length() && state.tombstone[i] {
      // Mark as tombstoned in new state to prevent ghost entries
      new_state.ensure_capacity(i + 1)
      new_state.tombstone[i] = true
      continue
    }
    let id = store.ids[i]
    hnsw_add(new_state, store, id)
  }
  (new_state, n - alive)
}

///|
/// Retrain IVF centroids using current vectors in store
/// Returns the number of centroid updates
pub fn ivf_retrain(
  state : IVFState,
  store : @store.CoreStore,
  iterations : Int,
) -> Int {
  if store.size() == 0 {
    return 0
  }
  // Train new centroids
  ivf_train(state, store, iterations~)
  // Clear existing lists
  for list in state.lists {
    list.clear()
  }
  state.id_to_list.clear()
  // Reassign all vectors to new centroids using ivf_assign (no bootstrap)
  let mut reassigned = 0
  for i in 0..<store.size() {
    let id = store.ids[i]
    ivf_assign(state, store, id)
    reassigned = reassigned + 1
  }
  reassigned
}

///|
/// Rebuild IVF index with new parameters
pub fn ivf_rebuild(
  store : @store.CoreStore,
  params : @types.IVFParams,
  metric : @types.Metric,
  iterations : Int,
) -> IVFState {
  let state = IVFState::new(params, metric, store.dim)
  if store.size() > 0 {
    ivf_train(state, store, iterations~)
    // Use ivf_assign to assign vectors to trained centroids (no bootstrap)
    for i in 0..<store.size() {
      let id = store.ids[i]
      ivf_assign(state, store, id)
    }
  }
  state
}

///|
/// Rebuild HNSW index from scratch
pub fn hnsw_rebuild(
  store : @store.CoreStore,
  params : @types.HNSWParams,
  metric : @types.Metric,
) -> HNSWState {
  let cap = if store.size() > 0 { store.size() } else { 1 }
  let state = HNSWState::new(params, metric, cap)
  for i in 0..<store.size() {
    let id = store.ids[i]
    hnsw_add(state, store, id)
  }
  state
}

///|
/// Get statistics about HNSW tombstones
pub fn hnsw_tombstone_stats(
  state : HNSWState,
  store : @store.CoreStore,
) -> (Int, Int) {
  let n = store.size()
  let mut dead = 0
  for i in 0..<n {
    if i < state.tombstone.length() && state.tombstone[i] {
      dead = dead + 1
    }
  }
  (n - dead, dead) // (alive, dead)
}
