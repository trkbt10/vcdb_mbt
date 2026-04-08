///|
/// Execute `vcdb load`: read JSONL, route via CRUSH, upsert into sharded PersistentDBs.
pub async fn execute_load(matches : @argparse.Matches) -> Unit {
  let input_path = match get_value(matches, "input") {
    Some(it) => it
    None => {
      println("Error: Input JSONL path is required")
      return
    }
  }
  let output_dir = match get_value(matches, "output") {
    Some(it) => it
    None => {
      println("Error: Output directory is required")
      return
    }
  }
  let dim = get_int_value_or(matches, "dim", 1024)
  let shard_count = get_int_value_or(matches, "shards", 1)
  let collection_name = get_value_or(matches, "collection", "db")
  let metric = match get_value(matches, "metric") {
    Some(v) =>
      match parse_metric(v) {
        Some(m) => m
        None => {
          println("Error: Invalid metric: " + v)
          return
        }
      }
    None => @types.Cosine
  }
  let strategy = match get_value(matches, "strategy") {
    Some(v) =>
      match parse_strategy(v) {
        Some(s) => s
        None => {
          println("Error: Invalid strategy: " + v)
          return
        }
      }
    None => @types.Strategy::default_hnsw()
  }
  let crush = @placement.CrushMap::new(shard_count, 1, [])
  let shards : Array[
    @vcdb.PersistentDB[@storage.NativeFileStorage, @storage.NativeFileStorage],
  ] = []
  for i in 0..<shard_count {
    let shard_dir = output_dir + "/shard-" + i.to_string()
    let wal = @storage.NativeFileStorage::new(shard_dir)
    let snap = @storage.NativeFileStorage::new(shard_dir)
    shards.push(
      @vcdb.PersistentDB::init(
        wal, snap, "", collection_name, dim, 4096, metric=metric, strategy=strategy,
      ),
    )
  }
  let file = @async_fs.open(input_path, mode=ReadOnly) catch {
    e => {
      println("Error: Failed to open: " + e.to_string())
      return
    }
  }
  let file_size = file.size()
  let buf = FixedArray::make(64 * 1024, b'\x00')
  let mut position : Int64 = 0L
  let line_bytes : Array[Byte] = []
  let mut loaded = 0
  let mut errors = 0
  let timestamp = 0L
  while position < file_size {
    let n = file.read_at(buf, position~) catch {
      e => {
        file.close()
        println("Error: Read error: " + e.to_string())
        return
      }
    }
    if n == 0 {
      break
    }
    position = position + n.to_int64()
    for i in 0..<n {
      if buf[i] == b'\n' {
        if line_bytes.length() > 0 {
          let line = @codec.decode_utf8(Bytes::from_array(line_bytes))
          line_bytes.clear()
          if upsert_from_line(shards, crush, line, timestamp) {
            loaded += 1
          } else {
            errors += 1
          }
        }
      } else {
        line_bytes.push(buf[i])
      }
    }
  }
  file.close()
  if line_bytes.length() > 0 {
    let line = @codec.decode_utf8(Bytes::from_array(line_bytes))
    if upsert_from_line(shards, crush, line, timestamp) {
      loaded += 1
    } else {
      errors += 1
    }
  }
  for i in 0..<shard_count {
    shards[i].checkpoint() catch {
      e => {
        println(
          "Error: Checkpoint shard " + i.to_string() + " failed: " + e.to_string(),
        )
        return
      }
    }
  }
  let shard_info = @buffer.new()
  for i in 0..<shard_count {
    if i > 0 {
      shard_info.write_string(", ")
    }
    shard_info.write_string(
      "shard " + i.to_string() + ": " + shards[i].size().to_string(),
    )
  }
  println(
    "loaded=" + loaded.to_string() + " errors=" + errors.to_string() + " [" + shard_info
    .to_string() + "]",
  )
}

///|
async fn upsert_from_line(
  shards : Array[
    @vcdb.PersistentDB[@storage.NativeFileStorage, @storage.NativeFileStorage],
  ],
  crush : @placement.CrushMap,
  line : String,
  timestamp : Int64,
) -> Bool {
  let point = match @distributed.TransportPoint::from_jsonl(line) {
    Some(p) => p
    None => return false
  }
  let shard = @distributed.shard_for_id(point.id, crush)
  shards[shard].upsert([(point.id, point.vector, point.attrs)], timestamp) catch {
    _ => return false
  }
  true
}
