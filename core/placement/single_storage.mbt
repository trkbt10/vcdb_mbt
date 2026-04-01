///|
/// Simplified save/load for single-storage backends (fs, DO, S3, etc.)
///
/// Wraps the distributed CRUSH-based API with sane defaults:
/// - 1 placement group, 1 replica, target "local"
/// - Automatic segment rotation at the given byte limit
///
/// Gateway uses these instead of constructing CrushMap directly.

///|
/// Save a CoreStore to a single storage backend using segments.
/// Each segment file stays under segment_bytes.
/// Writes: .vseg (Data kind), .vidx + .vcdb.manifest (Index kind)
pub fn[S : @storage.Storage] save_segmented(
  store : @store.CoreStore,
  base_name : String,
  segment_bytes : Int,
  storage : S,
) -> Unit raise @storage.IOError {
  let crush = CrushMap::new(32, 1, [CrushTarget::new("local")])
  let opts = SegmentOptions::segmented(base_name, crush, segment_bytes)
  let storages : Map[String, S] = { "local": storage }
  let _ = save_store_distributed(store, opts, storages, storage)
}

///|
/// Load a CoreStore from a single storage backend using segments.
/// Reads: .vidx + .vcdb.manifest (Index kind), .vseg (Data kind)
pub fn[S : @storage.Storage] load_segmented(
  base_name : String,
  storage : S,
) -> @store.CoreStore raise @storage.IOError {
  let storages : Map[String, S] = { "local": storage }
  load_store_distributed(base_name, storages, storage)
}
