# core/vecmath

Vector math utilities optimized for similarity search.

## Functions

- `normalize_in_place(vec)`: Normalize vector to unit L2 norm in place
- `normalize(vec)`: Return normalized copy of vector
- `dot_at(data, base, q, dim)`: Dot product with strided data access
- `l2_sq_at(data, base, q, dim)`: Squared L2 distance with strided access
- `get_score_fn(metric)`: Get scoring function for given metric

## Performance

All hot-path functions use 4-way loop unrolling for better performance on typical vector dimensions.
