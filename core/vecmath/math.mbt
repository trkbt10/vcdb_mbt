///|
/// Normalize a vector to unit L2 norm in place.
/// Leaves a zero vector unchanged (avoids dividing by zero).
pub fn normalize_in_place(vec : Array[Double]) -> Unit {
  let len = vec.length()
  let end4 = len - (len % 4)
  let mut s0 = 0.0
  let mut s1 = 0.0
  let mut s2 = 0.0
  let mut s3 = 0.0
  let mut i = 0
  while i < end4 {
    let v0 = vec[i]
    let v1 = vec[i + 1]
    let v2 = vec[i + 2]
    let v3 = vec[i + 3]
    s0 += v0 * v0
    s1 += v1 * v1
    s2 += v2 * v2
    s3 += v3 * v3
    i += 4
  }
  let mut sum = s0 + s1 + s2 + s3
  while i < len {
    let v = vec[i]
    sum += v * v
    i += 1
  }
  let inv = if sum > 0.0 { 1.0 / sum.sqrt() } else { 1.0 }
  i = 0
  while i < end4 {
    vec[i] = vec[i] * inv
    vec[i + 1] = vec[i + 1] * inv
    vec[i + 2] = vec[i + 2] * inv
    vec[i + 3] = vec[i + 3] * inv
    i += 4
  }
  while i < len {
    vec[i] = vec[i] * inv
    i += 1
  }
}

///|
/// Normalize a vector and return a new copy.
pub fn normalize(vec : Array[Double]) -> Array[Double] {
  let out = vec.copy()
  normalize_in_place(out)
  out
}

///|
/// Dot product between query q and a strided slice of data.
/// Operates on data[base..base+dim] and q[0..dim].
/// No bounds checks for performance - caller must ensure valid ranges.
pub fn dot_at(
  data : Array[Double],
  base : Int,
  q : Array[Double],
  dim : Int,
) -> Double {
  let mut s0 = 0.0
  let mut s1 = 0.0
  let mut s2 = 0.0
  let mut s3 = 0.0
  let end4 = dim - (dim % 4)
  let mut i = 0
  while i < end4 {
    s0 += data[base + i] * q[i]
    s1 += data[base + i + 1] * q[i + 1]
    s2 += data[base + i + 2] * q[i + 2]
    s3 += data[base + i + 3] * q[i + 3]
    i += 4
  }
  let mut s = s0 + s1 + s2 + s3
  while i < dim {
    s += data[base + i] * q[i]
    i += 1
  }
  s
}

///|
/// Negative squared L2 distance between q and a strided slice of data.
/// Returns -sum((data[base+i]-q[i])^2) so that higher is better,
/// unifying the scoring direction with cosine/dot.
pub fn l2neg_at(
  data : Array[Double],
  base : Int,
  q : Array[Double],
  dim : Int,
) -> Double {
  let mut s0 = 0.0
  let mut s1 = 0.0
  let mut s2 = 0.0
  let mut s3 = 0.0
  let end4 = dim - (dim % 4)
  let mut i = 0
  while i < end4 {
    let d0 = data[base + i] - q[i]
    let d1 = data[base + i + 1] - q[i + 1]
    let d2 = data[base + i + 2] - q[i + 2]
    let d3 = data[base + i + 3] - q[i + 3]
    s0 += d0 * d0
    s1 += d1 * d1
    s2 += d2 * d2
    s3 += d3 * d3
    i += 4
  }
  let mut s = s0 + s1 + s2 + s3
  while i < dim {
    let d = data[base + i] - q[i]
    s += d * d
    i += 1
  }
  -s
}

///|
/// Get score function for a given metric.
/// Returns a function that computes similarity score.
pub fn get_score_fn(
  metric : @types.Metric,
) -> (Array[Double], Int, Array[Double], Int) -> Double {
  match metric {
    @types.Cosine => dot_at // cosine uses dot after normalization
    @types.Dot => dot_at
    @types.L2 => l2neg_at
  }
}

///|
/// Compute L2 norm of a vector
pub fn l2_norm(vec : Array[Double]) -> Double {
  let len = vec.length()
  let end4 = len - (len % 4)
  let mut s0 = 0.0
  let mut s1 = 0.0
  let mut s2 = 0.0
  let mut s3 = 0.0
  let mut i = 0
  while i < end4 {
    let v0 = vec[i]
    let v1 = vec[i + 1]
    let v2 = vec[i + 2]
    let v3 = vec[i + 3]
    s0 += v0 * v0
    s1 += v1 * v1
    s2 += v2 * v2
    s3 += v3 * v3
    i += 4
  }
  let mut sum = s0 + s1 + s2 + s3
  while i < len {
    let v = vec[i]
    sum += v * v
    i += 1
  }
  sum.sqrt()
}

///|
/// Compute dot product of two vectors
pub fn dot(a : Array[Double], b : Array[Double]) -> Double {
  let len = if a.length() < b.length() { a.length() } else { b.length() }
  let end4 = len - (len % 4)
  let mut s0 = 0.0
  let mut s1 = 0.0
  let mut s2 = 0.0
  let mut s3 = 0.0
  let mut i = 0
  while i < end4 {
    s0 += a[i] * b[i]
    s1 += a[i + 1] * b[i + 1]
    s2 += a[i + 2] * b[i + 2]
    s3 += a[i + 3] * b[i + 3]
    i += 4
  }
  let mut sum = s0 + s1 + s2 + s3
  while i < len {
    sum += a[i] * b[i]
    i += 1
  }
  sum
}

///|
/// Compute squared L2 distance between two vectors
pub fn l2_squared(a : Array[Double], b : Array[Double]) -> Double {
  let len = if a.length() < b.length() { a.length() } else { b.length() }
  let end4 = len - (len % 4)
  let mut s0 = 0.0
  let mut s1 = 0.0
  let mut s2 = 0.0
  let mut s3 = 0.0
  let mut i = 0
  while i < end4 {
    let d0 = a[i] - b[i]
    let d1 = a[i + 1] - b[i + 1]
    let d2 = a[i + 2] - b[i + 2]
    let d3 = a[i + 3] - b[i + 3]
    s0 += d0 * d0
    s1 += d1 * d1
    s2 += d2 * d2
    s3 += d3 * d3
    i += 4
  }
  let mut sum = s0 + s1 + s2 + s3
  while i < len {
    let d = a[i] - b[i]
    sum += d * d
    i += 1
  }
  sum
}

///|
/// Compute cosine similarity between two vectors
pub fn cosine_similarity(a : Array[Double], b : Array[Double]) -> Double {
  let d = dot(a, b)
  let na = l2_norm(a)
  let nb = l2_norm(b)
  if na > 0.0 && nb > 0.0 {
    d / (na * nb)
  } else {
    0.0
  }
}

///|
/// Natural logarithm approximation using series expansion.
/// Uses ln(x) = 2 * sum_{n=0}^{inf} (1/(2n+1)) * ((x-1)/(x+1))^(2n+1)
/// For x in (0.5, 2.0), then uses ln(x*2^k) = ln(x) + k*ln(2) for range reduction.
pub fn ln(x : Double) -> Double {
  if x <= 0.0 {
    return -1.0e308 // negative infinity approximation
  }
  if x == 1.0 {
    return 0.0
  }
  // Range reduction: find k such that x / 2^k is in [0.5, 2.0)
  let ln2 = 0.6931471805599453
  let mut y = x
  let mut k = 0
  while y >= 2.0 {
    y = y / 2.0
    k = k + 1
  }
  while y < 0.5 {
    y = y * 2.0
    k = k - 1
  }
  // Now y is in [0.5, 2.0), compute ln(y) using series
  let z = (y - 1.0) / (y + 1.0)
  let z2 = z * z
  // ln(y) = 2 * (z + z^3/3 + z^5/5 + z^7/7 + ...)
  let mut term = z
  let mut sum = z
  for i in 1..<=15 {
    term = term * z2
    sum = sum + term / (2 * i + 1).to_double()
  }
  2.0 * sum + k.to_double() * ln2
}
