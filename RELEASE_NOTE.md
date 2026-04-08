# vcdb 0.2.0 Release Notes

## Highlights

vcdb 0.2.0 introduces distributed database primitives, a restructured persistence layer, and comprehensive safety improvements across the FFI boundary.

## Breaking Changes

- **`PersistentDB::add` returns `Bool`** instead of `Unit`. Returns `false` when the ID already exists, preventing orphaned WAL records.
- **`VectorDB` renamed to internal engine**. The public API is now `PersistentDB[W, S]` which wraps the engine with WAL-before-state guarantees.
- **Gateway `JsonValue` removed**. All gateway types now use the standard `Json` type from MoonBit core.
- **CLI `ParsedArgs` removed**. CLI now uses `moonbitlang/core/argparse` directly.
- **`lib/` package removed**, replaced by `ffi/` with a cleaner FFI export structure.

## New Features

### Distributed Database Primitives (`core/distributed`)
- `DistributedDB[T]` — scatter-gather query execution across shards
- Quorum reads/writes with configurable N/W/R parameters
- Shard health tracking with automatic failure detection
- WAL shipping and replication state management
- LWW (Last-Write-Wins) conflict resolution for divergent WALs
- Partition state tracking and recovery planning

### CRUSH Placement (`core/placement`)
- Async rebalancing with move plan generation and progress tracking
- `async_apply_rebalance` for live data migration between shards

### Storage Enhancements (`core/storage`)
- `ReplicatedStorage[T]` — quorum-based replicated storage
- `JsAsyncCallbackStorage` — Promise-based async storage for JS environments
- `KindAwareStorage` — storage routing by data kind (config/index/data)
- Cloudflare R2 and Durable Objects storage adapters (JS/TypeScript)

### Persistence
- `PersistentDB::from_snapshot` — restore from snapshot bytes with explicit storage backends
- `PersistentDB::in_memory` / `in_memory_hnsw` / `in_memory_ivf` / `in_memory_bruteforce` — convenience constructors
- WAL v2 format with timestamp support
- Auto-checkpoint by record count and byte size thresholds

### Gateway
- `dump` and `load` CLI subcommands for snapshot management (native target)
- `CollectionManager` now supports persistent storage backends
- `export_jsonl` for VectorDB data export

### FFI (`ffi/`)
- Complete JS FFI surface with 44 exported functions
- Split Int64 encoding (hi/lo pairs) for WASM interop
- Distributed merge operations exposed for JS consumers

### Types
- `Metric::from_name` / `to_name` for string-based metric selection
- `Strategy::from_name` / `to_name` for string-based strategy selection
- `TransportPoint` with JSONL serialization

## Bug Fixes

- **PersistentDB::add WAL ordering**: existence check now runs before WAL append, preventing orphaned records when adding duplicate IDs
- **FFI abort on invalid input**: `parse_metric_name`/`parse_strategy_name` now raise errors that propagate as Promise rejects instead of crashing the WASM module
- **FFI uninitialized instance**: `get_persistent_db` returns proper errors instead of aborting; sync read functions return safe defaults
- **Gateway catch-all abort**: four `abort(e.to_string())` in `CollectionManager` methods replaced with `Err(StorageError(...))`
- **Storage callback abort**: `JsAsyncCallbackStorage` returns error via `reject` callback instead of aborting when callbacks are not registered
- **Placement decode abort**: `async_load_segmented` raises `AsyncIOFailed` on decode failures instead of aborting
- Removed unused `json_null()` function
- Fixed deprecated `as @alias` import syntax

## Internal Changes

- Restructured from `lib/` to `ffi/` for clearer FFI boundary separation
- VectorDB tests migrated to use PersistentDB facade
- Segment construction and loading refactored for clarity
- Gateway JSON handling unified on standard `Json` type
