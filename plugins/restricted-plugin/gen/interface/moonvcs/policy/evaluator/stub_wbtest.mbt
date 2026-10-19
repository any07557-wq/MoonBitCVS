///|
fn restricted_request() -> PolicyRequest {
  {
    hook: ON_COMMIT,
    policy_version: "1",
    commit_message: "",
    parent_id: None,
    tree_id: None,
    files: [
      {
        path: "allowed.txt",
        content: b"harmless-allowed-content".to_fixedarray(),
      },
    ],
    granted_capabilities: ["staged_content.read"],
  }
}

///|
test "only the exact authorized data passes" {
  let result = evaluate(restricted_request())
  assert_eq(result.decision, Pass)
  assert_true(result.diagnostics.is_empty())
}

///|
test "extra unauthorized capability is not silently accepted" {
  let request = restricted_request()
  request.granted_capabilities.push("repository.secrets.read")
  guard evaluate(request).decision is Error(_) else {
    fail("unexpected grant accepted")
  }
}
