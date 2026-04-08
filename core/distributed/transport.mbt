///|
/// Shard transport trait — abstracts communication with shard instances.
///
/// Platform adapters implement this trait to provide shard-level operations:
///   - Cloudflare: DO RPC calls
///   - HTTP: fetch to shard endpoints
///   - Local: direct PersistentDB method calls (testing, single-process)
///
/// All operations are async (continuation-passing style), matching
/// the AsyncStorage pattern used throughout vcdb.
///
/// Each method receives a shard index and operation parameters.
/// The transport is responsible for routing to the correct shard instance.

///|
pub(open) trait ShardTransport {
  /// Upsert points into a specific shard.
  shard_upsert(
    Self,
    Int,
    Array[TransportPoint],
    Int64,
    () -> Unit,
    (String) -> Unit,
  ) -> Unit

  /// Search a specific shard. Returns hits via resolve callback.
  shard_search(
    Self,
    Int,
    Array[Double],
    Int,
    String,
    (Array[@types.SearchHit]) -> Unit,
    (String) -> Unit,
  ) -> Unit

  /// Get a vector from a specific shard.
  shard_get(
    Self,
    Int,
    @types.VectorId,
    (@types.VectorRecord?) -> Unit,
    (String) -> Unit,
  ) -> Unit

  /// Check if a vector exists on a specific shard.
  shard_has(Self, Int, @types.VectorId, (Bool) -> Unit, (String) -> Unit) -> Unit

  /// Remove a vector from a specific shard.
  shard_remove(
    Self,
    Int,
    @types.VectorId,
    Int64,
    (Bool) -> Unit,
    (String) -> Unit,
  ) -> Unit

  /// Scroll entries from a specific shard.
  shard_scroll(
    Self,
    Int,
    String,
    Int64?,
    Int,
    (Array[ShardScrollEntry]) -> Unit,
    (String) -> Unit,
  ) -> Unit

  /// Count filtered entries on a specific shard.
  shard_count(Self, Int, String, (Int) -> Unit, (String) -> Unit) -> Unit
}
