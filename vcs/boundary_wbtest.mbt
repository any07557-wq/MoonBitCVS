///|
async fn[T] expect_failure(f : async () -> T) -> Error {
  try f() catch {
    error => error
  } noraise {
    _ => fail("expected operation to fail")
  }
}

///|
fn wrapped_payload(kind : Int32, payload : Bytes) -> Bytes {
  let encoder = Encoder::new()
  encoder.bytes(object_magic)
  encoder.byte(1)
  encoder.byte(kind)
  encoder.u64(payload.length().to_uint64())
  encoder.bytes(payload)
  encoder.finish()
}

///|
test "malformed and noncanonical object encodings are rejected" {
  let id = object_id_for(BlobObject({ content: b"x", }))
  let payload = Encoder::new()
  payload.u32(2)
  for name in ["z", "a"] {
    payload.byte(1)
    payload.string(name)
    payload.object_id(id)
  }
  let malformed = [
    b"",
    b"not an object",
    wrapped_payload(99, b""),
    wrapped_payload(2, b"\x80\x00\x00\x00"),
    wrapped_payload(2, b"\x00\x00\x00\x01"),
    wrapped_payload(2, payload.finish()),
    wrapped_payload(1, b"ok") + b"extra",
  ]
  for bytes in malformed {
    let rejected = try decode_object(bytes) catch {
      _ => true
    } noraise {
      _ => false
    }
    assert_true(rejected)
    // A matching SHA-256 alone must not validate malformed remote bytes.
    assert_false(verify_encoded_object(object_id_for_bytes(bytes), bytes))
  }
}

///|
test "tree ordering is UTF-8 byte order and independent of insertion order" {
  let id = object_id_for(BlobObject({ content: b"x", }))
  let names = ["🌙", "月亮", "a", "\uE000"]
  let entries = names.map(name => TreeEntry::{
    name,
    kind: BlobEntry,
    object_id: id,
  })
  let tree = Tree::new(entries)
  assert_eq(tree.entries.map(entry => entry.name), [
    "a", "月亮", "\uE000", "🌙",
  ])
  entries.rev_in_place()
  assert_eq(
    object_id_for(TreeObject(tree)),
    object_id_for(TreeObject(Tree::new(entries))),
  )
}

///|
test "paths cannot traverse into parent directories or metadata" {
  assert_eq(
    normalize_repository_path("./nested//月亮.txt"),
    "nested/月亮.txt",
  )
  for
    path in [
      "", "/tmp/file", "../file", "a/../../b", ".moonvcs/HEAD", "a\\b", "a\u0000b",
    ] {
    let rejected = try normalize_repository_path(path) catch {
      VcsError::InvalidPath(_) => true
      _ => fail("unexpected path error")
    } noraise {
      _ => false
    }
    assert_true(rejected)
  }
}

///|
async test "disk store round trips bytes and rejects corrupted persisted objects" {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="moonvcs-store")
    group.add_defer(() => {
      @async.protect_from_cancel(() => @fs.rmdir(root, recursive=true))
    })
    let repository = init_test_repository(root)
    let blob = BlobObject({ content: b"\x00\xff\x01", })
    let id = repository.store.put(blob)
    assert_eq(repository.store.put(blob), id)
    let reopened = FileObjectStore::new(root)
    assert_eq(reopened.get(id), blob)
    assert_true(reopened.has(id))
    let path = reopened.object_path(id)
    @fs.chmod(path, 0o600)
    @fs.write_file(path, b"corrupt", create_mode=TruncateExisting)
    assert_false(reopened.verify(id))
    guard expect_failure(() => reopened.get(id)) is VcsError::InvalidObject(_) else {
      fail("corrupt object was not rejected")
    }
    guard expect_failure(() => reopened.put(blob)) is VcsError::InvalidObject(_) else {
      fail("put silently replaced a corrupt object")
    }
  }
}

///|
async test "symlink files and ancestor directories are rejected without changing index" {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="moonvcs-paths")
    group.add_defer(() => {
      @async.protect_from_cancel(() => @fs.rmdir(root, recursive=true))
    })
    let repository = init_test_repository(root)
    @fs.mkdir(root + "/real", permission=0o700)
    @fs.write_file(root + "/real/file.txt", "contents", create_mode=CreateNew)
    repository.add(["real"]) |> ignore
    let index = repository.load_index()
    @fs.symlink(root + "/link", target=root + "/real")
    for path in ["link", "link/file.txt"] {
      guard expect_failure(() => repository.add([path]))
        is VcsError::InvalidPath(_) else {
        fail("symlink was not rejected")
      }
      assert_eq(repository.load_index(), index)
    }
    guard expect_failure(() => repository.status()) is VcsError::InvalidPath(_) else {
      fail("status followed a symlink")
    }
    @fs.remove(root + "/link")
    @fs.symlink(root + "/outside", target=parent_directory(root))
    guard expect_failure(() => repository.add(["outside"]))
      is VcsError::InvalidPath(_) else {
      fail("outside path was not rejected")
    }
    @fs.remove(root + "/outside")
  }
}

///|
async test "existing locks are preserved and failed ref writes clean their own lock" {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="moonvcs-locks")
    group.add_defer(() => {
      @async.protect_from_cancel(() => @fs.rmdir(root, recursive=true))
    })
    let repository = init_test_repository(root)
    @fs.write_file(root + "/file", "contents", create_mode=CreateNew)
    repository.add(["file"]) |> ignore
    let candidate = repository.make_candidate("A", 1UL, "initial")
    let id = repository.store.put(
      CommitObject({
        tree_id: candidate.tree_id,
        parents: [],
        author: "A",
        timestamp: 1UL,
        message: "initial",
      }),
    )
    let lock = root + "/.moonvcs/refs/heads/main.lock"
    @fs.write_file(lock, "other writer", create_mode=CreateNew)
    expect_failure(() => repository.update_ref("refs/heads/main", None, id))
    |> ignore
    assert_eq(@fs.read_file(lock).text(), "other writer")
    assert_eq(repository.head(), None)
    @fs.remove(lock)
    let ref_file = root + "/.moonvcs/refs/heads/main"
    @fs.write_file(ref_file, "invalid object id\n", create_mode=CreateNew)
    expect_failure(() => repository.update_ref("refs/heads/main", None, id))
    |> ignore
    assert_false(@fs.exists(lock))
    assert_eq(@fs.read_file(ref_file).text(), "invalid object id\n")
    let index_lock = root + "/.moonvcs/index.lock"
    @fs.write_file(index_lock, "other writer", create_mode=CreateNew)
    let index = repository.load_index()
    expect_failure(() => repository.add(["file"])) |> ignore
    assert_eq(repository.load_index(), index)
    assert_eq(@fs.read_file(index_lock).text(), "other writer")
  }
}

///|
priv struct FailurePolicy {
  throws : Bool
}

///|
impl PolicyValidator for FailurePolicy with fn validate(self, candidate) {
  assert_eq(candidate.staged_files[0].content, b"staged bytes")
  if self.throws {
    raise VcsError::InvalidObject("policy invocation failed")
  }
  PolicyError("policy could not decide")
}

///|
async test "candidate uses staged bytes and policy errors never publish a commit" {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="moonvcs-candidate")
    group.add_defer(() => {
      @async.protect_from_cancel(() => @fs.rmdir(root, recursive=true))
    })
    let repository = init_test_repository(root)
    @fs.write_file(root + "/file", "staged bytes", create_mode=CreateNew)
    repository.add(["file"]) |> ignore
    @fs.write_file(
      root + "/file",
      "working bytes",
      create_mode=TruncateExisting,
    )
    for throws in [false, true] {
      expect_failure(() => {
        repository.commit_with_validator("A", 1UL, "initial", FailurePolicy::{
          throws,
        })
      })
      |> ignore
      assert_eq(repository.head(), None)
    }
    let candidate = repository.make_candidate("A", 1UL, "initial")
    let commit_id = object_id_for(
      CommitObject({
        tree_id: candidate.tree_id,
        parents: [],
        author: "A",
        timestamp: 1UL,
        message: "initial",
      }),
    )
    assert_false(repository.store.has(commit_id))
  }
}

///|
priv struct RacingPolicy {
  repository : Repository
  target : ObjectId
}

///|
impl PolicyValidator for RacingPolicy with fn validate(self, candidate) {
  self.repository.update_ref(
    "refs/heads/main",
    Some(candidate.parents[0]),
    self.target,
  )
  PolicyPass
}

///|
async test "a ref changed during validation cannot be overwritten by the candidate" {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="moonvcs-race")
    group.add_defer(() => {
      @async.protect_from_cancel(() => @fs.rmdir(root, recursive=true))
    })
    let repository = init_test_repository(root)
    @fs.write_file(root + "/file", "first", create_mode=CreateNew)
    repository.add(["file"]) |> ignore
    let first = repository.commit("A", 1UL, "first")
    @fs.write_file(root + "/file", "second", create_mode=TruncateExisting)
    repository.add(["file"]) |> ignore
    let candidate = repository.make_candidate("A", 2UL, "candidate")
    let other = repository.store.put(
      CommitObject({
        tree_id: candidate.tree_id,
        parents: [first],
        author: "B",
        timestamp: 2UL,
        message: "other writer",
      }),
    )
    let error = expect_failure(() => {
      repository.commit_with_validator("A", 2UL, "candidate", RacingPolicy::{
        repository,
        target: other,
      })
    })
    guard error is VcsError::RefConflict(_) else {
      fail("expected ref conflict")
    }
    assert_eq(repository.head(), Some(other))
    assert_false(@fs.exists(root + "/.moonvcs/refs/heads/main.lock"))
  }
}
