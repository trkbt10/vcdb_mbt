///|
/// Concatenate two byte buffers.
fn concat_bytes(a : Bytes, b : Bytes) -> Bytes {
  let w = @binary.BinaryWriter::new()
  w.push_bytes(a)
  w.push_bytes(b)
  w.concat()
}
