///|
/// Distributed FFI exports — scatter-gather merge and routing.
///
/// Wire format for VectorId: Bytes of exactly 16 bytes.
/// See VectorId::to_wire_bytes / VectorId::from_wire_bytes for details.
///
/// These are synchronous pure functions (no I/O, no instance state).
///
/// FFI convention: Shard IDs at the FFI boundary are integers.
/// Internally we convert to TargetKey using the shard-id's string
/// representation ("0", "1", ...) so that the CRUSH/merge layer
/// (which now uses TargetKey) can operate uniformly.

///|
/// Convert an integer shard ID to a TargetKey for internal use.
fn shard_id_to_key(id : Int) -> @placement.TargetKey {
  @placement.TargetKey::new(id.to_string())
}

///|
/// Convert a TargetKey back to an integer shard ID for FFI output.
/// Falls back to -1 if the key does not parse as an integer.
fn key_to_shard_id(key : @placement.TargetKey) -> Int {
  let s = key.to_string()
  let result : Result[Int, _] = try? @string.parse_int(s)
  match result {
    Ok(n) => n
    Err(_) => -1
  }
}

// ── Merge: search ───────────────────────────────────────────

///|
/// Merge search results from multiple shards.
///
/// Each shard result: (shard_id, hits, error_or_empty)
/// Each hit: (id_bytes: Bytes, score: Double, payload_json: String)
/// Returns: (merged_hits, succeeded_shard_ids, failed: Array[(shard_id, error)])
pub fn distributed_merge_search(
  shard_results : Array[(Int, Array[(Bytes, Double, String)], String)],
  top_k : Int,
) -> (Array[(Bytes, Double, String)], Array[Int], Array[(Int, String)]) {
  let inputs : Array[@distributed.ShardSearchResult] = shard_results.map(fn(
    sr,
  ) {
    let (shard_id, raw_hits, error) = sr
    let hits = raw_hits.filter_map(fn(h) {
      let (id_bytes, score, payload_json) = h
      match @types.VectorId::from_wire_bytes(id_bytes) {
        Some(id) => {
          let attrs = parse_json_to_attrs(payload_json)
          Some(@types.SearchHit::{ id, score, attrs })
        }
        None => None
      }
    })
    let error_opt : String? = if error.length() > 0 {
      Some(error)
    } else {
      None
    }
    { target_key: shard_id_to_key(shard_id), hits, error: error_opt }
  })
  let merged = @distributed.merge_search(inputs, top_k)
  let out_hits = merged.hits.map(fn(hit) {
    let payload_json = @codec.attrs_to_json(Some(hit.attrs))
    (@types.VectorId::to_wire_bytes(hit.id), hit.score, payload_json)
  })
  let succeeded = merged.succeeded.map(fn(k) { key_to_shard_id(k) })
  let failed = merged.failed.map(fn(pair) {
    let (k, msg) = pair
    (key_to_shard_id(k), msg)
  })
  (out_hits, succeeded, failed)
}

// ── Merge: scroll ───────────────────────────────────────────

///|
/// Merge scroll results from multiple shards.
///
/// Each shard result: (shard_id, entries, error_or_empty)
/// Each entry: (id_bytes: Bytes, attrs_json: String)
/// Returns: (merged_entries, succeeded_shard_ids, failed)
pub fn distributed_merge_scroll(
  shard_results : Array[(Int, Array[(Bytes, String)], String)],
  limit : Int,
) -> (Array[(Bytes, String)], Array[Int], Array[(Int, String)]) {
  let inputs : Array[@distributed.ShardScrollResult] = shard_results.map(fn(
    sr,
  ) {
    let (shard_id, raw_entries, error) = sr
    let entries = raw_entries.filter_map(fn(e) {
      let (id_bytes, attrs_json) = e
      match @types.VectorId::from_wire_bytes(id_bytes) {
        Some(id) => {
          let attrs = parse_json_to_attrs(attrs_json)
          Some(@distributed.ShardScrollEntry::{ id, attrs })
        }
        None => None
      }
    })
    let error_opt : String? = if error.length() > 0 {
      Some(error)
    } else {
      None
    }
    { target_key: shard_id_to_key(shard_id), entries, error: error_opt }
  })
  let merged = @distributed.merge_scroll(inputs, limit)
  let out_entries = merged.entries.map(fn(entry) {
    let attrs_json = @codec.attrs_to_json(Some(entry.attrs))
    (@types.VectorId::to_wire_bytes(entry.id), attrs_json)
  })
  let succeeded = merged.succeeded.map(fn(k) { key_to_shard_id(k) })
  let failed = merged.failed.map(fn(pair) {
    let (k, msg) = pair
    (key_to_shard_id(k), msg)
  })
  (out_entries, succeeded, failed)
}

// ── Merge: count ────────────────────────────────────────────

///|
/// Merge count results from multiple shards.
///
/// Each shard result: (shard_id, count, error_or_empty)
/// Returns: (total_count, succeeded_shard_ids, failed)
pub fn distributed_merge_count(
  shard_results : Array[(Int, Int, String)],
) -> (Int, Array[Int], Array[(Int, String)]) {
  let inputs : Array[@distributed.ShardCountResult] = shard_results.map(fn(sr) {
    let (shard_id, count, error) = sr
    let error_opt : String? = if error.length() > 0 {
      Some(error)
    } else {
      None
    }
    { target_key: shard_id_to_key(shard_id), count, error: error_opt }
  })
  let merged = @distributed.merge_count(inputs)
  let succeeded = merged.succeeded.map(fn(k) { key_to_shard_id(k) })
  let failed = merged.failed.map(fn(pair) {
    let (k, msg) = pair
    (key_to_shard_id(k), msg)
  })
  (merged.count, succeeded, failed)
}

// ── Routing ─────────────────────────────────────────────────

// ── Rebalance planning ─────────────────────────────────────

///|
/// Compute rebalance plan for vector IDs when shard config changes.
///
/// Each ID: Bytes (16-byte wire format)
/// Returns: Array of (id_bytes, add_to_shards, remove_from_shards)
pub fn distributed_rebalance_plan(
  ids : Array[Bytes],
  old_pg_count : Int,
  old_replicas : Int,
  new_pg_count : Int,
  new_replicas : Int,
) -> Array[(Bytes, Array[Int], Array[Int])] {
  let old_map = ffi_crush_map(old_pg_count, old_replicas)
  let new_map = ffi_crush_map(new_pg_count, new_replicas)
  let typed_ids = ids.filter_map(fn(id_bytes) {
    @types.VectorId::from_wire_bytes(id_bytes)
  })
  let plan = @distributed.compute_rebalance_plan(typed_ids, old_map, new_map)
  plan.map(fn(action) {
    (
      @types.VectorId::to_wire_bytes(action.id),
      action.add_to.map(fn(k) { key_to_shard_id(k) }),
      action.remove_from.map(fn(k) { key_to_shard_id(k) }),
    )
  })
}

///|
/// Summarize a rebalance plan without computing full actions.
/// Returns: (affected_vectors, total_additions, total_removals)
pub fn distributed_rebalance_summary(
  ids : Array[Bytes],
  old_pg_count : Int,
  old_replicas : Int,
  new_pg_count : Int,
  new_replicas : Int,
) -> (Int, Int, Int) {
  let old_map = ffi_crush_map(old_pg_count, old_replicas)
  let new_map = ffi_crush_map(new_pg_count, new_replicas)
  let typed_ids = ids.filter_map(fn(id_bytes) {
    @types.VectorId::from_wire_bytes(id_bytes)
  })
  let plan = @distributed.compute_rebalance_plan(typed_ids, old_map, new_map)
  let summary = @distributed.summarize_rebalance(plan)
  (summary.affected_vectors, summary.total_additions, summary.total_removals)
}

// ── Routing ─────────────────────────────────────────────────

///|
/// Group upsert points by shard using CRUSH placement (single replica).
///
/// Each point: (id_bytes: Bytes, vector, payload_json)
/// Returns: Array of (shard_id, points_for_shard)
pub fn distributed_group_upsert(
  points : Array[(Bytes, Array[Double], String)],
  pg_count : Int,
) -> Array[(Int, Array[(Bytes, Array[Double], String)])] {
  distributed_group_upsert_replicated(points, pg_count, 1)
}

///|
/// Group upsert points by shard with replication.
///
/// Each point is placed on `replicas` shards (primary + replicas).
/// When replicas=1, behaves identically to `distributed_group_upsert`.
/// When replicas=3, each point appears in 3 shard groups.
///
/// Each point: (id_bytes: Bytes, vector, payload_json)
/// Returns: Array of (shard_id, points_for_shard)
pub fn distributed_group_upsert_replicated(
  points : Array[(Bytes, Array[Double], String)],
  pg_count : Int,
  replicas : Int,
) -> Array[(Int, Array[(Bytes, Array[Double], String)])] {
  let crush_map = ffi_crush_map(pg_count, replicas)
  let typed_points : Array[(@types.VectorId, Array[Double], @types.Attrs)] = points.filter_map(fn(
      p,
    ) {
      let (id_bytes, vector, payload_json) = p
      match @types.VectorId::from_wire_bytes(id_bytes) {
        Some(id) => Some((id, vector, parse_json_to_attrs(payload_json)))
        None => None
      }
    },
  )
  // Use the core router's group_by_target which correctly handles replicas
  let groups = @distributed.group_by_target(typed_points, crush_map)
  let result : Array[(Int, Array[(Bytes, Array[Double], String)])] = []
  for target_key in groups.keys() {
    match groups.get(target_key) {
      Some(pts) => {
        let shard_id = key_to_shard_id(target_key)
        let raw_pts = pts.map(fn(p) {
          let (id, vector, attrs) = p
          (
            @types.VectorId::to_wire_bytes(id),
            vector,
            @codec.attrs_to_json(Some(attrs)),
          )
        })
        result.push((shard_id, raw_pts))
      }
      None => ()
    }
  }
  result
}
