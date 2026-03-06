# vcdb

High-performance vector database with multiple ANN algorithms for MoonBit.

## Features

- **Multiple ANN Algorithms**: HNSW, IVF, and Brute-force search
- **Flexible Storage**: Pluggable backends (memory, S3)
- **Persistence**: WAL-based durability with segment management
- **Attribute Filtering**: Metadata-based vector filtering
- **REST Gateway**: HTTP API for collections and vectors


## Overview

vcdb is structured as a layered architecture:

### Core Layers

| Package | Purpose |
|---------|---------|
| `core/ann` | ANN algorithms (HNSW, IVF, Bruteforce) |
| `core/store` | Vector data storage |
| `core/storage` | Abstract storage interface |
| `core/persistence` | WAL and segment management |
| `core/attr` | Attribute indexing and filtering |

### API Layers

| Package | Purpose |
|---------|---------|
| `gateway` | REST API server |
| `cli` | Command-line interface |
| `lib` | Library entry point |


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


## Usage

### REST API

Start the gateway server:

```bash
moon run cmd/main
```

#### Create Collection

```bash
curl -X POST http://localhost:8080/collections/my_collection \
  -H "Content-Type: application/json" \
  -d '{"dim": 128, "ann_type": "hnsw"}'
```

#### Upsert Vectors

```bash
curl -X PUT http://localhost:8080/collections/my_collection/points \
  -H "Content-Type: application/json" \
  -d '{"points": [{"id": "1", "vector": [...]}]}'
```

#### Search

```bash
curl -X POST http://localhost:8080/collections/my_collection/search \
  -H "Content-Type: application/json" \
  -d '{"vector": [...], "top_k": 10}'
```


## Installation

### From Package Manager

```bash
moon add trkbt10/vcdb
```

### From Source

```bash
git clone https://github.com/trkbt10/vcdb_mbt
cd vcdb_mbt
moon build
```

### Requirements

- MoonBit toolchain (moon >= 0.1.0)


## License

See [LICENSE](LICENSE) for details.
