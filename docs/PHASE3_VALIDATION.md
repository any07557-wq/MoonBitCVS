# Phase 3: Required Policies and Secret Scanner

Verified on 2026-10-17, Linux x86_64/WSL2, using the pinned phase-1/2 toolchain.

## Result

The actual native MoonBit commit path invokes the MoonBit Wasm Secret Scanner
through Wasmtime before storing a Commit or publishing a Ref:

    Stage -> CommitCandidate -> MoonBit Policy Engine -> stdin JSON
                                                       |
                                          Rust Host + pinned Wasm component
                                                       |
                                           MoonBit Secret Scanner
                                                       |
                                  Accept / Reject(diagnostics) / Error
                                                       |
                      optional additional validator -> Commit -> Ref CAS

New repositories require Secret Scanner 0.2.0 by default. Both public commit
APIs execute the required gate; a caller-supplied validator is additional and
cannot replace it. Low-level ref publication is package-private. There is no
CLI skip-policy flag or environment-variable bypass.

## Delivered implementation

| Responsibility | Files |
|---|---|
| Engine decisions, diagnostics, configuration, subprocess adapter | vcs/policy_engine.mbt |
| Config ownership, mandatory gate, frozen commit payload, Ref CAS | vcs/repository.mbt |
| CLI messages and policy exit codes | vcs/cmd/main/main.mbt, vcs/cli.mbt |
| Bounded stdin transport, identity/capability checks and Wasmtime | host/src/main.rs |
| Secret detection and custom-rule interpretation | plugins/secret-scanner/gen/interface/moonvcs/policy/evaluator/stub.mbt |
| Real-engine native integration tests | vcs/policy_integration_wbtest.mbt |
| Runtime build/install | scripts/build-policy-runtime.sh, scripts/build-vcs.sh |
| CLI assertions and demo | scripts/test-policy.sh, scripts/demo-policy.sh |
| Config template | examples/required-policies.json |

The engine operates on a candidate and an explicit PolicyContext. It does not
read working files, store objects or update refs. Repository orchestration owns
configuration loading. Rust provides the runtime; all detection rules execute
inside the MoonBit component.

## Configuration and identity

The build installs the native CLI, Host and generated default configuration
under target/bin, and verified components/manifests under target/components.
The Host generates defaults from the actual verified Scanner manifest and
component. Init copies them into .moonvcs/policies.json. Paths are absolute so
commits work from any directory. The example configuration uses placeholder
paths; use generated defaults for the demo.

For an existing phase-2 repository without policy metadata, first build the
runtime, review its generated defaults, then explicitly install the policy:

    cp /path/to/MoonBit_Program/target/bin/moonvcs-default-policy.json \
      /path/to/existing-repository/.moonvcs/policies.json

Review the paths and grants before copying. This preserves existing objects and
refs and adds the mandatory gate to subsequent commits. A repository with an
older pin must also review/re-pin an intentional Scanner upgrade.

Each required entry binds name, version, module_digest, component and manifest.
The Host compares the pin against the manifest, then hashes the loaded component
against that pin. Replacing the manifest and component together cannot silently
change a repository's pinned program. Distribution upgrades require an explicit
trusted repository pin update; commit never rewrites pins.

Scanner 0.2.0 SHA-256:

    3743537dad366b6af66d0b36d27eb77f47bee2b4669475e2d4a7b0fca5023cf2

Required policies execute in configuration order and must all Pass. Reject
diagnostics accumulate; any execution failure fails closed. An explicitly empty
required list is a trusted administrator choice, used for isolated Core tests.
Missing/malformed config is an error, never an implicit empty list.
The repository owner can deliberately edit trusted metadata; remote enforcement
remains a separate future trust boundary.

## Contracts and data handling

The MoonBit EngineDecision has Accept, Reject(Array[PolicyDiagnostic]) and
EngineError(String) variants. Diagnostics contain plugin, rule, file, optional
line, severity and message. Host JSON retains code/path aliases for phase-1
compatibility. Line is currently null because WIT v1 has no line-number field.
File/rule location is real and tested. Scanner messages use the constant
"suspicious credential" and never embed matched values.

The Host's new --request-stdin mode accepts a bounded JSON envelope containing
the expected plugin, capability grants/budgets, custom rules, and candidate
message, parent/tree IDs, paths and raw bytes as integer arrays. It never rereads
candidate paths. The engine uses pipes rather than a shell or secret-bearing
command-line arguments; child environment inheritance is disabled.

The transport limit is 16 MiB and configured candidate input is capped at 1 MiB.
Wasmtime preserves the empty linker, no WASI, fuel, epoch, memory and output
limits. An outer subprocess timeout adds 15 seconds to the configured guest
timeout for startup/compilation. Host stderr and raw request bodies are not
printed by the engine.

Plugins without granted staged_content.read receive an empty file list, even
when the candidate contains files. This is tested for a message-only policy.

A real integration test exposed MoonBit's JSON Option convention: derived
Option[String] expects a singleton array, while Host file fields are nullable
strings. PolicyDiagnostic therefore has explicit conversion for nullable
file/line fields.

## Rules and unchanged WIT

| Family | MVP behavior |
|---|---|
| Simulated API key | MOONVCS_API_KEY= marker |
| Simulated access token | MOONVCS_ACCESS_TOKEN= and existing MOONVCS_TEST_TOKEN= markers |
| Private-key header | generic, RSA, EC and OpenSSH private-key BEGIN headers |
| Password | nonempty password, passwd or db_password key, case-insensitive; line-oriented =/: assignments and nested JSON |
| Custom | nonempty configured UTF-8 literal; diagnostic ID custom.<id> |

Custom rules are additive and cannot disable built-ins. At most 64 rules are
accepted: IDs have 1–64 lowercase ASCII letters/digits/dots/hyphens, and literals
have 1–256 UTF-8 bytes. Invalid config returns plugin Error. Matching is literal,
not regex. These MVP rules do not provide comprehensive DLP/secret detection.

WIT bytes are unchanged, with SHA-256:

    4b3ff703ed44a679ea8b689e0977867505ec602d159d2f57f9c4773bccc8725d

To deliver custom rules without inventing a WIT field, the Host injects one
reserved virtual staged-file record at .moonvcs/plugin-config/v1.json, containing
a JSON custom_rules array. Core forbids staging .moonvcs; stdin transport rejects
supplied metadata paths. The Scanner consumes this record as configuration and
excludes it from content scanning. Other plugins must explicitly support this
convention. No filesystem import or new capability is introduced.

## Rejection and recovery

Reject, Error, missing runtime/plugin, identity mismatch, Trap and resource
exhaustion stop the commit before writing its Commit object. HEAD, Stage and
working files remain unchanged. CLI exit codes are 2 for Reject and 3 for
required-policy Error. Blobs/Trees may already exist from staging/candidate
construction and remain recoverable.

Repairing working files does not repair Stage: run add again. After all required
policies and the additional validator accept, Core uses its frozen candidate
payload and existing Ref CAS. Configuration is reread before writing the Commit
to detect an in-flight change. Failed Ref CAS can leave an unreferenced,
policy-approved Commit.

## Reproduce and evidence

From the project root:

    export PATH="$HOME/.moon/bin:$PATH"
    ./scripts/test-policy.sh
    ./scripts/test.sh
    ./scripts/demo-policy.sh

The first script builds and tests the whole policy-connected CLI; the second
runs the complete regression suite. Test fixtures are removed after tests.
The demo retains its temporary repository for inspection.

There are 22 native tests (16 previous Core tests plus 6 real-Wasm integrations),
13 plugin tests (8 Scanner, 3 Hello Policy, 2 adversarial), and 8 Rust Host tests.
Native code is built/tested with --deny-warn. Component imports and digests are
checked by the existing build/regression scripts.

| Acceptance | Actual evidence |
|---|---|
| Clean commit succeeds | native real-engine and CLI tests |
| Secret commit fails | API-key/token CLI fixture exits 2 |
| Repair then succeeds | working-only repair still rejects; re-add then commits |
| Missing required policy | missing component/Host/config and pin mismatches fail closed |
| Plugin exception preserves HEAD | real adversarial Trap, infinite loop and memory growth |
| Multiple-file location | config.env and nested/access.env CLI output; native password/custom-rule diagnostics |
| Internal bypass blocked | direct commit and commit_with_validator(Mock Pass) both reject |
| No full key in logs | stdout/stderr and rejection reasons checked for fixture-value absence |
| No rejected Commit written | expected object ID absent; independent CLI object-type counts unchanged |
| Version/content binding | name/version/digest substitution rejected |
| Every required policy enforced | Scanner Pass cannot override Hello Policy Reject |
| Sandbox regression | existing fuel/memory/Trap/output checks remain in the full suite |

The demo's policy output is:

    Commit rejected
    Policy: secret-scanner
    File: config.env | Rule: secret.api-key | Severity: error
    Reason: suspicious credential
    ...
    Policy passed
    Commit created
    Committed <actual SHA-256 ID>

IDs/timestamps vary per run. All fixture credentials are harmless.

## Limits

Configuration, Host and approved manifests are local trusted inputs. There are
no signed policies, remote receive enforcement or organization-wide policy
administration. On-commit is integrated; on-receive orchestration is future work.
Assets must remain at configured paths. The Host is a separate native child
process, but it has no OS resource sandbox; Wasmtime limits do not include all
Host/JIT allocations. Filesystem races, staging concurrency and durability limits
remain documented in [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md).
