///|
/// HNSW (Hierarchical Navigable Small World) graph-based ANN implementation.
/// Provides high-performance similarity search with logarithmic complexity.
/// XORShift random number generator
struct Rng {
  mut state : UInt64
}

///|
fn Rng::new(seed : UInt64) -> Rng {
  { state: if seed == 0UL { 1UL } else { seed } }
}

///|
fn Rng::next(self : Rng) -> Double {
  // XORShift64
  let mut x = self.state
  x = x ^ (x << 13)
  x = x ^ (x >> 17)
  x = x ^ (x << 5)
  self.state = x
  // Convert to [0, 1)
  (x & 0xFFFFFFFFUL).to_double() / 4294967296.0
}

///|
/// HNSW state
pub struct HNSWState {
  metric : @types.Metric
  m : Int // max connections per node
  ef_construction : Int // construction beam width
  ef_search : Int // search beam width
  level_mult : Double // level multiplier
  allow_replace_deleted : Bool
  mut enter_point : Int // entry point index (-1 if empty)
  mut max_level : Int // maximum level in the graph
  mut level_arr : Array[Int] // level[idx] = level of node at idx
  mut tombstone : Array[Bool] // tombstone[idx] = true if deleted
  links : Array[Array[Array[Int]]] // links[level][idx] = neighbors
  rng : Rng
}

///|
/// Create HNSW state
pub fn HNSWState::new(
  params : @types.HNSWParams,
  metric : @types.Metric,
  capacity : Int,
) -> HNSWState {
  let m = params.m
  let cap = if capacity < 1 { 1 } else { capacity }
  {
    metric,
    m,
    ef_construction: params.ef_construction,
    ef_search: params.ef_search,
    level_mult: params.level_mult,
    allow_replace_deleted: params.allow_replace_deleted,
    enter_point: -1,
    max_level: -1,
    level_arr: Array::make(cap, 0),
    tombstone: Array::make(cap, false),
    links: [],
    rng: Rng::new(params.seed),
  }
}

///|
/// Ensure capacity for HNSW state
pub fn HNSWState::ensure_capacity(self : HNSWState, capacity : Int) -> Unit {
  if self.level_arr.length() >= capacity && self.tombstone.length() >= capacity {
    return
  }
  // Grow level_arr
  if self.level_arr.length() < capacity {
    let new_arr = Array::make(capacity, 0)
    for i in 0..<self.level_arr.length() {
      new_arr[i] = self.level_arr[i]
    }
    self.level_arr = new_arr
  }
  // Grow tombstone
  if self.tombstone.length() < capacity {
    let new_arr = Array::make(capacity, false)
    for i in 0..<self.tombstone.length() {
      new_arr[i] = self.tombstone[i]
    }
    self.tombstone = new_arr
  }
}

///|
/// Sample a random level for a new node
fn HNSWState::sample_level(self : HNSWState) -> Int {
  let u = self.rng.next()
  let u_clamped = if u < 0.000001 { 0.000001 } else { u }
  // level = floor(-ln(u) * level_mult)
  let neg_ln_u = -@math.ln(u_clamped)
  (neg_ln_u * self.level_mult).to_int()
}

///|
/// Ensure levels array has enough layers
fn HNSWState::ensure_levels(self : HNSWState, level : Int) -> Unit {
  while self.links.length() <= level {
    self.links.push([])
  }
}

///|
/// Compute score between query and vector at index (inline for performance)
fn hnsw_score(
  state : HNSWState,
  store : @store.CoreStore,
  idx : Int,
  q : Array[Double],
) -> Double {
  let dim = store.dim
  let base = idx * dim
  // Guard: return very low score for out-of-bounds index
  if base + dim > store.data.length() {
    return -1.0e308
  }
  // Inline score computation to avoid function lookup overhead
  match state.metric {
    Cosine | Dot => @vecmath.dot_at(store.data, base, q, dim)
    L2 => @vecmath.l2neg_at(store.data, base, q, dim)
  }
}

///|
/// Greedy descent from entry point to target through upper layers
fn greedy_descent(
  state : HNSWState,
  store : @store.CoreStore,
  ep : Int,
  target : Array[Double],
  from_level : Int,
  to_level? : Int = 0,
) -> Int {
  let mut cur = ep
  for level = from_level; level > to_level; {
    let mut improved = true
    while improved {
      improved = false
      let neigh = if level < state.links.length() &&
        cur < state.links[level].length() {
        state.links[level][cur]
      } else {
        []
      }
      let mut best_idx = cur
      let mut best_score = hnsw_score(state, store, cur, target)
      for nb in neigh {
        // Guard: skip out-of-bounds neighbors
        if nb >= store.count {
          continue
        }
        if nb < state.tombstone.length() && state.tombstone[nb] {
          continue
        }
        let sc = hnsw_score(state, store, nb, target)
        if sc > best_score {
          best_score = sc
          best_idx = nb
          improved = true
        }
      }
      cur = best_idx
    }
    continue level - 1
  }
  cur
}

///|
/// Search layer - explore neighbors at a given level
fn hnsw_search_layer(
  state : HNSWState,
  store : @store.CoreStore,
  entry : Int,
  target : Array[Double],
  level : Int,
  ef : Int,
) -> Array[@collection.ScoredItem] {
  // Use max of store.count and tombstone.length for visited array
  // to handle cases where HNSW indices exceed current store size after removals
  let visited_size = @cmp.maximum(store.count, state.tombstone.length())
  let visited_size = @cmp.maximum(visited_size, entry + 1)
  let visited = Array::make(visited_size, false)
  let heap : @collection.MaxHeap[@collection.ScoredItem] = @collection.MaxHeap::for_scored()
  let results : Array[@collection.ScoredItem] = []
  // Guard: entry might be out of bounds or tombstoned
  if entry >= store.count ||
    (entry < state.tombstone.length() && state.tombstone[entry]) {
    return []
  }
  let entry_score = hnsw_score(state, store, entry, target)
  heap.push(@collection.ScoredItem::{ idx: entry, s: entry_score })
  results.push(@collection.ScoredItem::{ idx: entry, s: entry_score })
  visited[entry] = true
  while heap.length() > 0 {
    let cur = heap.pop().unwrap()
    // Early termination
    let worst = if results.length() > 0 {
      results[results.length() - 1].s
    } else {
      -1.0e308
    }
    if results.length() >= ef && cur.s <= worst {
      break
    }
    let neigh = if level < state.links.length() &&
      cur.idx < state.links[level].length() {
      state.links[level][cur.idx]
    } else {
      []
    }
    for nb in neigh {
      // Guard: skip out-of-bounds neighbors
      if nb >= visited_size {
        continue
      }
      if visited[nb] {
        continue
      }
      visited[nb] = true
      // Check if tombstoned - still explore neighbors but don't add to results
      let is_tombstoned = nb < state.tombstone.length() && state.tombstone[nb]
      // Skip scoring for out-of-bounds (but still mark visited for graph traversal)
      if nb >= store.count {
        continue
      }
      let sc = hnsw_score(state, store, nb, target)
      // Always add to heap for exploration (even tombstoned)
      heap.push(@collection.ScoredItem::{ idx: nb, s: sc })
      // Only add to results if not tombstoned
      if is_tombstoned {
        continue
      }
      @collection.push_sorted_desc(
        results,
        @collection.ScoredItem::{ idx: nb, s: sc },
        Some(ef),
      )
    }
  }
  results
}

///|
/// Prune neighbor list to keep top-m by distance to node
fn prune_neighbors_by_distance(
  neighbors : Array[Int],
  node_idx : Int,
  m : Int,
  store : @store.CoreStore,
  score_fn : (Array[Double], Int, Array[Double], Int) -> Double,
) -> Unit {
  if neighbors.length() <= m {
    return
  }
  let dim = store.dim
  // Get node vector
  let node_base = node_idx * dim
  let node_vec = Array::make(dim, 0.0)
  for i in 0..<dim {
    node_vec[i] = store.data[node_base + i]
  }
  // Score each neighbor
  let scored : Array[(Int, Double)] = []
  for n in neighbors {
    let n_base = n * dim
    let score = score_fn(store.data, n_base, node_vec, dim)
    scored.push((n, score))
  }
  // Sort by score descending (higher = closer)
  scored.sort_by(fn(a, b) { b.1.compare(a.1) })
  // Rebuild neighbors with top-m
  neighbors.clear()
  for i in 0..<m {
    if i < scored.length() {
      neighbors.push(scored[i].0)
    }
  }
}

///|
/// Connect node mutually with neighbors
fn connect_mutually(
  state : HNSWState,
  store : @store.CoreStore,
  a : Int,
  neighbors : Array[Int],
  level : Int,
) -> Unit {
  // Ensure links array exists
  while state.links.length() <= level {
    state.links.push([])
  }
  while state.links[level].length() <= a {
    state.links[level].push([])
  }
  let la = state.links[level][a]
  let score_fn = @vecmath.get_score_fn(state.metric)
  for b in neighbors {
    if b == a {
      continue
    }
    // Add b to a's neighbors if not present
    let mut found = false
    for n in la {
      if n == b {
        found = true
        break
      }
    }
    if not(found) {
      la.push(b)
    }
    // Add a to b's neighbors
    while state.links[level].length() <= b {
      state.links[level].push([])
    }
    let lb = state.links[level][b]
    found = false
    for n in lb {
      if n == a {
        found = true
        break
      }
    }
    if not(found) {
      lb.push(a)
    }
    // Prune if too many connections - keep top-m by distance
    if la.length() > state.m {
      prune_neighbors_by_distance(la, a, state.m, store, score_fn)
    }
    if lb.length() > state.m {
      prune_neighbors_by_distance(lb, b, state.m, store, score_fn)
    }
  }
}

///|
/// Add a vector to HNSW
pub fn hnsw_add(
  state : HNSWState,
  store : @store.CoreStore,
  id : @types.VectorId,
) -> Unit {
  with_store_vector(store, id, fn(at, vec) {
    state.ensure_capacity(at + 1)
    // Sample level for this node
    let node_level = state.sample_level()
    state.level_arr[at] = node_level
    state.tombstone[at] = false
    // First node becomes entry point
    if state.enter_point < 0 {
      state.enter_point = at
      state.max_level = node_level
      state.ensure_levels(node_level)
    } else {
      // Descend from entry point through upper levels, stopping at node_level
      let mut cur = state.enter_point
      if state.max_level > node_level {
        cur = greedy_descent(
          state,
          store,
          cur,
          vec,
          state.max_level,
          to_level=node_level,
        )
      }
      // Connect at each level from min(node_level, max_level) down to 0
      let start_level = if node_level < state.max_level {
        node_level
      } else {
        state.max_level
      }
      for level = start_level; level >= 0; {
        let candidates = hnsw_search_layer(
          state,
          store,
          cur,
          vec,
          level,
          state.ef_construction,
        )
        // Select M nearest neighbors
        let neighbors : Array[Int] = []
        for c in candidates {
          if neighbors.length() >= state.m {
            break
          }
          if c.idx != at {
            neighbors.push(c.idx)
          }
        }
        state.ensure_levels(level)
        connect_mutually(state, store, at, neighbors, level)
        // Update current for next level
        if candidates.length() > 0 {
          cur = candidates[0].idx
        }
        continue level - 1
      }
      // Update entry point if this node has higher level
      if node_level > state.max_level {
        state.max_level = node_level
        state.enter_point = at
      }
    }
  })
}

///|
/// Remove a vector from HNSW (mark as tombstone)
pub fn hnsw_remove(
  state : HNSWState,
  id : @types.VectorId,
  store : @store.CoreStore,
) -> Unit {
  match store.get_index(id) {
    None => ()
    Some(at) => if at < state.tombstone.length() { state.tombstone[at] = true }
  }
}

///|
/// Search HNSW for k nearest neighbors
pub fn hnsw_search(
  state : HNSWState,
  store : @store.CoreStore,
  q : Array[Double],
  k : Int,
  filter : ((@types.VectorId, @types.Attrs) -> Bool)?,
) -> Array[@types.SearchHit] {
  guard q.length() == store.dim else {
    abort(
      "dim mismatch: got " +
      q.length().to_string() +
      ", want " +
      store.dim.to_string(),
    )
  }
  if state.enter_point < 0 {
    return []
  }
  // Find a valid entry point (not tombstoned and within store bounds)
  let mut entry = state.enter_point
  if entry >= store.count ||
    (entry < state.tombstone.length() && state.tombstone[entry]) {
    // Entry point is invalid, find any valid node
    entry = -1
    for i in 0..<state.tombstone.length() {
      if i < store.count && not(state.tombstone[i]) {
        entry = i
        break
      }
    }
    if entry < 0 {
      return [] // All nodes are tombstoned or invalid
    }
  }
  // Normalize query for cosine
  let query = store.normalize_query(q)
  // Descend from entry point
  let mut cur = entry
  if state.max_level > 0 {
    cur = greedy_descent(state, store, cur, query, state.max_level)
  }
  // Search at level 0
  let candidates = hnsw_search_layer(
    state,
    store,
    cur,
    query,
    0,
    state.ef_search,
  )
  // Convert to SearchHit and apply filter
  let out : Array[@types.SearchHit] = []
  for c in candidates {
    if c.idx >= store.count {
      continue
    }
    // Skip tombstoned entries
    if c.idx < state.tombstone.length() && state.tombstone[c.idx] {
      continue
    }
    let id = store.ids[c.idx]
    let attrs = store.attrs[c.idx]
    match filter {
      Some(f) => if not(f(id, attrs)) { continue }
      None => ()
    }
    push_search_hit_top_k(out, @types.SearchHit::{ id, score: c.s, attrs }, k)
  }
  out
}

///|
/// Find single best match in HNSW
pub fn hnsw_find(
  state : HNSWState,
  store : @store.CoreStore,
  q : Array[Double],
  filter : ((@types.VectorId, @types.Attrs) -> Bool)?,
) -> @types.SearchHit? {
  let results = hnsw_search(state, store, q, 1, filter)
  first_search_hit(results)
}

///|
/// Serialize HNSW state to bytes
pub fn hnsw_serialize(state : HNSWState) -> Bytes {
  let w = @binary.BinaryWriter::new()
  // Write enter_point and max_level
  w.push_i32(state.enter_point)
  w.push_i32(state.max_level)
  // Write level_arr length and data
  w.push_u32(state.level_arr.length().reinterpret_as_uint())
  for level in state.level_arr {
    w.push_i32(level)
  }
  // Write tombstone length and data
  w.push_u32(state.tombstone.length().reinterpret_as_uint())
  for t in state.tombstone {
    w.push_u32(if t { 1U } else { 0U })
  }
  // Write links: num_levels, then for each level: num_nodes, then for each node: num_neighbors, neighbors
  w.push_u32(state.links.length().reinterpret_as_uint())
  for level_links in state.links {
    w.push_u32(level_links.length().reinterpret_as_uint())
    for node_neighbors in level_links {
      w.push_u32(node_neighbors.length().reinterpret_as_uint())
      for neighbor in node_neighbors {
        w.push_i32(neighbor)
      }
    }
  }
  w.concat()
}

///|
/// Deserialize HNSW state from bytes
pub fn hnsw_deserialize(state : HNSWState, data : Bytes) -> Unit {
  let r = @binary.BinaryReader::new(data)
  // Read enter_point and max_level
  state.enter_point = r.read_i32()
  state.max_level = r.read_i32()
  // Read level_arr
  let level_arr_len = r.read_u32().reinterpret_as_int()
  state.level_arr = Array::make(level_arr_len, 0)
  for i in 0..<level_arr_len {
    state.level_arr[i] = r.read_i32()
  }
  // Read tombstone
  let tombstone_len = r.read_u32().reinterpret_as_int()
  state.tombstone = Array::make(tombstone_len, false)
  for i in 0..<tombstone_len {
    state.tombstone[i] = r.read_u32() != 0U
  }
  // Read links
  let num_levels = r.read_u32().reinterpret_as_int()
  while state.links.length() > 0 {
    let _ = state.links.pop()
  }
  for _ in 0..<num_levels {
    let num_nodes = r.read_u32().reinterpret_as_int()
    let level_links : Array[Array[Int]] = []
    for _ in 0..<num_nodes {
      let num_neighbors = r.read_u32().reinterpret_as_int()
      let neighbors : Array[Int] = []
      for _ in 0..<num_neighbors {
        neighbors.push(r.read_i32())
      }
      level_links.push(neighbors)
    }
    state.links.push(level_links)
  }
}
