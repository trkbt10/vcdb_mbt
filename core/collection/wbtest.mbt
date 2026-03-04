// Whitebox tests for collection module

///|
test "topk/push_top_k" {
  let out : Array[ScoredItem] = []
  push_top_k(out, scored_item(0, 1.0), 3, fn(x) { x.s })
  push_top_k(out, scored_item(1, 3.0), 3, fn(x) { x.s })
  push_top_k(out, scored_item(2, 2.0), 3, fn(x) { x.s })
  push_top_k(out, scored_item(3, 5.0), 3, fn(x) { x.s })
  push_top_k(out, scored_item(4, 0.5), 3, fn(x) { x.s })
  // Should have [5.0, 3.0, 2.0] (top 3)
  inspect(out.length(), content="3")
  inspect(out[0].s, content="5")
  inspect(out[1].s, content="3")
  inspect(out[2].s, content="2")
}

///|
test "heap/max_heap" {
  let heap : MaxHeap[ScoredItem] = MaxHeap::for_scored()
  heap.push(scored_item(0, 1.0))
  heap.push(scored_item(1, 5.0))
  heap.push(scored_item(2, 3.0))
  inspect(heap.length(), content="3")
  // Pop should return highest first
  let top = heap.pop()
  inspect(top.unwrap().s, content="5")
  let next = heap.pop()
  inspect(next.unwrap().s, content="3")
}

///|
/// Test: MaxHeap peek and is_empty
test "heap/peek_is_empty" {
  let heap : MaxHeap[ScoredItem] = MaxHeap::for_scored()
  inspect(heap.is_empty(), content="true")
  inspect(heap.peek() is None, content="true")
  heap.push(scored_item(1, 5.0))
  inspect(heap.is_empty(), content="false")
  match heap.peek() {
    Some(item) => inspect(item.s, content="5")
    None => inspect(false, content="true")
  }
  // Peek doesn't remove
  inspect(heap.length(), content="1")
}

///|
/// Test: MaxHeap clear
test "heap/clear" {
  let heap : MaxHeap[ScoredItem] = MaxHeap::for_scored()
  heap.push(scored_item(1, 1.0))
  heap.push(scored_item(2, 2.0))
  heap.push(scored_item(3, 3.0))
  inspect(heap.length(), content="3")
  heap.clear()
  inspect(heap.length(), content="0")
  inspect(heap.is_empty(), content="true")
}

///|
/// Test: MaxHeap pop order with many elements
test "heap/pop_order" {
  let heap : MaxHeap[ScoredItem] = MaxHeap::for_scored()
  // Push in random order
  heap.push(scored_item(1, 3.0))
  heap.push(scored_item(2, 1.0))
  heap.push(scored_item(3, 4.0))
  heap.push(scored_item(4, 1.5))
  heap.push(scored_item(5, 5.0))
  heap.push(scored_item(6, 2.0))
  // Pop should return in descending order
  let p1 = heap.pop()
  inspect(p1.unwrap().s, content="5")
  let p2 = heap.pop()
  inspect(p2.unwrap().s, content="4")
  let p3 = heap.pop()
  inspect(p3.unwrap().s, content="3")
  let p4 = heap.pop()
  inspect(p4.unwrap().s, content="2")
  let p5 = heap.pop()
  inspect(p5.unwrap().s, content="1.5")
  let p6 = heap.pop()
  inspect(p6.unwrap().s, content="1")
  // Empty
  inspect(heap.pop() is None, content="true")
}

///|
/// Test: MaxHeap with custom compare
test "heap/custom_compare" {
  // Min heap by using negative comparison
  let heap : MaxHeap[Int] = MaxHeap::new(fn(a, b) {
    if a < b {
      1
    } else if a > b {
      -1
    } else {
      0
    }
  })
  heap.push(5)
  heap.push(1)
  heap.push(3)
  // Should pop smallest first (min heap)
  inspect(heap.pop().unwrap(), content="1")
  inspect(heap.pop().unwrap(), content="3")
  inspect(heap.pop().unwrap(), content="5")
}

///|
/// Test: push_top_k with k <= 0 (P2 fix)
/// Should not crash and should not insert any items
test "topk/push_top_k_zero_k" {
  let out : Array[ScoredItem] = []
  // k = 0 should not insert anything
  push_top_k(out, scored_item(0, 1.0), 0, fn(x) { x.s })
  push_top_k(out, scored_item(1, 2.0), 0, fn(x) { x.s })
  inspect(out.length(), content="0")
  // k = -1 should also not insert anything
  push_top_k(out, scored_item(2, 3.0), -1, fn(x) { x.s })
  inspect(out.length(), content="0")
}

///|
/// Test: push_top_k with k = 1 (boundary case)
test "topk/push_top_k_k_equals_one" {
  let out : Array[ScoredItem] = []
  push_top_k(out, scored_item(0, 1.0), 1, fn(x) { x.s })
  inspect(out.length(), content="1")
  push_top_k(out, scored_item(1, 2.0), 1, fn(x) { x.s })
  inspect(out.length(), content="1")
  inspect(out[0].s, content="2") // Higher score should replace
  push_top_k(out, scored_item(2, 0.5), 1, fn(x) { x.s })
  inspect(out.length(), content="1")
  inspect(out[0].s, content="2") // Lower score should not replace
}
