///|
/// Insert item into a descending Top-K result set in place.
/// Maintains sorted order (descending by score) at all times.
/// Immediately rejects items that do not exceed the current worst score.
/// When k <= 0, no items are inserted.
pub fn[T] push_top_k(
  out : Array[T],
  item : T,
  k : Int,
  get_score : (T) -> Double,
) -> Unit {
  // Guard against non-positive k
  if k <= 0 {
    return
  }
  let item_score = get_score(item)
  let len = out.length()
  if len < k {
    // Find insertion position using binary search on descending array
    let mut lo = 0
    let mut hi = len
    while lo < hi {
      let mid = (lo + hi) / 2
      if get_score(out[mid]) > item_score {
        lo = mid + 1
      } else {
        hi = mid
      }
    }
    // Insert at position lo
    out.push(item) // Add placeholder at end
    for i = len; i > lo; {
      out[i] = out[i - 1]
      continue i - 1
    }
    out[lo] = item
    return
  }
  // out.length() >= k
  let worst_score = get_score(out[len - 1])
  if item_score <= worst_score {
    return
  }
  // Replace worst and bubble up (cache item_score)
  out[len - 1] = item
  for i = len - 1; i > 0; {
    let prev_score = get_score(out[i - 1])
    if item_score <= prev_score {
      break
    }
    out[i] = out[i - 1]
    out[i - 1] = item
    continue i - 1
  }
}

///|
/// Scored trait for items with a score field
pub trait Scored {
  score(Self) -> Double
}

///|
/// Push item keeping array sorted by score descending (insertion sort).
/// If limit is provided, the array is truncated to that length after insertion.
pub fn[T : Scored] push_sorted_desc(
  arr : Array[T],
  item : T,
  limit : Int?,
) -> Unit {
  let item_score = item.score()
  // Find insertion position
  let mut pos = arr.length()
  for i in 0..<arr.length() {
    if item_score > arr[i].score() {
      pos = i
      break
    }
  }
  // Insert at position
  arr.push(item) // Add to end first
  // Shift elements right
  for i = arr.length() - 1; i > pos; {
    arr[i] = arr[i - 1]
    continue i - 1
  }
  arr[pos] = item
  // Truncate if needed
  match limit {
    Some(lim) =>
      if arr.length() > lim {
        // Remove excess elements
        while arr.length() > lim {
          let _ = arr.pop()
        }
      }
    None => ()
  }
}

///|
/// Scored wrapper for SearchHit
pub impl Scored for @types.SearchHit with score(self) -> Double {
  self.score
}

///|
/// Simple scored item for internal use
pub(all) struct ScoredItem {
  idx : Int
  s : Double
} derive(Show)

///|
pub impl Scored for ScoredItem with score(self) -> Double {
  self.s
}

///|
/// Create a scored item
pub fn scored_item(idx : Int, s : Double) -> ScoredItem {
  { idx, s }
}
