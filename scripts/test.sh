#!/usr/bin/env bash
set -euo pipefail

MOONVCS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -x "$MOONVCS_ROOT/.toolchains/cargo/bin/cargo" ]]; then
  export RUSTUP_HOME="$MOONVCS_ROOT/.toolchains/rustup"
  export CARGO_HOME="$MOONVCS_ROOT/.toolchains/cargo"
  MOONVCS_CARGO="$CARGO_HOME/bin/cargo"
else
  MOONVCS_CARGO="${MOONVCS_CARGO:-$(command -v cargo || true)}"
fi
[[ -x "$MOONVCS_CARGO" ]] || { echo "cargo was not found" >&2; exit 1; }
if [[ -z "${MOONVCS_WASM_TOOLS:-}" ]]; then
  MOONVCS_WASM_TOOLS="$MOONVCS_ROOT/.toolchains/cargo/bin/wasm-tools"
  [[ -x "$MOONVCS_WASM_TOOLS" ]] || MOONVCS_WASM_TOOLS="$(command -v wasm-tools || true)"
fi
[[ -x "$MOONVCS_WASM_TOOLS" ]] || { echo "wasm-tools was not found" >&2; exit 1; }

"$MOONVCS_ROOT/scripts/build-component.sh"
"$MOONVCS_CARGO" fmt --manifest-path "$MOONVCS_ROOT/host/Cargo.toml" -- --check
"$MOONVCS_CARGO" test --locked --manifest-path "$MOONVCS_ROOT/host/Cargo.toml"
"$MOONVCS_CARGO" build --locked --manifest-path "$MOONVCS_ROOT/host/Cargo.toml"

MOONVCS_HOST="$MOONVCS_ROOT/host/target/debug/moonvcs-policy-host"
pushd "$MOONVCS_ROOT" >/dev/null

MOONVCS_PASS_OUTPUT="$($MOONVCS_HOST --file examples/clean.txt)"
[[ "$MOONVCS_PASS_OUTPUT" == *'"status":"pass"'* ]]
MOONVCS_HELLO_PASS_OUTPUT="$($MOONVCS_HOST \
  --component target/components/hello-policy.component.wasm \
  --manifest plugins/hello-policy/plugin.toml \
  --policy examples/hello-policy.toml \
  --message "add safe configuration" \
  --file examples/clean.txt)"
[[ "$MOONVCS_HELLO_PASS_OUTPUT" == *'"status":"pass"'* ]]
MOONVCS_HELLO_INTERFACE="$($MOONVCS_WASM_TOOLS component wit \
  target/components/hello-policy.component.wasm)"
[[ "$MOONVCS_HELLO_INTERFACE" == *'export moonvcs:policy/evaluator@0.1.0'* ]]
[[ "$MOONVCS_HELLO_INTERFACE" != *'import '* ]]

set +e
MOONVCS_REJECT_OUTPUT="$($MOONVCS_HOST --file examples/contains-secret.txt 2>&1)"
MOONVCS_REJECT_CODE=$?
MOONVCS_DENIED_OUTPUT="$($MOONVCS_HOST \
  --policy examples/repository-policy-deny-content.toml \
  --file examples/clean.txt 2>&1)"
MOONVCS_DENIED_CODE=$?
MOONVCS_HELLO_REJECT_OUTPUT="$($MOONVCS_HOST \
  --component target/components/hello-policy.component.wasm \
  --manifest plugins/hello-policy/plugin.toml \
  --policy examples/hello-policy.toml \
  --message "commit forbidden-demo" \
  --file examples/clean.txt 2>&1)"
MOONVCS_HELLO_REJECT_CODE=$?
MOONVCS_HELLO_INVALID_OUTPUT="$($MOONVCS_HOST \
  --component target/components/hello-policy.component.wasm \
  --manifest plugins/hello-policy/plugin.toml \
  --policy examples/hello-policy.toml \
  --message "" \
  --file examples/clean.txt 2>&1)"
MOONVCS_HELLO_INVALID_CODE=$?
MOONVCS_INFINITE_OUTPUT="$($MOONVCS_HOST \
  --component target/components/adversarial-fixture.component.wasm \
  --manifest plugins/adversarial-fixture/plugin.toml \
  --policy examples/adversarial-fuel.toml \
  --message fixture:infinite-loop \
  --file examples/clean.txt 2>&1)"
MOONVCS_INFINITE_CODE=$?
MOONVCS_MEMORY_OUTPUT="$($MOONVCS_HOST \
  --component target/components/adversarial-fixture.component.wasm \
  --manifest plugins/adversarial-fixture/plugin.toml \
  --policy examples/adversarial-memory.toml \
  --message fixture:memory-growth \
  --file examples/clean.txt 2>&1)"
MOONVCS_MEMORY_CODE=$?
MOONVCS_TRAP_OUTPUT="$($MOONVCS_HOST \
  --component target/components/adversarial-fixture.component.wasm \
  --manifest plugins/adversarial-fixture/plugin.toml \
  --policy examples/adversarial-trap.toml \
  --message fixture:trap \
  --file examples/clean.txt 2>&1)"
MOONVCS_TRAP_CODE=$?
MOONVCS_OUTPUT_OUTPUT="$($MOONVCS_HOST \
  --component target/components/adversarial-fixture.component.wasm \
  --manifest plugins/adversarial-fixture/plugin.toml \
  --policy examples/adversarial-output.toml \
  --message fixture:oversized-output \
  --file examples/clean.txt 2>&1)"
MOONVCS_OUTPUT_CODE=$?
set -e

[[ $MOONVCS_REJECT_CODE -eq 2 ]]
[[ "$MOONVCS_REJECT_OUTPUT" == *'"status":"reject"'* ]]
[[ "$MOONVCS_REJECT_OUTPUT" != *'demo-only-value'* ]]
[[ $MOONVCS_DENIED_CODE -eq 3 ]]
[[ "$MOONVCS_DENIED_OUTPUT" == *'not granted by the repository'* ]]
[[ $MOONVCS_HELLO_REJECT_CODE -eq 2 ]]
[[ "$MOONVCS_HELLO_REJECT_OUTPUT" == *'"status":"reject"'* ]]
[[ "$MOONVCS_HELLO_REJECT_OUTPUT" == *'"message":"forbidden-demo detected"'* ]]
[[ $MOONVCS_HELLO_INVALID_CODE -eq 3 ]]
[[ "$MOONVCS_HELLO_INVALID_OUTPUT" == *'plugin returned an error'* ]]
[[ $MOONVCS_INFINITE_CODE -eq 3 ]]
[[ "$MOONVCS_INFINITE_OUTPUT" == *'all fuel consumed by WebAssembly'* ]]
[[ $MOONVCS_MEMORY_CODE -eq 3 ]]
[[ "$MOONVCS_MEMORY_OUTPUT" == *'memory growth denied by configured 4194304-byte limit'* ]]
[[ $MOONVCS_TRAP_CODE -eq 3 ]]
[[ "$MOONVCS_TRAP_OUTPUT" == *'wasm `unreachable` instruction executed'* ]]
[[ $MOONVCS_OUTPUT_CODE -eq 3 ]]
[[ "$MOONVCS_OUTPUT_OUTPUT" == *'policy output exceeds 1024 bytes'* ]]

for adversarial_output in \
  "$MOONVCS_INFINITE_OUTPUT" \
  "$MOONVCS_MEMORY_OUTPUT" \
  "$MOONVCS_TRAP_OUTPUT" \
  "$MOONVCS_OUTPUT_OUTPUT"; do
  [[ "$adversarial_output" != *'"status":"pass"'* ]]
done

popd >/dev/null
"$MOONVCS_ROOT/scripts/test-vcs.sh"
"$MOONVCS_ROOT/scripts/test-policy.sh" --built
"$MOONVCS_ROOT/scripts/test-security.sh" --built
"$MOONVCS_ROOT/scripts/demo-lazy.sh" --built
"$MOONVCS_ROOT/scripts/demo-receive.sh" --built
python3 "$MOONVCS_ROOT/tests/system_audit.py"
python3 "$MOONVCS_ROOT/tests/verification_harness.py"
python3 "$MOONVCS_ROOT/tests/staging_concurrency.py"
python3 "$MOONVCS_ROOT/tests/recovery_audit.py"
python3 "$MOONVCS_ROOT/tests/lazy_read_audit.py"
python3 "$MOONVCS_ROOT/tests/toolchain_archive_audit.py"
python3 "$MOONVCS_ROOT/tests/diff_audit.py"
python3 "$MOONVCS_ROOT/tests/branch_switch_audit.py"
python3 "$MOONVCS_ROOT/tests/submission_audit.py"
"$MOONVCS_ROOT/scripts/test-hackathon.sh" --built
printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n' \
  "$MOONVCS_PASS_OUTPUT" \
  "$MOONVCS_HELLO_PASS_OUTPUT" \
  "$MOONVCS_REJECT_OUTPUT" \
  "$MOONVCS_DENIED_OUTPUT" \
  "$MOONVCS_HELLO_REJECT_OUTPUT" \
  "$MOONVCS_HELLO_INVALID_OUTPUT" \
  "$MOONVCS_INFINITE_OUTPUT" \
  "$MOONVCS_MEMORY_OUTPUT" \
  "$MOONVCS_TRAP_OUTPUT" \
  "$MOONVCS_OUTPUT_OUTPUT"
echo "MoonVCS phases 1–8 tests passed"
