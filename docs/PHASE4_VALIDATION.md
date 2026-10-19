# Phase 4 — capability-secure plugins

Validation date: 2026-10-17, Linux, Asia/Shanghai.
Status: implemented; reproducible full-suite command below.

## Unchanged binary contract

WIT remains moonvcs:policy@0.1.0 / policy-plugin, ABI version 1.
wit/policy.wit SHA-256:

    4b3ff703ed44a679ea8b689e0977867505ec602d159d2f57f9c4773bccc8725d

No imported Host API, WASI, or capability resource was added. Warning is
represented by the existing Pass decision plus Warning-severity diagnostics;
the Host JSON adapter exposes status warning (exit 0). Existing Pass/Reject/Error
binary representation is unchanged. Core aggregates Accept, Warning, Reject,
or EngineError; Error outranks Reject, Reject outranks Warning, Warning permits
publication. Evaluation order and diagnostic order follow required[] exactly.
On a runtime Error the engine stops fail-closed; it need not run later plugins.

Toolchain remains MoonBit moon 0.1.20261012 / moonc v0.10.15,
Rust 1.99.1, wit-bindgen 0.63.0, wasm-tools 1.262.0, Wasmtime 49.0.3.

## Artifacts

| Component | Version | SHA-256 (without sha256: prefix) |
|---|---|---|
| secret-scanner | 0.2.0 | 3743537dad366b6af66d0b36d27eb77f47bee2b4669475e2d4a7b0fca5023cf2 |
| license-check | 0.1.0 | 444639aeeac8c19b143dc438dc36c27e45f98881d3b9f0e2555c5ce45ff7375a |
| restricted-plugin | 0.1.0 | 3d83dd0450ceb8a3bd4abf108f1760cc224349916025f2d0689b411f834f0df0 |

All five MoonBit components, including Hello and adversarial fixtures, compile
and validate. Existing three component digests are unchanged. All production
and restricted components have zero component imports, checked using Wasmtime's
actual compiled component type. WAT-only invalid-return and infinite-start
fixtures use the same real WIT and are not production plugins.

License Checker enforces this demo repository convention: a nonempty root
LICENSE in the complete staged snapshot; .mbt/.rs/.py files must contain
SPDX-License-Identifier: Apache-2.0 in their first 512 bytes. Optional absent
NOTICE emits a Warning. These are configurable-demo conventions in code, not
license compatibility analysis or legal advice.

## Reproduce

From the project root:

    MOONVCS_MOON=/home/user/.moon/bin/moon ./scripts/test.sh

Standalone phase-4 build/tests/demo:

    MOONVCS_MOON=/home/user/.moon/bin/moon ./scripts/test-security.sh

The full suite includes 19 MoonBit guest tests, 26 Rust Host tests and 29 native
MoonBit tests, plus CLI end-to-end scripts. All native checks/tests/release builds
use --deny-warn. The sandbox tests cover permitted data, denied/unsupported
capabilities, excessive requests, ABI/hook/manifest/digest/identity mismatches,
Trap, independent fuel and epoch exhaustion, epoch interruption during component
initialization, memory bounds, multi-memory denial, output/log flooding, forbidden
imports and malformed canonical return data. Native integration proves actual
required-policy commit gating, preserved state and deterministic aggregation.

The security demo uses only a temporary mock-home/.ssh/id_demo. It demonstrates
two real policy rejections, repair plus warning-permitted commit, static symlink
denial, and rejection of a correctly digested component with a WASI filesystem
import. Native tests additionally check no rejected Commit object is stored.
No user's real HOME or private key is read.

## Configuration and compatibility migration

Default init deliberately keeps only Secret Scanner required, preserving prior
repositories' workflow. License Checker is enabled explicitly in the supplied
two-policy configuration; it is not silently imposed on existing projects.

Build produces:

- target/bin/moonvcs-default-policy.json: schema 2, scanner only.
- target/bin/moonvcs-multi-policy.json: schema 2, scanner then license-check.

To enable both in a repository, the trusted configuration authority copies the
second file to .moonvcs/policies.json. Absolute runtime paths and module pins are
already filled by the installed Host.

Schema 2 adds required[].granted_capabilities and limits.max_log_bytes.
allowed_capabilities is now an overall ceiling, not an implicit grant to every
plugin. Missing per-plugin grants in schema 2 fail closed. Schema 1 remains
readable: missing plugin grants inherit its old global grant list, preserving
the old semantics; missing log budget defaults to 65,536 bytes. To migrate,
enumerate each plugin's approved grants, add a log budget, then set schema to 2.
Never approve requests automatically from a third-party manifest.

WIT and guest binaries need no migration. Hello and the adversarial fixture
actually inspect commit messages, so their manifests/configs now explicitly
request/grant commit_metadata.read. Previously that metadata was delivered
without a capability. Old custom configurations for those plugins must
deliberately add the grant; lack of it fails closed. Scanner needs no metadata
grant. Downstream consumers of Host JSON should accept status warning with
exit 0; old non-warning results retain their status/exit codes.

Default budgets: 50,000,000 fuel, 1,000 ms epoch timeout, 32 MiB single linear
memory, 1 MiB logical candidate input, 64 KiB serialized output and 16 KiB
diagnostic text/child-stderr log budget. See the [threat model](THREAT_MODEL.md)
for scope, import audit and remaining JIT/OS/TOCTOU risks.
