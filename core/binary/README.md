# core/binary

Binary serialization utilities.

## Types

- `BinaryWriter`: Sequential binary writer with auto-growing buffer
- `BinaryReader`: Sequential binary reader with position tracking

## BinaryWriter Methods

- `write_u32(value)`: Write 32-bit unsigned (little-endian)
- `write_i32(value)`: Write 32-bit signed (little-endian)
- `write_u64(value)`: Write 64-bit unsigned (little-endian)
- `write_i64(value)`: Write 64-bit signed (little-endian)
- `write_f32(value)`: Write 32-bit float (IEEE 754)
- `write_f64(value)`: Write 64-bit float (IEEE 754)
- `write_bytes(bytes)`: Write raw bytes
- `to_bytes()`: Get final buffer

## BinaryReader Methods

- `read_u32()`: Read 32-bit unsigned
- `read_i32()`: Read 32-bit signed
- `read_u64()`: Read 64-bit unsigned
- `read_i64()`: Read 64-bit signed
- `read_f32()`: Read 32-bit float
- `read_f64()`: Read 64-bit float
- `read_bytes(n)`: Read n bytes
- `position()`: Get current read position

## Utilities

- `crc32(data)`: Compute CRC32 checksum
- `read_u32_le(data, offset)`: Read u32 at offset
- `write_u32_le(data, offset, value)`: Write u32 at offset
