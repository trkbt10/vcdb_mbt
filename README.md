# vcdb

[![CI](https://github.com/trkbt10/vcdb/actions/workflows/ci.yml/badge.svg)](https://github.com/trkbt10/vcdb/actions/workflows/ci.yml)

A high-performance vector database written in MoonBit for approximate nearest neighbor (ANN) search.

## Features

- **Multiple ANN Algorithms**
  - **Bruteforce**: Exact linear scan, best for small datasets (<1000 vectors)
  - **HNSW**: Hierarchical Navigable Small World graphs, O(log n) search
  - **IVF**: Inverted File Index with k-means clustering for large datasets

- **Similarity Metrics**
  - Cosine similarity (default, vectors auto-normalized)
  - Dot product
  - L2 (Euclidean) distance

- **Attribute Filtering**
  - Pre-filter: Use attribute index for selective queries
  - Post-filter: Filter after scoring
  - Auto: Automatically choose based on selectivity

- **Attribute Indexes**
  - Basic: Hash map based, good for equality queries
  - Bitmap: For low-cardinality fields
  - B+Tree: Balanced tree for range queries
  - LSM: Write-optimized with memtable

- **Persistence**
  - WAL (Write-Ahead Logging) for durability
  - Binary serialization for snapshots
  - CRUSH algorithm for distributed placement

- **Filter Expressions**
  - `Must`: All conditions must match (AND)
  - `MustNot`: None of the conditions can match
  - `Should(min)`: At least min conditions must match (OR)
  - Leaf predicates: `Match`, `Range`, `Exists`, `IsNull`

## Installation

```bash
moon add trkbt10/vcdb
```

## Quick Start

```moonbit
// Create a vector database with HNSW index (recommended)
let db = @vcdb.VectorDB::with_hnsw(128, metric=@core.Cosine)

// Add vectors with attributes
let attrs = @vcdb.empty_attrs()
attrs.set("category", @core.String("electronics"))
attrs.set("price", @core.Float(299.99))
db.add(@core.VectorId::from_int(1), embedding, attrs)

// Search for nearest neighbors
let results = db.search(query_vector, k=10, filter=None)
for hit in results {
  println("ID: \{hit.id}, Score: \{hit.score}")
}
```

## API Reference

### VectorDB

The main facade for all database operations.

```moonbit
// Creation
VectorDB::with_dim(dim: Int) -> VectorDB           // Bruteforce (default)
VectorDB::with_hnsw(dim: Int, metric?: Metric)     // HNSW (recommended)
VectorDB::with_ivf(dim: Int, metric?: Metric)      // IVF (large datasets)
VectorDB::new(options: DatabaseOptions)            // Full control

// Basic operations
db.add(id, vector, attrs)         // Add new vector
db.upsert(id, vector, attrs)      // Add or update
db.remove(id) -> Bool             // Remove by ID
db.get(id) -> VectorRecord?       // Get by ID
db.has(id) -> Bool                // Check existence
db.size() -> Int                  // Count vectors

// Search
db.search(query, k, filter?) -> Array[SearchHit]
db.find(query, filter?) -> SearchHit?              // Single best match
db.search_with_expr(query, k, expr, index, strategy)

// Maintenance
db.train(iterations?)             // Train IVF centroids
db.update_attrs(id, attrs)        // Update attributes only

// Persistence
db.serialize() -> Bytes
VectorDB::deserialize(data: Bytes) -> VectorDB
```

### Similarity Metrics

```moonbit
@core.Cosine  // Cosine similarity [-1, 1], vectors auto-normalized
@core.Dot     // Dot product, higher = more similar
@core.L2      // Euclidean distance, lower = more similar (returned as negative)
```

### Filter Expressions

```moonbit
// Leaf predicates
@filter.Match("category", @core.String("electronics"))
@filter.Range("price", gt=Some(100.0), lte=Some(500.0))
@filter.Exists("brand")
@filter.IsNull("optional_field")

// Compound expressions
@filter.Must([expr1, expr2])       // AND: all must match
@filter.MustNot([expr1])           // NOT: none can match
@filter.Should([expr1, expr2], 1)  // OR: at least 1 must match
```

### Attribute Index

```moonbit
let index = @attr.BasicAttrIndex::new()
index.set_attrs(id, attrs)
let matches = index.eq("category", @core.String("electronics"))
let range_matches = index.range("price", { gte: Some(100.0), lt: Some(200.0) })
```

## Architecture

```
vcdb/
├── core/           # Core types, storage, and utilities
│   ├── types.mbt   # VectorId, Attrs, Metric, SearchHit
│   ├── store.mbt   # CoreStore: vector and attribute storage
│   ├── binary.mbt  # BinaryWriter/Reader for serialization
│   └── math.mbt    # Vector math (normalization, distance)
│
├── ann/            # ANN algorithm implementations
│   ├── bruteforce.mbt  # Linear scan
│   ├── hnsw.mbt        # Hierarchical NSW
│   ├── ivf.mbt         # Inverted file index
│   └── maintain.mbt    # Compaction utilities
│
├── attr/           # Attribute index implementations
│   ├── basic.mbt   # Hash map based index
│   ├── bitmap.mbt  # Bitmap index
│   ├── bptree.mbt  # B+ tree index
│   ├── lsm.mbt     # LSM tree index
│   └── sstable.mbt # SSTable format for LSM
│
├── filter/         # Filter expression system
│   └── expr.mbt    # FilterExpr compilation
│
├── persistence/    # Durability layer
│   ├── wal.mbt         # Write-ahead log format
│   ├── wal_runtime.mbt # WAL operations
│   ├── storage.mbt     # Storage abstraction
│   └── crush.mbt       # Distributed placement
│
└── vcdb.mbt        # Main VectorDB facade
```

## Algorithm Details

### HNSW (Hierarchical Navigable Small World)

- Multi-layer graph structure for O(log n) search
- Higher layers contain fewer "hub" nodes for fast traversal
- Lower layers provide fine-grained connectivity
- Default parameters: M=16, ef_construction=200, ef_search=50
- Deletions use tombstones to maintain graph connectivity

### IVF (Inverted File Index)

- Partitions vectors into clusters using k-means
- Search probes only the nearest centroids (nprobe)
- Requires training after initial data load
- Default parameters: nlist=100, nprobe=10

### Attribute Indexes

| Index | Best For | Ops | Notes |
|-------|----------|-----|-------|
| Basic | Equality queries | O(1) lookup | Hash map based |
| Bitmap | Low cardinality | Fast set ops | Memory efficient |
| B+Tree | Range queries | O(log n) | Ordered traversal |
| LSM | Write-heavy | O(1) write | Memtable + compaction |

## Performance Tips

1. **Choose the right algorithm**:
   - <1K vectors: Bruteforce is fine
   - 1K-1M vectors: HNSW recommended
   - >1M vectors: Consider IVF with training

2. **Use pre-filtering** when filters are selective (<50% of data)

3. **Tune HNSW parameters**:
   - Higher `M`: Better recall, more memory
   - Higher `ef_search`: Better recall, slower search

4. **Train IVF** after loading representative data

5. **Use cosine metric** unless you have a specific reason not to (auto-normalization handles magnitude differences)

## License

Apache-2.0
