///|
/// Shard transport trait — abstracts communication with target nodes.
///
/// Platform adapters implement this trait to provide target-level operations:
///   - Cloudflare: DO RPC calls (target_key = DO shard name)
///   - HTTP: fetch to target endpoints (target_key = URL)
///   - Local: direct PersistentDB method calls (target_key = instance name)
///
/// All operations are async (continuation-passing style), matching
/// the AsyncStorage pattern used throughout vcdb.
///
/// Each method receives a TargetKey identifying the physical node.
/// The transport is responsible for routing to the correct node instance.

///|
pub(open) trait ShardTransport {
  /// Upsert points into a specific target node.
  shard_upsert(
    Self,
    @placement.TargetKey,
    Array[TransportPoint],
    Int64,
    () -> Unit,
    (String) -> Unit,
  ) -> Unit

  /// Search a specific target node. Returns hits via resolve callback.
  shard_search(
    Self,
    @placement.TargetKey,
    Array[Double],
    Int,
    String,
    (Array[@types.SearchHit]) -> Unit,
    (String) -> Unit,
  ) -> Unit

  /// Get a vector from a specific target node.
  shard_get(
    Self,
    @placement.TargetKey,
    @types.VectorId,
    (@types.VectorRecord?) -> Unit,
    (String) -> Unit,
  ) -> Unit

  /// Check if a vector exists on a specific target node.
  shard_has(
    Self,
    @placement.TargetKey,
    @types.VectorId,
    (Bool) -> Unit,
    (String) -> Unit,
  ) -> Unit

  /// Remove a vector from a specific target node.
  shard_remove(
    Self,
    @placement.TargetKey,
    @types.VectorId,
    Int64,
    (Bool) -> Unit,
    (String) -> Unit,
  ) -> Unit

  /// Scroll entries from a specific target node.
  shard_scroll(
    Self,
    @placement.TargetKey,
    String,
    Int64?,
    Int,
    (Array[ShardScrollEntry]) -> Unit,
    (String) -> Unit,
  ) -> Unit

  /// Count filtered entries on a specific target node.
  shard_count(
    Self,
    @placement.TargetKey,
    String,
    (Int) -> Unit,
    (String) -> Unit,
  ) -> Unit
}
