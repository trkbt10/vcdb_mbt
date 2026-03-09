# Distributed Storage & Single-File Mode

vcdb supports two independent persistence paths that can interoperate.

## Persistence Paths

### 1. Single-File Mode (Simple)

Serialize entire database to a single `Bytes`:

```moonbit
// Save
let bytes = db.serialize()
@fs.write_bytes_to_file("db.bin", bytes)

// Load
let bytes = @fs.read_bytes_from_file("db.bin")
let db = VectorDB::deserialize(bytes)
```

Contents:
- Strategy type and params (HNSW/IVF/Bruteforce)
- CoreStore (all vectors + attributes)
- ANN index state (HNSW graph, IVF centroids)
- Attribute index (B+ tree metadata)

### 2. Distributed Mode (CRUSH)

Route data to multiple storage backends using CRUSH algorithm:

```moonbit
import "trkbt10/vcdb/core/placement"
import "trkbt10/vcdb/core/storage"

// Setup CRUSH map
let targets = [
  CrushTarget::new("s3-bucket-1"),
  CrushTarget::new("s3-bucket-2"),
]
let crush = CrushMap::new(pgs=32, replicas=2, targets)

// Save with distributed placement
let opts = SegmentOptions::default("mydb", crush)
let manifest = save_store_distributed_with_ann(
  db.store(),
  opts,
  data_storages,    // Map[String, Storage] for vector data
  index_storage,    // Storage for index/manifest
  db.strategy,
  ann_bytes,        // Serialized ANN state
)

// Load from distributed storage
let result = load_store_distributed_full("mydb", data_storages, index_storage)
let db = VectorDB::from_store(result.store, options)
```

StorageKind routing:
- `Config` - Collection configuration
- `Index` - Index structures, manifests
- `Data` - Vector segments

## Interoperability

| Direction | Supported | Notes |
|-----------|-----------|-------|
| Single-File -> Distributed | Yes | Use `db.store()` to extract CoreStore, then `save_store_distributed_with_ann()` |
| Distributed -> Single-File | Yes | Load with `load_store_distributed_full()`, rebuild with `VectorDB::from_store()`, then `serialize()` |

### Migration: Single-File to Distributed

```moonbit
// Load from single file
let bytes = @fs.read_bytes_from_file("db.bin")
let db = VectorDB::deserialize(bytes)

// Save to distributed storage
let crush = CrushMap::new(32, 2, targets)
let opts = SegmentOptions::default("mydb", crush)
let ann_bytes = match db.hnsw {
  Some(state) => Some(@ann.hnsw_serialize(state))
  None => None
}
save_store_distributed_with_ann(
  db.store(), opts, storages, index_storage, db.strategy, ann_bytes
)
```

### Migration: Distributed to Single-File

```moonbit
// Load from distributed storage
let result = load_store_distributed_full("mydb", storages, index_storage)

// Rebuild VectorDB
let options = DatabaseOptions::{ dim: result.header.dim, ... }
let db = VectorDB::from_store(result.store, options)

// Save to single file
let bytes = db.serialize()
@fs.write_bytes_to_file("db.bin", bytes)
```

**Note**: When converting from distributed to single-file, the HNSW graph is rebuilt from scratch. This cleans up tombstones but discards the original graph structure. Search accuracy remains equivalent.

## When to Use Each Mode

| Mode | Use Case |
|------|----------|
| Single-File | Embedded use, CLI tools, simple deployments, development |
| Distributed | Production with S3/DynamoDB, horizontal scaling, fault tolerance |

Single-file mode works independently without any distributed infrastructure. You can start with single-file and migrate to distributed later when needed.
