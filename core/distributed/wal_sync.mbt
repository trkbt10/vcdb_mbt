///|
/// WAL shipping and replica synchronization.
///
/// All functions are pure computation (no I/O). Platform adapters
/// handle the actual network transport of WAL shipments.
///
/// Pull model: replicas request WAL segments from the primary starting
/// at a known timestamp. The primary extracts records since that timestamp
/// and packages them as a WalShipment.
///
/// Reuses existing WAL infrastructure (SoT in format.mbt):
///   - decode_wal_records for parsing
///   - encode_wal_segment for packaging
///   - merge_wal for applying shipments
///   - max_wal_timestamp for tracking progress

///|
/// Tracks a replica's synchronization position.
pub(all) struct ReplicaPosition {
  replica_key : String
  /// Timestamp of the last record applied to this replica (nanoseconds).
  last_applied_ts : Int64
}

///|
/// Tracks replication state across all replicas for a shard.
pub(all) struct ReplicationState {
  /// Per-replica synchronization positions.
  positions : Map[String, ReplicaPosition]
  /// Maximum timestamp in the primary's WAL.
  mut primary_max_ts : Int64
}

///|
/// A package of WAL records for shipping to a replica.
pub(all) struct WalShipment {
  /// Which shard this shipment is from.
  source_shard : Int
  /// Records in this shipment have timestamps > from_ts.
  from_ts : Int64
  /// Maximum timestamp in this shipment.
  to_ts : Int64
  /// Encoded WAL segment bytes (header + records + footer).
  data : Bytes
  /// Number of records in this shipment.
  record_count : Int
}

///|
/// Replication lag measurement for a single replica.
pub(all) struct ReplicationLag {
  replica_key : String
  /// Time difference between primary max and replica position (nanoseconds).
  lag_ns : Int64
  /// Estimated record count difference.
  lag_records : Int
}

///|
/// Create a new replication state with all replicas at position 0.
pub fn ReplicationState::new(
  replica_keys : Array[String],
) -> ReplicationState {
  let positions : Map[String, ReplicaPosition] = {}
  for key in replica_keys {
    positions[key] = { replica_key: key, last_applied_ts: 0L }
  }
  { positions, primary_max_ts: 0L }
}

///|
/// Update the primary's maximum timestamp from its WAL.
pub fn ReplicationState::update_primary_ts(
  self : ReplicationState,
  wal_data : Bytes,
) -> Unit {
  self.primary_max_ts = @wal.max_wal_timestamp(wal_data)
}

///|
/// Extract WAL records since a given timestamp for shipping.
///
/// Returns records with timestamp > since_ts (exclusive).
/// This is the inverse of filter_wal_by_timestamp (which returns ≤ cutoff).
///
/// Packages records into a complete WAL segment (header + records + footer)
/// ready for transport.
pub fn extract_wal_since(
  wal_data : Bytes,
  since_ts : Int64,
  source_shard : Int,
) -> WalShipment {
  let all_records = @wal.decode_wal_records(wal_data)
  let new_records : Array[@wal.WalRecord] = []
  let mut max_ts = since_ts

  for record in all_records {
    // Include records strictly after since_ts.
    // Also include v1 records (timestamp=0) if since_ts is 0
    // (initial sync includes everything).
    if record.timestamp > since_ts || (record.timestamp == 0L && since_ts == 0L) {
      new_records.push(record)
      if record.timestamp > max_ts {
        max_ts = record.timestamp
      }
    }
  }

  let data = if new_records.is_empty() {
    @wal.encode_wal_header()
  } else {
    @wal.encode_wal_segment(new_records)
  }

  {
    source_shard,
    from_ts: since_ts,
    to_ts: max_ts,
    data,
    record_count: new_records.length(),
  }
}

///|
/// Apply a WAL shipment to a replica's existing WAL.
///
/// Delegates to merge_wal (SoT in format.mbt) for the actual merge.
/// Returns the merged WAL bytes.
pub fn apply_wal_shipment(
  existing_wal : Bytes,
  shipment : WalShipment,
) -> Bytes {
  @wal.merge_wal(existing_wal, shipment.data)
}

///|
/// Update a replica's position after successfully applying a shipment.
pub fn ReplicationState::update_replica_position(
  self : ReplicationState,
  replica_key : String,
  applied_ts : Int64,
) -> Unit {
  match self.positions.get(replica_key) {
    Some(pos) =>
      self.positions[replica_key] = { ..pos, last_applied_ts: applied_ts }
    None =>
      self.positions[replica_key] = {
        replica_key,
        last_applied_ts: applied_ts,
      }
  }
}

///|
/// Compute replication lag for all replicas.
///
/// Lag is measured as the difference between the primary's max timestamp
/// and each replica's last applied timestamp.
pub fn ReplicationState::compute_replication_lag(
  self : ReplicationState,
) -> Array[ReplicationLag] {
  let result : Array[ReplicationLag] = []
  let keys = self.positions.keys().collect()
  keys.sort()
  for key in keys {
    match self.positions.get(key) {
      Some(pos) => {
        let lag_ns = self.primary_max_ts - pos.last_applied_ts
        // Record count estimate: we can't know exactly without scanning WAL,
        // so we report -1 to indicate "unknown". The caller can compute
        // this by decoding the WAL if needed.
        result.push({
          replica_key: key,
          lag_ns: if lag_ns > 0L { lag_ns } else { 0L },
          lag_records: -1, // Unknown without WAL access
        })
      }
      None => ()
    }
  }
  result
}

///|
/// Check if a replica is caught up within a tolerance window.
pub fn ReplicationState::is_replica_caught_up(
  self : ReplicationState,
  replica_key : String,
  tolerance_ns : Int64,
) -> Bool {
  match self.positions.get(replica_key) {
    Some(pos) => {
      let lag = self.primary_max_ts - pos.last_applied_ts
      lag <= tolerance_ns
    }
    None => false
  }
}

///|
/// Get the last applied timestamp for a replica.
pub fn ReplicationState::replica_position(
  self : ReplicationState,
  replica_key : String,
) -> Int64 {
  match self.positions.get(replica_key) {
    Some(pos) => pos.last_applied_ts
    None => 0L
  }
}
