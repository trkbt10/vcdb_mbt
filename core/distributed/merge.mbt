///|
/// Distributed merge strategies.
///
/// These functions combine partial results from multiple shards
/// into a single unified result. They handle:
///   - Score-descending merge for search
///   - ID-ascending merge for scroll
///   - Summation for count
///   - Partial failure tracking

///|
/// Merge search results from multiple shards.
///
/// Collects hits from all successful shards, sorts by score descending,
/// and returns the top K. Failed shards are recorded but do not
/// prevent the merge — callers decide how to handle partial results.
pub fn merge_search(
  shard_results : Array[ShardSearchResult],
  top_k : Int,
) -> MergedSearchResult {
  let all_hits : Array[@types.SearchHit] = []
  let succeeded : Array[Int] = []
  let failed : Array[(Int, String)] = []

  for result in shard_results {
    match result.error {
      Some(msg) => failed.push((result.shard_id, msg))
      None => {
        succeeded.push(result.shard_id)
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

  let hits = if top_k >= all_hits.length() {
    all_hits
  } else {
    let truncated : Array[@types.SearchHit] = []
    for i in 0..<top_k {
      truncated.push(all_hits[i])
    }
    truncated
  }

  { hits, succeeded, failed }
}

///|
/// Merge scroll results from multiple shards.
///
/// Collects entries from all successful shards, sorts by ID ascending,
/// and returns up to `limit` entries. This is a k-way merge simplified
/// to sort-then-slice for correctness; can be optimized to streaming
/// merge for large limits.
pub fn merge_scroll(
  shard_results : Array[ShardScrollResult],
  limit : Int,
) -> MergedScrollResult {
  let all_entries : Array[ShardScrollEntry] = []
  let succeeded : Array[Int] = []
  let failed : Array[(Int, String)] = []

  for result in shard_results {
    match result.error {
      Some(msg) => failed.push((result.shard_id, msg))
      None => {
        succeeded.push(result.shard_id)
        for entry in result.entries {
          all_entries.push(entry)
        }
      }
    }
  }

  // Sort by ID ascending
  all_entries.sort_by(fn(a, b) { a.id.compare(b.id) })

  let entries = if limit >= all_entries.length() {
    all_entries
  } else {
    let truncated : Array[ShardScrollEntry] = []
    for i in 0..<limit {
      truncated.push(all_entries[i])
    }
    truncated
  }

  { entries, succeeded, failed }
}

///|
/// Merge count results from multiple shards.
///
/// Sums counts from all successful shards. Failed shards contribute 0
/// to the total — callers should check `failed` to decide if the
/// result is authoritative.
pub fn merge_count(
  shard_results : Array[ShardCountResult],
) -> MergedCountResult {
  let mut total = 0
  let succeeded : Array[Int] = []
  let failed : Array[(Int, String)] = []

  for result in shard_results {
    match result.error {
      Some(msg) => failed.push((result.shard_id, msg))
      None => {
        succeeded.push(result.shard_id)
        total = total + result.count
      }
    }
  }

  { count: total, succeeded, failed }
}
