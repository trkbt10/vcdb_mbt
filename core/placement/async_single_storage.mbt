///|
/// Async segmented save/load — target-independent.
///
/// Segment construction uses write_segments_in_memory (SoT in io.mbt).
/// Only the actual storage writes/reads are async via AsyncStorage trait.

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

  // Build segments in memory (SoT: write_segments_in_memory in io.mbt)
  let mem = write_segments_in_memory(store, opts)

  // Persist segments to storage (async)
  for seg in mem.segments {
    @storage.async_atomic_write(
      storage,
      seg.name + @codec.ext_segment,
      seg.data,
      @storage.Data,
    )
  }

  // Write index file
  let has_ann = false
  let header = @segment.IndexHeader::from_store(
    store,
    @types.Bruteforce,
    has_ann,
  )
  let index_bytes = @segment.encode_index_file(header, mem.entries, None)
  @storage.async_atomic_write(
    storage,
    base_name + @codec.ext_index,
    index_bytes,
    @storage.Index,
  )

  // Write manifest
  let manifest_bytes = serialize_manifest(mem.manifest)
  @storage.async_atomic_write(
    storage,
    base_name + @codec.ext_manifest,
    manifest_bytes,
    @storage.Index,
  )
}

///|
/// Load a CoreStore from async storage using segments.
///
/// Fetches bytes asynchronously, then delegates reconstruction
/// to reconstruct_from_index / reconstruct_from_segments (SoT in io.mbt).
pub async fn[S : @storage.AsyncStorage] async_load_segmented(
  base_name : String,
  storage : S,
) -> @store.CoreStore {
  let index_path = base_name + @codec.ext_index
  let has_index = @storage.async_exists(storage, index_path, @storage.Index)

  if has_index {
    // Fast path: fetch index + manifest + segment bytes, then reconstruct
    let index_bytes = @storage.async_read(storage, index_path, @storage.Index)
    let manifest_bytes = @storage.async_read(
      storage,
      base_name + @codec.ext_manifest,
      @storage.Index,
    )

    // Determine which segments to fetch from the index
    let decoded = match @segment.decode_index_file(index_bytes) {
      None => abort("Invalid index file")
      Some(d) => d
    }
    let needed : Map[String, Bool] = {}
    for entry in decoded.entries {
      needed.set(entry.ptr.segment, true)
    }

    let segment_data : Map[String, Bytes] = {}
    for seg_name in needed.keys() {
      let data = @storage.async_read(
        storage,
        seg_name + @codec.ext_segment,
        @storage.Data,
      )
      segment_data.set(seg_name, data)
    }

    match reconstruct_from_index(index_bytes, manifest_bytes, segment_data) {
      Some(result) => return result.store
      None => abort("Failed to reconstruct from index")
    }
  }

  // Slow path: fetch manifest + all segment bytes, then reconstruct
  let manifest_bytes = @storage.async_read(
    storage,
    base_name + @codec.ext_manifest,
    @storage.Index,
  )
  let manifest = match deserialize_manifest(manifest_bytes) {
    None => abort("Invalid manifest")
    Some(m) => m
  }

  let segment_data : Map[String, Bytes] = {}
  for seg in manifest.segments {
    let data = @storage.async_read(
      storage,
      seg.name + @codec.ext_segment,
      @storage.Data,
    )
    segment_data.set(seg.name, data)
  }

  match reconstruct_from_segments(manifest_bytes, segment_data) {
    Some(result) => result.store
    None => abort("Failed to reconstruct from segments")
  }
}
