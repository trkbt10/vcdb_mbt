///|
/// Persistence-aware FFI exports for JS environments.
///
/// Design principle: MoonBit handles data preparation synchronously.
/// JS handles all I/O asynchronously with proper await ordering.
///
/// WAL and checkpoint data are returned as Bytes for JS to persist.
/// This avoids MoonBit async runtime (incompatible with workerd)
/// while ensuring WAL writes are truly durable before proceeding.

///|
/// Managed VectorDB instance for the async gateway.
let async_db_instance : Ref[@vcdb.VectorDB?] = { val: None }

///|
/// WAL state tracking.
struct WalState {
  mut path : String
  mut record_count : Int
}

///|
let wal_state : WalState = { path: "", record_count: 0 }

///|
/// Initialize a VectorDB from existing data (or create empty).
/// Called by JS after loading snapshot + WAL replay.
pub fn async_init_db(dim : Int) -> Unit {
  let options : @types.DatabaseOptions = {
    dim,
    metric: @types.Cosine,
    capacity: 65536,
    strategy: @types.HNSW(@types.HNSWParams::default()),
  }
  async_db_instance.val = Some(@vcdb.VectorDB::new(options))
}

///|
/// Initialize a VectorDB from a serialized snapshot.
pub fn async_init_db_from_snapshot(data : Bytes) -> Unit {
  async_db_instance.val = Some(@vcdb.VectorDB::deserialize(data))
}

///|
/// Initialize a VectorDB from a CoreStore (after WAL replay).
fn async_init_db_from_store(
  store : @store.CoreStore,
  dim : Int,
) -> Unit {
  let options : @types.DatabaseOptions = {
    dim,
    metric: @types.Cosine,
    capacity: @math.maximum(store.size() + 4096, 65536),
    strategy: @types.HNSW(@types.HNSWParams::default()),
  }
  async_db_instance.val = Some(@vcdb.VectorDB::from_store(store, options))
}

///|
/// Replay WAL data onto a CoreStore, then initialize the DB.
/// Returns the number of records applied.
pub fn async_replay_wal_and_init(
  wal_data : Bytes,
  snapshot_data : Bytes,
  dim : Int,
) -> Int {
  if snapshot_data.length() > 0 {
    // Snapshot is VectorDB::serialize format (includes strategy + index state)
    let db = @vcdb.VectorDB::deserialize(snapshot_data)
    let store = db.store()
    let applied = @wal.replay_wal_data(wal_data, store)
    if applied > 0 {
      // WAL had records — rebuild DB from updated store
      async_init_db_from_store(store, dim)
    } else {
      // No WAL changes — use deserialized DB as-is
      async_db_instance.val = Some(db)
    }
    applied
  } else {
    // No snapshot — build from WAL only
    let store = @store.CoreStore::new(dim, @types.Cosine, capacity=1024)
    let applied = @wal.replay_wal_data(wal_data, store)
    async_init_db_from_store(store, dim)
    applied
  }
}

///|
/// Upsert points into the in-memory DB.
/// payload_json is a JSON string for each point's attrs.
/// Returns the WAL binary data that JS must persist.
pub fn async_upsert(
  points : Array[(Double, Array[Double], String)],
) -> Bytes {
  let db = match async_db_instance.val {
    Some(d) => d
    None => abort("DB not initialized")
  }
  let typed_points : Array[(@types.VectorId, Array[Double], @types.Attrs)] = []
  for p in points {
    let (id, vector, payload_json) = p
    let vid = @types.VectorId(id.to_int64())
    let attrs = parse_json_to_attrs(payload_json)
    let _ = db.upsert(vid, vector, attrs)
    typed_points.push((vid, vector, attrs))
  }
  let records : Array[@wal.WalRecord] = typed_points.map(fn(p) {
    let (id, vector, attrs) = p
    @wal.WalRecord::upsert(id, vector, attrs)
  })
  @wal.encode_wal_segment(records)
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
/// Search the in-memory DB with optional attribute filtering.
/// filter_json: JSON string describing filter conditions, or empty for no filter.
///
/// Filter format (flat key-value match, AND logic):
///   {"category": "科学", "status": "解決済み"}
///   → must match both category=科学 AND status=解決済み
///
/// Returns array of (id, score, payload_json_or_empty).
pub fn async_search(
  query : Array[Double],
  k : Int,
  with_payload : Bool,
  filter_json : String,
) -> Array[(Double, Double, String)] {
  let db = match async_db_instance.val {
    Some(d) => d
    None => abort("DB not initialized")
  }
  let filter = parse_filter(filter_json)
  let hits = db.search_with_expr(query, k, filter, None, @filter.Auto)
  let results : Array[(Double, Double, String)] = []
  for hit in hits {
    let payload_json = if with_payload {
      match db.get(hit.id) {
        Some(record) => @codec.attrs_to_json(Some(record.attrs))
        None => ""
      }
    } else {
      ""
    }
    results.push((vector_id_to_double(hit.id), hit.score, payload_json))
  }
  results
}

///|
/// Parse a flat JSON object into a FilterExpr.
/// {"category": "科学"} → Must([Match("category", String("科学"))])
/// Empty/null → None (no filtering)
fn parse_filter(json : String) -> @filter.FilterExpr? {
  if json.length() == 0 || json == "{}" {
    return None
  }
  let attrs = parse_json_to_attrs(json)
  let conditions : Array[@filter.FilterExpr] = []
  for key in attrs.keys() {
    match attrs.get(key) {
      Some(value) => conditions.push(@filter.FilterExpr::match_(key, value))
      None => ()
    }
  }
  if conditions.is_empty() {
    None
  } else if conditions.length() == 1 {
    Some(conditions[0])
  } else {
    Some(@filter.FilterExpr::must(conditions))
  }
}

///|
/// Serialize the current DB state as a snapshot.
/// JS calls this during checkpoint, then persists the returned bytes.
pub fn async_serialize_snapshot() -> Bytes {
  match async_db_instance.val {
    Some(db) => db.serialize()
    None => abort("DB not initialized")
  }
}

///|
/// Build a fresh WAL header (for truncation).
/// JS writes this to the WAL path to "truncate" it.
pub fn async_wal_header() -> Bytes {
  @wal.encode_wal_header()
}

///|
/// Merge an existing WAL with a new WAL segment.
/// Returns a valid WAL with correct CRC footer.
/// This is the only correct way to accumulate WAL records.
pub fn async_merge_wal(existing : Bytes, new_segment : Bytes) -> Bytes {
  @wal.merge_wal(existing, new_segment)
}

///|
/// Get the current DB size.
pub fn async_db_size() -> Int {
  match async_db_instance.val {
    Some(db) => db.size()
    None => 0
  }
}
