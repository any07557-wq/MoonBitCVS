#!/usr/bin/env bash
set -euo pipefail

MOONVCS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOONVCS_HOST="$MOONVCS_ROOT/host/target/debug/moonvcs-policy-host"

"$MOONVCS_ROOT/scripts/test.sh"
pushd "$MOONVCS_ROOT" >/dev/null
echo "Clean candidate:"
"$MOONVCS_HOST" --file examples/clean.txt
echo "Candidate containing a simulated secret:"
set +e
"$MOONVCS_HOST" --file examples/contains-secret.txt
MOONVCS_REJECT_CODE=$?
set -e
popd >/dev/null
[[ $MOONVCS_REJECT_CODE -eq 2 ]]
