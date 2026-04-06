///|
/// Shard health tracking for distributed vector database.
///
/// Tracks the health state of each shard and supports state transitions:
///   Healthy → Degraded (on first failure)
///   Degraded → Failed (consecutive failures ≥ threshold)
///   Failed → Healthy (on success report)
///   Degraded → Healthy (on success report)
///
/// Platform adapters call report_success / report_failure after each
/// shard RPC. The router uses the tracker to exclude failed shards
/// from fan-out operations.

///|
/// Shard health status.
pub(all) enum ShardStatus {
  /// Shard is responding normally.
  Healthy
  /// Shard has experienced failures but is below the failure threshold.
  Degraded
  /// Shard has exceeded the failure threshold and is considered unavailable.
  Failed
} derive(Eq, Show)

///|
/// Health information for a single shard.
pub(all) struct ShardHealth {
  shard_id : Int
  status : ShardStatus
  /// Timestamp of the last successful response (nanoseconds since epoch).
  last_success_ts : Int64
  /// Timestamp of the last failure (nanoseconds since epoch).
  last_failure_ts : Int64
  /// Number of consecutive failures without a success.
  consecutive_failures : Int
  /// Most recent error message, if any.
  last_error : String?
}

///|
/// Tracks health state for all shards in a distributed deployment.
///
/// - `failure_threshold`: consecutive failures required to transition to Failed
/// - Transitions are immediate on success (any failed/degraded shard recovers)
pub(all) struct ShardHealthTracker {
  shards : Map[Int, ShardHealth]
  /// Number of consecutive failures before a shard is marked Failed.
  failure_threshold : Int
}

///|
/// Create a new tracker with all shards initially Healthy.
pub fn ShardHealthTracker::new(
  shard_count : Int,
  failure_threshold? : Int = 3,
) -> ShardHealthTracker {
  let shards : Map[Int, ShardHealth] = {}
  for i in 0..<shard_count {
    shards[i] = {
      shard_id: i,
      status: Healthy,
      last_success_ts: 0L,
      last_failure_ts: 0L,
      consecutive_failures: 0,
      last_error: None,
    }
  }
  { shards, failure_threshold }
}

///|
/// Report a successful response from a shard.
/// Resets failure count and transitions to Healthy regardless of previous state.
pub fn ShardHealthTracker::report_success(
  self : ShardHealthTracker,
  shard_id : Int,
  ts : Int64,
) -> Unit {
  match self.shards.get(shard_id) {
    Some(health) =>
      self.shards[shard_id] = {
        ..health,
        status: Healthy,
        last_success_ts: ts,
        consecutive_failures: 0,
        last_error: None,
      }
    None => ()
  }
}

///|
/// Report a failure from a shard.
/// Increments consecutive failure count and transitions:
///   Healthy → Degraded (first failure)
///   Degraded → Failed (at threshold)
///   Failed stays Failed (but updates error/timestamp)
pub fn ShardHealthTracker::report_failure(
  self : ShardHealthTracker,
  shard_id : Int,
  ts : Int64,
  error : String,
) -> Unit {
  match self.shards.get(shard_id) {
    Some(health) => {
      let new_failures = health.consecutive_failures + 1
      let new_status = if new_failures >= self.failure_threshold {
        Failed
      } else {
        Degraded
      }
      self.shards[shard_id] = {
        ..health,
        status: new_status,
        last_failure_ts: ts,
        consecutive_failures: new_failures,
        last_error: Some(error),
      }
    }
    None => ()
  }
}

///|
/// Get the current status of a specific shard.
pub fn ShardHealthTracker::get_status(
  self : ShardHealthTracker,
  shard_id : Int,
) -> ShardStatus {
  match self.shards.get(shard_id) {
    Some(health) => health.status
    None => Failed // Unknown shard is treated as Failed
  }
}

///|
/// Get the full health record for a specific shard.
pub fn ShardHealthTracker::get_health(
  self : ShardHealthTracker,
  shard_id : Int,
) -> ShardHealth? {
  self.shards.get(shard_id)
}

///|
/// Return shard IDs that are not Failed (Healthy or Degraded).
/// These are the shards available for fan-out operations.
pub fn ShardHealthTracker::healthy_shards(
  self : ShardHealthTracker,
) -> Array[Int] {
  let result : Array[Int] = []
  for shard_id in self.shards.keys() {
    match self.shards.get(shard_id) {
      Some(health) =>
        if health.status != Failed {
          result.push(shard_id)
        }
      None => ()
    }
  }
  result.sort()
  result
}

///|
/// Return shard IDs that are Failed.
pub fn ShardHealthTracker::failed_shards(
  self : ShardHealthTracker,
) -> Array[Int] {
  let result : Array[Int] = []
  for shard_id in self.shards.keys() {
    match self.shards.get(shard_id) {
      Some(health) =>
        if health.status == Failed {
          result.push(shard_id)
        }
      None => ()
    }
  }
  result.sort()
  result
}

///|
/// Return health information for all shards, sorted by shard_id.
pub fn ShardHealthTracker::all_health(
  self : ShardHealthTracker,
) -> Array[ShardHealth] {
  let result : Array[ShardHealth] = []
  let keys = self.shards.keys().collect()
  keys.sort()
  for shard_id in keys {
    match self.shards.get(shard_id) {
      Some(health) => result.push(health)
      None => ()
    }
  }
  result
}

///|
/// Total number of tracked shards.
pub fn ShardHealthTracker::shard_count(
  self : ShardHealthTracker,
) -> Int {
  self.shards.length()
}
