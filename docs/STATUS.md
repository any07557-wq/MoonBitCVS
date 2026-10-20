# MoonVCS Status

Verified implementation CI: run [#3](https://github.com/any07557-wq/MoonBitCVS/actions/runs/39378888384)
on exact commit `b361ed475dc0a6699d7116c405f0a79051a59f9a` passed 245 unique tests
and all three verify stages. Its new ZIP and reports are independently checked
and archived in `evidence/ci/39378888384-attempt-1/`. The later documentation
freeze is verified separately by its exact package-side reproduction report;
see [FINAL_DELIVERY.md](FINAL_DELIVERY.md) and [CI_VALIDATION.md](CI_VALIDATION.md).

Mooncakes `any07557-wq/moonvcs@0.1.0` was published on 2026-10-19
13:19:34 UTC (server 200 / CLI 0). Frozen source commit `d5d8242` passed
the full 237-test verify entry in a source-clean export using installed tools
and dependency caches. On 2026-10-20 a credential-free, empty-registry consumer
downloaded the release, passed native check and 2 external import tests, and ran
the README example. Registry ZIP/cache bytes and all 33 installed files match
the frozen candidate. This is **native core library source only**, not the full
Rust Host, Wasm plugin or precompiled CLI distribution. No GitHub push, new CI
run or new rootfs acceptance was performed. See [release evidence](MOONCAKES_RELEASE.md).

CI configuration: pinned tools + existing full verify.sh entry, 6 original guards
(237 tests in the archived CI entry). The later packaging extension adds 8 guards
(245 total); its local validation is tracked separately in
[PACKAGING_EVIDENCE_VALIDATION.md](PACKAGING_EVIDENCE_VALIDATION.md).
The implementation package was separately unpacked/rebuilt: 245 tests passed,
69 durable evidence members match, and 166 current executable-source/configuration
files match the tested snapshot. This is local installed-tool/cache reuse, not
a new GitHub run or rootfs acceptance; final result documents were written later.
GitHub run #1 on commit `6d96157` succeeded;
the original artifact digest, all three exit-zero stages and 237 unique tests
have been checked and preserved locally. This evidence update does not rerun
tests, push changes or claim a new rootfs acceptance. See [CI.md](CI.md) and
[CI_VALIDATION.md](CI_VALIDATION.md).

Historical host regression: 245 tests on the packaging implementation archive, 2026-10-20.
Final engineering source/document archives use their own package-side reproduction status.
Historical branch/switch closeout regression: 225 tests, 2026-10-18 (Asia/Shanghai).
Branch/switch status: local prototype acceptance passed, not production acceptance.
The 2026-10-19 delivery entry adds 6 archive/reproduction guards (231 total).
Actual unpack/rebuild status is attached to each immutable source archive in
REPRODUCTION.json/REPRODUCTION.md; old 225/149 results are not that verification.
Last isolated installation: 149 tests, before diff; not a new-source install pass.
Historical first isolated installation: 134 tests, preserved unchanged.

Current closeout evidence: [BRANCH_SWITCH_ACCEPTANCE.md](BRANCH_SWITCH_ACCEPTANCE.md).
Earlier branch/switch implementation evidence: [BRANCH_SWITCH_VALIDATION.md](BRANCH_SWITCH_VALIDATION.md).
Earlier diff evidence: [DIFF_VALIDATION.md](DIFF_VALIDATION.md).
Earlier storage/recovery evidence: [ROUND2_VALIDATION.md](ROUND2_VALIDATION.md).
Final-archive installation passed in a new rootfs: tools, 149 tests and four
independent demos. The actual fresh-02 registry 401 is preserved; bounded renewal
and 3 regressions were added before clean fresh-03 preparation. One renewal
occurred; no host tools/registries were mounted. Installation shares the host
kernel/network and is not a physical blank-OS or full-offline guarantee.
[Current installation evidence](FRESH_INSTALL_VALIDATION.md).
Historical first iteration: [ROADMAP_PROGRESS.md](ROADMAP_PROGRESS.md).

## Next iteration and presentation focus

Read-only diff is implemented in MoonBit: index -> working tree, HEAD -> index
and HEAD -> working tree, with text/binary/add/modify/delete support and literal
path filtering. It verifies compared local object bytes/types without fetching,
repairing promises or creating locks; it is not a global filesystem snapshot or
Secret redaction. Its iteration added 8 native and 20 CLI regressions. Minimal
branch and existing-local-branch switch now implement the prior BRANCH_SWITCH.md
contract: complete read-only planning, clean-state/collision checks, a shared
writer lock, no-replace moves, retained before-inode backups, pending gates and
read-only recovery identity/phase/HEAD-index observations. Another 8 native and
38 CLI tests were added, with real failed attempts and fixes retained. Closeout
adds 2 help/manual-recovery regressions (40 CLI total), reruns the full 225-test
entry and binds frozen source/runtime digests. A retained fixture drill preserves
the interrupted original/evidence, rebuilds in a new directory, and reconciles
user bytes without discarding distinct versions. Its first actual failure exposed
the documented invalid `status --offline`; it now uses `moonvcs --offline status`.
Successful switches retain backups in `.moonvcs/switch-history/`; help warns that
disk use grows without automatic cleanup. Force,
automatic rollback/replay and branch delete/rename remain unsupported. Remaining
wide-Tree profiling, external tool-archive backup and general recovery UX are future work.
Same-version delivery uses the package/reproduction workflow documented in
[SUBMISSION.md](SUBMISSION.md), with actual status in the package-side report.
The old 149-test rootfs/source archives do not automatically cover this feature.

Fresh-environment installation passed in an independently downloaded OCI
rootfs without host toolchain/registry mounts: 134 tests and all four real demos.
Failed installation attempts were retained; retries reuse only that installation's
downloaded dependencies and cold project-source copies. This shares the host kernel,
not a physical blank OS or cross-platform guarantee. Wide-Tree instruction/logical-IO
profiling is complete; concurrent staging has been repaired and tested.
Directory sync, quarantine leases and read-only recovery inspection are implemented;
journal replay, automatic cleanup, GC and power-loss validation remain incomplete.
The second iteration passed 146 host tests. The later fixed installer and local
archives now pass a separate 149-test isolated installation, with an independently
rerun 149-test host suite. Compiler/core archives were fetched from
explicit version URLs with unchanged digests, and an operator-local CAS path is
supported; no public long-term mirror was deployed. Process-termination tests must
not be advertised as power-loss durability tests. See [ROADMAP.md](../ROADMAP.md).

The presentation stays with demonstrated MoonBit Core, real Wasm policies,
explicit capabilities, commit/receive gates and verified lazy history. Receive
means the local filesystem/stdio entry, not a production remote service, and
zero repeat transfers do not imply faster cached reads. If a real remote is
opened later, authentication, ACLs, TLS and server OS privilege separation must
be implemented and validated first. No such deployment is added by this update.

## Priority risk: original feature vision remains incomplete

"Eight phases complete" refers only to verification and delivery of the current
converged prototype scope, not completion of the original feature vision.
merge, general checkout and the Git protocol are not implemented. Branch only
lists/creates from current HEAD; switch only selects existing local branches with
clean snapshots and locally present verified objects. It is not force checkout,
arbitrary revision restore or automatic recovery. These gaps remain future work.

## Priority deployment risk: remote is filesystem/stdio only

No authentication, ACL, TLS or server OS identity separation is implemented.
Independent receive execution validates candidates submitted through that entry;
it cannot stop a same-account client directly modifying server objects, Refs,
policy configuration or runtime files. A separate process, empty environment,
mode-0700 quarantine and Ref CAS do not establish a client/server privilege
boundary. The bypass demo is not a hostile same-account deployment test.
Production deployment remains out of scope until these missing controls exist.

## Priority performance risk: P7-001 remains open

The historical 2026-10-17 benchmark measured a 2165.92 ms cached Tree read versus
1856.86 ms for its first uncached read at 10000 objects / 498 files per snapshot
(medians across three trials, complete CLI processes). Repeated reads added zero
transfers, but faster reads are not established. The new instruction/logical-IO
profile observes 499 reads of the same Tree and repeated decode/hash work.
These are not sampled CPU-time percentages. Round 2 implements bounded per-get
source/typed-edge reuse: the paired cached-read median falls from 2093.86 ms to
961.39 ms, Tree reads from 499 to 1, with 998 promise reads unchanged. This is not
a rerun of the formal three-scale benchmark or a general speed guarantee; the
remaining near-one-second cost is still open. No persistent trust cache is added.

## Priority reliability risk: staging updates and crash recovery

The old concurrent-add loss was reproduced and repaired by an advisory transaction
lock spanning the entire index read-modify-write, with cross-process/kill/cancel
regressions. Critical object/metadata/Ref publication now syncs parent directories;
post-rename sync failure returns PublicationUncertain. Process death may still
leave exclusive lock files, temporaries or quarantine. Lease-aware recover --check
is read-only and does not delete or replay. There is no journal, GC, automatic
recovery or verified power-loss durability. See [RECOVERY.md](RECOVERY.md).

## Priority security limits: guest budgets, byte pins and authorized output

Guest linear-memory limits do not bound total Host/JIT memory or process RSS.
Component digest/name/version pins bind approved bytes, not author identity or
publisher authenticity; no plugin signature verification is implemented.
A malicious plugin with staged_content.read and diagnostic.emit can return
authorized content in a size-compliant diagnostic. Host validation does not
provide generic sensitive-content redaction. Scanner-specific redaction tests
do not prove confidentiality against arbitrary malicious plugins. This update
adds no RSS control, publisher authentication or output-confidentiality mechanism.

## Priority receive scale risk: full target closure, no approval reuse

Receive supports one Ref, linear history and fast-forward/new-branch updates,
with at most 4096 unique target-reachable graph objects and 128 Commits,
including server-existing ancestors. These are not just upload limits or a
global repository object-count cap. Every reachable Commit's full snapshot is
rechecked under current policies; no approval-result cache exists. Validation
work grows with history, snapshots and required policies, and other budgets may
reject requests below the count limits. The local 10000-object benchmark is not
a receive benchmark. No limit increase or new receive scale measurement was
performed in this documentation update.

## Phase 8 final delivery

The developer/judge README, architecture/security/roadmap, installation/testing
guides, neutral comparison, claim checklist, three-minute script and four SVG
diagrams now describe the actually implemented scope. Four real demonstrations
run through the unchanged WIT/Core/Host and are included in the unified test
entry. The extended regression passes 122 distinct tests plus separate CLI/demo
smokes; the four final scenarios also pass twice in fresh run directories.
The 40-commit demonstration measures 120 source objects / 12,976 encoded bytes,
3 initial clone objects / 326 bytes and 6 cached objects / 893 bytes after
reading four commits, with no transfer on repeated reads. A real terminal
recording is retained, not a fabricated screenshot.

See [PHASE8_DELIVERY.md](PHASE8_DELIVERY.md), [DEMO.md](../DEMO.md),
[TESTING.md](../TESTING.md) and [CLAIMS.md](CLAIMS.md).
The existing phase-7 benchmark/source-clean results below are historical evidence,
not a newly verified blank-machine installation. Source/evidence packaging is
documented in [SUBMISSION.md](SUBMISSION.md).

## Tested

| Capability | Evidence |
|---|---|
| MoonBit components | 19 Wasm tests pass: 8 Scanner, 3 Hello, 2 adversarial, 4 License, 2 Restricted |
| Wasm Component generation | all five MoonBit components and invalid-return/infinite-start fixtures compile and validate |
| Wasmtime invocation | clean input returns Pass through the real component |
| Minimal Hello Policy | safe message passes, forbidden marker rejects, and empty message returns Error |
| Import inspection | extracted Hello Policy world exports only evaluator and has no imports |
| Commit rejection primitive | simulated token returns Reject and exit code 2 |
| Scanner-specific diagnostic redaction | integration test confirms the fixture token value is absent; not generic malicious-plugin redaction |
| Capability enforcement | missing repository grant is rejected before execution |
| Infinite-loop containment | 20,000-unit fuel budget is exhausted; Host exits 3 |
| Memory containment | growth to 4,849,664 bytes is denied under a 4 MiB Store limit; Host exits 3 |
| Explicit Trap handling | MoonBit panic becomes a Wasm `unreachable` Trap; Host exits 3 |
| Output containment | 4 KiB diagnostic exceeds the 1 KiB policy limit; Host exits 3 |
| Host validation logic | 26 Rust tests pass, including permissions, pins, import audit, actual malformed ABI, initializer interruption and multi-memory limits |
| Component content pin, not author identity | SHA-256 digests checked by Host and build script; no publisher authentication/signature verification |
| MoonBit Core, policies, lazy storage, receive, diff and branch/switch | 86 native tests pass; native check, tests and release build use `--deny-warn` |
| Read-only diff | 20 real CLI tests pass; three views, text/binary, integrity, read-only snapshots and observed concurrent metadata changes |
| Branch/switch | 40 real CLI protection/fault/help/manual-drill tests pass; pending Core gates, preserved before-inodes, SIGKILL/EIO and observed publication state; no automatic recovery |
| Object IDs | four independent SHA-256 vectors, type separation, canonical UTF-8 ordering and serialization round trips |
| Persistent storage | Blob/Tree/Commit loose objects, deduplication and corruption detection |
| Local history | two commits, parent link, newest-first log and CLI `show HEAD` |
| Policy boundary | real Wasm Reject/Trap/fuel/memory failures leave HEAD and index unchanged; no rejected Commit object is written |
| Required-policy enforcement | ordinary commit and commit_with_validator(Mock Pass) both enforce repository policies |
| Scanner rules | simulated API keys/access tokens, private-key headers, password fields, custom literals and multi-file diagnostics |
| Recovery/redaction | working-only repair still rejects; re-stage then succeeds; fixture values absent from CLI diagnostics |
| Ref publication | CAS rejects stale writers; tested ordinary failure/cancellation cleans owned locks; existing locks are preserved; no process-death recovery guarantee |
| Filesystem boundaries | recursive directories, tracked deletion, binary/empty/Unicode files, symlink and traversal rejection |
| CLI | original six commands plus clone/lazy/receive/push tested, including subdirectory paths; formal object files checked by `sha256sum` |
| Multiple real policies | Scanner + License, deterministic diagnostics order, Warning permits commit, Reject/Error preserve state |
| Least privilege | four capabilities; metadata/list/read/diagnostic filtering, per-plugin grants and repository ceiling |
| Independent wall-time containment | high-fuel infinite evaluation and initializer loops are interrupted by epoch |
| Live log/output containment | infinite mock Host stdout/stderr trigger bounded reads and hard cancellation |
| Ambient access denial | import audit plus independently tested empty Linker; temporary mock HOME/SSH symlink test |
| Partial clone | 80 real commits, remote 244 objects / 37,948 bytes; clone only 7 objects / 742 bytes |
| Lazy history | six commits cached using 12 objects / 1,682 bytes total; repeat reads transfer zero |
| Concurrent fetch | 12 async readers and 8 independent CLI processes coalesce duplicate misses |
| Promise boundary | Local / PromisedRemote / Unknown, verified immediate edges, no unknown-ID remote probe |
| Offline and failure semantics | cached reads work after remote removal; offline miss, unavailable remote, deletion and corruption distinguished |
| Server-required policies | actual on-receive Scanner/License execution, version/digest pins and server-only configuration |
| Client bypass | independent unchecked-object program rejected by independent server receiver; no rejected objects promoted |
| Publication safety | private quarantine, graph/type/hash checks, full-history snapshots, final policy recheck and Ref CAS |
| Concurrent publication | two tasks and two server processes: one accept, one conflict; concurrent reader sees complete Ref IDs only |
| Receive failures/recovery | Trap/timeout/memory/config change/cancellation fail closed and clean quarantine; corrected retry succeeds |
| Independent system audit | 9 CLI/security tests, including 167 malformed protocol inputs, external hash oracle, mock environment and quarantine permissions |
| Verification harness | 6 tests prove failure recording, fail-fast smoke, unrequested checks, atomic executable replacement and explicit/local/PATH tool resolution |
| Display safety | C0/ANSI metadata/path/text display escaped without changing canonical stored bytes |
| Source-clean rebuild | complete 122-test regression passes without copied outputs/project dependencies; installed tools/registry caches reused |
| Measured benchmark | 100/1000/10000 objects, 20 snapshots, 3 trials each; actual initial clones 5/50/500 objects and 540/5445/54495 bytes |

## Implemented

- WIT ABI v1 with `on-commit` and `on-receive` hook values.
- MoonBit Hello Policy for minimal message-based Pass, Reject, and Error validation.
- MoonBit Secret Scanner 0.2.0 for credential markers, password assignments and configurable literal rules.
- MoonBit License Checker 0.1.0 and Restricted Plugin 0.1.0 on unchanged WIT v1.
- Untrusted Manifest Loader, CapabilityManager and schema-2 per-plugin grants; schema-1 compatibility.
- Warning aggregation, independent epoch initializer interruption, total single-memory cap and bounded native process pipes.
- SECURITY.md, Threat Model, migration report and executable phase-4 security demo.
- Security-test-only MoonBit adversarial component with four selectable behaviors.
- Manifest and repository capability configuration.
- Requested ∩ granted ∩ supported permission resolution.
- Wasmtime fuel, epoch timeout, Store memory limits, and input/output limits.
- Empty linker instantiation with no WASI imports.
- Structured JSON result and fail-closed exit statuses.
- Reproducible build, test, regeneration, and demo scripts.
- Fail-closed integration assertions for fuel exhaustion, denied memory growth, Trap, and output overflow.
- MoonBit Blob/Tree/Commit/Ref/CommitCandidate and binary object format v1.
- Open async ObjectStore interface and memory/local disk implementations.
- MoonBit LocalObjectStore, read-only filesystem RemoteObjectStore and LazyObjectStore on unchanged object format.
- Pinned promisor Ref metadata, typed per-object provenance, demand-fetched parent discovery and append-only verified caching.
- Atomic partial clone/HEAD checkout, log --max-count, show --offline, storage-state and persistent transfer statistics.
- Advisory-lock fetch coalescing, atomic cache visibility, disconnected demo and measured phase-5 run log/report.
- Persistent full-snapshot index, candidate creation, required Wasm validation and local ref CAS.
- Native `moonvcs init/add/status/commit/log/show` executable.
- Phase-2 example project, format specification, policy contract and validation report.
- MoonBit Policy Engine, bounded stdin Host adapter, pinned repository policies and real commit enforcement.
- Fail-closed CLI policy errors (exit 3), structured Reject output (exit 2), phase-3 integration tests and demo script.
- MoonBit bounded binary receive protocol, stdin/file server entry, independent push receiver process and acceptance receipts.
- Server receive policy authority, on-receive validation of every reachable linear Commit snapshot and policy revision binding.
- Quarantine isolation, verified graph promotion, final Ref/configuration concurrency checks and existing Ref CAS.
- Test-only bypass client, A–D demo, concurrent receive tests and phase-6 report/run log.
- Phase-7 unified verifier, isolated source rebuild, benchmark harness, environment metadata, audit/fix reports and independent regressions.

## Planned

- OS-level Host/JIT RSS quotas, signed plugin distribution and supply-chain verification.
- HTTP/TLS/authentication, batching, compression, eviction and large-file streaming extensions.
- Authenticated/authorized privilege-separated receive deployment and TLS transport.
- Multi-Ref transactions, merge publication, promotion journals and durable receive quotas.
- Wide-Tree promise-verification optimization, blank-machine installer validation and dependency advisory scanning.

## Blocked

None for the implemented functional paths. Local commits and the remote receive entry independently
execute required Wasm policies; partial clones fetch history on demand.
The prototype still lacks production authentication/authorization, secure network
transport and OS privilege separation.
Phase-7 exact run status, benchmark scale and unverified checks are recorded in
[PHASE7_VALIDATION.md](PHASE7_VALIDATION.md), [BENCHMARKS.md](BENCHMARKS.md)
and [PHASE7_SECURITY_AUDIT.md](PHASE7_SECURITY_AUDIT.md).

## Next-stage interface agreement

Core constructs candidates from verified Stage objects and invokes every required
Wasm policy through the adapter in deterministic order. Pass or Warning permits
Commit/Ref publication. Extra validators cannot replace this gate; WIT is
unchanged. See [PHASE4_VALIDATION.md](PHASE4_VALIDATION.md), [THREAT_MODEL.md](THREAT_MODEL.md) and
[POLICY_ENGINE.md](POLICY_ENGINE.md).

The storage contract remains put/get/has/verify with typed IDs and no transport
arguments. Lazy reads require a validated promise; Unknown never probes a remote.
See [PHASE5_VALIDATION.md](PHASE5_VALIDATION.md) and [LAZY_STORAGE.md](LAZY_STORAGE.md).

Remote updates use server-owned schema-2 required policies and the existing
on-receive Hook. Only complete validated graphs and approved full linear history
can reach atomic Ref publication. See [REMOTE_RECEIVE.md](REMOTE_RECEIVE.md)
and [PHASE6_VALIDATION.md](PHASE6_VALIDATION.md).
