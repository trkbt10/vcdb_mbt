# vcdb on Cloudflare Workers + R2

Deploy vcdb on Cloudflare Workers with R2 persistence.

Uses MoonBit WASM (JS target) gateway for routing/logic, TypeScript Worker for HTTP handling.

## Architecture

```
┌──────────────┐     ┌─────────────────────────────────┐     ┌─────────────┐
│ Worker URL   │────▶│ worker.ts                       │────▶│ R2 Bucket   │
│ (HTTP)       │     │   └─▶ vcdb gateway (WASM)       │     │ (vcdb data) │
└──────────────┘     └─────────────────────────────────┘     └─────────────┘
```

## Files

```
examples/cloudflare-workers/
├── src/
│   └── worker.ts       # Worker entry point (R2 I/O + WASM gateway)
├── wrangler.jsonc      # Wrangler configuration
├── package.json
└── tsconfig.json
```

## How It Works

1. Worker initializes vcdb WASM module on first request
2. R2 storage adapter is wrapped in CachedStorage for sync WASM callbacks
3. HTTP requests are routed through `gatewayRequest()` (MoonBit gateway)
4. Dirty cache entries are flushed to R2 after mutations

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

Reuses routes from `gateway/handler.mbt`:

| Method | Path | Description |
|--------|------|-------------|
| GET | / | Service info |
| GET | /healthz | Health check |
| GET | /collections | List collections |
| POST | /collections/{name} | Create collection |
| GET | /collections/{name} | Get collection info |
| DELETE | /collections/{name} | Delete collection |
| PUT | /collections/{name}/points | Upsert points |
| POST | /collections/{name}/points/search | Search |
| GET | /collections/{name}/points/{id} | Get point |
| DELETE | /collections/{name}/points/{id} | Delete point |

## Limitations

- Single Worker isolate — no sharding (see `cloudflare-do` example for sharding)
- R2 latency on every flush — CachedStorage mitigates via in-memory cache
- Worker memory limit (128MB) applies to the vcdb instance
