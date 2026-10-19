#!/usr/bin/env bash
set -euo pipefail

MOONVCS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOONVCS_MOON="${MOONVCS_MOON:-$(command -v moon || true)}"
if [[ -z "${MOONVCS_WIT_BINDGEN:-}" ]]; then
  MOONVCS_WIT_BINDGEN="$MOONVCS_ROOT/.toolchains/cargo/bin/wit-bindgen"
  [[ -x "$MOONVCS_WIT_BINDGEN" ]] || MOONVCS_WIT_BINDGEN="$(command -v wit-bindgen || true)"
fi
MOONVCS_BINDINGS_LOCK="$MOONVCS_ROOT/wit/bindings.lock"
[[ -x "$MOONVCS_MOON" ]] || { echo "moon was not found" >&2; exit 1; }
[[ -x "$MOONVCS_WIT_BINDGEN" ]] || { echo "wit-bindgen was not found" >&2; exit 1; }

MOONVCS_WIT_DIGEST="$(sha256sum "$MOONVCS_ROOT/wit/policy.wit" | awk '{print $1}')"
MOONVCS_GENERATOR_VERSION="$($MOONVCS_WIT_BINDGEN --version)"
MOONVCS_LOCKED_WIT_DIGEST="$(awk -F\" '/^wit_sha256/ {print $2}' "$MOONVCS_BINDINGS_LOCK" 2>/dev/null || true)"
MOONVCS_LOCKED_GENERATOR="$(awk -F\" '/^generator/ {print $2}' "$MOONVCS_BINDINGS_LOCK" 2>/dev/null || true)"

if [[ "${MOONVCS_FORCE_REGENERATE:-0}" != "1" \
  && "$MOONVCS_WIT_DIGEST" == "$MOONVCS_LOCKED_WIT_DIGEST" \
  && "$MOONVCS_GENERATOR_VERSION" == "$MOONVCS_LOCKED_GENERATOR" \
  && -f "$MOONVCS_ROOT/plugins/secret-scanner/gen/ffi.mbt" \
  && -f "$MOONVCS_ROOT/plugins/hello-policy/gen/ffi.mbt" \
  && -f "$MOONVCS_ROOT/plugins/adversarial-fixture/gen/ffi.mbt" \
  && -f "$MOONVCS_ROOT/plugins/license-check/gen/ffi.mbt" \
  && -f "$MOONVCS_ROOT/plugins/restricted-plugin/gen/ffi.mbt" ]]; then
  echo "checked-in MoonBit bindings already match wit/bindings.lock"
  exit 0
fi

generate_plugin() {
  local plugin="$1"
  local project_name="$2"
  local plugin_root="$MOONVCS_ROOT/plugins/$plugin"
  local evaluator_pkg="$plugin_root/gen/interface/moonvcs/policy/evaluator/moon.pkg"

  "$MOONVCS_WIT_BINDGEN" moonbit "$MOONVCS_ROOT/wit/policy.wit" \
    --out-dir "$plugin_root" \
    --project-name "$project_name" \
    --derive-debug \
    --derive-eq \
    --derive-error \
    --ignore-stub

  # wit-bindgen emits runtime helper calls resolved by the Wasm linker. Accept
  # either spelling used by supported MoonBit/wit-bindgen toolchain versions.
  if ! grep -Eq 'invalid_inline_wasm|warnings = "-44"' "$evaluator_pkg"; then
    printf '%s\n' \
      '// wit-bindgen runtime helpers are resolved by the Wasm linker.' \
      'warnings = "-invalid_inline_wasm"' >>"$evaluator_pkg"
  fi

  pushd "$plugin_root" >/dev/null
  "$MOONVCS_MOON" fmt
  "$MOONVCS_MOON" check --target wasm
  popd >/dev/null
}

generate_plugin secret-scanner moonvcs/secret-scanner
generate_plugin hello-policy moonvcs/hello-policy
generate_plugin adversarial-fixture moonvcs/adversarial-fixture
generate_plugin license-check moonvcs/license-check
generate_plugin restricted-plugin moonvcs/restricted-plugin

echo "bindings regenerated; review generated glue and component digest changes" >&2
echo "after review, update wit/bindings.lock if its inputs changed" >&2
