#!/usr/bin/env bash
# Source-clean rebuild with the installed pinned toolchain/dependency caches.
# This is not a blank-OS installer or a registry availability test.
set -euo pipefail
MOONVCS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$MOONVCS_ROOT/target/reports"
MOONVCS_CLEAN_WORK="$(mktemp -d "$MOONVCS_ROOT/target/phase7-clean.XXXXXX")"
cleanup() {
  if [[ "$MOONVCS_CLEAN_WORK" == "$MOONVCS_ROOT"/target/phase7-clean.* && -d "$MOONVCS_CLEAN_WORK" ]]; then
    rm -rf -- "$MOONVCS_CLEAN_WORK"
  fi
}
trap cleanup EXIT
mkdir "$MOONVCS_CLEAN_WORK/source"
tar -C "$MOONVCS_ROOT" --exclude=_build --exclude=target --exclude=.mooncakes \
  --exclude=__pycache__ --exclude=.toolchains -cf - \
  README.md ARCHITECTURE.md SECURITY.md ROADMAP.md DEMO.md TESTING.md INSTALL.md \
  LICENSE .gitignore .github BRANCH_SWITCH.md docs examples scripts tests vcs plugins wit host |
  tar -C "$MOONVCS_CLEAN_WORK/source" -xf -
[[ ! -e "$MOONVCS_CLEAN_WORK/source/target" ]]
[[ ! -e "$MOONVCS_CLEAN_WORK/source/host/target" ]]
[[ ! -e "$MOONVCS_CLEAN_WORK/source/vcs/_build" ]]
[[ ! -e "$MOONVCS_CLEAN_WORK/source/vcs/.mooncakes" ]]
if [[ -d "$MOONVCS_ROOT/.toolchains" ]]; then
  ln -s "$MOONVCS_ROOT/.toolchains" "$MOONVCS_CLEAN_WORK/source/.toolchains"
fi
export MOONVCS_MOON="${MOONVCS_MOON:-$(command -v moon || true)}"
export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-2}"
export CARGO_NET_OFFLINE=true
export CARGO_TARGET_DIR="$MOONVCS_CLEAN_WORK/source/host/target"
MOONVCS_STARTED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
MOONVCS_STARTED_SECONDS=$SECONDS
set +e
(
  echo 'Source-clean build: no copied outputs, project dependencies or runtime binaries'
  echo 'Uses installed compiler/tool binaries and global pinned dependency caches; Cargo is offline'
  cd "$MOONVCS_CLEAN_WORK/source"
  ./scripts/test.sh
) 2>&1 | tee "$MOONVCS_ROOT/target/reports/phase7-clean-build.log"
MOONVCS_CLEAN_CODE=${PIPESTATUS[0]}
set -e
python3 - "$MOONVCS_ROOT/target/reports/phase7-clean-build.json" \
  "$MOONVCS_STARTED" "$((SECONDS - MOONVCS_STARTED_SECONDS))" "$MOONVCS_CLEAN_CODE" <<'PY'
import json
import sys
from pathlib import Path
path, started, elapsed, code = sys.argv[1:]
Path(path).write_text(json.dumps({
    "schema": 1, "started_utc": started, "elapsed_seconds": int(elapsed),
    "exit": int(code), "source_clean": True, "copied_build_artifacts": False,
    "shared_installed_toolchain": True, "shared_dependency_registry_caches": True,
    "cargo_offline": True, "blank_machine_bootstrap_verified": False,
    "log": "phase7-clean-build.log",
}, indent=2) + "\n")
PY
exit "$MOONVCS_CLEAN_CODE"
