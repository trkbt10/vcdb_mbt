# core/attr

Attribute indexing strategies for filtered search.

## Strategies

- `Basic`: Hash map based indexing
- `Bitmap`: Bitmap index for low-cardinality fields
- `BPTree`: B+ tree for balanced read/write
- `LSM`: Write-optimized with memtable

## Key Types

- `AttrIndexStrategy`: Strategy selection enum
- `NumEntry`: Sorted entry for numeric index (value, id) pair
- `BasicAttrIndex`: Hash map based attribute index
- `BitmapIndex`: Bitmap index implementation
- `BPTree`: B+ tree index implementation
- `LSMTree`: LSM tree with memtable and levels

## Usage

```moonbit
let index = BasicAttrIndex::new()
index.insert("category", @types.String("electronics"), 123L)
let ids = index.find("category", @types.String("electronics"))
```
