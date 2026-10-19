#!/usr/bin/env bash
set -euo pipefail

MOONVCS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -x "$MOONVCS_ROOT/.toolchains/cargo/bin/cargo" ]]; then
  export RUSTUP_HOME="$MOONVCS_ROOT/.toolchains/rustup"
  export CARGO_HOME="$MOONVCS_ROOT/.toolchains/cargo"
  MOONVCS_CARGO="${MOONVCS_CARGO:-$CARGO_HOME/bin/cargo}"
else
  MOONVCS_CARGO="${MOONVCS_CARGO:-$(command -v cargo || true)}"
fi
[[ -x "$MOONVCS_CARGO" ]] || { echo "cargo was not found" >&2; exit 1; }

"$MOONVCS_ROOT/scripts/build-component.sh"
"$MOONVCS_CARGO" build --locked --manifest-path "$MOONVCS_ROOT/host/Cargo.toml"
mkdir -p "$MOONVCS_ROOT/target/bin"
"$MOONVCS_ROOT/scripts/install-runtime-file.sh" \
  "$MOONVCS_ROOT/host/target/debug/moonvcs-policy-host" \
  "$MOONVCS_ROOT/target/bin/moonvcs-policy-host" 0755
for MOONVCS_PLUGIN in secret-scanner hello-policy adversarial-fixture license-check restricted-plugin; do
  cp "$MOONVCS_ROOT/plugins/$MOONVCS_PLUGIN/plugin.toml" "$MOONVCS_ROOT/target/components/$MOONVCS_PLUGIN.plugin.toml"
done
"$MOONVCS_ROOT/target/bin/moonvcs-policy-host" --default-config \
  >"$MOONVCS_ROOT/target/bin/moonvcs-default-policy.json"
echo "built required-policy runtime and pinned default configuration"
"$MOONVCS_ROOT/target/bin/moonvcs-policy-host" --multi-policy-config \
  >"$MOONVCS_ROOT/target/bin/moonvcs-multi-policy.json"
