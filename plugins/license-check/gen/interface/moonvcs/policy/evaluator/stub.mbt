// Demonstration repository convention, not legal advice.

///|
pub fn evaluate(request : PolicyRequest) -> PolicyResult {
  if request.policy_version != "1" ||
    !request.granted_capabilities.contains("staged_content.list") ||
    !request.granted_capabilities.contains("staged_content.read") ||
    !request.granted_capabilities.contains("diagnostic.emit") {
    return {
      decision: Error("required license capabilities missing"),
      diagnostics: [],
    }
  }
  let diagnostics : Array[Diagnostic] = []
  let mut license_found = false
  let mut notice_found = false
  for file in request.files {
    if file.path == "LICENSE" && file.content.length() > 0 {
      license_found = true
    }
    if file.path == "NOTICE" {
      notice_found = true
    }
    if file.path.has_suffix(".mbt") ||
      file.path.has_suffix(".rs") ||
      file.path.has_suffix(".py") {
      // Header must occur within the first 512 bytes; never echo file content.
      let prefix = file.content[:if file.content.length() < 512 {
          file.content.length()
        } else {
          512
        }]
      let marker : Bytes = b"SPDX-License-Identifier: Apache-2.0"
      let mut found = false
      if prefix.length() >= marker.length() {
        for start = 0
            start <= prefix.length() - marker.length()
            start = start + 1 {
          let mut equal = true
          for i = 0; i < marker.length(); i = i + 1 {
            if prefix[start + i] != marker[i] {
              equal = false
              break
            }
          }
          if equal {
            found = true
            break
          }
        }
      }
      if !found {
        diagnostics.push({
          code: "license.header",
          severity: ERROR,
          message: "required SPDX header is absent",
          path: Some(file.path),
        })
      }
    }
  }
  if !license_found {
    diagnostics.push({
      code: "license.missing",
      severity: ERROR,
      message: "nonempty root LICENSE must be present in the candidate",
      path: None,
    })
  }
  if !diagnostics.is_empty() {
    return { decision: Reject, diagnostics, }
  }
  if !notice_found {
    diagnostics.push({
      code: "license.optional-notice",
      severity: WARNING,
      message: "optional NOTICE file is absent",
      path: None,
    })
  }
  { decision: Pass, diagnostics, }
}
