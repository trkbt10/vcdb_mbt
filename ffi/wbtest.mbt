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
