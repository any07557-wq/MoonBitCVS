# Known Limitations

## Priority scope risk: original vision is not complete

"Eight phases complete" means verification and delivery within the current
converged prototype scope, not the entire original feature vision. Read-only diff
now supports working/index/HEAD comparisons; minimal branch listing/creation and
conservative switching to existing local branches are implemented. Branch
delete/rename, force/automatic recovery, merge, general checkout and Git protocol remain unimplemented.
Switch requires clean tracked/index state and locally present target objects;
it is not arbitrary revision checkout. See [the safety contract](../BRANCH_SWITCH.md).
Passing tests for implemented paths do not validate these missing features.

## Priority deployment risk: no client/server OS privilege boundary

The remote is only a local filesystem/stdio prototype, with no authentication,
ACL, TLS or server OS identity separation. The independent receive process
validates requests through its entry but cannot stop same-account writes to
server objects, Refs, configuration or runtime files. Mode-0700 quarantine,
cleared child environments, CAS and Wasm guest capability isolation do not
provide the missing native client/server privilege separation. Existing bypass
tests do not prove resistance to direct server-file modification.

## Priority performance risk: P7-001 remains open

The historical 10000-object / 498-file snapshot benchmark measured a cached
Tree-read median of 2165.92 ms (~2.17 s), slower than its first uncached read
at 1856.86 ms (~1.86 s). All three trials avoided additional transfers on repeat
reads; that is not evidence of faster reads. These are complete CLI-process
timings. The new instruction/logical-IO profile confirms 499 reads of the same
Tree and repeated decode/hash work, not sampled CPU-time attribution of all latency.
Round 2 reduces request-local duplicate validation: paired cached reads fall
from 2093.86 to 961.39 ms and Tree reads from 499 to 1, with 998 promise reads
unchanged. The index is bounded and discarded per call; fallback keeps full
verification. The historical formal benchmark is unchanged and the remaining
near-one-second cost is not closed. See [round-2 evidence](ROUND2_VALIDATION.md).

## Priority reliability risk: index updates and crash recovery

The historical concurrent-add loss was reproduced and repaired by a transaction
lock before reading the index. Current cooperating writers are serialized;
old/noncooperating writers are not covered. Critical publication parent directories
are synced, with PublicationUncertain after a post-rename sync failure.
There is still no general promotion/recovery journal, automatic replay or GC;
switch has a bounded intent/phase record and backups only. Process death can
leave exclusive index/Ref locks, temporaries or quarantine. Lease-aware
recover --check is read-only; do not blindly delete files or treat its report as
full fsck or proof of power-loss durability. See [RECOVERY.md](RECOVERY.md).

## Priority security limits: memory, authenticity and authorized disclosure

Wasm guest budgets do not cover total Host/JIT memory or process RSS; no OS-level
aggregate memory quota exists. A component digest and name/version pin binds
approved bytes, not author identity, publisher authenticity or benign behavior;
plugin signatures and their verification are not implemented. A malicious plugin
granted staged_content.read and diagnostic.emit can echo authorized content in
bounded diagnostics. Output limits and escaping are not confidentiality controls,
and the Host does not generically redact sensitive content. Redaction tests for
the supplied Scanner do not establish redaction by arbitrary malicious plugins.

## Priority receive scale risk: target closure and full-history policy work

Only single-Ref linear fast-forward/new-branch receive is supported. The target's
complete reachable closure is capped at 4096 unique graph objects and 128 Commits,
including server-existing ancestors, not just the new upload. This is not a
global object-count cap across the repository. Even a single new Commit can
cross a closure limit; splitting uploads does not avoid that limit.
Every reachable full snapshot is rescanned with current required policies, with
no approval-result reuse. Shared objects are not an exemption from policy work.
History length, snapshot size and policy count increase validation work; no
receive scaling benchmark or latency guarantee is claimed. Other byte/time
budgets still apply below the count ceilings. The local 10000-object benchmark
does not establish support for receiving a graph of that size.

## Existing prototype limitations

- Local commits and remote receive independently enforce real required Wasm policies. Configuration/runtime installation remain trusted administration; production privilege separation is not implemented.
- Lazy fetching/typed promises and receive publication are implemented for filesystem repositories. HTTP/TLS/authentication are not implemented.
- Secret Scanner patterns are demonstration markers, not enterprise DLP rules.
- Hello Policy is intentionally minimal; Secret Scanner and License Checker are real staged-content policies. Adversarial and Restricted components are demonstrations, not production policies. License checks are demo conventions, not legal compliance analysis.
- The suite covers fuel/epoch interruption (including initialization), memory growth and multi-memory denial, Trap, malformed canonical ABI, forbidden imports and output/log flooding. There are no Host callbacks to exercise for callback abuse.
- Repository policy configuration is trusted local authority, but plugin manifests are untrusted declarations. Module digests bind bytes, not author identity; manifests/distribution are not signed.
- Component digest reproducibility depends on the pinned MoonBit and component tool versions.
- The VCS adapter supplies staged bytes over stdin. The separate legacy Host --file mode still reads fixture files and is not used by commits.
- Plugins execute inside a separate native Host child process under Wasmtime. The child has no OS resource sandbox; Wasmtime budgets do not account for every Host/JIT allocation.
- Epoch interruption covers instantiation and execution, not compilation, and is not hard real time. The Core adds a child timeout with a 15-second startup allowance and hard cancellation. No separate JIT RSS/cgroup quota is implemented.
- Only one guest linear memory is allowed so per-memory bounds cannot be multiplied. Returned strings/lists can allocate up to that memory bound before the smaller output cap is checked. max_log_bytes bounds diagnostic UTF-8 payload and child stderr; serialized result bytes have a separate limit.
- Granted diagnostic.emit permits an untrusted plugin to return text, including any candidate bytes it was authorized to read. Redaction is tested for the supplied scanners, not guaranteed for arbitrary malicious policy code.
- Schema 1 configuration remains readable with legacy global-grant inheritance. Migrate to schema 2 per-plugin grants for least privilege; see PHASE4_VALIDATION.md.
- Secret rules are literal/MVP checks, not comprehensive secret detection. Custom rules are additive literals, not regex. The unchanged WIT has no line-number field, so diagnostic line is currently null.
- Repository policy paths are absolute. Moving/upgrading the runtime requires deliberate configuration/pin updates. Policies are not signed; a trusted owner can intentionally empty the local commit policy list. The receive entry separately requires a nonempty server policy list.
- No HTTP transport, Git protocol compatibility, merge/rebase, authentication, or browser UI exists.

## Phase-2 filesystem scope

- Tested on Linux x86_64/WSL2 with the native backend. macOS and Windows paths/rename behavior have not been verified; path handling currently assumes `/` and a POSIX repository root.
- Filenames must be valid Unicode/UTF-8. No NFC/NFD normalization or case folding is performed. Non-UTF-8 names, executable bits, file permissions, ownership, timestamps, hard-link identity, special files and empty directory tracking are unsupported.
- `add` accepts relative files/directories and `.`. Repeated separators and `.` components normalize away. Absolute paths, any `..` component, backslash, NUL and root `.moonvcs` paths are rejected even if some would resolve inside the root.
- Symlink files and symlink ancestors are rejected, including links whose targets remain inside the repository. `status` fails explicitly if traversal encounters one. No ignore-file mechanism exists.
- `.moonvcs` metadata and the repository owner are trusted. Component checks and realpath containment handle static paths; they do not provide an `openat`/`O_NOFOLLOW` defense against a hostile process swapping paths between check and read. Do not claim race-proof filesystem confinement.
- Files, encodings and staged snapshots are held in memory. The format caps lengths/counts at 2,147,483,647, but practical memory limits are much smaller. No streaming or repository quota is implemented.
- Local/remote/lazy adapters cap encoded objects at 32 MiB. Clone checkout caps 100,000 entries, depth 128, 4,096-byte UTF-8 paths and 256 MiB file data. Large-file streaming remains future work.

## Local state and concurrency

- Branch refs have lock-file/CAS protection against cooperating writers. Existing locks are preserved. Ordinary failure and cancellation clean owned locks; process death can leave a stale lock requiring inspection/manual recovery.
- Current cooperating add writers hold staging-transaction.lock across the complete index read/modify/write, with a 30-second wait bound; old/noncooperating writers are outside that protocol. The working directory is not a multi-file atomic snapshot.
- Critical object/metadata/Ref parent directories are synced after rename. A crash-recovery journal, automatic replay and real power-loss durability tests remain unimplemented; this is not one durable transaction over the whole repository lifecycle.
- Policy rejection can leave unreferenced Blobs/Trees; failed ref publication can leave an unreferenced Commit. There is no garbage collection, reflog, rollback or general checkout command. Clone materializes pinned HEAD; switch only selects existing local branches under its strict clean-state/collision checks.
- `ObjectStore.verify` validates one local object's digest and canonical encoding, not its entire reachable DAG. Typed promises validate the immediate imported edge; full remote graph completeness/retention is not guaranteed.
- `log` follows only the first parent. The model serializes multiple parents, but CLI merge, detached HEAD, general checkout, rebase and cherry-pick are not implemented.
- Switch is a multi-file operation, not an atomic worktree/index/HEAD transaction. New/changed files use 0600, new directories 0700; modes/empty directories/renames are not tracked. File-directory transitions are rejected, as are all dirty tracked/index states and untracked collisions. Before-files remain in private transaction/history directories even after success; no backup GC, automatic continue/abort or general replay exists. Pending blocks ordinary operations; read-only recovery reports identity/phase and metadata observations, not full snapshot integrity. Editors/old binaries and hostile same-account path races are not serialized or fully confined.
- Switch rejects non-root empty Trees in either snapshot instead of silently losing explicit directory structure; an empty root snapshot remains supported. Recovery history summaries have per-manifest/entry bounds but no separate global byte/time quota; checking many large retained manifests can be expensive. Backup retention and inspection cost remain future work.
- `diff` is a bounded, escaped inspection view, not an apply protocol or globally atomic filesystem snapshot. Pure untracked files, rename detection, modes and empty directories are not represented. It reads verified local objects only, never fetches/repairs promises and does not authenticate remote provenance. Missing objects and budget overruns fail explicitly. Text diff intentionally displays requested content, without Secret redaction. See [diff contract](DIFF.md).
- Policy CLI outcomes retain 0/2/3, storage failures use 4–10, RefConflict is 11, receive Reject/policy-error/invalid-candidate use 12/13/14, StagingBusy is 15, PublicationUncertain is 16 and SwitchIncomplete is 18. Preflight/other failures retain exit 1. A general structured CLI protocol is future work.

## Phase-5 partial clones

- The operator-selected filesystem Ref is the trust root; hashes do not authenticate the original remote Ref. Remote policy executables/configuration are not copied. Partial-clone metadata is local trusted authority.
- clone requires a nonexistent destination and an existing parent. Empty/unborn remote branches are not supported. HEAD/Ref are re-read to detect observed races; later Ref changes do not update the pinned clone or tracking snapshot.
- One repository-wide advisory lock serializes lazy gets/fetches. This favors duplicate-fetch suppression over parallel throughput; Linux native is verified. No batching, compression, alternate promisor fallback or cache eviction exists.
- Unknown hashes are not fetched even if physically present on the remote. Discover authority by traversing imported object edges. Remote deletion remains a broken promise, not automatic Unknown state or corruption.
- Object cache is append-only under normal operation. A corrupt local hit is not automatically healed. Manually removing provenance/source objects or partial metadata can invalidate promises; do not prune this cache without a future promise-aware GC layer.
- Ordinary clone errors/cancellation clean owned temporary state; process death may leave orphan temporaries. File sync and atomic rename do not imply directory-fsync/power-loss guarantees. Transfer counters are exact for completed normal runs, not transactionally crash-exact with object/edge publication.
- Metrics count actual canonical object bytes read from source files, excluding Ref/HEAD metadata, stat calls, local policy installation and hypothetical network compression. See [LAZY_STORAGE.md](LAZY_STORAGE.md).

## Phase-6 receive prototype

- The wire entry rejects client policy/configuration fields and independently applies server-owned on-receive policies. The demo runs client/server under one OS account; that account can still directly edit server files. This is not a production security boundary without a separately privileged receiver and restricted filesystem access.
- No network listener, authentication, authorization/branch ACLs, TLS, signed policy administration or aggregate request/rate/disk/RSS quota exists.
- Receive supports one refs/heads update, complete server repositories, linear history, fast-forward/new branches. Merge/force/delete/no-op Ref updates and multi-Ref transactions are rejected or unsupported. Server working tree/index are not checked out by receive.
- Every target-reachable Commit is revalidated using its complete snapshot under current server policy. This is intentionally conservative and can reject previously accepted history after a policy upgrade; no approval cache or grandfathering exists. It does not retroactively remove already published refs.
- A 16 MiB bundle, 4,096 graph objects, 128 Commits and other documented graph/snapshot/time bounds limit this MVP. Standard push/bundle exports full reachable closure and may demand-fetch client history; there is no differential transport negotiation yet.
- Quarantine cleanup is tested for success/rejection/cancellation. Process death or cleanup I/O failure may leave an owned private quarantine requiring inspection. It is never automatically trusted or published.
- Multi-object promotion is not a journalled transaction. After approval an I/O failure or separate local-writer CAS conflict can leave approved unreachable objects. Atomic Ref rename is the commit point; there is no complete power-loss or exactly-once delivery guarantee.
- Administrative policy installation shares the receive publication lock. Manual concurrent policy edits outside that API are unsupported. Lost acknowledgement requires Ref inspection before retry, not blind overwrite.
- See [REMOTE_RECEIVE.md](REMOTE_RECEIVE.md) for authority, limits, precise publication and retry semantics.

## Phase-7 audit and performance scope

- Durable-evidence selection verifies regular-file bytes and rejects symbolic links, but does not yet specially reject ordinary hard-linked inputs. Tar may encode such inputs as hardlink members that the reproduction extractor rejects. Current delivery inputs are checked independently before freezing; this is not general hardlink support or a completed hardlink hardening fix. See [delivery contract](FINAL_DELIVERY.md).
- CLI text output is a JSON-style escaped inspection view, not a lossless raw byte stream. Canonical objects and checkout bytes are unchanged. C0/ANSI escaping does not prove defense against Unicode bidi/confusable presentation.
- Runtime executable installation is atomic per file. Build/config/component installation is not one atomic runtime-version transaction; concurrent deliberate upgrades can fail pins closed and require retry.
- Wide Trees still incur per-promise/provenance checks on cache hits. Repeated source hashing/decoding within one get now uses a bounded typed-edge index; above its budget the full original check remains. Zero transfers does not imply constant-time reads. The historical two-snapshot 1000-object pilot took 18.71 s to clone and 2.23 s for a cached wide-Tree read. See [BENCHMARKS.md](BENCHMARKS.md) and the separate [new comparison](ROUND2_VALIDATION.md).
- Benchmarks are local filesystem, warmed OS cache, native Core release and installed Rust Host dev/debug. Three samples are not p99/SLA evidence, an industrial scalability result or a fair cross-VCS comparison. No Git comparison was performed.
- In the formal 10000-object/498-file snapshot benchmark, a cached Tree read took 2165.92 ms versus 1856.86 ms for its miss (medians). Zero transfer is not a speed guarantee; existing-promise checks remain costly. This storage scale does not extend the receive graph limit of 4096 objects.
- Historical source-clean rebuild reuses installed tools/registries; the first independent OCI-rootfs run passed 134 tests. The final local-archive installer now passes a separate 149-test rootfs run and four demos without host tools/registries. An actual registry 401 failure is preserved; bounded renewal and 3 tests were added before clean retry. Shared host kernel/network, upstream retention, independent backup/hosting, CI, physical blank-OS, cross-platform and full offline installation remain unresolved; no public mirror was created. See [installation evidence](FRESH_INSTALL_VALIDATION.md).
- No CVE/advisory database scan, long-running fuzzing campaign, power-loss fault injection, formal sandbox proof or cross-platform verification was performed. See [security audit](PHASE7_SECURITY_AUDIT.md) and [fix record](PHASE7_FIXES.md).
- GCC 12.2 in the installation rootfs reports implicit-declaration warnings for posix_spawn_*_np in the pinned moonbitlang/async C dependency. The dependency cache was not patched. MoonBit --deny-warn does not make this a zero-warning C build; dependency portability remains a follow-up.
