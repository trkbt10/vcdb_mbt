# core/filter

Filter expression DSL for attribute-based filtering.

## Expression Types

### Leaf Expressions
- `Match(key, value)`: Exact match (key == value)
- `Range(key, range)`: Numeric range query
- `Exists(key)`: Key exists and is not null
- `IsNull(key)`: Key is null or doesn't exist

### Composite Expressions
- `Must([exprs])`: All must match (AND)
- `MustNot([exprs])`: None must match (AND NOT)
- `Should([exprs], min)`: At least N must match (OR with minimum)

## Filter Strategies

- `PreFilter`: Filter before vector search (faster for selective filters)
- `PostFilter`: Filter after vector search (simpler, always correct)
- `Auto`: Automatically choose based on selectivity

## Usage

```moonbit
let filter = FilterExpr::must([
  FilterExpr::match_("category", @types.String("electronics")),
  FilterExpr::range("price", NumericRange::between(10.0, 100.0)),
])
let matches = filter.evaluate(attrs)
```
