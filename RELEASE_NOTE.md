# vcdb 0.3.1 Release Notes

## Highlights

Compatibility release for the current MoonBit toolchain, plus fixes and features accumulated since 0.3.0 shipped.

## Toolchain & Packaging

- **Build restored on current moon (0.1.20260713+).** `moonbitlang/async` bumped 0.16.7 → 0.19.4; the previously pinned 0.16.7 no longer compiles against the current core, which also broke downstream consumers of the published 0.3.0 package.
- **Manifest migrated to `moon.mod` (TOML)** from `moon.mod.json`.
- **`core/distributed` whitebox tests follow the `*_wbtest.mbt` naming convention**, so they are no longer compiled into dependent builds (the published 0.3.0 shipped a bare `wbtest.mbt` that failed to compile in dependents on the current toolchain).
- Formatting and generated interfaces refreshed with current `moon fmt` / `moon info`.

## Fixes

- **WAL**: accept v3 header in `read_wal_version` so real v3 WAL files decode; cross-version WAL migration test harness built from real historical encoders.
- **CRUSH**: `crush_placement_group` returns the target index (not the raw PG number); FFI placement fix; `select_read_targets` dedup; `TargetKey` type safety.
- **pg**: BigInt-based float8 decimal conversion for PostgreSQL-compatible output (extracted as `pg/ryu`).

## Features

- Version-aware byte reading with `BinaryReader::peek_byte`.
- Persistent data source support; D1 storage adapter.
- JS-native `DistributedDB` with `ShardTransport` interface; `vcdb/wasm` export path for static bundler imports.
- VSCode plugin with webview bridge; web-dashboard restructured into workspace packages (`@vcdb/vcdb-features` extracted).

---

# vcdb 0.3.0 Release Notes

## Highlights

vcdb 0.3.0 establishes VectorId as the single source of truth (SoT) across every layer of the system. 128-bit IDs (UUID/ULID) are now fully operational for all operations — add, upsert, search, filter, remove, serialize, and deserialize. The npm package has been restructured as `vcdb` with a clean public API that hides FFI internals.

## Breaking Changes

### MoonBit Core
- **`VectorId::to_int64()` removed.** This method aborted on Bytes16Id and was a SoT violation. Use `VectorId::as_int64() -> Int64?` (safe) or pattern match directly. All internal code now uses VectorId natively as Map keys, comparison operands, and serialization subjects.
- **WAL format bumped to v4.** New records use length-prefixed wire bytes for VectorId. Reads v1/v2/v3 WAL segments for backward compatibility. merge_wal re-encodes all records in v4 format.
- **Snapshot format v2.** VectorDB::serialize now writes a magic header ("VCDB" + version 2). Reads legacy headerless snapshots for backward compatibility.
- **CoreStore format v2.** Serialization uses magic header ("STOR" + version 2) with wire-bytes VectorId. Reads legacy tag-byte format for backward compatibility.
- **BPTree attr index format v2.** Posting lists and data maps use wire-bytes VectorId. Reads v1 (fixed 8-byte Int64) for backward compatibility.
- **IVF format v2.** Magic marker "IVF2" + wire-bytes posting lists. Reads legacy format for backward compatibility.
- **Segment format/index v2.** Length-prefixed wire bytes for VectorId in data records and index entries. Reads v1 (fixed 8-byte) for backward compatibility.
- **Gateway response types.** `SearchHitResponse`, `PointResponse`, `ScrollPointResponse` id fields changed from `Int64` to `VectorId`. JSON serializes Int64Id as number, Bytes16Id as hex string.
- **Gateway scroll semantics.** `next_page_offset` now returns the last returned ID (not last_id + 1). Both `scroll()` and `scroll_filtered()` use strictly-greater-than (`>`) offset semantics uniformly for Int64Id and Bytes16Id.
- **`remove_int64_swap` renamed to `remove_vectorid_swap`.**
- **`NumEntry.id` type changed from `Int64` to `VectorId`.**

### npm Package (`vcdb`)
- **Package renamed** from `@vcdb/server` to `vcdb`.
- **`PersistentDB` constructor is now private.** Use `PersistentDB.create(options)` static factory. The `ffi` parameter is removed — FFI is resolved internally.
- **`PersistentDBOptions.instanceId` is optional.** If omitted, allocated by MoonBit runtime via `persistent_allocate_id()`. Explicit IDs remain supported for Durable Object stable-ID patterns.
- **Distributed functions no longer take `ffi` parameter.** `placementGroup()`, `groupUpsert()`, `mergeSearch()`, `mergeScroll()`, `mergeCount()` resolve FFI internally.
- **`registerPersistentStorage` and `initPersistentDB` removed.** Replaced by `PersistentDB.create()` which handles registration and initialization.
- **`hono` and `@hono/node-server` moved to `peerDependencies`** (optional). Only needed for `vcdb/server` subpath.
- **`bun.d.ts` removed.** No Bun-specific type declarations.
- **Internal FFI paths (`vcdb/ffi/types`, `vcdb/wasm/lib.js`) are not in the exports map.** Use the public API only.

## New Features

### Bytes16Id (UUID/ULID) Full Support
- All database operations work with 128-bit IDs: add, upsert, get, search, has, remove, scroll, filter, serialize/deserialize.
- Mixed Int64Id and Bytes16Id coexist in the same database.
- `VectorId::from_uuid_string()` parses UUID strings with or without hyphens.
- Wire format: 16-byte fixed representation. Int64Id uses bytes 0-7 (big-endian) + 8 zero bytes. Bytes16Id uses all 16 bytes.

### VectorId as SoT
- Every serialization layer uses `VectorId::to_wire_bytes()` / `VectorId::from_wire_bytes()` — a single canonical path.
- All Map/Set keys use `VectorId` directly (Hash + Eq traits). No intermediate Int64 conversion.
- All comparisons use `VectorId::compare()` directly.
- Adding a new VectorId variant requires only updating `to_wire_bytes`/`from_wire_bytes` in `core/types/types.mbt`.

### npm Package Structure
- Subpath exports: `vcdb`, `vcdb/server`, `vcdb/distributed`, `vcdb/gateway`, `vcdb/storage/*` (10 adapters).
- `AsyncStorageCallbacks` exported from public API.
- `loadModule()` required before any database operation. `PersistentDB.create()` and distributed functions throw clear function-specific errors if called before `loadModule()`.

### Safety
- `BinaryReader`: bounds checking (`ensure()`) on all read operations and `skip()`. Corrupted length prefixes abort with clear offset/need/len diagnostic message.
- Instance ID allocation: monotonic counter in MoonBit runtime (`persistent_allocate_id()`), not JS-side random. SoT for instance identity.

## Bug Fixes

### HNSW
- **Tombstoned entry point search** (`hnsw/tombstoned_entrypoint_search_still_works`): search correctly skips tombstoned entry point and finds remaining live nodes.
- **Add after all tombstoned** (`hnsw/add_after_all_tombstoned`): new node added after all existing nodes are tombstoned becomes reachable.
- **Remove bridge then add nearby** (`hnsw/remove_bridge_then_add_nearby_reachable`): tombstoning a bridge node then adding a nearby node preserves graph connectivity.
- **Fallback entry point must not pick inserting node** (`hnsw/fallback_ep_must_not_pick_inserting_node`): prevents disconnected entry point promotion.

### Serialization
- Backward-compatible deserialization for all format versions (WAL v1-v4, BPTree v1-v2, IVF v1-v2, CoreStore v1-v2, Segment v1-v2, Snapshot v1-v2).
- IVF version detection: magic marker "IVF2" (`0x49564632`) eliminates collision with `centroid_count==2` in legacy format.

### Gateway
- `as_int64().unwrap()` panic on Bytes16Id replaced with VectorId-native response types.
- `scroll_filtered` used directly for offset handling — eliminates asymmetric Int64Id-minus-1 hack.

## Test Coverage

- MoonBit wasm-gc: 613 tests
- MoonBit js: 629 tests (includes FFI layer)
- JS smoke: all pass
- JS contract: 48 tests
- Bytes16Id-specific tests across: attr (BPTree, Basic, Bitmap, LSM), ann (Bruteforce, HNSW, IVF), filter, FFI, mixed Int64Id+Bytes16Id coexistence, serialize/deserialize round-trips.

## CI

- Added `moon check --target js` and `moon test --target js` to CI pipeline.
- TypeScript type check and `npm pack --dry-run` validation in CI.

## Internal Changes

- `ids_to_vector_ids` helper removed (no longer needed).
- All `Map[Int64, ...]` keys replaced with `Map[VectorId, ...]` across attr, ann, filter, distributed, persistence layers (95+ call sites).
- merge_wal now re-encodes all records in current format (no byte-copy of old format headers).
- Dead code `get_safe_copy_length` removed.
- `flag_has_128bit_id` deprecated (WAL v3 only, not used in v4).

---

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
