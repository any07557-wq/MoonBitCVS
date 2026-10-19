///|
fn test_promise_bytes(promise : ObjectPromise) -> Bytes {
  @utf8.encode(@json.to_json(promise).stringify())
}

///|
test "request edge indexes preserve typed edges and have bounded capacity" {
  let id = object_id_for(BlobObject({ content: b"index target", }))
  let object = TreeObject(
    Tree::new([
      { name: "a", kind: BlobEntry, object_id: id, },
      { name: "b", kind: TreeEntry, object_id: id, },
    ]),
  )
  let validation = new_promise_validation()
  guard validation.remember(object_id_for(object), object) is Some(source) else {
    fail("small source was not indexed")
  }
  assert_true(source.edges.contains(promise_edge_key(id, "blob")))
  assert_true(source.edges.contains(promise_edge_key(id, "tree")))
  assert_false(source.edges.contains(promise_edge_key(id, "commit")))
  assert_eq(validation.indexed_edges, 2)
  validation.remember(object_id_for(object), object) |> ignore
  assert_eq(validation.indexed_edges, 2)
  for i in 0..<15 {
    let blob = BlobObject({ content: @utf8.encode(i.to_string()), })
    assert_true(validation.remember(object_id_for(blob), blob) is Some(_))
  }
  let extra = BlobObject({ content: b"over capacity", })
  assert_true(validation.remember(object_id_for(extra), extra) is None)
  let full = new_promise_validation()
  full.indexed_edges = 16384
  assert_true(full.remember(object_id_for(object), object) is None)
  assert_eq(full.indexed_edges, 16384)
}

///|
async test "reused source index still rechecks provenance type and source presence" {
  with_lazy_fixture(f => {
    let store = f.cloned.store
    guard store.promisor() is Some(config) else { fail("no promisor") }
    let validation = new_promise_validation()
    let id = f.blobs[23]
    let one_off = new_promise_validation()
    assert_true(
      store.read_promise(id, config, one_off, index_source=false) is Some(_),
    )
    assert_eq(one_off.sources.length(), 0)
    guard store.read_promise(id, config, validation) is Some(promise) else {
      fail("no child promise")
    }
    let source = ObjectId::parse(promise.source)
    guard store.read_promise_record(source, config) is Some(original) else {
      fail("no source provenance")
    }
    assert_eq(validation.sources.length(), 1)
    write_atomic(
      store.promise_path(source),
      test_promise_bytes({ ..original, kind: "blob", }),
    )
    guard expect_failure(() => store.read_promise(id, config, validation))
      is VcsError::InvalidPromise(_) else {
      fail("cached index bypassed source type")
    }
    @fs.remove(store.promise_path(source))
    guard expect_failure(() => store.read_promise(id, config, validation))
      is VcsError::InvalidPromise(_) else {
      fail("cached index bypassed source provenance")
    }
    write_atomic(store.promise_path(source), test_promise_bytes(original))
    @fs.rename(store.object_path(source), f.root + "/removed-source")
    guard expect_failure(() => store.read_promise(id, config, validation))
      is VcsError::InvalidPromise(_) else {
      fail("cached index bypassed source presence")
    }
  })
}

///|
async test "source hash is revalidated on the next get on the same store instance" {
  with_lazy_fixture(f => {
    let store = f.cloned.store
    guard store.promisor() is Some(config) else { fail("no promisor") }
    guard store.read_promise_record(f.blobs[23], config) is Some(promise) else {
      fail("no child promise")
    }
    let source = ObjectId::parse(promise.source)
    store.get(source) |> ignore
    let path = store.object_path(source)
    let original = @fs.read_file(path).binary()
    @fs.chmod(path, 0o600)
    @fs.write_file(path, b"corrupt-source-after-successful-get")
    let before = store.transfer_stats()
    guard expect_failure(() => store.get(f.blobs[23]))
      is VcsError::InvalidObject(_) else {
      fail("request cache leaked into a later get")
    }
    assert_eq(store.transfer_stats(), before)
    @fs.write_file(path, original)
    assert_eq(store.get(f.blobs[23]), BlobObject({ content: b"version-23", }))
  })
}

///|
async test "warm tree gets still reject forged child identity anchor type and source" {
  with_lazy_fixture(f => {
    let store = f.cloned.store
    guard store.promisor() is Some(config) else { fail("no promisor") }
    guard store.read_promise_record(f.blobs[23], config) is Some(original) else {
      fail("no child promise")
    }
    let source = ObjectId::parse(original.source)
    store.get(source) |> ignore
    let before = store.transfer_stats()
    for
      altered in [
        { ..original, id: f.blobs[0].hex, },
        { ..original, anchor: f.commits[0].hex, },
        { ..original, kind: "tree", },
        { ..original, source: f.commits[23].hex, },
      ] {
      write_atomic(store.promise_path(f.blobs[23]), test_promise_bytes(altered))
      guard expect_failure(() => store.get(source))
        is VcsError::InvalidPromise(_) else {
        fail("tree edge-index reuse trusted a forged child promise")
      }
      write_atomic(
        store.promise_path(f.blobs[23]),
        test_promise_bytes(original),
      )
      store.get(source) |> ignore
    }
    assert_eq(store.transfer_stats(), before)
  })
}

///|
async test "a different verified source must actually contain the promised typed edge" {
  with_lazy_fixture(f => {
    let store = f.cloned.store
    guard store.promisor() is Some(config) else { fail("no promisor") }
    guard store.get(f.commits[22]) is CommitObject(previous) else {
      fail("no previous commit")
    }
    store.get(previous.tree_id) |> ignore
    guard store.read_promise_record(f.blobs[23], config) is Some(original) else {
      fail("no child promise")
    }
    let source = ObjectId::parse(original.source)
    write_atomic(
      store.promise_path(f.blobs[23]),
      test_promise_bytes({ ..original, source: previous.tree_id.hex, }),
    )
    guard expect_failure(() => store.get(source)) is VcsError::InvalidPromise(_) else {
      fail("current tree's cached edge was used for a different source")
    }
  })
}

///|
async test "exhausted index budget falls back to full verified source validation" {
  with_lazy_fixture(f => {
    let store = f.cloned.store
    guard store.promisor() is Some(config) else { fail("no promisor") }
    let validation = new_promise_validation()
    validation.indexed_edges = 16384
    assert_true(store.read_promise(f.blobs[23], config, validation) is Some(_))
    assert_eq(validation.sources.length(), 0)
    guard store.read_promise_record(f.blobs[23], config) is Some(original) else {
      fail("no child promise")
    }
    write_atomic(
      store.promise_path(f.blobs[23]),
      test_promise_bytes({ ..original, kind: "tree", }),
    )
    guard expect_failure(() => {
        store.read_promise(f.blobs[23], config, validation)
      })
      is VcsError::InvalidPromise(_) else {
      fail("budget fallback skipped typed edge validation")
    }
  })
}
