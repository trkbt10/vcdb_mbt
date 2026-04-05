// Whitebox tests for wal module

///|
fn run_async_blocking(f : async () -> Unit noraise) -> Unit = "%async.run"

///|
fn run_async_test(f : async () -> Unit) -> Unit {
  run_async_blocking(async fn() noraise {
    try f() catch {
      e => abort("async test failed: " + e.to_string())
    }
  })
}

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
  run_async_test(async fn() {
    let storage = @storage.MemoryStorage::new()
    let wal = AsyncWalRuntime::new(storage, "test.wal")
    let _ = wal.load()
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
    wal.append(records)
    // Replay into store
    let store = @store.CoreStore::new(3, @types.Dot)
    let count = wal.replay_into(store)
    inspect(count, content="2")
    inspect(store.size(), content="2")
    inspect(store.has(@types.VectorId::from_int(1)), content="true")
    inspect(store.has(@types.VectorId::from_int(2)), content="true")
  })
}

///|
test "wal/replay_remove" {
  run_async_test(async fn() {
    let storage = @storage.MemoryStorage::new()
    let wal = AsyncWalRuntime::new(storage, "test_remove.wal")
    let _ = wal.load()
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
    wal.append(records)
    let store = @store.CoreStore::new(2, @types.Dot)
    let count = wal.replay_into(store)
    inspect(count, content="3")
    // id=1 should be removed
    inspect(store.has(@types.VectorId::from_int(1)), content="false")
    inspect(store.has(@types.VectorId::from_int(2)), content="true")
  })
}

///|
test "wal/e2e_crud_replay" {
  run_async_test(async fn() {
    let storage = @storage.MemoryStorage::new()
    let wal = AsyncWalRuntime::new(storage, "e2e.wal")
    let _ = wal.load()
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
    wal.append(records)
    // Replay into a new store
    let store = @store.CoreStore::new(3, @types.Dot)
    let count = wal.replay_into(store)
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
  })
}

///|
test "wal/large_batch" {
  run_async_test(async fn() {
    let storage = @storage.MemoryStorage::new()
    let wal = AsyncWalRuntime::new(storage, "large.wal")
    let _ = wal.load()
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
    wal.append(records)
    // Replay
    let store = @store.CoreStore::new(3, @types.Dot)
    let count = wal.replay_into(store)
    inspect(count, content="100")
    inspect(store.size(), content="100")
    // Verify first and last
    inspect(store.has(@types.VectorId::from_int(1)), content="true")
    inspect(store.has(@types.VectorId::from_int(100)), content="true")
  })
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
  run_async_test(async fn() {
    let storage = @storage.MemoryStorage::new()
    let wal = AsyncWalRuntime::new(storage, "truncate.wal")
    let _ = wal.load()
    // Append some records
    let records = [
      WalRecord::upsert(
        @types.VectorId::from_int(1),
        [1.0],
        @types.empty_attrs(),
      ),
    ]
    wal.append(records)
    let before = storage.read("truncate.wal") catch { _ => Bytes::new(0) }
    inspect(before.length() > @codec.header_size, content="true") // Header + records
    // Truncate
    wal.truncate()
    // WAL should be reset to just header (12 bytes)
    let data = storage.read("truncate.wal") catch { _ => Bytes::new(0) }
    inspect(data.length(), content="12") // Just header
  })
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
  run_async_test(async fn() {
    let storage = @storage.MemoryStorage::new()
    // Write corrupted WAL file
    let corrupted = Bytes::from_array(
      [b'X', b'X', b'X', b'X', b'X', b'X', b'X', b'X'][:],
    )
    storage.write("corrupted.wal", corrupted)
    let wal = AsyncWalRuntime::new(storage, "corrupted.wal")
    let _ = wal.load()
    let store = @store.CoreStore::new(3, @types.Dot)
    let count = wal.replay_into(store)
    inspect(count, content="0")
  })
}

///|
test "wal/runtime_empty" {
  run_async_test(async fn() {
    let storage = @storage.MemoryStorage::new()
    let wal = AsyncWalRuntime::new(storage, "new.wal")
    let _ = wal.load()
    let store = @store.CoreStore::new(3, @types.Dot)
    let count = wal.replay_into(store)
    inspect(count, content="0")
  })
}

///|
test "wal/runtime_size_exists" {
  run_async_test(async fn() {
    let storage = @storage.MemoryStorage::new()
    let wal = AsyncWalRuntime::new(storage, "size.wal")
    let _ = wal.load()
    // Not exists yet
    inspect(wal.async_exists(), content="false")
    inspect(wal.byte_size(), content="0")
    // Append some records
    let records = [
      WalRecord::upsert(
        @types.VectorId::from_int(1),
        [1.0, 2.0],
        @types.empty_attrs(),
      ),
    ]
    wal.append(records)
    inspect(wal.async_exists(), content="true")
    // Check physical WAL size from storage
    let data = storage.read("size.wal") catch { _ => Bytes::new(0) }
    inspect(data.length() > 8, content="true") // At least header + record
  })
}

///|
test "wal/runtime_append_empty" {
  run_async_test(async fn() {
    let storage = @storage.MemoryStorage::new()
    let wal = AsyncWalRuntime::new(storage, "empty_append.wal")
    let _ = wal.load()
    // Append empty should not create file
    wal.append([])
    inspect(wal.async_exists(), content="false")
  })
}

///|
test "wal/runtime_setattrs_nonexistent" {
  run_async_test(async fn() {
    let storage = @storage.MemoryStorage::new()
    let wal = AsyncWalRuntime::new(storage, "setattrs.wal")
    let _ = wal.load()
    // SetAttrs for ID that doesn't exist in store
    let attrs = @types.empty_attrs()
    attrs.set("key", @types.String("value"))
    let records = [WalRecord::set_attrs(@types.VectorId::from_int(999), attrs)]
    wal.append(records)
    let store = @store.CoreStore::new(2, @types.Dot)
    let count = wal.replay_into(store)
    // SetAttrs increments count but doesn't create new vector
    inspect(count, content="1")
    inspect(store.size(), content="0")
  })
}

///|
test "wal/runtime_remove_nonexistent" {
  run_async_test(async fn() {
    let storage = @storage.MemoryStorage::new()
    let wal = AsyncWalRuntime::new(storage, "remove.wal")
    let _ = wal.load()
    // Remove ID that doesn't exist
    let records = [WalRecord::remove(@types.VectorId::from_int(999))]
    wal.append(records)
    let store = @store.CoreStore::new(2, @types.Dot)
    let count = wal.replay_into(store)
    inspect(count, content="1")
    inspect(store.size(), content="0")
  })
}
