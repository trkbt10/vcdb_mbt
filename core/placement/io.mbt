///|
/// Distributed Storage Integration
/// Provides save/open operations using CRUSH placement for distributed storage

///|
/// Segmentation options
pub struct SegmentOptions {
  base_name : String
  crush : CrushMap
  segmented : Bool // Enable multi-part segments
  segment_bytes : Int // Max bytes per segment (default 64MB)
}

///|
/// Default segment options
pub fn SegmentOptions::default(
  base_name : String,
  crush : CrushMap,
) -> SegmentOptions {
  { base_name, crush, segmented: false, segment_bytes: 64 * 1024 * 1024 }
}

///|
/// Create segment options with segmentation enabled and custom size limit
pub fn SegmentOptions::segmented(
  base_name : String,
  crush : CrushMap,
  segment_bytes : Int,
) -> SegmentOptions {
  { base_name, crush, segmented: true, segment_bytes }
}

///|
/// Result of writing segments
pub struct SegmentResult {
  entries : Array[@segment.IndexEntry]
  manifest : PlacementManifest
  dim : Int
  count : Int
}

///|
/// Internal: Segment state during writing
priv struct SegState {
  mut writer : @segment.SegmentWriter
  mut size : Int
  mut part : Int
  target_key : String
}

///|
/// Write vectors to segments using CRUSH placement
/// Returns index entries and manifest for index building
pub fn[S : @storage.Storage] write_segments_from_store(
  store : @store.CoreStore,
  opts : SegmentOptions,
  storages : Map[String, S],
) -> SegmentResult raise @storage.IOError {
  let base = opts.base_name
  let seg_limit = if opts.segment_bytes > 0 {
    opts.segment_bytes
  } else {
    64 * 1024 * 1024
  }

  // Track writers per placement group
  let writers : Map[Int, SegState] = {}
  let entries : Array[@segment.IndexEntry] = []
  let dim = store.dim
  let count = store.size()

  // Process each vector
  for i in 0..<count {
    let id = store.ids[i]
    let result = crush_locate(id, opts.crush)
    let pg = result.pg
    let target_key = first_string_or(result.primaries, "local")

    // Get or create segment writer for this PG
    let seg = match writers.get(pg) {
      Some(s) => s
      None => {
        let name = "\{base}.pg\{pg}.part0"
        let s : SegState = {
          writer: @segment.SegmentWriter::new(name),
          size: 8,
          part: 0,
          target_key,
        }
        writers.set(pg, s)
        s
      }
    }

    // Get vector data
    let vector : Array[Double] = []
    let base_idx = i * dim
    for j in 0..<dim {
      vector.push(store.data[base_idx + j])
    }
    let attrs = store.attrs[i]

    // Estimate record size
    let attrs_size = estimate_attrs_size(attrs)
    let rec_size = 16 + attrs_size + vector.length() * 4

    // Check if we need a new segment part
    if opts.segmented && seg.size + rec_size > seg_limit {
      // Flush current segment
      let seg_data = seg.writer.to_bytes()
      let storage = require_storage(storages, seg.target_key)
      storage.atomic_write(
        seg.writer.get_name() + @codec.ext_segment,
        seg_data,
        @storage.Data,
      )

      // Start new part
      seg.part = seg.part + 1
      let new_name = "\{base}.pg\{pg}.part\{seg.part}"
      seg.writer = @segment.SegmentWriter::new(new_name)
      seg.size = 8
    }

    // Append record
    let ptr = seg.writer.append(id, vector, attrs)
    seg.size = seg.size + ptr.length
    entries.push({ id, ptr })
  }

  // Flush all remaining segments
  let segment_entries : Array[SegmentEntry] = []
  for pg in writers.keys() {
    match writers.get(pg) {
      None => continue
      Some(seg) => {
        let seg_data = seg.writer.to_bytes()
        let storage = require_storage(storages, seg.target_key)
        storage.atomic_write(
          seg.writer.get_name() + @codec.ext_segment,
          seg_data,
          @storage.Data,
        )
        segment_entries.push({
          name: seg.writer.get_name(),
          target_key: seg.target_key,
        })
      }
    }
  }

  let manifest : PlacementManifest = {
    base,
    segments: segment_entries,
    crush: opts.crush,
    epoch: 0,
    commit_ts: 0L,
  }

  { entries, manifest, dim, count }
}

///|
/// Estimate attrs JSON size
fn estimate_attrs_size(attrs : @types.Attrs) -> Int {
  let mut size = 2 // {}
  for key in attrs.keys() {
    size = size + key.length() + 4 // "key":
    match attrs.get(key) {
      Some(@types.String(s)) => size = size + s.length() + 2
      Some(@types.Int(_)) => size = size + 20
      Some(@types.Float(_)) => size = size + 20
      Some(@types.Bool(_)) => size = size + 5
      Some(@types.Null) | None => size = size + 4
    }
  }
  size
}

///|
/// Read vectors from distributed segments using manifest
pub fn[S : @storage.Storage] read_segments_from_manifest(
  manifest : PlacementManifest,
  storages : Map[String, S],
) -> Array[(@types.VectorId, Array[Double], @types.Attrs)] raise @storage.IOError {
  let results : Array[(@types.VectorId, Array[Double], @types.Attrs)] = []

  // Read each segment from its target storage
  for segment in manifest.segments {
    let storage = require_storage(storages, segment.target_key)

    let data = storage.read(segment.name + @codec.ext_segment, @storage.Data)
    let reader = match @segment.SegmentReader::from_bytes(segment.name, data) {
      None => raise @storage.IoFailed("Invalid segment: " + segment.name)
      Some(r) => r
    }

    for record in reader.iter() {
      results.push(record)
    }
  }

  results
}

///|
/// Save options for distributed storage
pub struct SaveDistributedOptions {
  segment_opts : SegmentOptions
  strategy : @types.Strategy
  include_ann : Bool
  ann_bytes : Bytes? // Pre-serialized ANN state (optional)
}

///|
/// Create default save options
pub fn SaveDistributedOptions::default(
  base_name : String,
  crush : CrushMap,
) -> SaveDistributedOptions {
  {
    segment_opts: SegmentOptions::default(base_name, crush),
    strategy: @types.Bruteforce,
    include_ann: false,
    ann_bytes: None,
  }
}

///|
/// Save CoreStore to distributed storage using CRUSH
/// Writes: data segments (.vseg), index file (.vidx), manifest (.vcdb.manifest)
pub fn[S : @storage.Storage] save_store_distributed(
  store : @store.CoreStore,
  opts : SegmentOptions,
  storages : Map[String, S],
  index_storage : S,
) -> PlacementManifest raise @storage.IOError {
  save_store_distributed_with_ann(
    store,
    opts,
    storages,
    index_storage,
    @types.Bruteforce,
    None,
  )
}

///|
/// Save CoreStore with ANN state to distributed storage
pub fn[S : @storage.Storage] save_store_distributed_with_ann(
  store : @store.CoreStore,
  opts : SegmentOptions,
  storages : Map[String, S],
  index_storage : S,
  strategy : @types.Strategy,
  ann_bytes : Bytes?,
) -> PlacementManifest raise @storage.IOError {
  // 1. Write data segments to distributed storages
  let result = write_segments_from_store(store, opts, storages)

  // 2. Build and write index file (entries + ANN)
  let has_ann = ann_bytes is Some(_)
  let header = @segment.IndexHeader::from_store(store, strategy, has_ann)
  let index_bytes = @segment.encode_index_file(
    header,
    result.entries,
    ann_bytes,
  )
  index_storage.atomic_write(
    opts.base_name + @codec.ext_index,
    index_bytes,
    @storage.Index,
  )

  // 3. Write manifest (segment locations)
  let manifest_bytes = serialize_manifest(result.manifest)
  index_storage.atomic_write(
    opts.base_name + @codec.ext_manifest,
    manifest_bytes,
    @storage.Index,
  )

  result.manifest
}

///|
/// Result of loading from distributed storage
pub struct LoadDistributedResult {
  store : @store.CoreStore
  header : @segment.IndexHeader
  ann_bytes : Bytes?
}

///|
/// Load CoreStore from distributed storage using index file
/// Fast path: use .index file with entry pointers
/// Slow path: scan segments from manifest
pub fn[S : @storage.Storage] load_store_distributed(
  base_name : String,
  storages : Map[String, S],
  index_storage : S,
) -> @store.CoreStore raise @storage.IOError {
  let result = load_store_distributed_full(base_name, storages, index_storage)
  result.store
}

///|
/// Load CoreStore with full metadata (including ANN bytes)
pub fn[S : @storage.Storage] load_store_distributed_full(
  base_name : String,
  storages : Map[String, S],
  index_storage : S,
) -> LoadDistributedResult raise @storage.IOError {
  // Try to load from index file (fast path with pointers)
  if index_storage.exists(base_name + @codec.ext_index, @storage.Index) {
    let index_bytes = index_storage.read(
      base_name + @codec.ext_index,
      @storage.Index,
    )
    let decoded = match @segment.decode_index_file(index_bytes) {
      None => raise @storage.IoFailed("Invalid index file")
      Some(d) => d
    }

    // Load manifest for segment locations
    let manifest_bytes = index_storage.read(
      base_name + @codec.ext_manifest,
      @storage.Index,
    )
    let manifest = match deserialize_manifest(manifest_bytes) {
      None => raise @storage.IoFailed("Invalid manifest")
      Some(m) => m
    }

    // Build segment target lookup
    let seg_targets : Map[String, String] = {}
    for seg in manifest.segments {
      seg_targets.set(seg.name, seg.target_key)
    }

    // Create store with correct metric
    let metric = @segment.decode_metric(decoded.header.metric_code)
    let store = @store.CoreStore::new(
      decoded.header.dim,
      metric,
      capacity=decoded.header.count + 100,
    )

    // Load vectors using index entries (pointer-based access)
    let seg_readers : Map[String, @segment.SegmentReader] = {}
    for entry in decoded.entries {
      let target_key = match seg_targets.get(entry.ptr.segment) {
        Some(t) => t
        None => {
          // Fall back to CRUSH placement
          let result = crush_locate(entry.id, manifest.crush)
          first_string_or(result.primaries, "local")
        }
      }

      // Get or create segment reader
      let reader = match seg_readers.get(entry.ptr.segment) {
        Some(r) => r
        None => {
          let storage = require_storage(storages, target_key)
          let data = storage.read(
            entry.ptr.segment + @codec.ext_segment,
            @storage.Data,
          )
          let r = match
            @segment.SegmentReader::from_bytes(entry.ptr.segment, data) {
            None =>
              raise @storage.IoFailed("Invalid segment: " + entry.ptr.segment)
            Some(r) => r
          }
          seg_readers.set(entry.ptr.segment, r)
          r
        }
      }

      // Read record at pointer
      match reader.read_at(entry.ptr.offset, entry.ptr.length) {
        Some((id, vec, attrs)) => {
          let _ = store.add_or_update(id, vec, attrs, upsert=true)
        }
        None => raise @storage.IoFailed("Failed to read entry at offset")
      }
    }

    return { store, header: decoded.header, ann_bytes: decoded.ann }
  }

  // Fall back to reading from segments (slow path - no index file)
  let manifest_bytes = index_storage.read(
    base_name + @codec.ext_manifest,
    @storage.Index,
  )
  let manifest = match deserialize_manifest(manifest_bytes) {
    None => raise @storage.IoFailed("Invalid manifest")
    Some(m) => m
  }

  if manifest.segments.is_empty() {
    raise @storage.IoFailed("Empty manifest")
  }

  // Determine dimension from first segment
  let first_segment = manifest.segments[0]
  let storage = require_storage(storages, first_segment.target_key)
  let data = storage.read(
    first_segment.name + @codec.ext_segment,
    @storage.Data,
  )
  let reader = match
    @segment.SegmentReader::from_bytes(first_segment.name, data) {
    None => raise @storage.IoFailed("Invalid segment")
    Some(r) => r
  }

  let mut dim = 0
  for record in reader.iter() {
    dim = record.1.length()
    break
  }

  if dim == 0 {
    raise @storage.IoFailed("Empty segments")
  }

  // Create store and load all records
  let store = @store.CoreStore::new(dim, @types.Cosine, capacity=1024)
  let records = read_segments_from_manifest(manifest, storages)
  for record in records {
    let (id, vec, attrs) = record
    let _ = store.add_or_update(id, vec, attrs, upsert=true)
  }

  {
    store,
    header: {
      metric_code: @segment.encode_metric(@types.Cosine),
      dim,
      count: store.size(),
      strategy_code: 0,
      has_ann: false,
    },
    ann_bytes: None,
  }
}

///|
/// Serialize manifest to JSON bytes
fn serialize_manifest(manifest : PlacementManifest) -> Bytes {
  let parts : Array[String] = []
  parts.push("\"base\":\"" + manifest.base + "\"")
  parts.push("\"epoch\":" + manifest.epoch.to_string())
  parts.push("\"commit_ts\":" + manifest.commit_ts.to_string())

  // Segments
  let seg_parts : Array[String] = []
  for seg in manifest.segments {
    seg_parts.push(
      "{\"name\":\"" +
      seg.name +
      "\",\"target_key\":\"" +
      seg.target_key +
      "\"}",
    )
  }
  let segs_str = seg_parts
    .iter()
    .intersperse(",")
    .fold(init="", fn(a, s) { a + s })
  parts.push("\"segments\":[" + segs_str + "]")

  // CRUSH map
  let target_parts : Array[String] = []
  for t in manifest.crush.targets {
    target_parts.push(
      "{\"key\":\"" + t.key + "\",\"weight\":" + t.weight.to_string() + "}",
    )
  }
  let targets_str = target_parts
    .iter()
    .intersperse(",")
    .fold(init="", fn(a, s) { a + s })
  let crush_str = "{\"pgs\":" +
    manifest.crush.pgs.to_string() +
    ",\"replicas\":" +
    manifest.crush.replicas.to_string() +
    ",\"targets\":[" +
    targets_str +
    "]}"
  parts.push("\"crush\":" + crush_str)

  let json = "{" +
    parts.iter().intersperse(",").fold(init="", fn(a, s) { a + s }) +
    "}"
  @codec.encode_utf8(json)
}

///|
/// Find substring index (helper since String.index_of doesn't exist)
fn find_substr(s : String, pattern : String) -> Int? {
  let s_chars = s.to_array()
  let p_chars = pattern.to_array()
  if p_chars.is_empty() {
    return Some(0)
  }
  if s_chars.length() < p_chars.length() {
    return None
  }
  for i in 0..<=(s_chars.length() - p_chars.length()) {
    let mut match_found = true
    for j in 0..<p_chars.length() {
      if s_chars[i + j] != p_chars[j] {
        match_found = false
        break
      }
    }
    if match_found {
      return Some(i)
    }
  }
  None
}

///|
/// Deserialize manifest from JSON bytes (simplified parser)
fn deserialize_manifest(bytes : Bytes) -> PlacementManifest? {
  let json = @codec.decode_utf8(bytes)

  // Extract fields
  let base = extract_string_field(json, "base")
  let epoch = extract_int_field(json, "epoch")
  let commit_ts = extract_int64_field(json, "commit_ts")
  let segments = extract_segments(json)
  let crush = extract_crush_map(json)

  Some({ base, segments, crush, epoch, commit_ts })
}

///|
fn extract_string_field(json : String, field : String) -> String {
  let pattern = "\"" + field + "\":\""
  let start = match find_substr(json, pattern) {
    Some(i) => i + pattern.length()
    None => return ""
  }
  let end_chars = json.to_array()[start:]
  let mut end = 0
  while end < end_chars.length() && end_chars[end] != '"' {
    end = end + 1
  }
  String::from_array(end_chars[:end])
}

///|
fn extract_int_field(json : String, field : String) -> Int {
  let pattern = "\"" + field + "\":"
  let start = match find_substr(json, pattern) {
    Some(i) => i + pattern.length()
    None => return 0
  }
  let chars = json.to_array()[start:]
  let num_chars : Array[Char] = []
  for c in chars {
    if c >= '0' && c <= '9' {
      num_chars.push(c)
    } else if not(num_chars.is_empty()) {
      break
    }
  }
  if num_chars.is_empty() {
    0
  } else {
    let result : Result[Int, _] = try? @strconv.parse_int(
      String::from_array(num_chars),
    )
    match result {
      Ok(n) => n
      Err(_) => 0
    }
  }
}

///|
fn extract_int64_field(json : String, field : String) -> Int64 {
  let pattern = "\"" + field + "\":"
  let start = match find_substr(json, pattern) {
    Some(i) => i + pattern.length()
    None => return 0L
  }
  let chars = json.to_array()[start:]
  let num_chars : Array[Char] = []
  for c in chars {
    if (c >= '0' && c <= '9') || c == '-' {
      num_chars.push(c)
    } else if not(num_chars.is_empty()) {
      break
    }
  }
  if num_chars.is_empty() {
    0L
  } else {
    let result : Result[Int64, _] = try? @strconv.parse_int64(
      String::from_array(num_chars),
    )
    match result {
      Ok(n) => n
      Err(_) => 0L
    }
  }
}

///|
fn extract_segments(json : String) -> Array[SegmentEntry] {
  let segments : Array[SegmentEntry] = []

  // Find segments array
  let pattern = "\"segments\":["
  let start = match find_substr(json, pattern) {
    Some(i) => i + pattern.length()
    None => return segments
  }

  // Find matching ]
  let chars = json.to_array()[start:]
  let mut depth = 1
  let mut end = 0
  while end < chars.length() && depth > 0 {
    if chars[end] == '[' {
      depth = depth + 1
    } else if chars[end] == ']' {
      depth = depth - 1
    }
    end = end + 1
  }

  let segments_str = String::from_array(chars[:end - 1])

  // Parse each segment object
  let mut pos = 0
  let seg_chars = segments_str.to_array()
  while pos < seg_chars.length() {
    // Find {
    while pos < seg_chars.length() && seg_chars[pos] != '{' {
      pos = pos + 1
    }
    if pos >= seg_chars.length() {
      break
    }

    // Find matching }
    let obj_start = pos + 1
    let mut obj_depth = 1
    pos = pos + 1
    while pos < seg_chars.length() && obj_depth > 0 {
      if seg_chars[pos] == '{' {
        obj_depth = obj_depth + 1
      } else if seg_chars[pos] == '}' {
        obj_depth = obj_depth - 1
      }
      pos = pos + 1
    }

    let obj_str = String::from_array(seg_chars[obj_start:pos - 1])
    let name = extract_string_field("{" + obj_str + "}", "name")
    let target_key = extract_string_field("{" + obj_str + "}", "target_key")
    if not(name.is_empty()) {
      segments.push({ name, target_key })
    }
  }

  segments
}

///|
fn extract_crush_map(json : String) -> CrushMap {
  // Find crush object
  let pattern = "\"crush\":{"
  let start = match find_substr(json, pattern) {
    Some(i) => i + pattern.length() - 1
    None => return CrushMap::new(32, 1, [])
  }

  // Find matching }
  let chars = json.to_array()[start:]
  let mut depth = 1
  let mut end = 1
  while end < chars.length() && depth > 0 {
    if chars[end] == '{' {
      depth = depth + 1
    } else if chars[end] == '}' {
      depth = depth - 1
    }
    end = end + 1
  }

  let crush_str = String::from_array(chars[:end])

  let pgs = extract_int_field(crush_str, "pgs")
  let replicas = extract_int_field(crush_str, "replicas")

  // Extract targets
  let targets : Array[CrushTarget] = []
  let targets_pattern = "\"targets\":["
  let targets_start = match find_substr(crush_str, targets_pattern) {
    Some(i) => i + targets_pattern.length()
    None => return CrushMap::new(pgs, replicas, [])
  }

  let target_chars = crush_str.to_array()[targets_start:]
  let mut tpos = 0
  while tpos < target_chars.length() {
    while tpos < target_chars.length() && target_chars[tpos] != '{' {
      if target_chars[tpos] == ']' {
        break
      }
      tpos = tpos + 1
    }
    if tpos >= target_chars.length() || target_chars[tpos] == ']' {
      break
    }

    let tobj_start = tpos + 1
    let mut tobj_depth = 1
    tpos = tpos + 1
    while tpos < target_chars.length() && tobj_depth > 0 {
      if target_chars[tpos] == '{' {
        tobj_depth = tobj_depth + 1
      } else if target_chars[tpos] == '}' {
        tobj_depth = tobj_depth - 1
      }
      tpos = tpos + 1
    }

    let tobj_str = String::from_array(target_chars[tobj_start:tpos - 1])
    let key = extract_string_field("{" + tobj_str + "}", "key")
    if not(key.is_empty()) {
      targets.push(CrushTarget::new(key))
    }
  }

  CrushMap::new(pgs, replicas, targets)
}
