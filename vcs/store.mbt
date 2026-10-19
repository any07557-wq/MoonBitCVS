///|
pub(open) trait ObjectStore {
  async fn put(Self, VcsObject) -> ObjectId
  async fn get(Self, ObjectId) -> VcsObject
  async fn has(Self, ObjectId) -> Bool
  async fn verify(Self, ObjectId) -> Bool
}

///|
pub struct MemoryObjectStore {
  objects : Map[String, Bytes]
}

///|
pub fn MemoryObjectStore::new() -> MemoryObjectStore {
  { objects: Map([]), }
}

///|
pub fn MemoryObjectStore::count(self : MemoryObjectStore) -> Int32 {
  self.objects.length()
}

///|
pub fn MemoryObjectStore::corrupt_for_test(
  self : MemoryObjectStore,
  id : ObjectId,
  bytes : Bytes,
) -> Unit {
  self.objects[id.hex] = bytes
}

///|
pub impl ObjectStore for MemoryObjectStore with fn put(self, object) {
  let encoded = encode_object(object)
  let id = object_id_for_bytes(encoded)
  if self.objects.get(id.hex) is Some(existing) {
    if !verify_encoded_object(id, existing) {
      raise VcsError::InvalidObject("existing object is corrupt: \{id.hex}")
    }
  } else {
    self.objects[id.hex] = encoded
  }
  id
}

///|
pub impl ObjectStore for MemoryObjectStore with fn get(self, id) {
  guard self.objects.get(id.hex) is Some(encoded) else {
    raise VcsError::ObjectNotFound(id.hex)
  }
  if object_id_for_bytes(encoded) != id {
    raise VcsError::InvalidObject("object checksum mismatch: \{id.hex}")
  }
  decode_object(encoded)
}

///|
pub impl ObjectStore for MemoryObjectStore with fn has(self, id) {
  self.objects.contains(id.hex)
}

///|
pub impl ObjectStore for MemoryObjectStore with fn verify(self, id) {
  match self.objects.get(id.hex) {
    Some(encoded) => verify_encoded_object(id, encoded)
    None => false
  }
}

///|
pub extend MemoryObjectStore with ObjectStore::{put, get, has, verify}

///|
pub struct FileObjectStore {
  objects_dir : String
}

///|
async fn ensure_storage_directory(path : String) -> Unit {
  if @fs.exists(path) {
    if @fs.kind(path, follow_symlink=false) != Directory {
      raise VcsError::InvalidPath("object storage directory is not a directory")
    }
    return
  }
  @fs.mkdir(path, recursive=true, permission=0o755) catch {
    error => {
      if @async.is_cancellation_error(error) {
        raise error
      }
      // A concurrent writer may have created the same bucket.
      if !@fs.exists(path) || @fs.kind(path, follow_symlink=false) != Directory {
        raise error
      }
    }
  }
  sync_storage_directory(path)
  sync_storage_directory(parent_directory(path))
}

///|
pub fn FileObjectStore::new(repository_root : String) -> FileObjectStore {
  { objects_dir: repository_root + "/.moonvcs/objects", }
}

///|
fn FileObjectStore::path(self : FileObjectStore, id : ObjectId) -> String {
  self.objects_dir + "/" + id.hex[:2].to_owned() + "/" + id.hex[2:].to_owned()
}

///|
pub fn FileObjectStore::object_path(
  self : FileObjectStore,
  id : ObjectId,
) -> String {
  self.path(id)
}

///|
pub impl ObjectStore for FileObjectStore with fn put(self, object) {
  let encoded = encode_object(object)
  let id = object_id_for_bytes(encoded)
  let path = self.path(id)
  if @fs.exists(path) {
    if !self.verify(id) {
      raise VcsError::InvalidObject("existing object is corrupt: \{id.hex}")
    }
    return id
  }
  ensure_storage_directory(self.objects_dir + "/" + id.hex[:2].to_owned())
  let nonce = match @env.rand(16) {
    Some(bytes) => object_id_for_bytes(bytes).hex
    None =>
      raise VcsError::InvalidObject(
        "cannot create unique object temporary file",
      )
  }
  let temporary = path + ".tmp-" + nonce
  let file = @fs.open(
    temporary,
    mode=WriteOnly,
    create_mode=CreateNew,
    permission=0o444,
    sync=Full,
  )
  @async.with_task_group() <| group => {
    let mut published = false
    group.add_defer() <| () => {
      @async.protect_from_cancel(() => {
        if !published && @fs.exists(temporary) {
          @fs.remove(temporary)
        }
      })
    }
    {
      defer file.close()
      file.write_at(encoded, position=0L)
      file.sync()
    }
    @fs.rename(temporary, path, replace=false) catch {
      err => if !self.verify(id) { raise err }
    }
    // A racing writer may have already installed the same verified object.
    published = !@fs.exists(temporary)
    if published {
      sync_published_directory(parent_directory(path))
    }
  }
  id
}

///|
pub impl ObjectStore for FileObjectStore with fn get(self, id) {
  let path = self.path(id)
  if !@fs.exists(path) {
    raise VcsError::ObjectNotFound(id.hex)
  }
  let encoded = @fs.read_file(path).binary()
  if object_id_for_bytes(encoded) != id {
    raise VcsError::InvalidObject("object checksum mismatch: \{id.hex}")
  }
  decode_object(encoded)
}

///|
pub impl ObjectStore for FileObjectStore with fn has(self, id) {
  @fs.exists(self.path(id))
}

///|
pub impl ObjectStore for FileObjectStore with fn verify(self, id) {
  let path = self.path(id)
  if !@fs.exists(path) {
    return false
  }
  verify_encoded_object(id, @fs.read_file(path).binary())
}

///|
pub extend FileObjectStore with ObjectStore::{put, get, has, verify}
