# vcdb

Minimal, dependency-free vector database with pluggable ANN strategies (bruteforce, HNSW, IVF), attribute filtering, and persistence. Powered by MoonBit WASM. Runs in Node.js, browsers, and edge runtimes.

## Install

```bash
npm install vcdb
```

## Quick Start

```typescript
import { loadModule, VectorDB } from "vcdb";

// Load the WASM module (required once before any operation)
await loadModule();

// Create an in-memory vector database
const db = new VectorDB(4); // 4-dimensional vectors

// Add vectors
db.add(1n, [1.0, 0.0, 0.0, 0.0]);
db.add(2n, [0.0, 1.0, 0.0, 0.0]);
db.add(3n, [0.5, 0.5, 0.0, 0.0]);

// Search
const results = db.search([1.0, 0.0, 0.0, 0.0], 2);
// [{ id: 1n, score: 1.0 }, { id: 3n, score: 0.707 }]

db.dispose();
```

## Persistent Database

```typescript
import { loadModule, PersistentDB } from "vcdb";
import { createMemoryStorage } from "vcdb/storage/memory";

await loadModule();

const storage = createMemoryStorage();

const db = await PersistentDB.create({
  dim: 128,
  capacity: 10000,
  metric: "cosine",
  strategy: "hnsw",
  walStorage: kvStoreToCallbacks(storage),
  snapshotStorage: kvStoreToCallbacks(storage),
});

await db.upsert([
  { id: 1n, vector: [...], payload: { title: "hello" } },
]);

const hits = db.search([...], 10);
```

## VectorId

Vector IDs are `bigint` values (Int64 range). The wire format is a fixed 16-byte `Uint8Array`, supporting both Int64Id and 128-bit Bytes16Id (UUID/ULID).

```typescript
// Int64Id — use bigint directly
db.add(42n, vector);

// Bytes16Id (UUID) — supported at the WASM level
// Use VectorId::from_uuid_string() on the MoonBit side
```

## Subpath Exports

| Import path | Description |
|---|---|
| `vcdb` | Core: VectorDB, PersistentDB, types, loadModule |
| `vcdb/server` | HTTP server (requires `hono` peer dependency) |
| `vcdb/distributed` | Distributed merge, CRUSH placement |
| `vcdb/gateway` | Gateway API bridge |
| `vcdb/storage/memory` | In-memory storage adapter |
| `vcdb/storage/node` | Node.js filesystem storage |
| `vcdb/storage/indexeddb` | IndexedDB storage (browser) |
| `vcdb/storage/opfs` | Origin Private File System (browser) |
| `vcdb/storage/local-storage` | LocalStorage adapter |
| `vcdb/storage/service-worker` | Service Worker cache storage |
| `vcdb/storage/cached` | Write-back caching wrapper |
| `vcdb/storage/r2` | Cloudflare R2 storage |
| `vcdb/storage/do-kv` | Cloudflare Durable Objects KV |

## ANN Strategies

- **Bruteforce** — exact search, no index overhead
- **HNSW** — approximate search, fast for large datasets
- **IVF** — inverted file index, memory-efficient

## Peer Dependencies

`hono` and `@hono/node-server` are optional peer dependencies, required only when using `vcdb/server`.

## License

Apache-2.0
