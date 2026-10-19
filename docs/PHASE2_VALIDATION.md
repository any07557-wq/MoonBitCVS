# Phase 2: MoonBit VCS Core validation

Historical phase-2 record. Phase 3 has since connected real required Wasm
policies; current build/test commands also build that runtime. See
[PHASE3_VALIDATION.md](PHASE3_VALIDATION.md) for current behavior and counts.

Verified on 2026-10-17, Linux x86_64 (WSL2), with real native builds and tests.

## Result and delivered files

The minimal local workflow is operational: initialize a repository, stage files,
commit through the Mock Policy boundary, inspect history and objects. Loose
objects are actually persisted under their SHA-256 IDs.

| Deliverable | Location |
|---|---|
| Blob, Tree, Commit, Ref, CommitCandidate, policy trait | `vcs/model.mbt` |
| Canonical encoding, SHA-256 and decoding | `vcs/encoding.mbt` |
| Open ObjectStore trait; memory and filesystem adapters | `vcs/store.mbt` |
| Stage, candidate, commit, ref CAS, log and status | `vcs/repository.mbt` |
| Native CLI | `vcs/cli.mbt`, `vcs/cmd/main/` |
| 16 MoonBit tests | `vcs/core_wbtest.mbt`, `vcs/boundary_wbtest.mbt` |
| Reproducible build and CLI integration | `scripts/build-vcs.sh`, `scripts/test-vcs.sh` |
| Example input project | `examples/vcs-demo/` |
| Serialization specification | [OBJECT_FORMAT.md](OBJECT_FORMAT.md) |
| Policy and storage contract | [POLICY_ENGINE.md](POLICY_ENGINE.md) |

## Toolchain and compatibility

| Tool | Actual version/choice |
|---|---|
| moon | `0.1.20261012` (`748b63c`) |
| moonc | `v0.10.15+943464bfa` |
| C compiler | GCC/cc `15.2.0` |
| Target | MoonBit `native`, release executable |
| Hash implementation | `gmlewis/sha256@0.18.0`, MoonBit source |
| Filesystem/runtime | `moonbitlang/async@0.20.2` |

The CLI structure follows the official [Native CLI Quickstart](https://docs.moonbitlang.com/en/latest/tutorial/cli-quickstart.html):
a library package and native executable entrypoint, using `env` and async
filesystem operations. The [package documentation](https://docs.moonbitlang.com/en/latest/toolchain/moon/package.html)
and [async language documentation](https://docs.moonbitlang.com/en/latest/language/async-experimental.html)
were checked against the installed compiler and dependency source.

`vcs/moon.mod` pins the two direct dependencies. A clean machine needs MoonBit,
a native C toolchain and Mooncakes access for dependency installation; Rust and
Wasmtime are only needed for the separate phase-1 sandbox suite.

Compatibility findings caught by real tests:

- MoonBit `String::to_bytes` returns UTF-16LE; the object format explicitly uses
  `@utf8.encode`, including for ASCII IDs. The initial round-trip tests exposed
  this difference.
- Generic `Bytes` comparison did not give the intended lexicographic UTF-8
  ordering. A dedicated unsigned-byte comparator now defines canonical order,
  tested with ASCII, CJK, a private-use character, and an emoji.
- The installed compiler supports explicit `extend` declarations and async
  tests. The phase-2 build and tests run with `--deny-warn`.
- Phase-1 WIT, generated plugin bindings and plugin manifests are unchanged by
  phase 2. WIT SHA-256 remains
  `4b3ff703ed44a679ea8b689e0977867505ec602d159d2f57f9c4773bccc8725d`.

## Reproduce

From the project root:

```bash
export PATH="$HOME/.moon/bin:$PATH"
./scripts/test-vcs.sh
```

This checks formatting, compiles with zero warnings, runs the 16 tests, builds
the release CLI as `target/bin/moonvcs`, and runs a temporary-repository CLI
integration test. The integration script removes only its own temporary fixture.

The CLI test checks `init`, recursive `add`, staged and clean status, `commit`,
`log`, and `show HEAD`. It makes a second commit from inside a subdirectory,
checks the newest-first history and parent link, then independently compares
every persisted object's filename with `sha256sum` of its bytes.

Run both stages with `./scripts/test.sh`. The phase-1 commands and acceptance
evidence remain documented in [PHASE1_VALIDATION.md](PHASE1_VALIDATION.md).
The combined run completed successfully: 16 native Core tests, 8 Wasm plugin
tests, 5 Rust Host tests, the native CLI integration and all sandbox integration
assertions passed. All three component digests still match their manifests.

Manual acceptance example, from the project root:

```bash
./scripts/build-vcs.sh
export PATH="$PWD/target/bin:$PATH"
MOONVCS_DEMO_ROOT="$(mktemp -d /tmp/moonvcs-demo.XXXXXX)"
cp -R examples/vcs-demo/. "$MOONVCS_DEMO_ROOT/"
cd "$MOONVCS_DEMO_ROOT"
moonvcs init
moonvcs add example.txt nested
moonvcs commit -m "initial"
moonvcs log
moonvcs show HEAD
```

Commit IDs and timestamps change for current-time CLI submissions. The binary
format vectors and fixed-timestamp MoonBit tests are deterministic.

## Test evidence

The observed MoonBit result is `Total tests: 16, passed: 16, failed: 0`.

| Requirement | Evidence |
|---|---|
| Hash consistency and known vectors | empty Blob, `hello\n`, four-zero-byte Blob, empty Tree |
| Type separation | identical four-zero-byte payload under Blob and Tree gets different IDs |
| Canonical serialization | Blob/Tree/Commit round trips, insertion-order independence and Unicode sort |
| Object deduplication | repeated memory/disk puts return the same ID |
| Blob and Tree persistence | binary/empty/Unicode files, nested Trees and reopened disk store |
| Commit graph | root and successor objects, parent IDs and two-commit log order |
| Ref updates | successful CAS, stale expected ID conflict, existing-lock preservation |
| Object corruption | altered disk and memory bytes rejected; corrupt copies are not overwritten |
| Malformed incoming objects | unknown kind, bad counts, truncation, trailing data and unsorted Tree rejected |
| Path boundary | absolute/parent/metadata paths rejected; symlink files and ancestors rejected |
| Candidate uses staged data | a later working-file edit is absent from policy input |
| Required validation fails closed | Reject, PolicyError and raised exception do not publish HEAD |
| Failed publication | validation-time ref race is detected; failed writes clean owned locks |
| CLI acceptance | real temporary repo, persisted objects and independent SHA-256 verification |

## Limits and next integration point

`moonvcs commit` currently uses Mock Pass. Connecting candidate data to the
verified Wasmtime Host is the next implementation step, through the existing
trait and WIT mapping. No claim is made that the current CLI enforces Wasm
policies. Local ref CAS is implemented; remote receive-side validation, lazy
history, Git protocol, diff, branch commands, checkout, merge and rebase are not.

Only Linux native execution was verified. Staging uses memory-resident whole
files and full snapshots. Metadata is trusted; concurrent hostile filesystem
mutation and power-loss recovery are not covered. See the complete
[known limitations](KNOWN_LIMITATIONS.md).
