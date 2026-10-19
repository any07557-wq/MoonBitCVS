///|
fn fixture_request(mode : String) -> PolicyRequest {
  {
    hook: ON_COMMIT,
    policy_version: "1",
    commit_message: mode,
    parent_id: None,
    tree_id: None,
    files: [],
    granted_capabilities: ["diagnostic.emit"],
  }
}

///|
test "oversized fixture constructs output larger than the host test limit" {
  let result = evaluate(fixture_request("fixture:oversized-output"))
  assert_eq(result.decision, Reject)
  assert_true(result.diagnostics[0].message.length() > 1024)
}

///|
test "unknown fixture mode fails closed" {
  let result = evaluate(fixture_request("fixture:unknown"))
  match result.decision {
    Error(reason) =>
      assert_true(reason.contains("unknown adversarial fixture mode"))
    _ => fail("expected policy error")
  }
}
