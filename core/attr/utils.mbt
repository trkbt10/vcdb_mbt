///|
/// Iterate all key-value pairs in attrs.
fn for_each_attr(
  attrs : @types.Attrs,
  f : (String, @types.AttrValue) -> Unit,
) -> Unit {
  for key in attrs.keys() {
    match attrs.get(key) {
      None => ()
      Some(value) => f(key, value)
    }
  }
}

///|
/// Whether a value should make its key visible to `exists(key)` filters.
fn attr_value_counts_as_exists(value : @types.AttrValue) -> Bool {
  match value {
    @types.Null => false
    _ => true
  }
}

///|
/// Add ID to the equality index for a key-value pair.
fn add_to_eq_index(
  eq_map : Map[String, Map[String, Array[@types.VectorId]]],
  key : String,
  value : @types.AttrValue,
  id : @types.VectorId,
) -> Unit {
  let value_key = attr_value_to_key(value)
  match eq_map.get(key) {
    None => {
      let value_map : Map[String, Array[@types.VectorId]] = {}
      value_map.set(value_key, [id])
      eq_map.set(key, value_map)
    }
    Some(value_map) =>
      match value_map.get(value_key) {
        None => value_map.set(value_key, [id])
        Some(ids) => ids.push(id)
      }
  }
}

///|
/// Remove ID from the equality index for a key-value pair.
fn remove_from_eq_index(
  eq_map : Map[String, Map[String, Array[@types.VectorId]]],
  key : String,
  value : @types.AttrValue,
  id : @types.VectorId,
) -> Unit {
  let value_key = attr_value_to_key(value)
  match eq_map.get(key) {
    None => ()
    Some(value_map) =>
      match value_map.get(value_key) {
        None => ()
        Some(ids) => {
          let _ = remove_vectorid_swap(ids, id)
        }
      }
  }
}

///|
/// Add ID to the exists index for a key.
fn add_to_exists_index(
  exists_map : Map[String, Array[@types.VectorId]],
  key : String,
  id : @types.VectorId,
) -> Unit {
  match exists_map.get(key) {
    None => exists_map.set(key, [id])
    Some(ids) => ids.push(id)
  }
}

///|
/// Remove ID from the exists index for a key.
fn remove_from_exists_index(
  exists_map : Map[String, Array[@types.VectorId]],
  key : String,
  id : @types.VectorId,
) -> Unit {
  match exists_map.get(key) {
    None => ()
    Some(ids) => {
      let _ = remove_vectorid_swap(ids, id)
    }
  }
}
