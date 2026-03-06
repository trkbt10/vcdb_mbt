# core/persistence/codec

Binary codec utilities for persistence formats.

## Functions

- `encode_header(writer, type, version)`: Write standard file header
- `decode_header(reader)`: Parse and validate file header
- `encode_attrs_json(attrs)`: Encode attrs as JSON UTF-8 bytes
- `decode_attrs_json(bytes)`: Decode attrs from JSON UTF-8 bytes
- `attrs_to_json(attrs)`: Convert attrs to JSON string
- `parse_attrs_json(json)`: Parse JSON string to attrs

## Constants

- `header_size`: 12 bytes
- `magic`: "VCDBMBT\0"
