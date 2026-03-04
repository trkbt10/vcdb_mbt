///|
/// vcdb - A high-performance vector database for approximate nearest neighbor search.
///
/// This module provides the main VectorDB facade that unifies access to different
/// ANN (Approximate Nearest Neighbor) indexing strategies:
/// - Bruteforce: Exact linear scan, best for small datasets (<1000 vectors)
/// - HNSW: Hierarchical Navigable Small World graphs, best for general use
/// - IVF: Inverted File Index, best for large datasets with training
///
/// Example:
/// ```moonbit
/// let db = VectorDB::with_hnsw(128, metric=Cosine)
/// db.add(VectorId::from_int(1), embedding, attrs)
/// let results = db.search(query, k=10, filter=None)
/// ```

///|
/// Re-export factory functions for convenience
pub fn empty_attrs() -> @core.Attrs {
  @core.empty_attrs()
}

///|
/// VectorDB - High-level vector database facade.
///
/// Provides a unified API for all ANN strategies: Bruteforce, HNSW, and IVF.
/// The database automatically handles:
/// - Vector normalization for cosine similarity
/// - Index updates on add/remove operations
/// - Tombstone management for HNSW deletions
///
/// Fields:
/// - store: The underlying CoreStore holding vectors and attributes
/// - strategy: The selected ANN strategy (Bruteforce/HNSW/IVF)
/// - bruteforce/hnsw/ivf: Strategy-specific index state
pub struct VectorDB {
  store : @core.CoreStore
  strategy : @core.Strategy
  bruteforce : @ann.BruteforceState?
  hnsw : @ann.HNSWState?
  ivf : @ann.IVFState?
}

///|
/// Create a new VectorDB with the given options.
///
/// Parameters:
/// - options: Configuration including dimension, metric, capacity, and strategy
///
/// Returns: A new VectorDB instance configured according to options
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
/// Create a VectorDB with default options (Bruteforce strategy).
///
/// Parameters:
/// - dim: Vector dimension
///
/// Returns: A VectorDB with Bruteforce strategy and Cosine metric
pub fn VectorDB::with_dim(dim : Int) -> VectorDB {
  VectorDB::new(@core.DatabaseOptions::default(dim))
}

///|
/// Create a VectorDB with HNSW strategy.
///
/// HNSW (Hierarchical Navigable Small World) is recommended for most use cases.
/// It provides O(log n) search time with high recall.
///
/// Parameters:
/// - dim: Vector dimension
/// - metric: Similarity metric (default: Cosine)
///
/// Returns: A VectorDB configured with HNSW index
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
/// Create a VectorDB with IVF strategy.
///
/// IVF (Inverted File Index) is best for very large datasets.
/// Requires training with train() before optimal search performance.
///
/// Parameters:
/// - dim: Vector dimension
/// - metric: Similarity metric (default: Cosine)
///
/// Returns: A VectorDB configured with IVF index
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
/// Get the number of accessible vectors in the database.
///
/// For HNSW, this excludes tombstoned (deleted) vectors.
/// Use raw_size() to get the total count including tombstones.
pub fn VectorDB::size(self : VectorDB) -> Int {
  match self.hnsw {
    Some(state) => {
      let (alive, _) = @ann.hnsw_tombstone_stats(state, self.store)
      alive
    }
    None => self.store.size()
  }
}

///|
/// Get the raw size including tombstoned vectors.
/// This is primarily for internal use and serialization.
pub fn VectorDB::raw_size(self : VectorDB) -> Int {
  self.store.size()
}

///|
/// Get the dimension of vectors in this database.
pub fn VectorDB::dim(self : VectorDB) -> Int {
  self.store.dim
}

///|
/// Get the similarity metric used by this database.
pub fn VectorDB::metric(self : VectorDB) -> @core.Metric {
  self.store.metric
}

///|
/// Get access to the underlying CoreStore (for distributed storage operations)
pub fn VectorDB::store(self : VectorDB) -> @core.CoreStore {
  self.store
}

///|
/// Create VectorDB from an existing CoreStore (for loading from distributed storage)
pub fn VectorDB::from_store(
  store : @core.CoreStore,
  options : @core.DatabaseOptions,
) -> VectorDB {
  match options.strategy {
    Bruteforce =>
      {
        bruteforce: Some(@ann.BruteforceState::new(store.metric)),
        hnsw: None,
        ivf: None,
        store,
        strategy: options.strategy,
      }
    HNSW(params) => {
      let hnsw = @ann.HNSWState::new(params, store.metric, options.capacity)
      // Rebuild HNSW index from store
      for i in 0..<store.size() {
        let id = store.ids[i]
        @ann.hnsw_add(hnsw, store, id)
      }
      {
        bruteforce: None,
        hnsw: Some(hnsw),
        ivf: None,
        store,
        strategy: options.strategy,
      }
    }
    IVF(params) => {
      let ivf = @ann.IVFState::new(params, store.metric, store.dim)
      // IVF requires training
      {
        bruteforce: None,
        hnsw: None,
        ivf: Some(ivf),
        store,
        strategy: options.strategy,
      }
    }
  }
}

///|
/// Check if an id is tombstoned in HNSW (internal helper).
///
/// HNSW uses tombstones for soft-delete to maintain graph connectivity.
/// Tombstoned vectors are excluded from search results but remain in storage
/// until compact() is called.
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
/// Check if an id exists and is accessible.
///
/// For HNSW mode, tombstoned IDs are considered non-existent.
///
/// Parameters:
/// - id: The vector ID to check
///
/// Returns: true if the vector exists and is not tombstoned
pub fn VectorDB::has(self : VectorDB, id : @core.VectorId) -> Bool {
  if not(self.store.has(id)) {
    return false
  }
  not(self.is_tombstoned(id))
}

///|
/// Get a vector and its attributes by ID.
///
/// For HNSW mode, tombstoned IDs return None.
///
/// Parameters:
/// - id: The vector ID to retrieve
///
/// Returns: The vector record if found and accessible, None otherwise
pub fn VectorDB::get(
  self : VectorDB,
  id : @core.VectorId,
) -> @core.VectorRecord? {
  if self.is_tombstoned(id) {
    return None
  }
  self.store.get(id)
}

///|
/// Add a new vector to the database.
///
/// For HNSW mode, allows re-adding tombstoned IDs (clears tombstone and re-indexes).
/// Fails if the ID already exists and is not tombstoned.
///
/// Parameters:
/// - id: Unique identifier for the vector
/// - vector: The embedding vector (must match database dimension)
/// - attrs: Metadata attributes for filtering
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
/// Add or update a vector (upsert operation).
///
/// If the ID exists, updates the vector and reindexes.
/// If the ID doesn't exist, adds a new vector.
///
/// Parameters:
/// - id: Unique identifier for the vector
/// - vector: The embedding vector
/// - attrs: Metadata attributes
///
/// Returns: true if a new vector was created, false if existing was updated
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
    match self.hnsw {
      Some(state) => {
        @ann.hnsw_remove(state, id, self.store)
        @ann.hnsw_add(state, self.store, id)
      }
      None => ()
    }
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
/// Remove a vector by ID.
///
/// Behavior differs by strategy:
/// - Bruteforce/IVF: Physically removes the vector
/// - HNSW: Marks as tombstone (soft delete) to maintain graph connectivity
///
/// For HNSW, use compact() to reclaim space from tombstoned vectors.
///
/// Parameters:
/// - id: The vector ID to remove
///
/// Returns: true if the vector was removed, false if not found or already deleted
pub fn VectorDB::remove(self : VectorDB, id : @core.VectorId) -> Bool {
  guard self.store.has(id) else { return false }
  // For HNSW, check if already tombstoned
  match self.hnsw {
    Some(state) => {
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
/// Search for k nearest neighbors to a query vector.
///
/// Parameters:
/// - query: The query vector (must match database dimension)
/// - k: Number of results to return
/// - filter: Optional predicate to filter results by ID and attributes
///
/// Returns: Array of SearchHit sorted by score (highest/most similar first)
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
/// Find the single best match for a query.
///
/// Convenience method equivalent to search(query, 1, filter).
///
/// Parameters:
/// - query: The query vector
/// - filter: Optional filter predicate
///
/// Returns: The best matching SearchHit, or None if no matches
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
/// Search with filter expressions and optional attribute index.
///
/// Supports two filtering strategies:
/// - PreFilter: Use attr index to get candidate IDs, then score only those
/// - PostFilter: Score all vectors, then filter results
/// - Auto: Automatically choose based on estimated selectivity
///
/// PreFilter is more efficient when the filter is selective (<50% of vectors).
/// PostFilter is better for broad filters or when no attr index is available.
///
/// Parameters:
/// - query: The query vector
/// - k: Number of results to return
/// - expr: Optional filter expression (Must/MustNot/Should/Leaf)
/// - attr_index: Optional attribute index for pre-filtering
/// - strategy: Filtering strategy (PreFilter/PostFilter/Auto)
///
/// Returns: Array of SearchHit matching the filter criteria
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
            let pred = @filter.compile_filter(filter_expr)
            self.search(query, k, Some(pred))
          }
          Some(index) =>
            match @filter.get_candidates_basic(filter_expr, index) {
              None => {
                let pred = @filter.compile_filter(filter_expr)
                self.search(query, k, Some(pred))
              }
              Some(candidates) => self.search_candidates(query, k, candidates)
            }
        }
      } else {
        let pred = @filter.compile_filter(filter_expr)
        self.search(query, k, Some(pred))
      }
    }
  }
}

///|
/// Search only within a set of candidate IDs (for pre-filtering).
///
/// Internal method used by search_with_expr for pre-filter strategy.
/// Scores only the specified candidate vectors instead of all vectors.
fn VectorDB::search_candidates(
  self : VectorDB,
  query : Array[Double],
  k : Int,
  candidates : Array[@core.VectorId],
) -> Array[@core.SearchHit] {
  guard query.length() == self.store.dim else { return [] }
  if candidates.is_empty() {
    return []
  }
  let q = self.store.normalize_query(query)
  let score_fn = @core.get_score_fn(self.store.metric)
  let dim = self.store.dim
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
        @collection.push_top_k(
          results,
          @core.SearchHit::{ id, score, attrs },
          k,
          fn(hit) { hit.score },
        )
      }
    }
  }
  results
}

///|
/// Update only the attributes for a vector (without changing the embedding).
///
/// Parameters:
/// - id: The vector ID to update
/// - attrs: New attributes to set
///
/// Returns: true if updated, false if ID not found
pub fn VectorDB::update_attrs(
  self : VectorDB,
  id : @core.VectorId,
  attrs : @core.Attrs,
) -> Bool {
  self.store.update_attrs(id, attrs)
}

///|
/// Train the IVF index for optimal search performance.
///
/// Only applicable for IVF strategy. Call this after adding a representative
/// sample of vectors to build the centroid clusters.
///
/// Parameters:
/// - iterations: Number of k-means iterations (default: 10)
pub fn VectorDB::train(self : VectorDB, iterations? : Int = 10) -> Unit {
  match self.ivf {
    Some(state) => @ann.ivf_train(state, self.store, iterations~)
    None => ()
  }
}

///|
/// Serialize the database to bytes for persistence.
///
/// Includes all vectors, attributes, and index state.
/// Use deserialize() to restore.
///
/// Returns: Binary representation of the database
pub fn VectorDB::serialize(self : VectorDB) -> Bytes {
  let w = @binary.BinaryWriter::new()
  // Write strategy type and params
  match self.strategy {
    Bruteforce => w.push_u32(0U)
    HNSW(params) => {
      w.push_u32(1U)
      w.push_u32(params.m.reinterpret_as_uint())
      w.push_u32(params.ef_construction.reinterpret_as_uint())
      w.push_u32(params.ef_search.reinterpret_as_uint())
      w.push_f64(params.level_mult)
      w.push_u64(params.seed)
      w.push_byte(if params.allow_replace_deleted { b'\x01' } else { b'\x00' })
    }
    IVF(params) => {
      w.push_u32(2U)
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
/// Deserialize a database from bytes.
///
/// Restores all vectors, attributes, and index state from a previous serialize().
///
/// Parameters:
/// - data: Binary data from serialize()
///
/// Returns: The restored VectorDB instance
pub fn VectorDB::deserialize(data : Bytes) -> VectorDB {
  let r = @binary.BinaryReader::new(data)
  let strategy_type = r.read_u32()
  let (hnsw_params, ivf_params) : (@core.HNSWParams?, @core.IVFParams?) = match
    strategy_type {
    0U => (None, None)
    1U => {
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
      let nlist = r.read_u32().reinterpret_as_int()
      let nprobe = r.read_u32().reinterpret_as_int()
      (None, Some(@core.IVFParams::{ nlist, nprobe }))
    }
  }
  let store_len = r.read_u32().reinterpret_as_int()
  let store_bytes = r.read_bytes(store_len)
  let store = @core.CoreStore::deserialize(store_bytes)
  match strategy_type {
    0U => {
      let _ = r.read_u32()
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
