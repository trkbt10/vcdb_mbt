///|
/// Re-export factory functions for convenience
pub fn empty_attrs() -> @core.Attrs {
  @core.empty_attrs()
}

///|
/// VectorDB - High-level vector database facade.
/// Provides a unified API for all ANN strategies: Bruteforce, HNSW, and IVF.
pub struct VectorDB {
  store : @core.CoreStore
  strategy : @core.Strategy
  bruteforce : @ann.BruteforceState?
  hnsw : @ann.HNSWState?
  ivf : @ann.IVFState?
}

///|
/// Create a new VectorDB with the given options
pub fn VectorDB::new(options : @core.DatabaseOptions) -> VectorDB {
  let store = @core.CoreStore::new(
    options.dim,
    options.metric,
    capacity=options.capacity,
  )
  match options.strategy {
    Bruteforce =>
      {
        bruteforce: Some(@ann.BruteforceState::new(options.metric)),
        hnsw: None,
        ivf: None,
        store,
        strategy: options.strategy,
      }
    HNSW(params) =>
      {
        bruteforce: None,
        hnsw: Some(
          @ann.HNSWState::new(params, options.metric, options.capacity),
        ),
        ivf: None,
        store,
        strategy: options.strategy,
      }
    IVF(params) =>
      {
        bruteforce: None,
        hnsw: None,
        ivf: Some(@ann.IVFState::new(params, options.metric, options.dim)),
        store,
        strategy: options.strategy,
      }
  }
}

///|
/// Create a VectorDB with default options (Bruteforce)
pub fn VectorDB::with_dim(dim : Int) -> VectorDB {
  VectorDB::new(@core.DatabaseOptions::default(dim))
}

///|
/// Create a VectorDB with HNSW strategy
pub fn VectorDB::with_hnsw(
  dim : Int,
  metric? : @core.Metric = Cosine,
) -> VectorDB {
  let options : @core.DatabaseOptions = {
    dim,
    metric,
    capacity: 1024,
    strategy: HNSW(@core.HNSWParams::default()),
  }
  VectorDB::new(options)
}

///|
/// Create a VectorDB with IVF strategy
pub fn VectorDB::with_ivf(
  dim : Int,
  metric? : @core.Metric = Cosine,
) -> VectorDB {
  let options : @core.DatabaseOptions = {
    dim,
    metric,
    capacity: 1024,
    strategy: IVF(@core.IVFParams::default()),
  }
  VectorDB::new(options)
}

///|
/// Get the number of vectors in the database
pub fn VectorDB::size(self : VectorDB) -> Int {
  self.store.size()
}

///|
/// Get the dimension of vectors
pub fn VectorDB::dim(self : VectorDB) -> Int {
  self.store.dim
}

///|
/// Get the metric used
pub fn VectorDB::metric(self : VectorDB) -> @core.Metric {
  self.store.metric
}

///|
/// Check if an id is tombstoned in HNSW (internal helper)
fn VectorDB::is_tombstoned(self : VectorDB, id : @core.VectorId) -> Bool {
  match self.hnsw {
    None => false
    Some(state) =>
      match self.store.get_index(id) {
        None => false
        Some(idx) => idx < state.tombstone.length() && state.tombstone[idx]
      }
  }
}

///|
/// Check if an id exists
/// For HNSW mode, tombstoned IDs are considered non-existent
pub fn VectorDB::has(self : VectorDB, id : @core.VectorId) -> Bool {
  if not(self.store.has(id)) {
    return false
  }
  // In HNSW mode, check tombstone
  not(self.is_tombstoned(id))
}

///|
/// Get a vector by id
/// For HNSW mode, tombstoned IDs return None
pub fn VectorDB::get(
  self : VectorDB,
  id : @core.VectorId,
) -> @core.VectorRecord? {
  // In HNSW mode, check tombstone first
  if self.is_tombstoned(id) {
    return None
  }
  self.store.get(id)
}

///|
/// Add a vector to the database
/// For HNSW mode, allows re-adding tombstoned IDs (clears tombstone and re-indexes)
pub fn VectorDB::add(
  self : VectorDB,
  id : @core.VectorId,
  vector : Array[Double],
  attrs : @core.Attrs,
) -> Unit {
  // Check if this is a tombstoned ID in HNSW mode (can be re-added)
  let was_tombstoned = self.is_tombstoned(id)
  if was_tombstoned {
    // Clear tombstone and update vector
    match self.hnsw {
      Some(state) =>
        match self.store.get_index(id) {
          Some(idx) =>
            if idx < state.tombstone.length() {
              state.tombstone[idx] = false
            }
          None => ()
        }
      None => ()
    }
    // Update the existing vector with upsert
    let _ = self.store.add_or_update(id, vector, attrs, upsert=true)
    // Re-add to HNSW graph
    match self.hnsw {
      Some(state) => @ann.hnsw_add(state, self.store, id)
      None => ()
    }
    return
  }
  // Normal add path
  let (_, created) = self.store.add_or_update(id, vector, attrs, upsert=false)
  if created {
    // Update index
    match self.hnsw {
      Some(state) => @ann.hnsw_add(state, self.store, id)
      None => ()
    }
    match self.ivf {
      Some(state) => @ann.ivf_add(state, self.store, id)
      None => ()
    }
  }
}

///|
/// Add or update a vector (upsert)
pub fn VectorDB::upsert(
  self : VectorDB,
  id : @core.VectorId,
  vector : Array[Double],
  attrs : @core.Attrs,
) -> Bool {
  let existed = self.store.has(id)
  let (_, created) = self.store.add_or_update(id, vector, attrs, upsert=true)
  if created {
    // New vector: add to index
    match self.hnsw {
      Some(state) => @ann.hnsw_add(state, self.store, id)
      None => ()
    }
    match self.ivf {
      Some(state) => @ann.ivf_add(state, self.store, id)
      None => ()
    }
  } else if existed {
    // Updated existing vector: need to reindex for ANN strategies
    // For HNSW: mark old as tombstone and re-add (graph connectivity update)
    match self.hnsw {
      Some(state) => {
        @ann.hnsw_remove(state, id, self.store)
        @ann.hnsw_add(state, self.store, id)
      }
      None => ()
    }
    // For IVF: remove from old centroid and reassign (no bootstrap)
    match self.ivf {
      Some(state) => {
        @ann.ivf_remove(state, id)
        @ann.ivf_assign(state, self.store, id)
      }
      None => ()
    }
  }
  created
}

///|
/// Remove a vector by id
/// Note: When using HNSW, this only marks as tombstone without physical removal.
/// Use compact() to reclaim space.
pub fn VectorDB::remove(self : VectorDB, id : @core.VectorId) -> Bool {
  // Check if vector exists (including tombstone check for HNSW)
  guard self.store.has(id) else { return false }
  // For HNSW, check if already tombstoned before reporting success
  match self.hnsw {
    Some(state) => {
      // Already tombstoned = already deleted, return false
      if self.is_tombstoned(id) {
        return false
      }
      @ann.hnsw_remove(state, id, self.store)
      return true // Don't remove from store, HNSW relies on stable indices
    }
    None => ()
  }
  // For IVF, remove from index
  match self.ivf {
    Some(state) => @ann.ivf_remove(state, id)
    None => ()
  }
  // Remove from store (only if not using HNSW)
  match self.store.remove_by_id(id) {
    Some(_) => true
    None => false
  }
}

///|
/// Search for k nearest neighbors
pub fn VectorDB::search(
  self : VectorDB,
  query : Array[Double],
  k : Int,
  filter : ((@core.VectorId, @core.Attrs) -> Bool)?,
) -> Array[@core.SearchHit] {
  match self.strategy {
    Bruteforce =>
      match self.bruteforce {
        Some(state) => @ann.bf_search(state, self.store, query, k, filter)
        None => []
      }
    HNSW(_) =>
      match self.hnsw {
        Some(state) => @ann.hnsw_search(state, self.store, query, k, filter)
        None => []
      }
    IVF(_) =>
      match self.ivf {
        Some(state) => @ann.ivf_search(state, self.store, query, k, filter)
        None => []
      }
  }
}

///|
/// Find the single best match
pub fn VectorDB::find(
  self : VectorDB,
  query : Array[Double],
  filter : ((@core.VectorId, @core.Attrs) -> Bool)?,
) -> @core.SearchHit? {
  let results = self.search(query, 1, filter)
  if results.is_empty() {
    None
  } else {
    Some(results[0])
  }
}

///|
/// Search with FilterExpr and optional attribute index for pre-filtering
/// - PreFilter: Use attr index to get candidates, then score only those
/// - PostFilter: Score all vectors, then filter results
/// - Auto: Choose based on estimated selectivity
pub fn VectorDB::search_with_expr(
  self : VectorDB,
  query : Array[Double],
  k : Int,
  expr : @filter.FilterExpr?,
  attr_index : @attr.BasicAttrIndex?,
  strategy : @filter.FilterStrategy,
) -> Array[@core.SearchHit] {
  match expr {
    None => self.search(query, k, None)
    Some(filter_expr) => {
      // Determine actual strategy
      let use_prefilter = match strategy {
        PreFilter => true
        PostFilter => false
        Auto =>
          // Use pre-filter if we have an attr index and can get candidates
          match attr_index {
            None => false
            Some(index) =>
              match @filter.get_candidates_basic(filter_expr, index) {
                None => false
                Some(candidates) =>
                  // Use pre-filter if candidates < 50% of total
                  candidates.length() < self.store.size() / 2
              }
          }
      }
      if use_prefilter {
        match attr_index {
          None => {
            // Fallback to post-filter
            let pred = @filter.compile_filter(filter_expr)
            self.search(query, k, Some(pred))
          }
          Some(index) =>
            match @filter.get_candidates_basic(filter_expr, index) {
              None => {
                // Cannot pre-filter, fallback to post-filter
                let pred = @filter.compile_filter(filter_expr)
                self.search(query, k, Some(pred))
              }
              Some(candidates) => self.search_candidates(query, k, candidates)
            }
        }
      } else {
        // Post-filter: compile expr to predicate and pass to search
        let pred = @filter.compile_filter(filter_expr)
        self.search(query, k, Some(pred))
      }
    }
  }
}

///|
/// Search only within a set of candidate IDs (for pre-filtering)
fn VectorDB::search_candidates(
  self : VectorDB,
  query : Array[Double],
  k : Int,
  candidates : Array[@core.VectorId],
) -> Array[@core.SearchHit] {
  // Validate query dimension
  guard query.length() == self.store.dim else { return [] }
  if candidates.is_empty() {
    return []
  }
  // Normalize query for cosine
  let q = self.store.normalize_query(query)
  let score_fn = @core.get_score_fn(self.store.metric)
  let dim = self.store.dim
  // Score all candidates, excluding tombstoned IDs
  let results : Array[@core.SearchHit] = []
  for id in candidates {
    // Skip tombstoned IDs (HNSW deletions)
    if self.is_tombstoned(id) {
      continue
    }
    match self.store.get_index(id) {
      None => continue
      Some(idx) => {
        let base = idx * dim
        let score = score_fn(self.store.data, base, q, dim)
        let attrs = self.store.attrs[idx]
        @core.push_top_k(results, @core.SearchHit::{ id, score, attrs }, k, fn(
          hit,
        ) {
          hit.score
        })
      }
    }
  }
  results
}

///|
/// Update only the attrs for a vector
pub fn VectorDB::update_attrs(
  self : VectorDB,
  id : @core.VectorId,
  attrs : @core.Attrs,
) -> Bool {
  self.store.update_attrs(id, attrs)
}

///|
/// Train IVF index (only applicable for IVF strategy)
pub fn VectorDB::train(self : VectorDB, iterations? : Int = 10) -> Unit {
  match self.ivf {
    Some(state) => @ann.ivf_train(state, self.store, iterations~)
    None => ()
  }
}

///|
/// Serialize database to bytes
pub fn VectorDB::serialize(self : VectorDB) -> Bytes {
  let w = @core.BinaryWriter::new()
  // Write strategy type and params
  match self.strategy {
    Bruteforce => w.push_u32(0U)
    // No params for bruteforce
    HNSW(params) => {
      w.push_u32(1U)
      // Serialize HNSW params
      w.push_u32(params.m.reinterpret_as_uint())
      w.push_u32(params.ef_construction.reinterpret_as_uint())
      w.push_u32(params.ef_search.reinterpret_as_uint())
      w.push_f64(params.level_mult)
      w.push_u64(params.seed)
      w.push_byte(if params.allow_replace_deleted { b'\x01' } else { b'\x00' })
    }
    IVF(params) => {
      w.push_u32(2U)
      // Serialize IVF params
      w.push_u32(params.nlist.reinterpret_as_uint())
      w.push_u32(params.nprobe.reinterpret_as_uint())
    }
  }
  // Write store
  let store_bytes = self.store.serialize()
  w.push_u32(store_bytes.length().reinterpret_as_uint())
  w.push_bytes(store_bytes)
  // Write index state
  match self.strategy {
    Bruteforce => {
      let bf_bytes = match self.bruteforce {
        Some(state) => @ann.bf_serialize(state)
        None => Bytes::new(0)
      }
      w.push_u32(bf_bytes.length().reinterpret_as_uint())
      w.push_bytes(bf_bytes)
    }
    HNSW(_) => {
      let hnsw_bytes = match self.hnsw {
        Some(state) => @ann.hnsw_serialize(state)
        None => Bytes::new(0)
      }
      w.push_u32(hnsw_bytes.length().reinterpret_as_uint())
      w.push_bytes(hnsw_bytes)
    }
    IVF(_) => {
      let ivf_bytes = match self.ivf {
        Some(state) => @ann.ivf_serialize(state, self.store.dim)
        None => Bytes::new(0)
      }
      w.push_u32(ivf_bytes.length().reinterpret_as_uint())
      w.push_bytes(ivf_bytes)
    }
  }
  w.concat()
}

///|
/// Deserialize database from bytes
pub fn VectorDB::deserialize(data : Bytes) -> VectorDB {
  let r = @core.BinaryReader::new(data)
  // Read strategy type
  let strategy_type = r.read_u32()
  // Read strategy params based on type
  let (hnsw_params, ivf_params) : (@core.HNSWParams?, @core.IVFParams?) = match
    strategy_type {
    0U => (None, None) // Bruteforce: no params
    1U => {
      // Read HNSW params
      let m = r.read_u32().reinterpret_as_int()
      let ef_construction = r.read_u32().reinterpret_as_int()
      let ef_search = r.read_u32().reinterpret_as_int()
      let level_mult = r.read_f64()
      let seed = r.read_u64()
      let allow_replace_deleted = r.read_byte() != b'\x00'
      (
        Some(@core.HNSWParams::{
          m,
          ef_construction,
          ef_search,
          level_mult,
          seed,
          allow_replace_deleted,
        }),
        None,
      )
    }
    _ => {
      // Read IVF params
      let nlist = r.read_u32().reinterpret_as_int()
      let nprobe = r.read_u32().reinterpret_as_int()
      (None, Some(@core.IVFParams::{ nlist, nprobe }))
    }
  }
  // Read store
  let store_len = r.read_u32().reinterpret_as_int()
  let store_bytes = r.read_bytes(store_len)
  let store = @core.CoreStore::deserialize(store_bytes)
  // Read index state and create db
  match strategy_type {
    0U => {
      let _ = r.read_u32() // bf_len (empty for bruteforce)
      {
        store,
        strategy: @core.Bruteforce,
        bruteforce: Some(@ann.BruteforceState::new(store.metric)),
        hnsw: None,
        ivf: None,
      }
    }
    1U => {
      let hnsw_len = r.read_u32().reinterpret_as_int()
      let hnsw_bytes = r.read_bytes(hnsw_len)
      let params = hnsw_params.unwrap()
      let state = @ann.HNSWState::new(params, store.metric, store.capacity())
      @ann.hnsw_deserialize(state, hnsw_bytes)
      {
        store,
        strategy: @core.HNSW(params),
        bruteforce: None,
        hnsw: Some(state),
        ivf: None,
      }
    }
    _ => {
      let ivf_len = r.read_u32().reinterpret_as_int()
      let ivf_bytes = r.read_bytes(ivf_len)
      let params = ivf_params.unwrap()
      let state = @ann.IVFState::new(params, store.metric, store.dim)
      @ann.ivf_deserialize(state, ivf_bytes, store.dim)
      {
        store,
        strategy: @core.IVF(params),
        bruteforce: None,
        hnsw: None,
        ivf: Some(state),
      }
    }
  }
}
