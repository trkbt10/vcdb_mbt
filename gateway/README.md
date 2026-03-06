# gateway

REST API gateway for vcdb collections.

## Features

- Collection management (create, list, delete)
- Point operations (upsert, get, delete)
- Vector search with pagination
- Persistence with pluggable storage backends

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/collections` | List all collections |
| POST | `/collections/{name}` | Create collection |
| DELETE | `/collections/{name}` | Delete collection |
| PUT | `/collections/{name}/points` | Upsert points |
| GET | `/collections/{name}/points/{id}` | Get point by ID |
| DELETE | `/collections/{name}/points/{id}` | Delete point |
| POST | `/collections/{name}/points/search` | Search vectors |

## Usage

```moonbit
let manager : CollectionManager[@storage.MemoryStorage] = CollectionManager::new()
let response = execute_request(manager, "POST", ["collections", "test"], body)
```
