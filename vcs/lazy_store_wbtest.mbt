///|
priv struct LazyFixture {
  root : String
  remote : Repository
  cloned : Repository
  commits : Array[ObjectId]
  blobs : Array[ObjectId]
}

///|
async fn storage_inventory(root : String) -> (Int32, UInt64) {
  let mut count = 0
  let mut bytes = 0UL
  for bucket in @fs.readdir(root + "/.moonvcs/objects") {
    for name in @fs.readdir(root + "/.moonvcs/objects/" + bucket) {
      ignore(ObjectId::parse(bucket + name))
      let encoded = @fs.read_file(
        root + "/.moonvcs/objects/" + bucket + "/" + name,
      ).binary()
      assert_true(
        verify_encoded_object(ObjectId::parse(bucket + name), encoded),
      )
      count = count + 1
      bytes = bytes + encoded.length().to_uint64()
    }
  }
  (count, bytes)
}

///|
async fn with_lazy_fixture(body : async (LazyFixture) -> Unit) -> Unit {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="moonvcs-lazy")
    group.add_defer(() => {
      @async.protect_from_cancel(() => @fs.rmdir(root, recursive=true))
    })
    @fs.mkdir(root + "/remote", permission=0o700)
    let remote = init_test_repository(root + "/remote")
    let commits : Array[ObjectId] = []
    let blobs : Array[ObjectId] = []
    for i = 0; i < 24; i = i + 1 {
      let blob = remote.store.put(
        BlobObject({ content: @utf8.encode("version-" + i.to_string()), }),
      )
      let tree = remote.store.put(
        TreeObject(
          Tree::new([{ name: "file.txt", kind: BlobEntry, object_id: blob, }]),
        ),
      )
      let commit = remote.store.put(
        CommitObject({
          tree_id: tree,
          parents: if i == 0 {
            []
          } else {
            [commits[i - 1]]
          },
          author: "Lazy Test",
          timestamp: i.to_uint64(),
          message: "history-" + i.to_string(),
        }),
      )
      blobs.push(blob)
      commits.push(commit)
    }
    remote.update_ref("refs/heads/main", None, commits[23])
    let cloned = clone_repository(
      remote.root,
      root + "/clone",
      policy_config=remote.policy_configuration(),
    )
    body({ root, remote, cloned, commits, blobs, })
  }
}

///|
async test "partial clone downloads only HEAD and checkout with exact byte statistics" {
  with_lazy_fixture(f => {
    let (remote_count, _) = storage_inventory(f.remote.root)
    let (cached_count, bytes) = storage_inventory(f.cloned.root)
    assert_eq(remote_count, 72)
    assert_eq(cached_count, 3)
    assert_true(cached_count * 10 < remote_count)
    let stats = f.cloned.store.transfer_stats()
    assert_eq(stats.received_objects, cached_count.to_uint64())
    assert_eq(stats.received_bytes, bytes)
    assert_eq(stats.cached_objects, stats.received_objects)
    assert_eq(@fs.read_file(f.cloned.root + "/file.txt").text(), "version-23")
    assert_eq(f.cloned.head(), Some(f.commits[23]))
    assert_eq(f.cloned.status(), [])
    assert_eq(f.cloned.store.state(f.commits[22]), PromisedRemote)
    assert_eq(f.cloned.store.state(f.commits[0]), Unknown)
    assert_eq(f.cloned.store.state(f.commits[23]), Local)
    assert_eq(f.cloned.log(max_count=0), [])
    assert_eq(f.cloned.log(max_count=1).length(), 1)
    assert_eq(f.cloned.store.transfer_stats(), stats)
  })
}

///|
async test "promised miss fetches once and discovers parents without an upfront history catalog" {
  with_lazy_fixture(f => {
    let before = f.cloned.store.transfer_stats()
    assert_false(f.cloned.store.has(f.commits[22]))
    assert_false(f.cloned.store.verify(f.commits[22]))
    let object = f.cloned.get_object(f.commits[22])
    assert_eq(object, f.remote.get_object(f.commits[22]))
    assert_eq(f.cloned.store.state(f.commits[21]), PromisedRemote)
    assert_eq(f.cloned.store.state(f.commits[20]), Unknown)
    let after = f.cloned.store.transfer_stats()
    assert_eq(after.requests, before.requests + 1UL)
    assert_eq(
      after.received_bytes,
      before.received_bytes + encode_object(object).length().to_uint64(),
    )
    assert_eq(f.cloned.get_object(f.commits[22]), object)
    assert_eq(f.cloned.log(max_count=2).length(), 2)
    assert_eq(f.cloned.store.transfer_stats(), after)
    let reopened = Repository::at(f.cloned.root, offline=true)
    assert_eq(reopened.get_object(f.commits[22]), object)
    assert_eq(reopened.store.state(f.commits[21]), PromisedRemote)
  })
}

///|
async test "unknown objects never contact a remote even if that remote really stores the hash" {
  with_lazy_fixture(f => {
    let before = f.cloned.store.transfer_stats()
    guard expect_failure(() => f.cloned.get_object(f.commits[0]))
      is VcsError::UnknownObject(_) else {
      fail("unknown hash was fetched")
    }
    let offline = Repository::at(f.cloned.root, offline=true)
    guard expect_failure(() => offline.get_object(f.commits[0]))
      is VcsError::UnknownObject(_) else {
      fail("unknown incorrectly became offline-unavailable")
    }
    assert_eq(f.cloned.store.transfer_stats(), before)
    // An arbitrary locally-created object is not a promise authority.
    let local_tree = f.cloned.store.put(
      TreeObject(
        Tree::new([{ name: "guess", kind: BlobEntry, object_id: f.blobs[0], }]),
      ),
    )
    f.cloned.get_object(local_tree) |> ignore
    assert_eq(f.cloned.store.state(f.blobs[0]), Unknown)
  })
}

///|
async test "offline cached objects work without the remote and offline misses are explicit" {
  with_lazy_fixture(f => {
    let offline = Repository::at(f.cloned.root, offline=true)
    let before = f.cloned.store.transfer_stats()
    @fs.rename(f.remote.root, f.root + "/remote-disconnected")
    assert_eq(offline.log(max_count=1).length(), 1)
    assert_eq(
      offline.get_object(f.blobs[23]),
      BlobObject({ content: b"version-23", }),
    )
    guard expect_failure(() => offline.get_object(f.commits[22]))
      is VcsError::ObjectUnavailableOffline(_) else {
      fail("offline miss not classified")
    }
    assert_eq(f.cloned.store.transfer_stats(), before)
    guard expect_failure(() => f.cloned.get_object(f.commits[22]))
      is VcsError::RemoteUnavailable(_) else {
      fail("remote failure called corruption")
    }
    assert_eq(f.cloned.store.state(f.commits[22]), PromisedRemote)
    assert_false(f.cloned.store.has(f.commits[22]))
    let after = f.cloned.store.transfer_stats()
    assert_eq(after.requests, before.requests + 1UL)
    assert_eq(after.received_bytes, before.received_bytes)
    @fs.rename(f.root + "/remote-disconnected", f.remote.root)
    f.cloned.get_object(f.commits[22]) |> ignore
  })
}

///|
async test "remote deletion is distinct from unknown offline and corruption" {
  with_lazy_fixture(f => {
    let id = f.commits[22]
    let path = f.remote.store.object_path(id)
    @fs.rename(path, f.root + "/removed-object")
    guard expect_failure(() => f.cloned.get_object(id))
      is VcsError::RemoteObjectMissing(_) else {
      fail("remote deletion not classified")
    }
    assert_eq(f.cloned.store.state(id), PromisedRemote)
    assert_false(f.cloned.store.has(id))
    @fs.rename(f.root + "/removed-object", path)
    f.cloned.get_object(id) |> ignore
    assert_true(f.cloned.store.verify(id))
  })
}

///|
async test "corrupt remote bytes are counted but never cached; retry after repair succeeds" {
  with_lazy_fixture(f => {
    let id = f.commits[22]
    let path = f.remote.store.object_path(id)
    let original = @fs.read_file(path).binary()
    let before = f.cloned.store.transfer_stats()
    @fs.chmod(path, 0o600)
    @fs.write_file(path, b"tampered")
    guard expect_failure(() => f.cloned.get_object(id))
      is VcsError::InvalidObject(_) else {
      fail("checksum mismatch accepted")
    }
    assert_false(f.cloned.store.has(id))
    let after = f.cloned.store.transfer_stats()
    assert_eq(after.received_bytes, before.received_bytes + 8UL)
    assert_eq(after.cached_objects, before.cached_objects)
    @fs.write_file(path, original)
    f.cloned.get_object(id) |> ignore
    assert_true(f.cloned.store.verify(id))
    storage_inventory(f.cloned.root) |> ignore
  })
}

///|
async test "corrupt local hit is not silently refetched or misreported as offline" {
  with_lazy_fixture(f => {
    let id = f.commits[23]
    let before = f.cloned.store.transfer_stats()
    let path = f.cloned.store.object_path(id)
    @fs.chmod(path, 0o600)
    @fs.write_file(path, b"corrupt-cache")
    assert_false(f.cloned.store.verify(id))
    guard expect_failure(() => f.cloned.get_object(id))
      is VcsError::InvalidObject(_) else {
      fail("corrupt local cache was hidden")
    }
    guard expect_failure(() => {
        Repository::at(f.cloned.root, offline=true).get_object(id)
      })
      is VcsError::InvalidObject(_) else {
      fail("offline cache corruption misclassified")
    }
    assert_eq(f.cloned.store.transfer_stats(), before)
  })
}

///|
async test "concurrent misses across store instances coalesce to one transfer" {
  with_lazy_fixture(f => {
    let before = f.cloned.store.transfer_stats()
    @async.with_task_group() <| group => {
      let tasks = []
      for _ in 0..<12 {
        tasks.push(
          group.spawn(() => {
            Repository::at(f.cloned.root).get_object(f.commits[22])
          }),
        )
      }
      for task in tasks {
        assert_eq(object_id_for(task.wait()), f.commits[22])
      }
    }
    let after = f.cloned.store.transfer_stats()
    assert_eq(after.requests, before.requests + 1UL)
    assert_eq(after.received_objects, before.received_objects + 1UL)
    assert_eq(after.cached_objects, before.cached_objects + 1UL)
    let (count, _) = storage_inventory(f.cloned.root)
    assert_eq(count, 4)
  })
}

///|
async test "atomic cache publication never exposes partial bytes to a concurrent local reader" {
  with_lazy_fixture(f => {
    let id = f.commits[22]
    let disk = FileObjectStore::new(f.cloned.root)
    @async.with_task_group() <| group => {
      let fetch = group.spawn(() => f.cloned.get_object(id))
      let reader = group.spawn(() => {
        while !disk.has(id) {
          @async.pause()
        }
        assert_eq(object_id_for(disk.get(id)), id)
        assert_true(disk.verify(id))
      })
      fetch.wait() |> ignore
      reader.wait()
    }
    // Every visible object file is complete and no owned .tmp files remain.
    storage_inventory(f.cloned.root) |> ignore
  })
}

///|
async test "missing edge registration is recovered from cached verified source while offline" {
  with_lazy_fixture(f => {
    let id = f.commits[22]
    @fs.remove(f.cloned.store.promise_path(id))
    let offline = Repository::at(f.cloned.root, offline=true)
    offline.get_object(f.commits[23]) |> ignore
    assert_eq(offline.store.state(id), PromisedRemote)
    guard expect_failure(() => offline.get_object(id))
      is VcsError::ObjectUnavailableOffline(_) else {
      fail("recovered edge not treated as a promise")
    }
    @fs.remove(f.cloned.root + "/.moonvcs/promisor.json")
    guard expect_failure(() => offline.get_object(f.commits[23]))
      is VcsError::InvalidPromise(_) else {
      fail("lost partial-clone metadata was silently ignored")
    }
  })
}

///|
async test "remote Ref advances do not change the clone snapshot and snapshot validation detects changes" {
  with_lazy_fixture(f => {
    let head_bytes = read_remote_metadata(f.remote.root, ".moonvcs/HEAD")
    let ref_bytes = read_remote_metadata(
      f.remote.root,
      ".moonvcs/refs/heads/main",
    )
    let previous = f.commits[23]
    guard f.remote.get_object(previous) is CommitObject(commit) else {
      fail("expected commit")
    }
    let next = f.remote.store.put(
      CommitObject({
        ..commit,
        parents: [previous],
        message: "remote advanced",
        timestamp: 25UL,
      }),
    )
    f.remote.update_ref("refs/heads/main", Some(previous), next)
    guard expect_failure(() => {
        validate_remote_snapshot(
          f.remote.root,
          "refs/heads/main",
          head_bytes,
          ref_bytes,
        )
      })
      is VcsError::RemoteRefChanged(_) else {
      fail("Ref race not detected")
    }
    assert_eq(f.cloned.head(), Some(previous))
    assert_eq(f.cloned.store.state(next), Unknown)
    assert_eq(
      @fs.read_file(f.cloned.root + "/.moonvcs/refs/remotes/origin/main").text(),
      previous.hex + "\n",
    )
  })
}

///|
async test "clone rejects wrong object types matching-hash malformed encodings and unsafe trees" {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="moonvcs-bad-clone")
    group.add_defer(() => {
      @async.protect_from_cancel(() => @fs.rmdir(root, recursive=true))
    })
    for mode in ["wrong-type", "invalid-encoding", "reserved-path"] {
      let remote_root = root + "/" + mode
      @fs.mkdir(remote_root)
      let remote = init_test_repository(remote_root)
      let blob = remote.store.put(BlobObject({ content: b"demo", }))
      let tree = match mode {
        "wrong-type" => blob
        "invalid-encoding" => {
          let bytes = b"matching-hash-but-not-a-canonical-object"
          let id = object_id_for_bytes(bytes)
          let path = remote.store.object_path(id)
          ensure_storage_directory(parent_directory(path))
          @fs.write_file(path, bytes, create_mode=CreateNew)
          id
        }
        _ =>
          remote.store.put(
            TreeObject(
              Tree::new([
                { name: ".moonvcs", kind: BlobEntry, object_id: blob, },
              ]),
            ),
          )
      }
      let commit = remote.store.put(
        CommitObject({
          tree_id: tree,
          parents: [],
          author: "Test",
          timestamp: 1UL,
          message: "bad snapshot",
        }),
      )
      remote.update_ref("refs/heads/main", None, commit)
      let destination = root + "/clone-" + mode
      let error = expect_failure(() => {
        clone_repository(
          remote_root,
          destination,
          policy_config=remote.policy_configuration(),
        )
      })
      match error {
        VcsError::InvalidObject(_) | VcsError::InvalidPath(_) => ()
        _ => fail("invalid remote snapshot was not rejected")
      }
      assert_false(@fs.exists(destination))
      for name in @fs.readdir(root, include_hidden=true) {
        assert_false(name.has_prefix(".moonvcs-clone-"))
      }
    }
  }
}

///|
async test "clone preserves existing destinations and never imports remote executable policy configuration" {
  with_lazy_fixture(f => {
    let configuration = f.cloned.policy_configuration()
    @fs.write_file(
      f.remote.root + "/.moonvcs/policies.json",
      "untrusted remote host selection must never be executed",
    )
    let other = clone_repository(
      f.remote.root,
      f.root + "/other",
      policy_config=configuration,
    )
    assert_eq(other.policy_configuration(), configuration)
    @fs.write_file(other.root + "/sentinel", "user data", create_mode=CreateNew)
    guard expect_failure(() => {
        clone_repository(f.remote.root, other.root, policy_config=configuration)
      })
      is VcsError::RepositoryExists(_) else {
      fail("existing directory was overwritten")
    }
    assert_eq(@fs.read_file(other.root + "/sentinel").text(), "user data")
    let remote = RemoteObjectStore::new(f.remote.root)
    assert_eq(remote.get(f.commits[23]), f.cloned.get_object(f.commits[23]))
    guard expect_failure(() => {
        remote.put(BlobObject({ content: b"not writable", }))
      })
      is VcsError::InvalidCommand(_) else {
      fail("remote accepted a write")
    }
  })
}

///|
async test "local commits in a partial clone retain required Wasm policy enforcement" {
  with_lazy_fixture(f => {
    configure_policies(f.cloned, integration_context())
    @fs.write_file(
      f.cloned.root + "/file.txt",
      "MOONVCS_API_KEY=harmless-lazy-secret",
    )
    f.cloned.add(["file.txt"]) |> ignore
    guard expect_failure(() => f.cloned.commit("Lazy Test", 30UL, "blocked"))
      is VcsError::PolicyRejected(_) else {
      fail("partial clone bypassed required scanner")
    }
    assert_eq(f.cloned.head(), Some(f.commits[23]))
    @fs.write_file(f.cloned.root + "/file.txt", "safe local change")
    f.cloned.add(["file.txt"]) |> ignore
    let local_commit = f.cloned.commit("Lazy Test", 31UL, "local")
    assert_eq(f.cloned.head(), Some(local_commit))
    assert_eq(f.cloned.log(max_count=3).map(pair => pair.0), [
      local_commit,
      f.commits[23],
      f.commits[22],
    ])
  })
}
