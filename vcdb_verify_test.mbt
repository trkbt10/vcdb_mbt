///|
/// Verification test: Index and Data storage separation

test "verify/index_data_separation" {
  // Create store with data
  let store = @core.CoreStore::new(3, @core.Cosine, capacity=20)
  for i in 1..=10 {
    let attrs = @core.empty_attrs()
    attrs.set("id", @core.Int(i.to_int64()))
    let _ = store.add_or_update(
      @core.VectorId::from_int(i),
      [i.to_double(), (i * 2).to_double(), (i * 3).to_double()],
      attrs,
      upsert=false,
    )
  }

  // Setup: 3 data storages + 1 index storage
  let crush = @persistence.CrushMap::new(
    8,
    1,
    [
      @persistence.CrushTarget::new("data-node-1"),
      @persistence.CrushTarget::new("data-node-2"),
      @persistence.CrushTarget::new("data-node-3"),
    ],
  )

  let data_storages : Map[String, @persistence.MemoryStorage] = {}
  data_storages.set("data-node-1", @persistence.MemoryStorage::new())
  data_storages.set("data-node-2", @persistence.MemoryStorage::new())
  data_storages.set("data-node-3", @persistence.MemoryStorage::new())
  let index_storage = @persistence.MemoryStorage::new()

  // Save
  let opts = @persistence.SegmentOptions::default("mydb", crush)
  let _ = @persistence.save_store_distributed!(store, opts, data_storages, index_storage)

  // === VERIFICATION ===

  // 1. Index storage should have .index and .manifest.json
  let index_files = index_storage.list()
  println("Index storage files: " + index_files.length().to_string())
  for file in index_files {
    println("  [INDEX] " + file)
  }

  // 2. Data storages should have .data files (distributed)
  let mut total_data_files = 0
  for key in data_storages.keys() {
    let storage = data_storages.get(key).unwrap()
    let files = storage.list()
    if files.length() > 0 {
      println("Data storage '" + key + "': " + files.length().to_string() + " files")
      for file in files {
        println("  [DATA] " + file)
      }
      total_data_files = total_data_files + files.length()
    }
  }

  // 3. Verify index storage does NOT have .data files
  let index_has_data = index_files.iter().any(fn(f) { f.contains(".data") })

  // 4. Verify data storages do NOT have .index or .manifest files
  let mut data_has_index = false
  for key in data_storages.keys() {
    let storage = data_storages.get(key).unwrap()
    for file in storage.list() {
      if file.contains(".index") || file.contains(".manifest") {
        data_has_index = true
      }
    }
  }

  // Print verification results
  println("")
  println("=== VERIFICATION RESULTS ===")
  println("Index storage has .index file: " + index_storage.exists("mydb.index").to_string())
  println("Index storage has .manifest.json: " + index_storage.exists("mydb.manifest.json").to_string())
  println("Index storage has .data files: " + index_has_data.to_string())
  println("Data storages have .index/.manifest: " + data_has_index.to_string())
  println("Total data segment files: " + total_data_files.to_string())

  // Assertions - strict separation
  assert_true!(index_storage.exists("mydb.index"))
  assert_true!(index_storage.exists("mydb.manifest.json"))
  assert_false!(index_has_data) // Index must NOT have data
  assert_false!(data_has_index) // Data must NOT have index
  assert_true!(total_data_files > 0) // Data must be distributed
}

///|
/// Verify data is distributed across multiple nodes
test "verify/data_distribution" {
  let store = @core.CoreStore::new(2, @core.Dot, capacity=100)

  // Add 50 vectors
  for i in 1..=50 {
    let _ = store.add_or_update(
      @core.VectorId::from_int(i),
      [i.to_double(), 0.0],
      @core.empty_attrs(),
      upsert=false,
    )
  }

  // 4 data nodes
  let crush = @persistence.CrushMap::new(
    16, // More PGs for better distribution
    1,
    [
      @persistence.CrushTarget::new("node-a"),
      @persistence.CrushTarget::new("node-b"),
      @persistence.CrushTarget::new("node-c"),
      @persistence.CrushTarget::new("node-d"),
    ],
  )

  let data_storages : Map[String, @persistence.MemoryStorage] = {}
  data_storages.set("node-a", @persistence.MemoryStorage::new())
  data_storages.set("node-b", @persistence.MemoryStorage::new())
  data_storages.set("node-c", @persistence.MemoryStorage::new())
  data_storages.set("node-d", @persistence.MemoryStorage::new())
  let index_storage = @persistence.MemoryStorage::new()

  let opts = @persistence.SegmentOptions::default("dist", crush)
  let _ = @persistence.save_store_distributed!(store, opts, data_storages, index_storage)

  // Count files per node
  let mut nodes_with_data = 0
  for key in data_storages.keys() {
    let storage = data_storages.get(key).unwrap()
    if storage.list().length() > 0 {
      nodes_with_data = nodes_with_data + 1
      println(key + ": " + storage.list().length().to_string() + " segments")
    }
  }

  println("Nodes with data: " + nodes_with_data.to_string() + "/4")

  // At least 2 nodes should have data (distribution working)
  assert_true!(nodes_with_data >= 2)
}

///|
/// Verify roundtrip: save distributed -> load -> verify data intact
test "verify/roundtrip_data_integrity" {
  let store = @core.CoreStore::new(3, @core.Cosine, capacity=20)

  // Add vectors with specific values
  for i in 1..=5 {
    let attrs = @core.empty_attrs()
    attrs.set("name", @core.String("vec-" + i.to_string()))
    attrs.set("value", @core.Float(i.to_double() * 1.5))
    let _ = store.add_or_update(
      @core.VectorId::from_int(i * 100), // Non-sequential IDs
      [i.to_double(), (i * 2).to_double(), (i * 3).to_double()],
      attrs,
      upsert=false,
    )
  }

  let crush = @persistence.CrushMap::new(
    4,
    1,
    [
      @persistence.CrushTarget::new("storage-1"),
      @persistence.CrushTarget::new("storage-2"),
    ],
  )

  let data_storages : Map[String, @persistence.MemoryStorage] = {}
  data_storages.set("storage-1", @persistence.MemoryStorage::new())
  data_storages.set("storage-2", @persistence.MemoryStorage::new())
  let index_storage = @persistence.MemoryStorage::new()

  // Save
  let opts = @persistence.SegmentOptions::default("integrity", crush)
  let _ = @persistence.save_store_distributed!(store, opts, data_storages, index_storage)

  // Load
  let restored = @persistence.load_store_distributed!(
    "integrity",
    data_storages,
    index_storage,
  )

  // Verify count
  assert_eq!(restored.size(), 5)

  // Verify each vector
  for i in 1..=5 {
    let id = @core.VectorId::from_int(i * 100)
    assert_true!(restored.has(id))

    match restored.get(id) {
      Some(rec) => {
        // Vectors are normalized for Cosine metric
        // Check proportions instead of absolute values
        let v = rec.vector
        assert_true!(v.length() == 3)
        // v[0]:v[1]:v[2] should be 1:2:3 (normalized)
        let ratio1 = v[1] / v[0]
        let ratio2 = v[2] / v[0]
        assert_true!((ratio1 - 2.0).abs() < 0.01)
        assert_true!((ratio2 - 3.0).abs() < 0.01)

        // Check attrs
        match rec.attrs.get("name") {
          Some(@core.String(s)) => assert_eq!(s, "vec-" + i.to_string())
          _ => assert_true!(false)
        }
        match rec.attrs.get("value") {
          Some(@core.Float(f)) => assert_true!((f - i.to_double() * 1.5).abs() < 0.001)
          Some(@core.Int(n)) => {
            // JSON may decode as Int if no decimal
            let f = n.to_double()
            assert_true!((f - i.to_double() * 1.5).abs() < 0.001)
          }
          _ => assert_true!(false)
        }
      }
      None => assert_true!(false)
    }
  }

  println("Data integrity verified: 5 vectors with correct values and attrs")
}
