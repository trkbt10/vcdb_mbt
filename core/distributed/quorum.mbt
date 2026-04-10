///|
/// Quorum semantics for distributed read/write operations.
///
/// Provides configurable consistency guarantees:
///   W + R > N → strong consistency (reads always see latest write)
///   W = N     → all replicas have every write
///   R = 1     → fastest reads (but W must = N for consistency)
///
/// All functions are pure computation. Platform adapters dispatch
/// RPCs to replicas and pass results here for quorum evaluation.

///|
/// Quorum configuration.
///
/// n = total replicas, w = write quorum, r = read quorum.
/// For strong consistency: w + r > n.
pub(all) struct QuorumConfig {
  n : Int
  w : Int
  r : Int
}

///|
/// Create a quorum config with validation.
///
/// Panics if parameters are invalid (w > n, r > n, or any <= 0).
pub fn QuorumConfig::new(n : Int, w : Int, r : Int) -> QuorumConfig {
  if n <= 0 || w <= 0 || r <= 0 {
    abort("QuorumConfig: n, w, r must all be > 0")
  }
  if w > n {
    abort("QuorumConfig: w (" + w.to_string() + ") > n (" + n.to_string() + ")")
  }
  if r > n {
    abort("QuorumConfig: r (" + r.to_string() + ") > n (" + n.to_string() + ")")
  }
  { n, w, r }
}

///|
/// Check if this config guarantees strong consistency.
pub fn QuorumConfig::is_strongly_consistent(self : QuorumConfig) -> Bool {
  self.w + self.r > self.n
}

///|
/// Result from writing to a single replica.
pub(all) struct ReplicaWriteResult {
  replica_key : String
  success : Bool
  error : String?
}

///|
/// Result from reading from a single replica.
pub(all) struct ReplicaReadResult {
  replica_key : String
  /// None indicates the replica returned no data or failed.
  value : Bytes?
  error : String?
}

///|
/// Evaluated write quorum result.
pub(all) struct QuorumWriteResult {
  /// Whether write quorum was achieved.
  quorum_met : Bool
  /// Number of replicas that acknowledged the write.
  achieved : Int
  /// Number of replicas required.
  required : Int
  /// Replica keys that succeeded.
  succeeded : Array[String]
  /// Replica keys that failed, with error messages.
  failed : Array[(String, String)]
}

///|
/// Evaluated read quorum result.
pub(all) struct QuorumReadResult {
  /// Whether read quorum was achieved.
  quorum_met : Bool
  /// The agreed-upon value (if quorum met and values are consistent).
  value : Bytes?
  /// Number of replicas that responded.
  achieved : Int
  /// Number of replicas required.
  required : Int
  /// Whether all responding replicas returned the same value.
  consistent : Bool
}

///|
/// Evaluate write results against quorum config.
///
/// Returns whether W replicas acknowledged the write.
pub fn evaluate_write_quorum(
  results : Array[ReplicaWriteResult],
  config : QuorumConfig,
) -> QuorumWriteResult {
  let succeeded : Array[String] = []
  let failed : Array[(String, String)] = []

  for result in results {
    if result.success {
      succeeded.push(result.replica_key)
    } else {
      let err_msg = match result.error {
        Some(msg) => msg
        None => "unknown error"
      }
      failed.push((result.replica_key, err_msg))
    }
  }

  {
    quorum_met: succeeded.length() >= config.w,
    achieved: succeeded.length(),
    required: config.w,
    succeeded,
    failed,
  }
}

///|
/// Evaluate read results against quorum config.
///
/// Checks that R replicas responded and that their values agree.
/// Agreement is determined by byte-level equality of the values.
pub fn evaluate_read_quorum(
  results : Array[ReplicaReadResult],
  config : QuorumConfig,
) -> QuorumReadResult {
  let valid_results : Array[(String, Bytes)] = []
  let mut error_count = 0

  for result in results {
    match (result.value, result.error) {
      (Some(v), None) => valid_results.push((result.replica_key, v))
      (Some(v), Some(_)) => {
        // Has both value and error — treat as error
        let _ = v
        error_count = error_count + 1
      }
      (None, _) => error_count = error_count + 1
    }
  }

  let achieved = valid_results.length()
  let quorum_met = achieved >= config.r

  // Check consistency: all valid values must match
  let consistent = if valid_results.length() <= 1 {
    true
  } else {
    let mut all_match = true
    let reference = valid_results[0].1
    for i = 1; i < valid_results.length(); i = i + 1 {
      if !bytes_equal(reference, valid_results[i].1) {
        all_match = false
        break
      }
    }
    all_match
  }

  let value = if quorum_met && consistent && valid_results.length() > 0 {
    Some(valid_results[0].1)
  } else {
    None
  }

  { quorum_met, value, achieved, required: config.r, consistent }
}

///|
/// Byte-level equality comparison.
fn bytes_equal(a : Bytes, b : Bytes) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i in 0..<a.length() {
    if a[i] != b[i] {
      return false
    }
  }
  true
}

///|
/// Select healthy replicas for a placement group's read operation.
///
/// Returns replica target keys that are not in `failed_keys`.
/// Order: same as CRUSH primaries (first is primary, rest are replicas).
///
/// The caller (platform adapter) is responsible for determining which
/// target keys are unreachable — typically by consulting a ShardHealthTracker
/// and mapping shard IDs to target keys. This keeps the quorum layer
/// independent of the shard↔target mapping convention.
pub fn select_read_replicas(
  id : @types.VectorId,
  crush_map : @placement.CrushMap,
  failed_keys : Array[@placement.TargetKey],
) -> Array[@placement.TargetKey] {
  let result = @placement.crush_locate(id, crush_map)
  let failed_set : Map[@placement.TargetKey, Bool] = {}
  for key in failed_keys {
    failed_set[key] = true
  }
  let healthy : Array[@placement.TargetKey] = []
  for key in result.primaries {
    if !failed_set.contains(key) {
      healthy.push(key)
    }
  }
  healthy
}

///|
/// Select all replicas for a write operation.
///
/// Writes must go to all replicas (the quorum evaluation determines
/// if enough acknowledged). Returns all CRUSH primaries for the ID.
pub fn select_write_replicas(
  id : @types.VectorId,
  crush_map : @placement.CrushMap,
) -> Array[@placement.TargetKey] {
  let result = @placement.crush_locate(id, crush_map)
  result.primaries
}
