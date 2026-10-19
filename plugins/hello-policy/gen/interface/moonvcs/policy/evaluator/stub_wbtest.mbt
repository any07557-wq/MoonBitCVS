///|
fn request_with(message : String) -> PolicyRequest {
  {
    hook: ON_COMMIT,
    policy_version: "1",
    commit_message: message,
    parent_id: None,
    tree_id: None,
    files: [{ path: "README.md", content: b"hello".to_fixedarray(), }],
    granted_capabilities: ["diagnostic.emit"],
  }
}

///|
test "safe commit message passes" {
  let result = evaluate(request_with("add safe configuration"))
  assert_eq(result.decision, Pass)
  assert_eq(result.diagnostics.length(), 0)
}

///|
test "forbidden marker is rejected with a structured reason" {
  let result = evaluate(request_with("commit forbidden-demo"))
  assert_eq(result.decision, Reject)
  assert_eq(result.diagnostics.length(), 1)
  assert_eq(result.diagnostics[0].code, "message.forbidden-demo")
  assert_eq(result.diagnostics[0].message, "forbidden-demo detected")
}

///|
test "empty commit message is invalid input" {
  let result = evaluate(request_with(""))
  match result.decision {
    Error(reason) => assert_eq(reason, "commit message must not be empty")
    _ => fail("expected policy error")
  }
}
