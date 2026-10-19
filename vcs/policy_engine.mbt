///|
pub struct PolicyDiagnostic {
  plugin : String
  rule : String
  file : String?
  line : Int32?
  severity : String
  message : String
}

///|
pub impl @json.FromJson for PolicyDiagnostic with fn from_json(value, path) {
  guard value
    is Object(
      {
        "plugin": String(plugin),
        "rule": String(rule),
        "file": file,
        "line": line,
        "severity": String(severity),
        "message": String(message),
        ..
      }
    ) else {
    raise @json.JsonDecodeError::JsonDecodeError(
      (path, "invalid policy diagnostic"),
    )
  }
  let file = match file {
    Null => None
    String(value) => Some(value)
    _ =>
      raise @json.JsonDecodeError::JsonDecodeError(
        (path, "invalid diagnostic file"),
      )
  }
  let line = match line {
    Null => None
    Number(value, ..) if value >= 1.0 &&
      value <= 2147483647.0 &&
      value.to_int().to_double() == value => Some(value.to_int())
    _ =>
      raise @json.JsonDecodeError::JsonDecodeError(
        (path, "invalid diagnostic line"),
      )
  }
  { plugin, rule, file, line, severity, message, }
}

///|
pub impl @json.ToJson for PolicyDiagnostic with fn to_json(self) {
  let file : Json = match self.file {
    Some(value) => Json::string(value)
    None => null
  }
  let line : Json = match self.line {
    Some(value) => Json::number(value.to_double())
    None => null
  }
  {
    "plugin": self.plugin,
    "rule": self.rule,
    "file": file,
    "line": line,
    "severity": self.severity,
    "message": self.message,
  }
}

///|
pub(all) enum EngineDecision {
  Accept
  Warning(Array[PolicyDiagnostic])
  Reject(Array[PolicyDiagnostic])
  EngineError(String)
}

///|
pub struct RequiredPolicy {
  name : String
  version : String
  module_digest : String
  component : String
  manifest : String
  granted_capabilities : Array[String]
} derive(@json.FromJson, @json.ToJson)

///|
pub struct PolicyLimits {
  fuel : Int32
  timeout_ms : Int32
  max_memory_bytes : Int32
  max_input_bytes : Int32
  max_output_bytes : Int32
  max_log_bytes : Int32
} derive(@json.FromJson, @json.ToJson)

///|
pub struct ConfiguredRule {
  id : String
  literal : String
} derive(@json.FromJson, @json.ToJson)

///|
pub struct PolicyContext {
  schema : Int32
  host : String
  required : Array[RequiredPolicy]
  allowed_capabilities : Array[String]
  limits : PolicyLimits
  custom_rules : Array[ConfiguredRule]
} derive(@json.FromJson, @json.ToJson)

///|
pub extend PolicyContext with @json.FromJson::{from_json}

///|
pub extend PolicyContext with @json.ToJson::{to_json}

///|
pub extend PolicyDiagnostic with @json.FromJson::{from_json}

///|
pub extend PolicyDiagnostic with @json.ToJson::{to_json}

///|
pub extend RequiredPolicy with @json.FromJson::{from_json}

///|
pub extend RequiredPolicy with @json.ToJson::{to_json}

///|
pub extend PolicyLimits with @json.FromJson::{from_json}

///|
pub extend PolicyLimits with @json.ToJson::{to_json}

///|
pub extend ConfiguredRule with @json.FromJson::{from_json}

///|
pub extend ConfiguredRule with @json.ToJson::{to_json}

///|
pub fn parse_policy_context(text : String) -> PolicyContext raise {
  let context : PolicyContext = try {
    let value = @json.parse(text)
    // v1 used one repository-wide grant list. Upgrade only v1, never infer
    // v2 grants from an untrusted plugin manifest.
    if value is Object(fields) {
      if fields.get("schema") == Some(Json::number(1.0)) {
        if fields.get("required") is Some(Array(plugins)) {
          for plugin in plugins {
            if plugin is Object(pin) && !pin.contains("granted_capabilities") {
              pin["granted_capabilities"] = match
                fields.get("allowed_capabilities") {
                Some(grants) => grants
                None => Json::array([])
              }
            }
          }
        }
      }
      if fields.get("limits") is Some(Object(limits)) &&
        !limits.contains("max_log_bytes") {
        limits["max_log_bytes"] = Json::number(65536.0)
      }
    }
    @json.from_json(value)
  } catch {
    _ =>
      raise VcsError::PolicyExecutionFailed(
        "invalid required-policy configuration",
      )
  }
  if (context.schema != 1 && context.schema != 2) ||
    context.limits.fuel <= 0 ||
    context.limits.timeout_ms <= 0 ||
    context.limits.timeout_ms > 60000 ||
    context.limits.max_input_bytes <= 0 ||
    context.limits.max_input_bytes > 1048576 ||
    context.limits.max_output_bytes <= 0 ||
    context.limits.max_output_bytes > 1048576 ||
    context.limits.max_log_bytes <= 0 ||
    context.limits.max_log_bytes > 1048576 ||
    context.limits.max_memory_bytes < 65536 ||
    context.limits.max_memory_bytes > 268435456 {
    raise VcsError::PolicyExecutionFailed(
      "unsupported policy configuration or invalid budgets",
    )
  }
  let names : Map[String, Bool] = Map([])
  for plugin in context.required {
    if plugin.name.is_empty() ||
      plugin.version.is_empty() ||
      names.contains(plugin.name) ||
      !plugin.module_digest.has_prefix("sha256:") ||
      !plugin.component.has_prefix("/") ||
      !plugin.manifest.has_prefix("/") ||
      !context.host.has_prefix("/") {
      raise VcsError::PolicyExecutionFailed(
        "invalid required-policy identity or runtime paths",
      )
    }
    try ObjectId::parse(plugin.module_digest[7:].to_owned()) |> ignore catch {
      _ =>
        raise VcsError::PolicyExecutionFailed("invalid required-policy digest")
    }
    names[plugin.name] = true
  }
  context
}

///|
fn candidate_transport(
  candidate : CommitCandidate,
  context : PolicyContext,
  plugin : RequiredPolicy,
  hook : String,
) -> String raise {
  if candidate.parents.length() > 1 {
    raise VcsError::PolicyExecutionFailed(
      "WIT v1 supports at most one candidate parent",
    )
  }
  let files : Array[Json] = []
  let mut input_bytes = @utf8.encode(candidate.message).length()
  for file in candidate.staged_files {
    input_bytes = input_bytes +
      file.content.length() +
      @utf8.encode(file.path).length()
    if input_bytes > context.limits.max_input_bytes {
      raise VcsError::PolicyExecutionFailed(
        "candidate exceeds policy input limit",
      )
    }
    files.push({
      "path": file.path,
      "content": file.content.to_array().map(byte => byte.to_int()),
    })
  }
  let parent : Json = match candidate.parents {
    [id] => Json::string(id.hex)
    _ => null
  }
  let value : Json = {
    "schema": 1,
    "expected_plugin": {
      "name": plugin.name,
      "version": plugin.version,
      "module_digest": plugin.module_digest,
    },
    "policy": {
      "allowed_capabilities": plugin.granted_capabilities.filter(capability => {
        context.allowed_capabilities.contains(capability)
      }),
      "limits": context.limits,
      "custom_rules": context.custom_rules,
    },
    "request": {
      "hook": hook,
      "policy_version": "1",
      "commit_message": candidate.message,
      "parent_id": parent,
      "tree_id": candidate.tree_id.hex,
      "files": files,
    },
  }
  value.stringify()
}

///|
priv struct HostPolicyResult {
  status : String
  plugin : String
  plugin_version : String
  diagnostics : Array[PolicyDiagnostic]
} derive(@json.FromJson)

///|
async fn call_policy_host(
  host : String,
  plugin : RequiredPolicy,
  input : String,
  limits : PolicyLimits,
) -> (Int32, Bytes) {
  @async.with_task_group() <| group => {
    let (stdin, writer) = @process.write_to_process()
    group.spawn_bg(() => {
      defer writer.close()
      writer.write(@utf8.encode(input))
    })
    let (stdout_reader, stdout) = @process.read_from_process()
    let (stderr_reader, stderr) = @process.read_from_process()
    let process = group.spawn(() => {
      @process.run(
        host,
        [
          "--request-stdin",
          "--component",
          plugin.component,
          "--manifest",
          plugin.manifest,
        ],
        stdin~,
        stdout~,
        stderr~,
        inherit_env=false,
        cancel_handler=@process.hard_cancel(),
      )
    })
    let output = group.spawn(() => {
      defer stdout_reader.close()
      read_policy_pipe(stdout_reader, limits.max_output_bytes + 4096)
    })
    let logs = group.spawn(() => {
      defer stderr_reader.close()
      read_policy_pipe(stderr_reader, limits.max_log_bytes)
    })
    let bytes = output.wait()
    logs.wait() |> ignore
    (process.wait(), bytes)
  }
}

///|
async fn read_policy_pipe(reader : &@io.Reader, limit : Int32) -> Bytes {
  let bytes : Array[Byte] = []
  while reader.read_some(max_len=4096) is Some(chunk) {
    if bytes.length() + chunk.length() > limit {
      raise VcsError::PolicyExecutionFailed(
        "policy process output/log limit exceeded",
      )
    }
    for byte in chunk {
      bytes.push(byte)
    }
  }
  Bytes::from_array(bytes)
}

///|
pub async fn validate_policies(
  candidate : CommitCandidate,
  context : PolicyContext,
  hook~ : String = "on-commit",
) -> EngineDecision {
  if hook != "on-commit" && hook != "on-receive" {
    return EngineError("unsupported policy lifecycle hook")
  }
  let diagnostics : Array[PolicyDiagnostic] = []
  let mut rejected = false
  let mut warned = false
  for plugin in context.required {
    let (code, output) = @async.with_timeout(
      context.limits.timeout_ms + 15000,
      () => {
        call_policy_host(
          context.host,
          plugin,
          candidate_transport(candidate, context, plugin, hook),
          context.limits,
        )
      },
    ) catch {
      _ =>
        return EngineError(
          "required policy " + plugin.name + " could not execute",
        )
    }
    if code != 0 && code != 2 {
      return EngineError(
        "required policy " + plugin.name + " failed (host exit \{code})",
      )
    }
    if output.length() > context.limits.max_output_bytes + 1 {
      return EngineError("required policy result exceeds transport limit")
    }
    let result : HostPolicyResult = @json.from_json(
      @json.parse(@utf8.decode(output)),
    ) catch {
      _ => return EngineError("required policy returned an invalid result")
    }
    if result.plugin != plugin.name ||
      result.plugin_version != plugin.version ||
      (code == 0 && result.status != "pass" && result.status != "warning") ||
      (code == 2 && result.status != "reject") {
      return EngineError("required policy result identity or status mismatch")
    }
    for diagnostic in result.diagnostics {
      if diagnostic.plugin != plugin.name {
        return EngineError("required policy diagnostic identity mismatch")
      }
    }
    if result.status == "reject" {
      rejected = true
      if result.diagnostics.is_empty() {
        return EngineError("required policy rejected without diagnostics")
      }
    }
    if result.status == "warning" {
      warned = true
    }
    for diagnostic in result.diagnostics {
      diagnostics.push(diagnostic)
    }
  }
  if rejected {
    Reject(diagnostics)
  } else if warned {
    Warning(diagnostics)
  } else {
    Accept
  }
}

///|
fn format_policy_diagnostics(diagnostics : Array[PolicyDiagnostic]) -> String {
  let lines : Array[String] = []
  for item in diagnostics {
    lines.push("Policy: " + safe_policy_text(item.plugin))
    let path = match item.file {
      Some(path) => path
      None => "<candidate>"
    }
    lines.push(
      "File: " +
      safe_policy_text(path) +
      " | Rule: " +
      safe_policy_text(item.rule) +
      " | Severity: " +
      safe_policy_text(item.severity),
    )
    lines.push("Reason: " + safe_policy_text(item.message))
  }
  lines.join("\n")
}

///|
fn safe_policy_text(value : String) -> String {
  let quoted = Json::string(value).stringify()
  quoted[1:quoted.length() - 1].to_owned()
}
