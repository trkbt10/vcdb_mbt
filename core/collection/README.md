# core/collection

Collection utilities for top-k search results.

## Functions

- `push_top_k(out, item, k, get_score)`: Insert item into descending top-k result set
- `top_k_heap_push(heap, item, k, get_score)`: Heap-based top-k insertion

## Usage

```moonbit
let results : Array[SearchHit] = []
for hit in candidates {
  push_top_k(results, hit, k, fn(h) { h.score })
}
```

Maintains sorted order (descending by score) and immediately rejects items below the threshold.
