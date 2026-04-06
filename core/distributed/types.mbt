///|
/// Types for distributed vector database operations.
///
/// These types represent the inputs and outputs of scatter-gather
/// across multiple shards. Each shard returns a partial result;
/// the merge layer combines them into a unified result.

///|
/// Result from a single shard's search operation.
pub(all) struct ShardSearchResult {
  shard_id : Int
  hits : Array[@types.SearchHit]
  /// None = success, Some(msg) = shard reported an error.
  /// Partial failures are tolerated — the merge includes whatever
  /// successful shards returned.
  error : String?
}

///|
/// Result from a single shard's scroll operation.
pub(all) struct ShardScrollEntry {
  id : @types.VectorId
  attrs : @types.Attrs
}

///|
pub(all) struct ShardScrollResult {
  shard_id : Int
  entries : Array[ShardScrollEntry]
  error : String?
}

///|
/// Result from a single shard's count operation.
pub(all) struct ShardCountResult {
  shard_id : Int
  count : Int
  error : String?
}

///|
/// Merged result with metadata about which shards participated.
pub(all) struct MergedSearchResult {
  hits : Array[@types.SearchHit]
  /// Shard IDs that returned successfully.
  succeeded : Array[Int]
  /// Shard IDs that failed (with error messages).
  failed : Array[(Int, String)]
}

///|
pub(all) struct MergedScrollResult {
  entries : Array[ShardScrollEntry]
  succeeded : Array[Int]
  failed : Array[(Int, String)]
}

///|
pub(all) struct MergedCountResult {
  count : Int
  succeeded : Array[Int]
  failed : Array[(Int, String)]
}
