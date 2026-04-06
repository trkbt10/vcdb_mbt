///|
/// Path helpers for storage operations
///
/// Centralized path construction. File extension constants are
/// defined in core/persistence/codec/header.mbt (the SoT).

///|
/// Config file extension (not part of binary format, defined here)
pub let ext_config : String = ".config.json"

///|
/// Data file extension (non-distributed, defined here)
pub let ext_data : String = ".data.bin"

///|
/// Path for collection config file
pub fn collection_config_path(collection_name : String) -> String {
  collection_name + ext_config
}

///|
/// Path for collection data (non-distributed)
pub fn collection_data_path(collection_name : String) -> String {
  collection_name + ext_data
}

///|
/// Path for collection WAL file
pub fn collection_wal_path(collection_name : String) -> String {
  collection_name + @codec.ext_wal
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

///|
/// Check if a path is a segment file for a given collection
pub fn is_segment_path(path : String, base_name : String) -> Bool {
  path.has_prefix(base_name + ".pg") && path.has_suffix(@codec.ext_segment)
}
