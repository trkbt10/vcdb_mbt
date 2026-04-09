///|
/// Partition detection, tracking, and recovery.
///
/// Handles network partitions between shards:
///   - Detect when a shard becomes partitioned (no response)
///   - Track partition duration per shard
///   - On recovery: merge divergent WALs using LWW (Last-Writer-Wins)
///   - Generate recovery plans from partition + replication state
///
/// Conflict resolution strategy: LWW per vector ID.
/// WAL v2 records carry nanosecond timestamps — the record with
/// the highest timestamp for each vector ID wins. Ties are broken
/// deterministically by vector ID (lower ID wins).

///|
/// Partition status for a shard.
pub(all) enum PartitionStatus {
  /// Shard is reachable.
  Connected
  /// Shard is unreachable since the given timestamp (nanoseconds).
  Partitioned(Int64)
} derive(Eq)

///|
pub impl Show for PartitionStatus with output(self, logger) {
  match self {
    Connected => logger.write_string("Connected")
    Partitioned(ts) => {
      logger.write_string("Partitioned(")
      Show::output(ts, logger)
      logger.write_string(")")
    }
  }
}

///|
/// Tracks partition state across all shards.
pub(all) struct PartitionState {
  statuses : Map[Int, PartitionStatus]
}

///|
/// Create a new partition state with all shards connected.
pub fn PartitionState::new(shard_count : Int) -> PartitionState {
  let statuses : Map[Int, PartitionStatus] = {}
  for i in 0..<shard_count {
    statuses[i] = Connected
  }
  { statuses, }
}

///|
/// Mark a shard as partitioned at the given timestamp.
/// No-op if already partitioned (preserves original partition timestamp).
pub fn PartitionState::detect_partition(
  self : PartitionState,
  shard_id : Int,
  ts : Int64,
) -> Unit {
  match self.statuses.get(shard_id) {
    Some(Connected) => self.statuses[shard_id] = Partitioned(ts)
    Some(Partitioned(_)) => () // Already partitioned, keep original ts
    None => self.statuses[shard_id] = Partitioned(ts)
  }
}

///|
/// Mark a shard as connected (partition resolved).
pub fn PartitionState::resolve_partition(
  self : PartitionState,
  shard_id : Int,
) -> Unit {
  self.statuses[shard_id] = Connected
}

///|
/// Get the partition status of a shard.
pub fn PartitionState::get_status(
  self : PartitionState,
  shard_id : Int,
) -> PartitionStatus {
  match self.statuses.get(shard_id) {
    Some(s) => s
    None => Connected
  }
}

///|
/// Check if a shard is currently partitioned.
pub fn PartitionState::is_partitioned(
  self : PartitionState,
  shard_id : Int,
) -> Bool {
  match self.statuses.get(shard_id) {
    Some(Partitioned(_)) => true
    _ => false
  }
}

///|
/// List all currently partitioned shards with their partition timestamps.
pub fn PartitionState::partitioned_shards(
  self : PartitionState,
) -> Array[(Int, Int64)] {
  let result : Array[(Int, Int64)] = []
  let keys = self.statuses.keys().collect()
  keys.sort()
  for shard_id in keys {
    match self.statuses.get(shard_id) {
      Some(Partitioned(ts)) => result.push((shard_id, ts))
      _ => ()
    }
  }
  result
}

///|
/// Record of a resolved conflict between local and remote WAL records.
pub(all) struct ConflictRecord {
  id : @types.VectorId
  local_ts : Int64
  remote_ts : Int64
  resolution : ConflictResolution
}

///|
/// How a conflict was resolved.
pub(all) enum ConflictResolution {
  /// Local record had higher timestamp; kept local.
  KeepLocal
  /// Remote record had higher timestamp; kept remote.
  KeepRemote
  /// Same timestamp; resolved deterministically by ID.
  TieBreakById
} derive(Eq)

///|
pub impl Show for ConflictResolution with output(self, logger) {
  match self {
    KeepLocal => logger.write_string("KeepLocal")
    KeepRemote => logger.write_string("KeepRemote")
    TieBreakById => logger.write_string("TieBreakById")
  }
}

///|
/// Resolve conflicts between local and remote WAL records using LWW.
///
/// For each vector ID present in both sets, the record with the highest
/// timestamp wins. If timestamps are equal, the record from the set
/// with the lower source indicator wins (local first for determinism).
///
/// Returns:
///   - Merged records (latest per ID, plus non-conflicting records)
///   - Conflict report (one entry per ID that appeared in both sets)
pub fn resolve_conflicts_lww(
  local_records : Array[@wal.WalRecord],
  remote_records : Array[@wal.WalRecord],
) -> (Array[@wal.WalRecord], Array[ConflictRecord]) {
  // Index records by ID, keeping only the latest per ID within each set
  let local_by_id : Map[Int64, @wal.WalRecord] = {}
  for record in local_records {
    let id_key = record.id.to_int64()
    match local_by_id.get(id_key) {
      Some(existing) =>
        if record.timestamp > existing.timestamp {
          local_by_id[id_key] = record
        }
      None => local_by_id[id_key] = record
    }
  }

  let remote_by_id : Map[Int64, @wal.WalRecord] = {}
  for record in remote_records {
    let id_key = record.id.to_int64()
    match remote_by_id.get(id_key) {
      Some(existing) =>
        if record.timestamp > existing.timestamp {
          remote_by_id[id_key] = record
        }
      None => remote_by_id[id_key] = record
    }
  }

  let merged : Array[@wal.WalRecord] = []
  let conflicts : Array[ConflictRecord] = []
  let seen : Map[Int64, Bool] = {}

  // Process all local records
  for id_key in local_by_id.keys() {
    match local_by_id.get(id_key) {
      Some(local_rec) => {
        seen[id_key] = true
        match remote_by_id.get(id_key) {
          Some(remote_rec) =>
            // Conflict: both sides have this ID
            if local_rec.timestamp > remote_rec.timestamp {
              merged.push(local_rec)
              conflicts.push({
                id: local_rec.id,
                local_ts: local_rec.timestamp,
                remote_ts: remote_rec.timestamp,
                resolution: KeepLocal,
              })
            } else if remote_rec.timestamp > local_rec.timestamp {
              merged.push(remote_rec)
              conflicts.push({
                id: local_rec.id,
                local_ts: local_rec.timestamp,
                remote_ts: remote_rec.timestamp,
                resolution: KeepRemote,
              })
            } else {
              // Same timestamp — deterministic tie-break: keep local
              merged.push(local_rec)
              conflicts.push({
                id: local_rec.id,
                local_ts: local_rec.timestamp,
                remote_ts: remote_rec.timestamp,
                resolution: TieBreakById,
              })
            }
          None => merged.push(local_rec) // Only local has this ID
        }
      }
      None => ()
    }
  }

  // Add remote-only records
  for id_key in remote_by_id.keys() {
    if !seen.contains(id_key) {
      match remote_by_id.get(id_key) {
        Some(rec) => merged.push(rec)
        None => ()
      }
    }
  }

  (merged, conflicts)
}

///|
/// Merge two divergent WALs that split at a known divergence point.
///
/// Extracts records after diverge_ts from both WALs, resolves conflicts
/// via LWW, and produces a single merged WAL.
///
/// Returns:
///   - Merged WAL bytes (ready to apply to a store)
///   - Conflict report
pub fn merge_divergent_wals(
  local_wal : Bytes,
  remote_wal : Bytes,
  diverge_ts : Int64,
) -> (Bytes, Array[ConflictRecord]) {
  // Extract post-divergence records from both sides
  let local_all = @wal.decode_wal_records(local_wal)
  let remote_all = @wal.decode_wal_records(remote_wal)

  let local_diverged : Array[@wal.WalRecord] = []
  for record in local_all {
    if record.timestamp > diverge_ts {
      local_diverged.push(record)
    }
  }

  let remote_diverged : Array[@wal.WalRecord] = []
  for record in remote_all {
    if record.timestamp > diverge_ts {
      remote_diverged.push(record)
    }
  }

  // Resolve conflicts
  let (merged_records, conflicts) = resolve_conflicts_lww(
    local_diverged, remote_diverged,
  )

  // Build shared base (records ≤ diverge_ts from local — should be same on both)
  let base_records : Array[@wal.WalRecord] = []
  for record in local_all {
    if record.timestamp <= diverge_ts || record.timestamp == 0L {
      base_records.push(record)
    }
  }

  // Combine base + merged divergent
  let all_records : Array[@wal.WalRecord] = []
  for record in base_records {
    all_records.push(record)
  }
  for record in merged_records {
    all_records.push(record)
  }

  let merged_wal = if all_records.is_empty() {
    @wal.encode_wal_header()
  } else {
    @wal.encode_wal_segment(all_records)
  }

  (merged_wal, conflicts)
}

///|
/// Generate a recovery plan from partition and replication state.
///
/// For each currently partitioned shard that has just been resolved,
/// returns (shard_id, since_ts) indicating the shard needs WAL records
/// from since_ts onwards to catch up.
///
/// The since_ts is taken from the replication state's last known
/// position for that shard.
pub fn recovery_plan(
  partition_state : PartitionState,
  replication_state : ReplicationState,
  recently_resolved : Array[Int],
) -> Array[(Int, Int64)] {
  let plan : Array[(Int, Int64)] = []
  for shard_id in recently_resolved {
    match partition_state.get_status(shard_id) {
      Connected => {
        // Shard was resolved — find its last known position
        // Use the shard ID as a replica key convention: "shard-{id}"
        let replica_key = "shard-" + shard_id.to_string()
        let last_ts = replication_state.replica_position(replica_key)
        plan.push((shard_id, last_ts))
      }
      Partitioned(_) => () // Still partitioned, skip
    }
  }
  plan
}
