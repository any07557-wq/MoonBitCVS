use std::collections::BTreeSet;
use std::fs;
use std::io::{self, Read};
use std::path::{Component as PathComponent, Path, PathBuf};
use std::sync::mpsc;
use std::time::Duration;

use anyhow::{Context, Result, bail, ensure};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use wasmtime::component::{Component, Linker};
use wasmtime::{Config, Engine, ResourceLimiter, Store, StoreLimits, StoreLimitsBuilder};

mod capabilities;
use capabilities::CapabilityManager;

wasmtime::component::bindgen!({
    path: "../wit",
    world: "policy-plugin",
    ownership: Owning,
});

use exports::moonvcs::policy::evaluator::{
    Decision, Hook, PolicyRequest, PolicyResult, Severity, StagedFile,
};

const SUPPORTED_ABI: &str = "1";
const MAX_TRANSPORT_BYTES: u64 = 16 * 1024 * 1024;
const PLUGIN_CONFIG_PATH: &str = ".moonvcs/plugin-config/v1.json";

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct PluginManifest {
    name: String,
    version: String,
    abi_version: String,
    hooks: Vec<String>,
    requested_capabilities: Vec<String>,
    module_digest: String,
}

struct ManifestLoader;

impl ManifestLoader {
    fn load(path: &Path, hook: &str, pin: Option<&PluginPin>) -> Result<PluginManifest> {
        let manifest: PluginManifest = parse_toml(path)?;
        validate_manifest(&manifest, hook)?;
        if let Some(pin) = pin {
            validate_pin(&manifest, pin)?;
        }
        Ok(manifest)
    }
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct RepositoryPolicy {
    allowed_capabilities: Vec<String>,
    limits: Limits,
    #[serde(default)]
    custom_rules: Vec<serde_json::Value>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct PluginPin {
    name: String,
    version: String,
    module_digest: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct WireFile {
    path: String,
    content: Vec<u8>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct WireRequest {
    hook: String,
    policy_version: String,
    commit_message: String,
    parent_id: Option<String>,
    tree_id: Option<String>,
    files: Vec<WireFile>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct CandidateTransport {
    schema: u32,
    expected_plugin: PluginPin,
    policy: RepositoryPolicy,
    request: WireRequest,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Limits {
    fuel: u64,
    timeout_ms: u64,
    max_memory_bytes: usize,
    max_input_bytes: usize,
    max_output_bytes: usize,
    #[serde(default = "default_log_limit")]
    max_log_bytes: usize,
}

fn default_log_limit() -> usize {
    65536
}

/// Cancel the timer on every exit path, including failed instantiation.
struct EpochTimer {
    cancel: mpsc::Sender<()>,
    thread: Option<std::thread::JoinHandle<()>>,
}

impl EpochTimer {
    fn start(engine: Engine, timeout_ms: u64) -> Self {
        let (cancel, receiver) = mpsc::channel();
        let thread = std::thread::spawn(move || {
            if matches!(
                receiver.recv_timeout(Duration::from_millis(timeout_ms)),
                Err(mpsc::RecvTimeoutError::Timeout)
            ) {
                engine.increment_epoch();
            }
        });
        Self {
            cancel,
            thread: Some(thread),
        }
    }
}

impl Drop for EpochTimer {
    fn drop(&mut self) {
        let _ = self.cancel.send(());
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
    }
}

#[derive(Debug)]
struct Cli {
    component: PathBuf,
    manifest: PathBuf,
    policy: PathBuf,
    hook: String,
    message: String,
    files: Vec<PathBuf>,
    request_stdin: bool,
}

#[derive(Serialize)]
struct JsonDiagnostic<'a> {
    plugin: &'a str,
    rule: &'a str,
    file: Option<&'a str>,
    line: Option<usize>,
    code: &'a str,
    severity: &'static str,
    message: &'a str,
    path: Option<&'a str>,
}

#[derive(Serialize)]
struct JsonResult<'a> {
    status: &'static str,
    plugin: &'a str,
    plugin_version: &'a str,
    diagnostics: Vec<JsonDiagnostic<'a>>,
}

struct HostState {
    limits: StoreLimits,
    memory_limit_bytes: usize,
    denied_memory_growth_to: Option<usize>,
}

impl ResourceLimiter for HostState {
    fn memory_growing(
        &mut self,
        current: usize,
        desired: usize,
        maximum: Option<usize>,
    ) -> wasmtime::Result<bool> {
        let allowed = self.limits.memory_growing(current, desired, maximum);
        if matches!(&allowed, Ok(false)) {
            self.denied_memory_growth_to = Some(desired);
        }
        allowed
    }

    fn memory_grow_failed(&mut self, error: wasmtime::Error) -> wasmtime::Result<()> {
        self.limits.memory_grow_failed(error)
    }

    fn table_growing(
        &mut self,
        current: usize,
        desired: usize,
        maximum: Option<usize>,
    ) -> wasmtime::Result<bool> {
        self.limits.table_growing(current, desired, maximum)
    }

    fn table_grow_failed(&mut self, error: wasmtime::Error) -> wasmtime::Result<()> {
        self.limits.table_grow_failed(error)
    }

    fn instances(&self) -> usize {
        self.limits.instances()
    }

    fn tables(&self) -> usize {
        self.limits.tables()
    }

    fn memories(&self) -> usize {
        self.limits.memories()
    }
}

fn main() {
    match real_main() {
        Ok(code) => std::process::exit(code),
        Err(error) => {
            let payload = serde_json::json!({
                "status": "error",
                "reason": format!("{error:#}").chars().take(1024).collect::<String>(),
            });
            println!("{payload}");
            std::process::exit(3);
        }
    }
}

fn real_main() -> Result<i32> {
    let mode = std::env::args().nth(1);
    if matches!(
        mode.as_deref(),
        Some("--default-config" | "--multi-policy-config")
    ) {
        return emit_default_config(mode.as_deref() == Some("--multi-policy-config"));
    }
    let cli = parse_cli(std::env::args().skip(1))?;
    if cli.request_stdin {
        let transport = read_transport(io::stdin().lock())?;
        ensure!(
            transport.schema == 1,
            "unsupported candidate transport schema"
        );
        let manifest = ManifestLoader::load(
            &cli.manifest,
            &transport.request.hook,
            Some(&transport.expected_plugin),
        )?;
        let request = request_from_transport(&manifest, &transport.policy, transport.request)?;
        let component_bytes = read_bounded(&cli.component, MAX_TRANSPORT_BYTES as usize)?;
        verify_digest(&component_bytes, &transport.expected_plugin.module_digest)?;
        let granted = request.granted_capabilities.clone();
        let result = evaluate(&component_bytes, &transport.policy.limits, request)?;
        return emit_result(&manifest, &result, &granted, &transport.policy.limits);
    }
    let manifest = ManifestLoader::load(&cli.manifest, &cli.hook, None)?;
    let repository: RepositoryPolicy = parse_toml(&cli.policy)?;
    validate_manifest(&manifest, &cli.hook)?;
    let granted = resolve_capabilities(&manifest, &repository)?;

    let component_bytes = read_bounded(&cli.component, MAX_TRANSPORT_BYTES as usize)?;
    verify_digest(&component_bytes, &manifest.module_digest)?;

    let request_metadata_size = cli
        .message
        .len()
        .checked_add(granted.iter().map(String::len).sum())
        .context("policy request size overflow")?;
    let mut files = load_staged_files(
        &cli.files,
        repository.limits.max_input_bytes,
        request_metadata_size,
    )?;
    filter_files(&mut files, &granted);
    let request = PolicyRequest {
        hook: parse_hook(&cli.hook)?,
        policy_version: SUPPORTED_ABI.to_owned(),
        commit_message: if granted.iter().any(|c| c == "commit_metadata.read") {
            cli.message
        } else {
            String::new()
        },
        parent_id: None,
        tree_id: None,
        files,
        granted_capabilities: granted.clone(),
    };

    let result = evaluate(&component_bytes, &repository.limits, request)?;
    emit_result(&manifest, &result, &granted, &repository.limits)
}

fn emit_default_config(multi: bool) -> Result<i32> {
    let host = std::env::current_exe()?.canonicalize()?;
    let root = host
        .parent()
        .and_then(Path::parent)
        .context("invalid runtime location")?;
    let mut required = Vec::new();
    let plugins = if multi {
        vec!["secret-scanner", "license-check"]
    } else {
        vec!["secret-scanner"]
    };
    for plugin in plugins {
        let component = root.join(format!("components/{plugin}.component.wasm"));
        let manifest_path = root.join(format!("components/{plugin}.plugin.toml"));
        let manifest = ManifestLoader::load(&manifest_path, "on-commit", None)?;
        verify_digest(
            &read_bounded(&component, MAX_TRANSPORT_BYTES as usize)?,
            &manifest.module_digest,
        )?;
        // This built-in policy authority deliberately approves known demo capabilities.
        // Never copy arbitrary manifest requests into grants.
        let grants = if plugin == "secret-scanner" {
            vec!["staged_content.read", "diagnostic.emit"]
        } else {
            vec![
                "staged_content.list",
                "staged_content.read",
                "diagnostic.emit",
            ]
        };
        required.push(serde_json::json!({"name": manifest.name, "version": manifest.version,
            "module_digest": manifest.module_digest, "component": component, "manifest": manifest_path,
            "granted_capabilities": grants}));
    }
    let config = serde_json::json!({
        "schema": 2, "host": host, "required": required,
        "allowed_capabilities": capabilities::AVAILABLE,
        "limits": {"fuel": 50000000, "timeout_ms": 1000, "max_memory_bytes": 33554432,
            "max_input_bytes": 1048576, "max_output_bytes": 65536, "max_log_bytes": 16384},
        "custom_rules": []
    });
    println!("{}", serde_json::to_string_pretty(&config)?);
    Ok(0)
}

fn parse_cli(args: impl Iterator<Item = String>) -> Result<Cli> {
    let mut component = PathBuf::from("target/components/secret-scanner.component.wasm");
    let mut manifest = PathBuf::from("plugins/secret-scanner/plugin.toml");
    let mut policy = PathBuf::from("examples/repository-policy.toml");
    let mut hook = String::from("on-commit");
    let mut message = String::from("MoonVCS policy evaluation");
    let mut files = Vec::new();
    let mut request_stdin = false;
    let mut args = args;

    while let Some(flag) = args.next() {
        let value = || anyhow::anyhow!("missing value for {flag}");
        match flag.as_str() {
            "--request-stdin" => request_stdin = true,
            "--component" => component = PathBuf::from(args.next().ok_or_else(value)?),
            "--manifest" => manifest = PathBuf::from(args.next().ok_or_else(value)?),
            "--policy" => policy = PathBuf::from(args.next().ok_or_else(value)?),
            "--hook" => hook = args.next().ok_or_else(value)?,
            "--message" => message = args.next().ok_or_else(value)?,
            "--file" => files.push(PathBuf::from(args.next().ok_or_else(value)?)),
            "--help" | "-h" => {
                println!(
                    "moonvcs-policy-host [--component PATH] [--manifest PATH] \
                     [--policy PATH] [--hook on-commit|on-receive] \
                     [--message TEXT] --file REPOSITORY_RELATIVE_PATH ..."
                );
                std::process::exit(0);
            }
            _ => bail!("unknown argument {flag}"),
        }
    }
    ensure!(
        request_stdin || !files.is_empty(),
        "at least one --file or --request-stdin is required"
    );
    ensure!(
        !request_stdin || files.is_empty(),
        "--request-stdin cannot be combined with --file"
    );
    Ok(Cli {
        component,
        manifest,
        policy,
        hook,
        message,
        files,
        request_stdin,
    })
}

fn read_transport(reader: impl Read) -> Result<CandidateTransport> {
    let mut bytes = Vec::new();
    reader
        .take(MAX_TRANSPORT_BYTES + 1)
        .read_to_end(&mut bytes)
        .context("failed to read candidate transport")?;
    ensure!(
        bytes.len() as u64 <= MAX_TRANSPORT_BYTES,
        "candidate transport exceeds size limit"
    );
    // Never include potentially sensitive request text in parser errors.
    serde_json::from_slice(&bytes).map_err(|_| anyhow::anyhow!("invalid candidate transport JSON"))
}

fn validate_pin(manifest: &PluginManifest, pin: &PluginPin) -> Result<()> {
    ensure!(
        manifest.name == pin.name,
        "required plugin identity mismatch"
    );
    ensure!(
        manifest.version == pin.version,
        "required plugin version mismatch"
    );
    ensure!(
        manifest.module_digest == pin.module_digest,
        "required plugin digest binding mismatch"
    );
    Ok(())
}

fn request_from_transport(
    manifest: &PluginManifest,
    policy: &RepositoryPolicy,
    wire: WireRequest,
) -> Result<PolicyRequest> {
    validate_manifest(manifest, &wire.hook)?;
    ensure!(
        wire.policy_version == SUPPORTED_ABI,
        "unsupported policy request version"
    );
    ensure!(
        policy.limits.fuel > 0 && policy.limits.timeout_ms > 0,
        "policy budgets must be positive"
    );
    let granted = resolve_capabilities(manifest, policy)?;
    let mut seen = BTreeSet::new();
    let mut files = Vec::new();
    for file in wire.files {
        validate_repository_path(Path::new(&file.path))?;
        ensure!(
            !file.path.starts_with(".moonvcs/"),
            "reserved policy metadata path"
        );
        ensure!(seen.insert(file.path.clone()), "duplicate staged path");
        files.push(StagedFile {
            path: file.path,
            content: file.content,
        });
    }
    if manifest.name == "secret-scanner" && !policy.custom_rules.is_empty() {
        files.push(StagedFile {
            path: PLUGIN_CONFIG_PATH.into(),
            content: serde_json::to_vec(&serde_json::json!({"custom_rules": policy.custom_rules}))?,
        });
    }
    let mut size = wire.commit_message.len()
        + wire.policy_version.len()
        + wire.parent_id.as_ref().map_or(0, String::len)
        + wire.tree_id.as_ref().map_or(0, String::len)
        + granted.iter().map(String::len).sum::<usize>();
    for file in &files {
        size = size
            .checked_add(file.path.len())
            .and_then(|n| n.checked_add(file.content.len()))
            .context("candidate size overflow")?;
    }
    ensure!(
        size <= policy.limits.max_input_bytes,
        "candidate input exceeds configured size limit"
    );
    filter_files(&mut files, &granted);
    let metadata = granted.iter().any(|c| c == "commit_metadata.read");
    Ok(PolicyRequest {
        hook: parse_hook(&wire.hook)?,
        policy_version: wire.policy_version,
        commit_message: if metadata {
            wire.commit_message
        } else {
            String::new()
        },
        parent_id: if metadata { wire.parent_id } else { None },
        tree_id: if metadata { wire.tree_id } else { None },
        files,
        granted_capabilities: granted,
    })
}

fn parse_toml<T: for<'de> Deserialize<'de>>(path: &Path) -> Result<T> {
    let bytes = read_bounded(path, 65536)?;
    let text = std::str::from_utf8(&bytes).context("configuration must be UTF-8")?;
    toml::from_str(text).map_err(|_| anyhow::anyhow!("invalid TOML configuration"))
}

fn read_bounded(path: &Path, limit: usize) -> Result<Vec<u8>> {
    let mut bytes = Vec::new();
    fs::File::open(path)
        .context("required runtime file is unavailable")?
        .take(limit as u64 + 1)
        .read_to_end(&mut bytes)?;
    ensure!(bytes.len() <= limit, "runtime file exceeds size limit");
    Ok(bytes)
}

fn filter_files(files: &mut Vec<StagedFile>, granted: &[String]) {
    if granted.iter().any(|c| c == "staged_content.read") {
        return;
    }
    if granted.iter().any(|c| c == "staged_content.list") {
        // Host-injected configuration is content, not a staged filename.
        files.retain(|f| f.path != PLUGIN_CONFIG_PATH);
        for file in files {
            file.content.clear();
        }
    } else {
        files.clear();
    }
}

fn validate_manifest(manifest: &PluginManifest, hook: &str) -> Result<()> {
    ensure!(
        !manifest.name.is_empty()
            && manifest.name.len() <= 64
            && manifest
                .name
                .bytes()
                .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-'),
        "invalid plugin name"
    );
    ensure!(
        !manifest.version.is_empty()
            && manifest.version.len() <= 64
            && manifest
                .version
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || b".-+".contains(&b)),
        "invalid plugin version"
    );
    ensure!(
        manifest.module_digest.len() == 71
            && manifest.module_digest.starts_with("sha256:")
            && manifest.module_digest[7..]
                .bytes()
                .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b)),
        "invalid plugin digest"
    );
    ensure!(
        manifest.abi_version == SUPPORTED_ABI,
        "unsupported plugin ABI; host supports {SUPPORTED_ABI}"
    );
    ensure!(
        manifest.hooks.iter().any(|configured| configured == hook),
        "plugin does not declare requested hook"
    );
    parse_hook(hook)?;
    ensure!(
        manifest.hooks.iter().all(|h| parse_hook(h).is_ok()),
        "manifest declares unsupported hook"
    );
    Ok(())
}

fn resolve_capabilities(
    manifest: &PluginManifest,
    repository: &RepositoryPolicy,
) -> Result<Vec<String>> {
    CapabilityManager::resolve(
        &manifest.requested_capabilities,
        &repository.allowed_capabilities,
    )
}

fn verify_digest(component: &[u8], expected: &str) -> Result<()> {
    let actual = format!("sha256:{:x}", Sha256::digest(component));
    ensure!(
        actual == expected,
        "component digest mismatch: expected {expected}, got {actual}"
    );
    Ok(())
}

fn load_staged_files(
    paths: &[PathBuf],
    max_input_bytes: usize,
    initial_size: usize,
) -> Result<Vec<StagedFile>> {
    let mut total = initial_size;
    let mut files = Vec::with_capacity(paths.len());
    let root = std::env::current_dir()?.canonicalize()?;
    for path in paths {
        validate_repository_path(path)?;
        let mut current = root.clone();
        for part in path.components() {
            current.push(part);
            ensure!(
                !fs::symlink_metadata(&current)?.file_type().is_symlink(),
                "staged symlinks are forbidden"
            );
        }
        ensure!(
            current.canonicalize()?.starts_with(&root),
            "staged path escapes repository"
        );
        let metadata = fs::metadata(path)
            .with_context(|| format!("failed to inspect staged file {}", path.display()))?;
        ensure!(
            metadata.is_file(),
            "staged path is not a regular file: {}",
            path.display()
        );
        let size = usize::try_from(metadata.len()).context("staged file is too large")?;
        total = total
            .checked_add(size)
            .and_then(|value| value.checked_add(path.as_os_str().len()))
            .context("staged input size overflow")?;
        ensure!(
            total <= max_input_bytes,
            "staged input exceeds {max_input_bytes} bytes"
        );
        let content = read_bounded(path, size)?;
        files.push(StagedFile {
            path: path.to_string_lossy().into_owned(),
            content,
        });
    }
    Ok(files)
}

fn validate_repository_path(path: &Path) -> Result<()> {
    ensure!(!path.is_absolute(), "absolute staged paths are forbidden");
    let text = path.to_str().context("staged path must be UTF-8")?;
    ensure!(
        !text.is_empty()
            && text.len() <= 4096
            && !text.contains(['\\', '\0'])
            && text
                .split('/')
                .all(|p| !p.is_empty() && p != "." && p != "..")
            && text.split('/').next() != Some(".moonvcs"),
        "invalid staged path"
    );
    for part in path.components() {
        ensure!(
            matches!(part, PathComponent::Normal(_)),
            "staged path may not escape the repository: {}",
            path.display()
        );
    }
    Ok(())
}

fn parse_hook(hook: &str) -> Result<Hook> {
    match hook {
        "on-commit" => Ok(Hook::OnCommit),
        "on-receive" => Ok(Hook::OnReceive),
        _ => bail!("unsupported hook {hook}"),
    }
}

fn evaluate(
    component_bytes: &[u8],
    limits: &Limits,
    request: PolicyRequest,
) -> Result<PolicyResult> {
    ensure!(
        limits.fuel > 0
            && (1..=60000).contains(&limits.timeout_ms)
            && (65536..=268435456).contains(&limits.max_memory_bytes)
            && (1..=1048576).contains(&limits.max_input_bytes)
            && (1..=1048576).contains(&limits.max_output_bytes)
            && (1..=1048576).contains(&limits.max_log_bytes),
        "invalid policy resource budgets"
    );
    let mut config = Config::new();
    config.wasm_component_model(true);
    config.consume_fuel(true);
    config.epoch_interruption(true);
    let engine = Engine::new(&config)
        .map_err(|error| anyhow::anyhow!("failed to create Wasmtime engine: {error}"))?;
    let component = Component::new(&engine, component_bytes)
        .map_err(|error| anyhow::anyhow!("invalid policy component: {error}"))?;
    ensure!(
        component.component_type().imports(&engine).len() == 0,
        "CapabilityDenied: component imports are forbidden (including WASI, filesystem and network)"
    );
    let linker = Linker::<HostState>::new(&engine);
    let store_limits = StoreLimitsBuilder::new()
        .memory_size(limits.max_memory_bytes)
        .instances(16)
        // memory_size is per memory: one memory makes this a total linear-memory cap.
        .memories(1)
        .tables(8)
        .table_elements(10000)
        .build();
    let mut store = Store::new(
        &engine,
        HostState {
            limits: store_limits,
            memory_limit_bytes: limits.max_memory_bytes,
            denied_memory_growth_to: None,
        },
    );
    store.limiter(|state| state);
    store
        .set_fuel(limits.fuel)
        .map_err(|error| anyhow::anyhow!("failed to set plugin fuel: {error}"))?;
    store.set_epoch_deadline(1);
    let _timer = EpochTimer::start(engine.clone(), limits.timeout_ms);
    let bindings = PolicyPlugin::instantiate(&mut store, &component, &linker).map_err(|error| {
        anyhow::anyhow!(
            "failed to instantiate policy component without ambient capabilities: {}",
            error.root_cause()
        )
    })?;
    let call_result = bindings
        .moonvcs_policy_evaluator()
        .call_evaluate(&mut store, &request);
    let call = match call_result {
        _ if store.data().denied_memory_growth_to.is_some() => {
            let state = store.data();
            Err(anyhow::anyhow!(
                "plugin memory growth denied by configured {}-byte limit (requested {} bytes)",
                state.memory_limit_bytes,
                state.denied_memory_growth_to.unwrap()
            ))
        }
        Ok(result) => Ok(result),
        Err(error) => {
            let root_cause = error.root_cause();
            Err(anyhow::anyhow!(
                "policy plugin trapped, timed out, or exhausted its resource budget: {root_cause}"
            ))
        }
    };
    call
}

fn ensure_output_limit(result: &PolicyResult, max_output_bytes: usize) -> Result<()> {
    let decision_size = match &result.decision {
        Decision::Error(reason) => reason.len(),
        Decision::Pass | Decision::Reject => 0,
    };
    let size = result
        .diagnostics
        .iter()
        .try_fold(decision_size, |total, diagnostic| {
            let path_len = diagnostic.path.as_ref().map_or(0, String::len);
            total
                .checked_add(diagnostic.code.len())
                .and_then(|n| n.checked_add(diagnostic.message.len()))
                .and_then(|n| n.checked_add(path_len))
                .context("policy output size overflow")
        })?;
    ensure!(
        size <= max_output_bytes,
        "policy output exceeds {max_output_bytes} bytes"
    );
    Ok(())
}

fn emit_result(
    manifest: &PluginManifest,
    result: &PolicyResult,
    granted: &[String],
    limits: &Limits,
) -> Result<i32> {
    ensure_output_limit(result, limits.max_output_bytes)?;
    ensure_output_limit(result, limits.max_log_bytes)
        .context("diagnostic log size limit exceeded")?;
    ensure!(
        result.diagnostics.is_empty() || granted.iter().any(|c| c == "diagnostic.emit"),
        "CapabilityDenied: diagnostic.emit was not granted"
    );
    ensure!(
        !matches!(result.decision, Decision::Reject) || !result.diagnostics.is_empty(),
        "invalid policy result: Reject requires diagnostics"
    );
    ensure!(
        result.diagnostics.len() <= 256,
        "too many policy diagnostics"
    );
    ensure!(
        !matches!(result.decision, Decision::Pass)
            || result
                .diagnostics
                .iter()
                .all(|d| !matches!(d.severity, Severity::Error)),
        "invalid policy result: Pass cannot carry error diagnostics"
    );
    for diagnostic in &result.diagnostics {
        ensure!(
            !diagnostic.code.is_empty() && diagnostic.code.len() <= 128,
            "invalid diagnostic rule"
        );
        if let Some(path) = &diagnostic.path {
            validate_repository_path(Path::new(path))?;
        }
    }
    let (status, exit_code) = match &result.decision {
        Decision::Pass
            if result
                .diagnostics
                .iter()
                .any(|d| matches!(d.severity, Severity::Warning)) =>
        {
            ("warning", 0)
        }
        Decision::Pass => ("pass", 0),
        Decision::Reject => ("reject", 2),
        Decision::Error(_) => bail!("plugin returned an error"),
    };
    let diagnostics = result
        .diagnostics
        .iter()
        .map(|diagnostic| JsonDiagnostic {
            plugin: &manifest.name,
            rule: &diagnostic.code,
            file: diagnostic.path.as_deref(),
            line: None,
            code: &diagnostic.code,
            severity: match diagnostic.severity {
                Severity::Info => "info",
                Severity::Warning => "warning",
                Severity::Error => "error",
            },
            message: &diagnostic.message,
            path: diagnostic.path.as_deref(),
        })
        .collect();
    let output = serde_json::to_string(&JsonResult {
        status,
        plugin: &manifest.name,
        plugin_version: &manifest.version,
        diagnostics,
    })?;
    ensure!(
        output.len() <= limits.max_output_bytes,
        "serialized policy output exceeds size limit"
    );
    println!("{output}");
    Ok(exit_code)
}

#[cfg(test)]
mod security_tests;

#[cfg(test)]
mod tests {
    use super::*;

    fn manifest(requested: &[&str]) -> PluginManifest {
        PluginManifest {
            name: "test".into(),
            version: "0.1.0".into(),
            abi_version: "1".into(),
            hooks: vec!["on-commit".into()],
            requested_capabilities: requested.iter().map(|item| (*item).into()).collect(),
            module_digest: format!("sha256:{}", "0".repeat(64)),
        }
    }

    fn repository(allowed: &[&str]) -> RepositoryPolicy {
        RepositoryPolicy {
            custom_rules: Vec::new(),
            allowed_capabilities: allowed.iter().map(|item| (*item).into()).collect(),
            limits: Limits {
                fuel: 1,
                timeout_ms: 1,
                max_memory_bytes: 1,
                max_input_bytes: 1,
                max_output_bytes: 1,
                max_log_bytes: 1,
            },
        }
    }

    #[test]
    fn grants_only_requested_supported_and_allowed_capabilities() {
        let granted = resolve_capabilities(
            &manifest(&["staged_content.read"]),
            &repository(&["diagnostic.emit", "staged_content.read"]),
        )
        .unwrap();
        assert_eq!(granted, vec!["staged_content.read"]);
    }

    #[test]
    fn rejects_capability_missing_from_repository_grant() {
        let error = resolve_capabilities(
            &manifest(&["staged_content.read"]),
            &repository(&["diagnostic.emit"]),
        )
        .unwrap_err();
        assert!(error.to_string().contains("not granted by the repository"));
    }

    #[test]
    fn rejects_capability_not_implemented_by_host() {
        let error = resolve_capabilities(
            &manifest(&["filesystem.read"]),
            &repository(&["filesystem.read"]),
        )
        .unwrap_err();
        assert!(error.to_string().contains("not provided by this host"));
    }

    #[test]
    fn rejects_parent_directory_escape() {
        let error = validate_repository_path(Path::new("../secret")).unwrap_err();
        assert!(error.to_string().contains("invalid staged path"));
    }

    #[test]
    fn records_memory_growth_denied_by_store_limit() {
        let mut state = HostState {
            limits: StoreLimitsBuilder::new().memory_size(64 * 1024).build(),
            memory_limit_bytes: 64 * 1024,
            denied_memory_growth_to: None,
        };

        assert!(!state.memory_growing(0, 128 * 1024, None).unwrap());
        assert_eq!(state.denied_memory_growth_to, Some(128 * 1024));
    }

    #[test]
    fn required_plugin_is_bound_to_name_version_and_digest() {
        let m = manifest(&[]);
        let mut pin = PluginPin {
            name: m.name.clone(),
            version: m.version.clone(),
            module_digest: m.module_digest.clone(),
        };
        validate_pin(&m, &pin).unwrap();
        pin.version = "changed".into();
        assert!(validate_pin(&m, &pin).is_err());
        pin.version = m.version.clone();
        pin.module_digest = "changed".into();
        assert!(validate_pin(&m, &pin).is_err());
        pin.module_digest = m.module_digest.clone();
        pin.name = "other".into();
        assert!(validate_pin(&m, &pin).is_err());
    }

    #[test]
    fn malformed_transport_errors_do_not_echo_candidate_bytes() {
        let error = read_transport(&b"{\"secret\":\"harmless-do-not-log"[..]).unwrap_err();
        assert_eq!(error.to_string(), "invalid candidate transport JSON");
    }

    #[test]
    fn transport_uses_supplied_binary_bytes_and_rejects_metadata_spoofing() {
        let m = manifest(&["staged_content.read"]);
        let mut policy = repository(&["staged_content.read"]);
        policy.limits.max_input_bytes = 4096;
        let request = || WireRequest {
            hook: "on-commit".into(),
            policy_version: "1".into(),
            commit_message: "test".into(),
            parent_id: None,
            tree_id: None,
            files: vec![WireFile {
                path: "missing-on-disk.bin".into(),
                content: vec![0, 255, 1],
            }],
        };
        let result = request_from_transport(&m, &policy, request()).unwrap();
        assert_eq!(result.files[0].content, vec![0, 255, 1]);
        policy.allowed_capabilities.push("diagnostic.emit".into());
        let message_only =
            request_from_transport(&manifest(&["diagnostic.emit"]), &policy, request()).unwrap();
        assert!(message_only.files.is_empty());
        let mut reserved = request();
        reserved.files[0].path = PLUGIN_CONFIG_PATH.into();
        assert!(request_from_transport(&m, &policy, reserved).is_err());
    }
}
