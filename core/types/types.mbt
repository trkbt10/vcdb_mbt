///|
/// Distance/Similarity Metric.
/// - Cosine: vectors are normalized internally, score in [-1,1]
/// - L2: score is negative squared distance (higher is closer)
/// - Dot: raw dot product (higher is more similar)
pub(all) enum Metric {
  Cosine
  L2
  Dot
} derive(Eq, Show)

///|
/// Canonical string representation of a Metric.
pub fn Metric::to_name(self : Metric) -> String {
  match self {
    Cosine => "cosine"
    L2 => "l2"
    Dot => "dot"
  }
}

///|
/// Parse a Metric from its string representation.
pub fn Metric::from_name(s : String) -> Metric? {
  match s {
    "cosine" | "Cosine" => Some(Cosine)
    "l2" | "L2" => Some(L2)
    "dot" | "Dot" => Some(Dot)
    _ => None
  }
}

///|
/// Vector ID type - Int64 for large-scale support
pub(all) struct VectorId(Int64) derive(Eq, Show, Hash, Compare)

///|
/// Attribute value - supports common primitive types
pub(all) enum AttrValue {
  Null
  Bool(Bool)
  Int(Int64)
  Float(Double)
  String(String)
} derive(Eq, Show)

///|
/// Attributes map - empty map as default
pub(all) struct Attrs(Map[String, AttrValue]) derive(Show)

///|
/// Search result: id + score + attrs
pub(all) struct SearchHit {
  id : VectorId
  score : Double
  attrs : Attrs
} derive(Show)

///|
/// Result returned by get(): vector and attrs for an id
pub(all) struct VectorRecord {
  vector : Array[Double]
  attrs : Attrs
} derive(Show)

///|
/// HNSW algorithm parameters
pub(all) struct HNSWParams {
  m : Int // default: 16
  ef_construction : Int // default: 200
  ef_search : Int // default: 50
  level_mult : Double // default: 1/ln(M)
  seed : UInt64 // default: 42
  allow_replace_deleted : Bool // default: false
} derive(Show)

///|
/// HNSW parameter constraints
pub let hnsw_m_min : Int = 2

///|
pub let hnsw_m_max : Int = 100

///|
pub let hnsw_ef_construction_min : Int = 1

///|
pub let hnsw_ef_construction_max : Int = 1000

///|
/// IVF algorithm parameters
pub(all) struct IVFParams {
  nlist : Int // default: 64
  nprobe : Int // default: sqrt(nlist)
} derive(Show)

///|
/// IVF parameter constraints
pub let ivf_nlist_min : Int = 1

///|
pub let ivf_nlist_max : Int = 65536

///|
/// ANN strategy selection
pub(all) enum Strategy {
  Bruteforce
  HNSW(HNSWParams)
  IVF(IVFParams)
} derive(Show)

///|
/// Canonical string representation of a Strategy (name only, no params).
pub fn Strategy::to_name(self : Strategy) -> String {
  match self {
    Bruteforce => "bruteforce"
    HNSW(_) => "hnsw"
    IVF(_) => "ivf"
  }
}

///|
/// Parse a Strategy from its string representation (uses default params).
pub fn Strategy::from_name(s : String) -> Strategy? {
  match s {
    "bruteforce" | "Bruteforce" => Some(Bruteforce)
    "hnsw" | "HNSW" => Some(Strategy::default_hnsw())
    "ivf" | "IVF" => Some(Strategy::default_ivf())
    _ => None
  }
}

///|
/// Database construction options
pub(all) struct DatabaseOptions {
  dim : Int
  metric : Metric // default: Cosine
  capacity : Int // default: 1024
  strategy : Strategy // default: Bruteforce
} derive(Show)

///|
/// Create default HNSW params
pub fn HNSWParams::default() -> HNSWParams {
  {
    m: 16,
    ef_construction: 200,
    ef_search: 50,
    level_mult: 0.36067376022224085, // 1.0 / ln(16.0)
    seed: 42,
    allow_replace_deleted: false,
  }
}

///|
/// Create default IVF params
pub fn IVFParams::default() -> IVFParams {
  { nlist: 64, nprobe: 8 }
}

///|
/// Default HNSW strategy (most common use case).
pub fn Strategy::default_hnsw() -> Strategy {
  HNSW(HNSWParams::default())
}

///|
/// Default IVF strategy.
pub fn Strategy::default_ivf() -> Strategy {
  IVF(IVFParams::default())
}

///|
/// Create default database options
pub fn DatabaseOptions::default(dim : Int) -> DatabaseOptions {
  { dim, metric: Cosine, capacity: 1024, strategy: Bruteforce }
}

///|
/// Create empty attrs
pub fn empty_attrs() -> Attrs {
  Attrs({})
}

///|
/// Create VectorId from Int64
pub fn VectorId::from_int64(id : Int64) -> VectorId {
  VectorId(id)
}

///|
/// Create VectorId from Int
pub fn VectorId::from_int(id : Int) -> VectorId {
  VectorId(id.to_int64())
}

///|
/// Get the underlying Int64 value
pub fn VectorId::to_int64(self : VectorId) -> Int64 {
  self.0
}

///|
/// Get a value from attrs
pub fn Attrs::get(self : Attrs, key : String) -> AttrValue? {
  self.0.get(key)
}

///|
/// Set a value in attrs
pub fn Attrs::set(self : Attrs, key : String, value : AttrValue) -> Unit {
  self.0.set(key, value)
}

///|
/// Check if attrs is empty
pub fn Attrs::is_empty(self : Attrs) -> Bool {
  self.0.is_empty()
}

///|
/// Get all keys from attrs
pub fn Attrs::keys(self : Attrs) -> Array[String] {
  self.0.keys().collect()
}

///|
/// Get size of attrs
pub fn Attrs::size(self : Attrs) -> Int {
  self.0.length()
}

///|
/// Clear all attrs
pub fn Attrs::clear(self : Attrs) -> Unit {
  self.0.clear()
}

///|
/// Create a defensive copy of attrs
pub fn Attrs::copy(self : Attrs) -> Attrs {
  let new_map : Map[String, AttrValue] = {}
  for k, v in self.0 {
    new_map.set(k, v)
  }
  Attrs(new_map)
}

///|
/// Numeric range for range queries
pub(all) struct NumericRange {
  gt : Double? // greater than
  gte : Double? // greater than or equal
  lt : Double? // less than
  lte : Double? // less than or equal
} derive(Show)

///|
pub fn NumericRange::empty() -> NumericRange {
  { gt: None, gte: None, lt: None, lte: None }
}

///|
pub fn NumericRange::gt(value : Double) -> NumericRange {
  { gt: Some(value), gte: None, lt: None, lte: None }
}

///|
pub fn NumericRange::gte(value : Double) -> NumericRange {
  { gt: None, gte: Some(value), lt: None, lte: None }
}

///|
pub fn NumericRange::lt(value : Double) -> NumericRange {
  { gt: None, gte: None, lt: Some(value), lte: None }
}

///|
pub fn NumericRange::lte(value : Double) -> NumericRange {
  { gt: None, gte: None, lt: None, lte: Some(value) }
}

///|
pub fn NumericRange::between(
  lower : Double,
  upper : Double,
  lower_inclusive? : Bool = true,
  upper_inclusive? : Bool = true,
) -> NumericRange {
  {
    gt: if lower_inclusive {
      None
    } else {
      Some(lower)
    },
    gte: if lower_inclusive {
      Some(lower)
    } else {
      None
    },
    lt: if upper_inclusive {
      None
    } else {
      Some(upper)
    },
    lte: if upper_inclusive {
      Some(upper)
    } else {
      None
    },
  }
}

///|
pub fn NumericRange::matches(self : NumericRange, value : Double) -> Bool {
  match self.gt {
    Some(bound) => if value <= bound { return false }
    None => ()
  }
  match self.gte {
    Some(bound) => if value < bound { return false }
    None => ()
  }
  match self.lt {
    Some(bound) => if value >= bound { return false }
    None => ()
  }
  match self.lte {
    Some(bound) => if value > bound { return false }
    None => ()
  }
  true
}

///|
pub fn attr_value_to_number(value : AttrValue) -> Double? {
  match value {
    Int(n) => Some(n.to_double())
    Float(f) => Some(f)
    _ => None
  }
}
