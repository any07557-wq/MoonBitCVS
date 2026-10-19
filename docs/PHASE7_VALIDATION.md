# Phase 7 — System integration, tests and audit

Environment: Linux x86_64/WSL2, 2026-10-17. Pinned compiler, Wasmtime, WIT and
guest component identities are unchanged. This phase adds tests, reproducibility
instrumentation and three reproduced fixes, not a new VCS feature.

Observed: the final working-tree regression and the fresh-source regression
both passed all 122 distinct tests. The source-clean run completed in 311 seconds
with exit 0. The complete requested runner finished with exit 0: regression,
environment, repeat-smoke, clean-build and benchmark all passed. All 9 benchmark
trials completed; no experiment failure was omitted from the result.

## One verification entry

    MOONVCS_MOON=/home/user/.moon/bin/moon ./scripts/verify.sh --clean-build --benchmark

Without the two optional flags the same entry runs build, formatting/unit checks,
all CLI/integration/security tests, environment recording and two extra receive
demo repetitions. JSON explicitly lists unrequested expensive stages rather
than inventing passes. Nonzero stage results stop the runner and remain recorded.

Artifacts (generated locally under target/reports):

| Artifact | Meaning |
|---|---|
| phase7-verify.json | final requested-stage status and elapsed seconds |
| phase7-regression.log | build + all unit/integration/security results |
| phase7-environment.json | exact versions, Cargo.lock/WIT/module digests, platform |
| phase7-repeat-smoke.log | two further independent A–D remote demos |
| phase7-clean-build.json / .log | source-clean build scope, elapsed time and result |
| phase7-benchmark.json / .log | every real sample, object/byte counter, status and summary |
| phase7-regression-before-fix.log | preserved actual ETXTBSY failure, not overwritten by success |
| phase7-verify-before-fix.json | corresponding failed regression stage/exit 1 |

## Functional and security coverage

122 distinct tests in the final regression, excluding repeated build-script runs:

| Group | Passed tests |
|---|---:|
| MoonBit native Core/policy/storage/receive/audit | 63 |
| Rust Host/unit/security | 26 |
| MoonBit Wasm plugins | 19 |
| Independent Python system audit | 9 |
| Verification-runner/runtime-installer regressions | 5 |

Native fmt/check/test/release build use the existing zero-warning checks;
Rust formatting and locked dependencies are checked. The first existing suite
passed with its original 59 native tests. Additional audit tests then exposed
real defects, detailed in [the fix record](PHASE7_FIXES.md), before passing.

| Required scenario | Executable evidence |
|---|---|
| init/add/commit/log/show | native tests, six-command/subdirectory CLI smoke, independent binary/empty/Unicode oracle |
| Policy Accept/Reject/repair | actual Wasm policy CLI tests, preserved HEAD/index/worktree and redaction |
| Multiple plugins | actual Scanner + License, deterministic aggregation, Warning permits, Reject/Error blocks |
| Lazy clone/fetch/offline | 80-commit CLI demo, exact inventory/counters, repeat zero-transfer reads, disconnected cache/error distinction |
| Remote push/reject/bypass | independent receiver and unchecked-object client; server pins and full reachable history |
| Integrity/illegal graphs | external SHA-256 vectors/oracle, canonical type separation, missing Tree/Parent, wrong types, corruption, deep graph and synthetic cycle guard |
| Resource/authority isolation | no actual imports, empty Linker, real fuel/epoch/memory/Trap/malformed-return/output failures, mock-only capability checks |
| Remote transactions | tasks/process races, old-Ref/config recheck, atomic readers, private quarantine, rejection/cancellation cleanup |
| Extra audit boundary | 167 deterministic malformed protocol inputs, mock sensitive environment, hostile paths and unchanged canonical bytes after display escaping |

The repeat smoke covers safe accept, local reject, bypass reject, stale-Ref
conflict and two independent receiver processes with exactly one winner, twice
after the main regression. The system audit independently repeats basic local
and remote flows. Fixture values are harmless; no real credentials are read.

## Clean-source reproducibility boundary

scripts/clean-build.sh makes an owned workspace source copy containing no target,
_build, project .mooncakes, native executable or runtime artifacts. It rebuilds
the five guest Components, Rust Host, native CLI and runs the same regression
entry in the copied source. Installed tool binaries and global registry caches
are reused; Cargo is forced offline and its build target is fresh. Components
must reproduce their existing SHA-256 pins. Temporary copies are removed and
the log/result are retained.

This verifies source-clean rebuilding on the recorded installed environment,
NOT a blank Linux installation or empty-cache network bootstrap. The ignored
.toolchains directory is not source distribution: a new machine must separately
obtain the exact versions listed in README/environment metadata. That installer
workflow, future registry availability and other operating systems are unverified.

## Performance scope

The formal experiment uses 100/1000/10000 actual reachable objects, 20 real
policy-gated snapshots at every scale and 3 trials. Snapshot widths are 3/48/498
files, not 100/1000/10000 files. Clone inventories, bytes, last Commit latency,
separate Host cost, parent/Tree misses and same-Tree online/offline hits are
measured and checked against counters. Source generation and add are not hidden
inside the reported Commit timing; all raw operation timings remain available.
The 10000-object case does not extend receive's 4096-object graph limit: publishing
that entire closure is unsupported, and no such remote-push performance claim is made.

See [BENCHMARKS.md](BENCHMARKS.md) for method, raw artifact paths, medians and
wide-Tree pilot limitations. There is no Git comparison, no network benchmark,
no pure guest-CPU claim and no industrial/p99 conclusion from three samples.

Observed last-Commit medians were 350.76 / 396.61 / 1041.37 ms; Clone medians
were 204.86 / 1511.93 / 15059.03 ms for the three scales. Initial download was
5 / 50 / 500 objects and 540 / 5445 / 54495 encoded bytes, measured by both
inventory and transfer counters. The largest cached Tree read still took
2165.92 ms and was slower than its 1856.86 ms miss; this remains an explicit
performance issue, not an assertion that caching universally accelerates reads.

## Limits and explicit exclusions

The security audit and [known issues](KNOWN_LIMITATIONS.md) remain binding.
The prototype lacks auth/ACL/TLS and OS privilege separation; same-account server
access is trusted. Wide-Tree cache/provenance checks remain expensive. Directory
fsync, power-loss journal/recovery, arbitrary multi-Ref/merge publication,
aggregate quotas, dependency-advisory scanning, long-duration fuzzing and a
formal sandbox proof were not implemented or verified.

The preserved earlier failure and per-stage JSON are part of the delivery. A
future failing experiment must remain a failure; do not copy benchmark numbers
into a marketing claim or treat an unrequested check as verified.
