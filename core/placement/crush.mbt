///|
/// CRUSH (Controlled Replication Under Scalable Hashing) Algorithm
/// Provides deterministic distributed placement for vector data.

///|
/// Storage target (device/bucket)
pub struct CrushTarget {
  key : String // Logical storage key
  weight : Double // Device weight (default 1.0)
  zone : String? // Failure domain (optional)
} derive(Show)

///|
/// Create a simple target with default weight
pub fn CrushTarget::new(key : String) -> CrushTarget {
  { key, weight: 1.0, zone: None }
}

///|
/// Create a target with weight
pub fn CrushTarget::with_weight(key : String, weight : Double) -> CrushTarget {
  { key, weight, zone: None }
}

///|
/// Create a target with zone
pub fn CrushTarget::with_zone(
  key : String,
  weight : Double,
  zone : String,
) -> CrushTarget {
  { key, weight, zone: Some(zone) }
}

///|
/// CRUSH map configuration
pub struct CrushMap {
  pgs : Int // Number of placement groups
  replicas : Int // Number of replicas per placement group
  targets : Array[CrushTarget] // Available storage targets
} derive(Show)

///|
/// Create a simple CRUSH map
pub fn CrushMap::new(
  pgs : Int,
  replicas : Int,
  targets : Array[CrushTarget],
) -> CrushMap {
  { pgs, replicas, targets }
}

///|
/// Placement result
pub struct LocateResult {
  pg : Int // Placement group number
  primaries : Array[String] // Ordered list of target keys
} derive(Show)

///|
/// 32-bit mixing hash function for deterministic distribution
/// Uses multiple rounds of XOR and multiplication for uniform output
fn hash32(x : UInt) -> UInt {
  let mut a = x ^ (x >> 16)
  a = a * 0x7FEB352DU
  a = a ^ (a >> 15)
  a = a * 0x846CA68BU
  a = a ^ (a >> 16)
  a
}

///|
/// Hash a 64-bit value to 32 bits without truncation
/// XOR-folds the upper and lower halves after mixing each
fn hash64_to_32(x : UInt64) -> UInt {
  let lo = (x & 0xFFFFFFFFUL).to_uint()
  let hi = ((x >> 32) & 0xFFFFFFFFUL).to_uint()
  // Mix both halves and XOR them together
  hash32(lo) ^ hash32(hi)
}

///|
/// Find unused index using linear probing
fn find_unused_index(start : Int, used : Map[Int, Bool], total : Int) -> Int {
  let mut idx = start
  while used.contains(idx) {
    idx = (idx + 1) % total
  }
  idx
}

///|
/// Choose primary targets for a placement group
/// Uses FNV-like constant for stable seed generation
fn choose_primaries(pg : Int, replicas : Int, total : Int) -> Array[Int] {
  if total == 0 {
    return []
  }
  let used : Map[Int, Bool] = {}
  let limit = if replicas < total { replicas } else { total }
  let result : Array[Int] = []
  // FNV-like constant for stable base seed
  let base = (pg.reinterpret_as_uint() * 2654435761U).reinterpret_as_int()
  for r in 0..<limit {
    let seed = hash32((base + r).reinterpret_as_uint())
    let pick = (seed % total.reinterpret_as_uint()).reinterpret_as_int()
    let idx = find_unused_index(pick, used, total)
    used.set(idx, true)
    result.push(idx)
  }
  result
}

///|
/// Locate placement for a vector ID
/// Returns the placement group and primary target keys
pub fn crush_locate(id : @types.VectorId, map : CrushMap) -> LocateResult {
  // Use hash64_to_32 to preserve full 64-bit ID without truncation
  let id_hash = hash64_to_32(id.to_int64().reinterpret_as_uint64())
  let pg = if map.pgs > 0 {
    (id_hash % map.pgs.reinterpret_as_uint()).reinterpret_as_int()
  } else {
    0
  }
  if map.targets.is_empty() {
    return { pg, primaries: [] }
  }
  let indices = choose_primaries(pg, map.replicas, map.targets.length())
  let primaries : Array[String] = []
  for idx in indices {
    primaries.push(map.targets[idx].key)
  }
  { pg, primaries }
}

///|
/// Locate placement using just ID and CRUSH map
/// Convenience function that returns the primary target key
pub fn crush_primary(id : @types.VectorId, map : CrushMap) -> String? {
  let result = crush_locate(id, map)
  first_string_opt(result.primaries)
}

///|
/// Segment manifest entry
pub(all) struct SegmentEntry {
  name : String // Segment name (e.g., "db.pg0.part0")
  target_key : String // Storage target key
} derive(Show)

///|
/// Placement manifest
pub(all) struct PlacementManifest {
  base : String // Base name
  segments : Array[SegmentEntry] // Segment entries
  crush : CrushMap // CRUSH configuration used
  epoch : Int // Epoch number for CAS
  commit_ts : Int64 // Commit timestamp
} derive(Show)

///|
/// Move plan for rebalancing
pub(all) struct MovePlan {
  name : String // Segment name
  from : String // Source target key
  to : String // Destination target key
} derive(Show)

///|
/// Extract placement group number from segment name
/// Format: {base}.pg{N}.part{M}
/// Finds the LAST ".pg" followed by digits to handle bases containing ".pg"
fn parse_pg_from_name(name : String) -> Int {
  let chars : Array[Char] = []
  for c in name {
    chars.push(c)
  }
  // Find all ".pg" occurrences and use the last one with digits
  let mut last_pg_value : Int? = None
  let mut i = 0
  while i < chars.length() - 2 {
    if chars[i] == '.' && chars[i + 1] == 'p' && chars[i + 2] == 'g' {
      // Found ".pg", try to parse digits after it
      let mut j = i + 3
      let pg_str : Array[Char] = []
      while j < chars.length() && chars[j] >= '0' && chars[j] <= '9' {
        pg_str.push(chars[j])
        j = j + 1
      }
      if !pg_str.is_empty() {
        // Parse number and save as potential last valid PG
        let mut val = 0
        for c in pg_str {
          val = val * 10 + (c.to_uint().reinterpret_as_int() - 48)
        }
        last_pg_value = Some(val)
      }
      i = j
    } else {
      i = i + 1
    }
  }
  match last_pg_value {
    Some(v) => v
    None => 0
  }
}

///|
/// Compute primary target for a placement group under a CRUSH map
/// Uses choose_primaries for consistency with crush_locate
/// Returns None if no targets available
fn target_for_pg(pg : Int, map : CrushMap) -> String? {
  if map.targets.is_empty() {
    return None
  }
  // Use choose_primaries for consistent placement with crush_locate
  let primaries = choose_primaries(pg, 1, map.targets.length())
  if primaries.is_empty() {
    return Some(map.targets[0].key)
  }
  Some(map.targets[primaries[0]].key)
}

///|
/// Plan rebalance operations when CRUSH map changes
/// Returns empty array if next map has no targets
pub fn plan_rebalance(
  manifest : PlacementManifest,
  next : CrushMap,
) -> Array[MovePlan] {
  let plans : Array[MovePlan] = []
  // No moves possible if no targets in next map
  if next.targets.is_empty() {
    return plans
  }
  for segment in manifest.segments {
    let pg = parse_pg_from_name(segment.name)
    match target_for_pg(pg, next) {
      None => continue // Skip if no target available
      Some(desired) =>
        if desired != segment.target_key {
          plans.push({
            name: segment.name,
            from: segment.target_key,
            to: desired,
          })
        }
    }
  }
  plans
}

///|
/// Execute rebalance plan using any Storage implementation
pub fn[S : @storage.Storage] apply_rebalance(
  plan : Array[MovePlan],
  storages : Map[String, S],
) -> Unit raise @storage.IOError {
  for mv in plan {
    let from_storage = require_storage_with_prefix(
      storages,
      mv.from,
      "Source storage not found: ",
    )
    let to_storage = require_storage_with_prefix(
      storages,
      mv.to,
      "Destination storage not found: ",
    )
    // Read from source
    let data = S::read(from_storage, mv.name + ".data", @storage.Data)
    // Write to destination
    S::atomic_write(to_storage, mv.name + ".data", data, @storage.Data)
    // Delete from source (optional cleanup)
    S::del(from_storage, mv.name + ".data", @storage.Data) catch {
      _ => () // Ignore delete errors
    }
  }
}

///|
/// Backward compatibility alias
pub fn apply_rebalance_memory(
  plan : Array[MovePlan],
  storages : Map[String, @storage.MemoryStorage],
) -> Unit raise @storage.IOError {
  apply_rebalance(plan, storages)
}

///|
/// Update manifest after rebalance
pub fn update_manifest_after_rebalance(
  manifest : PlacementManifest,
  plan : Array[MovePlan],
  new_crush : CrushMap,
  new_epoch : Int,
  new_ts : Int64,
) -> PlacementManifest {
  // Create move lookup
  let move_map : Map[String, String] = {}
  for mv in plan {
    move_map.set(mv.name, mv.to)
  }
  // Update segments
  let new_segments : Array[SegmentEntry] = []
  for segment in manifest.segments {
    let new_target = match move_map.get(segment.name) {
      None => segment.target_key
      Some(t) => t
    }
    new_segments.push({ name: segment.name, target_key: new_target })
  }
  {
    base: manifest.base,
    segments: new_segments,
    crush: new_crush,
    epoch: new_epoch,
    commit_ts: new_ts,
  }
}
