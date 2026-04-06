///|
/// Distributed shard routing.
///
/// Determines which shard(s) an operation targets using CRUSH placement.
/// This is the SoT for all shard routing decisions — platform adapters
/// (JS shard-router, native dispatcher) must use these functions rather
/// than implementing their own hash.

///|
/// Group upsert points by target shard using CRUSH placement.
///
/// Returns a map from shard index (placement group) to the points
/// that belong to that shard. Platform adapters dispatch each group
/// to the corresponding shard instance.
pub fn group_by_shard(
  points : Array[(@types.VectorId, Array[Double], @types.Attrs)],
  crush_map : @placement.CrushMap,
) -> Map[Int, Array[(@types.VectorId, Array[Double], @types.Attrs)]] {
  let groups : Map[Int, Array[(@types.VectorId, Array[Double], @types.Attrs)]] = {}
  for point in points {
    let (id, _, _) = point
    let result = @placement.crush_locate(id, crush_map)
    let pg = result.pg
    match groups.get(pg) {
      Some(arr) => arr.push(point)
      None => groups.set(pg, [point])
    }
  }
  groups
}

///|
/// Determine which shard owns a specific vector ID.
///
/// Used for single-vector operations (get, has, remove).
pub fn shard_for_id(
  id : @types.VectorId,
  crush_map : @placement.CrushMap,
) -> Int {
  let result = @placement.crush_locate(id, crush_map)
  result.pg
}

///|
/// List all shard indices for fan-out operations (search, scroll, count).
///
/// Returns [0, 1, ..., shard_count - 1] where shard_count is the
/// number of placement groups in the CRUSH map.
pub fn all_shards(crush_map : @placement.CrushMap) -> Array[Int] {
  let shards : Array[Int] = []
  for i in 0..<crush_map.pgs {
    shards.push(i)
  }
  shards
}
