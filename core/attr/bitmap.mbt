///|
/// Bitmap Attribute Index - Simplified index for low-cardinality fields
/// Supports equality and existence queries only, no range queries.
pub struct BitmapAttrIndex {
  data : Map[Int64, @core.Attrs] // id -> attrs
  eq_map : Map[String, Map[String, Array[Int64]]] // key -> value -> ids
  exists_map : Map[String, Array[Int64]] // key -> ids with that key
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
  id : @core.VectorId,
  attrs : @core.Attrs,
) -> Unit {
  let id_val = id.to_int64()
  // Remove old attrs from indexes if present
  match self.data.get(id_val) {
    None => ()
    Some(old_attrs) =>
      for key in old_attrs.keys() {
        match old_attrs.get(key) {
          None => ()
          Some(value) => {
            bitmap_remove_from_eq(self.eq_map, key, value, id_val)
            bitmap_remove_from_exists(self.exists_map, key, id_val)
          }
        }
      }
  }
  // Add new attrs to indexes
  for key in attrs.keys() {
    match attrs.get(key) {
      None => ()
      Some(value) => {
        bitmap_add_to_eq(self.eq_map, key, value, id_val)
        bitmap_add_to_exists(self.exists_map, key, id_val)
      }
    }
  }
  // Store attrs (defensive copy to prevent external mutation)
  self.data.set(id_val, attrs.copy())
}

///|
fn bitmap_add_to_eq(
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
fn bitmap_remove_from_eq(
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
fn bitmap_add_to_exists(
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
fn bitmap_remove_from_exists(
  exists_map : Map[String, Array[Int64]],
  key : String,
  id : Int64,
) -> Unit {
  match exists_map.get(key) {
    None => ()
    Some(ids) => {
      let mut found_idx = -1
      for i in 0..<ids.length() {
        if ids[i] == id {
          found_idx = i
          break
        }
      }
      if found_idx >= 0 {
        let last = ids.length() - 1
        if found_idx != last {
          ids[found_idx] = ids[last]
        }
        let _ = ids.pop()
      }
    }
  }
}

///|
/// Get attributes for an ID
pub fn BitmapAttrIndex::get_attrs(
  self : BitmapAttrIndex,
  id : @core.VectorId,
) -> @core.Attrs? {
  self.data.get(id.to_int64())
}

///|
/// Remove an ID from the index
pub fn BitmapAttrIndex::remove_id(
  self : BitmapAttrIndex,
  id : @core.VectorId,
) -> Unit {
  let id_val = id.to_int64()
  match self.data.get(id_val) {
    None => ()
    Some(old_attrs) => {
      for key in old_attrs.keys() {
        match old_attrs.get(key) {
          None => ()
          Some(value) => {
            bitmap_remove_from_eq(self.eq_map, key, value, id_val)
            bitmap_remove_from_exists(self.exists_map, key, id_val)
          }
        }
      }
      self.data.remove(id_val)
    }
  }
}

///|
/// Find IDs where key equals value
pub fn BitmapAttrIndex::eq(
  self : BitmapAttrIndex,
  key : String,
  value : @core.AttrValue,
) -> Array[@core.VectorId] {
  let value_key = attr_value_to_key(value)
  match self.eq_map.get(key) {
    None => []
    Some(value_map) =>
      match value_map.get(value_key) {
        None => []
        Some(ids) => {
          let result : Array[@core.VectorId] = []
          for id in ids {
            result.push(@core.VectorId(id))
          }
          result
        }
      }
  }
}

///|
/// Find IDs where key exists
pub fn BitmapAttrIndex::exists(
  self : BitmapAttrIndex,
  key : String,
) -> Array[@core.VectorId] {
  match self.exists_map.get(key) {
    None => []
    Some(ids) => {
      let result : Array[@core.VectorId] = []
      for id in ids {
        result.push(@core.VectorId(id))
      }
      result
    }
  }
}

///|
/// Range queries not supported for Bitmap index
pub fn BitmapAttrIndex::range(
  _self : BitmapAttrIndex,
  key : String,
  range : @core.NumericRange,
) -> Array[@core.VectorId]? {
  let _ = (key, range)
  None // Not supported
}

///|
/// Get the number of indexed IDs
pub fn BitmapAttrIndex::size(self : BitmapAttrIndex) -> Int {
  self.data.length()
}
