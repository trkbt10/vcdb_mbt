///|
/// Bitmap Attribute Index - Simplified index for low-cardinality fields
/// Supports equality and existence queries only, no range queries.
pub struct BitmapAttrIndex {
  data : Map[@types.VectorId, @types.Attrs] // id -> attrs
  eq_map : Map[String, Map[String, Array[@types.VectorId]]] // key -> value -> ids
  exists_map : Map[String, Array[@types.VectorId]] // key -> ids with that key
}

///|
/// Create a new empty BitmapAttrIndex
pub fn BitmapAttrIndex::new() -> BitmapAttrIndex {
  { data: {}, eq_map: {}, exists_map: {} }
}

///|
/// Set attributes for an ID (replaces existing)
pub fn BitmapAttrIndex::set_attrs(
  self : BitmapAttrIndex,
  id : @types.VectorId,
  attrs : @types.Attrs,
) -> Unit {
  // Remove old attrs from indexes if present
  match self.data.get(id) {
    None => ()
    Some(old_attrs) =>
      for_each_attr(old_attrs, fn(key, value) {
        remove_from_eq_index(self.eq_map, key, value, id)
        remove_from_exists_index(self.exists_map, key, id)
      })
  }
  // Add new attrs to indexes
  for_each_attr(attrs, fn(key, value) {
    add_to_eq_index(self.eq_map, key, value, id)
    if attr_value_counts_as_exists(value) {
      add_to_exists_index(self.exists_map, key, id)
    }
  })
  // Store attrs (defensive copy to prevent external mutation)
  self.data.set(id, attrs.copy())
}

///|
/// Get attributes for an ID
pub fn BitmapAttrIndex::get_attrs(
  self : BitmapAttrIndex,
  id : @types.VectorId,
) -> @types.Attrs? {
  self.data.get(id)
}

///|
/// Remove an ID from the index
pub fn BitmapAttrIndex::remove_id(
  self : BitmapAttrIndex,
  id : @types.VectorId,
) -> Unit {
  match self.data.get(id) {
    None => ()
    Some(old_attrs) => {
      for_each_attr(old_attrs, fn(key, value) {
        remove_from_eq_index(self.eq_map, key, value, id)
        remove_from_exists_index(self.exists_map, key, id)
      })
      self.data.remove(id)
    }
  }
}

///|
/// Find IDs where key equals value
pub fn BitmapAttrIndex::eq(
  self : BitmapAttrIndex,
  key : String,
  value : @types.AttrValue,
) -> Array[@types.VectorId] {
  let value_key = attr_value_to_key(value)
  match self.eq_map.get(key) {
    None => []
    Some(value_map) =>
      match value_map.get(value_key) {
        None => []
        Some(ids) => ids.copy()
      }
  }
}

///|
/// Find IDs where key exists
pub fn BitmapAttrIndex::exists(
  self : BitmapAttrIndex,
  key : String,
) -> Array[@types.VectorId] {
  match self.exists_map.get(key) {
    None => []
    Some(ids) => ids.copy()
  }
}

///|
/// Range queries not supported for Bitmap index
pub fn BitmapAttrIndex::range(
  _self : BitmapAttrIndex,
  key : String,
  range : @types.NumericRange,
) -> Array[@types.VectorId]? {
  let _ = (key, range)
  None // Not supported
}

///|
/// Get the number of indexed IDs
pub fn BitmapAttrIndex::size(self : BitmapAttrIndex) -> Int {
  self.data.length()
}
