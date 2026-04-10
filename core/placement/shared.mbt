///|
/// Lookup storage by target key or raise an IO error.
fn[S] require_storage(
  storages : Map[TargetKey, S],
  key : TargetKey,
) -> S raise @storage.IOError {
  require_storage_with_prefix(storages, key, "Storage not found: ")
}

///|
/// Lookup storage by target key or raise an IO error with custom message prefix.
fn[S] require_storage_with_prefix(
  storages : Map[TargetKey, S],
  key : TargetKey,
  prefix : String,
) -> S raise @storage.IOError {
  match storages.get(key) {
    Some(storage) => storage
    None => raise @storage.IoFailed(prefix + key.to_string())
  }
}
