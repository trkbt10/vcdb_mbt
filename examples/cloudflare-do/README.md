# vcdb on Cloudflare Durable Objects + R2

Production-grade vcdb deployment using Durable Objects for sharded vector storage with R2 snapshot persistence.

Based on production patterns from [usbkr](https://github.com/trkbt10/usbkr).

## Architecture

```
                    ┌──────────────────────────────────────────┐
                    │ Worker                                   │
┌──────────┐       │  ┌─────────────┐                         │     ┌──────────┐
│  Client  │──────▶│  │ ShardRouter │──scatter/gather──▶ DO 0 │────▶│ R2       │
│  (HTTP)  │       │  │  (8 shards) │                   DO 1  │     │ (snaps)  │
└──────────┘       │  └─────────────┘                   ...   │     └──────────┘
                    │                                   DO 7  │
                    └──────────────────────────────────────────┘
```

Each Durable Object shard:
- Hosts an isolated vcdb WASM instance
- Manages its own WAL (Write-Ahead Log) in DO storage
- Snapshots to R2 on checkpoint (every 50 mutations or 100KB WAL)
- Recovers via WAL replay on cold start

## Files

```
examples/cloudflare-do/
├── src/
│   ├── worker.ts           # Worker entry point + HTTP API
│   ├── types.ts            # Shared types, ID conversion
│   ├── vcdb-lib.d.ts       # WASM FFI type declarations
│   └── infra/
│       ├── vcdb-do.ts      # Durable Object — single vcdb shard
│       ├── shard-router.ts # Scatter-gather across DO shards
│       ├── wal-writer.ts   # WAL buffer + checkpoint management
│       └── r2-store.ts     # R2 adapter (DOKeyValueStore interface)
├── wrangler.jsonc
├── package.json
└── tsconfig.json
```

## Key Patterns

### Shard Routing
- Vectors are distributed across 8 DO shards by `abs(id) % shardCount`
- Search queries all shards in parallel, merges by score descending
- Upsert groups points by shard, writes each bucket in parallel

### WAL Persistence
- **DO storage**: WAL segments (write coalescing for atomicity)
- **R2 storage**: Snapshots (5GB objects, no chunking needed)
- **DO storage chunking**: 120KB chunks for values exceeding 128KB limit
- **Crash safety**: Snapshot written before WAL truncation — replay is idempotent

### Instance ID Stability
- Each DO derives a stable `instanceId` from its DO ID via FNV-1a hash
- Survives DO restarts — no global singleton needed
- Multiple DOs in the same JS module are fully isolated

## Setup

```bash
# Create R2 bucket
wrangler r2 bucket create vcdb-data

# Install dependencies
npm install

# Local development
npm run dev

# Deploy
npm run deploy
```

## API

| Method | Path | Body | Description |
|--------|------|------|-------------|
| POST | /upsert | `{ points: [{ id, vector, payload }] }` | Upsert vectors |
| POST | /search | `{ vector, topK?, filter? }` | Vector similarity search |
| GET | /vectors/:id | — | Get vector by ID |
| POST | /scroll | `{ filter?, offset?, limit? }` | Paginated scroll |
| POST | /count | `{ filter }` | Count matching vectors |
| GET | /health | — | Health check |

## Scaling

- **Memory**: Each DO shard has 128MB — 8 shards = ~1GB total vector capacity
- **Throughput**: Shards handle requests independently and in parallel
- **Recovery**: Cold start replays WAL + snapshot (~100ms per shard)
- **To increase shards**: Change `createShardRouter(8)` in worker.ts (requires new shard version for clean migration)
