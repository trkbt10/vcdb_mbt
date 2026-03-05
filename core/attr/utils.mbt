///|
/// Iterate all key-value pairs in attrs.
fn for_each_attr(
  attrs : @core.Attrs,
  f : (String, @core.AttrValue) -> Unit,
) -> Unit {
  for key in attrs.keys() {
    match attrs.get(key) {
      None => ()
      Some(value) => f(key, value)
    }
  }
}

///|
/// Convert internal Int64 id list to VectorId list.
fn ids_to_vector_ids(ids : Array[Int64]) -> Array[@core.VectorId] {
  let result : Array[@core.VectorId] = []
  for id in ids {
    result.push(@core.VectorId(id))
  }
  result
}

///|
/// Add ID to the equality index for a key-value pair.
fn add_to_eq_index(
  eq_map : Map[String, Map[String, Array[Int64]]],
  key : String,
  value : @core.AttrValue,
  id : Int64,
) -> Unit {
  let value_key = attr_value_to_key(value)
  match eq_map.get(key) {
    None => {
      let value_map : Map[String, Array[Int64]] = {}
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
  eq_map : Map[String, Map[String, Array[Int64]]],
  key : String,
  value : @core.AttrValue,
  id : Int64,
) -> Unit {
  let value_key = attr_value_to_key(value)
  match eq_map.get(key) {
    None => ()
    Some(value_map) =>
      match value_map.get(value_key) {
        None => ()
        Some(ids) => {
          let _ = remove_int64_swap(ids, id)
        }
      }
  }
}

///|
/// Add ID to the exists index for a key.
fn add_to_exists_index(
  exists_map : Map[String, Array[Int64]],
  key : String,
  id : Int64,
) -> Unit {
  match exists_map.get(key) {
    None => exists_map.set(key, [id])
    Some(ids) => ids.push(id)
  }
}

///|
/// Remove ID from the exists index for a key.
fn remove_from_exists_index(
  exists_map : Map[String, Array[Int64]],
  key : String,
  id : Int64,
) -> Unit {
  match exists_map.get(key) {
    None => ()
    Some(ids) => {
      let _ = remove_int64_swap(ids, id)
    }
  }
}
