#!/usr/bin/env bash
set -euo pipefail

MOONVCS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$MOONVCS_ROOT/scripts/build-vcs.sh"
MOONVCS_BIN="$MOONVCS_ROOT/target/bin/moonvcs"
MOONVCS_DEMO_ROOT="$(mktemp -d /tmp/moonvcs-policy-demo.XXXXXX)"
pushd "$MOONVCS_DEMO_ROOT" >/dev/null
"$MOONVCS_BIN" init
printf 'MOONVCS_API_KEY=harmless-demo-placeholder\n' >config.env
"$MOONVCS_BIN" add config.env
set +e
"$MOONVCS_BIN" commit -m "add config"
MOONVCS_REJECT_CODE=$?
set -e
[[ "$MOONVCS_REJECT_CODE" -eq 2 ]]
printf 'APP_MODE=demo\n' >config.env
"$MOONVCS_BIN" add config.env
"$MOONVCS_BIN" commit -m "add safe config"
"$MOONVCS_BIN" log
popd >/dev/null
echo "Demo repository retained at $MOONVCS_DEMO_ROOT"
