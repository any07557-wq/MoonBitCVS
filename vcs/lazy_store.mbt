// Transport and promise metadata live in this adapter, not the ObjectStore trait.

///|
let max_remote_object_bytes = 33554432

///|
pub struct LocalObjectStore {
  disk : FileObjectStore
}

///|
pub fn LocalObjectStore::new(root : String) -> LocalObjectStore {
  { disk: FileObjectStore::new(root), }
}

///|
pub impl ObjectStore for LocalObjectStore with fn put(self, object) {
  if encode_object(object).length() > max_remote_object_bytes {
    raise VcsError::InvalidObject("object exceeds adapter size limit")
  }
  self.disk.put(object)
}

///|
pub impl ObjectStore for LocalObjectStore with fn get(self, id) {
  if !self.disk.has(id) {
    raise VcsError::ObjectNotFound(id.hex)
  }
  decode_verified_storage_object(
    id,
    read_bounded_storage_file(
      self.disk.object_path(id),
      max_remote_object_bytes,
    ),
  )
}

///|
pub impl ObjectStore for LocalObjectStore with fn has(self, id) {
  self.disk.has(id)
}

///|
pub impl ObjectStore for LocalObjectStore with fn verify(self, id) {
  if !self.disk.has(id) {
    return false
  }
  try self.get(id) |> ignore catch {
    error => {
      if @async.is_cancellation_error(error) {
        raise error
      }
      return false
    }
  }
  true
}

///|
pub extend LocalObjectStore with ObjectStore::{put, get, has, verify}

///|
pub struct RemoteObjectStore {
  root : String
}

///|
pub fn RemoteObjectStore::new(root : String) -> RemoteObjectStore {
  { root, }
}

///|
async fn read_bounded_storage_file(path : String, limit : Int32) -> Bytes {
  if @fs.kind(path, follow_symlink=false) != Regular {
    raise VcsError::InvalidObject("storage path is not a regular file")
  }
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  if file.kind() != Regular {
    raise VcsError::InvalidObject("storage path is not a regular file")
  }
  let size = file.size()
  if size < 0L || size > limit.to_int64() {
    raise VcsError::InvalidObject("storage file exceeds size limit")
  }
  let bytes = file.read_exactly_at(size.to_int(), position=0L)
  if file.size() != size {
    raise VcsError::RemoteUnavailable("storage file changed during read")
  }
  bytes
}

///|
pub async fn RemoteObjectStore::fetch_encoded(
  self : RemoteObjectStore,
  id : ObjectId,
) -> Bytes {
  ignore(ObjectId::parse(id.hex))
  if !@fs.exists(self.root + "/.moonvcs/objects") {
    raise VcsError::RemoteUnavailable("configured promisor is unavailable")
  }
  let relative = ".moonvcs/objects/" +
    id.hex[:2].to_owned() +
    "/" +
    id.hex[2:].to_owned()
  let path = self.root + "/" + relative
  if !@fs.exists(path) {
    raise VcsError::RemoteObjectMissing(id.hex)
  }
  try {
    reject_symlink_components(self.root, relative)
    let real = @fs.realpath(path)
    if !within_root(self.root, real) {
      raise VcsError::InvalidObject("remote object escapes configured root")
    }
    read_bounded_storage_file(path, max_remote_object_bytes)
  } catch {
    VcsError::InvalidObject(_) as error => raise error
    VcsError::InvalidPath(_) =>
      raise VcsError::InvalidObject(
        "remote object path contains a symbolic link",
      )
    error => {
      if @async.is_cancellation_error(error) {
        raise error
      }
      raise VcsError::RemoteUnavailable("configured promisor read failed")
    }
  }
}

///|
pub impl ObjectStore for RemoteObjectStore with fn put(_, _) {
  raise VcsError::InvalidCommand("filesystem remote is read-only")
}

///|
pub impl ObjectStore for RemoteObjectStore with fn get(self, id) {
  decode_verified_storage_object(id, self.fetch_encoded(id))
}

///|
pub impl ObjectStore for RemoteObjectStore with fn has(self, id) {
  @fs.exists(FileObjectStore::new(self.root).object_path(id))
}

///|
pub impl ObjectStore for RemoteObjectStore with fn verify(self, id) {
  // A missing object is false, as in the local/memory implementations. A failed
  // provider is still an error: availability must not be called corruption.
  verify_encoded_object(id, self.fetch_encoded(id)) catch {
    VcsError::RemoteObjectMissing(_) | VcsError::InvalidObject(_) => false
    error => raise error
  }
}

///|
pub extend RemoteObjectStore with ObjectStore::{put, get, has, verify}

///|
fn decode_verified_storage_object(
  id : ObjectId,
  bytes : Bytes,
) -> VcsObject raise {
  if object_id_for_bytes(bytes) != id {
    raise VcsError::InvalidObject("object checksum mismatch: " + id.hex)
  }
  // decode_object also enforces type/version and canonical re-encoding.
  decode_object(bytes)
}

///|
pub(all) enum ObjectState {
  Local
  PromisedRemote
  Unknown
} derive(Eq, Debug)

///|
priv struct PromisorConfig {
  schema : Int32
  remote_root : String
  head_ref : String
  head_id : String
} derive(@json.FromJson, @json.ToJson)

///|
priv struct ObjectPromise {
  schema : Int32
  id : String
  kind : String
  source : String
  anchor : String
} derive(@json.FromJson, @json.ToJson)

///|
priv struct VerifiedPromiseSource {
  kind : String
  edges : Map[String, Bool]
}

///|
priv struct PromiseValidation {
  sources : Map[String, VerifiedPromiseSource]
  mut indexed_edges : Int32
}

///|
fn new_promise_validation() -> PromiseValidation {
  { sources: Map([]), indexed_edges: 0, }
}

///|
fn promise_edge_key(id : ObjectId, kind : String) -> String {
  id.hex + ":" + kind
}

///|
fn PromiseValidation::remember(
  self : PromiseValidation,
  id : ObjectId,
  object : VcsObject,
) -> VerifiedPromiseSource? {
  if self.sources.get(id.hex) is Some(source) {
    return Some(source)
  }
  let edge_count = match object {
    BlobObject(_) => 0
    TreeObject(tree) => tree.entries.length()
    CommitObject(commit) => commit.parents.length() + 1
  }
  // Request-local bounds, not a total process-memory guarantee. Above these
  // limits keep the original verified read/linear edge check, never skip it.
  if self.sources.length() >= 16 || edge_count > 16384 - self.indexed_edges {
    return None
  }
  let edges : Map[String, Bool] = Map([])
  for (target, kind) in object_references(object) {
    edges[promise_edge_key(target, kind)] = true
  }
  let source : VerifiedPromiseSource = { kind: object_kind(object), edges, }
  self.sources[id.hex] = source
  self.indexed_edges = self.indexed_edges + edge_count
  Some(source)
}

///|
pub struct TransferStats {
  requests : UInt64
  received_objects : UInt64
  received_bytes : UInt64
  cached_objects : UInt64
} derive(@json.FromJson, @json.ToJson, Eq, Debug)

///|
pub extend TransferStats with @json.ToJson::{to_json}

///|
fn empty_transfer_stats() -> TransferStats {
  {
    requests: 0UL,
    received_objects: 0UL,
    received_bytes: 0UL,
    cached_objects: 0UL,
  }
}

///|
pub struct LazyObjectStore {
  root : String
  cache : LocalObjectStore
  offline : Bool
  fetch_events : Bool
}

///|
pub fn LazyObjectStore::new(
  root : String,
  offline~ : Bool = false,
  fetch_events~ : Bool = false,
) -> LazyObjectStore {
  { root, cache: LocalObjectStore::new(root), offline, fetch_events, }
}

///|
pub fn LazyObjectStore::object_path(
  self : LazyObjectStore,
  id : ObjectId,
) -> String {
  self.cache.disk.object_path(id)
}

///|
async fn LazyObjectStore::promisor(self : LazyObjectStore) -> PromisorConfig? {
  let path = self.root + "/.moonvcs/promisor.json"
  if !@fs.exists(path) {
    if @fs.exists(self.root + "/.moonvcs/promises") {
      raise VcsError::InvalidPromise(
        "partial clone lost its promisor configuration",
      )
    }
    return None
  }
  let config : PromisorConfig = @json.from_json(
    @json.parse(@utf8.decode(read_bounded_storage_file(path, 65536))),
  ) catch {
    _ => raise VcsError::InvalidPromise("invalid promisor metadata")
  }
  if config.schema != 1 ||
    !config.remote_root.has_prefix("/") ||
    config.remote_root == "/" {
    raise VcsError::InvalidPromise("invalid promisor version or path")
  }
  try {
    ignore(ObjectId::parse(config.head_id))
    ignore(ref_path(self.root, config.head_ref))
  } catch {
    _ => raise VcsError::InvalidPromise("invalid promisor Ref anchor")
  }
  Some(config)
}

///|
fn LazyObjectStore::promise_path(
  self : LazyObjectStore,
  id : ObjectId,
) -> String {
  self.root + "/.moonvcs/promises/" + id.hex
}

///|
fn object_kind(object : VcsObject) -> String {
  match object {
    BlobObject(_) => "blob"
    TreeObject(_) => "tree"
    CommitObject(_) => "commit"
  }
}

///|
fn object_references(object : VcsObject) -> Array[(ObjectId, String)] {
  match object {
    BlobObject(_) => []
    CommitObject(commit) => {
      let links = [(commit.tree_id, "tree")]
      for parent in commit.parents {
        links.push((parent, "commit"))
      }
      links
    }
    TreeObject(tree) =>
      tree.entries.map(entry => {
        (
          entry.object_id,
          match entry.kind {
            BlobEntry => "blob"
            TreeEntry => "tree"
          },
        )
      })
  }
}

///|
async fn LazyObjectStore::read_promise_record(
  self : LazyObjectStore,
  id : ObjectId,
  config : PromisorConfig,
) -> ObjectPromise? {
  let path = self.promise_path(id)
  if !@fs.exists(path) {
    return None
  }
  let promise : ObjectPromise = @json.from_json(
    @json.parse(@utf8.decode(read_bounded_storage_file(path, 4096))),
  ) catch {
    _ => raise VcsError::InvalidPromise("invalid object promise")
  }
  if promise.schema != 1 ||
    promise.id != id.hex ||
    promise.anchor != config.head_id ||
    !["blob", "tree", "commit"].contains(promise.kind) {
    raise VcsError::InvalidPromise("object promise identity/type mismatch")
  }
  Some(promise)
}

///|
async fn LazyObjectStore::read_promise(
  self : LazyObjectStore,
  id : ObjectId,
  config : PromisorConfig,
  validation : PromiseValidation,
  index_source~ : Bool = true,
) -> ObjectPromise? {
  guard self.read_promise_record(id, config) is Some(promise) else {
    return None
  }
  if promise.source == "ref" {
    if id.hex != config.head_id || promise.kind != "commit" {
      raise VcsError::InvalidPromise("invalid Ref promise")
    }
  } else {
    let source = ObjectId::parse(promise.source) catch {
      _ => raise VcsError::InvalidPromise("invalid promise source ID")
    }
    // Records are issued only by this adapter under trusted local metadata.
    // Check the immediate edge again rather than trusting a guessed hash.
    if !self.cache.has(source) {
      raise VcsError::InvalidPromise(
        "promise source is not a cached promisor object",
      )
    }
    guard self.read_promise_record(source, config) is Some(source_promise) else {
      raise VcsError::InvalidPromise(
        "promise source has no promisor provenance",
      )
    }
    let remembered = if index_source {
      validation.sources.get(source.hex)
    } else {
      None
    }
    let (kind, has_edge) = match remembered {
      Some(verified) =>
        (
          verified.kind,
          verified.edges.contains(promise_edge_key(id, promise.kind)),
        )
      None => {
        let object = self.cache.get(source)
        let verified = if index_source {
          validation.remember(source, object)
        } else {
          None
        }
        match verified {
          Some(verified) =>
            (
              verified.kind,
              verified.edges.contains(promise_edge_key(id, promise.kind)),
            )
          None =>
            (
              object_kind(object),
              object_references(object).contains((id, promise.kind)),
            )
        }
      }
    }
    if source_promise.kind != kind {
      raise VcsError::InvalidPromise("promise source type is inconsistent")
    }
    if !has_edge {
      raise VcsError::InvalidPromise(
        "promise is not an edge of its verified source",
      )
    }
  }
  Some(promise)
}

///|
async fn LazyObjectStore::record_links(
  self : LazyObjectStore,
  id : ObjectId,
  object : VcsObject,
  config : PromisorConfig,
  validation : PromiseValidation,
) -> Unit {
  // The caller has verified the target hash/canonical encoding and promised
  // type. Reuse its immediate edge index only within this locked get call.
  validation.remember(id, object) |> ignore
  for (target, kind) in object_references(object) {
    let path = self.promise_path(target)
    if @fs.exists(path) {
      guard self.read_promise(target, config, validation) is Some(existing) else {
        raise VcsError::InvalidPromise("lost promise")
      }
      if existing.kind != kind {
        raise VcsError::InvalidObject(
          "remote graph references an object with conflicting types",
        )
      }
    } else {
      let promise : ObjectPromise = {
        schema: 1,
        id: target.hex,
        kind,
        source: id.hex,
        anchor: config.head_id,
      }
      write_atomic(path, @utf8.encode(@json.to_json(promise).stringify()))
    }
  }
}

///|
pub async fn LazyObjectStore::state(
  self : LazyObjectStore,
  id : ObjectId,
) -> ObjectState {
  ignore(ObjectId::parse(id.hex))
  if self.cache.has(id) {
    return Local
  }
  if self.promisor() is Some(config) &&
    self.read_promise(id, config, new_promise_validation(), index_source=false)
    is Some(_) {
    PromisedRemote
  } else {
    Unknown
  }
}

///|
pub async fn LazyObjectStore::transfer_stats(
  self : LazyObjectStore,
) -> TransferStats {
  let path = self.root + "/.moonvcs/transfer-stats.json"
  if !@fs.exists(path) {
    return empty_transfer_stats()
  }
  @json.from_json(
    @json.parse(@utf8.decode(read_bounded_storage_file(path, 4096))),
  )
}

///|
async fn LazyObjectStore::write_stats(
  self : LazyObjectStore,
  stats : TransferStats,
) -> Unit {
  write_atomic(
    self.root + "/.moonvcs/transfer-stats.json",
    @utf8.encode(@json.to_json(stats).stringify()),
  )
}

///|
fn LazyObjectStore::event(self : LazyObjectStore, message : String) -> Unit {
  if self.fetch_events {
    println("[Fetch] " + message)
  }
}

///|
async fn acquire_fetch_lock(root : String) -> @fs.File {
  let file = @fs.open(
    root + "/.moonvcs/lazy-fetch.lock",
    mode=ReadWrite,
    create_mode=OpenOrCreate,
    permission=0o600,
  )
  errdefer file.close()
  @async.with_timeout(30000, () => {
    while !file.try_lock(Exclusive) {
      @async.sleep(5)
    }
  })
  file
}

///|
pub impl ObjectStore for LazyObjectStore with fn put(self, object) {
  // Locally-created objects do not confer remote promises on arbitrary hashes.
  self.cache.put(object)
}

///|
pub impl ObjectStore for LazyObjectStore with fn get(self, id) {
  ignore(ObjectId::parse(id.hex))
  let config = self.promisor()
  if config is None {
    if self.cache.has(id) {
      return self.cache.get(id)
    }
    raise VcsError::UnknownObject(id.hex)
  }
  // Stable advisory lock inode; close releases it even on cancellation/death.
  // This intentionally serializes fetches in the MVP and coalesces processes.
  let lock = acquire_fetch_lock(self.root)
  defer lock.close()
  defer lock.unlock()
  guard config is Some(config) else { abort("unreachable") }
  // Never retained in LazyObjectStore or across calls, including errors/cancel.
  let validation = new_promise_validation()
  // A Blob get/state check has no batch of outgoing links. Avoid building a
  // potentially wide index for this one-off incoming-edge check.
  let promise = self.read_promise(id, config, validation, index_source=false)
  if self.cache.has(id) {
    let object = self.cache.get(id) // Corruption never falls back to the remote.
    if promise is Some(p) {
      if object_kind(object) != p.kind {
        raise VcsError::InvalidObject("cached object violates promised type")
      }
      // Also repairs interrupted edge-registration after a successful cache write.
      self.record_links(id, object, config, validation)
    }
    return object
  }
  guard promise is Some(promise) else { raise VcsError::UnknownObject(id.hex) }
  if self.offline {
    raise VcsError::ObjectUnavailableOffline(id.hex)
  }
  self.event("Local Cache Miss " + id.hex)
  self.event("Remote Fetch " + id.hex)
  let before = self.transfer_stats()
  self.write_stats({ ..before, requests: before.requests + 1UL, })
  let bytes = RemoteObjectStore::new(config.remote_root).fetch_encoded(id)
  let received : TransferStats = {
    ..before,
    requests: before.requests + 1UL,
    received_objects: before.received_objects + 1UL,
    received_bytes: before.received_bytes + bytes.length().to_uint64(),
  }
  self.write_stats(received)
  let object = decode_verified_storage_object(id, bytes)
  if object_kind(object) != promise.kind {
    raise VcsError::InvalidObject(
      "remote object violates promised type: " + id.hex,
    )
  }
  self.event("Hash Verified " + id.hex + " bytes=" + bytes.length().to_string())
  if self.cache.put(object) != id {
    raise VcsError::InvalidObject("cache encoding changed object identity")
  }
  self.write_stats({
    ..received,
    cached_objects: received.cached_objects + 1UL,
  })
  self.record_links(id, object, config, validation)
  self.event("Cached " + id.hex)
  object
}

///|
pub impl ObjectStore for LazyObjectStore with fn has(self, id) {
  self.cache.has(id)
}

///|
pub impl ObjectStore for LazyObjectStore with fn verify(self, id) {
  self.cache.verify(id)
}

///|
pub extend LazyObjectStore with ObjectStore::{put, get, has, verify}
