## Usage

### REST API

Start the gateway server:

```bash
moon run cmd/main
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
