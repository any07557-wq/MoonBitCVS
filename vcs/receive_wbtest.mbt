///|
priv struct ReceiveFixture {
  root : String
  server : Repository
  client : Repository
  base : ObjectId
}

///|
// Deliberately bypass Repository.commit and all local hooks.
async fn unchecked_receive_commit(
  client : Repository,
  files : Array[(String, Bytes)],
  parents : Array[ObjectId],
  message : String,
) -> ObjectId {
  let tree = DirectoryNode::new()
  for (path, bytes) in files {
    let id = client.store.put(BlobObject({ content: bytes, }))
    tree.insert(path.split("/").map(p => p.to_owned()).collect(), id)
  }
  let tree_id = write_directory(client.store, tree)
  client.store.put(
    CommitObject({
      tree_id,
      parents,
      author: "Untrusted Client",
      timestamp: 123UL,
      message,
    }),
  )
}

///|
async fn assert_receive_quarantine_empty(server : Repository) -> Unit {
  let path = server.root + "/.moonvcs/quarantine"
  if @fs.exists(path) {
    assert_eq(@fs.readdir(path, include_hidden=true), [])
  }
}

///|
async fn with_receive_fixture(body : async (ReceiveFixture) -> Unit) -> Unit {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="moonvcs-receive")
    group.add_defer(() => {
      @async.protect_from_cancel(() => @fs.rmdir(root, recursive=true))
    })
    @fs.mkdir(root + "/server")
    @fs.mkdir(root + "/client")
    let server = integration_repository(root + "/server")
    install_receive_policy(
      server,
      @json.to_json(integration_context()).stringify(),
      initialize=true,
    )
    let client = init_test_repository(root + "/client")
    let base = unchecked_receive_commit(
      client,
      [("config.env", b"APP_MODE=base\n")],
      [],
      "base",
    )
    let report = receive_candidate(
      server,
      prepare_receive_request(client, "refs/heads/main", None, base),
    )
    assert_eq(report.checked_commits, 1)
    assert_eq(report.promoted_objects, 3)
    assert_eq(server.head(), Some(base))
    body({ root, server, client, base, })
    assert_receive_quarantine_empty(server)
  }
}

///|
async fn receive_child_request(
  fixture : ReceiveFixture,
  content : Bytes,
  message : String,
) -> ReceiveRequest {
  let target = unchecked_receive_commit(
    fixture.client,
    [("config.env", content)],
    [fixture.base],
    message,
  )
  prepare_receive_request(
    fixture.client,
    "refs/heads/main",
    Some(fixture.base),
    target,
  )
}

///|
async test "valid receive runs actual server policies and publishes a complete graph atomically" {
  with_receive_fixture(f => {
    let request = receive_child_request(f, b"APP_MODE=published\n", "safe")
    let index = f.server.load_index()
    let report = receive_candidate(f.server, request)
    assert_eq(report.target, request.target)
    assert_eq(report.checked_commits, 2)
    assert_eq(report.promoted_objects, 3)
    assert_true(report.policy_revision.has_prefix("sha256:"))
    assert_eq(f.server.head(), Some(request.target))
    assert_eq(f.server.load_index(), index) // Receive never checks out a working tree.
    assert_eq(f.server.log().map(pair => pair.0), [request.target, f.base])
    storage_inventory(f.server.root) |> ignore
  })
}

///|
async test "server rejects direct client-hook bypass and preserves all published objects and refs" {
  with_receive_fixture(f => {
    let before = storage_inventory(f.server.root)
    let request = receive_child_request(
      f, b"MOONVCS_API_KEY=harmless-remote-do-not-log\n", "bypass",
    )
    guard expect_failure(() => receive_candidate(f.server, request))
      is VcsError::ReceiveRejected(reason) else {
      fail("server accepted an unscanned secret")
    }
    assert_true(reason.contains("secret-scanner"))
    assert_false(reason.contains("harmless-remote-do-not-log"))
    assert_eq(f.server.head(), Some(f.base))
    assert_false(f.server.store.has(request.target))
    assert_eq(storage_inventory(f.server.root), before)
    assert_receive_quarantine_empty(f.server)
    let repaired = receive_child_request(f, b"APP_MODE=repaired\n", "retry")
    receive_candidate(f.server, repaired) |> ignore
    assert_eq(f.server.head(), Some(repaired.target))
  })
}

///|
async test "a secret introduced then removed in the tip is rejected by full reachable-history scanning" {
  with_receive_fixture(f => {
    let secret = unchecked_receive_commit(
      f.client,
      [("nested/config.env", b"MOONVCS_ACCESS_TOKEN=harmless-history-token")],
      [f.base],
      "hidden secret",
    )
    let clean_tip = unchecked_receive_commit(
      f.client,
      [("nested/config.env", b"APP_MODE=clean")],
      [secret],
      "removed at tip",
    )
    let request = prepare_receive_request(
      f.client,
      "refs/heads/main",
      Some(f.base),
      clean_tip,
    )
    guard expect_failure(() => receive_candidate(f.server, request))
      is VcsError::ReceiveRejected(reason) else {
      fail("tip-only scanning missed history secret")
    }
    assert_true(reason.contains("nested/config.env"))
    assert_false(reason.contains("harmless-history-token"))
    assert_eq(f.server.head(), Some(f.base))
    assert_false(f.server.store.has(secret))
    assert_false(f.server.store.has(clean_tip))
  })
}

///|
async test "hash mismatch and invalid object graphs never escape quarantine" {
  with_receive_fixture(f => {
    let before = storage_inventory(f.server.root)
    let valid = receive_child_request(f, b"APP_MODE=good", "target")
    let corrupted : ReceiveRequest = {
      ..valid,
      objects: valid.objects.map(item => {
        if item.id == valid.target {
          { id: item.id, encoded: b"tampered", }
        } else {
          item
        }
      }),
    }
    guard expect_failure(() => receive_candidate(f.server, corrupted))
      is VcsError::ReceiveInvalid(_) else {
      fail("invalid object hash accepted")
    }
    let malformed = b"matching-hash-without-a-typed-envelope"
    let malformed_id = object_id_for_bytes(malformed)
    let malformed_request : ReceiveRequest = {
      ref_name: "refs/heads/main",
      expected_old: Some(f.base),
      target: malformed_id,
      objects: [{ id: malformed_id, encoded: malformed, }],
    }
    guard expect_failure(() => receive_candidate(f.server, malformed_request))
      is VcsError::ReceiveInvalid(_) else {
      fail("hash-only validation accepted malformed encoding")
    }
    let incomplete : ReceiveRequest = {
      ..valid,
      objects: valid.objects.filter(item => item.id == valid.target),
    }
    guard expect_failure(() => receive_candidate(f.server, incomplete))
      is VcsError::ReceiveInvalid(_) else {
      fail("missing tree accepted")
    }
    let bad_commit = f.client.store.put(
      CommitObject({
        tree_id: f.base,
        parents: [f.base],
        author: "Client",
        timestamp: 124UL,
        message: "wrong tree type",
      }),
    )
    let bad : ReceiveRequest = {
      ref_name: "refs/heads/main",
      expected_old: Some(f.base),
      target: bad_commit,
      objects: [
        {
          id: bad_commit,
          encoded: encode_object(f.client.store.get(bad_commit)),
        },
      ],
    }
    guard expect_failure(() => receive_candidate(f.server, bad))
      is VcsError::ReceiveInvalid(_) else {
      fail("graph type confusion accepted")
    }
    assert_eq(f.server.head(), Some(f.base))
    assert_eq(storage_inventory(f.server.root), before)
  })
}

///|
async test "server rejects unreachable extra uploads and client policy-result trailers" {
  with_receive_fixture(f => {
    let request = receive_child_request(f, b"APP_MODE=good", "wire")
    let bytes = encode_receive_request(request)
    let decoded = decode_receive_request(bytes)
    assert_eq(decoded.target, request.target)
    for length in [1, 8, bytes.length() - 1] {
      let mut truncated_rejected = false
      try decode_receive_request(bytes[:length].to_owned()) |> ignore catch {
        _ => truncated_rejected = true
      }
      assert_true(truncated_rejected)
    }
    let mut rejected = false
    try
      decode_receive_request(bytes + b"client_policy_result=Pass") |> ignore
    catch {
      VcsError::ReceiveInvalid(_) => rejected = true
      _ => fail("unexpected protocol error")
    }
    assert_true(rejected)
    let extra = BlobObject({ content: b"unreachable upload", })
    let objects = request.objects.copy()
    objects.push({ id: object_id_for(extra), encoded: encode_object(extra), })
    guard expect_failure(() => {
        receive_candidate(f.server, { ..request, objects, })
      })
      is VcsError::ReceiveInvalid(_) else {
      fail("unreachable object was promoted")
    }
    assert_false(f.server.store.has(object_id_for(extra)))
    assert_eq(f.server.head(), Some(f.base))
  })
}

///|
async test "client repository policy files and hostile Ref paths cannot change server policy authority" {
  with_receive_fixture(f => {
    let original = receive_policy_text(f.server)
    let target = unchecked_receive_commit(
      f.client,
      [
        (
          "receive-policies.json", b"{\"required\":[],\"client_result\":\"Pass\"}",
        ),
        ("config.env", b"MOONVCS_API_KEY=harmless-policy-disable"),
      ],
      [f.base],
      "disable policy",
    )
    guard expect_failure(() => {
        receive_candidate(
          f.server,
          prepare_receive_request(
            f.client,
            "refs/heads/main",
            Some(f.base),
            target,
          ),
        )
      })
      is VcsError::ReceiveRejected(_) else {
      fail("client disabled server policy")
    }
    let forbidden = unchecked_receive_commit(
      f.client,
      [(".moonvcs/receive-policies.json", b"{\"required\":[]}")],
      [f.base],
      "metadata injection",
    )
    guard expect_failure(() => {
        receive_candidate(
          f.server,
          prepare_receive_request(
            f.client,
            "refs/heads/main",
            Some(f.base),
            forbidden,
          ),
        )
      })
      is VcsError::ReceiveInvalid(_) else {
      fail("repository metadata path accepted")
    }
    let bad_ref : ReceiveRequest = {
      ref_name: "refs/heads/../../receive-policies.json",
      expected_old: None,
      target,
      objects: [],
    }
    guard expect_failure(() => receive_candidate(f.server, bad_ref))
      is VcsError::ReceiveInvalid(_) else {
      fail("Ref traversal accepted")
    }
    assert_eq(receive_policy_text(f.server), original)
    assert_eq(f.server.head(), Some(f.base))
  })
}

///|
async test "missing empty and mismatched server required policy configuration fails closed" {
  with_receive_fixture(f => {
    let request = receive_child_request(f, b"APP_MODE=safe", "config failures")
    let path = f.server.root + "/.moonvcs/receive-policies.json"
    let original = receive_policy_text(f.server)
    @fs.remove(path)
    guard expect_failure(() => receive_candidate(f.server, request))
      is VcsError::ReceivePolicyError(_) else {
      fail("missing server policy accepted")
    }
    let empty = integration_context()
    empty.required.clear()
    guard expect_failure(() => {
        install_receive_policy(f.server, @json.to_json(empty).stringify())
      })
      is VcsError::ReceivePolicyError(_) else {
      fail("empty server policy accepted")
    }
    install_receive_policy(f.server, original)
    let context = integration_context()
    let pin = context.required[0]
    context.required[0] = { ..pin, module_digest: "sha256:" + "0".repeat(64), }
    install_receive_policy(f.server, @json.to_json(context).stringify())
    guard expect_failure(() => receive_candidate(f.server, request))
      is VcsError::ReceivePolicyError(_) else {
      fail("digest mismatch accepted")
    }
    assert_eq(f.server.head(), Some(f.base))
    assert_false(f.server.store.has(request.target))
  })
}

///|
async test "real on-receive traps epoch timeouts and memory failures fail closed and clean quarantine" {
  with_receive_fixture(f => {
    let project = integration_project_root()
    let component = project +
      "/target/components/adversarial-fixture.component.wasm"
    for
      mode in ["fixture:trap", "fixture:infinite-loop", "fixture:memory-growth"] {
      let context = integration_context()
      context.required[0] = {
        name: "adversarial-fixture",
        version: "0.1.0",
        component,
        module_digest: "sha256:" +
        object_id_for_bytes(@fs.read_file(component).binary()).hex,
        manifest: project + "/plugins/adversarial-fixture/plugin.toml",
        granted_capabilities: ["commit_metadata.read", "diagnostic.emit"],
      }
      let context : PolicyContext = {
        ..context,
        limits: {
          ..context.limits,
          fuel: 2000000000,
          timeout_ms: if mode == "fixture:infinite-loop" {
            10
          } else {
            1000
          },
          max_memory_bytes: 4194304,
        },
      }
      install_receive_policy(f.server, @json.to_json(context).stringify())
      let target = unchecked_receive_commit(
        f.client,
        [("file.txt", b"safe")],
        [],
        mode,
      )
      let request = prepare_receive_request(
        f.client,
        "refs/heads/fixture",
        None,
        target,
      )
      guard expect_failure(() => receive_candidate(f.server, request))
        is VcsError::ReceivePolicyError(_) else {
        fail("required guest failure accepted")
      }
      assert_eq(f.server.read_ref("refs/heads/fixture"), None)
      assert_eq(f.server.head(), Some(f.base))
      assert_false(f.server.store.has(target))
      assert_receive_quarantine_empty(f.server)
    }
  })
}

///|
async test "two concurrent receives using the same old Ref cannot silently overwrite" {
  with_receive_fixture(f => {
    let a = receive_child_request(f, b"APP_MODE=client-a", "client a")
    let b = receive_child_request(f, b"APP_MODE=client-b", "client b")
    @async.with_task_group() <| group => {
      let mut finished = false
      let observer = group.spawn(() => {
        while !finished {
          let head = f.server.head()
          assert_true(
            head == Some(f.base) ||
            head == Some(a.target) ||
            head == Some(b.target),
          )
          @async.sleep(1)
        }
      })
      let first = group.spawn(() => {
        try receive_candidate(f.server, a) catch {
          VcsError::RefConflict(_) => false
          error => raise error
        } noraise {
          _ => true
        }
      })
      let second = group.spawn(() => {
        try receive_candidate(f.server, b) catch {
          VcsError::RefConflict(_) => false
          error => raise error
        } noraise {
          _ => true
        }
      })
      let a_won = first.wait()
      let b_won = second.wait()
      finished = true
      observer.wait()
      assert_not_eq(a_won, b_won)
      let winner = if a_won { a.target } else { b.target }
      let loser = if a_won { b.target } else { a.target }
      assert_eq(f.server.head(), Some(winner))
      assert_true(f.server.store.has(winner))
      assert_false(f.server.store.has(loser))
      assert_receive_quarantine_empty(f.server)
    }
  })
}

///|
async fn blocking_receive_policy(f : ReceiveFixture) -> (String, String) {
  let entered = f.root + "/host-entered"
  let release = f.root + "/host-release"
  let wrapper = f.root + "/gated-real-host"
  let context = integration_context()
  let script = "#!/bin/sh\n: > \"" +
    entered +
    "\"\nwhile [ ! -f \"" +
    release +
    "\" ]; do /bin/sleep 0.01; done\nexec \"" +
    context.host +
    "\" \"$@\"\n"
  @fs.write_file(wrapper, script, create_mode=CreateNew, permission=0o700)
  install_receive_policy(
    f.server,
    @json.to_json({ ..context, host: wrapper, }).stringify(),
  )
  (entered, release)
}

///|
async fn wait_receive_host(entered : String) -> Unit {
  @async.with_timeout(5000, () => {
    while !@fs.exists(entered) {
      @async.sleep(5)
    }
  })
}

///|
async test "quarantine stays unpublished during validation and concurrent server policy changes require retry" {
  with_receive_fixture(f => {
    let request = receive_child_request(f, b"APP_MODE=waiting", "policy race")
    let before = storage_inventory(f.server.root)
    let (entered, release) = blocking_receive_policy(f)
    @async.with_task_group() <| group => {
      let receiving = group.spawn(() => {
        try receive_candidate(f.server, request) catch {
          VcsError::ReceivePolicyError(reason) => reason
          error => raise error
        } noraise {
          _ => fail("changed policy was accepted")
        }
      })
      wait_receive_host(entered)
      assert_eq(f.server.head(), Some(f.base))
      assert_false(f.server.store.has(request.target))
      assert_eq(storage_inventory(f.server.root), before)
      let quarantines = @fs.readdir(f.server.root + "/.moonvcs/quarantine")
      assert_eq(quarantines.length(), 1)
      let staged = LocalObjectStore::new(
        f.server.root + "/.moonvcs/quarantine/" + quarantines[0],
      )
      assert_true(staged.has(request.target))
      install_receive_policy(
        f.server,
        @json.to_json(integration_context()).stringify(),
      )
      @fs.write_file(release, "release", create_mode=CreateNew)
      assert_true(receiving.wait().contains("changed during validation"))
    }
    assert_eq(f.server.head(), Some(f.base))
    assert_eq(storage_inventory(f.server.root), before)
    assert_receive_quarantine_empty(f.server)
    receive_candidate(f.server, request) |> ignore
    assert_eq(f.server.head(), Some(request.target))
  })
}

///|
async test "cancelling receive while the real Host is gated cleans quarantine without publishing" {
  with_receive_fixture(f => {
    let request = receive_child_request(f, b"APP_MODE=cancelled", "cancel")
    let before = storage_inventory(f.server.root)
    let (entered, _) = blocking_receive_policy(f)
    @async.with_task_group() <| group => {
      let receiving = group.spawn(
        () => receive_candidate(f.server, request),
        allow_failure=true,
      )
      wait_receive_host(entered)
      receiving.cancel()
      try receiving.wait() |> ignore catch {
        _ => ()
      }
    }
    assert_eq(f.server.head(), Some(f.base))
    assert_eq(storage_inventory(f.server.root), before)
    assert_false(f.server.store.has(request.target))
    assert_receive_quarantine_empty(f.server)
  })
}

///|
async test "current server policy rescans old published history and objects reused on a new branch" {
  with_receive_fixture(f => {
    let context = integration_context()
    context.custom_rules.push({ id: "old-base", literal: "APP_MODE=base", })
    install_receive_policy(f.server, @json.to_json(context).stringify())
    let request = receive_child_request(f, b"APP_MODE=new", "clean tip")
    guard expect_failure(() => receive_candidate(f.server, request))
      is VcsError::ReceiveRejected(reason) else {
      fail("old policy result was trusted")
    }
    assert_true(reason.contains("custom.old-base"))
    let existing : ReceiveRequest = {
      ref_name: "refs/heads/reused",
      expected_old: None,
      target: f.base,
      objects: [],
    }
    guard expect_failure(() => receive_candidate(f.server, existing))
      is VcsError::ReceiveRejected(_) else {
      fail("new branch laundered old object approval")
    }
    assert_eq(f.server.read_ref("refs/heads/reused"), None)
    assert_eq(f.server.head(), Some(f.base))
  })
}

///|
async test "receive dispatches the existing on-receive hook rather than reusing on-commit permission" {
  with_receive_fixture(f => {
    let project = integration_project_root()
    let component = project + "/target/components/hello-policy.component.wasm"
    let context = integration_context()
    context.required[0] = {
      name: "hello-policy",
      version: "0.1.0",
      component,
      manifest: project + "/plugins/hello-policy/plugin.toml",
      module_digest: "sha256:" +
      object_id_for_bytes(@fs.read_file(component).binary()).hex,
      granted_capabilities: ["commit_metadata.read", "diagnostic.emit"],
    }
    install_receive_policy(f.server, @json.to_json(context).stringify())
    let request = receive_child_request(f, b"APP_MODE=clean", "safe")
    guard expect_failure(() => receive_candidate(f.server, request))
      is VcsError::ReceivePolicyError(_) else {
      fail("on-commit-only manifest ran on receive")
    }
    assert_eq(f.server.head(), Some(f.base))
  })
}

///|
async test "non-fast-forward and merge histories are explicitly rejected" {
  with_receive_fixture(f => {
    let unrelated = unchecked_receive_commit(
      f.client,
      [("file", b"unrelated")],
      [],
      "unrelated root",
    )
    let request = prepare_receive_request(
      f.client,
      "refs/heads/main",
      Some(f.base),
      unrelated,
    )
    guard expect_failure(() => receive_candidate(f.server, request))
      is VcsError::ReceiveRejected(_) else {
      fail("force push was accepted")
    }
    let tree = f.client.store.put(TreeObject(Tree::new([])))
    let merge = f.client.store.put(
      CommitObject({
        tree_id: tree,
        parents: [f.base, unrelated],
        author: "Client",
        timestamp: 125UL,
        message: "merge",
      }),
    )
    let request : ReceiveRequest = {
      ref_name: "refs/heads/main",
      expected_old: Some(f.base),
      target: merge,
      objects: [
        { id: merge, encoded: encode_object(f.client.store.get(merge)), },
      ],
    }
    guard expect_failure(() => receive_candidate(f.server, request))
      is VcsError::ReceiveInvalid(_) else {
      fail("unsupported merge history was accepted")
    }
    assert_eq(f.server.head(), Some(f.base))
  })
}

///|
async test "a valid quarantined duplicate cannot hide corruption in the published graph" {
  with_receive_fixture(f => {
    let request = receive_child_request(f, b"APP_MODE=new", "duplicate base")
    let path = f.server.store.object_path(f.base)
    @fs.chmod(path, 0o600)
    @fs.write_file(path, b"corrupt published commit")
    guard expect_failure(() => receive_candidate(f.server, request))
      is VcsError::ReceiveInvalid(_) else {
      fail("published corruption hidden by quarantine")
    }
    assert_eq(f.server.head(), Some(f.base))
    assert_false(f.server.store.has(request.target))
  })
}

///|
async test "server can require both real MoonBit policies on receive and accepts Warning only" {
  with_receive_fixture(f => {
    let context = multi_policy_context()
    let pin = context.required[1]
    context.required[1] = {
      ..pin,
      manifest: integration_project_root() +
      "/plugins/license-check/plugin.toml",
    }
    install_receive_policy(f.server, @json.to_json(context).stringify())
    let target = unchecked_receive_commit(
      f.client,
      [
        ("LICENSE", b"demo license"),
        ("main.mbt", b"// SPDX-License-Identifier: Apache-2.0\n"),
      ],
      [],
      "two server policies",
    )
    let report = receive_candidate(
      f.server,
      prepare_receive_request(f.client, "refs/heads/licensed", None, target),
    )
    assert_eq(report.checked_commits, 1)
    assert_eq(f.server.read_ref("refs/heads/licensed"), Some(target))
    let missing = unchecked_receive_commit(
      f.client,
      [("main.mbt", b"no header")],
      [],
      "missing license",
    )
    guard expect_failure(() => {
        receive_candidate(
          f.server,
          prepare_receive_request(
            f.client,
            "refs/heads/unlicensed",
            None,
            missing,
          ),
        )
      })
      is VcsError::ReceiveRejected(reason) else {
      fail("second server policy was skipped")
    }
    assert_true(reason.contains("license-check"))
    assert_eq(f.server.read_ref("refs/heads/unlicensed"), None)
  })
}
