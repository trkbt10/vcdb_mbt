# core/placement

CRUSH (Controlled Replication Under Scalable Hashing) algorithm for distributed placement.

## Features

- Deterministic placement based on object hash
- Weighted distribution across storage targets
- Failure domain awareness (zones)
- Consistent hashing for minimal data movement

## Key Types

- `CrushTarget`: Storage target with key, weight, and optional zone
- `CrushMap`: Configuration with PGs, replicas, and targets
- `PlacementGroup`: Logical grouping of objects

## Usage

```moonbit
let targets = [
  CrushTarget::with_weight("node-1", 2.0),
  CrushTarget::with_weight("node-2", 1.0),
  CrushTarget::with_weight("node-3", 1.0),
]
let map = CrushMap::new(pgs=64, replicas=2, targets)
let placement = map.select(object_id)
```

## Algorithm

1. Hash object ID to placement group (PG)
2. Select replicas from targets using weighted pseudo-random selection
3. Respect failure domain constraints (zones)
