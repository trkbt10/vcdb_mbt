///|
/// Distributed merge strategies.
///
/// These functions combine partial results from multiple targets
/// into a single unified result. They handle:
///   - Score-descending merge for search
///   - ID-ascending merge for scroll
///   - Summation for count
///   - Partial failure tracking
///
/// ## Deduplication
///
/// When the caller correctly queries one target per PG, results
/// contain no duplicates. The dedup logic in search and scroll is
/// a safety net for misconfigured fan-outs or during rebalancing.

///|
/// Merge search results from multiple targets.
///
/// Collects hits from all successful targets, sorts by score descending,
/// deduplicates by ID, and returns the top K.
pub fn merge_search(
  shard_results : Array[ShardSearchResult],
  top_k : Int,
) -> MergedSearchResult {
  let all_hits : Array[@types.SearchHit] = []
  let succeeded : Array[@placement.TargetKey] = []
  let failed : Array[(@placement.TargetKey, String)] = []

  for result in shard_results {
    match result.error {
      Some(msg) => failed.push((result.target_key, msg))
      None => {
        succeeded.push(result.target_key)
        for hit in result.hits {
          all_hits.push(hit)
        }
      }
    }
  }

  // Sort by score descending. Tie-break by ID ascending for determinism.
  all_hits.sort_by(fn(a, b) {
    let score_cmp = b.score.compare(a.score)
    if score_cmp != 0 {
      score_cmp
    } else {
      a.id.compare(b.id)
    }
  })

  // Deduplicate by ID (safety net for replica overlap).
  let seen : Map[@types.VectorId, Bool] = {}
  let deduped : Array[@types.SearchHit] = []
  for hit in all_hits {
    if !seen.contains(hit.id) {
      seen.set(hit.id, true)
      deduped.push(hit)
    }
  }

  let hits = if top_k >= deduped.length() {
    deduped
  } else {
    let truncated : Array[@types.SearchHit] = []
    for i in 0..<top_k {
      truncated.push(deduped[i])
    }
    truncated
  }

  { hits, succeeded, failed }
}

///|
/// Merge scroll results from multiple targets.
///
/// Collects entries from all successful targets, sorts by ID ascending,
/// deduplicates, and returns up to `limit` entries.
pub fn merge_scroll(
  shard_results : Array[ShardScrollResult],
  limit : Int,
) -> MergedScrollResult {
  let all_entries : Array[ShardScrollEntry] = []
  let succeeded : Array[@placement.TargetKey] = []
  let failed : Array[(@placement.TargetKey, String)] = []

  for result in shard_results {
    match result.error {
      Some(msg) => failed.push((result.target_key, msg))
      None => {
        succeeded.push(result.target_key)
        for entry in result.entries {
          all_entries.push(entry)
        }
      }
    }
  }

  // Sort by ID ascending
  all_entries.sort_by(fn(a, b) { a.id.compare(b.id) })

  // Deduplicate by ID (safety net for replica overlap).
  let deduped : Array[ShardScrollEntry] = []
  for entry in all_entries {
    if deduped.is_empty() || deduped[deduped.length() - 1].id != entry.id {
      deduped.push(entry)
    }
  }

  let entries = if limit >= deduped.length() {
    deduped
  } else {
    let truncated : Array[ShardScrollEntry] = []
    for i in 0..<limit {
      truncated.push(deduped[i])
    }
    truncated
  }

  { entries, succeeded, failed }
}

///|
/// Merge count results from multiple targets.
///
/// When fan-out correctly queries one target per PG, the sum of
/// counts equals the true unique count. No division needed.
pub fn merge_count(
  shard_results : Array[ShardCountResult],
) -> MergedCountResult {
  let mut total = 0
  let succeeded : Array[@placement.TargetKey] = []
  let failed : Array[(@placement.TargetKey, String)] = []

  for result in shard_results {
    match result.error {
      Some(msg) => failed.push((result.target_key, msg))
      None => {
        succeeded.push(result.target_key)
        total = total + result.count
      }
    }
  }

  { count: total, succeeded, failed }
}
