///|
/// IVF (Inverted File) index implementation.
/// Uses k-means clustering for approximate nearest neighbor search.
pub struct IVFState {
  metric : @core.Metric
  nlist : Int // number of clusters
  nprobe : Int // number of clusters to search
  mut centroid_count : Int
  centroids : Array[Double] // flattened: centroids[c*dim..(c+1)*dim]
  lists : Array[Array[@core.VectorId]] // posting lists
  id_to_list : Map[Int64, Int] // id -> list index
}

///|
/// Create IVF state
pub fn IVFState::new(
  params : @core.IVFParams,
  metric : @core.Metric,
  dim : Int,
) -> IVFState {
  let nlist = if params.nlist < 1 { 1 } else { params.nlist }
  let nprobe_default = nlist.to_double().sqrt().to_int()
  let nprobe = if params.nprobe < 1 {
    if nprobe_default < 1 {
      1
    } else {
      nprobe_default
    }
  } else if params.nprobe > nlist {
    nlist
  } else {
    params.nprobe
  }
  let lists : Array[Array[@core.VectorId]] = []
  for _ in 0..<nlist {
    lists.push([])
  }
  {
    metric,
    nlist,
    nprobe,
    centroid_count: 0,
    centroids: Array::make(nlist * dim, 0.0),
    lists,
    id_to_list: {},
  }
}

///|
/// Find nearest centroid to a vector
fn nearest_centroid(
  state : IVFState,
  store : @core.CoreStore,
  vec : Array[Double],
) -> Int {
  let dim = store.dim
  let score_fn = @core.get_score_fn(state.metric)
  let mut best = -1
  let mut best_score = -1.0e308
  let count = if state.centroid_count < 1 { 1 } else { state.centroid_count }
  for c in 0..<count {
    let base = c * dim
    let sc = score_fn(state.centroids, base, vec, dim)
    if sc > best_score {
      best_score = sc
      best = c
    }
  }
  if best < 0 {
    0
  } else {
    best
  }
}

///|
/// Add a vector to IVF
pub fn ivf_add(
  state : IVFState,
  store : @core.CoreStore,
  id : @core.VectorId,
) -> Unit {
  let idx = store.get_index(id)
  match idx {
    None => ()
    Some(i) => {
      let base = i * store.dim
      let vec = Array::make(store.dim, 0.0)
      for j in 0..<store.dim {
        vec[j] = store.data[base + j]
      }
      // Initialize centroids with first nlist vectors
      if state.centroid_count < state.nlist {
        let c = state.centroid_count
        for j in 0..<store.dim {
          state.centroids[c * store.dim + j] = vec[j]
        }
        state.centroid_count = state.centroid_count + 1
        state.lists[c].push(id)
        state.id_to_list.set(id.to_int64(), c)
        return
      }
      // Find nearest centroid
      let c = nearest_centroid(state, store, vec)
      state.lists[c].push(id)
      state.id_to_list.set(id.to_int64(), c)
    }
  }
}

///|
/// Assign a vector to its nearest centroid WITHOUT bootstrap behavior
/// Use this after training to reassign vectors to the trained centroids
pub fn ivf_assign(
  state : IVFState,
  store : @core.CoreStore,
  id : @core.VectorId,
) -> Unit {
  let idx = store.get_index(id)
  match idx {
    None => ()
    Some(i) => {
      let base = i * store.dim
      let vec = Array::make(store.dim, 0.0)
      for j in 0..<store.dim {
        vec[j] = store.data[base + j]
      }
      // Always assign to nearest existing centroid (no bootstrap)
      let c = nearest_centroid(state, store, vec)
      state.lists[c].push(id)
      state.id_to_list.set(id.to_int64(), c)
    }
  }
}

///|
/// Remove a vector from IVF
pub fn ivf_remove(state : IVFState, id : @core.VectorId) -> Unit {
  match state.id_to_list.get(id.to_int64()) {
    None => ()
    Some(li) => {
      let arr = state.lists[li]
      // Find and remove id from list
      let mut found_idx = -1
      for i in 0..<arr.length() {
        if arr[i].to_int64() == id.to_int64() {
          found_idx = i
          break
        }
      }
      if found_idx >= 0 {
        // Swap with last and pop
        let last = arr.length() - 1
        if found_idx != last {
          arr[found_idx] = arr[last]
        }
        let _ = arr.pop()
      }
      state.id_to_list.remove(id.to_int64())
    }
  }
}

///|
/// IVF search - find k nearest neighbors
pub fn ivf_search(
  state : IVFState,
  store : @core.CoreStore,
  q : Array[Double],
  k : Int,
  filter : ((@core.VectorId, @core.Attrs) -> Bool)?,
) -> Array[@core.SearchHit] {
  let dim = store.dim
  guard q.length() == dim else {
    abort(
      "dim mismatch: got " +
      q.length().to_string() +
      ", want " +
      dim.to_string(),
    )
  }
  // Normalize query for cosine
  let query = store.normalize_query(q)
  let score_fn = @core.get_score_fn(state.metric)
  // Score all centroids
  let scores : Array[(Int, Double)] = []
  let count = if state.centroid_count < 1 { 1 } else { state.centroid_count }
  for c in 0..<count {
    let s = score_fn(state.centroids, c * dim, query, dim)
    scores.push((c, s))
  }
  // Sort by score descending
  scores.sort_by(fn(a, b) { b.1.compare(a.1) })
  // Search top nprobe clusters
  let probe = if state.nprobe < scores.length() {
    state.nprobe
  } else {
    scores.length()
  }
  let out : Array[@core.SearchHit] = []
  for i in 0..<probe {
    let (c, _) = scores[i]
    let list = state.lists[c]
    for id in list {
      match store.get_index(id) {
        None => continue
        Some(at) => {
          let attrs = store.attrs[at]
          // Apply filter
          match filter {
            Some(f) => if not(f(id, attrs)) { continue }
            None => ()
          }
          let base = at * dim
          let s = score_fn(store.data, base, query, dim)
          @collection.push_top_k(out, @core.SearchHit::{ id, score: s, attrs }, k, fn(
            hit,
          ) {
            hit.score
          })
        }
      }
    }
  }
  out
}

///|
/// IVF find one - returns the best match
pub fn ivf_find(
  state : IVFState,
  store : @core.CoreStore,
  q : Array[Double],
  filter : ((@core.VectorId, @core.Attrs) -> Bool)?,
) -> @core.SearchHit? {
  let results = ivf_search(state, store, q, 1, filter)
  if results.is_empty() {
    None
  } else {
    Some(results[0])
  }
}

///|
/// Serialize IVF state to bytes
pub fn ivf_serialize(state : IVFState, dim : Int) -> Bytes {
  let w = @binary.BinaryWriter::new()
  // Write centroid_count
  w.push_i32(state.centroid_count)
  // Write centroids (flattened array)
  let centroid_len = state.nlist * dim
  for i in 0..<centroid_len {
    w.push_f64(state.centroids[i])
  }
  // Write lists: for each list, write length and ids
  w.push_u32(state.nlist.reinterpret_as_uint())
  for list in state.lists {
    w.push_u32(list.length().reinterpret_as_uint())
    for id in list {
      w.push_u64(id.to_int64().reinterpret_as_uint64())
    }
  }
  w.concat()
}

///|
/// Deserialize IVF state from bytes
pub fn ivf_deserialize(state : IVFState, data : Bytes, dim : Int) -> Unit {
  let r = @binary.BinaryReader::new(data)
  // Read centroid_count
  state.centroid_count = r.read_i32()
  // Read centroids
  let centroid_len = state.nlist * dim
  for i in 0..<centroid_len {
    state.centroids[i] = r.read_f64()
  }
  // Read lists
  let nlist = r.read_u32().reinterpret_as_int()
  // Clear existing lists
  for list in state.lists {
    while list.length() > 0 {
      let _ = list.pop()
    }
  }
  state.id_to_list.clear()
  // Read new lists
  for li in 0..<nlist {
    let list_len = r.read_u32().reinterpret_as_int()
    for _ in 0..<list_len {
      let id_val = r.read_u64().reinterpret_as_int64()
      let id = @core.VectorId(id_val)
      state.lists[li].push(id)
      state.id_to_list.set(id_val, li)
    }
  }
}

///|
/// Train IVF centroids using k-means++ initialization
pub fn ivf_train(
  state : IVFState,
  store : @core.CoreStore,
  iterations? : Int = 10,
) -> Unit {
  if store.count == 0 {
    return
  }
  let dim = store.dim
  let k = state.nlist
  // K-means++ initialization: select first centroid randomly
  // For simplicity, use first k vectors as initial centroids
  let centroid_count = if store.count < k { store.count } else { k }
  state.centroid_count = centroid_count
  // Copy first centroid_count vectors as initial centroids
  for c in 0..<centroid_count {
    let base = c * dim
    for i in 0..<dim {
      state.centroids[c * dim + i] = store.data[base + i]
    }
  }
  // K-means iterations
  for _ in 0..<iterations {
    // Clear assignment
    for list in state.lists {
      while list.length() > 0 {
        let _ = list.pop()
      }
    }
    state.id_to_list.clear()
    // Assign each vector to nearest centroid
    for idx in 0..<store.count {
      let id = store.ids[idx]
      let base = idx * dim
      let vec = Array::make(dim, 0.0)
      for i in 0..<dim {
        vec[i] = store.data[base + i]
      }
      let c = nearest_centroid(state, store, vec)
      state.lists[c].push(id)
      state.id_to_list.set(id.to_int64(), c)
    }
    // Update centroids
    for c in 0..<centroid_count {
      let list = state.lists[c]
      if list.is_empty() {
        continue
      }
      // Compute mean of assigned vectors
      let mean = Array::make(dim, 0.0)
      for id in list {
        match store.get_index(id) {
          None => continue
          Some(idx) => {
            let base = idx * dim
            for i in 0..<dim {
              mean[i] = mean[i] + store.data[base + i]
            }
          }
        }
      }
      let n = list.length().to_double()
      for i in 0..<dim {
        state.centroids[c * dim + i] = mean[i] / n
      }
    }
  }
}
