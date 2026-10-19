#!/usr/bin/env bash
# Util-linux script captures the REAL terminal stream, not a fabricated screenshot.
set -euo pipefail
MOONVCS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ "$#" -eq 1 ]] || { echo 'Usage: scripts/record-demo.sh PREPARED_WORKDIR' >&2; exit 1; }
command -v script >/dev/null || { echo 'util-linux script is required; plain text evidence is produced by hackathon-demo.py' >&2; exit 1; }
mkdir -p "$MOONVCS_ROOT/target/reports"
MOONVCS_RECORD_DIR="$(mktemp -d "$MOONVCS_ROOT/target/reports/phase8-recording.XXXXXX")"
MOONVCS_RECORD_COMMAND="$(python3 -c 'import shlex,sys; print(shlex.join(sys.argv[1:]))' \
  python3 "$MOONVCS_ROOT/scripts/hackathon-demo.py" run --workdir "$1" --only all)"
script -q -e -m advanced -O "$MOONVCS_RECORD_DIR/terminal.typescript" \
  -T "$MOONVCS_RECORD_DIR/timing.log" -c "$MOONVCS_RECORD_COMMAND"
echo "Actual terminal recording (not MP4): $MOONVCS_RECORD_DIR"
echo "Replay with: scriptreplay -T '$MOONVCS_RECORD_DIR/timing.log' -O '$MOONVCS_RECORD_DIR/terminal.typescript'"
