///|
/// CRUSH (Controlled Replication Under Scalable Hashing) Algorithm
/// Provides deterministic distributed placement for vector data.

///|
/// Storage target (device/bucket)
pub struct CrushTarget {
  key : String // Logical storage key
  weight : Double // Device weight (default 1.0)
  zone : String? // Failure domain (optional)
}

///|
pub impl Show for CrushTarget with output(self, logger) {
  logger.write_string("{ key: ")
  Show::output(self.key, logger)
  logger.write_string(", weight: ")
  Show::output(self.weight, logger)
  logger.write_string(", zone: ")
  Show::output(self.zone, logger)
  logger.write_string(" }")
}

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
}

///|
pub impl Show for CrushMap with output(self, logger) {
  logger.write_string("{ pgs: ")
  Show::output(self.pgs, logger)
  logger.write_string(", replicas: ")
  Show::output(self.replicas, logger)
  logger.write_string(", targets: ")
  Show::output(self.targets, logger)
  logger.write_string(" }")
}

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
}

///|
pub impl Show for LocateResult with output(self, logger) {
  logger.write_string("{ pg: ")
  Show::output(self.pg, logger)
  logger.write_string(", primaries: ")
  Show::output(self.primaries, logger)
  logger.write_string(" }")
}

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
/// Hash all 16 bytes of a Bytes16 into 32 bits.
/// Uses the same hash32 mixing function for consistency with hash64_to_32.
fn hash_bytes16_to_32(b : @types.Bytes16) -> UInt {
  // Mix bytes in four 32-bit words (big-endian grouping), then combine
  let w0 = (b.b0.to_uint() << 24) |
    (b.b1.to_uint() << 16) |
    (b.b2.to_uint() << 8) |
    b.b3.to_uint()
  let w1 = (b.b4.to_uint() << 24) |
    (b.b5.to_uint() << 16) |
    (b.b6.to_uint() << 8) |
    b.b7.to_uint()
  let w2 = (b.b8.to_uint() << 24) |
    (b.b9.to_uint() << 16) |
    (b.b10.to_uint() << 8) |
    b.b11.to_uint()
  let w3 = (b.b12.to_uint() << 24) |
    (b.b13.to_uint() << 16) |
    (b.b14.to_uint() << 8) |
    b.b15.to_uint()
  hash32(w0) ^ hash32(w1) ^ hash32(w2) ^ hash32(w3)
}

///|
/// Locate placement for a vector ID
/// Returns the placement group and primary target keys
pub fn crush_locate(id : @types.VectorId, map : CrushMap) -> LocateResult {
  let id_hash = match id {
    @types.Int64Id(v) => hash64_to_32(v.reinterpret_as_uint64())
    @types.Bytes16Id(b) => hash_bytes16_to_32(b)
  }
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
}

///|
pub impl Show for SegmentEntry with output(self, logger) {
  logger.write_string("{ name: ")
  Show::output(self.name, logger)
  logger.write_string(", target_key: ")
  Show::output(self.target_key, logger)
  logger.write_string(" }")
}

///|
/// Placement manifest
pub(all) struct PlacementManifest {
  base : String // Base name
  segments : Array[SegmentEntry] // Segment entries
  crush : CrushMap // CRUSH configuration used
  epoch : Int // Epoch number for CAS
  commit_ts : Int64 // Commit timestamp
}

///|
pub impl Show for PlacementManifest with output(self, logger) {
  logger.write_string("{ base: ")
  Show::output(self.base, logger)
  logger.write_string(", segments: ")
  Show::output(self.segments, logger)
  logger.write_string(", crush: ")
  Show::output(self.crush, logger)
  logger.write_string(", epoch: ")
  Show::output(self.epoch, logger)
  logger.write_string(", commit_ts: ")
  Show::output(self.commit_ts, logger)
  logger.write_string(" }")
}

///|
/// Move plan for rebalancing
pub(all) struct MovePlan {
  name : String // Segment name
  from : String // Source target key
  to : String // Destination target key
}

///|
pub impl Show for MovePlan with output(self, logger) {
  logger.write_string("{ name: ")
  Show::output(self.name, logger)
  logger.write_string(", from: ")
  Show::output(self.from, logger)
  logger.write_string(", to: ")
  Show::output(self.to, logger)
  logger.write_string(" }")
}

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
