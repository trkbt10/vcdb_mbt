///|
/// Return the first string in array, or fallback when empty.
fn first_string_or(values : Array[String], fallback : String) -> String {
  if values.is_empty() {
    fallback
  } else {
    values[0]
  }
}

///|
/// Return first string as option.
fn first_string_opt(values : Array[String]) -> String? {
  if values.is_empty() {
    None
  } else {
    Some(values[0])
  }
}

///|
/// Lookup storage by key or raise an IO error.
fn[S] require_storage(
  storages : Map[String, S],
  key : String,
) -> S raise @storage.IOError {
  require_storage_with_prefix(storages, key, "Storage not found: ")
}

///|
/// Lookup storage by key or raise an IO error with custom message prefix.
fn[S] require_storage_with_prefix(
  storages : Map[String, S],
  key : String,
  prefix : String,
) -> S raise @storage.IOError {
  match storages.get(key) {
    Some(storage) => storage
    None => raise @storage.IoFailed(prefix + key)
  }
}
