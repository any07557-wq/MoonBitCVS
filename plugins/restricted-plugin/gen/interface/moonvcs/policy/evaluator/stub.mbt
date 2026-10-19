// Executable observation of the actual request, not a fictional denied callback.

///|
pub fn evaluate(request : PolicyRequest) -> PolicyResult {
  if request.granted_capabilities != ["staged_content.read"] ||
    request.commit_message != "" ||
    request.parent_id != None ||
    request.tree_id != None ||
    request.files.length() != 1 ||
    request.files[0].path != "allowed.txt" ||
    Bytes::from_array(request.files[0].content[:]) !=
    b"harmless-allowed-content" {
    return {
      decision: Error("restricted request boundary violated"),
      diagnostics: [],
    }
  }
  { decision: Pass, diagnostics: [], }
}
