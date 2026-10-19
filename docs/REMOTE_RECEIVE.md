# Remote policy enforcement v1

MoonBit implements receive, graph validation, snapshot materialization, quarantine
and publication. Rust remains the existing capability-secure Wasmtime Host.
This is a filesystem/stdio protocol prototype, NOT a production secure VCS.

## Roles and boundary

Trusted: installed server receiver/Core, server policy administrator, installed
Host/runtime and server filesystem metadata. Untrusted: client executable,
client hook results, supplied objects, Commit metadata and proposed Ref updates.

The trusted entry is moonvcs receive, running against an administrator-selected
server repository. It accepts only a bounded binary bundle, never a client
policy result, executable path, grant list or server configuration. push invokes
an independent receiver process with the bundle on stdin and no inherited
environment. The receiver then independently launches the pinned Wasm policies.

"Independent" describes the validation process, not a separate OS identity or
filesystem authority. There is no authentication, ACL or TLS endpoint here.
The same-account client can bypass receive by directly changing server objects,
Refs, configuration or runtime files. Empty child environments, mode-0700
quarantine and Ref CAS do not revoke that account's access. The bypass tests
exercise the receive entry, not resistance to direct server-file modification.

The filesystem demo runs both roles under one OS account. It does NOT prevent
that account from editing server files or invoking administrative commands.
Actual hostile-client deployment needs a separately privileged trusted receiver,
restricted object/ref filesystem access, authentication, authorization, transport
security and operational quotas. Merely placing this prototype's server directory
on a client-writable share is not a security boundary.

## Implemented flow

    received Ref/old-ID/target-ID/object bytes
      -> freeze request; validate framing, names and budgets
      -> early expected-old check
      -> private uniquely owned quarantine
      -> SHA-256 + canonical typed decoding for every supplied object
      -> complete reachable object graph validation, using quarantine + local store
      -> determine fast-forward/new-branch update
      -> load SERVER required policy configuration
      -> materialize every reachable Commit's full snapshot
      -> actual on-receive Wasm validation
      -> acquire publication lock
      -> recheck server policy bytes and expected old Ref
      -> recheck existing published graph integrity
      -> promote only validated reachable objects
      -> existing lock-file/CAS atomic Ref rename
      -> cleanup owned quarantine, return policy-bound receipt

Server object reads use a local-only overlay; they never consult the client's
promisor configuration or fetch a guessed remote ID. Partial-clone server
repositories are rejected in this MVP. Supplied unreachable extra objects are
rejected, not promoted. A matching hash alone is insufficient: canonical
encoding, type tags, expected edge types and graph completeness are required.
An incoming valid duplicate cannot hide an existing corrupt published copy.

## Supported policy scope

Every proposed target's ENTIRE reachable linear history is checked under the
current server configuration, including previously published Commits. Each
Commit is scanned parent-first using its COMPLETE Tree/Blob snapshot, not a
client-supplied diff or claimed changed-line list.

Consequences are deliberate:

- A secret introduced in an intermediate Commit and removed at the tip rejects.
- Reusing an existing object on another branch does not reuse an old approval.
- A policy/configuration upgrade rescans old reachable snapshots on the next
  update. Existing refs are not retroactively deleted, but a later push may be
  blocked by history that passed an older policy.
- Policies are repository-wide in this version, not per-user or per-branch.
- Warning permits publication; Reject or Error fails closed.

MVP accepts one refs/heads/... update per request, creation of a new branch,
and fast-forward updates with an exact expected-old value. It rejects merge
history anywhere in the target closure, force/rewrite updates, deletion and
no-op Ref updates. The unchanged WIT v1 has one optional parent; no merge parent
is silently dropped. Tags and atomic multi-Ref transactions are not implemented.

## Priority scale risk: bounded closure and full-history rescanning

The 4096-object and 128-Commit limits apply to the proposed target's complete
reachable graph, including ancestors and objects already present on the server,
not just newly uploaded objects. They are not a global object-count limit across
every Ref in the repository. Upload count also has its own 4096-object cap.
A single new Commit can therefore exceed the reachable-history limit; splitting
uploads does not remove the target-closure limit.

Every reachable Commit is materialized as a full snapshot and checked under
current required policies. There is no approval-result cache or exemption for
already published history. Object deduplication does not deduplicate policy
scanning of shared snapshot content. More history, larger snapshots and more
required policies increase validation work; no measured receive scaling curve
or guaranteed linear latency is available.

The limits are rejection thresholds, not throughput/latency guarantees; other
byte, snapshot, policy and timeout budgets can reject a request below them.
The historical 10000-object benchmark measures local storage/commit/clone/read,
not receive. Raising a constant or splitting a bundle is not evidence that this
receiver supports larger histories. Any future approval reuse needs an explicit
trusted validation model; client Pass results or Commit IDs alone cannot replace
current server-required checks.

## Server policy authority and versioning

.moonvcs/receive-policies.json is separate from local .moonvcs/policies.json.
It uses the existing schema-2 PolicyContext, requires a nonempty required list,
and contains server-selected module name/version/SHA-256 pins, per-plugin grants,
resource limits and custom rules. Manifest declarations remain untrusted.

Administrative commands:

    moonvcs init
    moonvcs receive-init
    moonvcs receive-policy-install /trusted/path/policy-context.json

receive-init installs the locally trusted runtime defaults and refuses to
overwrite an initialized receive configuration. receive-policy-install is a
TRUSTED ADMINISTRATIVE operation, not part of the client wire protocol.
Both installation and publication use the same stable advisory lock. A policy
change during evaluation forces rejection/retry, even if the old policy passed.
Manual edits outside that administrative locking API are outside the supported
concurrent-update guarantee.

The acceptance receipt includes policy_revision = sha256 of the exact server
configuration text. That text binds the actual plugin versions/digests and
settings used for validation. Whitespace changes conservatively change revision.
Policies use the pre-existing on-receive Hook. WIT and all five guest component
digests are unchanged. License Checker and the adversarial test fixture now
declare support for that Hook in their manifests; their binaries were not edited.
The on-commit-only Hello manifest is tested to fail closed on receive.

Client-supplied policies.json/receive-policies.json in ordinary repository content
do not configure the server. Root .moonvcs paths are rejected while materializing
snapshots, and Ref names cannot escape refs/heads. No received file is checked
out onto the server working directory, index or configuration.

## Quarantine and commit point

Each request creates .moonvcs/quarantine/rx-<unpredictable-nonce>/ with mode 0700.
Inside it is a separate typed object store. Graph lookup sees that store and the
existing formal store; no published Ref is changed while policy runs.

Only after all required policies pass, and final policy/Ref checks succeed, are
reachable objects installed into the formal store. Existing published copies
are verified again before promotion. Each object write is synced and atomically
renamed; the Ref's atomic rename is the publication commit point. The receiver
uses the same Ref lock/CAS as normal local commits, so a racing cooperating writer
cannot be silently overwritten.

Policy/hash/graph/config failures and stale receiver conflicts before promotion
leave no new formal objects. Ordinary success, rejection and cancellation clean
the owned quarantine. Cleanup failure is reported as pending inspection, never
as a rollback after an already successful Ref commit. Process death may leave a
private orphan quarantine; it is never auto-trusted or auto-published.

Promotion of many objects is not one filesystem transaction. An I/O failure, or
a separate local writer winning the final Ref CAS, can leave policy-approved
unreferenced formal objects. The successful live-process path publishes no Ref
to an incomplete new graph; this is not a power-loss recovery guarantee. Critical
object and Ref parent directories are now synced after publication, but a
promotion journal, verified power-loss durability and automatic orphan GC are
not implemented. Post-rename directory-sync failure returns PublicationUncertain.

Current receive owns an active.lock advisory lease inside its quarantine.
[recover --check](RECOVERY.md) observes active/idle lease state without removing
or publishing anything; unknown legacy quarantine is preserved. It is not a
journal replay or a complete crash-recovery transaction.

An orphan quarantine is not automatically safe to delete or publish. Recovery
must distinguish active requests and preserve unapproved data for inspection;
the prototype provides no automatic recovery/GC tool. The persistent receive
advisory-lock file's existence alone does not establish that a lock is held.

Retry behavior: after rejection, fix the candidate and retry with the same old
ID if still current. After RefConflict, refresh and rebase/reconstruct explicitly;
the client does not silently change its expected-old. A lost acknowledgement
after Ref publication is ambiguous: inspect the server Ref before retrying.
Exactly-once request IDs and automatic rollback are not provided.

## Binary receive bundle

All numeric counts are existing unsigned big-endian u32 values restricted to
the MoonBit Int32 range. Strings and IDs use the existing object-format
primitives, but this envelope is NOT itself a stored VCS object.

    8 bytes: MOONRX followed by two NUL bytes
    u8:      protocol version 1
    string:  target Ref name
    u8:      expected-old presence (0 or 1)
    id:      expected-old, only when present
    id:      proposed target Commit
    u32:     supplied object count
    repeat:
      id:    claimed typed-object SHA-256
      u32:   encoded byte length
      bytes: complete canonical object envelope

Duplicate IDs, truncated data, trailing bytes, unsupported framing, invalid Ref
paths and excessive lengths/counts fail closed. There is deliberately no field
for client PolicyResult, policies, grants, shell command or server path.

Limits: 16 MiB bundle, 4,096 unique graph/upload objects, 128 Commits,
64 MiB distinct decoded graph bytes, depth 256 and 32,768 graph edge visits.
Snapshots cap 4,096 entries, directory depth 128, 4,096-byte UTF-8 paths and the
configured policy input budget (default 1 MiB). Required policies retain their
independent Wasmtime fuel/epoch/memory/output/log budgets. Stdin ingress has a
10-second deadline; the quarantined receive operation has a 60-second deadline.
Publication/admin lock acquisition is bounded to 30 seconds.

These are prototype per-request budgets, not total RSS, disk-space, concurrent
request, connection-rate, durable-queue or OS sandbox limits.

## CLI transport

Normal filesystem push, with an explicitly last-observed server Ref:

    moonvcs push /path/to/server refs/heads/main none
    moonvcs push /path/to/server refs/heads/main <last-observed-server-id>

Prepare a file for a separately invoked receiver:

    moonvcs bundle /new/path/update.rx refs/heads/main <old-id-or-none> HEAD
    cd /path/to/server
    moonvcs receive /path/to/update.rx

receive --stdin also accepts the bounded binary envelope. Standard push/bundle
currently exports the full reachable closure, which can trigger client-side
Lazy Fetch and can exceed bundle limits for larger histories. The receiver can
resolve omitted already-published objects itself; future transport negotiation
can avoid resending them without weakening validation.

Success prints Push accepted plus a JSON receipt containing Ref, target,
checked_commits, promoted_objects and policy_revision. Failures:

| Outcome | Exit |
|---|---:|
| RefConflict, stale expected-old | 11 |
| Required-policy Reject / forbidden non-fast-forward | 12 |
| Required-policy configuration/runtime error | 13 |
| Invalid request/hash/type/graph/unsupported history | 14 |

Other filesystem/timeout failures may retain generic nonzero exit 1; the server
never turns an unclassified failure into approval. Policy values are not echoed
in parser errors; provided Scanner diagnostics omit matched credentials.

## Security and future work

There is no network listener, authentication, ACL, TLS, signed policy authority,
branch ownership, receive-side server OS sandbox or hostile local-process
filesystem-race defense. The test bypass utility only constructs CLIENT objects;
it never changes a client Ref and is not a normal commit path. It is intentionally
installed as moonvcs-bypass-client to make the test reproducible, not offered as
a server administrative capability.

The quarantine/publish ordering is informed by Git's
[receive-pack quarantine documentation](https://git-scm.com/docs/git-receive-pack).
This implementation has its own typed SHA-256 object format and binary protocol;
it does not implement Git wire protocol, packs or Git hook compatibility.
