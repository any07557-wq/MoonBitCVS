///|
fn request(files : Array[StagedFile]) -> PolicyRequest {
  {
    hook: ON_COMMIT,
    policy_version: "1",
    commit_message: "",
    parent_id: None,
    tree_id: None,
    files,
    granted_capabilities: [
      "staged_content.list", "staged_content.read", "diagnostic.emit",
    ],
  }
}

///|
test "valid license header and NOTICE pass" {
  let result = evaluate(
    request([
      { path: "LICENSE", content: b"demo license".to_fixedarray(), },
      { path: "NOTICE", content: b"demo notice".to_fixedarray(), },
      {
        path: "main.mbt",
        content: b"// SPDX-License-Identifier: Apache-2.0\n".to_fixedarray(),
      },
    ]),
  )
  assert_eq(result.decision, Pass)
  assert_eq(result.diagnostics.length(), 0)
}

///|
test "missing license rejects" {
  let result = evaluate(request([]))
  assert_eq(result.decision, Reject)
  assert_eq(result.diagnostics[0].code, "license.missing")
}

///|
test "missing source header rejects without echoing contents" {
  let result = evaluate(
    request([
      { path: "LICENSE", content: b"demo".to_fixedarray(), },
      {
        path: "main.rs",
        content: b"harmless-private-test-value".to_fixedarray(),
      },
    ]),
  )
  assert_eq(result.decision, Reject)
  assert_eq(result.diagnostics[0].path, Some("main.rs"))
  assert_eq(result.diagnostics[0].message, "required SPDX header is absent")
}

///|
test "Pass can carry a warning without changing WIT" {
  let result = evaluate(
    request([{ path: "LICENSE", content: b"demo".to_fixedarray(), }]),
  )
  assert_eq(result.decision, Pass)
  assert_eq(result.diagnostics[0].severity, WARNING)
}
