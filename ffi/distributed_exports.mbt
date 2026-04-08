///|
/// Distributed FFI exports — scatter-gather merge and routing.
///
/// These are synchronous pure functions (no I/O, no instance state).
/// JS callers collect shard results via platform-specific RPC,
/// then pass them here for merge.
///
/// All merge functions accept shard results as arrays of tuples
/// and return merged results in the same tuple encoding used by
/// persistent_search / persistent_scroll.

// ── Merge: search ───────────────────────────────────────────

///|
/// Merge search results from multiple shards.
///
/// Each shard result: (shard_id, hits, error_or_empty)
/// Each hit: (id_hi, id_lo, score, payload_json)
/// Returns: merged hits sorted by score desc, truncated to top_k.
///
/// Failed shards (non-empty error string) are excluded from merge.
/// Returns: (hits, succeeded_shard_ids, failed_shard_ids_with_errors)
pub fn distributed_merge_search(
  shard_results : Array[(Int, Array[(Int, Int, Double, String)], String)],
  top_k : Int,
) -> (Array[(Int, Int, Double, String)], Array[Int], Array[(Int, String)]) {
  let inputs : Array[@distributed.ShardSearchResult] = shard_results.map(fn(
    sr,
  ) {
    let (shard_id, raw_hits, error) = sr
    let hits = raw_hits.map(fn(h) {
      let (hi, lo, score, payload_json) = h
      let attrs = parse_json_to_attrs(payload_json)
      @types.SearchHit::{ id: vid_from_pair(hi, lo), score, attrs }
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
    let (hi, lo) = vid_to_pair(hit.id)
    let payload_json = @codec.attrs_to_json(Some(hit.attrs))
    (hi, lo, hit.score, payload_json)
  })
  (out_hits, merged.succeeded, merged.failed)
}

// ── Merge: scroll ───────────────────────────────────────────

///|
/// Merge scroll results from multiple shards.
///
/// Each shard result: (shard_id, entries, error_or_empty)
/// Each entry: (id_hi, id_lo, attrs_json)
/// Returns: merged entries sorted by ID asc, truncated to limit.
pub fn distributed_merge_scroll(
  shard_results : Array[(Int, Array[(Int, Int, String)], String)],
  limit : Int,
) -> (Array[(Int, Int, String)], Array[Int], Array[(Int, String)]) {
  let inputs : Array[@distributed.ShardScrollResult] = shard_results.map(fn(
    sr,
  ) {
    let (shard_id, raw_entries, error) = sr
    let entries = raw_entries.map(fn(e) {
      let (hi, lo, attrs_json) = e
      let attrs = parse_json_to_attrs(attrs_json)
      @distributed.ShardScrollEntry::{ id: vid_from_pair(hi, lo), attrs }
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
    let (hi, lo) = vid_to_pair(entry.id)
    let attrs_json = @codec.attrs_to_json(Some(entry.attrs))
    (hi, lo, attrs_json)
  })
  (out_entries, merged.succeeded, merged.failed)
}

// ── Merge: count ────────────────────────────────────────────

///|
/// Merge count results from multiple shards.
///
/// Each shard result: (shard_id, count, error_or_empty)
/// Returns: (total_count, succeeded_shard_ids, failed_shard_ids_with_errors)
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
/// Each point: (id_hi, id_lo, vector, payload_json)
/// Returns: Array of (shard_id, points_for_shard)
pub fn distributed_group_upsert(
  points : Array[(Int, Int, Array[Double], String)],
  pg_count : Int,
) -> Array[(Int, Array[(Int, Int, Array[Double], String)])] {
  let crush_map = @placement.CrushMap::new(pg_count, 1, [])
  let typed_points : Array[(@types.VectorId, Array[Double], @types.Attrs)] = points.map(fn(
      p,
    ) {
      let (hi, lo, vector, payload_json) = p
      (vid_from_pair(hi, lo), vector, parse_json_to_attrs(payload_json))
    },
  )
  let groups = @distributed.group_by_shard(typed_points, crush_map)
  let result : Array[(Int, Array[(Int, Int, Array[Double], String)])] = []
  for pg in groups.keys() {
    match groups.get(pg) {
      Some(pts) => {
        let raw_pts = pts.map(fn(p) {
          let (id, vector, attrs) = p
          let (hi, lo) = vid_to_pair(id)
          (hi, lo, vector, @codec.attrs_to_json(Some(attrs)))
        })
        result.push((pg, raw_pts))
      }
      None => ()
    }
  }
  result
}

// ── MbInt64 utilities ───────────────────────────────────────

///|
/// Parse a decimal string to MbInt64 (hi/lo i32 pair).
///
/// Returns (true, hi, lo) on success, (false, 0, 0) on invalid input.
/// Handles the full signed 64-bit range without JS float64 precision loss.
pub fn parse_int64(input : String) -> (Bool, Int, Int) {
  if input.length() == 0 {
    return (false, 0, 0)
  }
  // Use MoonBit's native Int64 parsing — no float64 intermediate
  let result : Result[Int64, _] = try? @string.parse_int64(input)
  match result {
    Ok(n) => {
      let vid = @types.VectorId(n)
      let (hi, lo) = vid_to_pair(vid)
      (true, hi, lo)
    }
    Err(_) => (false, 0, 0)
  }
}

///|
/// Convert MbInt64 (hi/lo pair) to decimal string.
///
/// Lossless representation for any Int64 value.
pub fn format_int64(hi : Int, lo : Int) -> String {
  let vid = vid_from_pair(hi, lo)
  vid.to_int64().to_string()
}
