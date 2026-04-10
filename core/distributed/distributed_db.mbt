///|
/// Async primitives for distributed operations.
async fn[T, E : Error] suspend(
  f : ((T) -> Unit, (E) -> Unit) -> Unit,
) -> T raise E = "%async.suspend"

///|
pub(all) suberror ShardError {
  ShardFailed(String)
}

///|
pub fn ShardError::to_string(self : ShardError) -> String {
  match self {
    ShardFailed(msg) => msg
  }
}

///|
/// DistributedDB — scatter-gather across target nodes with replication.
///
/// ## Architecture
///
/// - PG (placement group): logical data partition.
/// - Target: physical storage node (identified by target_key: String).
/// - CRUSH maps each PG to N target nodes (replicas).
/// - Each target holds data for exactly the PGs assigned to it.
/// - Reads query one healthy target per PG.
/// - Writes go to all targets for each PG's replicas.
///
/// ## Quorum semantics
///
/// N = replicas per PG (from CrushMap)
/// W = write quorum (replicas that must acknowledge per point)
/// R = read quorum (targets needed per PG for a successful read)
/// W + R > N → strong consistency

///|
pub struct DistributedDB[T] {
  crush_map : @placement.CrushMap
  quorum : QuorumConfig
  transport : T
  health : ShardHealthTracker
  partition_state : PartitionState
}

///|
/// Create a DistributedDB.
///
/// `pg_count`: number of placement groups (logical data partitions).
/// `targets`: physical storage nodes. Each target is identified by a key string.
/// `replicas`: how many targets hold each PG's data.
/// `write_quorum`: how many targets must acknowledge a write per point (default: replicas).
/// `read_quorum`: not used for fan-out reads (1 target per PG is always sufficient).
pub fn[T] DistributedDB::new(
  pg_count : Int,
  targets : Array[@placement.CrushTarget],
  transport : T,
  replicas? : Int = 1,
  write_quorum? : Int = 0,
  failure_threshold? : Int = 3,
) -> DistributedDB[T] {
  let effective_replicas = if replicas > targets.length() {
    targets.length()
  } else if replicas < 1 {
    1
  } else {
    replicas
  }
  let w = if write_quorum > 0 { write_quorum } else { effective_replicas }
  let target_keys = targets.map(fn(t) { t.key })
  {
    crush_map: @placement.CrushMap::new(pg_count, effective_replicas, targets),
    quorum: QuorumConfig::new(effective_replicas, w, 1),
    transport,
    health: ShardHealthTracker::new(target_keys, failure_threshold~),
    partition_state: PartitionState::new(target_keys),
  }
}

///|
/// Helper: execute a target operation with error handling and health tracking.
async fn[T, R] DistributedDB::exec_target(
  self : DistributedDB[T],
  target_key : @placement.TargetKey,
  timestamp_ns : Int64,
  op : ((R) -> Unit, (String) -> Unit) -> Unit,
) -> R? {
  let result : Result[R, _] = try? suspend(fn(resolve : (R) -> Unit, reject) {
    op(resolve, fn(err) { reject(ShardFailed(err)) })
  })
  match result {
    Ok(value) => {
      self.health.report_success(target_key, timestamp_ns)
      Some(value)
    }
    Err(msg) => {
      let err_str = msg.to_string()
      self.health.report_failure(target_key, timestamp_ns, err_str)
      self.partition_state.detect_partition(target_key, timestamp_ns)
      None
    }
  }
}

// ── Write operations (async, routed, quorum-aware) ─────────────

///|
/// Upsert points across targets with replication.
///
/// Each point is written to all its replica targets. Raises ShardError
/// if any point fails to reach W replicas.
pub async fn[T : ShardTransport] DistributedDB::upsert(
  self : DistributedDB[T],
  points : Array[TransportPoint],
  timestamp_ns : Int64,
) -> Unit raise ShardError {
  let groups = group_by_target(
    points.map(fn(p) { (p.id, p.vector, p.attrs) }),
    self.crush_map,
  )
  // Track which targets succeeded
  let target_ok : Map[@placement.TargetKey, Bool] = {}
  let mut last_error = ""
  // Fan out to targets
  for target_key in groups.keys() {
    match groups.get(target_key) {
      Some(target_points) => {
        let tp = target_points.map(fn(p) {
          let (id, vector, attrs) = p
          TransportPoint::{ id, vector, attrs }
        })
        let result : Result[Unit, _] = try? suspend(fn(
          resolve : (Unit) -> Unit,
          reject,
        ) {
          self.transport.shard_upsert(
            target_key,
            tp,
            timestamp_ns,
            fn() { resolve(()) },
            fn(err) { reject(ShardFailed(err)) },
          )
        })
        match result {
          Ok(_) => {
            self.health.report_success(target_key, timestamp_ns)
            target_ok.set(target_key, true)
          }
          Err(msg) => {
            last_error = msg.to_string()
            self.health.report_failure(target_key, timestamp_ns, last_error)
            self.partition_state.detect_partition(target_key, timestamp_ns)
          }
        }
      }
      None => ()
    }
  }
  // Verify per-point write quorum
  for point in points {
    let point_targets = targets_for_id(point.id, self.crush_map)
    let mut point_acks = 0
    for t in point_targets {
      if target_ok.contains(t) {
        point_acks = point_acks + 1
      }
    }
    if point_acks < self.quorum.w {
      raise ShardFailed(
        "Write quorum not met for point " +
        point.id.to_string() +
        ": " +
        point_acks.to_string() +
        "/" +
        self.quorum.w.to_string() +
        " replicas acknowledged. Last error: " +
        last_error,
      )
    }
  }
}

///|
/// Remove a vector from all replica targets.
pub async fn[T : ShardTransport] DistributedDB::remove(
  self : DistributedDB[T],
  id : @types.VectorId,
  timestamp_ns : Int64,
) -> Bool {
  let replica_targets = targets_for_id(id, self.crush_map)
  let mut any_removed = false
  for target_key in replica_targets {
    match
      self.exec_target(target_key, timestamp_ns, fn(resolve, reject) {
        self.transport.shard_remove(
          target_key, id, timestamp_ns, resolve, reject,
        )
      }) {
      Some(removed) => if removed { any_removed = true }
      None => ()
    }
  }
  any_removed
}

// ── Read operations (async, one target per PG) ─────────────────

///|
/// Search across targets, one per PG.
///
/// select_read_targets picks one healthy target per PG, so each PG's
/// data is queried exactly once. No dedup division needed.
pub async fn[T : ShardTransport] DistributedDB::search(
  self : DistributedDB[T],
  query : Array[Double],
  top_k : Int,
  filter_json? : String = "",
  timestamp_ns? : Int64 = 0L,
) -> MergedSearchResult {
  let targets = select_read_targets(self.crush_map, self.health)
  let shard_results : Array[ShardSearchResult] = []
  for target_key in targets {
    match
      self.exec_target(target_key, timestamp_ns, fn(resolve, reject) {
        self.transport.shard_search(
          target_key, query, top_k, filter_json, resolve, reject,
        )
      }) {
      Some(hits) => shard_results.push({ target_key, hits, error: None })
      None =>
        shard_results.push({
          target_key,
          hits: [],
          error: Some("target unreachable"),
        })
    }
  }
  merge_search(shard_results, top_k)
}

///|
/// Get a vector from any target that holds it.
///
/// Tries each replica target. Returns as soon as one positively confirms
/// the record exists. Returns None only after all replicas are exhausted.
pub async fn[T : ShardTransport] DistributedDB::get(
  self : DistributedDB[T],
  id : @types.VectorId,
  timestamp_ns? : Int64 = 0L,
) -> @types.VectorRecord? {
  let replica_targets = targets_for_id(id, self.crush_map)
  for target_key in replica_targets {
    match
      self.exec_target(target_key, timestamp_ns, fn(resolve, reject) {
        self.transport.shard_get(target_key, id, resolve, reject)
      }) {
      Some(Some(record)) => return Some(record)
      Some(None) => continue // Target responded but doesn't have it
      None => continue // Target failed
    }
  }
  None
}

///|
/// Check if a vector exists on any replica target.
pub async fn[T : ShardTransport] DistributedDB::has(
  self : DistributedDB[T],
  id : @types.VectorId,
  timestamp_ns? : Int64 = 0L,
) -> Bool {
  let replica_targets = targets_for_id(id, self.crush_map)
  for target_key in replica_targets {
    match
      self.exec_target(target_key, timestamp_ns, fn(resolve, reject) {
        self.transport.shard_has(target_key, id, resolve, reject)
      }) {
      Some(found) => if found { return true }
      None => continue
    }
  }
  false
}

///|
/// Scroll across targets, one per PG.
pub async fn[T : ShardTransport] DistributedDB::scroll_filtered(
  self : DistributedDB[T],
  filter_json? : String = "",
  offset? : Int64? = None,
  limit? : Int = 10,
  timestamp_ns? : Int64 = 0L,
) -> MergedScrollResult {
  let targets = select_read_targets(self.crush_map, self.health)
  let shard_results : Array[ShardScrollResult] = []
  for target_key in targets {
    match
      self.exec_target(target_key, timestamp_ns, fn(resolve, reject) {
        self.transport.shard_scroll(
          target_key, filter_json, offset, limit, resolve, reject,
        )
      }) {
      Some(entries) => shard_results.push({ target_key, entries, error: None })
      None =>
        shard_results.push({
          target_key,
          entries: [],
          error: Some("target unreachable"),
        })
    }
  }
  merge_scroll(shard_results, limit)
}

///|
/// Count across targets, one per PG.
///
/// Since each PG is queried exactly once, the sum of counts is the
/// true unique count. No division needed.
pub async fn[T : ShardTransport] DistributedDB::count_filtered(
  self : DistributedDB[T],
  filter_json? : String = "",
  timestamp_ns? : Int64 = 0L,
) -> MergedCountResult {
  let targets = select_read_targets(self.crush_map, self.health)
  let shard_results : Array[ShardCountResult] = []
  for target_key in targets {
    match
      self.exec_target(target_key, timestamp_ns, fn(resolve, reject) {
        self.transport.shard_count(target_key, filter_json, resolve, reject)
      }) {
      Some(count) => shard_results.push({ target_key, count, error: None })
      None =>
        shard_results.push({
          target_key,
          count: 0,
          error: Some("target unreachable"),
        })
    }
  }
  merge_count(shard_results)
}

// ── Diagnostics ─────────────────────────────────────────────────

///|
pub fn[T] DistributedDB::all_health(
  self : DistributedDB[T],
) -> Array[ShardHealth] {
  self.health.all_health()
}

///|
pub fn[T] DistributedDB::failed_targets(
  self : DistributedDB[T],
) -> Array[@placement.TargetKey] {
  self.health.failed_targets()
}

///|
pub fn[T] DistributedDB::partitioned_targets(
  self : DistributedDB[T],
) -> Array[(@placement.TargetKey, Int64)] {
  self.partition_state.partitioned_targets()
}

///|
pub fn[T] DistributedDB::resolve_partition(
  self : DistributedDB[T],
  target_key : @placement.TargetKey,
) -> Unit {
  self.partition_state.resolve_partition(target_key)
}

///|
pub fn[T] DistributedDB::target_count(self : DistributedDB[T]) -> Int {
  self.crush_map.targets.length()
}

///|
pub fn[T] DistributedDB::pg_count(self : DistributedDB[T]) -> Int {
  self.crush_map.pgs
}

///|
pub fn[T] DistributedDB::replicas(self : DistributedDB[T]) -> Int {
  self.crush_map.replicas
}

///|
/// Get all target keys that hold a vector ID.
pub fn[T] DistributedDB::targets_for(
  self : DistributedDB[T],
  id : @types.VectorId,
) -> Array[@placement.TargetKey] {
  targets_for_id(id, self.crush_map)
}

///|
/// Get the quorum configuration.
pub fn[T] DistributedDB::quorum_config(self : DistributedDB[T]) -> QuorumConfig {
  self.quorum
}
