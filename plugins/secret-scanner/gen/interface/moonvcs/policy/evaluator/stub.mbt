// MoonBit policy implementation; WIT and generated ABI remain unchanged.

///|
priv struct CustomRule {
  id : String
  literal : String
} derive(@json.FromJson)

///|
priv struct ScannerConfig {
  custom_rules : Array[CustomRule]
} derive(@json.FromJson)

///|
let plugin_config_path = ".moonvcs/plugin-config/v1.json"

///|
fn password_assignment(content : Bytes) -> Bool {
  let text = @utf8.decode_lossy(content)
  let parsed = @json.parse(text) catch { _ => null }
  if json_password(parsed) {
    return true
  }
  for raw in text.split("\n") {
    let line = raw.trim()
    if line.has_prefix("#") || line.has_prefix(";") || line.has_prefix("//") {
      continue
    }
    let lower = line.to_lower()
    for separator in ["=", ":"] {
      if lower.find(separator) is Some(offset) {
        let key = lower[:offset].trim().trim(char_set="\"'")
        let value = line[offset + 1:].trim().trim(char_set="\"',; ")
        if (key == "password" || key == "passwd" || key == "db_password") &&
          !value.is_empty() {
          return true
        }
      }
    }
  }
  false
}

///|
fn json_password(value : Json) -> Bool {
  match value {
    Object(fields) =>
      for (name, child) in fields {
        let key = name.to_lower()
        if (key == "password" || key == "passwd" || key == "db_password") &&
          child != null &&
          child != Json::string("") {
          return true
        }
        if json_password(child) {
          return true
        }
      }
    Array(items) =>
      for item in items {
        if json_password(item) {
          return true
        }
      }
    _ => ()
  }
  false
}

///|
fn add_diagnostic(
  output : Array[Diagnostic],
  path : String,
  rule : String,
) -> Unit {
  output.push({
    code: rule,
    severity: ERROR,
    message: "suspicious credential",
    path: Some(path),
  })
}

///|
fn scan_file(
  file : StagedFile,
  rules : Array[CustomRule],
  output : Array[Diagnostic],
) -> Unit {
  let content = Bytes::from_array(file.content[:])
  for
    (marker, rule) in [
      (b"MOONVCS_TEST_TOKEN=", "secret.test-token"),
      (b"MOONVCS_ACCESS_TOKEN=", "secret.access-token"),
      (b"MOONVCS_API_KEY=", "secret.api-key"),
      (b"-----BEGIN PRIVATE KEY-----", "secret.private-key"),
      (b"-----BEGIN RSA PRIVATE KEY-----", "secret.private-key-rsa"),
      (b"-----BEGIN EC PRIVATE KEY-----", "secret.private-key-ec"),
      (b"-----BEGIN OPENSSH PRIVATE KEY-----", "secret.private-key-openssh"),
    ] {
    if content.find(marker) is Some(_) {
      add_diagnostic(output, file.path, rule)
    }
  }
  if password_assignment(content) {
    add_diagnostic(output, file.path, "secret.password")
  }
  for rule in rules {
    if content.find(@utf8.encode(rule.literal)) is Some(_) {
      add_diagnostic(output, file.path, "custom." + rule.id)
    }
  }
}

///|
pub fn evaluate(request : PolicyRequest) -> PolicyResult {
  if !request.granted_capabilities.contains("staged_content.read") {
    return {
      decision: Error("required capability staged_content.read was not granted"),
      diagnostics: [],
    }
  }
  if !request.granted_capabilities.contains("diagnostic.emit") {
    return {
      decision: Error("required capability diagnostic.emit was not granted"),
      diagnostics: [],
    }
  }
  let rules : Array[CustomRule] = []
  let mut config_seen = false
  for file in request.files {
    if file.path == plugin_config_path {
      if config_seen {
        return {
          decision: Error("duplicate scanner configuration"),
          diagnostics: [],
        }
      }
      config_seen = true
      let config : ScannerConfig = @json.from_json(
        @json.parse(@utf8.decode(Bytes::from_array(file.content[:]))),
      ) catch {
        _ =>
          return {
            decision: Error("invalid scanner configuration"),
            diagnostics: [],
          }
      }
      let ids : Map[String, Bool] = Map([])
      for rule in config.custom_rules {
        if rule.id.is_empty() ||
          rule.id.length() > 64 ||
          rule.literal.is_empty() ||
          @utf8.encode(rule.literal).length() > 256 ||
          ids.contains(rule.id) {
          return {
            decision: Error("invalid custom scanner rule"),
            diagnostics: [],
          }
        }
        for byte in @utf8.encode(rule.id) {
          let n = byte.to_int()
          if !((n >= 97 && n <= 122) ||
            (n >= 48 && n <= 57) ||
            n == 45 ||
            n == 46) {
            return {
              decision: Error("invalid custom scanner rule identifier"),
              diagnostics: [],
            }
          }
        }
        ids[rule.id] = true
        rules.push(rule)
      }
      if rules.length() > 64 {
        return {
          decision: Error("too many custom scanner rules"),
          diagnostics: [],
        }
      }
    }
  }
  let diagnostics : Array[Diagnostic] = []
  for file in request.files {
    if file.path != plugin_config_path {
      scan_file(file, rules, diagnostics)
    }
  }
  if diagnostics.is_empty() {
    { decision: Pass, diagnostics, }
  } else {
    { decision: Reject, diagnostics, }
  }
}
