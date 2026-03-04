///|
/// Attribute Index Strategy
pub enum AttrIndexStrategy {
  Basic // Hash map based
  Bitmap // For low-cardinality fields
  BPTree // B+ tree for balanced read/write
  LSM // Write-optimized with memtable
} derive(Eq, Show)

///|
/// Convert AttrValue to string key for indexing
/// Uses type prefix to disambiguate different types with same string representation
pub fn attr_value_to_key(value : @core.AttrValue) -> String {
  match value {
    Null => "N:"
    Bool(b) => if b { "B:true" } else { "B:false" }
    Int(n) => "I:" + n.to_string()
    Float(f) => "F:" + f.to_string()
    String(s) => "S:" + s
  }
}

///|
/// Extract numeric value from AttrValue for range queries
pub fn attr_value_to_number(value : @core.AttrValue) -> Double? {
  match value {
    Int(n) => Some(n.to_double())
    Float(f) => Some(f)
    _ => None
  }
}

///|
/// Sorted entry for numeric index (value, id) pair
pub struct NumEntry {
  value : Double
  id : Int64
} derive(Show)

///|
/// Compare NumEntry by value for sorting
pub fn NumEntry::compare(self : NumEntry, other : NumEntry) -> Int {
  if self.value < other.value {
    -1
  } else if self.value > other.value {
    1
  } else {
    0
  }
}

///|
/// Binary search for lower bound in sorted array
/// Returns index of first element >= target
pub fn lower_bound(arr : Array[NumEntry], target : Double) -> Int {
  let mut lo = 0
  let mut hi = arr.length()
  while lo < hi {
    let mid = (lo + hi) / 2
    if arr[mid].value < target {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  lo
}

///|
/// Binary search for upper bound in sorted array
/// Returns index of first element > target
pub fn upper_bound(arr : Array[NumEntry], target : Double) -> Int {
  let mut lo = 0
  let mut hi = arr.length()
  while lo < hi {
    let mid = (lo + hi) / 2
    if arr[mid].value <= target {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  lo
}

///|
/// Sort NumEntry array by value
pub fn sort_num_entries(arr : Array[NumEntry]) -> Unit {
  // Simple insertion sort for now (stable and works for small arrays)
  for i in 1..<arr.length() {
    let key = arr[i]
    let mut j = i - 1
    while j >= 0 && arr[j].value > key.value {
      arr[j + 1] = arr[j]
      j = j - 1
    }
    arr[j + 1] = key
  }
}

///|
/// Remove an Int64 value from an array using swap-and-pop
/// Returns true if the value was found and removed
pub fn remove_int64_swap(arr : Array[Int64], value : Int64) -> Bool {
  let mut found_idx = -1
  for i in 0..<arr.length() {
    if arr[i] == value {
      found_idx = i
      break
    }
  }
  if found_idx >= 0 {
    let last = arr.length() - 1
    if found_idx != last {
      arr[found_idx] = arr[last]
    }
    let _ = arr.pop()
    true
  } else {
    false
  }
}

///|
/// Remove a NumEntry by id from an array using swap-and-pop
/// Returns true if the entry was found and removed
pub fn remove_num_entry_swap(arr : Array[NumEntry], id : Int64) -> Bool {
  let mut found_idx = -1
  for i in 0..<arr.length() {
    if arr[i].id == id {
      found_idx = i
      break
    }
  }
  if found_idx >= 0 {
    let last = arr.length() - 1
    if found_idx != last {
      arr[found_idx] = arr[last]
    }
    let _ = arr.pop()
    true
  } else {
    false
  }
}
