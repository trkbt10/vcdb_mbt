// Whitebox tests for wal module

///|
test "wal/record_roundtrip" {
  let attrs = @types.empty_attrs()
  attrs.set("key", @types.String("value"))
  let record = WalRecord::upsert(
    @types.VectorId::from_int(42),
    [1.0, 2.0, 3.0],
    attrs,
  )
  let encoded = encode_wal_record(record)
  let reader = @binary.BinaryReader::new(encoded)
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
test "wal/segment_encoding" {
  let records = [
    WalRecord::upsert(@types.VectorId::from_int(1), [1.0], @types.empty_attrs()),
    WalRecord::remove(@types.VectorId::from_int(2)),
  ]
  let segment = encode_wal_segment(records)
  // Should have header (8) + records + footer (8)
  inspect(segment.length() > 16, content="true")
  // Verify checksum
  inspect(verify_wal_checksum(segment), content="true")
}

///|
test "wal/decode_records" {
  let records = [
    WalRecord::upsert(
      @types.VectorId::from_int(1),
      [1.0, 2.0],
      @types.empty_attrs(),
    ),
    WalRecord::set_attrs(@types.VectorId::from_int(2), @types.empty_attrs()),
    WalRecord::remove(@types.VectorId::from_int(3)),
  ]
  let segment = encode_wal_segment(records)
  let decoded = decode_wal_records(segment)
  inspect(decoded.length(), content="3")
}

///|
test "wal/replay" {
  let storage = @storage.MemoryStorage::new()
  let wal = WalRuntime::new(storage, "test.wal")
  // Create WAL records
  let records = [
    WalRecord::upsert(
      @types.VectorId::from_int(1),
      [1.0, 0.0, 0.0],
      @types.empty_attrs(),
    ),
    WalRecord::upsert(
      @types.VectorId::from_int(2),
      [0.0, 1.0, 0.0],
      @types.empty_attrs(),
    ),
  ]
  wal.append(records) catch {
    _ => ()
  }
  // Replay into store
  let store = @store.CoreStore::new(3, @types.Dot)
  let count = wal.replay_into(store) catch { _ => 0 }
  inspect(count, content="2")
  inspect(store.size(), content="2")
  inspect(store.has(@types.VectorId::from_int(1)), content="true")
  inspect(store.has(@types.VectorId::from_int(2)), content="true")
}

///|
test "wal/replay_remove" {
  let storage = @storage.MemoryStorage::new()
  let wal = WalRuntime::new(storage, "test_remove.wal")
  let records = [
    WalRecord::upsert(
      @types.VectorId::from_int(1),
      [1.0, 0.0],
      @types.empty_attrs(),
    ),
    WalRecord::upsert(
      @types.VectorId::from_int(2),
      [0.0, 1.0],
      @types.empty_attrs(),
    ),
    WalRecord::remove(@types.VectorId::from_int(1)),
  ]
  wal.append(records) catch {
    _ => ()
  }
  let store = @store.CoreStore::new(2, @types.Dot)
  let count = wal.replay_into(store) catch { _ => 0 }
  inspect(count, content="3")
  // id=1 should be removed
  inspect(store.has(@types.VectorId::from_int(1)), content="false")
  inspect(store.has(@types.VectorId::from_int(2)), content="true")
}

///|
test "wal/e2e_crud_replay" {
  let storage = @storage.MemoryStorage::new()
  let wal = WalRuntime::new(storage, "e2e.wal")
  // Simulate CRUD operations
  let attrs1 = @types.empty_attrs()
  attrs1.set("tag", @types.String("A"))
  let attrs2 = @types.empty_attrs()
  attrs2.set("tag", @types.String("B"))
  let records = [
    WalRecord::upsert(@types.VectorId::from_int(1), [1.0, 0.0, 0.0], attrs1),
    WalRecord::upsert(@types.VectorId::from_int(2), [0.0, 1.0, 0.0], attrs2),
    WalRecord::upsert(
      @types.VectorId::from_int(3),
      [0.0, 0.0, 1.0],
      @types.empty_attrs(),
    ),
    WalRecord::set_attrs(
      @types.VectorId::from_int(3),
      {
        let a = @types.empty_attrs()
        a.set("tag", @types.String("C"))
        a
      },
    ),
    WalRecord::remove(@types.VectorId::from_int(2)),
  ]
  wal.append(records) catch {
    _ => ()
  }
  // Replay into a new store
  let store = @store.CoreStore::new(3, @types.Dot)
  let count = wal.replay_into(store) catch { _ => 0 }
  inspect(count, content="5")
  // Verify state after replay
  inspect(store.size(), content="2") // 3 added - 1 removed
  inspect(store.has(@types.VectorId::from_int(1)), content="true")
  inspect(store.has(@types.VectorId::from_int(2)), content="false") // removed
  inspect(store.has(@types.VectorId::from_int(3)), content="true")
  // Verify attrs were updated
  let record3 = store.get(@types.VectorId::from_int(3))
  match record3 {
    Some(r) =>
      match r.attrs.get("tag") {
        Some(@types.String(s)) => inspect(s, content="C")
        _ => inspect(false, content="true")
      }
    None => inspect(false, content="true")
  }
}

///|
test "wal/large_batch" {
  let storage = @storage.MemoryStorage::new()
  let wal = WalRuntime::new(storage, "large.wal")
  // Add 100 vectors
  let records : Array[WalRecord] = []
  for i in 1..<=100 {
    let attrs = @types.empty_attrs()
    attrs.set("index", @types.Int(i.to_int64()))
    records.push(
      WalRecord::upsert(
        @types.VectorId::from_int(i),
        [i.to_double() / 100.0, 1.0 - i.to_double() / 100.0, 0.0],
        attrs,
      ),
    )
  }
  wal.append(records) catch {
    _ => ()
  }
  // Replay
  let store = @store.CoreStore::new(3, @types.Dot)
  let count = wal.replay_into(store) catch { _ => 0 }
  inspect(count, content="100")
  inspect(store.size(), content="100")
  // Verify first and last
  inspect(store.has(@types.VectorId::from_int(1)), content="true")
  inspect(store.has(@types.VectorId::from_int(100)), content="true")
}

///|
test "wal/attr_types_roundtrip" {
  let attrs = @types.empty_attrs()
  attrs.set("string_val", @types.String("hello world"))
  attrs.set("int_val", @types.Int(42L))
  attrs.set("float_val", @types.Float(3.14159))
  attrs.set("bool_val", @types.Bool(true))
  attrs.set("null_val", @types.Null)
  let record = WalRecord::upsert(
    @types.VectorId::from_int(999),
    [1.0, 2.0, 3.0],
    attrs,
  )
  let encoded = encode_wal_record(record)
  let reader = @binary.BinaryReader::new(encoded)
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
            Some(@types.String(s)) => inspect(s, content="hello world")
            _ => inspect(false, content="true")
          }
          match a.get("int_val") {
            Some(@types.Int(n)) => inspect(n, content="42")
            _ => inspect(false, content="true")
          }
          match a.get("bool_val") {
            Some(@types.Bool(b)) => inspect(b, content="true")
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
test "wal/set_attrs_record" {
  let attrs = @types.empty_attrs()
  attrs.set("key", @types.String("value"))
  let record = WalRecord::set_attrs(@types.VectorId::from_int(100), attrs)
  let encoded = encode_wal_record(record)
  let reader = @binary.BinaryReader::new(encoded)
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
test "wal/remove_record" {
  let record = WalRecord::remove(@types.VectorId::from_int(50))
  let encoded = encode_wal_record(record)
  let reader = @binary.BinaryReader::new(encoded)
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
test "wal/corrupted_checksum" {
  let records = [
    WalRecord::upsert(@types.VectorId::from_int(1), [1.0], @types.empty_attrs()),
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
test "wal/empty_attrs" {
  let record = WalRecord::upsert(
    @types.VectorId::from_int(1),
    [1.0, 2.0],
    @types.empty_attrs(),
  )
  let encoded = encode_wal_record(record)
  let reader = @binary.BinaryReader::new(encoded)
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
test "wal/truncate" {
  let storage = @storage.MemoryStorage::new()
  let wal = WalRuntime::new(storage, "truncate.wal")
  // Append some records
  let records = [
    WalRecord::upsert(@types.VectorId::from_int(1), [1.0], @types.empty_attrs()),
  ]
  wal.append(records) catch {
    _ => ()
  }
  let before = storage.read("truncate.wal") catch { _ => Bytes::new(0) }
  inspect(before.length() > @codec.header_size, content="true") // Header + records
  // Truncate
  wal.truncate()
  // WAL should be reset to just header (12 bytes)
  let data = storage.read("truncate.wal") catch { _ => Bytes::new(0) }
  inspect(data.length(), content="12") // Just header
}

///|
test "wal/json_escape_special" {
  let attrs = @types.empty_attrs()
  attrs.set("text", @types.String("hello\nworld\ttab\"quote\\backslash"))
  attrs.set("cr", @types.String("line\rwith\rCR"))
  let record = WalRecord::upsert(@types.VectorId::from_int(1), [1.0], attrs)
  let encoded = encode_wal_record(record)
  let reader = @binary.BinaryReader::new(encoded)
  let decoded = decode_wal_record(reader)
  match decoded {
    Some(r) =>
      match r.attrs {
        Some(a) =>
          match a.get("text") {
            Some(@types.String(s)) =>
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
test "wal/attrs_float" {
  let attrs = @types.empty_attrs()
  attrs.set("pi", @types.Float(3.14159))
  attrs.set("neg", @types.Float(-2.5))
  let record = WalRecord::set_attrs(@types.VectorId::from_int(1), attrs)
  let encoded = encode_wal_record(record)
  let reader = @binary.BinaryReader::new(encoded)
  let decoded = decode_wal_record(reader)
  match decoded {
    Some(r) =>
      match r.attrs {
        Some(a) =>
          match a.get("pi") {
            Some(@types.Float(f)) =>
              inspect((f - 3.14159).abs() < 0.001, content="true")
            _ => inspect(false, content="true")
          }
        None => inspect(false, content="true")
      }
    None => inspect(false, content="true")
  }
}

///|
test "wal/attrs_bool" {
  let attrs = @types.empty_attrs()
  attrs.set("active", @types.Bool(true))
  attrs.set("deleted", @types.Bool(false))
  let record = WalRecord::set_attrs(@types.VectorId::from_int(1), attrs)
  let encoded = encode_wal_record(record)
  let reader = @binary.BinaryReader::new(encoded)
  let decoded = decode_wal_record(reader)
  match decoded {
    Some(r) =>
      match r.attrs {
        Some(a) => {
          match a.get("active") {
            Some(@types.Bool(b)) => inspect(b, content="true")
            _ => inspect(false, content="true")
          }
          match a.get("deleted") {
            Some(@types.Bool(b)) => inspect(b, content="false")
            _ => inspect(false, content="true")
          }
        }
        None => inspect(false, content="true")
      }
    None => inspect(false, content="true")
  }
}

///|
test "wal/decode_invalid_header" {
  // Invalid magic number
  let bad_data = Bytes::from_array(
    [b'B', b'A', b'D', b'!', b'\x02', b'\x00', b'\x00', b'\x00'][:],
  )
  let records = decode_wal_records(bad_data)
  inspect(records.length(), content="0")
}

///|
test "wal/decode_short_data" {
  let short_data = Bytes::from_array([b'V', b'L', b'W'][:])
  let records = decode_wal_records(short_data)
  inspect(records.length(), content="0")
}

///|
test "wal/verify_header" {
  // Valid header
  let valid = encode_wal_header()
  let reader = @binary.BinaryReader::new(valid)
  inspect(verify_wal_header(reader), content="true")
  // Invalid magic
  let invalid = Bytes::from_array(
    [b'X', b'X', b'X', b'X', b'\x02', b'\x00', b'\x00', b'\x00'][:],
  )
  let reader2 = @binary.BinaryReader::new(invalid)
  inspect(verify_wal_header(reader2), content="false")
}

///|
test "wal/segment_no_footer" {
  // Create segment with only header (8 bytes)
  let header = encode_wal_header()
  // Header-only WAL is valid (used after truncate)
  inspect(verify_wal_checksum(header), content="true")
  // Create larger segment without footer
  let w = @binary.BinaryWriter::new()
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
test "wal/decode_short_record" {
  // Create valid header but truncated record
  let w = @binary.BinaryWriter::new()
  w.push_bytes(encode_wal_header())
  w.push_byte(b'\x01') // Record type
  w.push_byte(b'\x00') // Reserved
  // Missing rest of record
  let data = w.concat()
  let records = decode_wal_records(data)
  inspect(records.length(), content="0")
}

///|
test "wal/runtime_corrupted" {
  let storage = @storage.MemoryStorage::new()
  // Write corrupted WAL file
  let corrupted = Bytes::from_array(
    [b'X', b'X', b'X', b'X', b'X', b'X', b'X', b'X'][:],
  )
  storage.write("corrupted.wal", corrupted)
  let wal = WalRuntime::new(storage, "corrupted.wal")
  let store = @store.CoreStore::new(3, @types.Dot)
  let count = wal.replay_into(store) catch { _ => 0 }
  inspect(count, content="0")
}

///|
test "wal/runtime_empty" {
  let storage = @storage.MemoryStorage::new()
  let wal = WalRuntime::new(storage, "new.wal")
  let store = @store.CoreStore::new(3, @types.Dot)
  let count = wal.replay_into(store) catch { _ => 0 }
  inspect(count, content="0")
}

///|
test "wal/runtime_size_exists" {
  let storage = @storage.MemoryStorage::new()
  let wal = WalRuntime::new(storage, "size.wal")
  // Not exists yet
  inspect(wal.exists(), content="false")
  inspect(wal.size(), content="0")
  // Append some records
  let records = [
    WalRecord::upsert(
      @types.VectorId::from_int(1),
      [1.0, 2.0],
      @types.empty_attrs(),
    ),
  ]
  wal.append(records) catch {
    _ => ()
  }
  inspect(wal.exists(), content="true")
  inspect(wal.size() > 8, content="true") // At least header + record
}

///|
test "wal/runtime_append_empty" {
  let storage = @storage.MemoryStorage::new()
  let wal = WalRuntime::new(storage, "empty_append.wal")
  // Append empty should not create file
  wal.append([]) catch {
    _ => ()
  }
  inspect(wal.exists(), content="false")
}

///|
test "wal/runtime_setattrs_nonexistent" {
  let storage = @storage.MemoryStorage::new()
  let wal = WalRuntime::new(storage, "setattrs.wal")
  // SetAttrs for ID that doesn't exist in store
  let attrs = @types.empty_attrs()
  attrs.set("key", @types.String("value"))
  let records = [WalRecord::set_attrs(@types.VectorId::from_int(999), attrs)]
  wal.append(records) catch {
    _ => ()
  }
  let store = @store.CoreStore::new(2, @types.Dot)
  let count = wal.replay_into(store) catch { _ => 0 }
  // SetAttrs increments count but doesn't create new vector
  inspect(count, content="1")
  inspect(store.size(), content="0")
}

///|
test "wal/runtime_remove_nonexistent" {
  let storage = @storage.MemoryStorage::new()
  let wal = WalRuntime::new(storage, "remove.wal")
  // Remove ID that doesn't exist
  let records = [WalRecord::remove(@types.VectorId::from_int(999))]
  wal.append(records) catch {
    _ => ()
  }
  let store = @store.CoreStore::new(2, @types.Dot)
  let count = wal.replay_into(store) catch { _ => 0 }
  inspect(count, content="1")
  inspect(store.size(), content="0")
}

///|
test "wal/runtime_append_existing" {
  let storage = @storage.MemoryStorage::new()
  let wal = WalRuntime::new(storage, "append.wal")
  // First append
  let records1 = [
    WalRecord::upsert(@types.VectorId::from_int(1), [1.0], @types.empty_attrs()),
  ]
  wal.append(records1) catch {
    _ => ()
  }
  let size1 = wal.size()
  // Second append
  let records2 = [
    WalRecord::upsert(@types.VectorId::from_int(2), [2.0], @types.empty_attrs()),
  ]
  wal.append(records2) catch {
    _ => ()
  }
  let size2 = wal.size()
  // Should have grown
  inspect(size2 > size1, content="true")
  // Replay should have 2 vectors
  let store = @store.CoreStore::new(1, @types.Dot)
  let count = wal.replay_into(store) catch { _ => 0 }
  inspect(count, content="2")
  inspect(store.size(), content="2")
}

///|
test "wal/upsert_no_attrs" {
  let storage = @storage.MemoryStorage::new()
  let _wal = WalRuntime::new(storage, "no_attrs.wal")
  // Create record manually without attrs
  let record : WalRecord = {
    record_type: WalRecordType::Upsert,
    id: @types.VectorId::from_int(1),
    attrs: None,
    vector: Some([1.0, 2.0]),
    timestamp: 0L,
  }
  let encoded = encode_wal_record(record)
  // Should still encode/decode
  let reader = @binary.BinaryReader::new(encoded)
  let decoded = decode_wal_record(reader)
  inspect(decoded is Some(_), content="true")
}

///|
test "wal/utf8_multibyte" {
  let attrs = @types.empty_attrs()
  attrs.set("emoji", @types.String("hello 👋"))
  attrs.set("japanese", @types.String("こんにちは"))
  attrs.set("mixed", @types.String("abc日本語123"))
  let record = WalRecord::upsert(@types.VectorId::from_int(1), [1.0], attrs)
  let encoded = encode_wal_record(record)
  let reader = @binary.BinaryReader::new(encoded)
  let decoded = decode_wal_record(reader)
  match decoded {
    Some(r) =>
      match r.attrs {
        Some(a) =>
          match a.get("mixed") {
            Some(@types.String(s)) => inspect(s.length() > 0, content="true")
            _ => inspect(false, content="true")
          }
        None => inspect(false, content="true")
      }
    None => inspect(false, content="true")
  }
}

///|
test "wal/attrs_negative" {
  let attrs = @types.empty_attrs()
  attrs.set("neg_int", @types.Int(-42L))
  attrs.set("neg_float", @types.Float(-3.14))
  let record = WalRecord::set_attrs(@types.VectorId::from_int(1), attrs)
  let encoded = encode_wal_record(record)
  let reader = @binary.BinaryReader::new(encoded)
  let decoded = decode_wal_record(reader)
  match decoded {
    Some(r) =>
      match r.attrs {
        Some(a) =>
          match a.get("neg_int") {
            Some(@types.Int(n)) => inspect(n, content="-42")
            _ => inspect(false, content="true")
          }
        None => inspect(false, content="true")
      }
    None => inspect(false, content="true")
  }
}

///|
test "wal/segment_mixed_types" {
  let records = [
    WalRecord::upsert(
      @types.VectorId::from_int(1),
      [1.0, 2.0],
      @types.empty_attrs(),
    ),
    WalRecord::set_attrs(
      @types.VectorId::from_int(1),
      {
        let a = @types.empty_attrs()
        a.set("key", @types.String("value"))
        a
      },
    ),
    WalRecord::remove(@types.VectorId::from_int(2)),
  ]
  let segment = encode_wal_segment(records)
  let decoded = decode_wal_records(segment)
  inspect(decoded.length(), content="3")
  inspect(decoded[0].record_type == WalRecordType::Upsert, content="true")
  inspect(decoded[1].record_type == WalRecordType::SetAttrs, content="true")
  inspect(decoded[2].record_type == WalRecordType::Remove, content="true")
}

///|
test "wal/large_int64_ids" {
  // Test with IDs that exceed 32-bit range
  let large_id = @types.VectorId(0x1_0000_0001L) // 4294967297, larger than u32 max
  let negative_id = @types.VectorId(-1L)
  let max_id = @types.VectorId(9223372036854775807L) // Int64 max
  let record1 = WalRecord::upsert(large_id, [1.0], @types.empty_attrs())
  let record2 = WalRecord::remove(negative_id)
  let record3 = WalRecord::set_attrs(max_id, @types.empty_attrs())
  // Encode and decode
  let encoded1 = encode_wal_record(record1)
  let decoded1 = decode_wal_record(@binary.BinaryReader::new(encoded1))
  match decoded1 {
    Some(r) => inspect(r.id.to_int64(), content="4294967297")
    None => inspect(false, content="true")
  }
  let encoded2 = encode_wal_record(record2)
  let decoded2 = decode_wal_record(@binary.BinaryReader::new(encoded2))
  match decoded2 {
    Some(r) => inspect(r.id.to_int64(), content="-1")
    None => inspect(false, content="true")
  }
  let encoded3 = encode_wal_record(record3)
  let decoded3 = decode_wal_record(@binary.BinaryReader::new(encoded3))
  match decoded3 {
    Some(r) => inspect(r.id.to_int64(), content="9223372036854775807")
    None => inspect(false, content="true")
  }
}

///|
test "wal/replay_large_ids" {
  let storage = @storage.MemoryStorage::new()
  let wal = WalRuntime::new(storage, "large_ids.wal")
  let large_id = @types.VectorId(0x1_0000_0001L)
  let records = [
    WalRecord::upsert(large_id, [1.0, 2.0, 3.0], @types.empty_attrs()),
  ]
  wal.append(records) catch {
    _ => ()
  }
  let store = @store.CoreStore::new(3, @types.Dot)
  let count = wal.replay_into(store) catch { _ => 0 }
  inspect(count, content="1")
  inspect(store.has(large_id), content="true")
}

///|
test "wal/truncated_record" {
  // Create a valid WAL segment
  let attrs = @types.empty_attrs()
  attrs.set("key", @types.String("value"))
  let record : WalRecord = {
    record_type: WalRecordType::Upsert,
    id: @types.VectorId::from_int(1),
    attrs: Some(attrs),
    vector: Some([1.0, 2.0, 3.0]),
    timestamp: 0L,
  }
  let full_segment = encode_wal_segment([record])
  // Truncate in the middle of the record body - copy first half
  let truncate_len = full_segment.length() / 2
  let w = @binary.BinaryWriter::new()
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
test "wal/corrupted_checksum_rejected" {
  let storage = @storage.MemoryStorage::new()
  let record : WalRecord = {
    record_type: WalRecordType::Upsert,
    id: @types.VectorId::from_int(1),
    attrs: None,
    vector: Some([1.0, 2.0]),
    timestamp: 0L,
  }
  let segment = encode_wal_segment([record])
  // Corrupt a byte in the body (before footer) - flip bit at position 10
  let w = @binary.BinaryWriter::new()
  for i in 0..<segment.length() {
    if i == 10 {
      w.push_byte((segment[i].to_int() ^ 0xFF).to_byte())
    } else {
      w.push_byte(segment[i])
    }
  }
  let corrupted = w.concat()
  storage.atomic_write("test.wal", corrupted)
  // Replay returns 0 records — corrupted WAL is silently skipped
  let wal = WalRuntime::new(storage, "test.wal")
  let store = @store.CoreStore::new(2, @types.Cosine)
  let applied = wal.replay_into(store) catch { _ => -1 }
  inspect(applied, content="0")
  inspect(store.size(), content="0")
}

///|
test "wal/invalid_attrs_len" {
  // Manually create a record with impossibly large attrs_len
  let w = @binary.BinaryWriter::new()
  // Header (12 bytes)
  w.push_bytes(encode_wal_header())
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
test "wal/replay_after_truncate" {
  let storage = @storage.MemoryStorage::new()
  let wal = WalRuntime::new(storage, "truncate.wal")
  // Append some records
  let record : WalRecord = {
    record_type: WalRecordType::Upsert,
    id: @types.VectorId::from_int(1),
    attrs: None,
    vector: Some([1.0, 2.0]),
    timestamp: 0L,
  }
  wal.append([record]) catch {
    _ => ()
  }
  // Truncate to header-only
  wal.truncate()
  // Replay should succeed with 0 records (not raise error)
  let store = @store.CoreStore::new(2, @types.Cosine)
  let applied = wal.replay_into(store) catch { _ => -1 }
  inspect(applied, content="0")
}

///|
test "wal/json_exponent_notation" {
  // Create attrs with a small float that serializes to exponent form
  let attrs = @types.empty_attrs()
  let tiny_val = 0.0000001 // 1e-7
  attrs.set("tiny", @types.Float(tiny_val))
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
            @types.Float(f) => inspect(f < 0.000001 && f > 0.0, content="true")
            _ => inspect(false, content="true") // Should be Float, not Null
          }
      }
  }
}

///|
test "wal/reject_non_aligned_vector" {
  let w = @binary.BinaryWriter::new()
  // Header (12 bytes)
  w.push_bytes(encode_wal_header())
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
test "wal/append_writes_footer" {
  let storage = @storage.MemoryStorage::new()
  let wal = WalRuntime::new(storage, "footer.wal")
  let record : WalRecord = {
    record_type: WalRecordType::Upsert,
    id: @types.VectorId::from_int(1),
    attrs: None,
    vector: Some([1.0, 2.0]),
    timestamp: 0L,
  }
  wal.append([record]) catch {
    _ => ()
  }
  // Read and verify footer is present
  let data = storage.read("footer.wal") catch { _ => Bytes::new(0) }
  // Check footer magic at end
  inspect(data.length() >= 16, content="true")
  let footer_start = data.length() - 8
  let r = @binary.BinaryReader::new(data)
  let _ = r.read_bytes(footer_start)
  let footer_magic = r.read_u32()
  inspect(footer_magic == wal_footer_magic, content="true")
  // Verify checksum
  inspect(verify_wal_checksum(data), content="true")
}

///|
test "wal/append_reinit_invalid_header" {
  let storage = @storage.MemoryStorage::new()
  // Write garbage to WAL file (no valid header)
  let garbage = Bytes::new(4)
  storage.atomic_write("invalid.wal", garbage)
  // Append should detect invalid header and start fresh
  let wal = WalRuntime::new(storage, "invalid.wal")
  let record : WalRecord = {
    record_type: WalRecordType::Upsert,
    id: @types.VectorId::from_int(1),
    attrs: None,
    vector: Some([1.0, 2.0]),
    timestamp: 0L,
  }
  wal.append([record]) catch {
    _ => ()
  }
  // Read and verify header is valid now
  let data = storage.read("invalid.wal") catch { _ => Bytes::new(0) }
  let r = @binary.BinaryReader::new(data)
  inspect(verify_wal_header(r), content="true")
  // Should be able to decode the record
  let records = decode_wal_records(data)
  inspect(records.length(), content="1")
}

///|
test "wal/append_rejects_corrupted_checksum" {
  let storage = @storage.MemoryStorage::new()
  // Create valid WAL first
  let wal = WalRuntime::new(storage, "corrupt.wal")
  let record1 : WalRecord = {
    record_type: WalRecordType::Upsert,
    id: @types.VectorId::from_int(1),
    attrs: None,
    vector: Some([1.0, 2.0]),
    timestamp: 0L,
  }
  wal.append([record1]) catch {
    _ => ()
  }
  // Corrupt the body (flip byte in middle, before footer)
  let data = storage.read("corrupt.wal") catch { _ => Bytes::new(0) }
  let w = @binary.BinaryWriter::new()
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
    id: @types.VectorId::from_int(2),
    attrs: None,
    vector: Some([3.0, 4.0]),
    timestamp: 0L,
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
test "wal/replay_rejects_invalid_header" {
  let storage = @storage.MemoryStorage::new()
  let garbage = Bytes::new(20) // >= 16 bytes but not a WAL
  storage.atomic_write("garbage.wal", garbage)
  let wal = WalRuntime::new(storage, "garbage.wal")
  let store = @store.CoreStore::new(2, @types.Cosine)
  // Invalid header → replay returns 0 (no records applied, no crash)
  let applied = wal.replay_into(store) catch { _ => -1 }
  inspect(applied, content="0")
  inspect(store.size(), content="0")
}

///|
test "wal/append_truncated_tail" {
  let storage = @storage.MemoryStorage::new()
  // Create valid WAL first
  let wal = WalRuntime::new(storage, "truncated.wal")
  let record1 : WalRecord = {
    record_type: WalRecordType::Upsert,
    id: @types.VectorId::from_int(1),
    attrs: None,
    vector: Some([1.0, 2.0]),
    timestamp: 0L,
  }
  wal.append([record1]) catch {
    _ => ()
  }
  // Remove footer to simulate truncation
  let data = storage.read("truncated.wal") catch { _ => Bytes::new(0) }
  let w = @binary.BinaryWriter::new()
  // Copy without footer (last 8 bytes)
  for i in 0..<(data.length() - 8) {
    w.push_byte(data[i])
  }
  storage.atomic_write("truncated.wal", w.concat())
  // Append should recover valid records
  let record2 : WalRecord = {
    record_type: WalRecordType::Upsert,
    id: @types.VectorId::from_int(2),
    attrs: None,
    vector: Some([3.0, 4.0]),
    timestamp: 0L,
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
test "wal/json_control_chars" {
  let storage = @storage.MemoryStorage::new()
  let wal = WalRuntime::new(storage, "control.wal")
  // Create attrs with control characters in value
  let attrs = @types.empty_attrs()
  // String with backspace, form feed, and other control chars
  attrs.set("data", @types.String("a\u0008b\u000Cc\u0001d"))
  let record : WalRecord = {
    record_type: WalRecordType::Upsert,
    id: @types.VectorId::from_int(1),
    attrs: Some(attrs),
    vector: Some([1.0, 2.0]),
    timestamp: 0L,
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
        Some(@types.String(s)) => inspect(s, content="a\u0008b\u000Cc\u0001d")
        _ => inspect(false, content="true")
      }
  }
}

// =============================================================================
// Coverage improvement tests - index_file.mbt
// =============================================================================
