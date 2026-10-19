# Phase 6 — Remote Policy Enforcement

Verified: 2026-10-17, Linux native, pinned toolchain unchanged.
Implementation: MoonBit server receiver and protocol, existing Wasmtime Host,
actual MoonBit Secret Scanner/License Checker, no final-demo Mock.

## Reproduce

Full six-phase regression:

    MOONVCS_MOON=/home/user/.moon/bin/moon ./scripts/test.sh

Build, native tests and standalone receive demonstration:

    MOONVCS_MOON=/home/user/.moon/bin/moon ./scripts/demo-receive.sh

Already built:

    ./scripts/demo-receive.sh --built

Real CLI log: target/reports/phase6-run.log. The demo removes only its owned
temporary client/server repositories; the run log is retained.

## A–D evidence

| Scenario | Actual behavior |
|---|---|
| A: normal safe commit and push | separate server receiver executes on-receive Wasm Scanner; accepts with policy revision receipt |
| B: simulated secret through normal commit | local real Wasm Scanner rejects; local HEAD stays unchanged |
| C: standalone unchecked-object client | creates Blob/Tree/Commit directly without any local policy call or Ref update; independent server receive rejects |
| D: same old Ref, two different targets | first accepted, stale second gets RefConflict; independent-process race also has exactly one winner |

The supplied bypass executable is vcs/cmd/bypass-client/main.mbt, built as
target/bin/moonvcs-bypass-client. It directly uses the canonical object store
and bundle encoder, not Repository.commit or Policy Engine. It writes only
harmless fixtures in the client repository. The server parses the wire request,
validates actual objects and materializes snapshots independently.

Observed example:

    Scenario A: safe client commit, server independently accepts
    Push accepted
    ... "checked_commits":1,"promoted_objects":3,"policy_revision":"sha256:..."
    Scenario B: local scanner rejects harmless simulated secret
    Commit rejected
    Policy: secret-scanner
    Reason: suspicious credential
    Scenario C: standalone bypass program creates unchecked objects without updating client HEAD
    Unscanned candidate <commit-id>
    Push rejected
    Policy: secret-scanner
    Reason: suspicious credential
    Scenario D: two prepared clients use the same old Ref; stale second publish cannot overwrite
    Push accepted
    RefConflict: expected old Ref changed; refresh and retry
    Concurrent server processes: exits 0 and 11 (one accept, one conflict)
    Measured published objects: initial=3 final=7; rejected candidate=<id> never published
    MoonVCS phase-6 remote policy receive tests passed

Final object totals are measured, not acceptance constants: the concurrent
winner may share different Blob/Tree objects, so final totals can vary. Ref IDs,
revision hashes and race winner also vary. The script checks rejection leaves
the formal object count unchanged, the rejected ID stays Unknown, server policy
bytes remain identical, quarantines are empty and every formal file matches
external sha256sum. Fixture credential values must be absent from all captured
local/remote rejection diagnostics.

## Automated tests

59 native tests (43 previous + 16 receive tests), plus unchanged 19 MoonBit guest
tests and 26 Rust Host tests; native check/test/release build use --deny-warn.

The receive tests cover:

- Safe push with actual required Wasm execution, complete graph and accepted receipt.
- Direct client-hook bypass rejected; formal objects, index and Ref preserved.
- Secret in intermediate history rejected even after removal at the tip.
- Hash mismatch, matching-hash malformed encoding, incomplete graph and type confusion.
- Unreachable extra uploads and malformed/truncated/trailing protocol data.
- Client policy content, repository-metadata paths and Ref traversal cannot alter authority.
- Missing/empty server policy, digest mismatch and runtime errors fail closed.
- Real MoonBit Trap, high-fuel epoch timeout and memory failure on on-receive.
- Two concurrent receive tasks and independent server processes, one winner only.
- Concurrent Ref reader observes only complete old/valid-new IDs.
- Quarantine contains the candidate during blocked validation, not the formal store.
- Administrative policy update during validation invalidates the old result; retry succeeds.
- Cancellation cleans owned quarantine without publishing.
- Current policies rescan previously approved history and objects reused on new branches.
- on-commit-only manifest is not permitted as an on-receive plugin.
- Unsupported force/merge history explicitly rejected.
- Valid quarantined duplicates cannot hide formal-store corruption.
- Both real Scanner and License Checker required on receive; Warning accepted, Reject blocked.

No WIT or canonical object encoding changed. The five existing component
SHA-256s are unchanged. Only License Checker/adversarial fixture manifest Hook
declarations gained on-receive; Hello intentionally remains on-commit-only.

## Scope and known limits

The MVP supports one branch update, complete server stores, linear reachable
history, fast-forward/new branches and full-snapshot/full-history rescanning.
It rejects Merge/force/delete/no-op Ref updates and enforces documented size,
graph, snapshot and time limits. Approval is under the exact current server
configuration and module pins; no client-supplied local result is trusted.

Ordinary failures/cancellation clean quarantine; process death can leave private
orphans. Multi-object promotion is not a journalled transaction: an I/O error or
a separate local writer winning the final Ref CAS may leave policy-approved
unreferenced formal objects, but no rejected/incomplete target Ref is published.
Lost acknowledgement after atomic Ref commit remains ambiguous and requires Ref
inspection, not automatic overwrite/retry.

This is not a production secure VCS. The filesystem demo uses one local OS
account and cannot stop that account from editing server files directly.
Authentication, ACLs, TLS, privilege-separated deployment, multi-Ref transactions,
durable promotion journal, rate/disk quotas and race-proof filesystem confinement
remain unimplemented. See [the exact receive contract](REMOTE_RECEIVE.md).
