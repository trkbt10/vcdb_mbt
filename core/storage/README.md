# core/storage

Storage abstraction layer for persistence operations.

## Storage Trait

```moonbit
pub trait Storage {
  read(Self, String, StorageKind) -> Bytes raise IOError
  write(Self, String, Bytes, StorageKind) -> Unit raise IOError
  append(Self, String, Bytes, StorageKind) -> Unit raise IOError
  atomic_write(Self, String, Bytes, StorageKind) -> Unit raise IOError
  del(Self, String, StorageKind) -> Unit raise IOError
  exists(Self, String, StorageKind) -> Bool
  list(Self, StorageKind) -> Array[String]
}
```

## Implementations

- `MemoryStorage`: In-memory storage for testing
- `CallbackStorage`: Delegates to JS callbacks for custom backends

## StorageKind

Routes data to appropriate backends:
- `Config`: Collection configuration files
- `Index`: Index structures and manifests
- `Data`: Vector data and segments
