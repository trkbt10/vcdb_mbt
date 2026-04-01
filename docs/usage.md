## Usage

### Native Gateway

Execute the gateway layer directly:

```bash
moon run cmd/native-gateway -- healthz
moon run cmd/native-gateway -- request --method GET --path /collections
```

### HTTP API

Start the JavaScript transport adapter:

```bash
cd js
npm run build
node dist/server.js --host 127.0.0.1 --port 6333 --storage ../.local-storage
```

Or start the native MoonBit transport adapter:

```bash
moon run cmd/native-serve -- --host 127.0.0.1 --port 6333
```

#### Create Collection

```bash
curl -X POST http://localhost:8080/collections/my_collection \
  -H "Content-Type: application/json" \
  -d '{"dim": 128, "ann_type": "hnsw"}'
```

#### Upsert Vectors

```bash
curl -X PUT http://localhost:8080/collections/my_collection/points \
  -H "Content-Type: application/json" \
  -d '{"points": [{"id": "1", "vector": [...]}]}'
```

#### Search

```bash
curl -X POST http://localhost:8080/collections/my_collection/search \
  -H "Content-Type: application/json" \
  -d '{"vector": [...], "top_k": 10}'
```
