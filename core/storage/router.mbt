///|
/// Path helpers for storage operations
///
/// Centralized path conventions. App layer uses these to construct paths.

///|
/// Path for collection config file
pub fn collection_config_path(collection_name : String) -> String {
  collection_name + ".config.json"
}

///|
/// Path for collection data (non-distributed)
pub fn collection_data_path(collection_name : String) -> String {
  collection_name + ".data.bin"
}

///|
/// Path for collection index file (distributed)
pub fn collection_index_path(collection_name : String) -> String {
  collection_name + @codec.ext_index
}

///|
/// Path for collection manifest file (distributed)
pub fn collection_manifest_path(collection_name : String) -> String {
  collection_name + @codec.ext_manifest
}

///|
/// Path for data segment file
pub fn segment_data_path(base : String, pg : Int, part : Int) -> String {
  base +
  ".pg" +
  pg.to_string() +
  ".part" +
  part.to_string() +
  @codec.ext_segment
}
