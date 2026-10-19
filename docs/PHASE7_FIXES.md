# Phase 7 — Reproduction and fix record

The first existing six-phase run passed: 59 native, 26 Rust and 19 guest tests,
plus CLI/security/lazy/receive demos. Additional audit tests and concurrent use
then exposed the following real failures; they were not relabelled as successes.

## S7-001: terminal controls from untrusted content

Reproducer added first:

    python3 tests/system_audit.py SystemAudit.test_untrusted_display_fields_cannot_emit_terminal_control_sequences

Observed failure: literal ESC in staged filename output. The same rendering paths
also exposed author/message, Tree names and text Blobs from remote objects.
Fix: existing JSON-style safe text formatting at CLI presentation boundaries.
Stored encodings, ObjectIds, policy inputs and checked-out bytes are unchanged.
Text show is an escaped inspection view, not a raw byte export. Regression checks
actual safe local/remote policy-gated commits and unchanged stored Blob bytes.

## S7-002: concurrent rebuild hit ETXTBSY

A real verification run failed after native tests passed while a benchmark CLI
was still running:

    cp: cannot create regular file '.../target/bin/moonvcs': Text file busy

The failure log/result were retained before rerunning verification:

    target/reports/phase7-regression-before-fix.log
    target/reports/phase7-verify-before-fix.json

Fix: scripts/install-runtime-file.sh uses an owned same-directory temporary and
atomic rename. CLI, test-only bypass binary and Host use it. The deterministic
regression reproduces the old copy failure on a live owned sleep executable,
then verifies successful replacement without stopping the old process.
This is atomic per-file visibility, not an atomic multi-file runtime upgrade;
concurrent policy/runtime upgrades can still fail pins closed and require retry.

An initial version of this regression used a different executable basename; the
environment's GNU multicall coreutils rejected it. The fixture now retains the
sleep basename. That was a test-fixture portability error, not a MoonVCS failure.

## S7-003: remote verify contract

Reproducer added first:

    cd vcs
    moon test --target native --deny-warn --filter '*remote verify*'

Observed: 2 tests, 1 passed, 1 failed with RemoteObjectMissing. Fix in
vcs/lazy_store.mbt makes missing/invalid objects return false, as the ObjectStore
contract and local/memory implementations do. RemoteUnavailable and cancellation
remain errors; get/fetch retain their explicit missing-object errors.

## Regression additions / no product feature expansion

- Real-hash deep graph and explicitly synthetic cycle traversal guard tests.
- Independent hashlib object oracle, malformed wire corpus, unsafe paths,
  missing Parent/Tree/type mismatch, bypass and quarantine permissions.
- Mock-only environment sentinel test with actual Wasmtime execution.
- Unified-runner tests prove failures stop/record stages, a failed first smoke
  cannot be hidden by a later success, requested benchmark failure is nonzero,
  and unrequested optional checks are not reported as passed.
- A uniform benchmark records actual CLI calls/counters and failures, not canned
  performance numbers. Wide-Tree performance remains a documented open issue.

No WIT/plugin ABI, object format, capability grant model or new VCS feature was
introduced. Final results are in [PHASE7_VALIDATION.md](PHASE7_VALIDATION.md).
