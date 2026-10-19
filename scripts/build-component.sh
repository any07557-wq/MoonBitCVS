#!/usr/bin/env bash
set -euo pipefail

MOONVCS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOONVCS_MOON="${MOONVCS_MOON:-$(command -v moon || true)}"
if [[ -z "${MOONVCS_WIT_BINDGEN:-}" ]]; then
  MOONVCS_WIT_BINDGEN="$MOONVCS_ROOT/.toolchains/cargo/bin/wit-bindgen"
  [[ -x "$MOONVCS_WIT_BINDGEN" ]] || MOONVCS_WIT_BINDGEN="$(command -v wit-bindgen || true)"
fi
if [[ -z "${MOONVCS_WASM_TOOLS:-}" ]]; then
  MOONVCS_WASM_TOOLS="$MOONVCS_ROOT/.toolchains/cargo/bin/wasm-tools"
  [[ -x "$MOONVCS_WASM_TOOLS" ]] || MOONVCS_WASM_TOOLS="$(command -v wasm-tools || true)"
fi

[[ -x "$MOONVCS_MOON" ]] || { echo "moon was not found" >&2; exit 1; }
[[ -x "$MOONVCS_WIT_BINDGEN" ]] || { echo "wit-bindgen was not found" >&2; exit 1; }
[[ -x "$MOONVCS_WASM_TOOLS" ]] || { echo "wasm-tools was not found" >&2; exit 1; }
[[ "$($MOONVCS_WIT_BINDGEN --version)" == "wit-bindgen-cli 0.63.0" ]] || {
  echo "MoonVCS requires wit-bindgen-cli 0.63.0" >&2
  exit 1
}
[[ "$($MOONVCS_WASM_TOOLS --version)" == "wasm-tools 1.262.0" ]] || {
  echo "MoonVCS requires wasm-tools 1.262.0" >&2
  exit 1
}

mkdir -p "$MOONVCS_ROOT/target/components"

build_plugin() {
  local plugin="$1"
  local plugin_root="$MOONVCS_ROOT/plugins/$plugin"
  local embedded="$MOONVCS_ROOT/target/components/$plugin.embedded.wasm"
  local component="$MOONVCS_ROOT/target/components/$plugin.component.wasm"

  pushd "$plugin_root" >/dev/null
  "$MOONVCS_MOON" check --target wasm
  "$MOONVCS_MOON" test --target wasm
  "$MOONVCS_MOON" build --target wasm --release
  popd >/dev/null

  "$MOONVCS_WASM_TOOLS" component embed \
    "$MOONVCS_ROOT/wit" \
    "$plugin_root/_build/wasm/release/build/gen/gen.wasm" \
    --encoding utf16 \
    --output "$embedded"
  "$MOONVCS_WASM_TOOLS" component new "$embedded" --output "$component"
  "$MOONVCS_WASM_TOOLS" validate --features component-model "$component"

  local actual_digest
  local expected_digest
  actual_digest="sha256:$(sha256sum "$component" | awk '{print $1}')"
  expected_digest="$(awk -F\" '/^module_digest/ {print $2}' "$plugin_root/plugin.toml")"
  [[ "$actual_digest" == "$expected_digest" ]] || {
    echo "$plugin component digest drifted" >&2
    echo "expected: $expected_digest" >&2
    echo "actual:   $actual_digest" >&2
    exit 1
  }

  echo "built $plugin.component.wasm ($actual_digest)"
}

build_plugin secret-scanner
build_plugin hello-policy
build_plugin adversarial-fixture
build_plugin license-check
build_plugin restricted-plugin

# Security fixtures use the exact same WIT; one corrupts the return value,
# the other loops in the initializer before evaluate can run.
for fixture in invalid-result infinite-start; do
  "$MOONVCS_WASM_TOOLS" parse "$MOONVCS_ROOT/tests/fixtures/$fixture.wat" \
    --output "$MOONVCS_ROOT/target/components/$fixture.core.wasm"
  "$MOONVCS_WASM_TOOLS" component embed "$MOONVCS_ROOT/wit" \
    "$MOONVCS_ROOT/target/components/$fixture.core.wasm" --encoding utf16 \
    --output "$MOONVCS_ROOT/target/components/$fixture.embedded.wasm"
  "$MOONVCS_WASM_TOOLS" component new \
    "$MOONVCS_ROOT/target/components/$fixture.embedded.wasm" \
    --output "$MOONVCS_ROOT/target/components/$fixture.component.wasm"
  "$MOONVCS_WASM_TOOLS" validate \
    "$MOONVCS_ROOT/target/components/$fixture.component.wasm"
done
