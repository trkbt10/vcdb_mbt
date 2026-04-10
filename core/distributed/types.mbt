///|
/// Types for distributed vector database operations.
///
/// These types represent the inputs and outputs of scatter-gather
/// across multiple target nodes. Each target returns a partial result;
/// the merge layer combines them into a unified result.
///
/// ## Naming convention
///
/// - `target_key`: A physical storage node identifier (String).
///   Corresponds to CrushTarget.key in the CRUSH map.
/// - `pg`: Placement group number (Int). A logical data partition.
///   CRUSH maps each PG to one or more target nodes.
///
/// Target keys are the routing primitive. PG numbers only appear
/// in CRUSH computation; once a target is chosen, all downstream
/// operations use target_key.

///|
/// Result from a single target's search operation.
pub(all) struct ShardSearchResult {
  target_key : @placement.TargetKey
  hits : Array[@types.SearchHit]
  /// None = success, Some(msg) = target reported an error.
  error : String?
}

///|
/// Result from a single target's scroll operation.
pub(all) struct ShardScrollEntry {
  id : @types.VectorId
  attrs : @types.Attrs
}

///|
pub(all) struct ShardScrollResult {
  target_key : @placement.TargetKey
  entries : Array[ShardScrollEntry]
  error : String?
}

///|
/// Result from a single target's count operation.
pub(all) struct ShardCountResult {
  target_key : @placement.TargetKey
  count : Int
  error : String?
}

///|
/// Merged result with metadata about which targets participated.
pub(all) struct MergedSearchResult {
  hits : Array[@types.SearchHit]
  /// Target keys that returned successfully.
  succeeded : Array[@placement.TargetKey]
  /// Target keys that failed (with error messages).
  failed : Array[(@placement.TargetKey, String)]
}

///|
pub(all) struct MergedScrollResult {
  entries : Array[ShardScrollEntry]
  succeeded : Array[@placement.TargetKey]
  failed : Array[(@placement.TargetKey, String)]
}

///|
pub(all) struct MergedCountResult {
  count : Int
  succeeded : Array[@placement.TargetKey]
  failed : Array[(@placement.TargetKey, String)]
}
