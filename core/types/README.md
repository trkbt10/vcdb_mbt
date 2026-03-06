# core/types

Core type definitions for vcdb.

## Key Types

- `Metric`: Distance metric (Cosine, L2, Dot)
- `VectorId`: 64-bit vector identifier
- `AttrValue`: Attribute value (Null, Bool, Int, Float, String)
- `Attrs`: Map of string keys to AttrValue
- `SearchHit`: Search result with id, score, and attrs
- `VectorRecord`: Vector data with attrs
- `HNSWParams`: HNSW algorithm parameters
- `IVFParams`: IVF algorithm parameters
- `Strategy`: ANN strategy selection (Bruteforce, HNSW, IVF)
- `DatabaseOptions`: Database construction options
- `NumericRange`: Range query constraints

## Usage

```moonbit
let id = @types.VectorId::from_int64(123L)
let attrs = @types.empty_attrs()
attrs.set("category", @types.String("test"))
```
