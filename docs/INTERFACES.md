# MoonVCS Interfaces

## Policy Component ABI v1

The authoritative contract is [`wit/policy.wit`](../wit/policy.wit), package `moonvcs:policy@0.1.0`, world `policy-plugin`.

The component exports one function:

```wit
evaluate: func(request: policy-request) -> policy-result;
```

`policy-request` carries the hook, ABI/policy version, commit message, optional future object IDs, staged file paths and bytes, and the exact granted capability names. No host callbacks are imported in phase 1.

`policy-result` contains:

- `pass`: the checked candidate satisfies this policy.
- `reject`: diagnostics explain a deterministic policy violation.
- `error(string)`: the plugin could not establish a policy result; required policies fail closed.

Diagnostics contain a stable rule code, severity, redacted message, and optional path. They must not contain matched credential values.

## Plugin manifest

Each plugin manifest, including `plugins/hello-policy/plugin.toml`, `plugins/secret-scanner/plugin.toml`, and the test-only `plugins/adversarial-fixture/plugin.toml`, defines:

- identity and semantic version;
- ABI version;
- supported lifecycle hooks;
- requested capability names;
- exact SHA-256 digest of the Component binary.

The manifest does not grant permissions. The Host requires every requested capability to also appear in repository grants and in the Host-supported capability set.

## Repository policy

`examples/repository-policy.toml` supplies granted capabilities and budgets:

- fuel;
- epoch timeout in milliseconds;
- maximum component linear memory;
- maximum aggregate staged input;
- maximum diagnostic output.

The `examples/adversarial-*.toml` variants isolate specific resource budgets for automated security tests. The adversarial component selects a fixture only from exact `fixture:*` commit-message values and fails closed for unknown values.

## Host CLI

```text
moonvcs-policy-host [--component PATH] [--manifest PATH]
  [--policy PATH] [--hook on-commit|on-receive]
  [--message TEXT] --file REPOSITORY_RELATIVE_PATH ...
```

Exit codes are stable for the phase-1 demo:

- `0`: Pass or Warning (existing Pass decision plus Warning diagnostics)
- `2`: Reject
- `3`: Host or plugin error, including denied capability, digest mismatch, trap, timeout, or invalid input

Standard output is one JSON object. Secret material is never intentionally included.

## Native VCS CLI (phases 2–6)

```text
moonvcs init
moonvcs clone <filesystem-remote-repository> <new-directory>
moonvcs add <path>...
moonvcs status
moonvcs commit -m <message>
moonvcs log [--max-count N] [--offline]
moonvcs show <object-id|HEAD> [--offline]
moonvcs storage-state <object-id>
moonvcs storage-stats
moonvcs receive-init
moonvcs receive-policy-install <trusted-local-policy-json>
moonvcs bundle <new-bundle-file> <ref> <old-id|none> [target-id|HEAD]
moonvcs receive <bundle-file|--stdin>
moonvcs push <filesystem-server-repository> <ref> <old-id|none>
```

`add` paths are current-directory-relative; internal index/candidate paths are
repository-root-relative. The index is a complete snapshot. Re-adding a directory
also stages tracked deletions below it. The default branch is `main`.
`MOONVCS_AUTHOR` overrides the default author and timestamps use Unix milliseconds.
Successful commands exit 0; raised validation/IO errors exit nonzero.
Display escapes control characters with JSON-style text escaping, including
paths, author/message and text Blob show output. This is not a raw export ABI;
stored bytes and object identities are unchanged.

## Core contracts

The MoonBit open async `ObjectStore` trait exposes `put`, `get`, `has`, and
`verify` using objects and ObjectIds only. Memory and local filesystem
implementations exist. Package-private `Repository::update_ref(name, expected, target)` implements
local exclusive-lock/CAS publication of verified Commit targets.

`CommitCandidate` and the open async `PolicyValidator` trait are implemented.
Both commit APIs execute the repository's required Wasm policies before any
additional validator. Mock Pass cannot bypass the gate. The engine accepts a
candidate and PolicyContext and returns Accept, Warning(diagnostics), Reject(diagnostics), or
EngineError. Filesystem remote/lazy stores and independent receive-side validation are implemented. See the exact
[policy and storage contract](POLICY_ENGINE.md) and
[serialization specification](OBJECT_FORMAT.md).

## Phase-4 compatibility

WIT v1 is unchanged. Host JSON adds `status: "warning"` with exit 0. Configuration
schema 2 requires `required[].granted_capabilities`, intersected with the global
ceiling before Host dispatch, and supports `limits.max_log_bytes`. Schema 1 has
explicit backwards-compatible grant/log defaults; see the [migration report](PHASE4_VALIDATION.md).
Four supported capabilities and exact request filtering are specified in the
[threat model](THREAT_MODEL.md). Manifest requests never grant authority.

## Lazy storage (phase 5)

ObjectStore is unchanged. LocalObjectStore, read-only RemoteObjectStore and
LazyObjectStore share canonical typed encoding/SHA-256. Lazy has/verify are
local-only; state returns Local, PromisedRemote or Unknown. Only get may fetch,
and only for validated promises. Repository::log(max_count~) stops without
prefetching the next parent. Offline flags and MOONVCS_OFFLINE=1 forbid fetches.
See [LAZY_STORAGE.md](LAZY_STORAGE.md) for metadata, metrics and storage exit codes.

## Remote receive (phase 6)

ReceiveRequest contains ref_name, expected_old, target and an array of
ReceivedObject { id, encoded }. ReceiveReport contains ref_name, target,
checked_commits, promoted_objects and policy_revision. Neither request type nor
binary protocol v1 carries client policy results, server grants or executable
paths. The 16 MiB envelope is separate from the unchanged canonical object format.

receive-init and receive-policy-install are trusted administrative operations,
not client wire commands. The receiver uses its own nonempty schema-2
.moonvcs/receive-policies.json and on-receive hook. validate_policies gains an
optional hook argument defaulting to on-commit; WIT v1 and existing callers are
unchanged. Exit codes 11/12/13/14 distinguish Ref conflict, policy Reject,
policy/configuration Error and invalid bundle/graph. See
[REMOTE_RECEIVE.md](REMOTE_RECEIVE.md) for exact framing, limits, CAS and retries.
