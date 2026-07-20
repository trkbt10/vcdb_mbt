///|
/// Execute `vcdb dump`: read a snapshot file, print JSONL to stdout.
pub fn execute_dump(matches : @argparse.Matches) -> Unit {
  let path = match get_value(matches, "file") {
    Some(it) => it
    None => {
      println("Error: Snapshot file path is required")
      return
    }
  }
  let data = @fs.read_file_to_bytes(path) catch {
    @fs.IOError(msg) => {
      println("Error: Failed to read file: " + msg)
      return
    }
  }
  let db = @vcdb.VectorDB::deserialize(data)
  let lines = db.export_jsonl()
  for line in lines {
    println(line)
  }
}
