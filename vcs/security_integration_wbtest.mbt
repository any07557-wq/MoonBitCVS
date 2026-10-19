///|
async fn multi_policy_context() -> PolicyContext {
  parse_policy_context(
    @fs.read_file(
      integration_project_root() + "/target/bin/moonvcs-multi-policy.json",
    ).text(),
  )
}

///|
async test "two real plugins aggregate Reject and Warning in configured order" {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="moonvcs-multi-secure")
    group.add_defer(() => {
      @async.protect_from_cancel(() => @fs.rmdir(root, recursive=true))
    })
    let repository = integration_repository(root)
    let context = multi_policy_context()
    configure_policies(repository, context)
    @fs.write_file(
      root + "/main.mbt",
      "MOONVCS_API_KEY=harmless-multi-value",
      create_mode=CreateNew,
    )
    repository.add(["."]) |> ignore
    let candidate = repository.make_candidate("Security Test", 1UL, "blocked")
    guard validate_policies(candidate, context) is Reject(diagnostics) else {
      fail("both plugins must reject")
    }
    assert_eq(diagnostics.length(), 3)
    assert_eq(diagnostics[0].plugin, "secret-scanner")
    assert_eq(diagnostics[1].plugin, "license-check")
    assert_eq(diagnostics[2].rule, "license.missing")
    let first = context.required[0]
    context.required[0] = context.required[1]
    context.required[1] = first
    guard validate_policies(candidate, context) is Reject(reversed) else {
      fail("reversed policy order did not reject")
    }
    assert_eq(reversed[0].plugin, "license-check")
    assert_eq(reversed[2].plugin, "secret-scanner")
    let index = repository.load_index()
    guard expect_failure(() => {
        repository.commit("Security Test", 1UL, "blocked")
      })
      is VcsError::PolicyRejected(_) else {
      fail("required gate bypassed")
    }
    assert_eq(repository.head(), None)
    assert_eq(repository.load_index(), index)
    assert_false(
      repository.store.has(expected_commit_id(repository, 1UL, "blocked")),
    )
    @fs.write_file(
      root + "/main.mbt",
      "// SPDX-License-Identifier: Apache-2.0\n",
      create_mode=TruncateExisting,
    )
    @fs.write_file(
      root + "/LICENSE",
      "demonstration license",
      create_mode=CreateNew,
    )
    repository.add(["."]) |> ignore
    guard validate_policies(
        repository.make_candidate("Security Test", 2UL, "fixed"),
        context,
      )
      is Warning(warnings) else {
      fail("expected optional NOTICE warning")
    }
    assert_eq(warnings.length(), 1)
    assert_eq(warnings[0].plugin, "license-check")
    let committed = repository.commit("Security Test", 2UL, "fixed")
    assert_eq(repository.head(), Some(committed))
    @fs.write_file(
      root + "/NOTICE",
      "demonstration notice",
      create_mode=CreateNew,
    )
    repository.add(["."]) |> ignore
    guard validate_policies(
        repository.make_candidate("Security Test", 3UL, "notice"),
        context,
      )
      is Accept else {
      fail("expected both real plugins to Pass")
    }
  }
}

///|
async test "per-plugin grants do not inherit capabilities approved for other plugins" {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="moonvcs-per-plugin")
    group.add_defer(() => {
      @async.protect_from_cancel(() => @fs.rmdir(root, recursive=true))
    })
    let repository = integration_repository(root)
    let context = multi_policy_context()
    let pin = context.required[1]
    context.required[1] = {
      name: pin.name,
      version: pin.version,
      module_digest: pin.module_digest,
      component: pin.component,
      manifest: pin.manifest,
      granted_capabilities: ["staged_content.list", "diagnostic.emit"],
    }
    configure_policies(repository, context)
    @fs.write_file(root + "/LICENSE", "demo", create_mode=CreateNew)
    repository.add(["."]) |> ignore
    guard expect_failure(() => repository.commit("Security Test", 1UL, "denied"))
      is VcsError::PolicyExecutionFailed(_) else {
      fail("global grants bypassed per-plugin grants")
    }
    assert_eq(repository.head(), None)
    assert_false(
      repository.store.has(expected_commit_id(repository, 1UL, "denied")),
    )
  }
}

///|
async test "illegal canonical ABI output fails closed at the real commit boundary" {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="moonvcs-invalid-abi")
    group.add_defer(() => {
      @async.protect_from_cancel(() => @fs.rmdir(root, recursive=true))
    })
    let repository = integration_repository(root)
    @fs.write_file(root + "/file", "clean", create_mode=CreateNew)
    repository.add(["."]) |> ignore
    let first = repository.commit("Security Test", 1UL, "initial")
    @fs.write_file(root + "/file", "changed", create_mode=TruncateExisting)
    repository.add(["file"]) |> ignore
    let context = integration_context()
    let component = integration_project_root() +
      "/target/components/invalid-result.component.wasm"
    let digest = "sha256:" +
      object_id_for_bytes(@fs.read_file(component).binary()).hex
    let manifest = root + "/invalid-result.toml"
    @fs.write_file(
      manifest,
      "name = \"invalid-result\"\nversion = \"0.1.0\"\nabi_version = \"1\"\nhooks = [\"on-commit\"]\nrequested_capabilities = []\nmodule_digest = \"" +
      digest +
      "\"\n",
      create_mode=CreateNew,
    )
    context.required[0] = {
      name: "invalid-result",
      version: "0.1.0",
      module_digest: digest,
      component,
      manifest,
      granted_capabilities: [],
    }
    configure_policies(repository, context)
    let index = repository.load_index()
    guard expect_failure(() => {
        repository.commit("Security Test", 2UL, "malformed")
      })
      is VcsError::PolicyExecutionFailed(_) else {
      fail("invalid ABI was accepted")
    }
    assert_eq(repository.head(), Some(first))
    assert_eq(repository.load_index(), index)
    assert_false(
      repository.store.has(expected_commit_id(repository, 2UL, "malformed")),
    )
  }
}

///|
test "schema v1 grants migrate but v2 requires explicit per-plugin grants" {
  let old =
    #|{"schema":1,"host":"/test/host","required":[{"name":"test","version":"0.1.0",
    #|"module_digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000",
    #|"component":"/test/plugin.wasm","manifest":"/test/plugin.toml"}],
    #|"allowed_capabilities":["diagnostic.emit"],"custom_rules":[],
    #|"limits":{"fuel":100,"timeout_ms":1000,"max_memory_bytes":33554432,
    #|"max_input_bytes":1048576,"max_output_bytes":65536}}
  let migrated = parse_policy_context(old)
  assert_eq(migrated.required[0].granted_capabilities, ["diagnostic.emit"])
  assert_eq(migrated.limits.max_log_bytes, 65536)
  let mut rejected = false
  try
    parse_policy_context(
      old.replace_all(old="\"schema\":1", new="\"schema\":2"),
    )
    |> ignore
  catch {
    _ => rejected = true
  }
  assert_true(rejected)
}

///|
test "untrusted diagnostics cannot inject terminal controls or fake log lines" {
  let formatted = format_policy_diagnostics([
    {
      plugin: "test",
      rule: "test.rule",
      file: Some("a\nb"),
      line: None,
      severity: "warning",
      message: "one\ntwo\u001b[31m",
    },
  ])
  assert_true(formatted.contains("a\\nb"))
  assert_true(formatted.contains("one\\ntwo\\u001b[31m"))
  assert_false(formatted.contains("\u001b"))
}

///|
async test "streaming policy output limit is enforced before EOF" {
  let reader = @io.MemoryReader::MemoryReader(writer => {
    while true {
      writer.write("x".repeat(4096))
    }
  })
  defer reader.close()
  guard expect_failure(() => read_policy_pipe(reader, 64))
    is VcsError::PolicyExecutionFailed(reason) else {
    fail("streaming limit not enforced")
  }
  assert_true(reason.contains("output/log limit"))
}

///|
async test "oversized child stdout and stderr cause bounded reads and process cancellation" {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="moonvcs-host-pipe")
    group.add_defer(() => {
      @async.protect_from_cancel(() => @fs.rmdir(root, recursive=true))
    })
    let context = integration_context()
    let limits : PolicyLimits = {
      fuel: 100,
      timeout_ms: 1000,
      max_memory_bytes: 33554432,
      max_input_bytes: 1024,
      max_output_bytes: 64,
      max_log_bytes: 64,
    }
    for redirect in ["", " >&2"] {
      let host = root + "/mock-host"
      @fs.write_file(
        host,
        "#!/bin/sh\nwhile :; do printf '%s' 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'" +
        redirect +
        "; done\n",
        permission=0o700,
        create_mode=CreateOrTruncate,
      )
      let error = expect_failure(() => {
        @async.with_timeout(3000, () => {
          call_policy_host(host, context.required[0], "{}", limits)
        })
      })
      guard error is VcsError::PolicyExecutionFailed(reason) else {
        fail("child output limit did not fire before timeout")
      }
      assert_true(reason.contains("output/log limit"))
    }
  }
}
