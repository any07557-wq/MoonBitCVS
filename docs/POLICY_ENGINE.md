# CommitCandidate and Policy Engine boundary

## Implemented contract

The MoonBit core defines these types in `vcs/model.mbt`:

```text
CommitCandidate {
  tree_id, parents, author, timestamp, message,
  staged_files: [{ path, blob_id, content: Bytes }]
}

PolicyValidator.validate(candidate) async ->
  PolicyPass | PolicyReject(reason) | PolicyError(reason)
```

Phase 3 adds `validate_policies(candidate, PolicyContext)` in
`vcs/policy_engine.mbt`, returning `Accept`, `Warning(Array[PolicyDiagnostic])`, `Reject(Array[PolicyDiagnostic])`, or
`EngineError(reason)`. Every normal commit first invokes the real required Wasm
policies pinned in `.moonvcs/policies.json`. The engine does not read working
files, store objects or update refs.

`Repository::commit_with_validator` accepts the older open trait as an additional
validator only. `MockPolicyValidator::pass()` cannot replace the required gate;
both public commit APIs enforce it before writing the Commit. See the
[phase-3 report](PHASE3_VALIDATION.md) for configuration, transport and evidence.

## Submission sequence

```text
Working files -> add -> staged Blob IDs in index
                         |
                         v
               canonical Trees + CommitCandidate
                         |
                         v
                 Required Wasm Policy Engine
                    /              \
          Reject/Error/raise        Pass
                 |                   |
          leave HEAD alone      store Commit
                                     |
                            compare-and-swap Ref
```

Candidate bytes come from verified staged objects, not from rereading working
files. Editing a file after `add` therefore cannot change the candidate silently.
`staged_files` includes all files in the resulting staged snapshot, including
unchanged tracked files. Deletions are reflected by absence from this snapshot
and by the candidate Tree. The current ABI has no deletion event type.

The policy validator and adapter are trusted host code. Core freezes the Commit
payload before validators run and copies request data into the Wasm invocation;
plugins see serialized requests, not MoonBit object references. Configuration is
reread before Commit writing, and an in-flight change fails closed.

Blob and Tree objects can already exist when validation fails. The Commit
object is written only after Pass. Reject, Error, or a raised validator exception
does not update the branch. Rejected staged data remains available for correction
and a later retry.

After Pass, an exclusive branch lock prevents cooperating writers from
publishing concurrently. The existing ref must still equal the candidate's
parent. A changed HEAD ref name is also rejected. The target must be a stored,
verified Commit. Ref conflict or I/O failure before rename leaves the previous
ref untouched; a newly written but unpublished Commit can remain as an
unreferenced object. Garbage collection is not implemented.

Owned lock files are cleaned on ordinary failure and cancellation. Existing
locks belonging to other writers are never removed. Process death can leave a
stale lock; inspect it and confirm no writer is active before manual recovery.
Directory fsync and full power-loss recovery are not implemented.

## Mapping to the established WIT API

`wit/policy.wit` is unchanged: package `moonvcs:policy@0.1.0`, world
`policy-plugin`, exported `evaluate(policy-request) -> policy-result`.

| Existing WIT field | Implemented adapter source |
|---|---|
| `hook` | `on-commit` locally; `on-receive` on the server |
| `policy-version` | configured policy version, independent of object format |
| `commit-message` | candidate message |
| `parent-id` | `None` for root, `Some(parents[0])` for one-parent commit |
| `tree-id` | `Some(candidate.tree_id.to_string())` |
| `files` | authorized candidate paths and staged bytes |
| `granted-capabilities` | resolved by trusted Host configuration |

The existing ABI carries only one optional parent. The adapter rejects
unsupported multiple-parent submissions instead of silently dropping parents;
no WIT revision is needed for this stage's linear CLI history.

All required policies must Pass or produce only Warning before publication. Host failures, denied
capabilities, malformed results, traps, timeouts and plugin Error fail validation.
The adapter preserves phase-1 identity/digest checks, capability resolution,
resource budgets and the empty WASI-free linker. Candidate bytes travel over a
bounded stdin JSON transport, never by rereading working paths. Custom Scanner
rules use a trusted reserved virtual configuration record; the WIT file itself
is unchanged. Diagnostic line is currently null because WIT v1 lacks that field.

## ObjectStore boundary

The open async trait in `vcs/store.mbt` contains only domain values:

| Method | Semantics |
|---|---|
| `put(object) -> ObjectId` | canonicalize, hash and store; deduplicate identical objects; reject an existing corrupt copy |
| `get(id) -> VcsObject` | read, verify digest and canonical decoding; raise for missing/corrupt data |
| `has(id) -> Bool` | presence only; this is not an integrity guarantee |
| `verify(id) -> Bool` | false for missing, checksum mismatch or malformed/noncanonical encoding; I/O errors may raise |

`MemoryObjectStore` and `FileObjectStore` implement the same contract. Object
models, hashing, and the trait do not carry HTTP URLs, cache policy, or disk paths.
The Repository composes LocalObjectStore and, for partial clones, LazyObjectStore
with a read-only filesystem RemoteObjectStore. Lazy get fetches only typed
promised objects; has/verify stay local-only. Object identities and the trait
remain unchanged. See [LAZY_STORAGE.md](LAZY_STORAGE.md).

For remote bytes, check `object_id_for_bytes(received) == requested`, then
`decode_object(received)` and `put(decoded)`, requiring the returned ID to match.
Neither hashing arbitrary bytes nor checking presence alone validates an object.
Typed promise bookkeeping and independent receive-side policy/ref validation
are implemented. Network transport, authentication and TLS remain future work.

## Independent server receive boundary

The server builds candidates itself from the hash/type/graph-verified quarantine
and published store. It scans every reachable Commit's complete snapshot,
parent-first, under server-owned .moonvcs/receive-policies.json. No client diff,
local hook result or versioned configuration can grant approval. The same real
Wasm engine runs with hook=on-receive; its optional hook argument defaults to
on-commit for source compatibility, with no WIT/component binary changes.

Required Reject/Error prevents promotion and Ref publication. After approval,
the receiver locks publication, rechecks exact server configuration and expected
old Ref, verifies formal copies, promotes reachable objects and uses Ref CAS.
Single-Ref linear fast-forward/new-branch scope, policy-update semantics,
quarantine cleanup, crash limitations and retry behavior are specified in
[REMOTE_RECEIVE.md](REMOTE_RECEIVE.md); see [real tests](PHASE6_VALIDATION.md).
