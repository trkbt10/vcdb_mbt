///|
test "lib/gateway_storage_read_propagates_missing_file" {
  let mut failed = false
  let _ = gateway_storage_read("missing", 0) catch {
    _ => {
      failed = true
      b""
    }
  }
  assert_true(failed)
}

// ── VectorId wire format contract tests ─────────────────────
//
// These tests are the SoT for the FFI wire format.
// If any of these fail, the JS side must be updated to match.

///|
/// Int64Id round-trip: encode → decode → same value
test "wire/int64_roundtrip" {
  let id = @types.Int64Id(42L)
  let wire = @types.VectorId::to_wire_bytes(id)
  assert_eq(wire.length(), 16)
  // Lower 8 bytes must be zero for Int64Id
  for i in 8..<16 {
    assert_eq(wire[i], b'\x00')
  }
  let decoded = @types.VectorId::from_wire_bytes(wire)
  assert_eq(decoded, Some(id))
}

///|
/// Int64Id with max value
test "wire/int64_max" {
  let id = @types.Int64Id(9223372036854775807L) // Int64::max_value
  let wire = @types.VectorId::to_wire_bytes(id)
  assert_eq(wire.length(), 16)
  let decoded = @types.VectorId::from_wire_bytes(wire)
  assert_eq(decoded, Some(id))
}

///|
/// Int64Id with negative value (signed)
test "wire/int64_negative" {
  let id = @types.Int64Id(-1L)
  let wire = @types.VectorId::to_wire_bytes(id)
  assert_eq(wire.length(), 16)
  // -1L in big-endian is 0xFF * 8
  for i in 0..<8 {
    assert_eq(wire[i], b'\xff')
  }
  // Lower 8 bytes must be zero
  for i in 8..<16 {
    assert_eq(wire[i], b'\x00')
  }
  let decoded = @types.VectorId::from_wire_bytes(wire)
  assert_eq(decoded, Some(id))
}

///|
/// Int64Id zero
test "wire/int64_zero" {
  let id = @types.Int64Id(0L)
  let wire = @types.VectorId::to_wire_bytes(id)
  // All bytes must be zero
  for i in 0..<16 {
    assert_eq(wire[i], b'\x00')
  }
  let decoded = @types.VectorId::from_wire_bytes(wire)
  assert_eq(decoded, Some(id))
}

///|
/// Bytes16Id round-trip via UUID string
test "wire/bytes16_roundtrip_uuid" {
  let uuid = "550e8400-e29b-41d4-a716-446655440000"
  let id = @types.VectorId::from_uuid_string(uuid).unwrap()
  let wire = @types.VectorId::to_wire_bytes(id)
  assert_eq(wire.length(), 16)
  let decoded = @types.VectorId::from_wire_bytes(wire)
  assert_eq(decoded, Some(id))
}

///|
/// Bytes16Id with non-zero lower bytes is decoded as Bytes16Id (not Int64Id)
test "wire/bytes16_not_confused_with_int64" {
  let uuid = "00000000-0000-0000-0000-000000000001"
  let id = @types.VectorId::from_uuid_string(uuid).unwrap()
  let wire = @types.VectorId::to_wire_bytes(id)
  // Lower 8 bytes have a non-zero byte → must decode as Bytes16Id
  let decoded = @types.VectorId::from_wire_bytes(wire)
  assert_eq(decoded, Some(id))
  match decoded {
    Some(@types.Bytes16Id(_)) => ()
    _ => abort("expected Bytes16Id")
  }
}

///|
/// Wrong length returns None
test "wire/invalid_length_returns_none" {
  assert_eq(@types.VectorId::from_wire_bytes(b""), None)
  assert_eq(@types.VectorId::from_wire_bytes(b"\x00\x01"), None)
  assert_eq(
    @types.VectorId::from_wire_bytes(Bytes::make(15, b'\x00')),
    None,
  )
  assert_eq(
    @types.VectorId::from_wire_bytes(Bytes::make(17, b'\x00')),
    None,
  )
}

///|
/// vcdb_add / vcdb_has / vcdb_get / vcdb_remove with Int64Id wire bytes
test "ffi/int64_add_has_get_remove" {
  let inst = vcdb_create(4)
  let id = @types.Int64Id(1L)
  let wire = @types.VectorId::to_wire_bytes(id)
  let vec = [1.0, 0.0, 0.0, 0.0]
  assert_eq(vcdb_add(inst, wire, vec), 0)
  assert_eq(vcdb_has(inst, wire), 1)
  let (got_vec, found) = vcdb_get(inst, wire)
  assert_eq(found, 1)
  assert_eq(got_vec.length(), 4)
  assert_eq(vcdb_remove(inst, wire), 1)
  assert_eq(vcdb_has(inst, wire), 0)
  vcdb_destroy(inst)
}

///|
/// Bytes16Id wire format: encode/decode round-trip is correct at the type level.
/// NOTE: vcdb_add with Bytes16Id is blocked by BPTreeAttrIndex::set_attrs
/// which calls VectorId::to_int64() and aborts on Bytes16Id.
/// This is a known limitation in core/attr/bptree.mbt that must be fixed
/// before Bytes16Id can be used in write operations.
test "ffi/bytes16_wire_roundtrip_only" {
  let uuid = "550e8400-e29b-41d4-a716-446655440000"
  let id = @types.VectorId::from_uuid_string(uuid).unwrap()
  let wire = @types.VectorId::to_wire_bytes(id)
  assert_eq(wire.length(), 16)
  let decoded = @types.VectorId::from_wire_bytes(wire)
  assert_eq(decoded, Some(id))
}

///|
/// vcdb_search returns wire-format IDs that decode back to original IDs
test "ffi/search_id_roundtrip" {
  let inst = vcdb_create(4)
  let id1 = @types.Int64Id(1L)
  let id2 = @types.Int64Id(2L)
  let w1 = @types.VectorId::to_wire_bytes(id1)
  let w2 = @types.VectorId::to_wire_bytes(id2)
  let _ = vcdb_add(inst, w1, [1.0, 0.0, 0.0, 0.0])
  let _ = vcdb_add(inst, w2, [0.0, 1.0, 0.0, 0.0])
  let results = vcdb_search(inst, [1.0, 0.0, 0.0, 0.0], 1)
  assert_eq(results.length(), 1)
  let (result_wire, _score) = results[0]
  assert_eq(result_wire.length(), 16)
  let decoded = @types.VectorId::from_wire_bytes(result_wire)
  assert_eq(decoded, Some(id1))
  vcdb_destroy(inst)
}

///|
/// vcdb_add duplicate returns -2
test "ffi/add_duplicate_returns_minus2" {
  let inst = vcdb_create(4)
  let wire = @types.VectorId::to_wire_bytes(@types.Int64Id(1L))
  assert_eq(vcdb_add(inst, wire, [1.0, 0.0, 0.0, 0.0]), 0)
  assert_eq(vcdb_add(inst, wire, [1.0, 0.0, 0.0, 0.0]), -2)
  vcdb_destroy(inst)
}

///|
/// Invalid wire bytes (wrong length) return error codes
test "ffi/invalid_wire_bytes_returns_error" {
  let inst = vcdb_create(4)
  let bad = b"\x00\x01"
  assert_eq(vcdb_add(inst, bad, [1.0, 0.0, 0.0, 0.0]), -1)
  assert_eq(vcdb_has(inst, bad), -1)
  assert_eq(vcdb_remove(inst, bad), -1)
  let (_, found) = vcdb_get(inst, bad)
  assert_eq(found, -1)
  vcdb_destroy(inst)
}

///|
/// crush_placement_group with Int64Id wire bytes
test "ffi/crush_placement_deterministic" {
  let wire = @types.VectorId::to_wire_bytes(@types.Int64Id(42L))
  let pg1 = crush_placement_group(wire, 16)
  let pg2 = crush_placement_group(wire, 16)
  assert_eq(pg1, pg2)
  assert_true(pg1 >= 0 && pg1 < 16)
}
