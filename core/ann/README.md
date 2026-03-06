# core/ann

Approximate Nearest Neighbor (ANN) search algorithms.

## Algorithms

- **Bruteforce**: Exact nearest neighbor search via linear scan
- **HNSW**: Hierarchical Navigable Small World graph for logarithmic search complexity
- **IVF**: Inverted File Index with clustering for large-scale datasets

## Usage

```moonbit
// Create HNSW state
let params = @types.HNSWParams::default()
let state = HNSWState::new(params, @types.Cosine, 1024)

// Add vector (returns assigned level)
let level = state.add(0, store, dim)

// Search for k nearest neighbors
let results = state.search(query, k, store, dim)
```

## Key Types

- `HNSWState`: HNSW graph state with configurable M and ef parameters
- `IVFState`: IVF index with nlist clusters and nprobe search parameter
