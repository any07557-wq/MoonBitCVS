#!/usr/bin/env bash
# One fail-closed integration entry; expensive benchmark/clean rebuild are explicit.
set -euo pipefail
MOONVCS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MOONVCS_REPORTS="$MOONVCS_ROOT/target/reports"
MOONVCS_RUN_BENCHMARK=false
MOONVCS_RUN_CLEAN=false
for MOONVCS_OPTION in "$@"; do
  case "$MOONVCS_OPTION" in
    --benchmark) MOONVCS_RUN_BENCHMARK=true ;;
    --clean-build) MOONVCS_RUN_CLEAN=true ;;
    *) echo 'Usage: scripts/verify.sh [--benchmark] [--clean-build]' >&2; exit 1 ;;
  esac
done
mkdir -p "$MOONVCS_REPORTS"
MOONVCS_STAGE_RESULTS="$(mktemp "$MOONVCS_REPORTS/.phase7-stages.XXXXXX")"
MOONVCS_VERIFY_STARTED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
finish() {
  local code=$?
  python3 - "$MOONVCS_STAGE_RESULTS" "$MOONVCS_REPORTS/phase7-verify.json" \
    "$MOONVCS_VERIFY_STARTED" "$code" "$MOONVCS_RUN_BENCHMARK" "$MOONVCS_RUN_CLEAN" <<'PY'
import json
from pathlib import Path
import sys
source, destination, started, code, benchmark, clean = sys.argv[1:]
stages = []
for line in Path(source).read_text().splitlines():
    name, elapsed, status = line.split("\t")
    stages.append({"stage": name, "seconds": int(elapsed), "exit": int(status), "log": f"phase7-{name}.log"})
Path(destination).write_text(json.dumps({
    "schema": 1, "started_utc": started, "exit": int(code), "stages": stages,
    "benchmark_requested": benchmark == "true", "clean_build_requested": clean == "true",
    "unrequested_optional_stages": [name for name, flag in [("benchmark", benchmark), ("clean-build", clean)] if flag != "true"],
}, indent=2) + "\n")
PY
  rm -f -- "$MOONVCS_STAGE_RESULTS"
}
trap finish EXIT
run_stage() {
  local name="$1"
  shift
  local started=$SECONDS
  local code
  echo "Phase 7: $name"
  set +e
  "$@" 2>&1 | tee "$MOONVCS_REPORTS/phase7-$name.log"
  code=${PIPESTATUS[0]}
  set -e
  printf '%s\t%s\t%s\n' "$name" "$((SECONDS - started))" "$code" >>"$MOONVCS_STAGE_RESULTS"
  return "$code"
}
repeat_smoke() {
  local repetition
  for repetition in 1 2; do
    echo "Repeat receive smoke: $repetition of 2"
    "$MOONVCS_ROOT/scripts/test-receive.sh" --built || return "$?"
  done
}
run_stage regression "$MOONVCS_ROOT/scripts/test.sh"
run_stage environment python3 "$MOONVCS_ROOT/scripts/environment.py"
run_stage repeat-smoke repeat_smoke
if "$MOONVCS_RUN_CLEAN"; then
  run_stage clean-build "$MOONVCS_ROOT/scripts/clean-build.sh"
fi
if "$MOONVCS_RUN_BENCHMARK"; then
  run_stage benchmark python3 "$MOONVCS_ROOT/scripts/benchmark.py"
fi
echo "Phase-7 requested verification stages passed. Reports: $MOONVCS_REPORTS"
