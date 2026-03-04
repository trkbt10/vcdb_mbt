# vcdb on AWS Lambda + S3

Deploy vcdb on AWS Lambda with S3 persistence.

Uses MoonBit WASM (JS target) for routing/logic, TypeScript for S3 I/O.

## Architecture

```
┌──────────────┐     ┌─────────────────────────────────┐     ┌─────────────┐
│ Lambda URL   │────▶│ handler.ts                      │────▶│ S3 Bucket   │
│ (HTTP)       │     │   └─▶ vcdb_gateway.js (WASM)    │     │ (vcdb data) │
└──────────────┘     └─────────────────────────────────┘     └─────────────┘
```

## Files

```
examples/aws-lambda-s3/
├── wasm/
│   ├── exports.mbt     # WASM entry point (calls gateway/http)
│   └── moon.pkg
├── ts-native/
│   ├── handler.ts      # Lambda handler (S3 I/O + WASM call)
│   ├── s3-storage.ts   # S3 adapter
│   ├── package.json
│   └── tsconfig.json
└── infra/
    ├── main.tf
    └── variables.tf
```

## How It Works

1. `wasm/exports.mbt` imports existing `gateway` and `http` packages
2. Builds to JS with `moon build --target js`
3. `handler.ts` imports the JS output and calls `execute_request(method, path, body)`
4. Routing logic from `gateway/handler.mbt` is reused (no duplication)

## Build & Deploy

```bash
cd ts-native
npm install
npm run build    # Builds WASM + TS
npm run package  # Creates function.zip

cd ../infra
terraform init
terraform apply
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
