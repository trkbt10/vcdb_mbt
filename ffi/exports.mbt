///|
/// FFI exports for JavaScript interop.
///
/// All vector IDs are passed as (hi: Int, lo: Int) pairs — never as Double.
/// This is the only way to construct/extract VectorIds in the FFI.
/// Double-based paths are structurally impossible.

///|
/// Bridge: run an async function synchronously.
/// Safe for MemoryStorage where all I/O resolves immediately.
fn run_async(f : async () -> Unit noraise) -> Unit = "%async.run"

///|
/// Global instance storage
let instances : @hashmap.HashMap[
  Int,
  @vcdb.PersistentDB[@storage.MemoryStorage, @storage.MemoryStorage],
] = @hashmap.new()

///|
priv struct Counter {
  mut value : Int
}

///|
let counter : Counter = { value: 1 }

///|
/// Construct an Int64Id from hi/lo Int pair (SoT for Int64 ID construction).
fn vid_from_pair(hi : Int, lo : Int) -> @types.VectorId {
  let hi64 = hi.to_int64()
  let lo64 = lo.to_int64().land(0xFFFFFFFFL)
  @types.Int64Id((hi64 << 32) | lo64)
}

///|
/// Extract hi/lo pair from a VectorId.
/// Int64Id: direct hi/lo extraction.
/// Bytes16Id: hi = upper 8 bytes as Int64, lo = lower 8 bytes truncated to Int32.
fn vid_to_pair(id : @types.VectorId) -> (Int, Int) {
  match id {
    @types.Int64Id(v) => {
      let hi = (v.reinterpret_as_uint64() >> 32).to_int()
      let lo = v.to_int()
      (hi, lo)
    }
    @types.Bytes16Id(b) => {
      let (hi64, lo64) = b.to_hi_lo()
      let hi = (hi64.reinterpret_as_uint64() >> 32).to_int()
      let lo = hi64.to_int()
      // Note: this loses the lower 8 bytes. Use vcdb_id_to_uuid for Bytes16Id.
      ignore(lo64)
      (hi, lo)
    }
  }
}

///|
/// Construct a Bytes16Id from a UUID string.
/// Returns None if the string is not a valid UUID.
pub fn vid_from_uuid(s : String) -> @types.VectorId? {
  @types.VectorId::from_uuid_string(s)
}

///|
/// Extract UUID string from a VectorId.
/// Int64Id: formatted as decimal string (not a UUID).
/// Bytes16Id: formatted as UUID string.
pub fn vcdb_id_to_string(id : @types.VectorId) -> String {
  id.to_display_string()
}

///|
pub fn vcdb_add_uuid(
  instance_id : Int,
  uuid : String,
  vector : Array[Double],
) -> Int {
  match (instances.get(instance_id), @types.VectorId::from_uuid_string(uuid)) {
    (Some(db), Some(id)) => {
      if db.has(id) {
        return -2
      }
      let attrs = @types.empty_attrs()
      run_async(async fn() noraise {
        let _ = db.add(id, vector, attrs, 0L) catch {
          _ => false
        }
      })
      0
    }
    _ => -1
  }
}

///|
pub fn vcdb_upsert_uuid(
  instance_id : Int,
  uuid : String,
  vector : Array[Double],
) -> Int {
  match (instances.get(instance_id), @types.VectorId::from_uuid_string(uuid)) {
    (Some(db), Some(id)) => {
      let attrs = @types.empty_attrs()
      run_async(async fn() noraise {
        db.upsert([(id, vector, attrs)], 0L) catch {
          _ => ()
        }
      })
      0
    }
    _ => -1
  }
}

///|
pub fn vcdb_get_uuid(
  instance_id : Int,
  uuid : String,
) -> (Array[Double], Int) {
  match (instances.get(instance_id), @types.VectorId::from_uuid_string(uuid)) {
    (Some(db), Some(id)) =>
      match db.get(id) {
        Some(record) => (record.vector, 1)
        None => ([], 0)
      }
    _ => ([], -1)
  }
}

///|
pub fn vcdb_has_uuid(instance_id : Int, uuid : String) -> Int {
  match (instances.get(instance_id), @types.VectorId::from_uuid_string(uuid)) {
    (Some(db), Some(id)) => if db.has(id) { 1 } else { 0 }
    _ => -1
  }
}

///|
pub fn vcdb_remove_uuid(instance_id : Int, uuid : String) -> Int {
  match (instances.get(instance_id), @types.VectorId::from_uuid_string(uuid)) {
    (Some(db), Some(id)) => {
      let mut result = 0
      run_async(async fn() noraise {
        let removed = db.remove(id, 0L) catch {
          _ => false
        }
        result = if removed { 1 } else { 0 }
      })
      result
    }
    _ => -1
  }
}

///|
pub fn vcdb_create(dim : Int) -> Int {
  let id = counter.value
  counter.value = counter.value + 1
  run_async(async fn() noraise {
    let db = @vcdb.PersistentDB::in_memory_bruteforce(dim) catch {
      _ => abort("vcdb_create failed")
    }
    instances[id] = db
  })
  id
}

///|
pub fn vcdb_create_hnsw(dim : Int) -> Int {
  let id = counter.value
  counter.value = counter.value + 1
  run_async(async fn() noraise {
    let db = @vcdb.PersistentDB::in_memory_hnsw(dim) catch {
      _ => abort("vcdb_create_hnsw failed")
    }
    instances[id] = db
  })
  id
}

///|
pub fn vcdb_create_ivf(dim : Int) -> Int {
  let id = counter.value
  counter.value = counter.value + 1
  run_async(async fn() noraise {
    let db = @vcdb.PersistentDB::in_memory_ivf(dim) catch {
      _ => abort("vcdb_create_ivf failed")
    }
    instances[id] = db
  })
  id
}

///|
pub fn vcdb_destroy(instance_id : Int) -> Unit {
  instances.remove(instance_id)
}

///|
pub fn vcdb_size(instance_id : Int) -> Int {
  match instances.get(instance_id) {
    Some(db) => db.size()
    None => -1
  }
}

///|
pub fn vcdb_dim(instance_id : Int) -> Int {
  match instances.get(instance_id) {
    Some(db) => db.dim()
    None => -1
  }
}

///|
pub fn vcdb_add(
  instance_id : Int,
  id_hi : Int,
  id_lo : Int,
  vector : Array[Double],
) -> Int {
  match instances.get(instance_id) {
    Some(db) => {
      let id = vid_from_pair(id_hi, id_lo)
      if db.has(id) {
        return -2
      }
      let attrs = @types.empty_attrs()
      run_async(async fn() noraise {
        let _ = db.add(id, vector, attrs, 0L) catch {
          _ => false
        }
      })
      0
    }
    None => -1
  }
}

///|
pub fn vcdb_upsert(
  instance_id : Int,
  id_hi : Int,
  id_lo : Int,
  vector : Array[Double],
) -> Int {
  match instances.get(instance_id) {
    Some(db) => {
      let attrs = @types.empty_attrs()
      run_async(async fn() noraise {
        db.upsert([(vid_from_pair(id_hi, id_lo), vector, attrs)], 0L) catch {
          _ => ()
        }
      })
      0
    }
    None => -1
  }
}

///|
pub fn vcdb_get(
  instance_id : Int,
  id_hi : Int,
  id_lo : Int,
) -> (Array[Double], Int) {
  match instances.get(instance_id) {
    Some(db) =>
      match db.get(vid_from_pair(id_hi, id_lo)) {
        Some(record) => (record.vector, 1)
        None => ([], 0)
      }
    None => ([], -1)
  }
}

///|
pub fn vcdb_search(
  instance_id : Int,
  query : Array[Double],
  k : Int,
) -> Array[(Int, Int, Double)] {
  match instances.get(instance_id) {
    Some(db) => {
      let results = db.search(query, k, None)
      let out : Array[(Int, Int, Double)] = []
      for hit in results {
        let (hi, lo) = vid_to_pair(hit.id)
        out.push((hi, lo, hit.score))
      }
      out
    }
    None => []
  }
}

///|
pub fn vcdb_has(instance_id : Int, id_hi : Int, id_lo : Int) -> Int {
  match instances.get(instance_id) {
    Some(db) => if db.has(vid_from_pair(id_hi, id_lo)) { 1 } else { 0 }
    None => -1
  }
}

///|
pub fn vcdb_remove(instance_id : Int, id_hi : Int, id_lo : Int) -> Int {
  match instances.get(instance_id) {
    Some(db) => {
      let mut result = 0
      run_async(async fn() noraise {
        let removed = db.remove(vid_from_pair(id_hi, id_lo), 0L) catch {
          _ => false
        }
        result = if removed { 1 } else { 0 }
      })
      result
    }
    None => -1
  }
}

///|
pub fn vcdb_serialize(instance_id : Int) -> Bytes {
  match instances.get(instance_id) {
    Some(db) => db.serialize_snapshot()
    None => b""
  }
}

///|
pub fn vcdb_deserialize(data : Bytes) -> Int {
  let id = counter.value
  counter.value = counter.value + 1
  instances[id] = @vcdb.PersistentDB::deserialize(data)
  id
}

///|
/// Parse JSON string to Attrs (used by persistent_exports)
fn parse_json_to_attrs(json : String) -> @types.Attrs {
  if json.length() == 0 || json == "{}" {
    return @types.empty_attrs()
  }
  @codec.parse_attrs_json(json).unwrap_or(@types.empty_attrs())
}

// ============================================================================
// CRUSH placement — deterministic vector-to-shard mapping
// ============================================================================

///|
/// Compute placement group for a vector ID.
/// This is the SoT for shard routing — JS consumers MUST use this
/// instead of implementing their own hash function.
///
/// Returns a placement group number in [0, pg_count).
pub fn crush_placement_group(id_hi : Int, id_lo : Int, pg_count : Int) -> Int {
  let vid = vid_from_pair(id_hi, id_lo)
  let map = @placement.CrushMap::new(pg_count, 1, [])
  let result = @placement.crush_locate(vid, map)
  result.pg
}

// ============================================================================
// Gateway API — JS exports are in gateway_exports.mbt (JS-only)
// ============================================================================

///|
/// Keep @gateway import alive for JS-only gateway_exports.mbt.
fn _gateway_import_anchor() -> @gateway.CollectionConfig {
  @gateway.CollectionConfig::default("", 0)
}
