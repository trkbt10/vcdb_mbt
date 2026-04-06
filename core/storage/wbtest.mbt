// Whitebox tests for storage module

///|
fn run_async_blocking(f : async () -> Unit noraise) -> Unit = "%async.run"

///|
test "storage/async_read_not_found_rejects" {
  let storage = MemoryStorage::new()
  let mut caught = false
  let mut err_msg = ""
  run_async_blocking(async fn() noraise {
    try {
      let _ = async_read(storage, "nonexistent.txt", Data)
    } catch {
      AsyncIOFailed(msg) => {
        caught = true
        err_msg = msg
      }
      _ => ()
    }
  })
  inspect(caught, content="true")
  inspect(err_msg, content="Not found: nonexistent.txt")
}

///|
test "storage/kind_aware_async_read_not_found_rejects" {
  let storage = KindAwareStorage::new()
  let mut caught = false
  let mut err_msg = ""
  run_async_blocking(async fn() noraise {
    try {
      let _ = async_read(storage, "missing.bin", Data)
    } catch {
      AsyncIOFailed(msg) => {
        caught = true
        err_msg = msg
      }
      _ => ()
    }
  })
  inspect(caught, content="true")
  inspect(err_msg, content="Not found: missing.bin")
}

///|
test "storage/memory_readwrite" {
  let storage = MemoryStorage::new()
  let data = Bytes::from_array([b'h', b'e', b'l', b'l', b'o'][:])
  storage.write("test.txt", data)
  let result = storage.read("test.txt") catch { _ => Bytes::new(0) }
  inspect(result.length(), content="5")
}

///|
test "storage/memory_atomic" {
  let storage = MemoryStorage::new()
  let data = Bytes::from_array([b't', b'e', b's', b't'][:])
  storage.atomic_write("atomic.dat", data)
  inspect(storage.exists("atomic.dat"), content="true")
}

///|
test "storage/memory_append" {
  let storage = MemoryStorage::new()
  let data1 = Bytes::from_array([b'a', b'b'][:])
  let data2 = Bytes::from_array([b'c', b'd'][:])
  storage.write("append.txt", data1)
  storage.append("append.txt", data2)
  let result = storage.read("append.txt") catch { _ => Bytes::new(0) }
  inspect(result.length(), content="4")
}

///|
test "storage/memory_delete" {
  let storage = MemoryStorage::new()
  let data = Bytes::from_array([b'x'][:])
  storage.write("del.txt", data)
  inspect(storage.exists("del.txt"), content="true")
  storage.del("del.txt") catch {
    _ => ()
  }
  inspect(storage.exists("del.txt"), content="false")
}

///|
test "storage/memory_list" {
  let storage = MemoryStorage::new()
  storage.write("a.txt", Bytes::new(0))
  storage.write("b.txt", Bytes::new(0))
  let files = storage.list()
  inspect(files.length(), content="2")
}

///|
test "storage/read_not_found" {
  let storage = MemoryStorage::new()
  let result : Bytes = storage.read("nonexistent.txt") catch {
    _ => Bytes::new(0)
  }
  inspect(result.length(), content="0")
}

///|
test "storage/append_new_file" {
  let storage = MemoryStorage::new()
  let data = Bytes::from_array([b'n', b'e', b'w'][:])
  storage.append("new.txt", data)
  let result = storage.read("new.txt") catch { _ => Bytes::new(0) }
  inspect(result.length(), content="3")
}

///|
test "storage/delete_not_found" {
  let storage = MemoryStorage::new()
  // Should not raise error
  storage.del("nonexistent.txt") catch {
    _ => ()
  }
  inspect(storage.exists("nonexistent.txt"), content="false")
}

///|
test "storage/clear" {
  let storage = MemoryStorage::new()
  storage.write("a.txt", Bytes::from_array([b'a'][:]))
  storage.write("b.txt", Bytes::from_array([b'b'][:]))
  inspect(storage.list().length(), content="2")
  storage.clear()
  inspect(storage.list().length(), content="0")
}

///|
test "storage/delete_existing" {
  let storage = MemoryStorage::new()
  storage.write("test.txt", Bytes::from_array([b'x'][:]))
  inspect(storage.exists("test.txt"), content="true")
  storage.del("test.txt") catch {
    _ => ()
  }
  inspect(storage.exists("test.txt"), content="false")
}

///|
test "storage/read_not_found_error" {
  let storage = MemoryStorage::new()
  let result : Bytes = storage.read("nonexistent.txt") catch {
    IOError::NotFound(path) => {
      inspect(path, content="nonexistent.txt")
      Bytes::new(0)
    }
    _ => Bytes::new(0)
  }
  inspect(result.length(), content="0")
}

///|
test "storage/del_not_found_error" {
  let storage = MemoryStorage::new()
  let mut caught = false
  storage.del("nonexistent.txt") catch {
    IOError::NotFound(_) => caught = true
    _ => ()
  }
  inspect(caught, content="true")
}

///|
test "storage/trait_impl" {
  let storage : MemoryStorage = MemoryStorage::new()
  // Test through trait interface - kind is ignored for MemoryStorage
  (storage as &Storage).write(
    "trait_test.txt",
    Bytes::from_array([b't', b'e', b's', b't'][:]),
    Data,
  )
  inspect((storage as &Storage).exists("trait_test.txt", Data), content="true")
  let data = (storage as &Storage).read("trait_test.txt", Data) catch {
    _ => Bytes::new(0)
  }
  inspect(data.length(), content="4")
  let files = (storage as &Storage).list(Data)
  inspect(files.length(), content="1")
  (storage as &Storage).del("trait_test.txt", Data) catch {
    _ => ()
  }
  inspect((storage as &Storage).exists("trait_test.txt", Data), content="false")
}

///|
test "storage/trait_atomic_write" {
  let storage : MemoryStorage = MemoryStorage::new()
  (storage as &Storage).atomic_write(
    "atomic.txt",
    Bytes::from_array([b'a'][:]),
    Config,
  )
  inspect((storage as &Storage).exists("atomic.txt", Config), content="true")
}

///|
test "storage/trait_append" {
  let storage : MemoryStorage = MemoryStorage::new()
  (storage as &Storage).write("append.txt", Bytes::from_array([b'a'][:]), Index)
  (storage as &Storage).append(
    "append.txt",
    Bytes::from_array([b'b'][:]),
    Index,
  )
  let data = (storage as &Storage).read("append.txt", Index) catch {
    _ => Bytes::new(0)
  }
  inspect(data.length(), content="2")
}
