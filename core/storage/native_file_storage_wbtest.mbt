///|
fn test_join_path(base : String, child : String) -> String {
  @path.Path::join(base, child).to_string()
}

///|
fn remove_tree(path : String) -> Unit {
  if not(@fs.path_exists(path)) {
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
