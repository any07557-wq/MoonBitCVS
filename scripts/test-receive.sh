#!/usr/bin/env bash
set -euo pipefail
trap 'printf "Receive demo failed at line %s\n" "$LINENO" >&2' ERR
MOONVCS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "$#" -eq 0 || "$1" != "--built" ]]; then
  "$MOONVCS_ROOT/scripts/build-vcs.sh"
fi
MOONVCS_BIN="$MOONVCS_ROOT/target/bin/moonvcs"
MOONVCS_BYPASS="$MOONVCS_ROOT/target/bin/moonvcs-bypass-client"
MOONVCS_TEST_ROOT="$(mktemp -d /tmp/moonvcs-receive-e2e.XXXXXX)"
cleanup() {
  if [[ "$MOONVCS_TEST_ROOT" == /tmp/moonvcs-receive-e2e.* && -d "$MOONVCS_TEST_ROOT" ]]; then
    rm -rf -- "$MOONVCS_TEST_ROOT"
  fi
}
trap cleanup EXIT
object_count() { find "$1/.moonvcs/objects" -type f | wc -l | tr -d ' '; }
assert_quarantine_empty() {
  [[ "$(find "$MOONVCS_TEST_ROOT/server/.moonvcs/quarantine" -mindepth 1 | wc -l)" -eq 0 ]]
}
expect_failure() {
  local code
  local expected="$1"
  local label="$2"
  shift 2
  if MOONVCS_RESULT="$("$@" 2>&1)"; then code=0; else code=$?; fi
  [[ "$code" -eq "$expected" ]]
  [[ "$MOONVCS_RESULT" == *"$label"* ]]
  [[ "$MOONVCS_RESULT" != *'harmless-bypass-only-do-not-log'* ]]
  [[ "$MOONVCS_RESULT" != *'harmless-local-only-do-not-log'* ]]
  printf '%s\n' "$MOONVCS_RESULT"
}

mkdir "$MOONVCS_TEST_ROOT/server" "$MOONVCS_TEST_ROOT/client"
pushd "$MOONVCS_TEST_ROOT/server" >/dev/null
"$MOONVCS_BIN" init
"$MOONVCS_BIN" receive-init
MOONVCS_POLICY_HASH="$(sha256sum .moonvcs/receive-policies.json)"
popd >/dev/null

echo 'Scenario A: safe client commit, server independently accepts'
pushd "$MOONVCS_TEST_ROOT/client" >/dev/null
"$MOONVCS_BIN" init
printf 'APP_MODE=safe\n' >config.env
"$MOONVCS_BIN" add config.env >/dev/null
"$MOONVCS_BIN" commit -m 'safe initial'
MOONVCS_BASE="$(cat .moonvcs/refs/heads/main)"
"$MOONVCS_BIN" push "$MOONVCS_TEST_ROOT/server" refs/heads/main none
[[ "$(cat "$MOONVCS_TEST_ROOT/server/.moonvcs/refs/heads/main")" == "$MOONVCS_BASE" ]]
assert_quarantine_empty
MOONVCS_INITIAL_OBJECTS="$(object_count "$MOONVCS_TEST_ROOT/server")"

echo 'Scenario B: local scanner rejects harmless simulated secret'
printf 'MOONVCS_API_KEY=harmless-local-only-do-not-log\n' >config.env
"$MOONVCS_BIN" add config.env >/dev/null
expect_failure 2 'Commit rejected' "$MOONVCS_BIN" commit -m 'blocked locally'
[[ "$(cat .moonvcs/refs/heads/main)" == "$MOONVCS_BASE" ]]
printf 'APP_MODE=safe\n' >config.env
"$MOONVCS_BIN" add config.env >/dev/null

echo 'Scenario C: standalone bypass program creates unchecked objects without updating client HEAD'
MOONVCS_BYPASS_OUTPUT="$("$MOONVCS_BYPASS" "$MOONVCS_TEST_ROOT/client" "$MOONVCS_TEST_ROOT/bypass.rx" "$MOONVCS_BASE" secret)"
printf '%s\n' "$MOONVCS_BYPASS_OUTPUT"
MOONVCS_REJECTED_ID="$(printf '%s\n' "$MOONVCS_BYPASS_OUTPUT" | awk '/^Unscanned candidate / {print $3}')"
[[ "$(cat .moonvcs/refs/heads/main)" == "$MOONVCS_BASE" ]]
popd >/dev/null
pushd "$MOONVCS_TEST_ROOT/server" >/dev/null
expect_failure 12 'Push rejected' "$MOONVCS_BIN" receive "$MOONVCS_TEST_ROOT/bypass.rx"
[[ "$MOONVCS_RESULT" == *'Policy: secret-scanner'* ]]
[[ "$MOONVCS_RESULT" == *'suspicious credential'* ]]
[[ "$(cat .moonvcs/refs/heads/main)" == "$MOONVCS_BASE" ]]
[[ "$(object_count "$MOONVCS_TEST_ROOT/server")" -eq "$MOONVCS_INITIAL_OBJECTS" ]]
[[ "$(sha256sum .moonvcs/receive-policies.json)" == "$MOONVCS_POLICY_HASH" ]]
assert_quarantine_empty
popd >/dev/null

echo 'Scenario D: two prepared clients use the same old Ref; stale second publish cannot overwrite'
"$MOONVCS_BYPASS" "$MOONVCS_TEST_ROOT/client" "$MOONVCS_TEST_ROOT/a.rx" "$MOONVCS_BASE" safe-a
"$MOONVCS_BYPASS" "$MOONVCS_TEST_ROOT/client" "$MOONVCS_TEST_ROOT/b.rx" "$MOONVCS_BASE" safe-b
pushd "$MOONVCS_TEST_ROOT/server" >/dev/null
"$MOONVCS_BIN" receive "$MOONVCS_TEST_ROOT/a.rx"
MOONVCS_FIRST="$(cat .moonvcs/refs/heads/main)"
[[ "$MOONVCS_FIRST" != "$MOONVCS_BASE" ]]
expect_failure 11 RefConflict "$MOONVCS_BIN" receive "$MOONVCS_TEST_ROOT/b.rx"
[[ "$(cat .moonvcs/refs/heads/main)" == "$MOONVCS_FIRST" ]]
assert_quarantine_empty

# Independent server processes race on fresh candidates with the same old Ref.
MOONVCS_C_OUTPUT="$("$MOONVCS_BYPASS" "$MOONVCS_TEST_ROOT/client" "$MOONVCS_TEST_ROOT/c.rx" "$MOONVCS_FIRST" safe-a)"
MOONVCS_D_OUTPUT="$("$MOONVCS_BYPASS" "$MOONVCS_TEST_ROOT/client" "$MOONVCS_TEST_ROOT/d.rx" "$MOONVCS_FIRST" safe-b)"
printf '%s\n%s\n' "$MOONVCS_C_OUTPUT" "$MOONVCS_D_OUTPUT"
"$MOONVCS_BIN" receive "$MOONVCS_TEST_ROOT/c.rx" >"$MOONVCS_TEST_ROOT/c.log" 2>&1 &
MOONVCS_PID_C=$!
"$MOONVCS_BIN" receive "$MOONVCS_TEST_ROOT/d.rx" >"$MOONVCS_TEST_ROOT/d.log" 2>&1 &
MOONVCS_PID_D=$!
if wait "$MOONVCS_PID_C"; then MOONVCS_CODE_C=0; else MOONVCS_CODE_C=$?; fi
if wait "$MOONVCS_PID_D"; then MOONVCS_CODE_D=0; else MOONVCS_CODE_D=$?; fi
[[ ( "$MOONVCS_CODE_C" -eq 0 && "$MOONVCS_CODE_D" -eq 11 ) ||
   ( "$MOONVCS_CODE_C" -eq 11 && "$MOONVCS_CODE_D" -eq 0 ) ]]
printf 'Concurrent server processes: exits %s and %s (one accept, one conflict)\n' "$MOONVCS_CODE_C" "$MOONVCS_CODE_D"
assert_quarantine_empty
[[ "$(sha256sum .moonvcs/receive-policies.json)" == "$MOONVCS_POLICY_HASH" ]]
[[ "$("$MOONVCS_BIN" storage-state "$MOONVCS_REJECTED_ID")" == Unknown ]]
"$MOONVCS_BIN" log --max-count 3
for MOONVCS_OBJECT in .moonvcs/objects/*/*; do
  MOONVCS_EXPECTED="$(basename "$(dirname "$MOONVCS_OBJECT")")$(basename "$MOONVCS_OBJECT")"
  [[ "$(sha256sum "$MOONVCS_OBJECT" | awk '{print $1}')" == "$MOONVCS_EXPECTED" ]]
done
printf 'Measured published objects: initial=%s final=%s; rejected candidate=%s never published\n' \
  "$MOONVCS_INITIAL_OBJECTS" "$(object_count "$MOONVCS_TEST_ROOT/server")" "$MOONVCS_REJECTED_ID"
popd >/dev/null
echo 'MoonVCS phase-6 remote policy receive tests passed'
