# MoonVCS Architecture

Current integrated architecture and diagrams: [root ARCHITECTURE.md](../ARCHITECTURE.md).
This document retains the implementation detail accumulated in phases 1–6.

## Phase-1 goal

Prove that policy domain logic written in MoonBit can compile into a WebAssembly Component, execute in a Wasmtime host with no ambient authority, and return a decision that can block publication of a future commit candidate.

## Implemented path

```text
staged fixture
    │ bytes + repository-relative path
    ▼
trusted Rust host
    ├── verify manifest ABI, hook, and SHA-256 component digest
    ├── requested ∩ repository grant ∩ host support
    ├── enforce input/output, memory, fuel, and epoch limits
    └── instantiate with an empty Component Linker (no WASI)
    │ PolicyRequest
    ▼
MoonBit policy Component
    ├── hello-policy checks the commit message
    ├── secret-scanner checks only supplied candidate bytes
    ├── license-check enforces the demonstration header/LICENSE convention
    └── return Pass / Reject / Error + diagnostics (Warning is Pass + warning)
    │ PolicyResult
    ▼
structured JSON + process exit status
```

The Rust boundary is intentionally narrow. Policy semantics and secret-pattern matching live in MoonBit. Rust supplies the runtime and enforces capabilities and resource budgets.

The same ABI also drives a security-test-only MoonBit component. Its commit-message selector deterministically triggers an infinite loop, retained memory growth, `panic()` Trap, or a 4 KiB diagnostic. This fixture is never a production policy; it exists to test the Host boundary end to end. The Host independently records Store limiter denials so allocator failure cannot hide that the configured memory ceiling caused the failure.

## Trust boundaries

- **Trusted:** Core validation logic, policy configuration authority, manifest loader, Rust Host, Wasmtime runtime.
- **Untrusted:** plugin component AND manifest declarations, commit metadata, candidate repository bytes/paths, remote clients.
- **Not granted to plugins:** filesystem, environment variables, network, shell, user home, SSH keys, clocks, random sources, or WASI APIs.
- **Explicit data capability:** the host copies only selected staged paths and bytes into `PolicyRequest` after permission checks.

## Phase-2 local Core

`vcs/model.mbt` and `vcs/encoding.mbt` define the MoonBit object model, canonical
binary representation and SHA-256 IDs. `vcs/store.mbt` defines an async domain-only
ObjectStore trait plus memory and local disk implementations. The local
`Repository` adapter in `vcs/repository.mbt` owns paths, index and refs; the
object model and store interface do not depend on that layout or a transport.

```text
native MoonBit CLI -> local filesystem/index -> CommitCandidate
                                                 |
                                        Required Policy Engine
                                        -> Wasmtime -> MoonBit Scanner
                                                 |
                                        additional validator
                                                 |
                                        immutable Commit object
                                                 |
                                       locked CAS branch update
```

Candidate files are read from verified staged Blob objects. No Commit object or
ref is published for a rejected candidate. Content-addressed Blobs/Trees may be
written earlier; a failed ref CAS may leave an unreferenced Commit. Ref updates
use exclusive lock creation, expected-old checking, sync and atomic rename.
See [object format](OBJECT_FORMAT.md) and [policy boundary](POLICY_ENGINE.md).

## Storage composition (phase 5)

The verified storage layer now attaches to the existing interface:

```text
MoonBit VCS Core → CommitCandidate → Required Policy Engine → verified Host
       │                                              │
       └→ Local/Remote/Lazy ObjectStore               └→ atomic ref update
```

The required-policy connection is implemented in phase 3. The MoonBit engine
receives a candidate/context and invokes the separate Host with staged bytes over
stdin. Repository configuration pins each plugin's name/version/digest; the Host
checks the pin, manifest and component before running it. The old validator trait
is now an additional gate and cannot replace required validation. The independent
server receiver repeats required validation before every remote Ref publication.

LazyObjectStore checks local verified data first, fetches only promises anchored
in the explicitly selected filesystem Ref or imported verified object edges,
and reports Unknown without contacting any remote. Clone materializes the current
HEAD snapshot only; log discovers missing parents incrementally through the
same ObjectStore API. Imported bytes are checked against canonical encoding,
expected type and SHA-256 before atomic cache installation. Repository advisory
locks coalesce concurrent misses; explicit offline mode never fetches. Remote
policy executables/configuration are not adopted. See [LAZY_STORAGE.md](LAZY_STORAGE.md)
and [measured validation](PHASE5_VALIDATION.md).

Phase 4 filters each plugin request using independently approved grants and a
repository capability ceiling. The Host audits actual imports and retains an
empty Linker. Both execution and initializers have fuel/epoch budgets; live
bounded process pipes prevent an unbounded native stdout/stderr collection.
The engine aggregates diagnostics deterministically and permits Warning, while
Reject/Error stop Commit creation. See [threat model](THREAT_MODEL.md).

## Remote publication (phase 6)

    untrusted binary bundle -> private quarantine -> hash/type/graph validation
      -> complete reachable linear-history snapshots
      -> server-owned pinned on-receive Wasm policies
      -> publication lock + policy/configuration/old-Ref recheck
      -> verified object promotion -> locked CAS atomic Ref rename

The receiver never trusts client policy results or adopts client configuration.
Every reachable Commit is rescanned under the current server policy, including
previously published history. Quarantine is cleaned on ordinary rejection and
cancellation; no unapproved Ref is published. Promotion is not a journalled
multi-object transaction, and process death can leave private orphan data.
This filesystem/stdio prototype requires separate server privileges and an
authenticated/authorized transport for hostile-client deployment; sharing one
OS account is not an authority boundary. See the exact supported scope,
transaction/retry semantics and limits in [REMOTE_RECEIVE.md](REMOTE_RECEIVE.md)
and the [measured tests](PHASE6_VALIDATION.md).

## System verification (phase 7)

scripts/verify.sh composes the existing build/unit/integration/security/demo
entry with independent CLI/codec/environment/quarantine tests and repeat smokes.
Optional source-clean rebuild and object-count benchmarks run serially and
record explicit stage outcomes. Independent Python hashlib fixtures supplement
MoonBit canonical-encoding tests; Python is test orchestration, not VCS or policy
domain implementation. See [validation](PHASE7_VALIDATION.md).

CLI presentation escapes C0/ANSI controls in untrusted names, author/message and
text Blob inspection; storage and policy inputs retain exact bytes. Build scripts
atomically replace individual runtime executables using same-directory temporaries
to support an already-running executable. This is not a multi-file deployment
transaction. No WIT, object encoding or capability boundary changes in phase 7.
