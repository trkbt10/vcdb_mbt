///|
/// Distributed FFI exports — scatter-gather merge and routing.
///
/// Wire format for VectorId: Bytes of exactly 16 bytes.
/// See VectorId::to_wire_bytes / VectorId::from_wire_bytes for details.
///
/// These are synchronous pure functions (no I/O, no instance state).

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
    { shard_id, hits, error: error_opt }
  })
  let merged = @distributed.merge_search(inputs, top_k)
  let out_hits = merged.hits.map(fn(hit) {
    let payload_json = @codec.attrs_to_json(Some(hit.attrs))
    (@types.VectorId::to_wire_bytes(hit.id), hit.score, payload_json)
  })
  (out_hits, merged.succeeded, merged.failed)
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
    { shard_id, entries, error: error_opt }
  })
  let merged = @distributed.merge_scroll(inputs, limit)
  let out_entries = merged.entries.map(fn(entry) {
    let attrs_json = @codec.attrs_to_json(Some(entry.attrs))
    (@types.VectorId::to_wire_bytes(entry.id), attrs_json)
  })
  (out_entries, merged.succeeded, merged.failed)
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
    { shard_id, count, error: error_opt }
  })
  let merged = @distributed.merge_count(inputs)
  (merged.count, merged.succeeded, merged.failed)
}

// ── Routing ─────────────────────────────────────────────────

///|
/// Group upsert points by shard using CRUSH placement.
///
/// Each point: (id_bytes: Bytes, vector, payload_json)
/// Returns: Array of (shard_id, points_for_shard)
pub fn distributed_group_upsert(
  points : Array[(Bytes, Array[Double], String)],
  pg_count : Int,
) -> Array[(Int, Array[(Bytes, Array[Double], String)])] {
  let crush_map = @placement.CrushMap::new(pg_count, 1, [])
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
  let groups = @distributed.group_by_shard(typed_points, crush_map)
  let result : Array[(Int, Array[(Bytes, Array[Double], String)])] = []
  for pg in groups.keys() {
    match groups.get(pg) {
      Some(pts) => {
        let raw_pts = pts.map(fn(p) {
          let (id, vector, attrs) = p
          (
            @types.VectorId::to_wire_bytes(id),
            vector,
            @codec.attrs_to_json(Some(attrs)),
          )
        })
        result.push((pg, raw_pts))
      }
      None => ()
    }
  }
  result
}
