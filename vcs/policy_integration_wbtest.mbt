///|
async fn integration_project_root() -> String {
  let mut directory = current_directory()
  while !@fs.exists(directory + "/wit/policy.wit") {
    let parent = parent_directory(directory)
    if parent == directory {
      fail("cannot find policy runtime test assets")
    }
    directory = parent
  }
  directory
}

///|
async fn integration_context() -> PolicyContext {
  let root = integration_project_root()
  parse_policy_context(
    @fs.read_file(root + "/target/bin/moonvcs-default-policy.json").text(),
  )
}

///|
async fn configure_policies(
  repository : Repository,
  context : PolicyContext,
) -> Unit {
  write_atomic(
    repository.root + "/.moonvcs/policies.json",
    @utf8.encode(@json.to_json(context).stringify()),
  )
}

///|
async fn integration_repository(root : String) -> Repository {
  init_repository(
    root,
    policy_config=@json.to_json(integration_context()).stringify(),
  )
}

///|
async fn expected_commit_id(
  repository : Repository,
  timestamp : UInt64,
  message : String,
) -> ObjectId {
  let candidate = repository.make_candidate("Policy Test", timestamp, message)
  object_id_for(
    CommitObject({
      tree_id: candidate.tree_id,
      parents: candidate.parents,
      author: candidate.author,
      timestamp: candidate.timestamp,
      message: candidate.message,
    }),
  )
}

///|
async test "real Wasm scanner accepts clean commits rejects secrets and accepts repaired stage" {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="moonvcs-real-policy")
    group.add_defer(() => {
      @async.protect_from_cancel(() => @fs.rmdir(root, recursive=true))
    })
    let repository = integration_repository(root)
    @fs.write_file(
      root + "/config.env",
      "APP_MODE=demo\n",
      create_mode=CreateNew,
    )
    repository.add(["config.env"]) |> ignore
    let first = repository.commit("Policy Test", 1UL, "clean")
    @fs.write_file(
      root + "/config.env",
      "MOONVCS_API_KEY=harmless-do-not-log\n",
      create_mode=TruncateExisting,
    )
    repository.add(["config.env"]) |> ignore
    let index = repository.load_index()
    let rejected_id = expected_commit_id(repository, 2UL, "secret")
    let error = expect_failure(() => {
      repository.commit("Policy Test", 2UL, "secret")
    })
    guard error is VcsError::PolicyRejected(reason) else {
      fail("real scanner did not reject")
    }
    assert_true(reason.contains("Policy: secret-scanner"))
    assert_true(reason.contains("secret.api-key"))
    assert_false(reason.contains("harmless-do-not-log"))
    assert_eq(repository.head(), Some(first))
    assert_false(repository.store.has(rejected_id))
    assert_eq(repository.load_index(), index)
    assert_eq(
      @fs.read_file(root + "/config.env").text(),
      "MOONVCS_API_KEY=harmless-do-not-log\n",
    )
    // A repair in the working tree cannot disguise the secret still in Stage.
    @fs.write_file(
      root + "/config.env",
      "APP_MODE=repaired\n",
      create_mode=TruncateExisting,
    )
    guard expect_failure(() => repository.commit("Policy Test", 2UL, "secret"))
      is VcsError::PolicyRejected(_) else {
      fail("scanner read working bytes instead of Stage")
    }
    repository.add(["config.env"]) |> ignore
    let second = repository.commit("Policy Test", 3UL, "repaired")
    assert_eq(repository.head(), Some(second))
    assert_eq(repository.log().length(), 2)
  }
}

///|
async test "required policies cannot be bypassed with Mock Pass or an internal normal commit" {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="moonvcs-no-bypass")
    group.add_defer(() => {
      @async.protect_from_cancel(() => @fs.rmdir(root, recursive=true))
    })
    let repository = integration_repository(root)
    @fs.write_file(
      root + "/config.env",
      "MOONVCS_ACCESS_TOKEN=harmless-only",
      create_mode=CreateNew,
    )
    repository.add(["config.env"]) |> ignore
    let id = expected_commit_id(repository, 1UL, "blocked")
    guard expect_failure(() => {
        repository.commit_with_validator(
          "Policy Test",
          1UL,
          "blocked",
          MockPolicyValidator::pass(),
        )
      })
      is VcsError::PolicyRejected(_) else {
      fail("Mock Pass bypassed a required Wasm policy")
    }
    guard expect_failure(() => repository.commit("Policy Test", 1UL, "blocked"))
      is VcsError::PolicyRejected(_) else {
      fail("normal commit bypassed a required Wasm policy")
    }
    assert_eq(repository.head(), None)
    assert_false(repository.store.has(id))
  }
}

///|
async test "real Wasm diagnostics locate multiple files and custom rules" {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="moonvcs-diagnostics")
    group.add_defer(() => {
      @async.protect_from_cancel(() => @fs.rmdir(root, recursive=true))
    })
    let repository = integration_repository(root)
    let context = integration_context()
    context.custom_rules.push({ id: "company", literal: "COMPANY_DEMO=", })
    configure_policies(repository, context)
    @fs.mkdir(root + "/nested", permission=0o700)
    @fs.write_file(
      root + "/a.env",
      "password=harmless-only",
      create_mode=CreateNew,
    )
    @fs.write_file(
      root + "/nested/b.env",
      "COMPANY_DEMO=harmless-custom",
      create_mode=CreateNew,
    )
    repository.add(["."]) |> ignore
    match
      validate_policies(
        repository.make_candidate("Policy Test", 1UL, "multiple"),
        context,
      ) {
      Reject(diagnostics) => {
        assert_eq(diagnostics.length(), 2)
        assert_eq(diagnostics[0].plugin, "secret-scanner")
        assert_eq(diagnostics[0].file, Some("a.env"))
        assert_eq(diagnostics[0].rule, "secret.password")
        assert_eq(diagnostics[1].file, Some("nested/b.env"))
        assert_eq(diagnostics[1].rule, "custom.company")
        assert_eq(diagnostics[1].message, "suspicious credential")
      }
      _ => fail("expected structured diagnostics from the real plugin")
    }
    assert_eq(repository.head(), None)
  }
}

///|
async test "missing plugin missing host and mismatched pins all fail closed" {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="moonvcs-policy-missing")
    group.add_defer(() => {
      @async.protect_from_cancel(() => @fs.rmdir(root, recursive=true))
    })
    let repository = integration_repository(root)
    @fs.write_file(root + "/file", "clean", create_mode=CreateNew)
    repository.add(["file"]) |> ignore
    let id = expected_commit_id(repository, 1UL, "blocked")
    for mode in ["component", "version", "digest", "name", "host"] {
      let context = integration_context()
      let pin = context.required[0]
      context.required[0] = {
        name: if mode == "name" {
          "different-plugin"
        } else {
          pin.name
        },
        version: if mode == "version" {
          "99.0.0"
        } else {
          pin.version
        },
        module_digest: if mode == "digest" {
          "sha256:" + "0".repeat(64)
        } else {
          pin.module_digest
        },
        component: if mode == "component" {
          root + "/missing.wasm"
        } else {
          pin.component
        },
        manifest: pin.manifest,
        granted_capabilities: pin.granted_capabilities,
      }
      let mut text = @json.to_json(context).stringify()
      if mode == "host" {
        text = text.replace_all(old=context.host, new=root + "/missing-host")
      }
      write_atomic(root + "/.moonvcs/policies.json", @utf8.encode(text))
      guard expect_failure(() => {
          repository.commit("Policy Test", 1UL, "blocked")
        })
        is VcsError::PolicyExecutionFailed(_) else {
        fail("missing or substituted required policy did not fail")
      }
      assert_eq(repository.head(), None)
      assert_false(repository.store.has(id))
    }
    @fs.remove(root + "/.moonvcs/policies.json")
    guard expect_failure(() => repository.commit("Policy Test", 1UL, "blocked"))
      is VcsError::PolicyExecutionFailed(_) else {
      fail("missing policy configuration silently disabled validation")
    }
  }
}

///|
async test "real Wasm Trap and resource failures leave existing HEAD and index untouched" {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="moonvcs-policy-trap")
    group.add_defer(() => {
      @async.protect_from_cancel(() => @fs.rmdir(root, recursive=true))
    })
    let repository = integration_repository(root)
    @fs.write_file(root + "/file", "clean", create_mode=CreateNew)
    repository.add(["file"]) |> ignore
    let first = repository.commit("Policy Test", 1UL, "initial")
    @fs.write_file(root + "/file", "updated", create_mode=TruncateExisting)
    repository.add(["file"]) |> ignore
    let index = repository.load_index()
    let project = integration_project_root()
    let component = project +
      "/target/components/adversarial-fixture.component.wasm"
    let context = integration_context()
    context.required[0] = {
      name: "adversarial-fixture",
      granted_capabilities: ["commit_metadata.read", "diagnostic.emit"],
      version: "0.1.0",
      module_digest: "sha256:" +
      object_id_for_bytes(@fs.read_file(component).binary()).hex,
      component,
      manifest: project + "/plugins/adversarial-fixture/plugin.toml",
    }
    configure_policies(repository, context)
    for
      message in [
        "fixture:trap", "fixture:infinite-loop", "fixture:memory-growth",
      ] {
      let id = expected_commit_id(repository, 2UL, message)
      guard expect_failure(() => repository.commit("Policy Test", 2UL, message))
        is VcsError::PolicyExecutionFailed(_) else {
        fail("required plugin failure did not stop commit")
      }
      assert_eq(repository.head(), Some(first))
      assert_eq(repository.load_index(), index)
      assert_false(repository.store.has(id))
    }
  }
}

///|
async test "all required policies must pass before a commit is written" {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="moonvcs-required-all")
    group.add_defer(() => {
      @async.protect_from_cancel(() => @fs.rmdir(root, recursive=true))
    })
    let repository = integration_repository(root)
    let project = integration_project_root()
    let component = project + "/target/components/hello-policy.component.wasm"
    let context = integration_context()
    context.required.push({
      name: "hello-policy",
      granted_capabilities: ["commit_metadata.read", "diagnostic.emit"],
      version: "0.1.0",
      component,
      manifest: project + "/plugins/hello-policy/plugin.toml",
      module_digest: "sha256:" +
      object_id_for_bytes(@fs.read_file(component).binary()).hex,
    })
    configure_policies(repository, context)
    @fs.write_file(root + "/file", "clean", create_mode=CreateNew)
    repository.add(["file"]) |> ignore
    guard expect_failure(() => {
        repository.commit("Policy Test", 1UL, "forbidden-demo")
      })
      is VcsError::PolicyRejected(reason) else {
      fail("second required policy was not enforced")
    }
    assert_true(reason.contains("hello-policy"))
    assert_eq(repository.head(), None)
    assert_false(
      repository.store.has(
        expected_commit_id(repository, 1UL, "forbidden-demo"),
      ),
    )
    repository.commit("Policy Test", 2UL, "safe") |> ignore
    assert_true(repository.head() is Some(_))
  }
}
