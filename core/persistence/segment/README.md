# core/persistence/segment

Data segment format for distributed vector storage.

## Format

```
Header (12 bytes):
  - Magic: "VCDBMBT\0" (8 bytes)
  - Type: 1 byte (Segment)
  - Version: 1 byte
  - Reserved: 2 bytes

Record:
  - ID: 8 bytes
  - AttrsLen: 4 bytes
  - VectorLen: 4 bytes
  - Attrs: JSON UTF-8
  - Vector: Float32 array
```

## Key Types

- `DataPointer`: Reference to a record (segment, offset, length)
- `IndexEntry`: Mapping from vector ID to data location
- `SegmentWriter`: Builds segments in memory
- `SegmentReader`: Reads records from segments

## Usage

```moonbit
let writer = SegmentWriter::new("segment-001")
let ptr = writer.write(id, vector, attrs)
let bytes = writer.finalize()
```
