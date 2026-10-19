# MoonVCS Decisions

## D001 — Validate the plugin chain before VCS breadth

**Status:** Accepted, verified.

The highest-risk integration was MoonBit → Wasm Component → Wasmtime. Phase 1 implements that chain before object storage, Git compatibility, or UI work.

## D002 — Use a single request/response WIT call

**Status:** Accepted.

The Host copies authorized candidate bytes into one `evaluate` request. This keeps the ABI auditable and avoids exposing filesystem handles or a large callback surface. Streaming resources can be evaluated later if measured input sizes require them.

## D003 — No WASI or ambient capabilities

**Status:** Accepted, verified by component interface inspection.

The Component has exports only. The Host instantiates it with an empty linker, so filesystem, network, environment, shell, and user-home access are unavailable by construction in phase 1.

## D004 — Keep policy semantics in MoonBit

**Status:** Accepted.

Secret detection and decision construction are MoonBit code. Rust is restricted to manifest/config validation, capability enforcement, resource limiting, runtime execution, and transport formatting.

## D005 — Pin a stable toolchain combination

**Status:** Accepted.

The current MoonBit compiler rejected bindings from the older `wit-bindgen 0.45.0` shown in the MoonBit tutorial. `wit-bindgen 0.63.0` generated compatible ownership annotations, with one documented E0044 suppression moved to the generated ABI subpackage. `wasm-tools 1.262.0` matches the generator family. Wasmtime `49.0.3` was selected because `50.0.0` was only a release candidate.

## D006 — Verify component identity before execution

**Status:** Accepted, verified.

The Host hashes component bytes with SHA-256 and requires an exact manifest digest before compilation or instantiation. The build script detects artifact drift.

## D007 — Fail closed

**Status:** Accepted.

Missing capabilities, ABI mismatch, digest mismatch, invalid path, oversized data, runtime trap, fuel exhaustion, timeout, output overflow, and plugin `error` all produce Host error status rather than Pass.

## D008 — Test sandbox limits with a MoonBit adversarial component

**Status:** Accepted, verified.

A test-only component uses the production WIT boundary to trigger infinite work, retained memory growth, an explicit Trap, and excessive output. Host integration tests require exit code 3 and a distinct cause for each case. Memory-limit denial is recorded at the Wasmtime `ResourceLimiter` boundary because a guest allocator may translate failed `memory.grow` into a generic Trap.

## D009 — Native MoonBit CLI and core, existing Wasm plugin ABI

**Status:** Accepted, verified.

Phase 2 implements objects, hashing, storage, staging, candidate construction and
CLI commands in MoonBit using its native backend. Filesystem operations use
`moonbitlang/async@0.20.2`; SHA-256 uses `gmlewis/sha256@0.18.0`, verified against
independent known vectors. Rust remains confined to the existing sandbox Host.
No change to WIT or plugin bindings is needed for the local Core.

## D010 — Versioned typed binary objects

**Status:** Accepted, verified.

Hash the whole `MOONVCS\0` envelope, version, type, payload length and payload
with SHA-256. Use length-prefixed UTF-8, big-endian numbers, canonical UTF-8-byte
Tree ordering and strict decoding. This avoids locale, JSON formatting, type
confusion and ambiguous field boundaries. The exact format is documented in
[OBJECT_FORMAT.md](OBJECT_FORMAT.md).

## D011 — Validate the staged snapshot before ref publication

**Status:** Accepted, verified with Mock and real Wasm validators.

Candidates use staged object bytes. A pluggable MoonBit validator must return
Pass before writing a Commit. Local refs use exclusive lock files and CAS against
the candidate parent; failed publication preserves the existing ref. Phase 3
connects real required-policy orchestration through the unchanged WIT contract.
Extra validators are additive and cannot replace repository policies.

## D012 — Keep storage transport out of the object contract

**Status:** Accepted, verified for memory and disk.

The ObjectStore trait accepts objects and IDs, not paths or URLs. `has` is only
presence; `get` and `verify` enforce digest and canonical decoding. Disk fanout
and locks belong to local adapters. Future remote/lazy stores can implement the
same async trait; transitive graph completeness is intentionally a separate
responsibility.

## D013 — Bind repository policy identity and transport staged bytes over stdin

**Status:** Accepted, verified.

Each repository pins required plugin names, versions and component SHA-256s.
The Host verifies pins against manifests and actual component bytes. MoonBit
serializes candidate bytes to a bounded stdin transport; the Host never rereads
working paths in this mode. Both commit APIs run required policies before
Commit writing. Missing runtime/config, malformed result and plugin failures
fail closed. Child environment inheritance is disabled, and plugins lacking
staged_content.read receive no content; staged_content.list separately permits filenames.

## D014 — Preserve WIT v1 while adding explicit Scanner configuration

**Status:** Accepted, verified.

The trusted Host can inject a reserved virtual file containing custom rules at
.moonvcs/plugin-config/v1.json. Candidate metadata paths are forbidden, preventing
working files from impersonating that record. MoonBit interprets the rules;
Rust only transports configuration. The WIT schema/import surface stays unchanged.
Diagnostic line remains null until an explicit ABI revision provides it.

## D015 — Independent grants and request filtering, no WIT expansion

**Status:** Accepted, verified in phase 4.

Manifest declarations remain untrusted. Schema 2 requires each plugin's grants,
intersected with the repository ceiling, manifest requests and Host availability.
Read/list/metadata/diagnostic capabilities have distinct, executable behavior.
Schema 1 retains legacy global-grant semantics only as a compatibility path.
Warning is existing WIT Pass plus Warning diagnostics; only the JSON adapter
and MoonBit engine gain a Warning outcome. Secret Scanner alone receives its
reserved custom-rule configuration file. See [migration](PHASE4_VALIDATION.md).

## D016 — Budget initialization and transport, not just evaluate

**Status:** Accepted, verified in phase 4.

The epoch timer starts before instantiation and is cancelled on all exit paths.
One linear memory makes Wasmtime's per-memory byte ceiling an actual total
guest-linear-memory ceiling. Live bounded stdout/stderr pipe reads and hard
child cancellation replace unbounded collect_output. Import audit is explicit
and the Linker remains empty. Compilation/RSS/TOCTOU limits remain documented,
not silently claimed to be solved by Wasm.

## D017 — Persist typed direct-edge promises instead of a complete history catalog

**Status:** Accepted, verified in phase 5.

The operator-selected filesystem Ref pins one remote and initial HEAD. Verified
imported Commits/Trees authorize only their direct references and declared
types. Unknown IDs do not cause remote probes, even if the remote contains them.
Per-ID provenance files avoid pre-downloading all ancestor IDs or rewriting one
large mutable promise catalog. Local-only has/verify are distinct from state.
The typed binary object encoding and ObjectStore trait remain unchanged.

## D018 — Atomic partial clone, serialized verified cache fills and explicit offline errors

**Status:** Accepted, verified in phase 5.

Clone uses an owned sibling directory, hydrates only HEAD checkout data, checks
the advertised snapshot again, then publishes without replacing user data.
Remote policy configuration is never trusted as local execution authority.
A stable advisory lock coalesces in-process and cross-process misses; exact
encoded source bytes are counted before integrity checks, and only verified
objects reach the cache. Explicit offline, unknown, unavailable remote, deleted
remote object and corruption have different outcomes. Missing edge registration
can be repaired from imported cached sources without fetching. File sync/atomic
visibility are not claimed to provide complete crash durability or crash-exact
telemetry. See [LAZY_STORAGE.md](LAZY_STORAGE.md).

## D019 — Server-owned policies and complete reachable-history snapshots

**Status:** Accepted, verified in phase 6.

A receive request contains only Ref expectations and typed object bytes, never
client PolicyResults or server configuration. The receiver independently checks
hashes/canonical encoding/types/completeness, then scans every reachable linear
Commit's full snapshot with the existing pinned on-receive Wasm API. This
conservative scope catches intermediate secrets and rescans existing history
under current policy, including when reused on a new branch. Merge history is
explicitly rejected rather than truncated to WIT v1's single optional parent.
No object format or WIT/component binary change is needed.

## D020 — Private quarantine, policy revision recheck and atomic single-Ref CAS

**Status:** Accepted, verified in phase 6.

Unapproved objects stay in an owned private quarantine. A server administrative
policy install and final publication share one stable advisory lock; after
validation the receiver rechecks exact policy bytes, old Ref and formal graph
integrity before promotion and the existing atomic Ref CAS. An independent
receiver process, standalone unchecked-object client and cross-process races
test this boundary. Ordinary failures/cancellation clean quarantine; crash
orphans, approved unreferenced promotion leftovers and lost-ack ambiguity are
documented instead of claiming a journalled distributed transaction.
The filesystem/stdio prototype has no authentication/TLS/ACL and does not isolate
two roles sharing an OS account. See [REMOTE_RECEIVE.md](REMOTE_RECEIVE.md).

## D021 — Verify composition without widening the feature or trust boundary

**Status:** Accepted, verified in phase 7 regression.

Independent standard-library Python fixtures and SHA-256 oracles complement the
MoonBit/Rust suites; they do not implement VCS/policy semantics. The single
verification entry records failures, repeat demos and optional source-clean and
benchmark outcomes. Cached-toolchain source rebuild is distinguished from a
blank-machine bootstrap; small local samples are not industrial/Git superiority
evidence. Wide-Tree costs remain visible instead of bypassing provenance checks.

Three reproduced fixes preserve WIT and typed object identities: absent remote
verify returns false without hiding provider failures; untrusted CLI inspection
is C0/ANSI escaped without rewriting bytes; running executable installation uses
same-directory atomic replacement, not in-place overwrite. This per-file build
operation is not a journalled runtime upgrade. See [audit](PHASE7_SECURITY_AUDIT.md),
[fixes](PHASE7_FIXES.md) and [validation](PHASE7_VALIDATION.md).
