# Storage Abstraction - Implementation Summary

## Changes Made

### 1. core/storage/callback.mbt (NEW)
```moonbit
pub struct StorageCallbacks {
  read : (String) -> Bytes
  write : (String, Bytes) -> Unit
  exists : (String) -> Bool
  del : (String) -> Unit
  list : () -> Array[String]
}

pub fn register_callbacks(cb : StorageCallbacks) -> Unit
pub struct CallbackStorage { prefix : String }
pub impl Storage for CallbackStorage
```

Enables external code (TypeScript/JS) to provide storage operations via callbacks.

### 2. core/storage/router.mbt (NEW)
```moonbit
pub enum RouterMode { Single(String) | Distributed(CrushConfig) }
pub struct StorageRouter[S] { mode, storages, index_storage_key }

pub fn StorageRouter::single(storage, key~) -> StorageRouter[S]
pub fn StorageRouter::distributed(config, storages, index_key) -> StorageRouter[S]
pub fn StorageRouter::resolve_target(self, id) -> String
```

Unified abstraction for single and CRUSH-distributed storage.

### 3. core/placement/io.mbt (MODIFIED)
```moonbit
// Changed from MemoryStorage to generic Storage
pub fn[S : Storage] write_segments_from_store(storages : Map[String, S], ...)
pub fn[S : Storage] read_segments_from_manifest(storages : Map[String, S], ...)
pub fn[S : Storage] save_store_distributed(storages : Map[String, S], index : S, ...)
pub fn[S : Storage] load_store_distributed(storages : Map[String, S], index : S, ...)
```

### 4. core/placement/crush.mbt (MODIFIED)
```moonbit
// Generic rebalance function
pub fn[S : Storage] apply_rebalance(plan, storages : Map[String, S])
// Backward compat alias
pub fn apply_rebalance_memory(plan, storages : Map[String, MemoryStorage])
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ External Code (TypeScript/JS)                               │
│   globalThis.__vcdb = { read, write, exists, del, list }    │
└─────────────────────────────────────────────────────────────┘
                          │ FFI
                          ▼
┌─────────────────────────────────────────────────────────────┐
│ core/storage/callback.mbt                                   │
│   register_callbacks() → CallbackStorage                    │
└─────────────────────────────────────────────────────────────┘
                          │ implements
                          ▼
┌─────────────────────────────────────────────────────────────┐
│ Storage trait                                               │
│   read, write, append, atomic_write, del, exists, list      │
└─────────────────────────────────────────────────────────────┘
                          │ used by
                          ▼
┌─────────────────────────────────────────────────────────────┐
│ StorageRouter                                               │
│   Single mode: all → one target                             │
│   Distributed mode: ID → CRUSH → target                     │
└─────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│ CollectionManager / placement/io                            │
│   Uses Storage trait for data/index operations              │
└─────────────────────────────────────────────────────────────┘
```

---

## CRUSH Data Resolution

### Data Segments
```
ID → crush_locate(id, map) → pg, primaries[]
primaries[0] = target storage key
Write: storages[target].write(segment_data_path(base, pg, part), data)
```

### Index/Manifest
```
Always written to index_storage (single target)
- {base}.index       - vector index entries
- {base}.manifest.json - segment locations + CRUSH config
```

---

## Usage Examples

### Single Storage (No CRUSH)
```moonbit
let storage = MemoryStorage::new()
let router = StorageRouter::single(storage)

// Or with CallbackStorage for external backend
register_callbacks({ read: ffi_read, write: ffi_write, ... })
let storage = CallbackStorage::new()
```

### Distributed Storage (CRUSH)
```moonbit
let config = CrushConfig::new(32, 2, [
  StorageTarget::new("bucket-a"),
  StorageTarget::new("bucket-b"),
])
let storages : Map[String, MemoryStorage] = {}
storages.set("bucket-a", MemoryStorage::new())
storages.set("bucket-b", MemoryStorage::new())

let router = StorageRouter::distributed(config, storages, "bucket-a")

// Resolve target for a vector ID
let target = router.resolve_target(vector_id)
```

---

## Test Results

All 425 tests pass after changes.
