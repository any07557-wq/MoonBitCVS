///|
test "empty blob has a stable external SHA-256 vector" {
  // Independent reference input (hex):
  // 4d4f4f4e5643530001010000000000000000
  // Verified with Python hashlib and sha256sum-compatible SHA-256 semantics.
  let id = object_id_for(BlobObject({ content: b"", }))
  assert_eq(
    id.hex,
    "3f2f7192ae4599c2d0886683b3b2833896f695ed1a83af663117e49a894deaa7",
  )
}

///|
test "object hashing is deterministic and type separated" {
  // These objects have the exact same payload (four zero bytes).
  let blob = BlobObject({ content: b"\x00\x00\x00\x00", })
  let empty_tree = TreeObject(Tree::new([]))
  assert_eq(object_id_for(blob), object_id_for(blob))
  assert_not_eq(object_id_for(blob), object_id_for(empty_tree))
  assert_eq(
    object_id_for(blob).hex,
    "9739581cae3d71824298d6b68d0978b9d7a69d7150530af684a66cde7d0596fd",
  )
  assert_eq(
    object_id_for(empty_tree).hex,
    "854955a81ec425451f4d78c00589900a817a2846c0fdf9e628ddd3fa0759f3a7",
  )
  assert_eq(
    object_id_for(BlobObject({ content: b"hello\n", })).hex,
    "a255789328a6ba5556b5f55d01dc72a70dc3970dd4c5d92cd82f9925df130dbf",
  )
}

///|
test "blob tree and commit serialization round trip" {
  let blob = BlobObject({ content: b"hello\x00moonvcs", })
  assert_eq(decode_object(encode_object(blob)), blob)
  let first = object_id_for(BlobObject({ content: b"first", }))
  let second = object_id_for(BlobObject({ content: b"second", }))
  let tree = TreeObject(
    Tree::new([
      { name: "z.txt", kind: BlobEntry, object_id: second, },
      { name: "a.txt", kind: BlobEntry, object_id: first, },
    ]),
  )
  assert_eq(decode_object(encode_object(tree)), tree)
  guard tree is TreeObject(value) else { fail("expected tree") }
  assert_eq(value.entries[0].name, "a.txt")
  let commit = CommitObject({
    tree_id: object_id_for(tree),
    parents: [object_id_for(BlobObject({ content: b"parent", }))],
    author: "测试者",
    timestamp: 1700000000123UL,
    message: "round trip 🌙",
  })
  assert_eq(decode_object(encode_object(commit)), commit)
}

///|
async test "memory store deduplicates and detects corruption" {
  let store = MemoryObjectStore::new()
  let object = BlobObject({ content: b"same bytes", })
  let first = store.put(object)
  let second = store.put(object)
  assert_eq(first, second)
  assert_eq(store.count(), 1)
  assert_true(store.has(first))
  assert_true(store.verify(first))
  assert_eq(store.get(first), object)
  store.corrupt_for_test(first, b"tampered")
  assert_false(store.verify(first))
  let mut detected = false
  try store.get(first) |> ignore catch {
    VcsError::InvalidObject(_) => detected = true
    _ => fail("unexpected corruption error")
  }
  assert_true(detected)
}

///|
async test "memory store supports a commit DAG" {
  let store = MemoryObjectStore::new()
  let tree_id = store.put(TreeObject(Tree::new([])))
  let root = store.put(
    CommitObject({
      tree_id,
      parents: [],
      author: "A",
      timestamp: 1UL,
      message: "root",
    }),
  )
  let child = store.put(
    CommitObject({
      tree_id,
      parents: [root],
      author: "A",
      timestamp: 2UL,
      message: "child",
    }),
  )
  guard store.get(child) is CommitObject(commit) else {
    fail("expected commit")
  }
  assert_eq(commit.parents, [root])
}

///|
async test "repository persists blobs trees commits refs and log order" {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="moonvcs-core")
    group.add_defer() <| () => {
      @async.protect_from_cancel(() => @fs.rmdir(root, recursive=true))
    }
    let repository = init_test_repository(root)
    @fs.write_file(
      root + "/example.txt",
      "first\n",
      create_mode=CreateNew,
      permission=0o600,
    )
    @fs.write_file(
      root + "/empty.bin",
      b"",
      create_mode=CreateNew,
      permission=0o600,
    )
    @fs.write_file(
      root + "/data.bin",
      b"\x00\xff\x01",
      create_mode=CreateNew,
      permission=0o600,
    )
    @fs.write_file(
      root + "/月亮.txt",
      "unicode",
      create_mode=CreateNew,
      permission=0o600,
    )
    @fs.mkdir(root + "/nested", permission=0o700)
    @fs.write_file(
      root + "/nested/child.txt",
      "child",
      create_mode=CreateNew,
      permission=0o600,
    )
    let staged = repository.add(["."])
    assert_eq(staged.length(), 5)
    let first = repository.commit("Alice", 1000UL, "initial")
    assert_eq(repository.head(), Some(first))
    assert_true(repository.store.verify(first))
    assert_eq(repository.status(), [])
    let mut empty_commit_rejected = false
    try repository.commit("Alice", 1500UL, "no changes") |> ignore catch {
      VcsError::InvalidCommand(reason) => {
        assert_eq(reason, "nothing is staged")
        empty_commit_rejected = true
      }
      _ => fail("unexpected empty commit error")
    }
    assert_true(empty_commit_rejected)
    assert_eq(repository.head(), Some(first))
    @fs.write_file(
      root + "/example.txt",
      "second\n",
      create_mode=CreateOrTruncate,
      permission=0o600,
    )
    @fs.remove(root + "/data.bin")
    let dirty = repository.status()
    assert_true(dirty.contains("modified example.txt"))
    assert_true(dirty.contains("deleted data.bin"))
    repository.add(["."]) |> ignore
    let staged_status = repository.status()
    assert_true(staged_status.contains("staged  example.txt"))
    assert_true(staged_status.contains("staged  delete data.bin"))
    let second = repository.commit("Alice", 2000UL, "second")
    let history = repository.log()
    assert_eq(history.length(), 2)
    assert_eq(history[0].0, second)
    assert_eq(history[0].1.message, "second")
    assert_eq(history[1].0, first)
    assert_eq(history[1].1.message, "initial")
    assert_eq(history[0].1.parents, [first])
    guard repository.get_object(second) is CommitObject(latest) else {
      fail("HEAD is not a commit")
    }
    guard repository.get_object(latest.tree_id) is TreeObject(root_tree) else {
      fail("commit tree is not a tree")
    }
    assert_eq(root_tree.entries.length(), 4)
    let mut checked_nested_tree = false
    for entry in root_tree.entries {
      if entry.name == "nested" {
        assert_eq(entry.kind, TreeEntry)
        guard repository.get_object(entry.object_id) is TreeObject(child_tree) else {
          fail("nested object is not a tree")
        }
        assert_eq(child_tree.entries.length(), 1)
        assert_eq(child_tree.entries[0].name, "child.txt")
        checked_nested_tree = true
      }
    }
    assert_true(checked_nested_tree)
  }
}

///|
async test "ref compare-and-swap rejects stale writers" {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="moonvcs-ref")
    group.add_defer() <| () => {
      @async.protect_from_cancel(() => @fs.rmdir(root, recursive=true))
    }
    let repository = init_test_repository(root)
    let tree_id = repository.store.put(TreeObject(Tree::new([])))
    let first = repository.store.put(
      CommitObject({
        tree_id,
        parents: [],
        author: "A",
        timestamp: 1UL,
        message: "first",
      }),
    )
    let second = repository.store.put(
      CommitObject({
        tree_id,
        parents: [first],
        author: "A",
        timestamp: 2UL,
        message: "second",
      }),
    )
    repository.update_ref("refs/heads/main", None, first)
    assert_eq(repository.read_ref("refs/heads/main"), Some(first))
    let mut conflicted = false
    repository.update_ref("refs/heads/main", None, second) catch {
      VcsError::RefConflict(_) => conflicted = true
      _ => fail("unexpected ref update error")
    }
    assert_true(conflicted)
    assert_eq(repository.read_ref("refs/heads/main"), Some(first))
    assert_false(@fs.exists(root + "/.moonvcs/refs/heads/main.lock"))
    repository.update_ref("refs/heads/main", Some(first), second)
    assert_eq(repository.head(), Some(second))
  }
}

///|
async test "policy rejection leaves HEAD unchanged" {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="moonvcs-policy")
    group.add_defer() <| () => {
      @async.protect_from_cancel(() => @fs.rmdir(root, recursive=true))
    }
    let repository = init_test_repository(root)
    @fs.write_file(
      root + "/example.txt",
      "accepted",
      create_mode=CreateNew,
      permission=0o600,
    )
    repository.add(["example.txt"]) |> ignore
    let accepted = repository.commit("Alice", 1000UL, "accepted")
    @fs.write_file(
      root + "/example.txt",
      "rejected",
      create_mode=CreateOrTruncate,
      permission=0o600,
    )
    repository.add(["example.txt"]) |> ignore
    let mut rejected = false
    try
      repository.commit_with_validator(
        "Alice",
        2000UL,
        "blocked",
        MockPolicyValidator::reject("test rejection"),
      )
      |> ignore
    catch {
      VcsError::PolicyRejected(reason) => {
        assert_eq(reason, "test rejection")
        rejected = true
      }
      _ => fail("unexpected policy error")
    }
    assert_true(rejected)
    assert_eq(repository.head(), Some(accepted))
    assert_eq(repository.log().length(), 1)
  }
}
