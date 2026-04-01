///|
/// CollectionPersistence — encapsulates all persistence mechanics.
///
/// Hides WAL, segmentation, and snapshot details from the gateway layer.
/// Gateway only sees: record_upsert, record_remove, save, load, remove, checkpoint.

///|
/// Persistence configuration
pub(all) enum PersistenceMode {
  /// Full serialize as single file (legacy)
  Snapshot
  /// Segmented: split data into multiple files, each under segment_bytes
  Segmented(Int)
}

///|
/// Manages WAL + snapshot/segment persistence for a single collection.
pub struct CollectionPersistence[S] {
  storage : S
  base_path : String
  name : String
  mode : PersistenceMode
  wal : @wal.WalRuntime[S]
  checkpoint_threshold : Int
}

///|
pub fn[S] CollectionPersistence::new(
  storage : S,
  base_path : String,
  name : String,
  mode? : PersistenceMode = Snapshot,
  checkpoint_threshold? : Int = 1000,
) -> CollectionPersistence[S] {
  let wal_path = join_path(base_path, @storage.collection_wal_path(name))
  let wal = @wal.WalRuntime::new(storage, wal_path)
  { storage, base_path, name, mode, wal, checkpoint_threshold }
}

///|
fn join_path(base : String, path : String) -> String {
  if base.length() == 0 {
    path
  } else {
    base + "/" + path
  }
}

///|
/// Record upsert operations to WAL. Auto-checkpoints if threshold exceeded.
pub fn[S : @storage.Storage] CollectionPersistence::record_upsert(
  self : CollectionPersistence[S],
  points : Array[(@types.VectorId, Array[Double], @types.Attrs)],
  store : @store.CoreStore,
) -> Unit {
  let records : Array[@wal.WalRecord] = points.map(fn(p) {
    let (id, vector, attrs) = p
    @wal.WalRecord::upsert(id, vector, attrs)
  })
  self.wal.append(records) catch { _ => () }
  if self.wal.record_count() >= self.checkpoint_threshold {
    self.save(store)
    self.wal.truncate()
  }
}

///|
/// Record remove operation to WAL. Auto-checkpoints if threshold exceeded.
pub fn[S : @storage.Storage] CollectionPersistence::record_remove(
  self : CollectionPersistence[S],
  id : @types.VectorId,
  store : @store.CoreStore,
) -> Unit {
  self.wal.append([@wal.WalRecord::remove(id)]) catch { _ => () }
  if self.wal.record_count() >= self.checkpoint_threshold {
    self.save(store)
    self.wal.truncate()
  }
}

///|
/// Save a full snapshot (and truncate WAL).
pub fn[S : @storage.Storage] CollectionPersistence::checkpoint(
  self : CollectionPersistence[S],
  store : @store.CoreStore,
) -> Unit {
  self.save(store)
  self.wal.truncate()
}

///|
/// Write snapshot data (mode-dependent).
fn[S : @storage.Storage] CollectionPersistence::save(
  self : CollectionPersistence[S],
  store : @store.CoreStore,
) -> Unit {
  match self.mode {
    Snapshot => {
      let data = store.serialize()
      let data_path = join_path(
        self.base_path,
        @storage.collection_data_path(self.name),
      )
      self.storage.write(data_path, data, @storage.Data) catch { _ => () }
    }
    Segmented(seg_bytes) => {
      let base_name = join_path(self.base_path, self.name)
      @placement.save_segmented(store, base_name, seg_bytes, self.storage) catch {
        _ => ()
      }
    }
  }
}

///|
/// Load a CoreStore from storage, replaying WAL on top.
pub fn[S : @storage.Storage] CollectionPersistence::load(
  self : CollectionPersistence[S],
) -> @store.CoreStore? {
  let base_name = join_path(self.base_path, self.name)
  let manifest_path = join_path(
    self.base_path,
    @storage.collection_manifest_path(self.name),
  )

  // Try segmented load, then legacy snapshot
  let store : @store.CoreStore? = if self.storage.exists(
    manifest_path,
    @storage.Index,
  ) {
    Some(@placement.load_segmented(base_name, self.storage) catch {
      _ => return None
    })
  } else {
    let data_path = join_path(
      self.base_path,
      @storage.collection_data_path(self.name),
    )
    if self.storage.exists(data_path, @storage.Data) {
      let data = self.storage.read(data_path, @storage.Data) catch {
        _ => return None
      }
      Some(@store.CoreStore::deserialize(data))
    } else {
      None
    }
  }

  match store {
    None => None
    Some(s) => {
      // Replay WAL on top
      let _ = self.wal.replay_into(s) catch { _ => 0 }
      Some(s)
    }
  }
}

///|
/// Remove all persisted data for a collection.
pub fn[S : @storage.Storage] CollectionPersistence::remove(
  self : CollectionPersistence[S],
) -> Unit {
  let base_name = join_path(self.base_path, self.name)

  // Data files
  let data_path = join_path(
    self.base_path,
    @storage.collection_data_path(self.name),
  )
  if self.storage.exists(data_path, @storage.Data) {
    self.storage.del(data_path, @storage.Data) catch { _ => () }
  }

  // WAL
  let wal_path = join_path(
    self.base_path,
    @storage.collection_wal_path(self.name),
  )
  if self.storage.exists(wal_path, @storage.Data) {
    self.storage.del(wal_path, @storage.Data) catch { _ => () }
  }

  // Manifest + index
  let manifest_path = join_path(
    self.base_path,
    @storage.collection_manifest_path(self.name),
  )
  if self.storage.exists(manifest_path, @storage.Index) {
    self.storage.del(manifest_path, @storage.Index) catch { _ => () }
  }
  let index_path = join_path(
    self.base_path,
    @storage.collection_index_path(self.name),
  )
  if self.storage.exists(index_path, @storage.Index) {
    self.storage.del(index_path, @storage.Index) catch { _ => () }
  }

  // Segments
  for path in self.storage.list(@storage.Data) {
    if @storage.is_segment_path(path, base_name) {
      self.storage.del(path, @storage.Data) catch { _ => () }
    }
  }
}

