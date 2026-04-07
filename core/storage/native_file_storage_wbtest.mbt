///|
fn test_join_path(base : String, child : String) -> String {
  @path.Path::join(base, child).to_string()
}

///|
fn run_async_blocking(f : async () -> Unit noraise) -> Unit = "%async.run"

///|
fn remove_tree(path : String) -> Unit {
  if !@fs.path_exists(path) {
    return
  }
  if (@fs.is_dir(path) catch { _ => false }) {
    let entries = @fs.read_dir(path) catch { _ => [] }
    for entry in entries {
      remove_tree(test_join_path(path, entry))
    }
    @fs.remove_dir(path) catch {
      _ => ()
    }
  } else {
    @fs.remove_file(path) catch {
      _ => ()
    }
  }
}

///|
test "native file storage read write list" {
  let root = "/tmp/vcdb-native-storage-wbtest"
  remove_tree(root)
  let storage = NativeFileStorage::new(root)

  storage.write("demo/test.bin", Bytes::from_array([b'a', b'b'][:]), Data)
  assert_true(storage.exists("demo/test.bin", Data))

  let data = storage.read("demo/test.bin", Data)
  assert_eq(data.length(), 2)

  let files = storage.list(Data)
  assert_true(files.contains("demo/test.bin"))

  storage.del("demo/test.bin", Data)
  assert_false(storage.exists("demo/test.bin", Data))

  remove_tree(root)
}

///|
test "native file storage append propagates read failure" {
  let root = "/tmp/vcdb-native-storage-append-failure-wbtest"
  remove_tree(root)
  let data_root = test_join_path(root, "data")
  let nested = test_join_path(data_root, "demo")
  let bad_path = test_join_path(nested, "bad.bin")
  @fs.create_dir(root) catch {
    _ => abort("failed to create test root")
  }
  @fs.create_dir(data_root) catch {
    _ => abort("failed to create data root")
  }
  @fs.create_dir(nested) catch {
    _ => abort("failed to create nested dir")
  }
  @fs.create_dir(bad_path) catch {
    _ => abort("failed to create bad path dir")
  }

  let storage = NativeFileStorage::new(root)
  let mut failed = false
  storage.append("demo/bad.bin", Bytes::from_array([b'x'][:]), Data) catch {
    _ => failed = true
  }

  assert_true(failed)
  assert_true(@fs.is_dir(bad_path) catch { _ => false })
  remove_tree(root)
}

///|
test "native file storage list propagates traversal failure" {
  let root = "/tmp/vcdb-native-storage-list-failure-wbtest"
  remove_tree(root)
  @fs.create_dir(root) catch {
    _ => abort("failed to create test root")
  }
  let data_root = test_join_path(root, "data")
  @fs.write_bytes_to_file(data_root, Bytes::from_array([b'x'][:])) catch {
    _ => abort("failed to create blocking file")
  }

  let storage = NativeFileStorage::new(root)
  let mut failed = false
  storage.list(Data) catch {
    _ => failed = true
  }

  assert_true(failed)
  remove_tree(root)
}

///|
test "native file storage async_list rejects traversal failure" {
  let root = "/tmp/vcdb-native-storage-async-list-failure-wbtest"
  remove_tree(root)
  @fs.create_dir(root) catch {
    _ => abort("failed to create test root")
  }
  let data_root = test_join_path(root, "data")
  @fs.write_bytes_to_file(data_root, Bytes::from_array([b'x'][:])) catch {
    _ => abort("failed to create blocking file")
  }

  let storage = NativeFileStorage::new(root)
  let mut failed = false
  run_async_blocking(async fn() noraise {
    try {
      let _ = async_list(storage, Data)
    } catch {
      AsyncIOFailed(_) => failed = true
      _ => ()
    }
  })

  assert_true(failed)
  remove_tree(root)
}
