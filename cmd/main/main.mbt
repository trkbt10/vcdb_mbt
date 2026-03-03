///|
/// vcdb CLI Demo - Vector Database functionality demonstration
/// Run with `moon run cmd/main` from the project root.

fn main {
  println("=== vcdb Vector Database Demo ===\n")

  // Demo 1: Basic Bruteforce Search
  demo_bruteforce()

  // Demo 2: HNSW Search
  demo_hnsw()

  // Demo 3: Search with Filters
  demo_filtered_search()

  // Demo 4: Serialization Roundtrip
  demo_serialization()

  // Demo 5: Multi-metric comparison
  demo_metrics()

  println("\n=== All demos completed successfully! ===")
}

///|
fn demo_bruteforce() -> Unit {
  println("--- Demo 1: Bruteforce Search ---")

  let db = @vcdb.VectorDB::with_dim(3)

  // Add sample vectors representing documents/items
  // Simulating embeddings for: "apple", "banana", "orange", "grape", "melon"
  let items = [
    (1, "apple",  [0.9, 0.1, 0.0]),
    (2, "banana", [0.1, 0.9, 0.0]),
    (3, "orange", [0.8, 0.2, 0.0]),
    (4, "grape",  [0.2, 0.8, 0.0]),
    (5, "melon",  [0.5, 0.5, 0.0]),
  ]

  for item in items {
    let (id, name, vec) = item
    let attrs = @core.empty_attrs()
    attrs.set("name", @core.String(name))
    db.add(@core.VectorId::from_int(id), vec, attrs)
  }

  println("Added \{db.size()} items to database")

  // Search for items similar to "apple" (query: [0.9, 0.1, 0.0])
  let query = [0.9, 0.1, 0.0]
  let results = db.search(query, 3, None)

  println("Query: similar to 'apple' [0.9, 0.1, 0.0]")
  println("Top 3 results:")
  for i, hit in results.iter2() {
    let name = match hit.attrs.get("name") {
      Some(@core.String(s)) => s
      _ => "unknown"
    }
    println("  \{i + 1}. \{name} (id=\{hit.id.to_int64()}, score=\{hit.score})")
  }
  println("")
}

///|
fn demo_hnsw() -> Unit {
  println("--- Demo 2: HNSW Approximate Search ---")

  let db = @vcdb.VectorDB::with_hnsw(4, metric=@core.Dot)

  // Add 100 vectors
  for i in 0..<100 {
    let v = [
      (i % 10).to_double() / 10.0,
      ((i / 10) % 10).to_double() / 10.0,
      (i % 7).to_double() / 7.0,
      (i % 13).to_double() / 13.0,
    ]
    let attrs = @core.empty_attrs()
    attrs.set("index", @core.Int(i.to_int64()))
    db.add(@core.VectorId::from_int(i), v, attrs)
  }

  println("Added \{db.size()} vectors with HNSW index")

  // Search
  let query = [0.5, 0.5, 0.5, 0.5]
  let results = db.search(query, 5, None)

  println("Query: [0.5, 0.5, 0.5, 0.5]")
  println("Top 5 results:")
  for i, hit in results.iter2() {
    let idx = match hit.attrs.get("index") {
      Some(@core.Int(n)) => n.to_string()
      _ => "?"
    }
    println("  \{i + 1}. index=\{idx} (id=\{hit.id.to_int64()}, score=\{format_score(hit.score)})")
  }
  println("")
}

///|
fn demo_filtered_search() -> Unit {
  println("--- Demo 3: Search with Attribute Filter ---")

  let db = @vcdb.VectorDB::with_dim(2)

  // Add products with categories
  let products = [
    (1, "iPhone",    "electronics", [0.9, 0.1]),
    (2, "Galaxy",    "electronics", [0.85, 0.15]),
    (3, "T-shirt",   "clothing",    [0.1, 0.9]),
    (4, "Jeans",     "clothing",    [0.15, 0.85]),
    (5, "MacBook",   "electronics", [0.95, 0.05]),
    (6, "Sneakers",  "clothing",    [0.2, 0.8]),
  ]

  for product in products {
    let (id, name, category, vec) = product
    let attrs = @core.empty_attrs()
    attrs.set("name", @core.String(name))
    attrs.set("category", @core.String(category))
    db.add(@core.VectorId::from_int(id), vec, attrs)
  }

  println("Added \{db.size()} products")

  // Search only in electronics category
  let filter = fn(_id : @core.VectorId, attrs : @core.Attrs) -> Bool {
    match attrs.get("category") {
      Some(@core.String(s)) => s == "electronics"
      _ => false
    }
  }

  let query = [1.0, 0.0]  // Looking for electronics-like vector
  let results = db.search(query, 3, Some(filter))

  println("Query: [1.0, 0.0] with filter: category='electronics'")
  println("Results:")
  for i, hit in results.iter2() {
    let name = match hit.attrs.get("name") {
      Some(@core.String(s)) => s
      _ => "unknown"
    }
    println("  \{i + 1}. \{name} (score=\{format_score(hit.score)})")
  }
  println("")
}

///|
fn demo_serialization() -> Unit {
  println("--- Demo 4: Serialization & Persistence ---")

  let db = @vcdb.VectorDB::with_hnsw(3, metric=@core.Cosine)

  // Add data
  for i in 1..<=10 {
    let attrs = @core.empty_attrs()
    attrs.set("label", @core.String("item-\{i}"))
    db.add(
      @core.VectorId::from_int(i),
      [i.to_double() / 10.0, (10 - i).to_double() / 10.0, 0.5],
      attrs,
    )
  }

  // Serialize
  let bytes = db.serialize()
  println("Original DB: \{db.size()} vectors, serialized to \{bytes.length()} bytes")

  // Deserialize
  let db2 = @vcdb.VectorDB::deserialize(bytes)
  println("Restored DB: \{db2.size()} vectors")

  // Verify search works on restored DB
  let query = [1.0, 0.0, 0.5]
  let results = db2.search(query, 3, None)

  println("Search on restored DB for [1.0, 0.0, 0.5]:")
  for i, hit in results.iter2() {
    let label = match hit.attrs.get("label") {
      Some(@core.String(s)) => s
      _ => "?"
    }
    println("  \{i + 1}. \{label} (score=\{format_score(hit.score)})")
  }
  println("")
}

///|
fn demo_metrics() -> Unit {
  println("--- Demo 5: Metric Comparison ---")

  // Same vectors, different metrics
  let vectors = [
    (1, [1.0, 0.0, 0.0]),
    (2, [2.0, 0.0, 0.0]),  // Same direction as 1, different magnitude
    (3, [0.0, 1.0, 0.0]),  // Orthogonal
  ]

  let query = [1.0, 0.0, 0.0]

  // Cosine: direction matters, not magnitude
  let db_cosine = @vcdb.VectorDB::new({
    dim: 3,
    metric: @core.Cosine,
    capacity: 10,
    strategy: @core.Bruteforce,
  })

  // Dot: both direction and magnitude matter
  let db_dot = @vcdb.VectorDB::new({
    dim: 3,
    metric: @core.Dot,
    capacity: 10,
    strategy: @core.Bruteforce,
  })

  // L2: distance matters
  let db_l2 = @vcdb.VectorDB::new({
    dim: 3,
    metric: @core.L2,
    capacity: 10,
    strategy: @core.Bruteforce,
  })

  for vec in vectors {
    let (id, v) = vec
    db_cosine.add(@core.VectorId::from_int(id), v, @core.empty_attrs())
    db_dot.add(@core.VectorId::from_int(id), v, @core.empty_attrs())
    db_l2.add(@core.VectorId::from_int(id), v, @core.empty_attrs())
  }

  println("Vectors: id=1 [1,0,0], id=2 [2,0,0], id=3 [0,1,0]")
  println("Query: [1,0,0]\n")

  println("Cosine (direction only):")
  let r_cos = db_cosine.search(query, 3, None)
  for hit in r_cos {
    println("  id=\{hit.id.to_int64()}, score=\{format_score(hit.score)}")
  }

  println("Dot (direction + magnitude):")
  let r_dot = db_dot.search(query, 3, None)
  for hit in r_dot {
    println("  id=\{hit.id.to_int64()}, score=\{format_score(hit.score)}")
  }

  println("L2 (distance, negated):")
  let r_l2 = db_l2.search(query, 3, None)
  for hit in r_l2 {
    println("  id=\{hit.id.to_int64()}, score=\{format_score(hit.score)}")
  }
}

///|
/// Format score for display
fn format_score(score : Double) -> String {
  // Simple formatting: truncate to 4 decimal places
  let scaled = (score * 10000.0).to_int64()
  let integer = scaled / 10000L
  let frac = if scaled >= 0L { scaled % 10000L } else { (-scaled) % 10000L }
  let sign = if score < 0.0 && integer == 0L { "-" } else { "" }
  let frac_str = frac.to_string()
  let padded = match frac_str.length() {
    1 => "000" + frac_str
    2 => "00" + frac_str
    3 => "0" + frac_str
    _ => frac_str
  }
  "\{sign}\{integer}.\{padded}"
}
