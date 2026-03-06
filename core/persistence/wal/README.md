# core/persistence/wal

Write-Ahead Log (WAL) for crash recovery.

## Format

```
Header (12 bytes):
  - Magic: "VCDBMBT\0" (8 bytes)
  - Type: 1 byte
  - Version: 1 byte
  - Reserved: 2 bytes

Records:
  - Type: 1 byte (Upsert/Remove/SetAttrs)
  - Reserved: 1 byte
  - ID: 8 bytes
  - AttrsLen: 4 bytes
  - VectorLen: 4 bytes
  - Attrs: JSON UTF-8
  - Vector: Float32 array

Footer (8 bytes, optional):
  - Magic: "WCRC" (4 bytes)
  - CRC32: 4 bytes
```

## Record Types

- `Upsert`: Insert or update vector with attrs
- `Remove`: Delete vector
- `SetAttrs`: Update attrs only

## Usage

```moonbit
let writer = WalWriter::new()
writer.write_upsert(id, vector, attrs)
let bytes = writer.finalize()
```
