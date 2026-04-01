///|
/// AsyncCollectionPersistence — fully async persistence for JS environments.
///
/// Every storage operation is awaited to completion. Checkpoint guarantees:
///   1. Snapshot is written and persisted
///   2. Only then WAL is truncated and persisted
///
/// No CachedStorage needed. No data loss window.

///|
pub struct AsyncCollectionPersistence[S] {
  storage : S
  base_path : String
  name : String
  mode : PersistenceMode
  wal : @wal.AsyncWalRuntime[S]
  checkpoint_threshold : Int
}

///|
pub fn[S] AsyncCollectionPersistence::new(
  storage : S,
  base_path : String,
  name : String,
  mode? : PersistenceMode = Snapshot,
  checkpoint_threshold? : Int = 1000,
) -> AsyncCollectionPersistence[S] {
  let wal_path = join_path(base_path, @storage.collection_wal_path(name))
  let wal = @wal.AsyncWalRuntime::new(storage, wal_path)
  { storage, base_path, name, mode, wal, checkpoint_threshold }
}

///|
/// Record upsert operations. WAL is durably written before returning.
/// Auto-checkpoints if threshold exceeded (also fully awaited).
pub async fn[S : @storage.AsyncStorage] AsyncCollectionPersistence::record_upsert(
  self : AsyncCollectionPersistence[S],
  points : Array[(@types.VectorId, Array[Double], @types.Attrs)],
  store : @store.CoreStore,
) -> Unit {
  let records : Array[@wal.WalRecord] = points.map(fn(p) {
    let (id, vector, attrs) = p
    @wal.WalRecord::upsert(id, vector, attrs)
  })
  self.wal.append(records)
  let count = self.wal.record_count()
  if count >= self.checkpoint_threshold {
    self.checkpoint(store)
  }
}

///|
/// Record remove operation. WAL is durably written before returning.
pub async fn[S : @storage.AsyncStorage] AsyncCollectionPersistence::record_remove(
  self : AsyncCollectionPersistence[S],
  id : @types.VectorId,
  store : @store.CoreStore,
) -> Unit {
  self.wal.append([@wal.WalRecord::remove(id)])
  let count = self.wal.record_count()
  if count >= self.checkpoint_threshold {
    self.checkpoint(store)
  }
}

///|
/// Checkpoint with guaranteed ordering:
///   1. Write snapshot → awaited to persistence
///   2. Truncate WAL → awaited to persistence
///
/// Crash safety:
///   After step 1, before step 2: WAL still exists, replay is idempotent
///   During step 1: WAL is intact, snapshot partial/absent, WAL recovers
pub async fn[S : @storage.AsyncStorage] AsyncCollectionPersistence::checkpoint(
  self : AsyncCollectionPersistence[S],
  store : @store.CoreStore,
) -> Unit {
  // Step 1: snapshot — durable before proceeding
  self.save(store)
  // Step 2: truncate WAL — only after snapshot is confirmed durable
  self.wal.truncate()
}

///|
/// Write snapshot data (mode-dependent).
async fn[S : @storage.AsyncStorage] AsyncCollectionPersistence::save(
  self : AsyncCollectionPersistence[S],
  store : @store.CoreStore,
) -> Unit {
  match self.mode {
    Snapshot => {
      let data = store.serialize()
      let data_path = join_path(
        self.base_path,
        @storage.collection_data_path(self.name),
      )
      self.storage.atomic_write(data_path, data, @storage.Data).wait()
    }
    Segmented(seg_bytes) => {
      let base_name = join_path(self.base_path, self.name)
      @placement.async_save_segmented(store, base_name, seg_bytes, self.storage)
    }
  }
}

///|
/// Load a CoreStore from storage, replaying WAL on top.
pub async fn[S : @storage.AsyncStorage] AsyncCollectionPersistence::load(
  self : AsyncCollectionPersistence[S],
) -> @store.CoreStore? {
  let base_name = join_path(self.base_path, self.name)
  let manifest_path = join_path(
    self.base_path,
    @storage.collection_manifest_path(self.name),
  )

  let has_manifest = self.storage.exists(manifest_path, @storage.Index).wait()
  let store : @store.CoreStore? = if has_manifest {
    Some(@placement.async_load_segmented(base_name, self.storage))
  } else {
    let data_path = join_path(
      self.base_path,
      @storage.collection_data_path(self.name),
    )
    let has_data = self.storage.exists(data_path, @storage.Data).wait()
    if has_data {
      let data = self.storage.read(data_path, @storage.Data).wait()
      Some(@store.CoreStore::deserialize(data))
    } else {
      None
    }
  }

  match store {
    None => None
    Some(s) => {
      let _ = self.wal.replay_into(s)
      Some(s)
    }
  }
}

///|
/// Remove all persisted data for a collection.
pub async fn[S : @storage.AsyncStorage] AsyncCollectionPersistence::remove(
  self : AsyncCollectionPersistence[S],
) -> Unit {
  let base_name = join_path(self.base_path, self.name)

  let data_path = join_path(
    self.base_path,
    @storage.collection_data_path(self.name),
  )
  let has_data = self.storage.exists(data_path, @storage.Data).wait()
  if has_data {
    self.storage.del(data_path, @storage.Data).wait()
  }

  let wal_path = join_path(
    self.base_path,
    @storage.collection_wal_path(self.name),
  )
  let has_wal = self.storage.exists(wal_path, @storage.Data).wait()
  if has_wal {
    self.storage.del(wal_path, @storage.Data).wait()
  }

  let manifest_path = join_path(
    self.base_path,
    @storage.collection_manifest_path(self.name),
  )
  let has_manifest = self.storage.exists(manifest_path, @storage.Index).wait()
  if has_manifest {
    self.storage.del(manifest_path, @storage.Index).wait()
  }

  let index_path = join_path(
    self.base_path,
    @storage.collection_index_path(self.name),
  )
  let has_index = self.storage.exists(index_path, @storage.Index).wait()
  if has_index {
    self.storage.del(index_path, @storage.Index).wait()
  }

  let data_files = self.storage.list(@storage.Data).wait()
  for path in data_files {
    if @storage.is_segment_path(path, base_name) {
      self.storage.del(path, @storage.Data).wait()
    }
  }
}
