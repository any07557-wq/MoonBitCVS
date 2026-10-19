///|
fn request_with(path : String, content : BytesView) -> PolicyRequest {
  {
    hook: ON_COMMIT,
    policy_version: "1",
    commit_message: "test commit",
    parent_id: None,
    tree_id: None,
    files: [{ path, content: content.to_fixedarray(), }],
    granted_capabilities: ["staged_content.read", "diagnostic.emit"],
  }
}

///|
test "clean staged content passes" {
  let result = evaluate(request_with("README.md", b"hello MoonVCS"))
  assert_eq(result.decision, Pass)
  assert_eq(result.diagnostics.length(), 0)
}

///|
test "simulated token is rejected without exposing its value" {
  let result = evaluate(
    request_with("config.env", b"MOONVCS_TEST_TOKEN=do-not-log-this-value"),
  )
  assert_eq(result.decision, Reject)
  assert_eq(result.diagnostics.length(), 1)
  assert_eq(result.diagnostics[0].code, "secret.test-token")
  assert_false(result.diagnostics[0].message.contains("do-not-log-this-value"))
}

///|
test "missing content capability fails closed" {
  let request : PolicyRequest = {
    hook: ON_COMMIT,
    policy_version: "1",
    commit_message: "test commit",
    parent_id: None,
    tree_id: None,
    files: [],
    granted_capabilities: [],
  }
  let result = evaluate(request)
  match result.decision {
    Error(reason) =>
      assert_eq(
        reason, "required capability staged_content.read was not granted",
      )
    _ => fail("expected policy error")
  }
}

///|
test "all credential families are rejected with redacted diagnostics" {
  for
    (content, rule) in [
      (b"MOONVCS_API_KEY=harmless-only", "secret.api-key"),
      (b"MOONVCS_ACCESS_TOKEN=harmless-only", "secret.access-token"),
      (b"-----BEGIN PRIVATE KEY-----", "secret.private-key"),
      (b"-----BEGIN OPENSSH PRIVATE KEY-----", "secret.private-key-openssh"),
      (b"Password = harmless-only", "secret.password"),
      (b"password: harmless-only", "secret.password"),
      (b"{\"database\":{\"password\":\"harmless-only\"}}", "secret.password"),
    ] {
    let result = evaluate(request_with("config.env", content))
    assert_eq(result.decision, Reject)
    assert_eq(result.diagnostics[0].code, rule)
    assert_eq(result.diagnostics[0].path, Some("config.env"))
    assert_eq(result.diagnostics[0].message, "suspicious credential")
  }
}

///|
test "empty and commented password fields are not credentials" {
  for
    content in [
      b"password=", b"password=\"\"", b"# password=comment", b"{\"password\":null}",
    ] {
    assert_eq(evaluate(request_with("config.env", content)).decision, Pass)
  }
}

///|
test "custom literal rules are interpreted inside the MoonBit component" {
  let request = request_with("config.env", b"COMPANY_DEMO=harmless-only")
  request.files.push({
    path: plugin_config_path,
    content: b"{\"custom_rules\":[{\"id\":\"company\",\"literal\":\"COMPANY_DEMO=\"}]}".to_fixedarray(),
  })
  let result = evaluate(request)
  assert_eq(result.decision, Reject)
  assert_eq(result.diagnostics[0].code, "custom.company")
  assert_eq(result.diagnostics[0].path, Some("config.env"))
  assert_eq(result.diagnostics[0].message, "suspicious credential")
}

///|
test "malformed custom configuration fails closed without echoing input" {
  let request = request_with("config.env", b"clean")
  request.files.push({
    path: plugin_config_path,
    content: b"{\"custom_rules\":[{\"id\":\"bad\",\"literal\":\"\"}]}".to_fixedarray(),
  })
  match evaluate(request).decision {
    Error(reason) => assert_eq(reason, "invalid custom scanner rule")
    _ => fail("expected configuration error")
  }
}

///|
test "multiple files and multiple rules retain their paths" {
  let request = request_with(
    "a.env", b"MOONVCS_API_KEY=harmless-a\npassword=harmless-p",
  )
  request.files.push({
    path: "nested/b.env",
    content: b"MOONVCS_ACCESS_TOKEN=harmless-b".to_fixedarray(),
  })
  let result = evaluate(request)
  assert_eq(result.diagnostics.length(), 3)
  assert_eq(result.diagnostics[2].path, Some("nested/b.env"))
}
