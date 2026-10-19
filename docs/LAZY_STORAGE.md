# Lazy object storage v1

Implemented in MoonBit. The policy WIT, plugin binaries, typed object encoding
and SHA-256 rules are unchanged.

## Layers

    ObjectStore: put / get / has / verify (objects and IDs only)
      MemoryObjectStore                 existing in-memory adapter
      FileObjectStore                   existing disk adapter, retained API
      LocalObjectStore                  bounded, verified local disk adapter
      RemoteObjectStore                 read-only filesystem source
      LazyObjectStore                   local-first, promise-authorized fetch

Repository's filesystem adapter now uses LazyObjectStore, so normal Core
operations, log and show use the same path. Remote locations and cache paths
remain outside the ObjectStore trait and canonical object model.
Repository::at remains source-compatible with existing callers; optional offline
and fetch_events settings select adapter behavior.

## Presence is not a promise

| State | Meaning | get behavior |
|---|---|---|
| Local | Object file is present; not a claim that bytes are valid | Verify SHA-256 and canonical decoding before returning |
| PromisedRemote | Missing locally, with provenance from a pinned Ref or verified imported object edge | Fetch only the configured promisor, unless offline |
| Unknown | No local file and no valid promise | UnknownObject; no remote probe, even if that remote has the hash |

has and verify on LazyObjectStore are local-only, never trigger fetching, and
return false for a not-yet-cached promise. state exposes the richer distinction.
A corrupt Local object is an integrity error, never silently downloaded again.
get of a promise verifies the source object and expected type as well as the
new object's SHA-256, format version and canonical typed encoding.

The promisor is the filesystem repository explicitly selected by the local
invoker. Its default branch and HEAD ID are captured once. A verified imported
Commit grants promises for its Tree and parents; a verified imported Tree grants
promises for its entries with their declared Blob/Tree types. An arbitrary
locally-created object does NOT confer remote authority on its references.

No full historical ID list is downloaded or assumed. Each fetched parent reveals
the next parent. Thus a very old ID may remain Unknown even if a user has learned
its hash out of band: traverse the authorized chain first. All parents get
promises, but the MVP log traverses only the first parent.

## Durable metadata and provenance

    .moonvcs/promisor.json
        schema=1, remote_root, head_ref, head_id
    .moonvcs/promises/<64-hex-id>
        schema=1, id, kind, source, anchor
    .moonvcs/refs/remotes/origin/<branch>
        clone-time Ref snapshot
    .moonvcs/transfer-stats.json
        requests, received_objects, received_bytes, cached_objects
    .moonvcs/lazy-fetch.lock
        stable advisory lock inode, not a stale create-exclusive lock

anchor is the initial HEAD hash. source is ref only for the initial HEAD Commit;
otherwise it is the verified cached source object's ID. When a promise is used,
the adapter rechecks identity/type/anchor, source provenance metadata, the source
object hash and its immediate outgoing edge. These are local trusted records
issued by the adapter, not remote manifest declarations. Validation is immediate
edge checking, not a recursive revalidation of the entire history on every read.

Each locked get now has a fresh request-local index of verified source kinds and
typed immediate edges. The verified target itself can supply this index during
edge registration. Every promise identity/anchor/type, source presence and source
provenance record is still checked; a cached source index never substitutes for
a different source ID. Up to 16 sources and 16384 edges are indexed; beyond that
the original hash/decode/linear check remains. The index is discarded on return,
error or cancellation and cannot hide corruption on the next get. This relies on
immutable content-addressed objects under cooperating writers, not protection
against same-account filesystem tampering. See [round-2 evidence](ROUND2_VALIDATION.md).

The root of trust is the operator-selected filesystem Ref, not a cryptographic
server identity. Hashes prevent object substitution after that selection; they
do not authenticate the original advertised Ref. Remote policy configurations,
executables and plugin paths are NEVER imported into local execution authority.
clone uses the installed trusted local policy defaults.

Metadata files use synced temporary writes and atomic rename. Promise records
are per ID, avoiding a whole-history mutable catalog. Missing or malformed
promisor configuration in a partial repository fails explicitly rather than
silently treating it as a complete repository.

## Fetch transaction and concurrency

    acquire repository advisory lock
      -> recheck local cache
      -> validate promise and offline policy
      -> read only configured remote object
      -> count actual encoded bytes received
      -> SHA-256 + canonical decode + promised-type validation
      -> synced same-directory temporary object
      -> rename without replacement (deduplicating concurrent puts)
      -> register newly discovered direct promises
      -> release lock

The MVP serializes fetching per repository. Both independent store instances
and independent CLI processes participate in the lock and recheck, so duplicate
simultaneous misses produce one successful transfer. Locks use the pinned
moonbitlang/async file-lock API; Linux native is tested. Closing the file releases
the OS lock on error/cancellation/process death; the inode is intentionally not
unlinked. Acquisition polls nonblocking try_lock with a 30-second timeout.

If execution stops after publishing an object but before registering its edges,
the next local get re-verifies that imported object and repairs missing direct
promises, including offline. Invalid remote bytes are never installed. No
eviction, LRU or GC is implemented.

FileObjectStore's bucket creation is now idempotent and race-safe for cooperating
writers; longer-history tests exposed the previous repeated-bucket mkdir error.

## Clone publication and checkout

clone accepts a filesystem MoonVCS repository and a nonexistent destination with
an existing parent. It reads only HEAD/branch metadata, HEAD Commit and recursively
the Trees/Blobs needed for that HEAD checkout. It does not fetch ancestor Commits,
old Trees or old Blobs. Paths are checked against traversal, metadata injection
and unsupported file types; binary, empty and Unicode-named files are supported.

Construction occurs in a uniquely owned sibling directory. The index is the
complete checked-out snapshot, so status is clean. Remote HEAD and Ref are
re-read to detect observed concurrent changes; the validated snapshot is pinned,
not followed automatically. Only after validation are local/tracking refs and
the whole directory published without replacement. Failures clean only the owned
temporary directory; existing destination contents are not overwritten.

An advancing remote after clone does not change local HEAD or origin snapshot.
There is no pull/fetch-refs/push protocol in this phase. Normal local commits still
run all required Wasm policies and preserve the existing Ref CAS gate.

## Offline behavior and CLI

    moonvcs clone /path/to/remote-repository new-directory
    cd new-directory
    moonvcs log --max-count 20
    moonvcs show <authorized-known-id>
    moonvcs --offline show HEAD
    moonvcs log --max-count 2 --offline
    moonvcs storage-state <id>
    moonvcs storage-stats

MOONVCS_OFFLINE=1 also disables fetching. Offline is explicit policy, not a claim
to detect network state. An absent/unreadable configured filesystem remote while
online reports RemoteUnavailable; an existing remote with a deleted requested
object reports RemoteObjectMissing. Neither is called object corruption.

| CLI error | Exit |
|---|---:|
| ObjectUnavailableOffline | 4 |
| UnknownObject | 5 |
| RemoteUnavailable | 6 |
| RemoteObjectMissing | 7 |
| ObjectCorrupt (hash/type/canonical validation) | 8 |
| InvalidPromise | 9 |
| RemoteRefChanged | 10 |

Other usage/IO errors retain exit 1; policy exit codes 2/3 are unchanged.
Fetched objects emit Local Cache Miss → Remote Fetch → Hash Verified → Cached
events. Cache hits emit no Fetch event.

## Accounting

requests counts attempted remote object reads, including unavailable attempts.
received_objects/received_bytes count completed source reads before verification;
therefore corrupt received payloads count as traffic but not cached objects.
cached_objects counts successful verified fetch installations. Counters persist
under the fetch lock and are UInt64 decimal strings in JSON, following MoonBit's
lossless integer JSON representation.

Bytes mean canonical encoded object bytes actually read from the source file,
not logical Blob bytes or hypothetical compressed/network traffic. Ref/HEAD
metadata, OS stat operations and locally installed policy configuration are
excluded. Demo inventories independently measure physical object count/byte
length and compare them with those counters and external sha256sum.

## Limits and future transports

The adapters cap each encoded object at 32 MiB. Checkout caps 100,000 total
entries, depth 128, UTF-8 paths 4,096 bytes and 256 MiB total file data.
Objects and checkout blobs are currently buffered; these are not large-file or
streaming guarantees. Static symlink checks are not an openat/O_NOFOLLOW defense
against hostile local races. Metadata/objects are synced, but directory fsync,
power-loss durability and crash-exact telemetry transactions remain unimplemented.
Process death may leave unreferenced temporary files/directories; ordinary errors
and cancellation clean owned temporary state. Counters can undercount at a crash
boundary between I/O and metadata commit.

This version has one absolute-path filesystem promisor, no HTTP/TLS/authentication,
batching, compression, remote retention lease, LRU, chunking or edge cache.
The unchanged open ObjectStore trait and isolated remote adapter leave room
for those additions; promises must preserve origin binding and integrity checks.

Concept reference: Git's [promisor-object documentation](https://git-scm.com/docs/partial-clone)
also distinguishes expected missing objects from arbitrary absence. This project
implements its own typed loose-object promises and lazy Commit traversal, not
Git packfiles, Git protocol or Git partial-clone compatibility.
