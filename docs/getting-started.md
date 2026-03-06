## Getting Started

```moonbit
// Create a collection with HNSW index
let store = @vcdb.CoreStore::new()
let collection = store.create_collection("my_vectors", dim=128, ann_type=HNSW)

// Add vectors with optional attributes
collection.upsert([
  { id: "vec1", vector: [...], attrs: { "category": "A" } },
  { id: "vec2", vector: [...], attrs: { "category": "B" } },
])

// Search with filtering
let results = collection.search(
  query_vector,
  top_k=10,
  filter={ "category": "A" }
)
```
