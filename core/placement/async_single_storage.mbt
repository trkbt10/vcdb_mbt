///|
/// Async segmented save/load for JS environments.
///
/// Segment construction (CRUSH placement, binary encoding) is done synchronously
/// in memory. Only the actual storage writes/reads are async, ensuring each
/// segment, index, and manifest is durably persisted before proceeding.

///|
/// Save a CoreStore to async storage using segments.
/// Each segment is awaited individually — durable on return.
pub async fn[S : @storage.AsyncStorage] async_save_segmented(
  store : @store.CoreStore,
  base_name : String,
  segment_bytes : Int,
  storage : S,
) -> Unit {
  let crush = CrushMap::new(32, 1, [CrushTarget::new("local")])
  let opts = SegmentOptions::segmented(base_name, crush, segment_bytes)

  // Build segments in memory (synchronous, no I/O)
  let result = write_segments_in_memory(store, opts)

  // Write each segment to storage (async, awaited)
  for seg in result.segments {
    storage
      .atomic_write(seg.name + @codec.ext_segment, seg.data, @storage.Data)
      .wait()
  }

  // Write index file
  let has_ann = false
  let header = @segment.IndexHeader::from_store(
    store,
    @types.Bruteforce,
    has_ann,
  )
  let index_bytes = @segment.encode_index_file(header, result.entries, None)
  storage
    .atomic_write(base_name + @codec.ext_index, index_bytes, @storage.Index)
    .wait()

  // Write manifest
  let manifest_bytes = serialize_manifest(result.manifest)
  storage
    .atomic_write(
      base_name + @codec.ext_manifest,
      manifest_bytes,
      @storage.Index,
    )
    .wait()
}

///|
/// Load a CoreStore from async storage using segments.
pub async fn[S : @storage.AsyncStorage] async_load_segmented(
  base_name : String,
  storage : S,
) -> @store.CoreStore {
  // Try fast path: load from index file
  let index_path = base_name + @codec.ext_index
  let has_index = storage.exists(index_path, @storage.Index).wait()

  if has_index {
    let index_bytes = storage.read(index_path, @storage.Index).wait()
    let decoded = match @segment.decode_index_file(index_bytes) {
      None => abort("Invalid index file")
      Some(d) => d
    }

    let manifest_bytes = storage
      .read(base_name + @codec.ext_manifest, @storage.Index)
      .wait()
    let manifest = match deserialize_manifest(manifest_bytes) {
      None => abort("Invalid manifest")
      Some(m) => m
    }

    let metric = @segment.decode_metric(decoded.header.metric_code)
    let store = @store.CoreStore::new(
      decoded.header.dim,
      metric,
      capacity=decoded.header.count + 100,
    )

    // Load segment data and reconstruct
    let seg_readers : Map[String, @segment.SegmentReader] = {}
    for entry in decoded.entries {
      let reader = match seg_readers.get(entry.ptr.segment) {
        Some(r) => r
        None => {
          let data = storage
            .read(entry.ptr.segment + @codec.ext_segment, @storage.Data)
            .wait()
          let r = match @segment.SegmentReader::from_bytes(
            entry.ptr.segment,
            data,
          ) {
            None => abort("Invalid segment: " + entry.ptr.segment)
            Some(r) => r
          }
          seg_readers.set(entry.ptr.segment, r)
          r
        }
      }
      match reader.read_at(entry.ptr.offset, entry.ptr.length) {
        Some((id, vec, attrs)) => {
          let _ = store.add_or_update(id, vec, attrs, upsert=true)
        }
        None => abort("Failed to read entry at offset")
      }
    }
    return store
  }

  // Slow path: read from manifest
  let manifest_bytes = storage
    .read(base_name + @codec.ext_manifest, @storage.Index)
    .wait()
  let manifest = match deserialize_manifest(manifest_bytes) {
    None => abort("Invalid manifest")
    Some(m) => m
  }

  if manifest.segments.is_empty() {
    abort("Empty manifest")
  }

  // Determine dimension from first segment
  let first_seg = manifest.segments[0]
  let first_data = storage
    .read(first_seg.name + @codec.ext_segment, @storage.Data)
    .wait()
  let first_reader = match @segment.SegmentReader::from_bytes(
    first_seg.name,
    first_data,
  ) {
    None => abort("Invalid segment")
    Some(r) => r
  }

  let mut dim = 0
  for record in first_reader.iter() {
    dim = record.1.length()
    break
  }
  if dim == 0 {
    abort("Empty segments")
  }

  let store = @store.CoreStore::new(dim, @types.Cosine, capacity=1024)

  // Load all segments
  for seg in manifest.segments {
    let data = storage
      .read(seg.name + @codec.ext_segment, @storage.Data)
      .wait()
    let reader = match @segment.SegmentReader::from_bytes(seg.name, data) {
      None => continue
      Some(r) => r
    }
    for record in reader.iter() {
      let (id, vec, attrs) = record
      let _ = store.add_or_update(id, vec, attrs, upsert=true)
    }
  }

  store
}

///|
/// Result of in-memory segment construction.
struct MemorySegmentResult {
  segments : Array[MemorySegment]
  entries : Array[@segment.IndexEntry]
  manifest : PlacementManifest
}

///|
struct MemorySegment {
  name : String
  data : Bytes
}

///|
/// Build segments in memory without writing to storage.
/// Used by async_save_segmented to separate computation from I/O.
fn write_segments_in_memory(
  store : @store.CoreStore,
  opts : SegmentOptions,
) -> MemorySegmentResult {
  let base = opts.base_name
  let seg_limit = if opts.segment_bytes > 0 {
    opts.segment_bytes
  } else {
    64 * 1024 * 1024
  }

  let writers : Map[Int, SegState] = {}
  let entries : Array[@segment.IndexEntry] = []
  let segments : Array[MemorySegment] = []
  let dim = store.dim
  let count = store.size()

  for i in 0..<count {
    let id = store.ids[i]
    let result = crush_locate(id, opts.crush)
    let pg = result.pg
    let target_key = first_string_or(result.primaries, "local")

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

    let vector : Array[Double] = []
    let base_idx = i * dim
    for j in 0..<dim {
      vector.push(store.data[base_idx + j])
    }
    let attrs = store.attrs[i]
    let attrs_size = estimate_attrs_size(attrs)
    let rec_size = 16 + attrs_size + vector.length() * 4

    if opts.segmented && seg.size + rec_size > seg_limit {
      let seg_data = seg.writer.to_bytes()
      segments.push({ name: seg.writer.get_name(), data: seg_data })

      seg.part = seg.part + 1
      let new_name = "\{base}.pg\{pg}.part\{seg.part}"
      seg.writer = @segment.SegmentWriter::new(new_name)
      seg.size = 8
    }

    let ptr = seg.writer.append(id, vector, attrs)
    seg.size = seg.size + ptr.length
    entries.push({ id, ptr })
  }

  // Flush remaining
  let segment_entries : Array[SegmentEntry] = []
  for pg in writers.keys() {
    match writers.get(pg) {
      None => continue
      Some(seg) => {
        let seg_data = seg.writer.to_bytes()
        segments.push({ name: seg.writer.get_name(), data: seg_data })
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

  { segments, entries, manifest }
}
