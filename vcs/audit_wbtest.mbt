///|
async test "remote verify obeys ObjectStore missing corrupt and valid semantics" {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="moonvcs-audit-verify")
    group.add_defer(() => {
      @async.protect_from_cancel(() => @fs.rmdir(root, recursive=true))
    })
    let repository = init_test_repository(root)
    let id = object_id_for(BlobObject({ content: b"verify audit", }))
    let remote = RemoteObjectStore::new(root)
    assert_false(remote.verify(id))
    assert_eq(
      repository.store.put(BlobObject({ content: b"verify audit", })),
      id,
    )
    assert_true(remote.verify(id))
    let path = repository.store.object_path(id)
    @fs.chmod(path, 0o600)
    @fs.write_file(path, b"corrupt")
    assert_false(remote.verify(id))
  }
}

///|
async test "remote verify still raises unavailable provider instead of calling it corruption" {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="moonvcs-audit-unavailable")
    group.add_defer(() => {
      @async.protect_from_cancel(() => @fs.rmdir(root, recursive=true))
    })
    let remote = RemoteObjectStore::new(root + "/missing-remote")
    let id = object_id_for(BlobObject({ content: b"verify audit", }))
    guard expect_failure(() => remote.verify(id))
      is VcsError::RemoteUnavailable(_) else {
      fail("provider failure must remain distinct from invalid object")
    }
  }
}

///|
// Synthetic graph-only fixture. It deliberately violates ObjectStore's hash
// identity contract to exercise cycle defense without claiming to construct a
// SHA-256 fixed point/collision or a valid cyclic content-addressed wire graph.
priv struct AuditGraphStore {
  objects : Map[String, VcsObject]
}

///|
impl ObjectStore for AuditGraphStore with fn put(_, _) {
  raise VcsError::InvalidCommand("read-only graph audit fixture")
}

///|
impl ObjectStore for AuditGraphStore with fn get(self, id) {
  guard self.objects.get(id.hex) is Some(object) else {
    raise VcsError::ObjectNotFound(id.hex)
  }
  object
}

///|
impl ObjectStore for AuditGraphStore with fn has(self, id) {
  self.objects.contains(id.hex)
}

///|
impl ObjectStore for AuditGraphStore with fn verify(self, id) {
  self.objects.contains(id.hex)
}

///|
async test "receive graph cycle guard is exercised with an explicitly synthetic store" {
  let first = ObjectId::parse("1".repeat(64))
  let second = ObjectId::parse("2".repeat(64))
  let tree_id = ObjectId::parse("3".repeat(64))
  let objects : Map[String, VcsObject] = Map([])
  objects[tree_id.hex] = TreeObject(Tree::new([]))
  objects[first.hex] = CommitObject({
    tree_id,
    parents: [second],
    author: "Audit",
    timestamp: 1UL,
    message: "synthetic cycle first",
  })
  objects[second.hex] = CommitObject({
    tree_id,
    parents: [first],
    author: "Audit",
    timestamp: 2UL,
    message: "synthetic cycle second",
  })
  let fixture : AuditGraphStore = { objects, }
  guard expect_failure(() => inspect_receive_graph(fixture, first))
    is VcsError::ReceiveInvalid(reason) else {
    fail("synthetic cycle was accepted")
  }
  assert_true(reason.contains("cycle"))
}

///|
async test "deep valid-hash graph is bounded before snapshot materialization" {
  let store = MemoryObjectStore::new()
  let mut tree_id = store.put(TreeObject(Tree::new([])))
  for _ in 0..<260 {
    tree_id = store.put(
      TreeObject(
        Tree::new([{ name: "nested", kind: TreeEntry, object_id: tree_id, }]),
      ),
    )
  }
  let target = store.put(
    CommitObject({
      tree_id,
      parents: [],
      author: "Audit",
      timestamp: 1UL,
      message: "deep graph",
    }),
  )
  guard expect_failure(() => inspect_receive_graph(store, target))
    is VcsError::ReceiveInvalid(reason) else {
    fail("deep graph was accepted")
  }
  assert_true(reason.contains("depth"))
}
