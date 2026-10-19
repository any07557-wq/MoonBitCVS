#!/usr/bin/env bash
set -euo pipefail
MOONVCS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$MOONVCS_ROOT/target/reports"
"$MOONVCS_ROOT/scripts/test-lazy.sh" "$@" |
  tee "$MOONVCS_ROOT/target/reports/phase5-run.log"
echo "Run log: $MOONVCS_ROOT/target/reports/phase5-run.log"
