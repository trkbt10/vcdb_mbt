# vcdb on Cloudflare Durable Objects + R2

Sharded vcdb deployment using Durable Objects for horizontal scaling with R2 snapshot persistence.

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
- Hosts a vcdb instance via the `persistent_*` FFI API
- WAL management, checkpointing, and crash recovery are handled by vcdb core
- DO storage holds WAL data, R2 holds snapshots
- Recovers via WAL replay on cold start

## Files

```
examples/cloudflare-do/
├── src/
│   ├── worker.ts           # Worker entry point + HTTP API
│   ├── types.ts            # Shared types, ID utilities
│   └── infra/
│       ├── vcdb-do.ts      # Durable Object — single vcdb shard
│       └── shard-router.ts # Scatter-gather across DO shards
├── wrangler.jsonc
├── package.json
└── tsconfig.json
```

## Key Patterns

### Shard Routing
- Vectors are distributed across 8 DO shards by `abs(id) % shardCount`
- Search queries all shards in parallel, merges by score descending
- Upsert groups points by shard, writes each bucket in parallel

### Persistence (via persistent_* API)
- **DO storage**: WAL (write coalescing for atomicity, 120KB chunking)
- **R2 storage**: Snapshots (5GB objects, no chunking needed)
- **Auto-checkpoint**: Triggered by record count or WAL byte size threshold
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
