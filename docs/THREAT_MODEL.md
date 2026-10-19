# Phase 4 threat model

Scope: local on_commit validation, verified on Linux on 2026-10-17.
Phase 6 adds independent server validation using the same plugin sandbox;
the additional authority/transaction boundary is specified in
[REMOTE_RECEIVE.md](REMOTE_RECEIVE.md).

## Assets and authority

Protect unpublished candidate data, repository/object/ref integrity, the user's
unrelated files, and availability within configured execution budgets.

Trusted: the Policy Configuration Authority, installed Plugin Host and Wasmtime,
and MoonBit Core validation/publication logic. The build toolchain and generated
canonical ABI glue are part of the supply chain.

Untrusted: plugin code AND manifest declarations, repository filenames/content,
commit metadata, malformed component bytes, returned diagnostics, and
remote-client input. A manifest is not a grant or a provenance signature.

The trusted local owner may edit .moonvcs/policies.json, including removing a
required policy. This prototype cannot enforce a policy against that owner.
Remote receive enforcement is an independently executed logical validation
boundary, not an OS privilege boundary. Its trusted administrator controls
separate receive policy pins; no client hook result or versioned file authorizes
publication through the receive entry. The remote is a local filesystem/stdio
prototype without authentication, ACL, TLS or server OS identity separation.
A client sharing the server OS account can directly edit server objects, Refs,
configuration or runtime files, outside that entry. The trusted-filesystem
assumption then fails; a separate process, cleared environment, mode-0700
quarantine and CAS do not protect against that client. Wasm guest isolation
does not provide native client/server privilege separation.

## Data boundary

    verified Stage snapshot
      -> MoonBit candidate + trusted per-plugin configuration
      -> bounded stdin to installed Host
      -> pin/manifest/digest checks
      -> capability intersection and request filtering
      -> import-free Wasm Component with bounded Store
      -> bounded, validated result
      -> MoonBit required-policy aggregate
      -> Commit write and locked Ref CAS

The Host is trusted and necessarily receives the candidate on stdin. The
untrusted guest receives only its filtered request; this is not a sandbox for
the Host executable itself. There are no guest filesystem or resource handles.

Effective capabilities are requested ∩ per-plugin grants ∩ repository ceiling
∩ Host available. Every requested MVP capability is mandatory: a request outside
that intersection yields an actual Host CapabilityDenied error before execution.
Unused approved capabilities are not passed to the plugin.

| Capability | Guest-visible effect |
|---|---|
| staged_content.list | Candidate-relative filenames, empty content buffers |
| staged_content.read | Candidate filenames and exact staged bytes, not filesystem access |
| commit_metadata.read | Message and optional parent/tree IDs |
| diagnostic.emit | May return bounded diagnostics; no stdout/stderr callback |

Read necessarily includes each returned file's name. With neither list nor read,
files is empty. Without metadata permission, message is empty and IDs are None.
Only Secret Scanner receives the Host-reserved custom-rule virtual file.
Hook/version/granted-capability names are protocol framing, not secret metadata.

## Attacks and controls

| Attack | Control and executable evidence |
|---|---|
| Manifest self-grants data access | CapabilityManager intersection; excess-request tests |
| A grant to one plugin leaks to another | schema 2 per-plugin grants plus global ceiling; native integration test |
| Component or identity substitution | trusted name/version/digest pin, strict manifest ABI/hooks, SHA-256 of actual bytes |
| Directory traversal/metadata spoofing | canonical relative path checks, duplicates/reserved-path rejection |
| Read unrelated HOME or SSH material | zero component imports, empty Linker, no WASI context/preopens; mock-only tests |
| Legacy --file symlink escape | static ancestor symlink and canonical containment checks; temporary fake HOME test |
| Infinite evaluation or initializer | independent fuel and epoch timer, active before instantiation |
| Linear-memory/table multiplication | one memory, explicit byte ceiling; 16 instances, 8 tables, 10,000 elements per table |
| Allocation denial swallowed by guest | remembered memory denial makes evaluation Error even if guest returns Pass |
| Oversized input/module/config | 1 MiB logical input ceiling, 16 MiB transport/module read cap, 64 KiB TOML cap |
| Output/log flooding | logical diagnostic/error-string and serialized JSON caps, 256 diagnostics, live bounded stdout/stderr reads |
| Malformed canonical return | invalid discriminant fixture traps in Wasmtime lifting, then fails closed at commit |
| Fake terminal lines/escapes | MoonBit renders diagnostic values with JSON string escaping |
| Partial/rejected publication | no Commit write until required validation passes; HEAD/index/worktree preserved in tests |
| Extra Mock validator bypass | both public commit paths run required policies before additional validators |

repository.secrets.read is NOT a Host API. Restricted Plugin's successful
execution proves staged-content access and metadata filtering. A separate test
adds that request to its untrusted declaration and gets CapabilityDenied from
the real resolver. It does not claim a nonexistent WIT callback returned a
CapabilityDenied variant. Forbidden-import tests independently show the empty
Linker cannot resolve ordinary ambient imports.

## Availability limits and residual risks

Fuel counts instrumented work, not elapsed time. Epoch interruption uses a
separate wall-clock timer and is checked at Wasmtime safepoints; scheduling and
runtime work mean it is not a hard real-time deadline. The timer covers
initialization, canonical lowering/call/lifting/post-return, not JIT compilation.
The MoonBit child-process timeout covers startup/compilation too, with a
15-second startup allowance and hard cancellation. Process output is drained
concurrently under live bounds; it is not buffered without limit until exit.

The Store cap covers guest linear memory, not total RSS, JIT, every host-side
allocation or all runtime GC state. Module size is bounded but compilation has
no separate RSS/cgroup budget. Returned data can allocate up to the linear
memory bound before the smaller output check runs. Plugins have no WASI log
channel; max_log_bytes bounds diagnostic text payload and captured child stderr.
There is no OS sandbox, signed distribution, provenance verification, side-channel
proof, or hostile multi-tenant guarantee. Untrusted diagnostics may contain
authorized candidate content if diagnostic.emit is granted; capability control
cannot make a malicious scanner redact data it is allowed to read and emit.

Local metadata is trusted. Static path checks do not close filesystem TOCTOU
races against another hostile local process. Native candidate construction and
object loading also have memory costs outside plugin budgets. See
[known limitations](KNOWN_LIMITATIONS.md). Do not deploy arbitrary third-party
plugins in production on the strength of this prototype.

## Mechanism references

Implementation was checked against the locally installed, pinned Wasmtime
49.0.3 sources (Config, component types, Store and StoreLimitsBuilder). Official
mechanism documentation: [interrupting execution](https://docs.wasmtime.dev/examples-interrupting-wasm.html),
[Config](https://docs.wasmtime.dev/api/wasmtime/struct.Config.html),
[Store](https://docs.wasmtime.dev/api/wasmtime/struct.Store.html).
Those rolling documentation pages may describe newer versions; the compiled
tests against Cargo.lock are the compatibility evidence for this project.
