///|
/// Push a search hit into top-k buffer using score ordering.
fn push_search_hit_top_k(
  out : Array[@types.SearchHit],
  hit : @types.SearchHit,
  k : Int,
) -> Unit {
  @collection.push_top_k(out, hit, k, fn(hit) { hit.score })
}

///|
/// Return best hit from result list.
fn first_search_hit(results : Array[@types.SearchHit]) -> @types.SearchHit? {
  if results.is_empty() {
    None
  } else {
    Some(results[0])
  }
}

///|
/// Run a callback with `(index, vector)` if id exists in store.
fn with_store_vector(
  store : @store.CoreStore,
  id : @types.VectorId,
  f : (Int, Array[Double]) -> Unit,
) -> Unit {
  match store.get_index(id) {
    None => ()
    Some(index) => {
      let base = index * store.dim
      let vec = Array::make(store.dim, 0.0)
      for i in 0..<store.dim {
        vec[i] = store.data[base + i]
      }
      f(index, vec)
    }
  }
}
