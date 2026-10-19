# Phase 5 — Lazy History Fetch

Verified on 2026-10-17, Linux native. Implementation is MoonBit; existing Rust
Host and WIT/plugin components are unchanged.

## Reproduce

Full five-phase regression:

    MOONVCS_MOON=/home/user/.moon/bin/moon ./scripts/test.sh

Build, native tests and the measured lazy-history demo alone:

    MOONVCS_MOON=/home/user/.moon/bin/moon ./scripts/demo-lazy.sh

Already built:

    ./scripts/demo-lazy.sh --built

The demo writes its real runtime output to target/reports/phase5-run.log and
removes only its own temporary test repositories on exit. It generates 80 real
CLI commits through the required Wasm Scanner, including binary, empty and
Unicode-named files. No transfer/object totals are hardcoded into the demo.

## Measured results

The verified run measured canonical encoded-object bytes:

| Point | Objects | Bytes |
|---|---:|---:|
| Full filesystem remote, 80 commits | 244 | 37,948 |
| Initial clone plus complete HEAD checkout | 7 | 742 |
| After reading six most recent commits | 12 | 1,682 |
| Repeating that history read | +0 | +0 |

Initial clone downloaded about 2.9% of the remote objects and 2.0% of object
bytes. It fetched one Commit, current Trees and current Blobs only. The five
additional Commit reads totalled 940 bytes; historical Trees/Blobs were not
downloaded by log. One of those Commits was requested by eight independent CLI
processes simultaneously and produced exactly one transfer.

Counts come from filesystem inventories; bytes come from file lengths and
persisted read counters, which the script cross-checks. Every cached filename
is independently compared with sha256sum of its complete object bytes.
Ref/HEAD metadata and local configuration are excluded from object-byte totals.
Hashes/timestamps vary by run; exact numbers above describe the supplied fixture
and observed run, not constants used to fake output.

Representative actual log lines (IDs abbreviated here only):

    Clone downloaded objects=7 object_bytes=742
    Concurrent Fetch: 8 processes, 1 transfer
    [Fetch] Local Cache Miss <parent-id>
    [Fetch] Remote Fetch <parent-id>
    [Fetch] Hash Verified <parent-id> bytes=188
    [Fetch] Cached <parent-id>
    Offline Cached Read: success without remote access
    ObjectUnavailableOffline: <uncached-promised-parent>
    UnknownObject: 0000000000000000000000000000000000000000000000000000000000000000
    RemoteUnavailable: configured promisor cannot be read
    remote_objects=244 remote_object_bytes=37948
    initial_clone_objects=7 initial_clone_object_bytes=742
    after_history_objects=12 after_history_object_bytes=1682
    repeat_fetches=0 concurrent_processes=8 concurrent_transfers=1
    MoonVCS phase-5 lazy storage CLI tests passed

Remote disconnection is real: the script renames its temporary remote directory.
Offline cached show/log work after that. Explicit offline misses and Unknown
requests do not increase the remote request counter. Online access to an uncached
promise increments attempts but returns RemoteUnavailable without claiming
corruption or adding transferred object bytes.

## Automated coverage

43 native tests pass with --deny-warn (29 earlier tests plus 14 storage tests),
alongside unchanged 19 guest and 26 Rust Host tests in the full suite.
Storage coverage:

- Local hit, exact initial clone inventory and zero-history-prefetch limit.
- Promised miss, verified parent discovery, persistent reopening and repeat hits.
- Unknown object present on remote nevertheless makes zero remote requests.
- Locally-created arbitrary edges cannot mint promises.
- Offline cached/uncached distinction, actual remote loss and recovery.
- Remote deletion distinct from corruption, with retry after restoration.
- Remote corrupted bytes counted but never cached; repair permits retry.
- Corrupt local cache detected without remote fallback.
- Twelve concurrent async readers across store instances produce one transfer.
- Concurrent local reader observes only complete atomically published cache data.
- Interrupted edge-registration recovery from verified local source, including offline.
- Missing partial-clone metadata fails closed.
- Remote Ref advances leave clone pinned; snapshot revalidation detects change.
- Wrong expected type, matching-hash malformed encoding and reserved checkout path rejected.
- Failed clones clean owned temporary state and do not overwrite existing directories.
- Remote policy configuration is not adopted; RemoteObjectStore rejects writes.
- Partial-clone local commits still run the actual Wasm Scanner and reject simulated secrets.

See [storage architecture and metadata schema](LAZY_STORAGE.md) for exact
capability of the storage layer, lock/atomicity semantics, accounting, exit codes,
and limitations. HTTP/TLS/authentication, remote receive enforcement, parallel
batching, compression, GC/LRU and large-file streaming remain out of scope.
