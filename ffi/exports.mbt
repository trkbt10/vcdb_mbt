///|
/// FFI exports for JavaScript interop.
///
/// Wire format for VectorId: Bytes of exactly 16 bytes.
///   Int64Id(v)    → bytes 0-7 = v big-endian, bytes 8-15 = 0x00
///   Bytes16Id(b)  → bytes 0-15 = b as-is
///
/// Use vcdb_id_encode / vcdb_id_decode for all ID conversions.
/// The old hi/lo pair and UUID-string paths have been removed.

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
/// Encode a VectorId to the 16-byte wire format.
/// JS receives a Uint8Array(16).
fn vid_encode(id : @types.VectorId) -> Bytes {
  id.to_wire_bytes()
}

///|
/// Decode a VectorId from the 16-byte wire format.
/// Returns None if data is not exactly 16 bytes.
fn vid_decode(data : Bytes) -> @types.VectorId? {
  @types.VectorId::from_wire_bytes(data)
}

// ── Instance management ──────────────────────────────────────

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

// ── ID encode / decode (SoT for JS ↔ VectorId conversion) ────

///|
/// Encode a VectorId to 16 bytes.
/// JS must call this to convert a VectorId returned by search/scroll
/// back to a wire-format Uint8Array for round-trip verification.
pub fn vcdb_id_encode(instance_id : Int, id_bytes : Bytes) -> Bytes {
  match (instances.get(instance_id), vid_decode(id_bytes)) {
    (Some(_), Some(id)) => vid_encode(id)
    _ => b""
  }
}

// ── Mutation operations ──────────────────────────────────────

///|
/// Add a vector. id_bytes must be exactly 16 bytes (wire format).
/// Returns 0 on success, -1 if instance not found or id invalid,
/// -2 if id already exists.
pub fn vcdb_add(
  instance_id : Int,
  id_bytes : Bytes,
  vector : Array[Double],
) -> Int {
  match (instances.get(instance_id), vid_decode(id_bytes)) {
    (Some(db), Some(id)) => {
      if db.has(id) {
        return -2
      }
      let attrs = @types.empty_attrs()
      run_async(async fn() noraise {
        let _ = db.add(id, vector, attrs, 0L) catch { _ => false }
      })
      0
    }
    _ => -1
  }
}

///|
/// Upsert a vector. id_bytes must be exactly 16 bytes (wire format).
/// Returns 0 on success, -1 if instance not found or id invalid.
pub fn vcdb_upsert(
  instance_id : Int,
  id_bytes : Bytes,
  vector : Array[Double],
) -> Int {
  match (instances.get(instance_id), vid_decode(id_bytes)) {
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
/// Remove a vector. id_bytes must be exactly 16 bytes (wire format).
/// Returns 1 if removed, 0 if not found, -1 on error.
pub fn vcdb_remove(instance_id : Int, id_bytes : Bytes) -> Int {
  match (instances.get(instance_id), vid_decode(id_bytes)) {
    (Some(db), Some(id)) => {
      let mut result = 0
      run_async(async fn() noraise {
        let removed = db.remove(id, 0L) catch { _ => false }
        result = if removed { 1 } else { 0 }
      })
      result
    }
    _ => -1
  }
}

// ── Read operations ──────────────────────────────────────────

///|
/// Get a vector by id. id_bytes must be exactly 16 bytes (wire format).
/// Returns (vector, 1) if found, ([], 0) if not found, ([], -1) on error.
pub fn vcdb_get(instance_id : Int, id_bytes : Bytes) -> (Array[Double], Int) {
  match (instances.get(instance_id), vid_decode(id_bytes)) {
    (Some(db), Some(id)) =>
      match db.get(id) {
        Some(record) => (record.vector, 1)
        None => ([], 0)
      }
    _ => ([], -1)
  }
}

///|
/// Check if a vector exists. id_bytes must be exactly 16 bytes (wire format).
/// Returns 1 if exists, 0 if not, -1 on error.
pub fn vcdb_has(instance_id : Int, id_bytes : Bytes) -> Int {
  match (instances.get(instance_id), vid_decode(id_bytes)) {
    (Some(db), Some(id)) => if db.has(id) { 1 } else { 0 }
    _ => -1
  }
}

///|
/// Search by vector similarity.
/// Returns Array of (id_bytes: Bytes, score: Double).
/// Each id_bytes is exactly 16 bytes in wire format.
pub fn vcdb_search(
  instance_id : Int,
  query : Array[Double],
  k : Int,
) -> Array[(Bytes, Double)] {
  match instances.get(instance_id) {
    Some(db) => {
      let results = db.search(query, k, None)
      results.map(fn(hit) { (vid_encode(hit.id), hit.score) })
    }
    None => []
  }
}

// ── Serialization ────────────────────────────────────────────

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

// ── Parse JSON attrs (used by persistent_exports) ────────────

///|
fn parse_json_to_attrs(json : String) -> @types.Attrs {
  if json.length() == 0 || json == "{}" {
    return @types.empty_attrs()
  }
  @codec.parse_attrs_json(json).unwrap_or(@types.empty_attrs())
}

// ── CRUSH placement ──────────────────────────────────────────

///|
/// Build a CrushMap with numbered targets for FFI use.
///
/// At the FFI boundary each shard IS a target, so we create
/// pg_count targets named "0", "1", …, "pg_count-1".
/// This gives crush_locate real targets to map PGs onto,
/// which is required for replicas > 1 to produce multiple
/// primaries and for rebalance plans to detect movement.
fn ffi_crush_map(pg_count : Int, replicas : Int) -> @placement.CrushMap {
  let targets : Array[@placement.CrushTarget] = []
  for i in 0..<pg_count {
    targets.push(@placement.CrushTarget::new(i.to_string()))
  }
  @placement.CrushMap::new(pg_count, replicas, targets)
}

///|
/// Compute placement group for a vector ID.
/// id_bytes must be exactly 16 bytes (wire format).
/// Returns placement group in [0, pg_count), or -1 on error.
pub fn crush_placement_group(id_bytes : Bytes, pg_count : Int) -> Int {
  match vid_decode(id_bytes) {
    Some(vid) => {
      let map = ffi_crush_map(pg_count, 1)
      let result = @placement.crush_locate(vid, map)
      result.pg
    }
    None => -1
  }
}

///|
/// Compute all shard indices (primary + replicas) for a vector ID.
/// id_bytes must be exactly 16 bytes (wire format).
/// Returns array of shard indices — one per replica.
/// Returns empty array on error.
pub fn crush_placement_groups(
  id_bytes : Bytes,
  pg_count : Int,
  replicas : Int,
) -> Array[Int] {
  match vid_decode(id_bytes) {
    Some(vid) => {
      let map = ffi_crush_map(pg_count, replicas)
      let result = @placement.crush_locate(vid, map)
      result.primaries.map(fn(k) { key_to_shard_id(k) })
    }
    None => []
  }
}

// ── Gateway import anchor ────────────────────────────────────

///|
fn _gateway_import_anchor() -> @gateway.CollectionConfig {
  @gateway.CollectionConfig::default("", 0)
}
