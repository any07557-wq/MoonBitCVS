// Server receive authority. No client policy result or policy configuration
// enters this interface. ObjectStore.get here never consults a promisor remote.

///|
priv struct ReceiveOverlay {
  quarantine : LocalObjectStore
  published : LocalObjectStore
}

///|
impl ObjectStore for ReceiveOverlay with fn put(_, _) {
  raise VcsError::ReceiveInvalid("receive graph overlay is read-only")
}

///|
impl ObjectStore for ReceiveOverlay with fn get(self, id) {
  if self.quarantine.has(id) {
    self.quarantine.get(id)
  } else {
    self.published.get(id)
  }
}

///|
impl ObjectStore for ReceiveOverlay with fn has(self, id) {
  self.quarantine.has(id) || self.published.has(id)
}

///|
impl ObjectStore for ReceiveOverlay with fn verify(self, id) {
  if self.quarantine.has(id) {
    self.quarantine.verify(id)
  } else {
    self.published.verify(id)
  }
}

///|
priv struct ReceiveGraph {
  store : &ObjectStore
  marks : Map[String, Int32]
  kinds : Map[String, String]
  ordered : Array[ObjectId]
  commits : Array[(ObjectId, Commit)]
  mut bytes : UInt64
  mut edges : Int32
}

///|
async fn ReceiveGraph::visit(
  self : ReceiveGraph,
  id : ObjectId,
  expected_kind : String,
  depth : Int32,
) -> Unit {
  self.edges = self.edges + 1
  if depth > 256 || self.edges > 32768 {
    raise VcsError::ReceiveInvalid("object graph depth/edge limit exceeded")
  }
  if self.kinds.get(id.hex) is Some(kind) && kind != expected_kind {
    raise VcsError::ReceiveInvalid(
      "object graph has conflicting type references",
    )
  }
  match self.marks.get(id.hex) {
    Some(1) => raise VcsError::ReceiveInvalid("object graph contains a cycle")
    Some(2) => return
    _ => ()
  }
  if self.marks.length() >= max_receive_objects {
    raise VcsError::ReceiveInvalid("object graph count limit exceeded")
  }
  let object = self.store.get(id) catch {
    error => {
      if @async.is_cancellation_error(error) {
        raise error
      }
      raise VcsError::ReceiveInvalid("object graph is incomplete or corrupt")
    }
  }
  if object_kind(object) != expected_kind {
    raise VcsError::ReceiveInvalid("object graph type mismatch")
  }
  self.bytes = self.bytes + encode_object(object).length().to_uint64()
  if self.bytes > 67108864UL {
    raise VcsError::ReceiveInvalid("object graph byte limit exceeded")
  }
  if object is CommitObject(commit) {
    if commit.parents.length() > 1 {
      raise VcsError::ReceiveInvalid("receive MVP rejects merge history")
    }
    if self.commits.length() >= 128 {
      raise VcsError::ReceiveInvalid("receive history exceeds 128 commits")
    }
  }
  self.kinds[id.hex] = expected_kind
  self.marks[id.hex] = 1
  for (child, kind) in object_references(object) {
    self.visit(child, kind, depth + 1)
  }
  self.marks[id.hex] = 2
  self.ordered.push(id)
  if object is CommitObject(commit) {
    self.commits.push((id, commit))
  }
}

///|
async fn inspect_receive_graph(
  store : &ObjectStore,
  target : ObjectId,
) -> ReceiveGraph {
  let graph : ReceiveGraph = {
    store,
    marks: Map([]),
    kinds: Map([]),
    ordered: [],
    commits: [],
    bytes: 0UL,
    edges: 0,
  }
  graph.visit(target, "commit", 0)
  if graph.commits.length() > 128 {
    raise VcsError::ReceiveInvalid("receive history exceeds 128 commits")
  }
  graph
}

///|
async fn acquire_receive_lock(root : String) -> @fs.File {
  let file = @fs.open(
    root + "/.moonvcs/receive-publish.lock",
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
fn parse_receive_policy(text : String) -> PolicyContext raise {
  let context = parse_policy_context(text) catch {
    _ =>
      raise VcsError::ReceivePolicyError(
        "invalid server required-policy configuration",
      )
  }
  if context.schema != 2 || context.required.is_empty() {
    raise VcsError::ReceivePolicyError(
      "server requires schema 2 and at least one required policy",
    )
  }
  context
}

///|
async fn receive_policy_text(server : Repository) -> String {
  @utf8.decode(
    read_bounded_storage_file(
      server.root + "/.moonvcs/receive-policies.json",
      65536,
    ),
  ) catch {
    _ =>
      raise VcsError::ReceivePolicyError(
        "server required-policy configuration is missing or unreadable",
      )
  }
}

///|
// Trusted administrative API, never dispatched by a received bundle.
pub async fn install_receive_policy(
  server : Repository,
  text : String,
  initialize~ : Bool = false,
) -> Unit {
  ignore(parse_receive_policy(text))
  if @utf8.encode(text).length() > 65536 {
    raise VcsError::ReceivePolicyError(
      "server policy configuration exceeds size limit",
    )
  }
  if @fs.exists(server.root + "/.moonvcs/promisor.json") {
    raise VcsError::ReceiveInvalid(
      "receive server must be a complete repository",
    )
  }
  let lock = acquire_receive_lock(server.root)
  defer lock.close()
  defer lock.unlock()
  let transaction = acquire_staging_lock(server.root)
  defer transaction.close()
  defer transaction.unlock()
  let path = server.root + "/.moonvcs/receive-policies.json"
  if initialize && @fs.exists(path) {
    raise VcsError::ReceivePolicyError(
      "server receive policy is already initialized",
    )
  }
  write_atomic(path, @utf8.encode(text))
}

///|
priv struct ReceiveSnapshotBudget {
  mut bytes : Int32
  mut entries : Int32
}

///|
async fn receive_snapshot_files(
  store : &ObjectStore,
  tree_id : ObjectId,
  prefix : String,
  files : Array[CandidateFile],
  budget : ReceiveSnapshotBudget,
  max_bytes : Int32,
  depth : Int32,
) -> Unit {
  if depth > 128 {
    raise VcsError::ReceiveInvalid("snapshot directory depth exceeded")
  }
  guard store.get(tree_id) is TreeObject(tree) else {
    raise VcsError::ReceiveInvalid("snapshot expected Tree")
  }
  for entry in tree.entries {
    budget.entries = budget.entries + 1
    if budget.entries > 4096 {
      raise VcsError::ReceiveInvalid("snapshot entry count exceeded")
    }
    let path = if prefix == "" { entry.name } else { prefix + "/" + entry.name }
    let canonical = normalize_repository_path(path) catch {
      _ =>
        raise VcsError::ReceiveInvalid(
          "snapshot contains reserved or unsafe path",
        )
    }
    if canonical != path || @utf8.encode(path).length() > 4096 {
      raise VcsError::ReceiveInvalid("snapshot contains unsafe path")
    }
    match entry.kind {
      TreeEntry =>
        receive_snapshot_files(
          store,
          entry.object_id,
          path,
          files,
          budget,
          max_bytes,
          depth + 1,
        )
      BlobEntry => {
        guard store.get(entry.object_id) is BlobObject(blob) else {
          raise VcsError::ReceiveInvalid("snapshot expected Blob")
        }
        budget.bytes = budget.bytes +
          blob.content.length() +
          @utf8.encode(path).length()
        if budget.bytes > max_bytes {
          raise VcsError::ReceiveInvalid(
            "full snapshot exceeds policy input limit",
          )
        }
        files.push({ path, blob_id: entry.object_id, content: blob.content, })
      }
    }
  }
}

///|
async fn validate_received_history(
  graph : ReceiveGraph,
  context : PolicyContext,
) -> Unit {
  // Parent-first order, every reachable Commit, under current server policy.
  for (_, commit) in graph.commits {
    let files : Array[CandidateFile] = []
    receive_snapshot_files(
      graph.store,
      commit.tree_id,
      "",
      files,
      { bytes: @utf8.encode(commit.message).length(), entries: 0, },
      context.limits.max_input_bytes,
      0,
    )
    let candidate : CommitCandidate = {
      tree_id: commit.tree_id,
      parents: commit.parents.copy(),
      author: commit.author,
      timestamp: commit.timestamp,
      message: commit.message,
      staged_files: files,
    }
    match validate_policies(candidate, context, hook="on-receive") {
      Accept => ()
      Warning(diagnostics) => println(format_policy_diagnostics(diagnostics))
      Reject(diagnostics) =>
        raise VcsError::ReceiveRejected(format_policy_diagnostics(diagnostics))
      EngineError(reason) => raise VcsError::ReceivePolicyError(reason)
    }
  }
}

///|
async fn receive_quarantined(
  server : Repository,
  request : ReceiveRequest,
  quarantine_root : String,
) -> ReceiveReport {
  let quarantine = LocalObjectStore::new(quarantine_root)
  let published = LocalObjectStore::new(server.root)
  for item in request.objects {
    let object = decode_verified_storage_object(item.id, item.encoded) catch {
      _ =>
        raise VcsError::ReceiveInvalid(
          "received object hash/type/canonical validation failed",
        )
    }
    if quarantine.put(object) != item.id {
      raise VcsError::ReceiveInvalid("quarantine identity mismatch")
    }
  }
  let overlay : ReceiveOverlay = { quarantine, published, }
  let graph = inspect_receive_graph(overlay, request.target)
  for item in request.objects {
    if !graph.marks.contains(item.id.hex) {
      raise VcsError::ReceiveInvalid(
        "bundle contains unreachable extra objects",
      )
    }
  }
  if request.expected_old is Some(old) {
    if old == request.target {
      raise VcsError::ReceiveRejected("no-op Ref updates are not supported")
    }
    if !graph.commits.any(pair => pair.0 == old) {
      raise VcsError::ReceiveRejected("non-fast-forward update is forbidden")
    }
  }
  let configuration = receive_policy_text(server)
  let context = parse_receive_policy(configuration)
  validate_received_history(graph, context)
  let lock = acquire_receive_lock(server.root)
  defer lock.close()
  defer lock.unlock()
  let transaction = acquire_staging_lock(server.root)
  defer transaction.close()
  defer transaction.unlock()
  if receive_policy_text(server) != configuration {
    raise VcsError::ReceivePolicyError(
      "server policy changed during validation; retry required",
    )
  }
  if server.read_ref(request.ref_name) != request.expected_old {
    raise VcsError::RefConflict(request.ref_name)
  }
  // A valid quarantined duplicate must not hide a corrupt published object.
  // Recheck every existing graph object before any promotion, not just the tip.
  for id in graph.ordered {
    if published.has(id) {
      (published.get(id) |> ignore) catch {
        _ => raise VcsError::ReceiveInvalid("published graph object is corrupt")
      }
    } else if !quarantine.has(id) {
      raise VcsError::ReceiveInvalid("published graph object disappeared")
    }
  }
  let mut promoted = 0
  for id in graph.ordered {
    if quarantine.has(id) && !published.has(id) {
      if published.put(quarantine.get(id)) != id {
        raise VcsError::ReceiveInvalid("object promotion identity mismatch")
      }
      promoted = promoted + 1
    }
  }
  ensure_storage_directory(
    parent_directory(ref_path(server.root, request.ref_name)),
  )
  // This CAS also coordinates with existing local commits' exclusive Ref locks.
  server.update_ref(request.ref_name, request.expected_old, request.target)
  {
    ref_name: request.ref_name,
    target: request.target,
    checked_commits: graph.commits.length(),
    promoted_objects: promoted,
    policy_revision: "sha256:" +
    object_id_for_bytes(@utf8.encode(configuration)).hex,
  }
}

///|
pub async fn receive_candidate(
  server : Repository,
  request : ReceiveRequest,
) -> ReceiveReport {
  assert_no_switch(server.root)
  // Freeze mutable caller-owned arrays before the first suspension.
  let request : ReceiveRequest = { ..request, objects: request.objects.copy(), }
  validate_receive_request(request) catch {
    _ => raise VcsError::ReceiveInvalid("invalid Ref update request")
  }
  if @fs.exists(server.root + "/.moonvcs/promisor.json") {
    raise VcsError::ReceiveInvalid(
      "receive server must be a complete repository",
    )
  }
  if server.read_ref(request.ref_name) != request.expected_old {
    raise VcsError::RefConflict(request.ref_name)
  }
  ensure_storage_directory(server.root + "/.moonvcs/quarantine")
  let nonce = match @env.rand(16) {
    Some(bytes) => object_id_for_bytes(bytes).hex
    None =>
      raise VcsError::ReceiveInvalid("cannot allocate quarantine identifier")
  }
  let quarantine_root = server.root + "/.moonvcs/quarantine/rx-" + nonce
  @fs.mkdir(quarantine_root, permission=0o700)
  @async.with_task_group() <| group => {
    group.add_defer(() => {
      @async.protect_from_cancel(() => {
        @fs.rmdir(quarantine_root, recursive=true) catch {
          _ =>
            println(
              "[Receive] owned quarantine cleanup pending; administrative inspection required",
            )
        }
      })
    })
    ensure_storage_directory(quarantine_root + "/.moonvcs/objects")
    let lease = @fs.open(
      quarantine_root + "/active.lock",
      mode=ReadWrite,
      create_mode=CreateNew,
      permission=0o600,
    )
    defer lease.close()
    defer lease.unlock()
    if !lease.try_lock(Exclusive) {
      raise VcsError::ReceiveInvalid("cannot acquire owned quarantine lease")
    }
    sync_storage_directory(quarantine_root)
    @async.with_timeout(60000, () => {
      receive_quarantined(server, request, quarantine_root)
    })
  }
}
