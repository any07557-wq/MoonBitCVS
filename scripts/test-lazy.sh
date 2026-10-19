#!/usr/bin/env bash
set -euo pipefail
trap 'printf "Lazy storage demo failed at line %s\n" "$LINENO" >&2' ERR
MOONVCS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "$#" -eq 0 || "$1" != "--built" ]]; then
  "$MOONVCS_ROOT/scripts/build-vcs.sh"
fi
MOONVCS_BIN="$MOONVCS_ROOT/target/bin/moonvcs"
MOONVCS_TEST_ROOT="$(mktemp -d /tmp/moonvcs-lazy-e2e.XXXXXX)"
cleanup() {
  if [[ "$MOONVCS_TEST_ROOT" == /tmp/moonvcs-lazy-e2e.* && -d "$MOONVCS_TEST_ROOT" ]]; then
    rm -rf -- "$MOONVCS_TEST_ROOT"
  fi
}
trap cleanup EXIT
object_count() {
  find "$1/.moonvcs/objects" -type f | wc -l | tr -d ' '
}
object_bytes() {
  find "$1/.moonvcs/objects" -type f -printf '%s\n' | awk '{total += $1} END {printf "%.0f", total}'
}
counter() {
  "$MOONVCS_BIN" storage-stats | tr ',' '\n' | sed -n "s/.*\"$1\":\"\\{0,1\\}\\([0-9]*\\).*/\\1/p"
}
expect_failure() {
  local expected="$1"
  local label="$2"
  shift 2
  local code
  set +e
  MOONVCS_OUTPUT="$("$@" 2>&1)"
  code=$?
  set -e
  [[ "$code" -eq "$expected" ]]
  [[ "$MOONVCS_OUTPUT" == *"$label"* ]]
  printf '%s\n' "$MOONVCS_OUTPUT"
}

mkdir "$MOONVCS_TEST_ROOT/remote"
pushd "$MOONVCS_TEST_ROOT/remote" >/dev/null
"$MOONVCS_BIN" init
mkdir nested
printf 'Data on demand fixture\n' >README.md
printf '' >nested/empty.bin
printf '\000\377\001moonvcs\n' >nested/二进制.bin
for i in $(seq 1 80); do
  printf 'version-%s\n' "$i" >history.txt
  "$MOONVCS_BIN" add . >/dev/null
  "$MOONVCS_BIN" commit -m "history-$i" >/dev/null
  if (( i % 20 == 0 )); then printf 'Prepared %s real policy-gated commits\n' "$i"; fi
done
MOONVCS_REMOTE_COUNT="$(object_count "$MOONVCS_TEST_ROOT/remote")"
MOONVCS_REMOTE_BYTES="$(object_bytes "$MOONVCS_TEST_ROOT/remote")"
popd >/dev/null
pushd "$MOONVCS_TEST_ROOT" >/dev/null
"$MOONVCS_BIN" clone remote clone
MOONVCS_CLONE_COUNT="$(object_count clone)"
MOONVCS_CLONE_BYTES="$(object_bytes clone)"
[[ "$MOONVCS_CLONE_COUNT" -lt "$MOONVCS_REMOTE_COUNT" ]]
[[ "$((MOONVCS_CLONE_COUNT * 10))" -lt "$MOONVCS_REMOTE_COUNT" ]]
cmp remote/history.txt clone/history.txt
cmp remote/nested/二进制.bin clone/nested/二进制.bin
cmp remote/nested/empty.bin clone/nested/empty.bin
pushd clone >/dev/null
[[ "$("$MOONVCS_BIN" status)" == clean ]]
[[ "$(counter received_objects)" -eq "$MOONVCS_CLONE_COUNT" ]]
[[ "$(counter received_bytes)" -eq "$MOONVCS_CLONE_BYTES" ]]
MOONVCS_PARENT="$("$MOONVCS_BIN" show HEAD | awk '/^parent / {print $2; exit}')"
[[ "$("$MOONVCS_BIN" storage-state "$MOONVCS_PARENT")" == PromisedRemote ]]

# Independent CLI processes race for the same promised object; exactly one reads it.
MOONVCS_BEFORE="$(counter requests)"
MOONVCS_JOBS=""
MOONVCS_PROCESS_COUNT=0
for i in $(seq 1 8); do
  "$MOONVCS_BIN" show "$MOONVCS_PARENT" >"$MOONVCS_TEST_ROOT/concurrent-$i.log" &
  MOONVCS_JOBS="$MOONVCS_JOBS $!"
  MOONVCS_PROCESS_COUNT=$((MOONVCS_PROCESS_COUNT + 1))
done
for MOONVCS_JOB in $MOONVCS_JOBS; do wait "$MOONVCS_JOB"; done
MOONVCS_CONCURRENT_TRANSFERS=$(($(counter requests) - MOONVCS_BEFORE))
[[ "$MOONVCS_CONCURRENT_TRANSFERS" -eq 1 ]]
for i in $(seq 1 8); do
  [[ "$(awk '/^commit / {print $2; exit}' "$MOONVCS_TEST_ROOT/concurrent-$i.log")" == "$MOONVCS_PARENT" ]]
done
printf 'Concurrent Fetch: %s processes, %s transfer\n' "$MOONVCS_PROCESS_COUNT" "$MOONVCS_CONCURRENT_TRANSFERS"
MOONVCS_HISTORY="$("$MOONVCS_BIN" log --max-count 6)"
[[ "$(printf '%s\n' "$MOONVCS_HISTORY" | awk '/^commit / {n++} END {print n}')" -eq 6 ]]
printf '%s\n' "$MOONVCS_HISTORY"
MOONVCS_AFTER_HISTORY="$(object_count "$MOONVCS_TEST_ROOT/clone")"
MOONVCS_HISTORY_BYTES="$(object_bytes "$MOONVCS_TEST_ROOT/clone")"
[[ "$(counter received_objects)" -eq "$MOONVCS_AFTER_HISTORY" ]]
[[ "$(counter received_bytes)" -eq "$MOONVCS_HISTORY_BYTES" ]]
MOONVCS_REQUESTS="$(counter requests)"
MOONVCS_REPEAT="$("$MOONVCS_BIN" log --max-count 6)"
[[ "$MOONVCS_REPEAT" != *'[Fetch]'* ]]
[[ "$(counter requests)" -eq "$MOONVCS_REQUESTS" ]]
MOONVCS_REPEAT_FETCHES=$(($(counter requests) - MOONVCS_REQUESTS))
MOONVCS_LAST="$(printf '%s\n' "$MOONVCS_REPEAT" | awk '/^commit / {last=$2} END {print last}')"
MOONVCS_UNCACHED="$("$MOONVCS_BIN" show "$MOONVCS_LAST" | awk '/^parent / {print $2; exit}')"
[[ "$("$MOONVCS_BIN" storage-state "$MOONVCS_UNCACHED")" == PromisedRemote ]]

mv "$MOONVCS_TEST_ROOT/remote" "$MOONVCS_TEST_ROOT/remote-disconnected"
"$MOONVCS_BIN" --offline show HEAD >/dev/null
"$MOONVCS_BIN" log --max-count 6 --offline >/dev/null
[[ "$(counter requests)" -eq "$MOONVCS_REQUESTS" ]]
echo 'Offline Cached Read: success without remote access'
expect_failure 4 ObjectUnavailableOffline "$MOONVCS_BIN" show "$MOONVCS_UNCACHED" --offline
[[ "$(counter requests)" -eq "$MOONVCS_REQUESTS" ]]
MOONVCS_UNKNOWN="$(printf '%064d' 0)"
expect_failure 5 UnknownObject "$MOONVCS_BIN" --offline show "$MOONVCS_UNKNOWN"
[[ "$(counter requests)" -eq "$MOONVCS_REQUESTS" ]]
expect_failure 6 RemoteUnavailable "$MOONVCS_BIN" show "$MOONVCS_UNCACHED"
[[ "$(counter requests)" -eq "$((MOONVCS_REQUESTS + 1))" ]]
[[ "$(counter received_bytes)" -eq "$MOONVCS_HISTORY_BYTES" ]]

# Independently verify every cached canonical file against its actual SHA-256.
for MOONVCS_OBJECT in .moonvcs/objects/*/*; do
  MOONVCS_EXPECTED="$(basename "$(dirname "$MOONVCS_OBJECT")")$(basename "$MOONVCS_OBJECT")"
  [[ "$(sha256sum "$MOONVCS_OBJECT" | awk '{print $1}')" == "$MOONVCS_EXPECTED" ]]
done
printf 'Transfer summary (measured, encoded-object bytes only):\n'
printf 'remote_objects=%s remote_object_bytes=%s\n' "$MOONVCS_REMOTE_COUNT" "$MOONVCS_REMOTE_BYTES"
printf 'initial_clone_objects=%s initial_clone_object_bytes=%s\n' "$MOONVCS_CLONE_COUNT" "$MOONVCS_CLONE_BYTES"
printf 'after_history_objects=%s after_history_object_bytes=%s\n' "$MOONVCS_AFTER_HISTORY" "$MOONVCS_HISTORY_BYTES"
printf 'repeat_fetches=%s concurrent_processes=%s concurrent_transfers=%s\n' \
  "$MOONVCS_REPEAT_FETCHES" "$MOONVCS_PROCESS_COUNT" "$MOONVCS_CONCURRENT_TRANSFERS"
popd >/dev/null
popd >/dev/null
echo 'MoonVCS phase-5 lazy storage CLI tests passed'
