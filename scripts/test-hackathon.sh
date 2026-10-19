#!/usr/bin/env bash
set -euo pipefail
MOONVCS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "$#" -eq 0 || "$1" != "--built" ]]; then
  "$MOONVCS_ROOT/scripts/build-vcs.sh"
fi
MOONVCS_DEMO_TEST="$(mktemp -d /tmp/moonvcs-stage8-test.XXXXXX)"
cleanup() {
  if [[ "$MOONVCS_DEMO_TEST" == /tmp/moonvcs-stage8-test.* && -d "$MOONVCS_DEMO_TEST" ]]; then
    rm -rf -- "$MOONVCS_DEMO_TEST"
  fi
}
trap cleanup EXIT
mkdir -p "$MOONVCS_ROOT/target/reports"
(
  python3 "$MOONVCS_ROOT/scripts/hackathon-demo.py" prepare --workdir "$MOONVCS_DEMO_TEST/prepared" --commits 8
  for MOONVCS_REPETITION in 1 2; do
    echo "Stage-8 real demo repetition: $MOONVCS_REPETITION"
    python3 "$MOONVCS_ROOT/scripts/hackathon-demo.py" run --workdir "$MOONVCS_DEMO_TEST/prepared" --only all
  done
) | tee "$MOONVCS_ROOT/target/reports/phase8-smoke.log"
echo 'MoonVCS stage-8 four-demo repeat smoke passed'
