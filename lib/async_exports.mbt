///|
/// Persistence-aware FFI exports for JS environments.
///
/// Each DO shard gets its own instance_id. Multiple instances can coexist
/// in the same JS module without interfering — no global singleton.
///
/// Design principle: MoonBit handles data preparation synchronously.
/// JS handles all I/O asynchronously with proper await ordering.
///
/// WAL and checkpoint data are returned as Bytes for JS to persist.
/// This avoids MoonBit async runtime (incompatible with workerd)
/// while ensuring WAL writes are truly durable before proceeding.

///|
/// Instance storage — each DO shard gets its own VectorDB by instance_id.
let async_instances : @hashmap.HashMap[Int, @vcdb.VectorDB] = @hashmap.new()

///|
/// vid_from_pair and vid_to_pair are defined in exports.mbt (shared SoT).

///|
fn get_db(instance_id : Int) -> @vcdb.VectorDB {
  match async_instances.get(instance_id) {
    Some(db) => db
    None => abort("DB instance " + instance_id.to_string() + " not initialized")
  }
}

///|
/// Initialize a VectorDB instance with a caller-specified ID.
/// If an instance with this ID already exists, it is replaced.
/// The caller (each DO shard) must provide a stable, unique ID.
pub fn async_init_db(instance_id : Int, dim : Int, capacity : Int) -> Unit {
  let options : @types.DatabaseOptions = {
    dim,
    metric: @types.Cosine,
    capacity,
    strategy: @types.HNSW(@types.HNSWParams::default()),
  }
  async_instances[instance_id] = @vcdb.VectorDB::new(options)
}

///|
/// Initialize a VectorDB from a serialized snapshot with a caller-specified ID.
pub fn async_init_db_from_snapshot(instance_id : Int, data : Bytes) -> Unit {
  async_instances[instance_id] = @vcdb.VectorDB::deserialize(data)
}

///|
/// Initialize a VectorDB from a CoreStore (after WAL replay).
fn set_db_from_store(
  instance_id : Int,
  store : @store.CoreStore,
  dim : Int,
  capacity : Int,
) -> Unit {
  if store.size() > capacity {
    abort(
      "capacity (" +
      capacity.to_string() +
      ") is less than store size (" +
      store.size().to_string() +
      ")",
    )
  }
  let options : @types.DatabaseOptions = {
    dim,
    metric: @types.Cosine,
    capacity,
    strategy: @types.HNSW(@types.HNSWParams::default()),
  }
  async_instances[instance_id] = @vcdb.VectorDB::from_store(store, options)
}

///|
/// Replay WAL data onto a CoreStore, then initialize the DB.
/// Returns the number of records applied.
pub fn async_replay_wal_and_init(
  instance_id : Int,
  wal_data : Bytes,
  snapshot_data : Bytes,
  dim : Int,
  capacity : Int,
) -> Int {
  if snapshot_data.length() > 0 {
    let db = @vcdb.VectorDB::deserialize(snapshot_data)
    let store = db.store()
    let applied = @wal.replay_wal_data(wal_data, store)
    if applied > 0 {
      set_db_from_store(instance_id, store, dim, capacity)
    } else {
      async_instances[instance_id] = db
    }
    applied
  } else {
    let store = @store.CoreStore::new(dim, @types.Cosine, capacity=capacity)
    let applied = @wal.replay_wal_data(wal_data, store)
    set_db_from_store(instance_id, store, dim, capacity)
    applied
  }
}

///|
fn parse_json_to_attrs(json : String) -> @types.Attrs {
  if json.length() == 0 || json == "{}" {
    return @types.empty_attrs()
  }
  let bytes = @codec.encode_utf8(json)
  match @codec.decode_attrs_json(bytes) {
    Some(attrs) => attrs
    None => @types.empty_attrs()
  }
}

///|
/// Upsert points into an instance. Returns WAL segment bytes.
/// Each point is (id_hi, id_lo, vector, payload_json).
pub fn async_upsert(
  instance_id : Int,
  points : Array[(Int, Int, Array[Double], String)],
  timestamp_ns : Int64,
) -> Bytes {
  let db = get_db(instance_id)
  let typed_points : Array[(@types.VectorId, Array[Double], @types.Attrs)] = []
  for p in points {
    let (id_hi, id_lo, vector, payload_json) = p
    let vid = vid_from_pair(id_hi, id_lo)
    let attrs = parse_json_to_attrs(payload_json)
    let _ = db.upsert(vid, vector, attrs)
    typed_points.push((vid, vector, attrs))
  }
  let records : Array[@wal.WalRecord] = typed_points.map(fn(p) {
    let (id, vector, attrs) = p
    @wal.WalRecord::upsert(id, vector, attrs, timestamp=timestamp_ns)
  })
  @wal.encode_wal_segment(records)
}

///|
/// Search with optional attribute filtering.
pub fn async_search(
  instance_id : Int,
  query : Array[Double],
  k : Int,
  with_payload : Bool,
  filter_json : String,
) -> Array[(Int, Int, Double, String)] {
  let db = get_db(instance_id)
  let filter = @filter.parse_filter_json(filter_json)
  let hits = db.search_with_expr(query, k, filter, None, @filter.Auto)
  let results : Array[(Int, Int, Double, String)] = []
  for hit in hits {
    let payload_json = if with_payload {
      match db.get(hit.id) {
        Some(record) => @codec.attrs_to_json(Some(record.attrs))
        None => ""
      }
    } else {
      ""
    }
    let (hi, lo) = vid_to_pair(hit.id)
    results.push((hi, lo, hit.score, payload_json))
  }
  results
}

///|
/// Serialize the current DB state as a snapshot.
pub fn async_serialize_snapshot(instance_id : Int) -> Bytes {
  get_db(instance_id).serialize()
}

///|
/// Build a fresh WAL header (for truncation).
pub fn async_wal_header() -> Bytes {
  @wal.encode_wal_header()
}

///|
/// Merge an existing WAL with a new WAL segment.
pub fn async_merge_wal(existing : Bytes, new_segment : Bytes) -> Bytes {
  @wal.merge_wal(existing, new_segment)
}

///|
/// Get the maximum timestamp across all records in a WAL.
pub fn async_max_wal_timestamp(wal_data : Bytes) -> Int64 {
  @wal.max_wal_timestamp(wal_data)
}

///|
/// Replay WAL with timestamp cutoff (read-at-timestamp).
/// Returns the number of records applied.
pub fn async_replay_wal_at_timestamp(
  instance_id : Int,
  wal_data : Bytes,
  snapshot_data : Bytes,
  dim : Int,
  capacity : Int,
  cutoff_ts : Int64,
) -> Int {
  if snapshot_data.length() > 0 {
    let db = @vcdb.VectorDB::deserialize(snapshot_data)
    let store = db.store()
    let applied = @wal.replay_wal_data(wal_data, store, cutoff_ts=cutoff_ts)
    if applied > 0 {
      set_db_from_store(instance_id, store, dim, capacity)
    } else {
      async_instances[instance_id] = db
    }
    applied
  } else {
    let store = @store.CoreStore::new(dim, @types.Cosine, capacity=capacity)
    let applied = @wal.replay_wal_data(wal_data, store, cutoff_ts=cutoff_ts)
    set_db_from_store(instance_id, store, dim, capacity)
    applied
  }
}

///|
pub fn async_db_size(instance_id : Int) -> Int {
  get_db(instance_id).size()
}

///|
pub fn async_db_raw_size(instance_id : Int) -> Int {
  get_db(instance_id).raw_size()
}

///|
pub fn async_db_dim(instance_id : Int) -> Int {
  get_db(instance_id).dim()
}

///|
/// Remove a vector by ID. Returns WAL segment bytes.
pub fn async_remove(instance_id : Int, id_hi : Int, id_lo : Int, timestamp_ns : Int64) -> Bytes {
  let db = get_db(instance_id)
  let vid = vid_from_pair(id_hi, id_lo)
  if db.remove(vid) {
    @wal.encode_wal_segment([@wal.WalRecord::remove(vid, timestamp=timestamp_ns)])
  } else {
    Bytes::new(0)
  }
}

///|
/// Get a single vector and its payload by ID.
/// Returns (found, vector, payload_json).
pub fn async_get(
  instance_id : Int,
  id_hi : Int,
  id_lo : Int,
  with_payload : Bool,
) -> (Bool, Array[Double], String) {
  let db = get_db(instance_id)
  let vid = vid_from_pair(id_hi, id_lo)
  match db.get(vid) {
    Some(record) => {
      let payload = if with_payload {
        @codec.attrs_to_json(Some(record.attrs))
      } else {
        ""
      }
      (true, record.vector, payload)
    }
    None => (false, [], "")
  }
}

///|
pub fn async_has(instance_id : Int, id_hi : Int, id_lo : Int) -> Bool {
  get_db(instance_id).has(vid_from_pair(id_hi, id_lo))
}

///|
/// Update attributes without re-embedding. Returns WAL segment bytes.
pub fn async_update_attrs(
  instance_id : Int,
  id_hi : Int,
  id_lo : Int,
  attrs_json : String,
  timestamp_ns : Int64,
) -> Bytes {
  let db = get_db(instance_id)
  let vid = vid_from_pair(id_hi, id_lo)
  if not(db.has(vid)) {
    return Bytes::new(0)
  }
  let attrs = parse_json_to_attrs(attrs_json)
  let _ = db.update_attrs(vid, attrs)
  @wal.encode_wal_segment([@wal.WalRecord::set_attrs(vid, attrs, timestamp=timestamp_ns)])
}

///|
/// Scroll through vectors in ascending ID order.
pub fn async_scroll(
  instance_id : Int,
  offset_hi : Int,
  offset_lo : Int,
  has_offset : Bool,
  limit : Int,
  with_payload : Bool,
) -> Array[(Int, Int, String)] {
  let db = get_db(instance_id)
  let offset_i64 : Int64? = if has_offset {
    Some(vid_from_pair(offset_hi, offset_lo).to_int64())
  } else {
    None
  }
  let entries = db.scroll(offset=offset_i64, limit=limit)
  let results : Array[(Int, Int, String)] = []
  for entry in entries {
    let (vid, record) = entry
    let payload = if with_payload {
      @codec.attrs_to_json(Some(record.attrs))
    } else {
      ""
    }
    let (hi, lo) = vid_to_pair(vid)
    results.push((hi, lo, payload))
  }
  results
}

///|
/// Scroll with optional filter expression.
pub fn async_scroll_filtered(
  instance_id : Int,
  filter_json : String,
  offset_hi : Int,
  offset_lo : Int,
  has_offset : Bool,
  limit : Int,
  with_payload : Bool,
) -> Array[(Int, Int, String)] {
  let db = get_db(instance_id)
  let offset_i64 : Int64? = if has_offset {
    Some(vid_from_pair(offset_hi, offset_lo).to_int64())
  } else {
    None
  }
  let entries = match @filter.parse_filter_json(filter_json) {
    Some(e) => db.scroll_filtered(expr=Some(e), offset=offset_i64, limit=limit)
    None => db.scroll_filtered(offset=offset_i64, limit=limit)
  }
  let results : Array[(Int, Int, String)] = []
  for entry in entries {
    let (vid, record) = entry
    let payload = if with_payload {
      @codec.attrs_to_json(Some(record.attrs))
    } else {
      ""
    }
    let (hi, lo) = vid_to_pair(vid)
    results.push((hi, lo, payload))
  }
  results
}

///|
/// Count vectors matching a filter expression.
pub fn async_count_filtered(instance_id : Int, filter_json : String) -> Int {
  let db = get_db(instance_id)
  match @filter.parse_filter_json(filter_json) {
    Some(e) => db.count_filtered(expr=Some(e))
    None => db.count_filtered()
  }
}

///|
/// Compact HNSW index. Returns (snapshot_bytes, removed_count).
pub fn async_compact(instance_id : Int) -> (Bytes, Int) {
  let db = get_db(instance_id)
  let (new_db, removed) = db.compact()
  async_instances[instance_id] = new_db
  (new_db.serialize(), removed)
}

///|
/// Destroy an instance and free its memory.
pub fn async_destroy(instance_id : Int) -> Unit {
  async_instances.remove(instance_id)
}

///|
/// Serialize a FilterExpr to JSON string (round-trip with parse_filter_json).
pub fn async_serialize_filter(filter_json : String) -> String {
  match @filter.parse_filter_json(filter_json) {
    Some(expr) => @filter.filter_to_json(expr)
    None => "{}"
  }
}
