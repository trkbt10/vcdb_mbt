# core/store

CoreStore provides contiguous vector storage with id-to-index mapping.

## Features

- Compact storage: vectors stored in flat `Array[Double]` with strided access
- Automatic normalization for cosine metric
- O(1) compaction on remove via swap-with-last
- Id-to-index mapping for fast lookups

## Usage

```moonbit
let store = CoreStore::new(128, @types.Cosine, capacity=1024)

// Add vector
store.add(id, vector, attrs)

// Get vector at index
let (vec, attrs) = store.get_at(idx)

// Remove by id
store.remove(id)
```
