# Phase 7 — Security and integrity audit

Date: 2026-10-17, Linux x86_64/WSL2. This is a scoped source review and executable
regression audit, not a penetration-test certification, formal proof, production
deployment approval or dependency-advisory clearance.

## Trust model reviewed

Trusted: installed Core/receiver, policy configuration administrator, Host/runtime,
build toolchain and local metadata. Untrusted: clients, hook results, plugins AND
manifest declarations, uploaded objects, paths and Commit metadata. Requested
permissions do not grant authority. Same-OS-account filesystem access remains
outside the enforced boundary; a directory shared with a hostile writer is not
a trusted server.

## Findings and fixes

| ID | Severity/scope | Reproduced behavior | Disposition |
|---|---|---|---|
| S7-001 | Medium, display security | add/status/log/show rendered untrusted C0/ANSI controls directly | fixed: JSON-style escaping of displayed paths, author/message and text Blob data; canonical stored bytes unchanged |
| S7-002 | Medium, reproducibility | rebuilding while a CLI was running failed with Linux ETXTBSY during direct executable copy | fixed: unique same-directory temporary plus atomic rename for native CLI, bypass fixture and Host installation |
| S7-003 | Medium, API correctness | RemoteObjectStore.verify raised RemoteObjectMissing instead of returning false | fixed: missing/invalid object is false; unavailable provider and cancellation still raise |
| P7-001 | Open, performance | wide Tree cache hits repeatedly load/hash/check source edges, despite zero remote transfers | measured and documented; no new cache-authority mechanism added in this audit |

Each product fix has a regression. The display test first failed with a literal
ESC in add output, then checks paths, local/remote metadata, Tree/Blob display and
unchanged object bytes. The runtime-installer test reproduces ETXTBSY using an
owned copy of the system sleep binary, then proves the old process keeps running
and the newly installed executable works. The verify test first failed with
RemoteObjectMissing; it now also checks that provider failure stays distinct.
The original concurrent-build failure log is retained at
target/reports/phase7-regression-before-fix.log; its runner failure result is
phase7-verify-before-fix.json. No WIT, object encoding or guest digest changed.

## Object integrity review

- SHA-256 hashes the complete typed/versioned/length-framed canonical envelope.
  Four independent vectors and a Python hashlib CLI oracle check actual files.
  Type separation, UTF-8 byte ordering and canonical decode/re-encode are tested.
- Matching hash alone is not accepted as a valid object: malformed encodings,
  unknown types, truncated counts and invalid IDs fail canonical decoding.
- Receive checks complete target closure, expected edge types, missing Trees,
  missing Parents, merge restrictions, extra uploads and published duplicates.
- A synthetic ObjectStore exercises cycle detection without falsely claiming a
  valid SHA-256 fixed-point/cyclic object graph. A real valid-hash deep graph is
  rejected by traversal budgets. Hash assumptions and lack of authenticity are
  explicit in [OBJECT_FORMAT.md](OBJECT_FORMAT.md).
- Cache/object writes use same-directory temp/sync/rename; Ref publication uses
  old-value checking and atomic rename. Concurrent readers/writers are tested.
  This does not establish directory-fsync/power-loss durability or multi-object
  journalled transactions.

## Wasm Host checks

| Check | Evidence |
|---|---|
| No ambient filesystem/network/environment/process access | all five actual Components have zero imports; import audit and independent empty-Linker tests deny mock filesystem, environment, network, process and shell imports |
| No sensitive environment inheritance | real local commit and independent receive launch a trusted test wrapper under simulated AWS/audit sentinel variables; wrapper observes both absent, then execs the actual Wasmtime Host |
| Manifest cannot self-grant | requested ∩ per-plugin grants ∩ repository ceiling ∩ available; excess requests and unsupported capabilities fail closed |
| Component substitution | name/version/ABI/hook/digest and actual bytes verified against trusted pins |
| Infinite evaluation/initializer | fuel plus independent epoch interruption; Core child startup/deadline and hard cancellation |
| Excess memory | single-memory limit, Store limiter denial remembered, table/instance bounds |
| Excess output/log | guest result/diagnostic/serialized output limits plus live bounded child pipes |
| Trap/Panic/malformed result | real MoonBit Trap, resource failures and malformed canonical result produce controlled errors, never approval |

No test reads real HOME, SSH keys or credentials. Filesystem isolation tests use
only owned temporary mock resources. The environment test proves native child
environment filtering, not an OS sandbox for the trusted Host executable.

## Receive-side checks

Server-required schema-2 policies are separate trusted authority. The wire has
no client PolicyResult/configuration/grant field. A standalone unchecked-object
client is rejected by actual server Wasm execution. Complete reachable linear
history is rescanned parent-first with full snapshots, catching an intermediate
secret removed at the tip and objects reused on a new branch. Policy revision
and old Ref are rechecked under the publication lock; two tasks/processes cannot
silently overwrite. Runtime errors, timeout, config change and cancellation are
fail closed. Quarantine is private mode 0700 and cleaned on ordinary outcomes.

An independent deterministic corpus contains 167 malformed/truncated/mutated
protocol cases, plus targeted hash/type/graph/path/secret inputs. Every rejected
case checks unchanged server policy, absent published Ref/formal objects and
empty quarantine. This is bounded regression coverage, not exhaustive fuzzing.

## Residual risk / not verified

- High deployment risk: no authentication, ACL/TLS, privilege-separated receiver,
  branch ownership or hostile same-account filesystem isolation. Do not expose
  this prototype as a secure multi-tenant service.
- Host/JIT total RSS, disk/rate/concurrent-request quotas, signed provenance,
  side channels and race-proof openat/O_NOFOLLOW confinement are absent.
- Trusted administrator changes outside the locking API are unsupported.
  Process death can leave quarantine/stale locks; approved unreachable objects
  can remain after promotion failure. Lost acknowledgements are ambiguous.
- Only complete server stores and single-Ref linear fast-forward/new-branch
  receive are supported. No force, merge, deletion or atomic multi-Ref protocol.
- Scanner patterns are MVP markers, not comprehensive DLP. Authorized malicious
  diagnostics can disclose authorized input. JSON-style C0 escaping is not a
  proof against Unicode bidi/confusable UI attacks; non-C0 terminal-control
  interpretation was not independently verified.
- No dependency advisory/CVE database scan, long-running fuzz campaign, formal
  verification, fault-injected power-loss test, Windows/macOS validation or blank
  OS bootstrap was performed. Rust pins alone are not a no-vulnerability claim.

See [SECURITY.md](SECURITY.md), [THREAT_MODEL.md](THREAT_MODEL.md),
[receive contract](REMOTE_RECEIVE.md) and [known limitations](KNOWN_LIMITATIONS.md).
