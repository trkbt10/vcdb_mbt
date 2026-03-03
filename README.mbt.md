# vcdb

[![CI](https://github.com/trkbt10/vcdb/actions/workflows/ci.yml/badge.svg)](https://github.com/trkbt10/vcdb/actions/workflows/ci.yml)
[![Coverage Status](https://coveralls.io/repos/github/trkbt10/vcdb/badge.svg?branch=main)](https://coveralls.io/github/trkbt10/vcdb?branch=main)

A high-performance vector database written in MoonBit.

## Features

- **Multiple ANN Algorithms**: Bruteforce, HNSW, IVF
- **Similarity Metrics**: Cosine, Dot Product, L2 (Euclidean)
- **Attribute Filtering**: Pre-filter and post-filter strategies
- **Attribute Indexes**: Basic, Bitmap, B+Tree, LSM
- **Persistence**: WAL (Write-Ahead Logging), CRUSH placement
- **Filter Expressions**: Must, MustNot, Should, Exists, Range

## Installation

```bash
moon add trkbt10/vcdb
```

## Quick Start

```moonbit nocheck
// Create a vector database with HNSW index
let db = @vcdb.VectorDB::with_hnsw(128, metric=@core.Cosine)

// Add vectors
db.add(@core.VectorId::from_int(1), embedding, attrs)

// Search for nearest neighbors
let results = db.search(query, k=10, filter=None)
```

## License

Apache-2.0
