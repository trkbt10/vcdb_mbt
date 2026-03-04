///|
/// Bruteforce ANN strategy implementation.
/// Simple linear scan over all vectors - best for small datasets.
pub struct BruteforceState {
  metric : @core.Metric
}

///|
/// Create bruteforce state
pub fn BruteforceState::new(metric : @core.Metric) -> BruteforceState {
  { metric, }
}

///|
/// Bruteforce search - linear scan over all vectors.
/// Returns top-k results sorted by score (highest first).
/// Query is normalized for cosine metric.
pub fn bf_search(
  state : BruteforceState,
  store : @core.CoreStore,
  q : Array[Double],
  k : Int,
  filter : ((@core.VectorId, @core.Attrs) -> Bool)?,
) -> Array[@core.SearchHit] {
  guard q.length() == store.dim else {
    abort(
      "dim mismatch: got " +
      q.length().to_string() +
      ", want " +
      store.dim.to_string(),
    )
  }
  // Normalize query for cosine
  let query = store.normalize_query(q)
  let out : Array[@core.SearchHit] = []
  let score_fn = @core.get_score_fn(state.metric)
  for i in 0..<store.count {
    let id = store.ids[i]
    let attrs = store.attrs[i]
    // Apply filter if provided
    match filter {
      Some(f) => if not(f(id, attrs)) { continue }
      None => ()
    }
    let base = i * store.dim
    let s = score_fn(store.data, base, query, store.dim)
    @collection.push_top_k(out, @core.SearchHit::{ id, score: s, attrs }, k, fn(hit) {
      hit.score
    })
  }
  out
}

///|
/// Bruteforce find one - returns the best match
pub fn bf_find(
  state : BruteforceState,
  store : @core.CoreStore,
  q : Array[Double],
  filter : ((@core.VectorId, @core.Attrs) -> Bool)?,
) -> @core.SearchHit? {
  let results = bf_search(state, store, q, 1, filter)
  if results.is_empty() {
    None
  } else {
    Some(results[0])
  }
}

///|
/// Bruteforce add - no-op for bruteforce (no index structure)
pub fn bf_add(
  _state : BruteforceState,
  _store : @core.CoreStore,
  _id : @core.VectorId,
) -> Unit {
  // No-op: bruteforce doesn't maintain an index
}

///|
/// Bruteforce remove - no-op for bruteforce (no index structure)
pub fn bf_remove(
  _state : BruteforceState,
  _store : @core.CoreStore,
  _id : @core.VectorId,
) -> Unit {
  // No-op: bruteforce doesn't maintain an index
}

///|
/// Serialize bruteforce state (empty for bruteforce)
pub fn bf_serialize(_state : BruteforceState) -> Bytes {
  Bytes::new(0)
}

///|
/// Deserialize bruteforce state (no-op)
pub fn bf_deserialize(_state : BruteforceState, _data : Bytes) -> Unit {
  // No-op: bruteforce has no serialized state
}
