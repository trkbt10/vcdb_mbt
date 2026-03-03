///|
/// MaxHeap implementation for HNSW search.
/// Uses a binary heap with the largest element at the root.
pub struct MaxHeap[T] {
  data : Array[T]
  compare : (T, T) -> Int // should return > 0 if first > second
}

///|
/// Create a new empty MaxHeap with a comparison function.
/// compare(a, b) should return > 0 if a should be higher priority (larger).
pub fn[T] MaxHeap::new(compare : (T, T) -> Int) -> MaxHeap[T] {
  { data: [], compare }
}

///|
/// Create a MaxHeap for Scored items (by score descending)
pub fn[T : Scored] MaxHeap::for_scored() -> MaxHeap[T] {
  MaxHeap::new(fn(a, b) {
    let sa = a.score()
    let sb = b.score()
    if sa > sb {
      1
    } else if sa < sb {
      -1
    } else {
      0
    }
  })
}

///|
/// Get the number of elements in the heap
pub fn[T] MaxHeap::length(self : MaxHeap[T]) -> Int {
  self.data.length()
}

///|
/// Check if the heap is empty
pub fn[T] MaxHeap::is_empty(self : MaxHeap[T]) -> Bool {
  self.data.is_empty()
}

///|
/// Peek at the maximum element without removing it
pub fn[T] MaxHeap::peek(self : MaxHeap[T]) -> T? {
  if self.data.is_empty() {
    None
  } else {
    Some(self.data[0])
  }
}

///|
/// Push an element onto the heap
pub fn[T] MaxHeap::push(self : MaxHeap[T], item : T) -> Unit {
  self.data.push(item)
  self.sift_up(self.data.length() - 1)
}

///|
/// Pop the maximum element from the heap
pub fn[T] MaxHeap::pop(self : MaxHeap[T]) -> T? {
  if self.data.is_empty() {
    return None
  }
  if self.data.length() == 1 {
    return self.data.pop()
  }
  let result = self.data[0]
  // Move last element to root
  match self.data.pop() {
    Some(last) => {
      self.data[0] = last
      self.sift_down(0)
    }
    None => ()
  }
  Some(result)
}

///|
/// Sift up element at index to maintain heap property
fn[T] MaxHeap::sift_up(self : MaxHeap[T], idx : Int) -> Unit {
  for i = idx; i > 0; {
    let parent = (i - 1) / 2
    if (self.compare)(self.data[i], self.data[parent]) > 0 {
      // Swap with parent
      let tmp = self.data[i]
      self.data[i] = self.data[parent]
      self.data[parent] = tmp
      continue parent
    } else {
      break
    }
  }
}

///|
/// Sift down element at index to maintain heap property
fn[T] MaxHeap::sift_down(self : MaxHeap[T], idx : Int) -> Unit {
  let len = self.data.length()
  for i = idx {
    let left = 2 * i + 1
    let right = 2 * i + 2
    let mut largest = i
    if left < len && (self.compare)(self.data[left], self.data[largest]) > 0 {
      largest = left
    }
    if right < len && (self.compare)(self.data[right], self.data[largest]) > 0 {
      largest = right
    }
    if largest != i {
      // Swap
      let tmp = self.data[i]
      self.data[i] = self.data[largest]
      self.data[largest] = tmp
      continue largest
    } else {
      break
    }
  }
}

///|
/// Clear all elements from the heap
pub fn[T] MaxHeap::clear(self : MaxHeap[T]) -> Unit {
  self.data.clear()
}
