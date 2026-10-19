use super::*;
use exports::moonvcs::policy::evaluator::Diagnostic;
use std::time::Instant;

fn root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .to_owned()
}

fn manifest(name: &str) -> PluginManifest {
    parse_toml(&root().join(format!("plugins/{name}/plugin.toml"))).unwrap()
}

fn component(name: &str) -> Vec<u8> {
    read_bounded(
        &root().join(format!("target/components/{name}.component.wasm")),
        MAX_TRANSPORT_BYTES as usize,
    )
    .expect("run scripts/build-component.sh first")
}

fn limits() -> Limits {
    Limits {
        fuel: 50000000,
        timeout_ms: 1000,
        max_memory_bytes: 33554432,
        max_input_bytes: 1048576,
        max_output_bytes: 65536,
        max_log_bytes: 16384,
    }
}

fn policy(caps: &[&str]) -> RepositoryPolicy {
    RepositoryPolicy {
        allowed_capabilities: caps.iter().map(|c| c.to_string()).collect(),
        limits: limits(),
        custom_rules: vec![],
    }
}

fn wire(message: &str) -> WireRequest {
    WireRequest {
        hook: "on-commit".into(),
        policy_version: "1".into(),
        commit_message: message.into(),
        parent_id: Some("private-parent".into()),
        tree_id: Some("private-tree".into()),
        files: vec![WireFile {
            path: "allowed.txt".into(),
            content: b"harmless-allowed-content".to_vec(),
        }],
    }
}

fn request(name: &str, caps: &[&str], message: &str) -> PolicyRequest {
    request_from_transport(&manifest(name), &policy(caps), wire(message)).unwrap()
}

#[test]
fn real_restricted_moonbit_plugin_observes_only_authorized_request_data() {
    let request = request(
        "restricted-plugin",
        &["staged_content.read"],
        "private-metadata",
    );
    let result = evaluate(&component("restricted-plugin"), &limits(), request).unwrap();
    assert!(matches!(result.decision, Decision::Pass));
    assert!(result.diagnostics.is_empty());
}

#[test]
fn requested_intersection_does_not_inherit_unrequested_grants() {
    let request = request("restricted-plugin", &capabilities::AVAILABLE, "private");
    assert_eq!(request.granted_capabilities, ["staged_content.read"]);
    assert!(request.commit_message.is_empty());
    assert!(request.parent_id.is_none() && request.tree_id.is_none());
}

#[test]
fn list_only_gets_paths_but_no_bytes_and_no_injected_config() {
    let mut m = manifest("restricted-plugin");
    m.requested_capabilities = vec!["staged_content.list".into()];
    let mut p = policy(&["staged_content.list"]);
    p.custom_rules = vec![serde_json::json!({"id":"demo", "literal":"harmless"})];
    let result = request_from_transport(&m, &p, wire("private")).unwrap();
    assert_eq!(result.files.len(), 1);
    assert_eq!(result.files[0].path, "allowed.txt");
    assert!(result.files[0].content.is_empty());
    assert!(result.commit_message.is_empty());
}

#[test]
fn no_read_or_list_receives_no_files() {
    let mut m = manifest("restricted-plugin");
    m.requested_capabilities = vec![];
    let result =
        request_from_transport(&m, &policy(&capabilities::AVAILABLE), wire("private")).unwrap();
    assert!(result.files.is_empty() && result.granted_capabilities.is_empty());
}

#[test]
fn metadata_requires_an_explicit_requested_and_granted_capability() {
    let mut m = manifest("restricted-plugin");
    m.requested_capabilities = vec!["commit_metadata.read".into()];
    let result =
        request_from_transport(&m, &policy(&["commit_metadata.read"]), wire("metadata")).unwrap();
    assert_eq!(result.commit_message, "metadata");
    assert_eq!(result.parent_id.as_deref(), Some("private-parent"));
    assert!(result.files.is_empty());
}

#[test]
fn overrequested_supported_capability_is_actually_denied() {
    let mut m = manifest("restricted-plugin");
    m.requested_capabilities.push("commit_metadata.read".into());
    let error = resolve_capabilities(&m, &policy(&["staged_content.read"])).unwrap_err();
    assert!(error.to_string().contains("CapabilityDenied"));
    assert!(error.to_string().contains("not granted"));
}

#[test]
fn repository_secrets_is_unavailable_even_if_a_config_accidentally_grants_it() {
    let mut m = manifest("restricted-plugin");
    m.requested_capabilities
        .push("repository.secrets.read".into());
    let error = resolve_capabilities(
        &m,
        &policy(&["staged_content.read", "repository.secrets.read"]),
    )
    .unwrap_err();
    assert!(error.to_string().contains("CapabilityDenied"));
    assert!(error.to_string().contains("not provided"));
}

#[test]
fn manifest_abi_hook_digest_and_unknown_fields_fail_closed() {
    let mut m = manifest("restricted-plugin");
    validate_manifest(&m, "on-commit").unwrap();
    m.abi_version = "2".into();
    assert!(validate_manifest(&m, "on-commit").is_err());
    m.abi_version = "1".into();
    assert!(validate_manifest(&m, "on-receive").is_err());
    m.hooks.push("on-unknown".into());
    assert!(validate_manifest(&m, "on-commit").is_err());
    assert!(
        verify_digest(
            &component("restricted-plugin"),
            &format!("sha256:{}", "0".repeat(64))
        )
        .is_err()
    );
    let text = fs::read_to_string(root().join("plugins/restricted-plugin/plugin.toml")).unwrap();
    assert!(toml::from_str::<PluginManifest>(&format!("{text}\nambient_access = true")).is_err());
}

#[test]
fn noncanonical_reserved_traversal_and_duplicate_paths_are_denied() {
    for path in [
        "../secret",
        "/tmp/secret",
        "./.moonvcs/config",
        ".moonvcs",
        "a//b",
        "a/./b",
        "a/../b",
        "a\\b",
        "a\0b",
    ] {
        assert!(
            validate_repository_path(Path::new(path)).is_err(),
            "{path:?}"
        );
    }
    let mut request = wire("private");
    request.files.push(WireFile {
        path: "allowed.txt".into(),
        content: vec![],
    });
    assert!(
        request_from_transport(
            &manifest("restricted-plugin"),
            &policy(&["staged_content.read"]),
            request
        )
        .is_err()
    );
}

#[test]
fn input_size_is_enforced_before_execution_even_for_filtered_data() {
    let mut p = policy(&["staged_content.read"]);
    p.limits.max_input_bytes = 8;
    assert!(request_from_transport(&manifest("restricted-plugin"), &p, wire("private")).is_err());
}

#[test]
fn malicious_diagnostics_need_permission_and_obey_log_and_serialized_output_limits() {
    let m = manifest("restricted-plugin");
    let result = PolicyResult {
        decision: Decision::Pass,
        diagnostics: vec![Diagnostic {
            code: "demo".into(),
            severity: Severity::Warning,
            message: "x".repeat(4096),
            path: None,
        }],
    };
    assert!(
        emit_result(&m, &result, &[], &limits())
            .unwrap_err()
            .to_string()
            .contains("CapabilityDenied")
    );
    let mut budget = limits();
    budget.max_log_bytes = 128;
    assert!(emit_result(&m, &result, &["diagnostic.emit".into()], &budget).is_err());
    budget = limits();
    budget.max_output_bytes = 128;
    let tiny = PolicyResult {
        decision: Decision::Pass,
        diagnostics: vec![Diagnostic {
            code: "demo".into(),
            severity: Severity::Warning,
            message: "\"\\\n".repeat(5),
            path: None,
        }],
    };
    assert!(emit_result(&m, &tiny, &["diagnostic.emit".into()], &budget).is_err());
    let invalid = PolicyResult {
        decision: Decision::Reject,
        diagnostics: vec![],
    };
    assert!(emit_result(&m, &invalid, &[], &limits()).is_err());
}

#[test]
fn malformed_canonical_return_is_a_controlled_call_error() {
    let request = request("restricted-plugin", &["staged_content.read"], "private");
    let error = evaluate(&component("invalid-result"), &limits(), request).unwrap_err();
    assert!(error.to_string().contains("discriminant"), "{error:#}");
}

#[test]
fn fuel_and_epoch_independently_interrupt_real_moonbit_infinite_loop() {
    let bytes = component("adversarial-fixture");
    let make_request = || {
        request(
            "adversarial-fixture",
            &["commit_metadata.read", "diagnostic.emit"],
            "fixture:infinite-loop",
        )
    };
    let mut budget = limits();
    budget.fuel = 20000;
    let error = evaluate(&bytes, &budget, make_request()).unwrap_err();
    assert!(error.to_string().contains("fuel"), "{error:#}");
    budget.fuel = u64::MAX;
    budget.timeout_ms = 10;
    let start = Instant::now();
    let error = evaluate(&bytes, &budget, make_request()).unwrap_err();
    assert!(error.to_string().contains("interrupt"), "{error:#}");
    assert!(start.elapsed() < Duration::from_secs(10));
}

#[test]
fn epoch_interrupts_component_initializer_before_evaluate() {
    let mut budget = limits();
    budget.fuel = u64::MAX;
    budget.timeout_ms = 10;
    let request = request("restricted-plugin", &["staged_content.read"], "private");
    let error = evaluate(&component("infinite-start"), &budget, request).unwrap_err();
    assert!(error.to_string().contains("instantiate"), "{error:#}");
    assert!(error.to_string().contains("interrupt"), "{error:#}");
}

#[test]
fn multiple_memories_cannot_multiply_the_configured_linear_memory_cap() {
    let engine = Engine::default();
    let component = Component::new(
        &engine,
        "(component (core module (memory 1) (memory 1)) (core instance (instantiate 0)))",
    )
    .unwrap();
    let mut store = Store::new(
        &engine,
        StoreLimitsBuilder::new()
            .memory_size(65536)
            .memories(1)
            .build(),
    );
    store.limiter(|limits| limits);
    assert!(
        Linker::new(&engine)
            .instantiate(&mut store, &component)
            .is_err()
    );
}

#[test]
fn trap_and_memory_exhaustion_are_controlled_errors() {
    for mode in ["fixture:trap", "fixture:memory-growth"] {
        let request = request(
            "adversarial-fixture",
            &["commit_metadata.read", "diagnostic.emit"],
            mode,
        );
        let mut budget = limits();
        budget.max_memory_bytes = 4 * 1024 * 1024;
        budget.fuel = 1000000000;
        let error = evaluate(&component("adversarial-fixture"), &budget, request).unwrap_err();
        if mode.contains("memory") {
            assert!(error.to_string().contains("memory"), "{error:#}");
        } else {
            assert!(error.to_string().contains("trapped"), "{error:#}");
        }
    }
}

#[test]
fn imports_audit_and_empty_linker_independently_deny_ambient_access() {
    // These imports can never reach a real file: no definitions are linked.
    // We neither read nor reference the user's actual HOME or SSH keys.
    let engine = Engine::default();
    for name in [
        "wasi:filesystem/preopens@0.2.0",
        "filesystem-read",
        "environment-read",
        "network-http",
        "process-exec",
        "shell-exec",
    ] {
        let wat = format!("(component (import \"{name}\" (func)))");
        let component = Component::new(&engine, wat.as_bytes()).unwrap();
        assert_eq!(component.component_type().imports(&engine).len(), 1);
        let mut store = Store::new(&engine, ());
        // Test the actual linker without depending on our explicit import audit.
        assert!(
            Linker::<()>::new(&engine)
                .instantiate(&mut store, &component)
                .is_err()
        );
        let request = request("restricted-plugin", &["staged_content.read"], "private");
        let error = evaluate(wat.as_bytes(), &limits(), request).unwrap_err();
        assert!(
            error
                .to_string()
                .contains("component imports are forbidden"),
            "{error:#}"
        );
    }
}

#[test]
fn real_components_have_no_imports_and_license_supports_warning_and_reject() {
    let engine = Engine::default();
    for name in ["secret-scanner", "license-check", "restricted-plugin"] {
        let component = Component::new(&engine, component(name)).unwrap();
        assert_eq!(component.component_type().imports(&engine).len(), 0);
    }
    let m = manifest("license-check");
    let p = policy(&[
        "staged_content.list",
        "staged_content.read",
        "diagnostic.emit",
    ]);
    let mut wire = wire("private");
    wire.files = vec![WireFile {
        path: "LICENSE".into(),
        content: b"demo license".to_vec(),
    }];
    let request = request_from_transport(&m, &p, wire).unwrap();
    let result = evaluate(&component("license-check"), &limits(), request).unwrap();
    assert!(matches!(result.decision, Decision::Pass));
    assert!(matches!(result.diagnostics[0].severity, Severity::Warning));
    assert_eq!(
        emit_result(&m, &result, &m.requested_capabilities, &limits()).unwrap(),
        0
    );
    let request = request_from_transport(&m, &p, self::wire("private")).unwrap();
    let result = evaluate(&component("license-check"), &limits(), request).unwrap();
    assert!(matches!(result.decision, Decision::Reject));
}
