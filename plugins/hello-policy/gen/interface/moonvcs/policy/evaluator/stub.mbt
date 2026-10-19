// Minimal phase-1 policy implementation for the generated WIT bindings.

///|
pub fn evaluate(request : PolicyRequest) -> PolicyResult {
  if request.policy_version != "1" {
    return {
      decision: Error("unsupported policy version: \{request.policy_version}"),
      diagnostics: [],
    }
  }
  if request.commit_message.length() == 0 {
    return {
      decision: Error("commit message must not be empty"),
      diagnostics: [],
    }
  }
  if request.commit_message.contains("forbidden-demo") {
    if !request.granted_capabilities.contains("diagnostic.emit") {
      return {
        decision: Error("required capability diagnostic.emit was not granted"),
        diagnostics: [],
      }
    }
    return {
      decision: Reject,
      diagnostics: [
        {
          code: "message.forbidden-demo",
          severity: ERROR,
          message: "forbidden-demo detected",
          path: None,
        },
      ],
    }
  }
  { decision: Pass, diagnostics: [], }
}
