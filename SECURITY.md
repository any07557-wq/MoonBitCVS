# MoonVCS security

This is a tested research prototype, not a production multi-tenant sandbox.

## Priority deployment risk: independent process is not privilege separation

The remote is a local filesystem/stdio prototype with no authentication, ACL,
TLS or server OS identity separation. The separate receive process independently
validates bundles submitted through its entry; it does not prevent a same-account
process from directly modifying server objects, Refs, policy configuration or
runtime files. Clearing the child's environment, quarantine mode 0700 and Ref
CAS do not remove that same-account authority. Wasm guest capability filtering
is a different boundary and does not isolate native client/server OS identities.

The bypass demo proves rejection through receive, not resistance to direct
server-file modification. Any hostile-client deployment requires these missing
controls; the prototype must not be presented as providing that guarantee.

## Priority reliability risk: staging and crash recovery are incomplete

The former concurrent-add lost-update window was reproduced with two real CLI
processes and repaired by a staging transaction lock spanning the entire index
read-modify-write. Old/noncooperating writers are not covered by that protocol.
Critical object/metadata/Ref publication now syncs parent directories after rename;
a post-rename sync error returns PublicationUncertain, not a rollback claim.

There is still no general promotion/recovery journal, automatic replay or GC. Switch now has a bounded private
intent/phase record and before-inode backups, not automatic recovery or a durable repository-wide transaction.
Ordinary error/cancellation cleanup is not recovery from process
death or power loss; exclusive index/Ref lock files, temporaries or private
quarantine may remain. recover --check is read-only; there is no automatic recovery or safe orphan collector.
Persistent fetch/receive advisory-lock files are not proof of a live lock holder;
do not delete locks, quarantine or objects merely because files remain.

## Priority security limits: memory, provenance and diagnostic disclosure

- Guest linear-memory and instance budgets are not a total Host/JIT memory or
  process RSS limit. JIT compilation and host-side allocations are not covered
  by an OS-level aggregate memory quota in this prototype.
- A pinned component SHA-256 binds approved bytes, not author identity, publisher
  authenticity or benign behavior. Manifest names/versions are not identity
  credentials. Plugin signatures, trusted publisher keys and signature
  verification are not implemented.
- A malicious plugin granted staged_content.read and diagnostic.emit can return
  authorized candidate content inside a size-compliant diagnostic. Bounds and
  JSON/display escaping do not provide confidentiality. Host output validation
  is not generic sensitive-content redaction; the supplied Scanner's redaction
  tests do not establish that arbitrary malicious plugins redact their output.

These are remaining limitations, not protections completed by this documentation
update. Guest containment, byte integrity and data confidentiality are different
claims and must not be advertised as interchangeable.

## Trust boundary and assumptions

The trusted Host, policy configuration authority and MoonBit Core enforce
required policies before Commit/Ref publication. Plugins AND their manifests
are untrusted. A manifest request never authorizes access.

Client hook results, Commit metadata, filenames and remote objects are also
untrusted. Server configuration, installed executable paths, local repository
metadata and the administrator remain trusted. Hashes assume SHA-256 collision
resistance; they do not authenticate a Ref or an author. Cooperative filesystem
locking and the verified Linux native toolchain are operational assumptions.

## Implemented protections

- Required pinned Wasm policies run at local Commit and independent server receive.
- Explicit capability intersection, filtered data, zero imports and empty Linker;
  no WASI directories, network, environment or shell supplied to guests.
- Fuel, independent epoch interruption, guest memory/input/output/log budgets and
  bounded/hard-cancelled Core-launched Host processes with no inherited environment.
- Canonical typed SHA-256 objects, verified lazy promises/cache, private receive
  quarantine, full reachable linear-history scanning and final Ref/config CAS.
- Request-local source/typed-edge reuse under the fetch lock is bounded and
  discarded after each get; promise/provenance checks and next-call hash checks
  remain. Over-budget sources use the original verified path, not skipped checks.
- C0/ANSI controls in CLI paths, metadata and text Blob inspection are escaped;
  canonical bytes are not rewritten. Runtime binary installation uses atomic
  per-file replacement rather than overwriting a running executable.

## Unimplemented protections and known limits

No authentication, authorization/ACL, TLS, privilege-separated deployment,
Host/JIT total RSS sandbox, aggregate rate/disk quotas, signed distribution or
race-proof filesystem confinement exists. Same-account clients can edit server
files directly. Automatic process-death recovery and verified power-loss durability,
promotion journals and exactly-once/multi-Ref transactions are not implemented.
Receive supports only complete server stores and one linear fast-forward/new
branch update. Authorized malicious diagnostics may disclose authorized data;
the supplied Scanner is an MVP detector, not comprehensive DLP.

The audit is not a sandbox proof or dependency/CVE clearance. Unicode UI
confusables/bidi attacks, Windows/macOS, physical blank-OS installation and
long-duration fuzzing were not verified. Installation/build/regression/demos in
an independently downloaded OCI rootfs passed without host toolchain/registry
mounts; its shared kernel and retained failed attempts are documented in the
[execution record](docs/ROADMAP_PROGRESS.md). Wide-Tree lazy reads have a documented
performance cost even on a cache hit. See the
[phase-7 security audit](docs/PHASE7_SECURITY_AUDIT.md) and
[known issues](docs/KNOWN_LIMITATIONS.md).
The later [round-2 regression](docs/ROUND2_VALIDATION.md) was rerun with 146 host
tests; a subsequent [final-archive installation](docs/FRESH_INSTALL_VALIDATION.md)
passes 149 tests and four demos in a separate new rootfs, preserving a real
registry 401 failure and its bounded-renewal fix. That bootstrap authentication
is not authentication for MoonVCS receive. Versioned archive pins
and local CAS copies improve availability, not publisher authentication or
guaranteed permanent upstream retention. Exit-16 handling remains a documented
manual inspection/retry protocol, not automatic durable recovery.

## Evidence and reproduction

Branch creation is no-overwrite from current HEAD. Switch requires clean staged/tracked
state, verified locally present target objects and no untracked/path-type collisions.
It shares the writer lock with add/commit/branch and final receive publication,
uses no-replace installs, retains original inodes even on success, and blocks
ordinary operations while a transaction is pending. Index then HEAD are separate
publications; exit 16/18 requires inspection, not blind retry. Fault tests use only
temporary fixtures; no automatic replay, force checkout, backup GC, race-proof
same-account confinement, total disk quota or power-loss guarantee is provided.
See [the prior safety contract](BRANCH_SWITCH.md).

The local diff command is read-only and does not invoke policies, fetch or repair
lazy metadata. It verifies compared local object bytes/types, rejects compared
symlink/special-file paths and escapes terminal controls and listed bidi formats.
It is not race-proof filesystem confinement, a provenance audit, an atomic
multi-file snapshot or Secret redaction: requested text content is displayed.
The earlier 149-test isolated installation predates diff; see the separately
scoped [diff contract and tests](docs/DIFF.md).

The final hackathon demonstrations use only harmless fixtures. See
[DEMO.md](DEMO.md), [the claim/evidence checklist](docs/CLAIMS.md) and
[the phase-8 delivery record](docs/PHASE8_DELIVERY.md). Capability denials
in that demo occur before instantiation, not in a filesystem callback; no
repository.secrets.read API exists. A real PTY recording is evidence of that
machine's execution, not a fresh-machine or production deployment guarantee.

See [the threat model](docs/THREAT_MODEL.md), [security boundaries](docs/SECURITY.md)
and [phase-4 validation and migration](docs/PHASE4_VALIDATION.md).
Filesystem partial-clone authority, remote validation, cache integrity and offline
limits are described in [lazy storage](docs/LAZY_STORAGE.md).
Independent receive-side required policies, quarantine, complete-history scanning
and Ref CAS are described in [remote receive](docs/REMOTE_RECEIVE.md) and its
[validation report](docs/PHASE6_VALIDATION.md). The filesystem demo shares one OS
account; a hostile-client deployment needs privilege separation, authentication,
authorization and secure transport, none of which this prototype provides.
Run the security regression with:

    MOONVCS_MOON=/home/user/.moon/bin/moon ./scripts/test-security.sh

Never put real credentials in test fixtures. Reports should use harmless
reproductions and omit secrets. No security-reporting service or private contact
channel is configured in this repository.
