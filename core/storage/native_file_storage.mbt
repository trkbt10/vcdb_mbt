///|
/// Filesystem-backed storage for native runtime.

///|
pub struct NativeFileStorage {
  root_dir : String
}

///|
pub fn NativeFileStorage::new(root_dir : String) -> NativeFileStorage {
  { root_dir, }
}

///|
fn kind_dir(kind : StorageKind) -> String {
  match kind {
    Config => "config"
    Index => "index"
    Data => "data"
  }
}

///|
fn join_path(base : String, child : String) -> String {
  @path.Path::join(base, child).to_string()
}

///|
fn dirname(path : String) -> String {
  @path.Path::dirname(path).to_string()
}

///|
fn raise_io_error(e : @fs.IOError) -> Unit raise IOError {
  raise IoFailed(e.to_string())
}

///|
fn ensure_dir(path : String) -> Unit raise IOError {
  if path.length() == 0 || path == "." || path == "/" {
    return
  }
  let chars = path.to_array()
  let current : Array[Char] = []
  let mut start = 0
  if chars.length() > 0 && chars[0] == '/' {
    current.push('/')
    start = 1
  }
  for i in start..<chars.length() {
    let ch = chars[i]
    current.push(ch)
    if ch == '/' {
      let part = String::from_array(current)
      if part.length() > 0 && part != "/" && !@fs.path_exists(part) {
        @fs.create_dir(part) catch {
          e => raise_io_error(e)
        }
      }
    }
  }
  let final_path = String::from_array(current)
  if final_path.length() > 0 &&
    final_path != "/" &&
    !@fs.path_exists(final_path) {
    @fs.create_dir(final_path) catch {
      e => raise_io_error(e)
    }
  }
}

///|
fn NativeFileStorage::full_path(
  self : NativeFileStorage,
  file_path : String,
  kind : StorageKind,
) -> String {
  @path.Path::join(@path.Path::join(self.root_dir, kind_dir(kind)), file_path)
  .normalize()
  .to_string()
}

///|
fn walk_dir(
  abs_dir : String,
  rel_dir : String,
  files : Array[String],
) -> Unit raise IOError {
  if !@fs.path_exists(abs_dir) {
    return
  }
  let is_root_dir = @fs.is_dir(abs_dir) catch {
    e => {
      raise_io_error(e)
      false
    }
  }
  if !is_root_dir {
    raise IoFailed(abs_dir + " is not a directory")
  }
  let entries = @fs.read_dir(abs_dir) catch {
    e => {
      raise_io_error(e)
      []
    }
  }
  for entry in entries {
    let abs_path = join_path(abs_dir, entry)
    let rel_path = if rel_dir.length() == 0 {
      entry
    } else {
      rel_dir + "/" + entry
    }
    let is_dir = @fs.is_dir(abs_path) catch {
      e => {
        raise_io_error(e)
        false
      }
    }
    if is_dir {
      walk_dir(abs_path, rel_path, files)
      continue
    }
    let is_file = @fs.is_file(abs_path) catch {
      e => {
        raise_io_error(e)
        false
      }
    }
    if is_file {
      files.push(rel_path)
    }
  }
}

///|
pub fn NativeFileStorage::read(
  self : NativeFileStorage,
  path : String,
  kind : StorageKind,
) -> Bytes raise IOError {
  let full = self.full_path(path, kind)
  @fs.read_file_to_bytes(full) catch {
    e => {
      raise_io_error(e)
      Bytes::new(0)
    }
  }
}

///|
pub fn NativeFileStorage::write(
  self : NativeFileStorage,
  path : String,
  data : Bytes,
  kind : StorageKind,
) -> Unit raise IOError {
  let full = self.full_path(path, kind)
  ensure_dir(dirname(full))
  @fs.write_bytes_to_file(full, data) catch {
    e => raise_io_error(e)
  }
}

///|
pub fn NativeFileStorage::append(
  self : NativeFileStorage,
  path : String,
  data : Bytes,
  kind : StorageKind,
) -> Unit raise IOError {
  let full = self.full_path(path, kind)
  let existing = if @fs.path_exists(full) {
    @fs.read_file_to_bytes(full) catch {
      e => {
        raise_io_error(e)
        Bytes::new(0)
      }
    }
  } else {
    Bytes::new(0)
  }
  self.write(path, concat_bytes(existing, data), kind)
}

///|
pub fn NativeFileStorage::atomic_write(
  self : NativeFileStorage,
  path : String,
  data : Bytes,
  kind : StorageKind,
) -> Unit raise IOError {
  self.write(path, data, kind)
}

///|
pub fn NativeFileStorage::del(
  self : NativeFileStorage,
  path : String,
  kind : StorageKind,
) -> Unit raise IOError {
  let full = self.full_path(path, kind)
  @fs.remove_file(full) catch {
    e => raise_io_error(e)
  }
}

///|
pub fn NativeFileStorage::exists(
  self : NativeFileStorage,
  path : String,
  kind : StorageKind,
) -> Bool {
  @fs.path_exists(self.full_path(path, kind))
}

///|
pub fn NativeFileStorage::list(
  self : NativeFileStorage,
  kind : StorageKind,
) -> Array[String] raise IOError {
  let files : Array[String] = []
  let root = join_path(self.root_dir, kind_dir(kind))
  walk_dir(root, "", files)
  files
}

///|
pub impl Storage for NativeFileStorage with fn read(self, path, kind) {
  self.read(path, kind)
}

///|
pub impl Storage for NativeFileStorage with fn write(self, path, data, kind) {
  self.write(path, data, kind)
}

///|
pub impl Storage for NativeFileStorage with fn append(self, path, data, kind) {
  self.append(path, data, kind)
}

///|
pub impl Storage for NativeFileStorage with fn atomic_write(
  self,
  path,
  data,
  kind,
) {
  self.atomic_write(path, data, kind)
}

///|
pub impl Storage for NativeFileStorage with fn del(self, path, kind) {
  self.del(path, kind)
}

///|
pub impl Storage for NativeFileStorage with fn exists(self, path, kind) {
  self.exists(path, kind)
}

///|
pub impl Storage for NativeFileStorage with fn list(self, kind) {
  self.list(kind)
}

///|
fn io_error_message(e : IOError) -> String {
  match e {
    NotFound(s) => "Not found: " + s
    PermissionDenied(s) => "Permission denied: " + s
    IoFailed(s) => "IO failed: " + s
  }
}

///|
/// AsyncStorage implementation for NativeFileStorage.
/// Wraps synchronous filesystem I/O — resolve is called immediately.
/// This enables NativeFileStorage to be used with PersistentVectorDB
/// and all async persistence infrastructure on native targets.
pub impl AsyncStorage for NativeFileStorage with fn async_read(
  self,
  path,
  kind,
  resolve,
  reject,
) {
  let data = self.read(path, kind) catch {
    e => {
      reject(io_error_message(e))
      return
    }
  }
  resolve(data)
}

///|
pub impl AsyncStorage for NativeFileStorage with fn async_write(
  self,
  path,
  data,
  kind,
  resolve,
  reject,
) {
  self.write(path, data, kind) catch {
    e => {
      reject(io_error_message(e))
      return
    }
  }
  resolve()
}

///|
pub impl AsyncStorage for NativeFileStorage with fn async_atomic_write(
  self,
  path,
  data,
  kind,
  resolve,
  reject,
) {
  self.atomic_write(path, data, kind) catch {
    e => {
      reject(io_error_message(e))
      return
    }
  }
  resolve()
}

///|
pub impl AsyncStorage for NativeFileStorage with fn async_del(
  self,
  path,
  kind,
  resolve,
  reject,
) {
  self.del(path, kind) catch {
    e => {
      reject(io_error_message(e))
      return
    }
  }
  resolve()
}

///|
pub impl AsyncStorage for NativeFileStorage with fn async_exists(
  self,
  path,
  kind,
  resolve,
  _reject,
) {
  resolve(self.exists(path, kind))
}

///|
pub impl AsyncStorage for NativeFileStorage with fn async_list(
  self,
  kind,
  resolve,
  reject,
) {
  let files = self.list(kind) catch {
    e => {
      reject(io_error_message(e))
      return
    }
  }
  resolve(files)
}
