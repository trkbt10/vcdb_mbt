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
/// DistributedDB — scatter-gather across multiple shards.
///
/// Integrates the distributed primitives (router, merge, health, partition)
/// into a single coordinated type. Platform adapters provide a ShardTransport
/// implementation; DistributedDB handles:
///
///   - CRUSH-based routing (which shard owns which vector)
///   - Fan-out to healthy shards for search/scroll/count
///   - Result merging across shards
///   - Health tracking (success/failure per shard)
///   - Partition detection and recovery planning
///
/// When shard_count=1, DistributedDB degrades to a passthrough — all
/// operations go to shard 0 with no merge overhead.

///|
pub struct DistributedDB[T] {
  shard_count : Int
  crush_map : @placement.CrushMap
  transport : T
  health : ShardHealthTracker
  partition_state : PartitionState
}

///|
pub fn[T] DistributedDB::new(
  shard_count : Int,
  transport : T,
  failure_threshold? : Int = 3,
) -> DistributedDB[T] {
  {
    shard_count,
    crush_map: @placement.CrushMap::new(shard_count, 1, []),
    transport,
    health: ShardHealthTracker::new(shard_count, failure_threshold~),
    partition_state: PartitionState::new(shard_count),
  }
}

///|
/// Helper: execute a shard operation with error handling and health tracking.
async fn[T, R] DistributedDB::exec_shard(
  self : DistributedDB[T],
  shard_id : Int,
  timestamp_ns : Int64,
  op : ((R) -> Unit, (String) -> Unit) -> Unit,
) -> R? {
  let result : Result[R, _] = try? suspend(fn(resolve : (R) -> Unit, reject) {
    op(resolve, fn(err) { reject(ShardFailed(err)) })
  })
  match result {
    Ok(value) => {
      self.health.report_success(shard_id, timestamp_ns)
      Some(value)
    }
    Err(msg) => {
      let err_str = msg.to_string()
      self.health.report_failure(shard_id, timestamp_ns, err_str)
      self.partition_state.detect_partition(shard_id, timestamp_ns)
      None
    }
  }
}

// ── Write operations (async, routed) ────────────────────────────

///|
/// Upsert points across shards.
/// Groups points by CRUSH placement, fans out to each shard.
pub async fn[T : ShardTransport] DistributedDB::upsert(
  self : DistributedDB[T],
  points : Array[TransportPoint],
  timestamp_ns : Int64,
) -> Unit {
  let groups = group_by_shard(
    points.map(fn(p) { (p.id, p.vector, p.attrs) }),
    self.crush_map,
  )
  for shard_id in groups.keys() {
    match groups.get(shard_id) {
      Some(shard_points) => {
        let tp = shard_points.map(fn(p) {
          let (id, vector, attrs) = p
          TransportPoint::{ id, vector, attrs }
        })
        let result : Result[Unit, _] = try? suspend(fn(
          resolve : (Unit) -> Unit,
          reject,
        ) {
          self.transport.shard_upsert(
            shard_id,
            tp,
            timestamp_ns,
            fn() { resolve(()) },
            fn(err) { reject(ShardFailed(err)) },
          )
        })
        match result {
          Ok(_) => self.health.report_success(shard_id, timestamp_ns)
          Err(msg) => {
            self.health.report_failure(shard_id, timestamp_ns, msg.to_string())
            self.partition_state.detect_partition(shard_id, timestamp_ns)
          }
        }
      }
      None => ()
    }
  }
}

///|
/// Remove a vector from the owning shard.
pub async fn[T : ShardTransport] DistributedDB::remove(
  self : DistributedDB[T],
  id : @types.VectorId,
  timestamp_ns : Int64,
) -> Bool {
  let shard_id = shard_for_id(id, self.crush_map)
  match
    self.exec_shard(shard_id, timestamp_ns, fn(resolve, reject) {
      self.transport.shard_remove(shard_id, id, timestamp_ns, resolve, reject)
    }) {
    Some(removed) => removed
    None => false
  }
}

// ── Read operations (async, fan-out + merge) ────────────────────

///|
/// Search across all healthy shards, merge results.
pub async fn[T : ShardTransport] DistributedDB::search(
  self : DistributedDB[T],
  query : Array[Double],
  top_k : Int,
  filter_json? : String = "",
  timestamp_ns? : Int64 = 0L,
) -> MergedSearchResult {
  let shards = healthy_shards_for_fanout(self.crush_map, self.health)
  let shard_results : Array[ShardSearchResult] = []
  for shard_id in shards {
    match
      self.exec_shard(shard_id, timestamp_ns, fn(resolve, reject) {
        self.transport.shard_search(
          shard_id, query, top_k, filter_json, resolve, reject,
        )
      }) {
      Some(hits) => shard_results.push({ shard_id, hits, error: None })
      None =>
        shard_results.push({
          shard_id,
          hits: [],
          error: Some("shard unreachable"),
        })
    }
  }
  merge_search(shard_results, top_k)
}

///|
/// Get a vector from the owning shard.
pub async fn[T : ShardTransport] DistributedDB::get(
  self : DistributedDB[T],
  id : @types.VectorId,
  timestamp_ns? : Int64 = 0L,
) -> @types.VectorRecord? {
  let shard_id = shard_for_id(id, self.crush_map)
  match
    self.exec_shard(shard_id, timestamp_ns, fn(resolve, reject) {
      self.transport.shard_get(shard_id, id, resolve, reject)
    }) {
    Some(record) => record
    None => None
  }
}

///|
/// Check if a vector exists on the owning shard.
pub async fn[T : ShardTransport] DistributedDB::has(
  self : DistributedDB[T],
  id : @types.VectorId,
  timestamp_ns? : Int64 = 0L,
) -> Bool {
  let shard_id = shard_for_id(id, self.crush_map)
  match
    self.exec_shard(shard_id, timestamp_ns, fn(resolve, reject) {
      self.transport.shard_has(shard_id, id, resolve, reject)
    }) {
    Some(found) => found
    None => false
  }
}

///|
/// Scroll across all healthy shards, merge results.
pub async fn[T : ShardTransport] DistributedDB::scroll_filtered(
  self : DistributedDB[T],
  filter_json? : String = "",
  offset? : Int64? = None,
  limit? : Int = 10,
  timestamp_ns? : Int64 = 0L,
) -> MergedScrollResult {
  let shards = healthy_shards_for_fanout(self.crush_map, self.health)
  let shard_results : Array[ShardScrollResult] = []
  for shard_id in shards {
    match
      self.exec_shard(shard_id, timestamp_ns, fn(resolve, reject) {
        self.transport.shard_scroll(
          shard_id, filter_json, offset, limit, resolve, reject,
        )
      }) {
      Some(entries) => shard_results.push({ shard_id, entries, error: None })
      None =>
        shard_results.push({
          shard_id,
          entries: [],
          error: Some("shard unreachable"),
        })
    }
  }
  merge_scroll(shard_results, limit)
}

///|
/// Count across all healthy shards, merge results.
pub async fn[T : ShardTransport] DistributedDB::count_filtered(
  self : DistributedDB[T],
  filter_json? : String = "",
  timestamp_ns? : Int64 = 0L,
) -> MergedCountResult {
  let shards = healthy_shards_for_fanout(self.crush_map, self.health)
  let shard_results : Array[ShardCountResult] = []
  for shard_id in shards {
    match
      self.exec_shard(shard_id, timestamp_ns, fn(resolve, reject) {
        self.transport.shard_count(shard_id, filter_json, resolve, reject)
      }) {
      Some(count) => shard_results.push({ shard_id, count, error: None })
      None =>
        shard_results.push({
          shard_id,
          count: 0,
          error: Some("shard unreachable"),
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
pub fn[T] DistributedDB::failed_shards(self : DistributedDB[T]) -> Array[Int] {
  self.health.failed_shards()
}

///|
pub fn[T] DistributedDB::partitioned_shards(
  self : DistributedDB[T],
) -> Array[(Int, Int64)] {
  self.partition_state.partitioned_shards()
}

///|
pub fn[T] DistributedDB::resolve_partition(
  self : DistributedDB[T],
  shard_id : Int,
) -> Unit {
  self.partition_state.resolve_partition(shard_id)
}

///|
pub fn[T] DistributedDB::shard_count(self : DistributedDB[T]) -> Int {
  self.shard_count
}

///|
pub fn[T] DistributedDB::shard_for(
  self : DistributedDB[T],
  id : @types.VectorId,
) -> Int {
  shard_for_id(id, self.crush_map)
}
