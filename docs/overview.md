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
