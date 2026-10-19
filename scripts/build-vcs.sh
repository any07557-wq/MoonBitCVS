#!/usr/bin/env bash
set -euo pipefail

MOONVCS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOONVCS_MOON="${MOONVCS_MOON:-$(command -v moon || true)}"
[[ -x "$MOONVCS_MOON" ]] || { echo "moon was not found" >&2; exit 1; }

"$MOONVCS_ROOT/scripts/build-policy-runtime.sh"

pushd "$MOONVCS_ROOT/vcs" >/dev/null
"$MOONVCS_MOON" fmt --check
"$MOONVCS_MOON" check --target native --deny-warn
"$MOONVCS_MOON" test --target native --deny-warn
"$MOONVCS_MOON" build --target native --release --deny-warn
popd >/dev/null

mkdir -p "$MOONVCS_ROOT/target/bin"
"$MOONVCS_ROOT/scripts/install-runtime-file.sh" \
  "$MOONVCS_ROOT/vcs/_build/native/release/build/cmd/main/main.exe" \
  "$MOONVCS_ROOT/target/bin/moonvcs" 0755
"$MOONVCS_ROOT/scripts/install-runtime-file.sh" \
  "$MOONVCS_ROOT/vcs/_build/native/release/build/cmd/bypass-client/bypass-client.exe" \
  "$MOONVCS_ROOT/target/bin/moonvcs-bypass-client" 0755
echo "built target/bin/moonvcs"
