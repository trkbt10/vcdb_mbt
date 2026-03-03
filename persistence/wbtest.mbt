// Whitebox tests for persistence module

///|
/// Test: CRC32 checksum
test "checksum/crc32" {
  let data = Bytes::from_array([b'h', b'e', b'l', b'l', b'o'][:])
  let crc = @core.crc32(data)
  // Known CRC32 for "hello"
  inspect(crc == 0x3610A686U, content="true")
}

///|
/// Test: WAL record encoding/decoding roundtrip
test "wal/record_roundtrip" {
  let attrs = @core.empty_attrs()
  attrs.set("key", @core.String("value"))
  let record = WalRecord::upsert(
    @core.VectorId::from_int(42),
    [1.0, 2.0, 3.0],
    attrs,
  )
  let encoded = encode_wal_record(record)
  let reader = @core.BinaryReader::new(encoded)
  let decoded = decode_wal_record(reader)
  match decoded {
    Some(r) => {
      inspect(r.id.to_int64(), content="42")
      inspect(r.record_type == WalRecordType::Upsert, content="true")
      match r.vector {
        Some(v) => inspect(v.length(), content="3")
        None => inspect(false, content="true")
      }
    }
    None => inspect(false, content="true")
  }
}

///|
/// Test: WAL segment encoding with header/footer
test "wal/segment_encoding" {
  let records = [
    WalRecord::upsert(@core.VectorId::from_int(1), [1.0], @core.empty_attrs()),
    WalRecord::remove(@core.VectorId::from_int(2)),
  ]
  let segment = encode_wal_segment(records)
  // Should have header (8) + records + footer (8)
  inspect(segment.length() > 16, content="true")
  // Verify checksum
  inspect(verify_wal_checksum(segment), content="true")
}

///|
/// Test: WAL decode multiple records
test "wal/decode_records" {
  let records = [
    WalRecord::upsert(
      @core.VectorId::from_int(1),
      [1.0, 2.0],
      @core.empty_attrs(),
    ),
    WalRecord::set_attrs(@core.VectorId::from_int(2), @core.empty_attrs()),
    WalRecord::remove(@core.VectorId::from_int(3)),
  ]
  let segment = encode_wal_segment(records)
  let decoded = decode_wal_records(segment)
  inspect(decoded.length(), content="3")
}

///|
/// Test: CRUSH deterministic placement
test "crush/deterministic" {
  let targets = [
    CrushTarget::new("node1"),
    CrushTarget::new("node2"),
    CrushTarget::new("node3"),
  ]
  let map = CrushMap::new(16, 2, targets)
  let id = @core.VectorId::from_int(12345)
  // Same ID should always map to same placement
  let result1 = crush_locate(id, map)
  let result2 = crush_locate(id, map)
  inspect(result1.pg == result2.pg, content="true")
  inspect(result1.primaries[0] == result2.primaries[0], content="true")
}

///|
/// Test: CRUSH primary selection
test "crush/primary" {
  let targets = [
    CrushTarget::new("a"),
    CrushTarget::new("b"),
    CrushTarget::new("c"),
  ]
  let map = CrushMap::new(8, 1, targets)
  let primary = crush_primary(@core.VectorId::from_int(100), map)
  match primary {
    Some(key) => inspect(key.length() > 0, content="true")
    None => inspect(false, content="true")
  }
}

///|
/// Test: CRUSH empty targets
test "crush/empty_targets" {
  let map = CrushMap::new(8, 2, [])
  let result = crush_locate(@core.VectorId::from_int(1), map)
  inspect(result.primaries.is_empty(), content="true")
}

///|
/// Test: MemoryStorage read/write
test "storage/memory_readwrite" {
  let storage = MemoryStorage::new()
  let data = Bytes::from_array([b'h', b'e', b'l', b'l', b'o'][:])
  storage.write("test.txt", data) catch {
    _ => ()
  }
  let result = storage.read("test.txt") catch { _ => Bytes::new(0) }
  inspect(result.length(), content="5")
}

///|
/// Test: MemoryStorage atomic write
test "storage/memory_atomic" {
  let storage = MemoryStorage::new()
  let data = Bytes::from_array([b't', b'e', b's', b't'][:])
  storage.atomic_write("atomic.dat", data) catch {
    _ => ()
  }
  inspect(storage.exists("atomic.dat"), content="true")
}

///|
/// Test: MemoryStorage append
test "storage/memory_append" {
  let storage = MemoryStorage::new()
  let data1 = Bytes::from_array([b'a', b'b'][:])
  let data2 = Bytes::from_array([b'c', b'd'][:])
  storage.write("append.txt", data1) catch {
    _ => ()
  }
  storage.append("append.txt", data2) catch {
    _ => ()
  }
  let result = storage.read("append.txt") catch { _ => Bytes::new(0) }
  inspect(result.length(), content="4")
}

///|
/// Test: MemoryStorage delete
test "storage/memory_delete" {
  let storage = MemoryStorage::new()
  let data = Bytes::from_array([b'x'][:])
  storage.write("del.txt", data) catch {
    _ => ()
  }
  inspect(storage.exists("del.txt"), content="true")
  storage.del("del.txt") catch {
    _ => ()
  }
  inspect(storage.exists("del.txt"), content="false")
}

///|
/// Test: MemoryStorage list
test "storage/memory_list" {
  let storage = MemoryStorage::new()
  storage.write("a.txt", Bytes::new(0)) catch {
    _ => ()
  }
  storage.write("b.txt", Bytes::new(0)) catch {
    _ => ()
  }
  let files = storage.list()
  inspect(files.length(), content="2")
}

///|
/// Test: WAL replay into CoreStore
test "wal/replay" {
  let storage = MemoryStorage::new()
  let wal = WalRuntime::new(storage, "test.wal")
  // Create WAL records
  let records = [
    WalRecord::upsert(
      @core.VectorId::from_int(1),
      [1.0, 0.0, 0.0],
      @core.empty_attrs(),
    ),
    WalRecord::upsert(
      @core.VectorId::from_int(2),
      [0.0, 1.0, 0.0],
      @core.empty_attrs(),
    ),
  ]
  wal.append(records) catch {
    _ => ()
  }
  // Replay into store
  let store = @core.CoreStore::new(3, @core.Dot)
  let count = wal.replay_into(store) catch { _ => 0 }
  inspect(count, content="2")
  inspect(store.size(), content="2")
  inspect(store.has(@core.VectorId::from_int(1)), content="true")
  inspect(store.has(@core.VectorId::from_int(2)), content="true")
}

///|
/// Test: WAL replay with remove record
test "wal/replay_remove" {
  let storage = MemoryStorage::new()
  let wal = WalRuntime::new(storage, "test_remove.wal")
  let records = [
    WalRecord::upsert(
      @core.VectorId::from_int(1),
      [1.0, 0.0],
      @core.empty_attrs(),
    ),
    WalRecord::upsert(
      @core.VectorId::from_int(2),
      [0.0, 1.0],
      @core.empty_attrs(),
    ),
    WalRecord::remove(@core.VectorId::from_int(1)),
  ]
  wal.append(records) catch {
    _ => ()
  }
  let store = @core.CoreStore::new(2, @core.Dot)
  let count = wal.replay_into(store) catch { _ => 0 }
  inspect(count, content="3")
  // id=1 should be removed
  inspect(store.has(@core.VectorId::from_int(1)), content="false")
  inspect(store.has(@core.VectorId::from_int(2)), content="true")
}

///|
/// Test: CRUSH deterministic hash distribution
test "crush/distribution" {
  let targets = [
    CrushTarget::new("node1"),
    CrushTarget::new("node2"),
    CrushTarget::new("node3"),
    CrushTarget::new("node4"),
  ]
  let map = CrushMap::new(16, 2, targets)
  // Check that different IDs are distributed across targets
  let mut node1_count = 0
  let mut node2_count = 0
  for i in 1..<=100 {
    let result = crush_locate(@core.VectorId::from_int(i), map)
    if result.primaries.length() > 0 {
      if result.primaries[0] == "node1" {
        node1_count = node1_count + 1
      } else if result.primaries[0] == "node2" {
        node2_count = node2_count + 1
      }
    }
  }
  // Distribution should be somewhat even (not all on one node)
  inspect(node1_count > 0, content="true")
  inspect(node2_count > 0, content="true")
}

///|
/// Test: E2E CRUD operations with WAL replay
test "wal/e2e_crud_replay" {
  let storage = MemoryStorage::new()
  let wal = WalRuntime::new(storage, "e2e.wal")
  // Simulate CRUD operations
  let attrs1 = @core.empty_attrs()
  attrs1.set("tag", @core.String("A"))
  let attrs2 = @core.empty_attrs()
  attrs2.set("tag", @core.String("B"))
  let records = [
    WalRecord::upsert(@core.VectorId::from_int(1), [1.0, 0.0, 0.0], attrs1),
    WalRecord::upsert(@core.VectorId::from_int(2), [0.0, 1.0, 0.0], attrs2),
    WalRecord::upsert(
      @core.VectorId::from_int(3),
      [0.0, 0.0, 1.0],
      @core.empty_attrs(),
    ),
    WalRecord::set_attrs(
      @core.VectorId::from_int(3),
      {
        let a = @core.empty_attrs()
        a.set("tag", @core.String("C"))
        a
      },
    ),
    WalRecord::remove(@core.VectorId::from_int(2)),
  ]
  wal.append(records) catch {
    _ => ()
  }
  // Replay into a new store
  let store = @core.CoreStore::new(3, @core.Dot)
  let count = wal.replay_into(store) catch { _ => 0 }
  inspect(count, content="5")
  // Verify state after replay
  inspect(store.size(), content="2") // 3 added - 1 removed
  inspect(store.has(@core.VectorId::from_int(1)), content="true")
  inspect(store.has(@core.VectorId::from_int(2)), content="false") // removed
  inspect(store.has(@core.VectorId::from_int(3)), content="true")
  // Verify attrs were updated
  let record3 = store.get(@core.VectorId::from_int(3))
  match record3 {
    Some(r) =>
      match r.attrs.get("tag") {
        Some(@core.String(s)) => inspect(s, content="C")
        _ => inspect(false, content="true")
      }
    None => inspect(false, content="true")
  }
}

///|
/// Test: WAL with large batch of records
test "wal/large_batch" {
  let storage = MemoryStorage::new()
  let wal = WalRuntime::new(storage, "large.wal")
  // Add 100 vectors
  let records : Array[WalRecord] = []
  for i in 1..<=100 {
    let attrs = @core.empty_attrs()
    attrs.set("index", @core.Int(i.to_int64()))
    records.push(
      WalRecord::upsert(
        @core.VectorId::from_int(i),
        [i.to_double() / 100.0, 1.0 - i.to_double() / 100.0, 0.0],
        attrs,
      ),
    )
  }
  wal.append(records) catch {
    _ => ()
  }
  // Replay
  let store = @core.CoreStore::new(3, @core.Dot)
  let count = wal.replay_into(store) catch { _ => 0 }
  inspect(count, content="100")
  inspect(store.size(), content="100")
  // Verify first and last
  inspect(store.has(@core.VectorId::from_int(1)), content="true")
  inspect(store.has(@core.VectorId::from_int(100)), content="true")
}

///|
/// Test: WAL record encoding/decoding with all attr types
test "wal/attr_types_roundtrip" {
  let attrs = @core.empty_attrs()
  attrs.set("string_val", @core.String("hello world"))
  attrs.set("int_val", @core.Int(42L))
  attrs.set("float_val", @core.Float(3.14159))
  attrs.set("bool_val", @core.Bool(true))
  attrs.set("null_val", @core.Null)
  let record = WalRecord::upsert(
    @core.VectorId::from_int(999),
    [1.0, 2.0, 3.0],
    attrs,
  )
  let encoded = encode_wal_record(record)
  let reader = @core.BinaryReader::new(encoded)
  let decoded = decode_wal_record(reader)
  match decoded {
    Some(r) => {
      inspect(r.id.to_int64(), content="999")
      inspect(r.record_type == WalRecordType::Upsert, content="true")
      match r.vector {
        Some(v) => {
          inspect(v.length(), content="3")
          // Float32 precision
          inspect((v[0] - 1.0).abs() < 0.001, content="true")
          inspect((v[1] - 2.0).abs() < 0.001, content="true")
        }
        None => inspect(false, content="true")
      }
      match r.attrs {
        Some(a) => {
          match a.get("string_val") {
            Some(@core.String(s)) => inspect(s, content="hello world")
            _ => inspect(false, content="true")
          }
          match a.get("int_val") {
            Some(@core.Int(n)) => inspect(n, content="42")
            _ => inspect(false, content="true")
          }
          match a.get("bool_val") {
            Some(@core.Bool(b)) => inspect(b, content="true")
            _ => inspect(false, content="true")
          }
        }
        None => inspect(false, content="true")
      }
    }
    None => inspect(false, content="true")
  }
}

///|
/// Test: CrushTarget with weight
test "crush/target_with_weight" {
  let target = CrushTarget::with_weight("node1", 2.0)
  inspect(target.key, content="node1")
  inspect(target.weight, content="2")
  inspect(target.zone is None, content="true")
}

///|
/// Test: CrushTarget with zone
test "crush/target_with_zone" {
  let target = CrushTarget::with_zone("node1", 1.5, "rack-a")
  inspect(target.key, content="node1")
  inspect(target.weight, content="1.5")
  match target.zone {
    Some(z) => inspect(z, content="rack-a")
    None => inspect(false, content="true")
  }
}

///|
/// Test: CRUSH rebalance planning
test "crush/plan_rebalance" {
  let old_targets = [CrushTarget::new("node1"), CrushTarget::new("node2")]
  let old_map = CrushMap::new(4, 1, old_targets)
  let manifest : PlacementManifest = {
    base: "db",
    segments: [
      SegmentEntry::{ name: "db.pg0.part0", target_key: "node1" },
      SegmentEntry::{ name: "db.pg1.part0", target_key: "node2" },
    ],
    crush: old_map,
    epoch: 1,
    commit_ts: 1000L,
  }
  // New map with different targets
  let new_targets = [
    CrushTarget::new("node1"),
    CrushTarget::new("node2"),
    CrushTarget::new("node3"),
  ]
  let new_map = CrushMap::new(4, 1, new_targets)
  let plan = plan_rebalance(manifest, new_map)
  // Some segments may need to move
  inspect(plan.length() >= 0, content="true")
}

///|
/// Test: CRUSH update manifest after rebalance
test "crush/update_manifest" {
  let targets = [CrushTarget::new("node1")]
  let map = CrushMap::new(2, 1, targets)
  let manifest : PlacementManifest = {
    base: "db",
    segments: [SegmentEntry::{ name: "db.pg0.part0", target_key: "node1" }],
    crush: map,
    epoch: 1,
    commit_ts: 1000L,
  }
  let plan : Array[MovePlan] = [
    MovePlan::{ name: "db.pg0.part0", from: "node1", to: "node2" },
  ]
  let new_targets = [CrushTarget::new("node1"), CrushTarget::new("node2")]
  let new_map = CrushMap::new(2, 1, new_targets)
  let updated = update_manifest_after_rebalance(
    manifest, plan, new_map, 2, 2000L,
  )
  inspect(updated.epoch, content="2")
  inspect(updated.commit_ts, content="2000")
  inspect(updated.segments[0].target_key, content="node2")
}

///|
/// Test: CRUSH replicas less than targets
test "crush/replicas_exceed_targets" {
  let targets = [CrushTarget::new("node1")]
  let map = CrushMap::new(8, 3, targets) // 3 replicas but only 1 target
  let result = crush_locate(@core.VectorId::from_int(1), map)
  // Should only return 1 primary (min of replicas and targets)
  inspect(result.primaries.length(), content="1")
}

///|
/// Test: Storage read non-existent file
test "storage/read_not_found" {
  let storage = MemoryStorage::new()
  let result : Bytes = storage.read("nonexistent.txt") catch {
    _ => Bytes::new(0)
  }
  inspect(result.length(), content="0")
}

///|
/// Test: Storage append to new file
test "storage/append_new_file" {
  let storage = MemoryStorage::new()
  let data = Bytes::from_array([b'n', b'e', b'w'][:])
  storage.append("new.txt", data) catch {
    _ => ()
  }
  let result = storage.read("new.txt") catch { _ => Bytes::new(0) }
  inspect(result.length(), content="3")
}

///|
/// Test: Storage delete non-existent file
test "storage/delete_not_found" {
  let storage = MemoryStorage::new()
  // Should not raise error
  storage.del("nonexistent.txt") catch {
    _ => ()
  }
  inspect(storage.exists("nonexistent.txt"), content="false")
}

///|
/// Test: WAL SetAttrs record
test "wal/set_attrs_record" {
  let attrs = @core.empty_attrs()
  attrs.set("key", @core.String("value"))
  let record = WalRecord::set_attrs(@core.VectorId::from_int(100), attrs)
  let encoded = encode_wal_record(record)
  let reader = @core.BinaryReader::new(encoded)
  let decoded = decode_wal_record(reader)
  match decoded {
    Some(r) => {
      inspect(r.record_type == WalRecordType::SetAttrs, content="true")
      inspect(r.id.to_int64(), content="100")
      inspect(r.vector is None, content="true")
      inspect(r.attrs is Some(_), content="true")
    }
    None => inspect(false, content="true")
  }
}

///|
/// Test: WAL Remove record
test "wal/remove_record" {
  let record = WalRecord::remove(@core.VectorId::from_int(50))
  let encoded = encode_wal_record(record)
  let reader = @core.BinaryReader::new(encoded)
  let decoded = decode_wal_record(reader)
  match decoded {
    Some(r) => {
      inspect(r.record_type == WalRecordType::Remove, content="true")
      inspect(r.id.to_int64(), content="50")
      inspect(r.vector is None, content="true")
    }
    None => inspect(false, content="true")
  }
}

///|
/// Test: WAL record type conversion
test "wal/record_type_conversion" {
  inspect(WalRecordType::Upsert.to_byte() == b'\x01', content="true")
  inspect(WalRecordType::Remove.to_byte() == b'\x02', content="true")
  inspect(WalRecordType::SetAttrs.to_byte() == b'\x03', content="true")
  // From byte
  match WalRecordType::from_byte(b'\x01') {
    Some(t) => inspect(t == WalRecordType::Upsert, content="true")
    None => inspect(false, content="true")
  }
  match WalRecordType::from_byte(b'\x02') {
    Some(t) => inspect(t == WalRecordType::Remove, content="true")
    None => inspect(false, content="true")
  }
  // Invalid byte
  inspect(WalRecordType::from_byte(b'\xFF') is None, content="true")
}

///|
/// Test: WAL segment with corrupted checksum
test "wal/corrupted_checksum" {
  let records = [
    WalRecord::upsert(@core.VectorId::from_int(1), [1.0], @core.empty_attrs()),
  ]
  let segment = encode_wal_segment(records)
  // Corrupt the checksum (last 4 bytes)
  let corrupted_arr : FixedArray[Byte] = FixedArray::make(
    segment.length(),
    b'\x00',
  )
  for i in 0..<segment.length() {
    corrupted_arr[i] = segment[i]
  }
  corrupted_arr[segment.length() - 1] = b'\xFF'
  let corrupted = Bytes::from_array(corrupted_arr)
  inspect(verify_wal_checksum(corrupted), content="false")
}

///|
/// Test: WAL with empty attrs
test "wal/empty_attrs" {
  let record = WalRecord::upsert(
    @core.VectorId::from_int(1),
    [1.0, 2.0],
    @core.empty_attrs(),
  )
  let encoded = encode_wal_record(record)
  let reader = @core.BinaryReader::new(encoded)
  let decoded = decode_wal_record(reader)
  match decoded {
    Some(r) => {
      inspect(r.id.to_int64(), content="1")
      match r.attrs {
        Some(a) => {
          // Empty attrs should decode as empty map
          let mut count = 0
          for _ in a.keys() {
            count = count + 1
          }
          inspect(count, content="0")
        }
        None => inspect(false, content="true")
      }
    }
    None => inspect(false, content="true")
  }
}

///|
/// Test: WAL truncate
test "wal/truncate" {
  let storage = MemoryStorage::new()
  let wal = WalRuntime::new(storage, "truncate.wal")
  // Append some records
  let records = [
    WalRecord::upsert(@core.VectorId::from_int(1), [1.0], @core.empty_attrs()),
  ]
  wal.append(records) catch {
    _ => ()
  }
  let before = storage.read("truncate.wal") catch { _ => Bytes::new(0) }
  inspect(before.length() > 8, content="true") // Header + records
  // Truncate
  wal.truncate()
  // WAL should be reset to just header (8 bytes)
  let data = storage.read("truncate.wal") catch { _ => Bytes::new(0) }
  inspect(data.length(), content="8") // Just header
}

///|
/// Test: Storage clear
test "storage/clear" {
  let storage = MemoryStorage::new()
  storage.write("a.txt", Bytes::from_array([b'a'][:]))
  storage.write("b.txt", Bytes::from_array([b'b'][:]))
  inspect(storage.list().length(), content="2")
  storage.clear()
  inspect(storage.list().length(), content="0")
}

///|
/// Test: Storage delete existing file
test "storage/delete_existing" {
  let storage = MemoryStorage::new()
  storage.write("test.txt", Bytes::from_array([b'x'][:]))
  inspect(storage.exists("test.txt"), content="true")
  storage.del("test.txt") catch {
    _ => ()
  }
  inspect(storage.exists("test.txt"), content="false")
}

///|
/// Test: WAL JSON escaping special characters
test "wal/json_escape_special" {
  let attrs = @core.empty_attrs()
  attrs.set("text", @core.String("hello\nworld\ttab\"quote\\backslash"))
  attrs.set("cr", @core.String("line\rwith\rCR"))
  let record = WalRecord::upsert(@core.VectorId::from_int(1), [1.0], attrs)
  let encoded = encode_wal_record(record)
  let reader = @core.BinaryReader::new(encoded)
  let decoded = decode_wal_record(reader)
  match decoded {
    Some(r) =>
      match r.attrs {
        Some(a) =>
          match a.get("text") {
            Some(@core.String(s)) =>
              inspect(
                s == "hello\nworld\ttab\"quote\\backslash",
                content="true",
              )
            _ => inspect(false, content="true")
          }
        None => inspect(false, content="true")
      }
    None => inspect(false, content="true")
  }
}

///|
/// Test: WAL attrs with Float values
test "wal/attrs_float" {
  let attrs = @core.empty_attrs()
  attrs.set("pi", @core.Float(3.14159))
  attrs.set("neg", @core.Float(-2.5))
  let record = WalRecord::set_attrs(@core.VectorId::from_int(1), attrs)
  let encoded = encode_wal_record(record)
  let reader = @core.BinaryReader::new(encoded)
  let decoded = decode_wal_record(reader)
  match decoded {
    Some(r) =>
      match r.attrs {
        Some(a) =>
          match a.get("pi") {
            Some(@core.Float(f)) =>
              inspect((f - 3.14159).abs() < 0.001, content="true")
            _ => inspect(false, content="true")
          }
        None => inspect(false, content="true")
      }
    None => inspect(false, content="true")
  }
}

///|
/// Test: WAL attrs with Bool values
test "wal/attrs_bool" {
  let attrs = @core.empty_attrs()
  attrs.set("active", @core.Bool(true))
  attrs.set("deleted", @core.Bool(false))
  let record = WalRecord::set_attrs(@core.VectorId::from_int(1), attrs)
  let encoded = encode_wal_record(record)
  let reader = @core.BinaryReader::new(encoded)
  let decoded = decode_wal_record(reader)
  match decoded {
    Some(r) =>
      match r.attrs {
        Some(a) => {
          match a.get("active") {
            Some(@core.Bool(b)) => inspect(b, content="true")
            _ => inspect(false, content="true")
          }
          match a.get("deleted") {
            Some(@core.Bool(b)) => inspect(b, content="false")
            _ => inspect(false, content="true")
          }
        }
        None => inspect(false, content="true")
      }
    None => inspect(false, content="true")
  }
}

///|
/// Test: WAL decode with invalid header
test "wal/decode_invalid_header" {
  // Invalid magic number
  let bad_data = Bytes::from_array(
    [b'B', b'A', b'D', b'!', b'\x02', b'\x00', b'\x00', b'\x00'][:],
  )
  let records = decode_wal_records(bad_data)
  inspect(records.length(), content="0")
}

///|
/// Test: WAL decode with short data
test "wal/decode_short_data" {
  let short_data = Bytes::from_array([b'V', b'L', b'W'][:])
  let records = decode_wal_records(short_data)
  inspect(records.length(), content="0")
}

///|
/// Test: WAL header verification
test "wal/verify_header" {
  // Valid header
  let valid = encode_wal_header()
  let reader = @core.BinaryReader::new(valid)
  inspect(verify_wal_header(reader), content="true")
  // Invalid magic
  let invalid = Bytes::from_array(
    [b'X', b'X', b'X', b'X', b'\x02', b'\x00', b'\x00', b'\x00'][:],
  )
  let reader2 = @core.BinaryReader::new(invalid)
  inspect(verify_wal_header(reader2), content="false")
}

///|
/// Test: WAL segment without footer
test "wal/segment_no_footer" {
  // Create segment with only header (8 bytes)
  let header = encode_wal_header()
  // Header-only WAL is valid (used after truncate)
  inspect(verify_wal_checksum(header), content="true")
  // Create larger segment without footer
  let w = @core.BinaryWriter::new()
  w.push_bytes(header)
  // Add some padding to make it >= 16 bytes
  for _ in 0..<8 {
    w.push_byte(b'\x00')
  }
  let no_footer = w.concat()
  inspect(verify_wal_checksum(no_footer), content="true")
  // Too short to have header (< 8 bytes) should fail
  let too_short = Bytes::new(4)
  inspect(verify_wal_checksum(too_short), content="false")
}

///|
/// Test: WAL decode short record
test "wal/decode_short_record" {
  // Create valid header but truncated record
  let w = @core.BinaryWriter::new()
  w.push_bytes(encode_wal_header())
  w.push_byte(b'\x01') // Record type
  w.push_byte(b'\x00') // Reserved
  // Missing rest of record
  let data = w.concat()
  let records = decode_wal_records(data)
  inspect(records.length(), content="0")
}

///|
/// Test: CRUSH locate with different PG counts
test "crush/pg_distribution" {
  let targets = [
    CrushTarget::new("node1"),
    CrushTarget::new("node2"),
    CrushTarget::new("node3"),
    CrushTarget::new("node4"),
  ]
  let map = CrushMap::new(32, 2, targets)
  // Test that different IDs get different PGs
  let mut pg0_count = 0
  let mut pg1_count = 0
  for i in 1..<=100 {
    let result = crush_locate(@core.VectorId::from_int(i), map)
    if result.pg == 0 {
      pg0_count = pg0_count + 1
    } else if result.pg == 1 {
      pg1_count = pg1_count + 1
    }
  }
  // Should have some variance in distribution
  inspect(pg0_count < 100, content="true")
  inspect(pg1_count < 100, content="true")
}

///|
/// Test: CRUSH zone-aware placement
test "crush/zone_aware" {
  let targets = [
    CrushTarget::with_zone("node1", 1.0, "rack-a"),
    CrushTarget::with_zone("node2", 1.0, "rack-a"),
    CrushTarget::with_zone("node3", 1.0, "rack-b"),
    CrushTarget::with_zone("node4", 1.0, "rack-b"),
  ]
  let map = CrushMap::new(8, 2, targets)
  let result = crush_locate(@core.VectorId::from_int(42), map)
  // Should have 2 primaries
  inspect(result.primaries.length(), content="2")
}

///|
/// Test: WAL runtime with corrupted data
test "wal/runtime_corrupted" {
  let storage = MemoryStorage::new()
  // Write corrupted WAL file
  let corrupted = Bytes::from_array(
    [b'X', b'X', b'X', b'X', b'X', b'X', b'X', b'X'][:],
  )
  storage.write("corrupted.wal", corrupted)
  let wal = WalRuntime::new(storage, "corrupted.wal")
  let store = @core.CoreStore::new(3, @core.Dot)
  let count = wal.replay_into(store) catch { _ => 0 }
  inspect(count, content="0")
}

///|
/// Test: WAL runtime empty file
test "wal/runtime_empty" {
  let storage = MemoryStorage::new()
  let wal = WalRuntime::new(storage, "new.wal")
  let store = @core.CoreStore::new(3, @core.Dot)
  let count = wal.replay_into(store) catch { _ => 0 }
  inspect(count, content="0")
}

///|
/// Test: WAL runtime size and exists
test "wal/runtime_size_exists" {
  let storage = MemoryStorage::new()
  let wal = WalRuntime::new(storage, "size.wal")
  // Not exists yet
  inspect(wal.exists(), content="false")
  inspect(wal.size(), content="0")
  // Append some records
  let records = [
    WalRecord::upsert(
      @core.VectorId::from_int(1),
      [1.0, 2.0],
      @core.empty_attrs(),
    ),
  ]
  wal.append(records) catch {
    _ => ()
  }
  inspect(wal.exists(), content="true")
  inspect(wal.size() > 8, content="true") // At least header + record
}

///|
/// Test: WAL runtime append empty array
test "wal/runtime_append_empty" {
  let storage = MemoryStorage::new()
  let wal = WalRuntime::new(storage, "empty_append.wal")
  // Append empty should not create file
  wal.append([]) catch {
    _ => ()
  }
  inspect(wal.exists(), content="false")
}

///|
/// Test: Storage read not found error
test "storage/read_not_found_error" {
  let storage = MemoryStorage::new()
  let result : Bytes = storage.read("nonexistent.txt") catch {
    IOError::NotFound(path) => {
      inspect(path, content="nonexistent.txt")
      Bytes::new(0)
    }
    _ => Bytes::new(0)
  }
  inspect(result.length(), content="0")
}

///|
/// Test: Storage del not found error
test "storage/del_not_found_error" {
  let storage = MemoryStorage::new()
  let mut caught = false
  storage.del("nonexistent.txt") catch {
    IOError::NotFound(_) => caught = true
    _ => ()
  }
  inspect(caught, content="true")
}

///|
/// Test: WAL runtime replay with SetAttrs for non-existent ID
test "wal/runtime_setattrs_nonexistent" {
  let storage = MemoryStorage::new()
  let wal = WalRuntime::new(storage, "setattrs.wal")
  // SetAttrs for ID that doesn't exist in store
  let attrs = @core.empty_attrs()
  attrs.set("key", @core.String("value"))
  let records = [WalRecord::set_attrs(@core.VectorId::from_int(999), attrs)]
  wal.append(records) catch {
    _ => ()
  }
  let store = @core.CoreStore::new(2, @core.Dot)
  let count = wal.replay_into(store) catch { _ => 0 }
  // SetAttrs increments count but doesn't create new vector
  inspect(count, content="1")
  inspect(store.size(), content="0")
}

///|
/// Test: WAL runtime replay Remove for non-existent ID
test "wal/runtime_remove_nonexistent" {
  let storage = MemoryStorage::new()
  let wal = WalRuntime::new(storage, "remove.wal")
  // Remove ID that doesn't exist
  let records = [WalRecord::remove(@core.VectorId::from_int(999))]
  wal.append(records) catch {
    _ => ()
  }
  let store = @core.CoreStore::new(2, @core.Dot)
  let count = wal.replay_into(store) catch { _ => 0 }
  inspect(count, content="1")
  inspect(store.size(), content="0")
}

///|
/// Test: WAL runtime append to existing WAL
test "wal/runtime_append_existing" {
  let storage = MemoryStorage::new()
  let wal = WalRuntime::new(storage, "append.wal")
  // First append
  let records1 = [
    WalRecord::upsert(@core.VectorId::from_int(1), [1.0], @core.empty_attrs()),
  ]
  wal.append(records1) catch {
    _ => ()
  }
  let size1 = wal.size()
  // Second append
  let records2 = [
    WalRecord::upsert(@core.VectorId::from_int(2), [2.0], @core.empty_attrs()),
  ]
  wal.append(records2) catch {
    _ => ()
  }
  let size2 = wal.size()
  // Should have grown
  inspect(size2 > size1, content="true")
  // Replay should have 2 vectors
  let store = @core.CoreStore::new(1, @core.Dot)
  let count = wal.replay_into(store) catch { _ => 0 }
  inspect(count, content="2")
  inspect(store.size(), content="2")
}

///|
/// Test: CRUSH with zero PGs
test "crush/zero_pgs" {
  let targets = [CrushTarget::new("node1")]
  let map = CrushMap::new(0, 1, targets)
  let result = crush_locate(@core.VectorId::from_int(1), map)
  inspect(result.pg, content="0")
}

///|
/// Test: WAL Upsert without attrs
test "wal/upsert_no_attrs" {
  let storage = MemoryStorage::new()
  let wal = WalRuntime::new(storage, "no_attrs.wal")
  // Create record manually without attrs
  let record : WalRecord = {
    record_type: WalRecordType::Upsert,
    id: @core.VectorId::from_int(1),
    attrs: None,
    vector: Some([1.0, 2.0]),
  }
  let encoded = encode_wal_record(record)
  // Should still encode/decode
  let reader = @core.BinaryReader::new(encoded)
  let decoded = decode_wal_record(reader)
  inspect(decoded is Some(_), content="true")
}

///|
/// Test: CRUSH apply_rebalance_memory
test "crush/apply_rebalance" {
  let storage1 = MemoryStorage::new()
  let storage2 = MemoryStorage::new()
  // Write some data to storage1
  storage1.write(
    "db.pg0.part0.data",
    Bytes::from_array([b'h', b'e', b'l', b'l', b'o'][:]),
  )
  let storages : Map[String, MemoryStorage] = {}
  storages.set("node1", storage1)
  storages.set("node2", storage2)
  // Create move plan
  let plan : Array[MovePlan] = [
    { name: "db.pg0.part0", from: "node1", to: "node2" },
  ]
  // Apply rebalance
  apply_rebalance_memory(plan, storages) catch {
    _ => ()
  }
  // Verify data moved
  inspect(storage2.exists("db.pg0.part0.data"), content="true")
  let data = storage2.read("db.pg0.part0.data") catch { _ => Bytes::new(0) }
  inspect(data.length(), content="5")
}

///|
/// Test: CRUSH apply_rebalance_memory source not found
test "crush/apply_rebalance_no_source" {
  let storages : Map[String, MemoryStorage] = {}
  let plan : Array[MovePlan] = [{ name: "missing", from: "node1", to: "node2" }]
  let mut caught = false
  apply_rebalance_memory(plan, storages) catch {
    IOError::IoFailed(msg) => {
      inspect(msg.has_prefix("Source storage not found"), content="true")
      caught = true
    }
    _ => ()
  }
  inspect(caught, content="true")
}

///|
/// Test: CRUSH apply_rebalance_memory dest not found
test "crush/apply_rebalance_no_dest" {
  let storage1 = MemoryStorage::new()
  storage1.write("test.data", Bytes::from_array([b'x'][:]))
  let storages : Map[String, MemoryStorage] = {}
  storages.set("node1", storage1)
  let plan : Array[MovePlan] = [{ name: "test", from: "node1", to: "node2" }]
  let mut caught = false
  apply_rebalance_memory(plan, storages) catch {
    IOError::IoFailed(msg) => {
      inspect(msg.has_prefix("Destination storage not found"), content="true")
      caught = true
    }
    _ => ()
  }
  inspect(caught, content="true")
}

///|
/// Test: CRUSH plan_rebalance no changes
test "crush/plan_rebalance_no_changes" {
  let targets = [CrushTarget::new("node1")]
  let map = CrushMap::new(4, 1, targets)
  let manifest : PlacementManifest = {
    base: "db",
    segments: [SegmentEntry::{ name: "db.pg0.part0", target_key: "node1" }],
    crush: map,
    epoch: 1,
    commit_ts: 1000L,
  }
  // Same map, no changes
  let plan = plan_rebalance(manifest, map)
  inspect(plan.length(), content="0")
}

///|
/// Test: CRUSH target_for_pg with empty targets
test "crush/target_for_pg_empty" {
  let targets : Array[CrushTarget] = []
  let map = CrushMap::new(4, 1, targets)
  let manifest : PlacementManifest = {
    base: "db",
    segments: [],
    crush: map,
    epoch: 1,
    commit_ts: 1000L,
  }
  let plan = plan_rebalance(manifest, map)
  inspect(plan.length(), content="0")
}

///|
/// Test: Storage trait implementation through interface
test "storage/trait_impl" {
  let storage : MemoryStorage = MemoryStorage::new()
  // Test through trait interface
  (storage as &Storage).write(
    "trait_test.txt",
    Bytes::from_array([b't', b'e', b's', b't'][:]),
  )
  inspect((storage as &Storage).exists("trait_test.txt"), content="true")
  let data = (storage as &Storage).read("trait_test.txt") catch {
    _ => Bytes::new(0)
  }
  inspect(data.length(), content="4")
  let files = (storage as &Storage).list()
  inspect(files.length(), content="1")
  (storage as &Storage).del("trait_test.txt") catch {
    _ => ()
  }
  inspect((storage as &Storage).exists("trait_test.txt"), content="false")
}

///|
/// Test: Storage atomic_write trait
test "storage/trait_atomic_write" {
  let storage : MemoryStorage = MemoryStorage::new()
  (storage as &Storage).atomic_write("atomic.txt", Bytes::from_array([b'a'][:]))
  inspect((storage as &Storage).exists("atomic.txt"), content="true")
}

///|
/// Test: Storage append trait
test "storage/trait_append" {
  let storage : MemoryStorage = MemoryStorage::new()
  (storage as &Storage).write("append.txt", Bytes::from_array([b'a'][:]))
  (storage as &Storage).append("append.txt", Bytes::from_array([b'b'][:]))
  let data = (storage as &Storage).read("append.txt") catch {
    _ => Bytes::new(0)
  }
  inspect(data.length(), content="2")
}

///|
/// Test: WAL with UTF-8 multibyte characters
test "wal/utf8_multibyte" {
  let attrs = @core.empty_attrs()
  attrs.set("emoji", @core.String("hello 👋"))
  attrs.set("japanese", @core.String("こんにちは"))
  attrs.set("mixed", @core.String("abc日本語123"))
  let record = WalRecord::upsert(@core.VectorId::from_int(1), [1.0], attrs)
  let encoded = encode_wal_record(record)
  let reader = @core.BinaryReader::new(encoded)
  let decoded = decode_wal_record(reader)
  match decoded {
    Some(r) =>
      match r.attrs {
        Some(a) =>
          match a.get("mixed") {
            Some(@core.String(s)) => inspect(s.length() > 0, content="true")
            _ => inspect(false, content="true")
          }
        None => inspect(false, content="true")
      }
    None => inspect(false, content="true")
  }
}

///|
/// Test: WAL attrs with negative numbers
test "wal/attrs_negative" {
  let attrs = @core.empty_attrs()
  attrs.set("neg_int", @core.Int(-42L))
  attrs.set("neg_float", @core.Float(-3.14))
  let record = WalRecord::set_attrs(@core.VectorId::from_int(1), attrs)
  let encoded = encode_wal_record(record)
  let reader = @core.BinaryReader::new(encoded)
  let decoded = decode_wal_record(reader)
  match decoded {
    Some(r) =>
      match r.attrs {
        Some(a) =>
          match a.get("neg_int") {
            Some(@core.Int(n)) => inspect(n, content="-42")
            _ => inspect(false, content="true")
          }
        None => inspect(false, content="true")
      }
    None => inspect(false, content="true")
  }
}

///|
/// Test: WAL segment encoding with multiple record types
test "wal/segment_mixed_types" {
  let records = [
    WalRecord::upsert(
      @core.VectorId::from_int(1),
      [1.0, 2.0],
      @core.empty_attrs(),
    ),
    WalRecord::set_attrs(
      @core.VectorId::from_int(1),
      {
        let a = @core.empty_attrs()
        a.set("key", @core.String("value"))
        a
      },
    ),
    WalRecord::remove(@core.VectorId::from_int(2)),
  ]
  let segment = encode_wal_segment(records)
  let decoded = decode_wal_records(segment)
  inspect(decoded.length(), content="3")
  inspect(decoded[0].record_type == WalRecordType::Upsert, content="true")
  inspect(decoded[1].record_type == WalRecordType::SetAttrs, content="true")
  inspect(decoded[2].record_type == WalRecordType::Remove, content="true")
}

///|
/// Test: WAL preserves full Int64 IDs (P1 fix)
test "wal/large_int64_ids" {
  // Test with IDs that exceed 32-bit range
  let large_id = @core.VectorId(0x1_0000_0001L) // 4294967297, larger than u32 max
  let negative_id = @core.VectorId(-1L)
  let max_id = @core.VectorId(9223372036854775807L) // Int64 max
  let record1 = WalRecord::upsert(large_id, [1.0], @core.empty_attrs())
  let record2 = WalRecord::remove(negative_id)
  let record3 = WalRecord::set_attrs(max_id, @core.empty_attrs())
  // Encode and decode
  let encoded1 = encode_wal_record(record1)
  let decoded1 = decode_wal_record(@core.BinaryReader::new(encoded1))
  match decoded1 {
    Some(r) => inspect(r.id.to_int64(), content="4294967297")
    None => inspect(false, content="true")
  }
  let encoded2 = encode_wal_record(record2)
  let decoded2 = decode_wal_record(@core.BinaryReader::new(encoded2))
  match decoded2 {
    Some(r) => inspect(r.id.to_int64(), content="-1")
    None => inspect(false, content="true")
  }
  let encoded3 = encode_wal_record(record3)
  let decoded3 = decode_wal_record(@core.BinaryReader::new(encoded3))
  match decoded3 {
    Some(r) => inspect(r.id.to_int64(), content="9223372036854775807")
    None => inspect(false, content="true")
  }
}

///|
/// Test: WAL replay with large IDs
test "wal/replay_large_ids" {
  let storage = MemoryStorage::new()
  let wal = WalRuntime::new(storage, "large_ids.wal")
  let large_id = @core.VectorId(0x1_0000_0001L)
  let records = [
    WalRecord::upsert(large_id, [1.0, 2.0, 3.0], @core.empty_attrs()),
  ]
  wal.append(records) catch {
    _ => ()
  }
  let store = @core.CoreStore::new(3, @core.Dot)
  let count = wal.replay_into(store) catch { _ => 0 }
  inspect(count, content="1")
  inspect(store.has(large_id), content="true")
}

///|
/// Test: CRUSH hashing preserves full 64-bit IDs (P1 fix)
/// IDs differing only in upper 32 bits should produce different placements
test "crush/full_64bit_hashing" {
  let targets = [
    CrushTarget::new("node1"),
    CrushTarget::new("node2"),
    CrushTarget::new("node3"),
    CrushTarget::new("node4"),
  ]
  let map = CrushMap::new(256, 2, targets)
  // IDs that differ only in upper 32 bits
  let id_low = @core.VectorId(1L) // Lower 32 bits: 1, Upper 32 bits: 0
  let id_high = @core.VectorId(0x1_0000_0001L) // Lower 32 bits: 1, Upper 32 bits: 1
  let result_low = crush_locate(id_low, map)
  let result_high = crush_locate(id_high, map)
  // These should produce different placement groups (hash includes upper bits)
  // Note: They could theoretically collide but with 256 PGs it's unlikely
  inspect(result_low.pg != result_high.pg, content="true")
}

///|
/// Test: CRUSH hashing with various 64-bit ID patterns
test "crush/64bit_id_patterns" {
  let targets = [
    CrushTarget::new("a"),
    CrushTarget::new("b"),
    CrushTarget::new("c"),
    CrushTarget::new("d"),
  ]
  let map = CrushMap::new(1024, 1, targets)
  // Test IDs with different upper/lower bit patterns
  let ids = [
    @core.VectorId(0L), // All zeros
    @core.VectorId(0xFFFF_FFFF_FFFF_FFFFL), // All ones (negative in signed)
    @core.VectorId(0x8000_0000_0000_0000L), // Only MSB set
    @core.VectorId(0x0000_0000_8000_0000L), // Only bit 31 set (lower half MSB)
    @core.VectorId(0x1234_5678_0000_0000L), // Upper 32 bits only
    @core.VectorId(0x0000_0000_1234_5678L), // Lower 32 bits only
  ]
  // All should get valid placements
  for id in ids {
    let result = crush_locate(id, map)
    inspect(result.pg >= 0, content="true")
    inspect(result.pg < 1024, content="true")
    inspect(result.primaries.length() > 0, content="true")
  }
}

///|
/// Test: WAL truncated record is handled gracefully
test "wal/truncated_record" {
  // Create a valid WAL segment
  let attrs = @core.empty_attrs()
  attrs.set("key", @core.String("value"))
  let record : WalRecord = {
    record_type: WalRecordType::Upsert,
    id: @core.VectorId::from_int(1),
    attrs: Some(attrs),
    vector: Some([1.0, 2.0, 3.0]),
  }
  let full_segment = encode_wal_segment([record])
  // Truncate in the middle of the record body - copy first half
  let truncate_len = full_segment.length() / 2
  let w = @core.BinaryWriter::new()
  for i in 0..<truncate_len {
    w.push_byte(full_segment[i])
  }
  let truncated = w.concat()
  // Should not crash, just return empty records
  let records = decode_wal_records(truncated)
  // Records should be empty (truncated data rejected)
  inspect(records.length(), content="0")
}

///|
/// Test: WAL corrupted checksum is rejected during replay
test "wal/corrupted_checksum_rejected" {
  let storage = MemoryStorage::new()
  // Create valid WAL segment with footer
  let record : WalRecord = {
    record_type: WalRecordType::Upsert,
    id: @core.VectorId::from_int(1),
    attrs: None,
    vector: Some([1.0, 2.0]),
  }
  let segment = encode_wal_segment([record])
  // Corrupt a byte in the body (before footer) - flip bit at position 10
  let w = @core.BinaryWriter::new()
  for i in 0..<segment.length() {
    if i == 10 {
      w.push_byte((segment[i].to_int() ^ 0xFF).to_byte())
    } else {
      w.push_byte(segment[i])
    }
  }
  let corrupted = w.concat()
  // Write corrupted WAL
  storage.atomic_write("test.wal", corrupted)
  // Replay should fail with checksum error
  let wal = WalRuntime::new(storage, "test.wal")
  let store = @core.CoreStore::new(2, @core.Cosine)
  let mut replay_failed = false
  let _ = wal.replay_into(store) catch {
    IoFailed(_) => {
      replay_failed = true
      0
    }
    _ => 0 // Other errors don't count as checksum failure
  }
  inspect(replay_failed, content="true")
}

///|
/// Test: WAL with invalid attrs_len is rejected
test "wal/invalid_attrs_len" {
  // Manually create a record with impossibly large attrs_len
  let w = @core.BinaryWriter::new()
  // Header
  w.push_u32(0x564C5741U) // Magic
  w.push_u32(2U) // Version
  // Record type (Upsert = 1)
  w.push_byte(b'\x01')
  // Reserved
  w.push_byte(b'\x00')
  // ID (8 bytes)
  w.push_u64(1UL)
  // attrs_len = 1000000 (way more than remaining)
  w.push_u32(1000000U)
  // vector_len = 0
  w.push_u32(0U)
  let bad_wal = w.concat()
  // Should not crash, just return empty records
  let records = decode_wal_records(bad_wal)
  inspect(records.length(), content="0")
}

///|
/// Test: Replay after truncate should succeed (header-only WAL is valid)
test "wal/replay_after_truncate" {
  let storage = MemoryStorage::new()
  let wal = WalRuntime::new(storage, "truncate.wal")
  // Append some records
  let record : WalRecord = {
    record_type: WalRecordType::Upsert,
    id: @core.VectorId::from_int(1),
    attrs: None,
    vector: Some([1.0, 2.0]),
  }
  wal.append([record]) catch {
    _ => ()
  }
  // Truncate to header-only
  wal.truncate()
  // Replay should succeed with 0 records (not raise error)
  let store = @core.CoreStore::new(2, @core.Cosine)
  let applied = wal.replay_into(store) catch { _ => -1 }
  inspect(applied, content="0")
}

///|
/// Test: JSON parsing handles exponent notation (e.g. 1e-7)
test "wal/json_exponent_notation" {
  // Create attrs with a small float that serializes to exponent form
  let attrs = @core.empty_attrs()
  let tiny_val = 0.0000001 // 1e-7
  attrs.set("tiny", @core.Float(tiny_val))
  // Encode to JSON
  let encoded = encode_attrs_json(Some(attrs))
  // Decode back
  let decoded = decode_attrs_json(encoded)
  match decoded {
    None => inspect(false, content="true") // Should not fail
    Some(result) =>
      match result.get("tiny") {
        None => inspect(false, content="true")
        Some(val) =>
          match val {
            @core.Float(f) => inspect(f < 0.000001 && f > 0.0, content="true")
            _ => inspect(false, content="true") // Should be Float, not Null
          }
      }
  }
}

///|
/// Test: WAL rejects non-aligned vector payloads
test "wal/reject_non_aligned_vector" {
  let w = @core.BinaryWriter::new()
  // Header
  w.push_u32(0x564C5741U) // Magic
  w.push_u32(2U) // Version
  // Record type (Upsert = 1)
  w.push_byte(b'\x01')
  // Reserved
  w.push_byte(b'\x00')
  // ID (8 bytes)
  w.push_u64(1UL)
  // attrs_len = 0
  w.push_u32(0U)
  // vector_len = 5 (not a multiple of 4)
  w.push_u32(5U)
  // Add 5 bytes of garbage
  for _ in 0..<5 {
    w.push_byte(b'\x00')
  }
  let bad_wal = w.concat()
  // Should reject the record
  let records = decode_wal_records(bad_wal)
  inspect(records.length(), content="0")
}

///|
/// Test: parse_pg_from_name handles base names containing "pg"
test "crush/parse_pg_with_pg_in_base" {
  // Base name "mypgdb" contains "pg" but should parse ".pg5" suffix
  let name = "mypgdb.pg5.part0"
  let pg = parse_pg_from_name(name)
  inspect(pg, content="5")
  // Another example: "postgres_backup.pg123.part2"
  let name2 = "postgres_backup.pg123.part2"
  let pg2 = parse_pg_from_name(name2)
  inspect(pg2, content="123")
  // No ".pg" should return 0
  let name3 = "pgdata"
  let pg3 = parse_pg_from_name(name3)
  inspect(pg3, content="0")
}

///|
/// Test: WAL append writes checksum footer
test "wal/append_writes_footer" {
  let storage = MemoryStorage::new()
  let wal = WalRuntime::new(storage, "footer.wal")
  let record : WalRecord = {
    record_type: WalRecordType::Upsert,
    id: @core.VectorId::from_int(1),
    attrs: None,
    vector: Some([1.0, 2.0]),
  }
  wal.append([record]) catch {
    _ => ()
  }
  // Read and verify footer is present
  let data = storage.read("footer.wal") catch { _ => Bytes::new(0) }
  // Check footer magic at end
  inspect(data.length() >= 16, content="true")
  let footer_start = data.length() - 8
  let r = @core.BinaryReader::new(data)
  let _ = r.read_bytes(footer_start)
  let footer_magic = r.read_u32()
  inspect(footer_magic == wal_footer_magic, content="true")
  // Verify checksum
  inspect(verify_wal_checksum(data), content="true")
}

///|
/// Test: WAL append reinitializes header for invalid/empty files
test "wal/append_reinit_invalid_header" {
  let storage = MemoryStorage::new()
  // Write garbage to WAL file (no valid header)
  let garbage = Bytes::new(4)
  storage.atomic_write("invalid.wal", garbage)
  // Append should detect invalid header and start fresh
  let wal = WalRuntime::new(storage, "invalid.wal")
  let record : WalRecord = {
    record_type: WalRecordType::Upsert,
    id: @core.VectorId::from_int(1),
    attrs: None,
    vector: Some([1.0, 2.0]),
  }
  wal.append([record]) catch {
    _ => ()
  }
  // Read and verify header is valid now
  let data = storage.read("invalid.wal") catch { _ => Bytes::new(0) }
  let r = @core.BinaryReader::new(data)
  inspect(verify_wal_header(r), content="true")
  // Should be able to decode the record
  let records = decode_wal_records(data)
  inspect(records.length(), content="1")
}

///|
/// Test: WAL append rejects corrupted checksum and starts fresh
test "wal/append_rejects_corrupted_checksum" {
  let storage = MemoryStorage::new()
  // Create valid WAL first
  let wal = WalRuntime::new(storage, "corrupt.wal")
  let record1 : WalRecord = {
    record_type: WalRecordType::Upsert,
    id: @core.VectorId::from_int(1),
    attrs: None,
    vector: Some([1.0, 2.0]),
  }
  wal.append([record1]) catch {
    _ => ()
  }
  // Corrupt the body (flip byte in middle, before footer)
  let data = storage.read("corrupt.wal") catch { _ => Bytes::new(0) }
  let w = @core.BinaryWriter::new()
  for i in 0..<data.length() {
    if i == 10 {
      w.push_byte((data[i].to_int() ^ 0xFF).to_byte())
    } else {
      w.push_byte(data[i])
    }
  }
  storage.atomic_write("corrupt.wal", w.concat())
  // Verify it's now corrupted
  let corrupted = storage.read("corrupt.wal") catch { _ => Bytes::new(0) }
  inspect(verify_wal_checksum(corrupted), content="false")
  // Append to corrupted WAL - should start fresh
  let record2 : WalRecord = {
    record_type: WalRecordType::Upsert,
    id: @core.VectorId::from_int(2),
    attrs: None,
    vector: Some([3.0, 4.0]),
  }
  wal.append([record2]) catch {
    _ => ()
  }
  // Result should have valid checksum and only the new record
  let final_data = storage.read("corrupt.wal") catch { _ => Bytes::new(0) }
  inspect(verify_wal_checksum(final_data), content="true")
  let records = decode_wal_records(final_data)
  // Only new record (corrupted data was discarded)
  inspect(records.length(), content="1")
  inspect(records[0].id.to_int64(), content="2")
}

///|
/// Test: WAL replay rejects invalid header
test "wal/replay_rejects_invalid_header" {
  let storage = MemoryStorage::new()
  // Write non-WAL data (valid checksum won't help)
  let garbage = Bytes::new(20) // >= 16 bytes but not a WAL
  storage.atomic_write("garbage.wal", garbage)
  let wal = WalRuntime::new(storage, "garbage.wal")
  let store = @core.CoreStore::new(2, @core.Cosine)
  let mut replay_failed = false
  let _ = wal.replay_into(store) catch {
    IoFailed(msg) => {
      if msg == "WAL header invalid" {
        replay_failed = true
      }
      0
    }
    _ => 0
  }
  inspect(replay_failed, content="true")
}

///|
/// Test: WAL append handles truncated tail (no footer)
test "wal/append_truncated_tail" {
  let storage = MemoryStorage::new()
  // Create valid WAL first
  let wal = WalRuntime::new(storage, "truncated.wal")
  let record1 : WalRecord = {
    record_type: WalRecordType::Upsert,
    id: @core.VectorId::from_int(1),
    attrs: None,
    vector: Some([1.0, 2.0]),
  }
  wal.append([record1]) catch {
    _ => ()
  }
  // Remove footer to simulate truncation
  let data = storage.read("truncated.wal") catch { _ => Bytes::new(0) }
  let w = @core.BinaryWriter::new()
  // Copy without footer (last 8 bytes)
  for i in 0..<(data.length() - 8) {
    w.push_byte(data[i])
  }
  storage.atomic_write("truncated.wal", w.concat())
  // Append should recover valid records
  let record2 : WalRecord = {
    record_type: WalRecordType::Upsert,
    id: @core.VectorId::from_int(2),
    attrs: None,
    vector: Some([3.0, 4.0]),
  }
  wal.append([record2]) catch {
    _ => ()
  }
  // Both records should be present
  let final_data = storage.read("truncated.wal") catch { _ => Bytes::new(0) }
  let records = decode_wal_records(final_data)
  inspect(records.length(), content="2")
}

///|
/// Test: CRUSH plan_rebalance returns empty for empty targets
test "crush/rebalance_empty_targets" {
  let targets = [CrushTarget::new("a"), CrushTarget::new("b")]
  let manifest : PlacementManifest = {
    base: "db",
    segments: [{ name: "db.pg0.part0", target_key: "a" }],
    crush: CrushMap::new(8, 1, targets),
    epoch: 1,
    commit_ts: 0L,
  }
  // Empty next map - should return no moves
  let empty_map = CrushMap::new(8, 1, [])
  let plans = plan_rebalance(manifest, empty_map)
  inspect(plans.length(), content="0")
}

///|
/// Test: parse_pg_from_name uses last .pg marker with digits
test "crush/parse_pg_last_marker" {
  // Test case: base name contains ".pg" (e.g., "archive.pg_backup")
  // Should parse PG 12 from the last ".pg12", not 0 from ".pg_backup"
  let targets = [CrushTarget::new("a"), CrushTarget::new("b")]
  let manifest : PlacementManifest = {
    base: "archive.pg_backup",
    segments: [{ name: "archive.pg_backup.pg12.part0", target_key: "a" }],
    crush: CrushMap::new(16, 1, targets),
    epoch: 1,
    commit_ts: 0L,
  }
  // Target for PG 12 should be computed correctly
  let next_map = CrushMap::new(16, 1, [CrushTarget::new("c")])
  let plans = plan_rebalance(manifest, next_map)
  // Should have one move (from "a" to "c")
  inspect(plans.length(), content="1")
  // The move should be for the segment with PG 12
  inspect(plans[0].name, content="archive.pg_backup.pg12.part0")
}

///|
/// Test: WAL JSON escapes all control characters
test "wal/json_control_chars" {
  let storage = MemoryStorage::new()
  let wal = WalRuntime::new(storage, "control.wal")
  // Create attrs with control characters in value
  let attrs = @core.empty_attrs()
  // String with backspace, form feed, and other control chars
  attrs.set("data", @core.String("a\u0008b\u000Cc\u0001d"))
  let record : WalRecord = {
    record_type: WalRecordType::Upsert,
    id: @core.VectorId::from_int(1),
    attrs: Some(attrs),
    vector: Some([1.0, 2.0]),
  }
  wal.append([record]) catch {
    _ => ()
  }
  // Read and decode - should not fail
  let data = storage.read("control.wal") catch { _ => Bytes::new(0) }
  let records = decode_wal_records(data)
  inspect(records.length(), content="1")
  // Verify attrs round-trip correctly
  match records[0].attrs {
    None => inspect(false, content="true")
    Some(decoded_attrs) =>
      match decoded_attrs.get("data") {
        Some(@core.String(s)) => inspect(s, content="a\u0008b\u000Cc\u0001d")
        _ => inspect(false, content="true")
      }
  }
}
