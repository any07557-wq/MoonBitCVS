# Security Boundaries

## Guarantees demonstrated in phase 1

- The plugin receives no WASI imports and no host functions.
- Candidate bytes are copied only after manifest and repository capability checks.
- Component bytes are checked against the manifest SHA-256 digest.
- Absolute paths and parent-directory traversal are rejected by the demo Host.
- Fuel bounds deterministic instruction work; an infinite-loop fixture is stopped by fuel exhaustion. Epoch interruption provides a wall-clock backstop.
- Wasmtime Store limits bound guest linear-memory growth and instance resources. The Host records and reports limiter-denied growth independently of the guest's resulting allocator Trap.
- Input and diagnostic output sizes are checked by the Host; a 4 KiB fixture result is rejected under a 1 KiB output budget.
- Explicit guest Traps are converted to error status and never to Pass.
- Required-policy failures are fail closed.
- Secret diagnostics identify rule and path but omit the matched value.

## Trusted computing base

The Policy Configuration Authority, Rust Host/Wasmtime, Core validation logic and
build/runtime glue are trusted. Plugin code AND manifest declarations, repository
content, commit metadata and remote clients are untrusted. A manifest is
not a grant. See the current [phase-4 threat model](THREAT_MODEL.md).

## Phase-2 local publication

The native MoonBit CLI constructs candidates from verified staged Blob objects
and only writes a Commit after every required Wasm policy and additional validator
returns Pass or Warning. Reject, Error and
raised failures leave HEAD unchanged. A lock-file/CAS check prevents a policy
validation result from overwriting a ref changed by another cooperating writer.
Object reads verify both SHA-256 and canonical binary decoding.

The phase-3 CLI supplies staged bytes to the real Host over bounded stdin JSON.
Both public commit paths execute pinned required policies; an extra Mock Pass
cannot bypass them. Missing policy configuration, Host, component, identity
mismatch and plugin failure stop publication. Native tests check expected Commit
object absence, preserved HEAD/index and real trap/resource failures. Scanner
diagnostics never copy matched values; captured Host stderr is not printed.
See [PHASE3_VALIDATION.md](PHASE3_VALIDATION.md).

Working paths reject traversal and static symlink ancestors. Repository metadata
is trusted, and filesystem checks are not race-proof against hostile local
mutation. Crash durability, concurrent staging and memory-size limits are
described in [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md).

## Non-guarantees

This is not a formal sandbox proof. Store memory limits do not account for every
byte allocated by the Host or JIT. Phase 4 independently tests fuel and epoch
interruption, including initializers. Epoch interruption is coarse grained and
does not cover compilation; the Core child timeout adds a startup allowance and
hard cancellation. The child has no OS resource sandbox. Side-channel resistance,
signed distribution, provenance and multi-tenant isolation are not implemented.
Repository configuration and the owner who edits it remain trusted. Phase 6
implements independent receive-side policy validation; actual hostile-client
deployment still requires privilege separation, authentication and authorization.

## Phase-4 audited behavior

- Four capabilities have explicit request filtering and per-plugin grants.
- Manifest name/version/digest are bound to trusted configuration; ABI/hooks and actual component imports are checked.
- Only one linear memory is allowed, preventing per-memory budget multiplication.
- Fuel and an independent epoch timer apply before instantiation, not only during evaluate.
- Input, serialized output, diagnostic payload and live stdout/stderr pipes have bounds.
- Required Reject/Error never writes a Commit or changes HEAD; Warning permits publication.
- Restricted Plugin proves actual allowed data; unsupported repository.secrets.read is denied by the real resolver, not a nonexistent callback.
- No WASI context, filesystem imports or preopened directories exist. Filesystem tests use only a temporary mock HOME/SSH resource.

See [validation and migration](PHASE4_VALIDATION.md) for tests and precise limits.

## Phase-5 filesystem promisor boundary

Remote object bytes, tree paths and Ref contents are untrusted data. The local
operator's explicit remote selection and locally persisted promisor/promise
metadata supply fetch authority; SHA-256/canonical/type checks supply object
integrity. Unknown objects never cause arbitrary remote lookup. Clone does not
import remote executable policy paths or grants. Static remote symlinks and
reserved checkout paths are rejected, and checkout/object-size budgets apply.
Cache corruption, remote unavailability, broken promises and explicit offline
misses are distinct outcomes. Partial clones retain the real required-policy
commit gate. See [storage trust/atomicity limits](LAZY_STORAGE.md) and
[measured tests](PHASE5_VALIDATION.md).

## Phase-6 remote publication boundary

The independent receiver accepts a bounded object/Ref bundle, not client policy
results or executable configuration. It validates hashes, canonical encodings,
edge types and the complete graph in private quarantine, then executes real
server-pinned on-receive Wasm policies on every reachable Commit's full snapshot.
Server receive configuration is separate from versioned files and local hooks.
Final publication rechecks that configuration and expected old Ref under the
administrative/publication lock, then uses the existing Ref CAS/atomic rename.
Rejected candidates never become published history. Tests cover a standalone
client-hook bypass, actual traps/timeouts, policy changes, cancellation and
independent-process races. See [validation](PHASE6_VALIDATION.md).

The demo shares one OS account and cannot stop that account editing server
objects/configuration directly. No authentication, ACL, TLS or receive OS sandbox
exists. Only complete server stores and single-Ref linear fast-forward/new-branch
updates are supported. Ordinary cleanup is not process-death recovery; approved
unreferenced objects can remain after promotion I/O/CAS failure. See the exact
[receive scope and limitations](REMOTE_RECEIVE.md).

Do not run arbitrary third-party components in production based only on this prototype.

## Phase-7 audited fixes and evidence

Independent CLI tests verify mock sensitive variables are absent in both native
policy children and independent receive execution. Component import inspection,
malformed protocol mutations, an external hash oracle and mode-0700 quarantine
checks supplement the existing real Wasm/resource/race tests. CLI paths/metadata
and text inspection now escape C0/ANSI controls; atomic runtime executable
replacement fixes concurrent-build ETXTBSY without changing running processes.
Remote verify returns false for absent/invalid objects, not provider failures.
See [security findings and residual risks](PHASE7_SECURITY_AUDIT.md),
[fix/reproduction record](PHASE7_FIXES.md) and [validation](PHASE7_VALIDATION.md).
