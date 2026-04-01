# gateway

Transport-agnostic API execution layer for vcdb collections.

## Features

- Collection management (create, list, delete)
- Point operations (upsert, get, delete)
- Vector search with pagination
- Persistence with pluggable storage backends
- Raw-path execution for transport adapters and native entrypoints

## Responsibility

- Accept API-shaped requests as `method + path + body`
- Execute vcdb collection commands
- Return structured JSON responses

It does not open sockets or serve HTTP directly. Runtime-specific transports
belong in adapter packages such as `http` and `js`.

## Usage

```moonbit
let manager : CollectionManager[@storage.MemoryStorage] = CollectionManager::new()
let response = execute_path_request(
  manager,
  "POST",
  "/collections/test",
  body,
)
```
