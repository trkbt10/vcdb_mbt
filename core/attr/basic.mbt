///|
/// Basic Attribute Index - Hash map based implementation
/// Provides fast equality lookups and range queries via sorted numeric arrays.
pub struct BasicAttrIndex {
  data : Map[Int64, @types.Attrs] // id -> attrs
  eq_map : Map[String, Map[String, Array[Int64]]] // key -> value -> ids
  exists_map : Map[String, Array[Int64]] // key -> ids with that key
  num_map : Map[String, (Array[NumEntry], Bool)] // key -> (sorted entries, dirty flag)
}

///|
/// Create a new empty BasicAttrIndex
pub fn BasicAttrIndex::new() -> BasicAttrIndex {
  { data: {}, eq_map: {}, exists_map: {}, num_map: {} }
}

///|
/// Add entry to numeric index for a key
fn add_to_num_index(
  num_map : Map[String, (Array[NumEntry], Bool)],
  key : String,
  value : Double,
  id : Int64,
) -> Unit {
  match num_map.get(key) {
    None => num_map.set(key, ([{ value, id }], true))
    Some((arr, _)) => {
      arr.push({ value, id })
      num_map.set(key, (arr, true)) // Mark as dirty
    }
  }
}

///|
/// Remove entry from numeric index
fn remove_from_num_index(
  num_map : Map[String, (Array[NumEntry], Bool)],
  key : String,
  id : Int64,
) -> Unit {
  match num_map.get(key) {
    None => ()
    Some((arr, _)) =>
      if remove_num_entry_swap(arr, id) {
        num_map.set(key, (arr, true)) // Mark as dirty after removal
      }
  }
}

///|
/// Set attributes for an ID (replaces existing)
pub fn BasicAttrIndex::set_attrs(
  self : BasicAttrIndex,
  id : @types.VectorId,
  attrs : @types.Attrs,
) -> Unit {
  let id_val = id.to_int64()
  // Remove old attrs from indexes if present
  match self.data.get(id_val) {
    None => ()
    Some(old_attrs) =>
      for_each_attr(old_attrs, fn(key, value) {
        remove_from_eq_index(self.eq_map, key, value, id_val)
        remove_from_exists_index(self.exists_map, key, id_val)
        match attr_value_to_number(value) {
          Some(_) => remove_from_num_index(self.num_map, key, id_val)
          None => ()
        }
      })
  }
  // Add new attrs to indexes
  for_each_attr(attrs, fn(key, value) {
    add_to_eq_index(self.eq_map, key, value, id_val)
    add_to_exists_index(self.exists_map, key, id_val)
    match attr_value_to_number(value) {
      Some(num) => add_to_num_index(self.num_map, key, num, id_val)
      None => ()
    }
  })
  // Store attrs (defensive copy to prevent external mutation)
  self.data.set(id_val, attrs.copy())
}

///|
/// Get attributes for an ID
pub fn BasicAttrIndex::get_attrs(
  self : BasicAttrIndex,
  id : @types.VectorId,
) -> @types.Attrs? {
  self.data.get(id.to_int64())
}

///|
/// Remove an ID from the index
pub fn BasicAttrIndex::remove_id(
  self : BasicAttrIndex,
  id : @types.VectorId,
) -> Unit {
  let id_val = id.to_int64()
  match self.data.get(id_val) {
    None => ()
    Some(old_attrs) => {
      for_each_attr(old_attrs, fn(key, value) {
        remove_from_eq_index(self.eq_map, key, value, id_val)
        remove_from_exists_index(self.exists_map, key, id_val)
        match attr_value_to_number(value) {
          Some(_) => remove_from_num_index(self.num_map, key, id_val)
          None => ()
        }
      })
      self.data.remove(id_val)
    }
  }
}

///|
/// Find IDs where key equals value
pub fn BasicAttrIndex::eq(
  self : BasicAttrIndex,
  key : String,
  value : @types.AttrValue,
) -> Array[@types.VectorId] {
  let value_key = attr_value_to_key(value)
  match self.eq_map.get(key) {
    None => []
    Some(value_map) =>
      match value_map.get(value_key) {
        None => []
        Some(ids) => ids_to_vector_ids(ids)
      }
  }
}

///|
/// Find IDs where key exists
pub fn BasicAttrIndex::exists(
  self : BasicAttrIndex,
  key : String,
) -> Array[@types.VectorId] {
  match self.exists_map.get(key) {
    None => []
    Some(ids) => ids_to_vector_ids(ids)
  }
}

///|
/// Ensure numeric array is sorted
fn ensure_sorted(
  num_map : Map[String, (Array[NumEntry], Bool)],
  key : String,
) -> Unit {
  match num_map.get(key) {
    None => ()
    Some((arr, dirty)) =>
      if dirty {
        sort_num_entries(arr)
        num_map.set(key, (arr, false)) // Mark as clean
      }
  }
}

///|
/// Find IDs matching a numeric range
/// Returns None if range queries are not supported for this key
pub fn BasicAttrIndex::range(
  self : BasicAttrIndex,
  key : String,
  range : @types.NumericRange,
) -> Array[@types.VectorId]? {
  match self.num_map.get(key) {
    None => Some([]) // Key doesn't exist, return empty
    Some((_arr, _)) => {
      // Ensure array is sorted
      ensure_sorted(self.num_map, key)
      // Re-get after potential sort
      match self.num_map.get(key) {
        None => Some([])
        Some((sorted_arr, _)) => {
          // Find lower bound
          let lo_idx = match range.gte {
            Some(v) => lower_bound(sorted_arr, v)
            None =>
              match range.gt {
                Some(v) => upper_bound(sorted_arr, v)
                None => 0
              }
          }
          // Find upper bound
          let hi_idx = match range.lt {
            Some(v) => lower_bound(sorted_arr, v)
            None =>
              match range.lte {
                Some(v) => upper_bound(sorted_arr, v)
                None => sorted_arr.length()
              }
          }
          // Collect results
          if lo_idx >= hi_idx {
            Some([])
          } else {
            let result : Array[@types.VectorId] = []
            for i = lo_idx; i < hi_idx; i = i + 1 {
              result.push(@types.Int64Id(sorted_arr[i].id))
            }
            Some(result)
          }
        }
      }
    }
  }
}

///|
/// Get the number of indexed IDs
pub fn BasicAttrIndex::size(self : BasicAttrIndex) -> Int {
  self.data.length()
}
