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
let instances : @hashmap.HashMap[Int, @vcdb.VectorDB[@storage.MemoryStorage, @storage.MemoryStorage]] = @hashmap.new()

///|
priv struct Counter {
  mut value : Int
}

///|
let counter : Counter = { value: 1 }

///|
/// Construct a VectorId from hi/lo Int pair (SoT for ID construction).
fn vid_from_pair(hi : Int, lo : Int) -> @types.VectorId {
  let hi64 = hi.to_int64()
  let lo64 = lo.to_int64().land(0xFFFFFFFFL)
  @types.VectorId(hi64.lsl(32).lor(lo64))
}

///|
/// Extract hi/lo pair from VectorId (SoT for ID extraction).
fn vid_to_pair(id : @types.VectorId) -> (Int, Int) {
  let v = id.to_int64()
  let hi = v.lsr(32).to_int()
  let lo = v.to_int()
  (hi, lo)
}

///|
pub fn vcdb_create(dim : Int) -> Int {
  let id = counter.value
  counter.value = counter.value + 1
  run_async(async fn() noraise {
    let db = @vcdb.VectorDB::in_memory_bruteforce(dim) catch { _ => abort("vcdb_create failed") }
    instances[id] = db
  })
  id
}

///|
pub fn vcdb_create_hnsw(dim : Int) -> Int {
  let id = counter.value
  counter.value = counter.value + 1
  run_async(async fn() noraise {
    let db = @vcdb.VectorDB::in_memory_hnsw(dim) catch { _ => abort("vcdb_create_hnsw failed") }
    instances[id] = db
  })
  id
}

///|
pub fn vcdb_create_ivf(dim : Int) -> Int {
  let id = counter.value
  counter.value = counter.value + 1
  run_async(async fn() noraise {
    let db = @vcdb.VectorDB::in_memory_ivf(dim) catch { _ => abort("vcdb_create_ivf failed") }
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
        db.add(id, vector, attrs, 0L) catch { _ => () }
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
  instances[id] = @vcdb.VectorDB::deserialize(data)
  id
}

///|
/// Parse JSON string to Attrs (used by persistent_exports)
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
/// Convert StorageKind to Int (used by persistent_exports and gateway_exports)
fn kind_to_int(kind : @storage.StorageKind) -> Int {
  match kind {
    @storage.Config => 0
    @storage.Index => 1
    @storage.Data => 2
  }
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
/// Global storage for gateway (in-memory, implements both Storage and AsyncStorage)
let gateway_storage : @storage.MemoryStorage = @storage.MemoryStorage::new()

///|
/// Manager with MemoryStorage
let gateway_manager : @gateway.CollectionManager[@storage.MemoryStorage] = @gateway.CollectionManager::with_storage(
  gateway_storage,
)
