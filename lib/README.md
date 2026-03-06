# lib

FFI exports for JavaScript interop via WASM.

## VectorDB Functions

| Function | Description |
|----------|-------------|
| `vcdb_create(dim)` | Create bruteforce DB, returns instance ID |
| `vcdb_create_hnsw(dim)` | Create HNSW DB, returns instance ID |
| `vcdb_create_ivf(dim)` | Create IVF DB, returns instance ID |
| `vcdb_destroy(id)` | Destroy instance |
| `vcdb_add(id, vec_id, vec)` | Add vector (returns 0=ok, -1=not found, -2=exists) |
| `vcdb_upsert(id, vec_id, vec)` | Upsert vector |
| `vcdb_get(id, vec_id)` | Get vector by ID |
| `vcdb_search(id, query, k)` | Search for k nearest neighbors |
| `vcdb_has(id, vec_id)` | Check if vector exists |
| `vcdb_remove(id, vec_id)` | Remove vector |
| `vcdb_serialize(id)` | Serialize to bytes |
| `vcdb_deserialize(data)` | Deserialize to new instance |

## Gateway Functions

| Function | Description |
|----------|-------------|
| `gateway_request(method, path, body)` | Execute gateway API request |
| `gateway_register_storage(...)` | Register storage callbacks |
| `gateway_storage_list(kind)` | List files in storage |
| `gateway_storage_read(path, kind)` | Read file from storage |
| `gateway_storage_write(path, data, kind)` | Write file to storage |
| `gateway_storage_exists(path, kind)` | Check if file exists |
