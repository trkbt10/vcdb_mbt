///|
/// Partition detection, tracking, and recovery.
///
/// Handles network partitions between targets:
///   - Detect when a target becomes partitioned (no response)
///   - Track partition duration per target
///   - On recovery: merge divergent WALs using LWW (Last-Writer-Wins)
///   - Generate recovery plans from partition + replication state
///
/// Conflict resolution strategy: LWW per vector ID.
/// WAL v2 records carry nanosecond timestamps — the record with
/// the highest timestamp for each vector ID wins. Ties are broken
/// deterministically by vector ID (lower ID wins).

///|
/// Partition status for a target.
pub(all) enum PartitionStatus {
  /// Target is reachable.
  Connected
  /// Target is unreachable since the given timestamp (nanoseconds).
  Partitioned(Int64)
} derive(Eq, Debug)

///|
pub impl Show for PartitionStatus with fn output(self, logger) {
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
/// Tracks partition state across all targets.
pub(all) struct PartitionState {
  statuses : Map[@placement.TargetKey, PartitionStatus]
}

///|
/// Create a new partition state with all targets connected.
pub fn PartitionState::new(
  target_keys : Array[@placement.TargetKey],
) -> PartitionState {
  let statuses : Map[@placement.TargetKey, PartitionStatus] = {}
  for key in target_keys {
    statuses[key] = Connected
  }
  { statuses, }
}

///|
/// Mark a target as partitioned at the given timestamp.
/// No-op if already partitioned (preserves original partition timestamp).
pub fn PartitionState::detect_partition(
  self : PartitionState,
  target_key : @placement.TargetKey,
  ts : Int64,
) -> Unit {
  match self.statuses.get(target_key) {
    Some(Connected) => self.statuses[target_key] = Partitioned(ts)
    Some(Partitioned(_)) => () // Already partitioned, keep original ts
    None => self.statuses[target_key] = Partitioned(ts)
  }
}

///|
/// Mark a target as connected (partition resolved).
pub fn PartitionState::resolve_partition(
  self : PartitionState,
  target_key : @placement.TargetKey,
) -> Unit {
  self.statuses[target_key] = Connected
}

///|
/// Get the partition status of a target.
pub fn PartitionState::get_status(
  self : PartitionState,
  target_key : @placement.TargetKey,
) -> PartitionStatus {
  match self.statuses.get(target_key) {
    Some(s) => s
    None => Connected
  }
}

///|
/// Check if a target is currently partitioned.
pub fn PartitionState::is_partitioned(
  self : PartitionState,
  target_key : @placement.TargetKey,
) -> Bool {
  match self.statuses.get(target_key) {
    Some(Partitioned(_)) => true
    _ => false
  }
}

///|
/// List all currently partitioned targets with their partition timestamps.
pub fn PartitionState::partitioned_targets(
  self : PartitionState,
) -> Array[(@placement.TargetKey, Int64)] {
  let result : Array[(@placement.TargetKey, Int64)] = []
  let keys = self.statuses.keys().collect()
  keys.sort()
  for key in keys {
    match self.statuses.get(key) {
      Some(Partitioned(ts)) => result.push((key, ts))
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
} derive(Eq, Debug)

///|
pub impl Show for ConflictResolution with fn output(self, logger) {
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
  let local_by_id : Map[@types.VectorId, @wal.WalRecord] = {}
  for record in local_records {
    let id_key = record.id
    match local_by_id.get(id_key) {
      Some(existing) =>
        if record.timestamp > existing.timestamp {
          local_by_id[id_key] = record
        }
      None => local_by_id[id_key] = record
    }
  }

  let remote_by_id : Map[@types.VectorId, @wal.WalRecord] = {}
  for record in remote_records {
    let id_key = record.id
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
  let seen : Map[@types.VectorId, Bool] = {}

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
/// For each recently resolved target, returns (target_key, since_ts)
/// indicating the target needs WAL records from since_ts onwards to catch up.
pub fn recovery_plan(
  partition_state : PartitionState,
  replication_state : ReplicationState,
  recently_resolved : Array[@placement.TargetKey],
) -> Array[(@placement.TargetKey, Int64)] {
  let plan : Array[(@placement.TargetKey, Int64)] = []
  for target_key in recently_resolved {
    match partition_state.get_status(target_key) {
      Connected => {
        let last_ts = replication_state.replica_position(target_key.to_string())
        plan.push((target_key, last_ts))
      }
      Partitioned(_) => () // Still partitioned, skip
    }
  }
  plan
}
