#!/usr/bin/env bash
set -euo pipefail
MOONVCS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -x "$MOONVCS_ROOT/.toolchains/cargo/bin/cargo" ]]; then
  export RUSTUP_HOME="$MOONVCS_ROOT/.toolchains/rustup"
  export CARGO_HOME="$MOONVCS_ROOT/.toolchains/cargo"
  MOONVCS_CARGO="${MOONVCS_CARGO:-$CARGO_HOME/bin/cargo}"
else
  MOONVCS_CARGO="${MOONVCS_CARGO:-$(command -v cargo || true)}"
fi
if [[ -z "${MOONVCS_WASM_TOOLS:-}" ]]; then
  MOONVCS_WASM_TOOLS="$MOONVCS_ROOT/.toolchains/cargo/bin/wasm-tools"
  [[ -x "$MOONVCS_WASM_TOOLS" ]] || MOONVCS_WASM_TOOLS="$(command -v wasm-tools || true)"
fi
[[ -x "$MOONVCS_WASM_TOOLS" ]] || { echo "wasm-tools was not found" >&2; exit 1; }
if [[ "$#" -eq 0 || "$1" != "--built" ]]; then
  "$MOONVCS_ROOT/scripts/build-vcs.sh"
  [[ -x "$MOONVCS_CARGO" ]] || { echo "cargo was not found" >&2; exit 1; }
  "$MOONVCS_CARGO" test --locked \
    --manifest-path "$MOONVCS_ROOT/host/Cargo.toml"
fi
MOONVCS_BIN="$MOONVCS_ROOT/target/bin/moonvcs"
MOONVCS_HOST="$MOONVCS_ROOT/target/bin/moonvcs-policy-host"
MOONVCS_TEST_ROOT="$(mktemp -d /tmp/moonvcs-security.XXXXXX)"
cleanup() {
  if [[ "$MOONVCS_TEST_ROOT" == /tmp/moonvcs-security.* && -d "$MOONVCS_TEST_ROOT" ]]; then
    rm -rf -- "$MOONVCS_TEST_ROOT"
  fi
}
trap cleanup EXIT
mkdir -p "$MOONVCS_TEST_ROOT/repository" "$MOONVCS_TEST_ROOT/mock-home/.ssh"
printf 'harmless-simulated-private-resource\n' >"$MOONVCS_TEST_ROOT/mock-home/.ssh/id_demo"
MOONVCS_MOCK_DIGEST="$(sha256sum "$MOONVCS_TEST_ROOT/mock-home/.ssh/id_demo")"
pushd "$MOONVCS_TEST_ROOT/repository" >/dev/null
"$MOONVCS_BIN" init
cp "$MOONVCS_ROOT/target/bin/moonvcs-multi-policy.json" .moonvcs/policies.json
printf 'MOONVCS_API_KEY=harmless-security-test-value\n' >main.mbt
"$MOONVCS_BIN" add main.mbt >/dev/null
MOONVCS_INDEX="$(sha256sum .moonvcs/index)"
set +e
MOONVCS_OUTPUT="$("$MOONVCS_BIN" commit -m blocked 2>&1)"
MOONVCS_CODE=$?
set -e
[[ "$MOONVCS_CODE" -eq 2 ]]
[[ "$MOONVCS_OUTPUT" == *'Policy: secret-scanner'* ]]
[[ "$MOONVCS_OUTPUT" == *'Policy: license-check'* ]]
[[ "$MOONVCS_OUTPUT" != *'harmless-security-test-value'* ]]
[[ "$(sha256sum .moonvcs/index)" == "$MOONVCS_INDEX" ]]
[[ ! -e .moonvcs/refs/heads/main ]]
printf '%s\n' "$MOONVCS_OUTPUT"
printf '// SPDX-License-Identifier: Apache-2.0\n' >main.mbt
printf 'Demonstration license fixture, not a legal license recommendation.\n' >LICENSE
"$MOONVCS_BIN" add main.mbt LICENSE >/dev/null
MOONVCS_OUTPUT="$("$MOONVCS_BIN" commit -m repaired)"
[[ "$MOONVCS_OUTPUT" == *'Severity: warning'* ]]
[[ "$MOONVCS_OUTPUT" == *'Commit created'* ]]
printf '%s\n' "$MOONVCS_OUTPUT"
MOONVCS_HEAD="$(cat .moonvcs/refs/heads/main)"

# Static symlink escape into a temporary mock HOME; never touch real HOME.
ln -s ../mock-home/.ssh/id_demo escape
set +e
MOONVCS_OUTPUT="$("$MOONVCS_HOST" \
  --component "$MOONVCS_ROOT/target/components/restricted-plugin.component.wasm" \
  --manifest "$MOONVCS_ROOT/plugins/restricted-plugin/plugin.toml" \
  --policy "$MOONVCS_ROOT/examples/repository-policy.toml" --file escape 2>&1)"
MOONVCS_CODE=$?
set -e
[[ "$MOONVCS_CODE" -eq 3 ]]
[[ "$MOONVCS_OUTPUT" == *'symlinks are forbidden'* ]]
[[ "$MOONVCS_OUTPUT" != *'harmless-simulated-private-resource'* ]]
printf '%s\n' "$MOONVCS_OUTPUT"

# Even a correctly digested component cannot obtain a WASI filesystem import.
"$MOONVCS_WASM_TOOLS" parse "$MOONVCS_ROOT/tests/fixtures/forbidden-wasi.wat" \
  -o "$MOONVCS_TEST_ROOT/forbidden.wasm"
MOONVCS_DIGEST="$(sha256sum "$MOONVCS_TEST_ROOT/forbidden.wasm" | awk '{print $1}')"
sed "s/sha256:[0-9a-f]*/sha256:$MOONVCS_DIGEST/" \
  "$MOONVCS_ROOT/plugins/restricted-plugin/plugin.toml" >"$MOONVCS_TEST_ROOT/forbidden.toml"
printf 'harmless-allowed-content' >allowed.txt
set +e
MOONVCS_OUTPUT="$("$MOONVCS_HOST" --component "$MOONVCS_TEST_ROOT/forbidden.wasm" \
  --manifest "$MOONVCS_TEST_ROOT/forbidden.toml" \
  --policy "$MOONVCS_ROOT/examples/repository-policy.toml" --file allowed.txt 2>&1)"
MOONVCS_CODE=$?
set -e
[[ "$MOONVCS_CODE" -eq 3 ]]
[[ "$MOONVCS_OUTPUT" == *'component imports are forbidden'* ]]
[[ "$MOONVCS_OUTPUT" != *'harmless-simulated-private-resource'* ]]
[[ "$(cat .moonvcs/refs/heads/main)" == "$MOONVCS_HEAD" ]]
[[ "$(sha256sum "$MOONVCS_TEST_ROOT/mock-home/.ssh/id_demo")" == "$MOONVCS_MOCK_DIGEST" ]]
printf '%s\n' "$MOONVCS_OUTPUT"
popd >/dev/null
echo "MoonVCS phase-4 security demo passed (only temporary mock resources used)"
