# Phase 7 — Reproducible performance experiment

This file preserves the historical formal benchmark. New wide-Tree instruction
and logical-IO profiling is recorded separately in [ROADMAP_PROGRESS.md](ROADMAP_PROGRESS.md).
The later request-local optimization and paired miss/hit comparison are in
[ROUND2_VALIDATION.md](ROUND2_VALIDATION.md); they do not replace these historical samples.

This is a local prototype characterization, not a Git comparison or an
industrial performance claim. Python only orchestrates real native CLI/Host
processes; object storage, commits, policies and clone remain MoonBit/Rust/Wasm.

## Priority performance risk: zero transfers is not a speedup

Documentation clarification: 2026-10-18; the benchmark data remains the historical
2026-10-17 run, not a new measurement. In the 10000-object / 498-files-per-snapshot
case, the same Tree's cached-read median was 2165.92 ms (~2.17 s), versus
1856.86 ms (~1.86 s) for its first uncached read. All three trials recorded
zero additional transfers on repeated reads. Avoiding transfers is verified;
faster cached reads are not established. P7-001 remains open.

These are complete separate CLI-process timings, not pure disk or get-function
latencies. Repeated source/provenance validation is visible in code, but its
share of total cost has not been established by CPU/IO profiling. Do not describe
the identified code path as a measured, exclusive cause or claim a fix exists.

## Reproduce

    MOONVCS_MOON=/home/user/.moon/bin/moon ./scripts/verify.sh --clean-build --benchmark

After building, run only the experiment:

    python3 scripts/benchmark.py

Raw samples, operation exit codes, resource limits, policy pins, environment and
summary statistics are written to target/reports/phase7-benchmark.json. The
unified run also retains phase7-benchmark.log and stage status in phase7-verify.json.
Failed cases remain failed with errors and any completed timings; a per-command
300-second deadline is an experiment guard, not a VCS performance guarantee.

## Dataset: exactly 100 / 1000 / 10000 objects

Each scale uses the SAME 20-version history shape. Every version rewrites every
file with a unique safe 10–11 byte text value. Each is a real add/required-Wasm
policy-gated commit, not a forged store fixture or a disabled-policy baseline.
Each version introduces F Blobs + one flat Tree + one Commit:

    F = N / 20 - 2
    actual source objects = 20 * (F + 2) = N

Thus the snapshots contain 3, 48 and 498 files respectively. SHA-256 inventory
checks enforce actual counts and independently verify every source/cache file.
Clone obtains only the final Commit, Tree and Blobs: 5, 50 and 500 objects
respectively; those measured inventories must match real transfer counters.
Actual encoded-byte counts, not estimates or filesystem block usage, are reported.

Object count is NOT file count. In particular the 10000-object experiment is not
a 10000-file snapshot or an unrestricted 10000-object remote-push benchmark.
The receiver's existing graph/snapshot/history limits are unchanged.
Its 4096-object graph ceiling means the entire 10000-object closure is not a
supported receive request; only local commit/storage/clone/read are measured here.

## Timing semantics

- Three fresh repository trials per scale, sequential, same local workspace
  filesystem/device and installed runtime. The unified runner finishes builds
  before starting measurements. The machine is not an exclusively reserved
  benchmark host; OS caches are not dropped and scheduling noise remains.
- Native Core release build; installed Rust Host is Cargo dev/debug as used by
  demos, with actual Wasmtime 49.0.3 and the unchanged MoonBit Scanner.
  Versions/pins are recorded in phase7-environment.json and the raw benchmark.
- Commit is the last commit's full CLI duration AFTER add. Staging and Python
  fixture generation are excluded from that metric; raw staging timings remain
  in the operations array. Every earlier commit also executes required policies.
- Clone includes verification, HEAD checkout, promises, atomic file operations,
  transfer accounting and CLI output capture. It is a filesystem partial clone,
  not a network measurement or an unverified byte-copy benchmark.
- Lazy parent miss reads one previously uncached parent Commit. Lazy Tree miss
  then reads its full uncached Tree and registers child promises. These are
  different object sizes/operations and must not be conflated.
- Cache hit is the median of three further CLI reads of that SAME Tree. Counters
  must show zero extra remote transfers. Offline hit reads the same cached Tree
  after renaming the owned mock remote out of reach; an uncached promised Blob
  must separately return ObjectUnavailableOffline.
- Policy Host is one separate actual invocation on the last snapshot: startup,
  stdin/validation, manifest/digest, JIT, lowering, Wasm execution and result.
  It is NOT isolated guest execution time, a warm-JIT metric, or a subtraction
  proving exactly how much overhead the guest alone adds.
- Milliseconds use perf_counter_ns; tables summarize medians, while JSON keeps
  all samples/min/max. n=3 does not support p99, SLA or industrial superiority.

## Measured formal results

Completed 2026-10-17, all 9 cases passed their command/integrity/counter/offline
assertions. All durations below are milliseconds, medians of 3 fresh repository
trials; Host means the entire separate process as defined above, not guest CPU.

| Objects | Commit | Clone | Initial objects / encoded bytes | Parent miss | Tree miss | Same Tree hit | Policy Host |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 100 | 350.76 | 204.86 | 5 / 540 | 36.56 | 42.38 | 16.75 | 302.50 |
| 1000 | 396.61 | 1511.93 | 50 / 5445 | 33.68 | 205.18 | 151.66 | 301.02 |
| 10000 | 1041.37 | 15059.03 | 500 / 54495 | 34.05 | 1856.86 | 2165.92 | 333.78 |

Measured source encoded bytes were 10,696 / 108,346 / 1,084,846 respectively.
Initial cache inventories matched counters in every trial. Repeated Tree reads
added zero transfers; offline cached Tree medians were 17.46 / 151.38 / 2164.02 ms.
Offline uncached promised Blobs returned exit 4 in every case. Fetching the parent
and historical Tree added 453 / 4053 / 40053 actual encoded bytes respectively.
Raw JSON retains individual timings and min/max, including the noticeably slower
first 100-object Clone sample; no outliers were silently discarded.

The 10000-object Tree hit is actually SLOWER than the Tree miss here, despite
zero remote bytes. Existing-promise validation rereads/checks verified source
edges on a hit, whereas initial registration creates records from the already
verified object. Code inspection suggests these different metadata paths explain
much of the cost; no CPU-profiler attribution was performed. This is an open
implementation cost, not a claimed cache
speedup; no guest/runtime limits or provenance checks were weakened to improve
the numbers.

## Wide-Tree pilot and open cost

The initial two-snapshot pilots are retained separately:

| Pilot | Files/snapshot | Commit ms | Clone ms | Tree miss ms | Cached Tree ms |
|---|---:|---:|---:|---:|---:|
| 100 objects, 1 trial | 48 | 430.64 | 1527.68 | 203.52 | 157.43 |
| 1000 objects, 1 trial | 498 | 1019.95 | 18710.08 | 2552.19 | 2234.99 |

Files: target/reports/phase7-benchmark-pilot.json and
phase7-benchmark-baseline.json. These diagnostic pilots overlapped other audit
activity and are not controlled before/after results or formal comparison samples.
The formal workload fixes history depth at 20 and varies snapshot width, rather
than mixing the two-snapshot timings into its summaries. A different shape is
explicitly reproducible with --snapshots 2 --objects 100 1000 --repeats 1.

Inspection explains a real limitation: cached Tree reads revalidate existing
promise/source edges; wide fanout can repeatedly hash/decode the same source.
Cached does not mean cheap. No new verification cache/trust mechanism was added
to hide this cost. Future optimization must preserve provenance, corruption
checks, recovery and offline behavior with regressions. No claim is made for
unmeasured larger snapshots.

## Comparison exclusions

No Git timing is reported, so no Git version/partial-clone/network configuration
is silently implied. Git object encoding, policy enforcement and transport
semantics differ. Comparing this local partial clone with a Git full network
clone would not justify general superiority. Compression, batching, JIT reuse,
network latency, RSS, sustained concurrency and large-file throughput were not
evaluated here.
