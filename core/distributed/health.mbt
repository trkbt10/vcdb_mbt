///|
/// Target health tracking for distributed vector database.
///
/// Tracks the health state of each target node and supports state transitions:
///   Healthy → Degraded (on first failure)
///   Degraded → Failed (consecutive failures ≥ threshold)
///   Failed → Healthy (on success report)
///   Degraded → Healthy (on success report)
///
/// Platform adapters call report_success / report_failure after each
/// target RPC. The router uses the tracker to exclude failed targets
/// from fan-out operations.

///|
/// Target health status.
pub(all) enum ShardStatus {
  /// Target is responding normally.
  Healthy
  /// Target has experienced failures but is below the failure threshold.
  Degraded
  /// Target has exceeded the failure threshold and is considered unavailable.
  Failed
} derive(Eq, Debug)

///|
pub impl Show for ShardStatus with output(self, logger) {
  match self {
    Healthy => logger.write_string("Healthy")
    Degraded => logger.write_string("Degraded")
    Failed => logger.write_string("Failed")
  }
}

///|
/// Health information for a single target node.
pub(all) struct ShardHealth {
  target_key : @placement.TargetKey
  status : ShardStatus
  /// Timestamp of the last successful response (nanoseconds since epoch).
  last_success_ts : Int64
  /// Timestamp of the last failure (nanoseconds since epoch).
  last_failure_ts : Int64
  /// Number of consecutive failures without a success.
  consecutive_failures : Int
  /// Most recent error message, if any.
  last_error : String?
} derive(Debug)

///|
/// Tracks health state for all targets in a distributed deployment.
///
/// - `failure_threshold`: consecutive failures required to transition to Failed
/// - Transitions are immediate on success (any failed/degraded target recovers)
pub(all) struct ShardHealthTracker {
  targets : Map[@placement.TargetKey, ShardHealth]
  /// Number of consecutive failures before a target is marked Failed.
  failure_threshold : Int
}

///|
/// Create a new tracker with the given target keys, all initially Healthy.
pub fn ShardHealthTracker::new(
  target_keys : Array[@placement.TargetKey],
  failure_threshold? : Int = 3,
) -> ShardHealthTracker {
  let targets : Map[@placement.TargetKey, ShardHealth] = {}
  for key in target_keys {
    targets[key] = {
      target_key: key,
      status: Healthy,
      last_success_ts: 0L,
      last_failure_ts: 0L,
      consecutive_failures: 0,
      last_error: None,
    }
  }
  { targets, failure_threshold }
}

///|
/// Report a successful response from a target.
/// Resets failure count and transitions to Healthy regardless of previous state.
pub fn ShardHealthTracker::report_success(
  self : ShardHealthTracker,
  target_key : @placement.TargetKey,
  ts : Int64,
) -> Unit {
  match self.targets.get(target_key) {
    Some(health) =>
      self.targets[target_key] = {
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
/// Report a failure from a target.
/// Increments consecutive failure count and transitions:
///   Healthy → Degraded (first failure)
///   Degraded → Failed (at threshold)
///   Failed stays Failed (but updates error/timestamp)
pub fn ShardHealthTracker::report_failure(
  self : ShardHealthTracker,
  target_key : @placement.TargetKey,
  ts : Int64,
  error : String,
) -> Unit {
  match self.targets.get(target_key) {
    Some(health) => {
      let new_failures = health.consecutive_failures + 1
      let new_status = if new_failures >= self.failure_threshold {
        Failed
      } else {
        Degraded
      }
      self.targets[target_key] = {
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
/// Get the current status of a specific target.
pub fn ShardHealthTracker::get_status(
  self : ShardHealthTracker,
  target_key : @placement.TargetKey,
) -> ShardStatus {
  match self.targets.get(target_key) {
    Some(health) => health.status
    None => Failed // Unknown target is treated as Failed
  }
}

///|
/// Get the full health record for a specific target.
pub fn ShardHealthTracker::get_health(
  self : ShardHealthTracker,
  target_key : @placement.TargetKey,
) -> ShardHealth? {
  self.targets.get(target_key)
}

///|
/// Return target keys that are not Failed (Healthy or Degraded).
/// These are the targets available for fan-out operations.
pub fn ShardHealthTracker::healthy_targets(
  self : ShardHealthTracker,
) -> Array[@placement.TargetKey] {
  let result : Array[@placement.TargetKey] = []
  for key in self.targets.keys() {
    match self.targets.get(key) {
      Some(health) => if health.status != Failed { result.push(key) }
      None => ()
    }
  }
  result.sort()
  result
}

///|
/// Return target keys that are Failed.
pub fn ShardHealthTracker::failed_targets(
  self : ShardHealthTracker,
) -> Array[@placement.TargetKey] {
  let result : Array[@placement.TargetKey] = []
  for key in self.targets.keys() {
    match self.targets.get(key) {
      Some(health) => if health.status == Failed { result.push(key) }
      None => ()
    }
  }
  result.sort()
  result
}

///|
/// Return health information for all targets, sorted by target_key.
pub fn ShardHealthTracker::all_health(
  self : ShardHealthTracker,
) -> Array[ShardHealth] {
  let result : Array[ShardHealth] = []
  let keys = self.targets.keys().collect()
  keys.sort()
  for key in keys {
    match self.targets.get(key) {
      Some(health) => result.push(health)
      None => ()
    }
  }
  result
}

///|
/// Total number of tracked targets.
pub fn ShardHealthTracker::target_count(self : ShardHealthTracker) -> Int {
  self.targets.length()
}
