///|
/// Benchmark: push_top_k small k (k=10, 100 items)
test "bench/topk_push_k10" (b : @bench.T) {
  let scores : Array[Double] = []
  for i in 0..<100 {
    scores.push((i * 17 % 100).to_double() / 100.0)
  }
  b.bench(fn() {
    let out : Array[Double] = []
    for s in scores {
      push_top_k(out, s, 10, fn(x) { x })
    }
    b.keep(out.length())
  })
}

///|
/// Benchmark: push_top_k larger k (k=50, 200 items)
test "bench/topk_push_k50" (b : @bench.T) {
  let scores : Array[Double] = []
  for i in 0..<200 {
    scores.push((i * 31 % 200).to_double() / 200.0)
  }
  b.bench(fn() {
    let out : Array[Double] = []
    for s in scores {
      push_top_k(out, s, 50, fn(x) { x })
    }
    b.keep(out.length())
  })
}

///|
/// Benchmark: push_top_k worst case (descending input)
test "bench/topk_worst_case" (b : @bench.T) {
  let scores : Array[Double] = []
  for i in 0..<100 {
    scores.push((100 - i).to_double())
  }
  b.bench(fn() {
    let out : Array[Double] = []
    for s in scores {
      push_top_k(out, s, 10, fn(x) { x })
    }
    b.keep(out.length())
  })
}

///|
/// Benchmark: push_top_k best case (ascending input)
test "bench/topk_best_case" (b : @bench.T) {
  let scores : Array[Double] = []
  for i in 0..<100 {
    scores.push(i.to_double())
  }
  b.bench(fn() {
    let out : Array[Double] = []
    for s in scores {
      push_top_k(out, s, 10, fn(x) { x })
    }
    b.keep(out.length())
  })
}

///|
/// Benchmark: push_top_k with ScoredItem
test "bench/topk_scored_item" (b : @bench.T) {
  let items : Array[ScoredItem] = []
  for i in 0..<100 {
    items.push(scored_item(i, (i * 23 % 100).to_double()))
  }
  b.bench(fn() {
    let out : Array[ScoredItem] = []
    for item in items {
      push_top_k(out, item, 10, fn(x : ScoredItem) { x.s })
    }
    b.keep(out.length())
  })
}

///|
/// Benchmark: push_sorted_desc
test "bench/push_sorted_desc" (b : @bench.T) {
  let items : Array[ScoredItem] = []
  for i in 0..<50 {
    items.push(scored_item(i, (i * 17 % 50).to_double()))
  }
  b.bench(fn() {
    let out : Array[ScoredItem] = []
    for item in items {
      push_sorted_desc(out, item, Some(20))
    }
    b.keep(out.length())
  })
}

///|
/// Benchmark: MaxHeap push 100 items
test "bench/maxheap_push_100" (b : @bench.T) {
  let items : Array[ScoredItem] = []
  for i in 0..<100 {
    items.push(scored_item(i, (i * 19 % 100).to_double()))
  }
  b.bench(fn() {
    let heap : MaxHeap[ScoredItem] = MaxHeap::for_scored()
    for item in items {
      heap.push(item)
    }
    b.keep(heap.length())
  })
}

///|
/// Benchmark: MaxHeap push and pop
test "bench/maxheap_push_pop" (b : @bench.T) {
  let items : Array[ScoredItem] = []
  for i in 0..<100 {
    items.push(scored_item(i, (i * 19 % 100).to_double()))
  }
  b.bench(fn() {
    let heap : MaxHeap[ScoredItem] = MaxHeap::for_scored()
    for item in items {
      heap.push(item)
    }
    let mut count = 0
    while heap.pop() is Some(_) {
      count = count + 1
    }
    b.keep(count)
  })
}

///|
/// Benchmark: MaxHeap interleaved push/pop (simulating search)
test "bench/maxheap_interleaved" (b : @bench.T) {
  let items : Array[ScoredItem] = []
  for i in 0..<100 {
    items.push(scored_item(i, (i * 23 % 100).to_double()))
  }
  b.bench(fn() {
    let heap : MaxHeap[ScoredItem] = MaxHeap::for_scored()
    let mut popped = 0
    for i, item in items {
      heap.push(item)
      if i > 0 && i % 10 == 0 {
        let _ = heap.pop()
        popped = popped + 1
      }
    }
    b.keep(heap.length() + popped)
  })
}
