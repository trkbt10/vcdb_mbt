///|
/// Filter Expression DSL for attribute-based filtering
/// Supports boolean combinations (Must/MustNot/Should) with leaf predicates.

///|
/// Leaf expression types
pub(all) enum LeafExpr {
  Match(String, @types.AttrValue) // key == value
  Range(String, @types.NumericRange) // key in range
  Exists(String) // key exists (not null)
  IsNull(String) // key is null or doesn't exist
}

///|
pub impl Show for LeafExpr with output(self, logger) {
  match self {
    Match(key, value) => {
      logger.write_string("Match(")
      Show::output(key, logger)
      logger.write_string(", ")
      Show::output(value, logger)
      logger.write_string(")")
    }
    Range(key, range) => {
      logger.write_string("Range(")
      Show::output(key, logger)
      logger.write_string(", ")
      Show::output(range, logger)
      logger.write_string(")")
    }
    Exists(key) => {
      logger.write_string("Exists(")
      Show::output(key, logger)
      logger.write_string(")")
    }
    IsNull(key) => {
      logger.write_string("IsNull(")
      Show::output(key, logger)
      logger.write_string(")")
    }
  }
}

///|
/// Filter expression (can be nested)
pub(all) enum FilterExpr {
  Leaf(LeafExpr)
  Must(Array[FilterExpr]) // All must match (AND)
  MustNot(Array[FilterExpr]) // None must match (AND NOT)
  Should(Array[FilterExpr], Int) // At least N must match (OR with min)
}

///|
pub impl Show for FilterExpr with output(self, logger) {
  match self {
    Leaf(leaf) => {
      logger.write_string("Leaf(")
      Show::output(leaf, logger)
      logger.write_string(")")
    }
    Must(exprs) => {
      logger.write_string("Must(")
      Show::output(exprs, logger)
      logger.write_string(")")
    }
    MustNot(exprs) => {
      logger.write_string("MustNot(")
      Show::output(exprs, logger)
      logger.write_string(")")
    }
    Should(exprs, min) => {
      logger.write_string("Should(")
      Show::output(exprs, logger)
      logger.write_string(", ")
      Show::output(min, logger)
      logger.write_string(")")
    }
  }
}

///|
/// Filter strategy for search
pub(all) enum FilterStrategy {
  PreFilter // Filter before vector search (faster for selective filters)
  PostFilter // Filter after vector search (simpler, always correct)
  Auto // Automatically choose based on selectivity
}

///|
pub impl Show for FilterStrategy with output(self, logger) {
  match self {
    PreFilter => logger.write_string("PreFilter")
    PostFilter => logger.write_string("PostFilter")
    Auto => logger.write_string("Auto")
  }
}

///|
/// Create a Match filter
pub fn FilterExpr::match_(key : String, value : @types.AttrValue) -> FilterExpr {
  Leaf(Match(key, value))
}

///|
/// Create a Range filter
pub fn FilterExpr::range(
  key : String,
  range : @types.NumericRange,
) -> FilterExpr {
  Leaf(Range(key, range))
}

///|
/// Create an Exists filter
pub fn FilterExpr::exists(key : String) -> FilterExpr {
  Leaf(Exists(key))
}

///|
/// Create an IsNull filter
pub fn FilterExpr::is_null(key : String) -> FilterExpr {
  Leaf(IsNull(key))
}

///|
/// Create a Must (AND) filter
pub fn FilterExpr::must(exprs : Array[FilterExpr]) -> FilterExpr {
  Must(exprs)
}

///|
/// Create a MustNot (NOT) filter
pub fn FilterExpr::must_not(exprs : Array[FilterExpr]) -> FilterExpr {
  MustNot(exprs)
}

///|
/// Create a Should (OR) filter with minimum matches
pub fn FilterExpr::should(
  exprs : Array[FilterExpr],
  min? : Int = 1,
) -> FilterExpr {
  Should(exprs, min)
}

///|
/// Evaluate a leaf expression against attrs
fn eval_leaf(expr : LeafExpr, attrs : @types.Attrs) -> Bool {
  match expr {
    Match(key, expected) =>
      match attrs.get(key) {
        None => false
        Some(actual) => attr_value_eq(actual, expected)
      }
    Range(key, range) =>
      match attrs.get(key) {
        None => false
        Some(value) =>
          match @types.attr_value_to_number(value) {
            None => false
            Some(num) => range.matches(num)
          }
      }
    Exists(key) =>
      match attrs.get(key) {
        None => false
        Some(Null) => false
        Some(_) => true
      }
    IsNull(key) =>
      match attrs.get(key) {
        None => true
        Some(Null) => true
        Some(_) => false
      }
  }
}

///|
/// Check if two AttrValues are equal
fn attr_value_eq(a : @types.AttrValue, b : @types.AttrValue) -> Bool {
  match (a, b) {
    (Null, Null) => true
    (Bool(x), Bool(y)) => x == y
    (Int(x), Int(y)) => x == y
    (Float(x), Float(y)) => x == y
    (String(x), String(y)) => x == y
    _ => false
  }
}

///|
/// Evaluate a filter expression against attrs
pub fn eval_filter(expr : FilterExpr, attrs : @types.Attrs) -> Bool {
  match expr {
    Leaf(leaf) => eval_leaf(leaf, attrs)
    Must(exprs) => {
      for e in exprs {
        if !eval_filter(e, attrs) {
          return false
        }
      }
      true
    }
    MustNot(exprs) => {
      for e in exprs {
        if eval_filter(e, attrs) {
          return false
        }
      }
      true
    }
    Should(exprs, min) => {
      let mut count = 0
      for e in exprs {
        if eval_filter(e, attrs) {
          count = count + 1
          if count >= min {
            return true
          }
        }
      }
      count >= min
    }
  }
}

///|
/// Compile a filter expression to a predicate function
pub fn compile_filter(
  expr : FilterExpr,
) -> (@types.VectorId, @types.Attrs) -> Bool {
  fn(id : @types.VectorId, attrs : @types.Attrs) -> Bool {
    let _ = id
    eval_filter(expr, attrs)
  }
}

///|
/// Get candidate IDs from a basic attribute index using a filter expression
/// Returns None if pre-filtering is not possible (should use post-filter)
pub fn get_candidates_basic(
  expr : FilterExpr,
  index : @attr.BasicAttrIndex,
) -> Array[@types.VectorId]? {
  match expr {
    Leaf(Match(key, value)) => Some(index.eq(key, value))
    Leaf(Exists(key)) => Some(index.exists(key))
    Leaf(Range(key, range)) => index.range(key, range)
    Leaf(IsNull(_)) => None // Cannot efficiently find nulls
    Must(exprs) => {
      // Intersect all candidate sets
      let mut result : Array[@types.VectorId]? = None
      for e in exprs {
        match get_candidates_basic(e, index) {
          None => return None
          Some(candidates) =>
            match result {
              None => result = Some(candidates)
              Some(current) => result = Some(intersect_ids(current, candidates))
            }
        }
      }
      result
    }
    MustNot(_) => None // Cannot efficiently negate
    Should(exprs, min) => {
      // If min <= 0, it matches everything (no minimum required)
      // Fall back to post-filter
      if min <= 0 {
        return None
      }
      // If min > 1, we cannot efficiently prefilter because we need to count
      // how many clauses each candidate satisfies
      if min > 1 {
        return None
      }
      // For min == 1 (OR), union all candidate sets
      let all : Array[@types.VectorId] = []
      let seen : Map[Int64, Bool] = {}
      for e in exprs {
        match get_candidates_basic(e, index) {
          None => return None
          Some(candidates) =>
            for id in candidates {
              if !seen.contains(id.to_int64()) {
                seen.set(id.to_int64(), true)
                all.push(id)
              }
            }
        }
      }
      Some(all)
    }
  }
}

///|
/// Resolve candidate IDs from a B+ tree attribute index.
/// Every FilterExpr variant is resolved through the index — there is no
/// fallback to post-filtering. This guarantees a single execution path
/// regardless of the expression shape.
///
/// - IsNull(key): complement of exists(key) against all indexed IDs
/// - MustNot(exprs): complement of union(resolve(e)) against all IDs
/// - Should(exprs, min>1): count per-ID and threshold
pub fn resolve_candidates_bptree(
  expr : FilterExpr,
  index : @attr.BPTreeAttrIndex,
) -> Array[@types.VectorId] {
  match expr {
    Leaf(Match(key, value)) => index.eq(key, value)
    Leaf(Exists(key)) => index.exists(key)
    Leaf(Range(key, range)) =>
      match index.range(key, range) {
        Some(ids) => ids
        None => []
      }
    Leaf(IsNull(key)) => {
      // All IDs minus those that have a non-null value for `key`
      let present = id_set_from(index.exists(key))
      let result : Array[@types.VectorId] = []
      for id in index.all_ids() {
        if !present.contains(id.to_int64()) {
          result.push(id)
        }
      }
      result
    }
    Must(exprs) => {
      let mut result : Array[@types.VectorId] = index.all_ids()
      for e in exprs {
        let candidates = resolve_candidates_bptree(e, index)
        result = intersect_ids(result, candidates)
      }
      result
    }
    MustNot(exprs) => {
      // All IDs minus the union of each sub-expression's candidates
      let excluded : Map[Int64, Bool] = {}
      for e in exprs {
        for id in resolve_candidates_bptree(e, index) {
          excluded.set(id.to_int64(), true)
        }
      }
      let result : Array[@types.VectorId] = []
      for id in index.all_ids() {
        if !excluded.contains(id.to_int64()) {
          result.push(id)
        }
      }
      result
    }
    Should(exprs, min) => {
      if min <= 0 {
        // min <= 0 means everything matches
        return index.all_ids()
      }
      if min == 1 {
        // OR: union of all sub-expressions
        let all : Array[@types.VectorId] = []
        let seen : Map[Int64, Bool] = {}
        for e in exprs {
          for id in resolve_candidates_bptree(e, index) {
            if !seen.contains(id.to_int64()) {
              seen.set(id.to_int64(), true)
              all.push(id)
            }
          }
        }
        all
      } else {
        // min > 1: count how many sub-expressions each ID satisfies
        let counts : Map[Int64, Int] = {}
        for e in exprs {
          for id in resolve_candidates_bptree(e, index) {
            let key = id.to_int64()
            match counts.get(key) {
              Some(c) => counts.set(key, c + 1)
              None => counts.set(key, 1)
            }
          }
        }
        let result : Array[@types.VectorId] = []
        for id_val, count in counts {
          if count >= min {
            result.push(@types.Int64Id(id_val))
          }
        }
        result
      }
    }
  }
}

///|
/// Build a set of Int64 from an ID array (for fast membership tests).
fn id_set_from(ids : Array[@types.VectorId]) -> Map[Int64, Bool] {
  let s : Map[Int64, Bool] = {}
  for id in ids {
    s.set(id.to_int64(), true)
  }
  s
}

///|
/// Intersect two ID arrays
fn intersect_ids(
  a : Array[@types.VectorId],
  b : Array[@types.VectorId],
) -> Array[@types.VectorId] {
  let b_set : Map[Int64, Bool] = {}
  for id in b {
    b_set.set(id.to_int64(), true)
  }
  let result : Array[@types.VectorId] = []
  for id in a {
    if b_set.contains(id.to_int64()) {
      result.push(id)
    }
  }
  result
}
