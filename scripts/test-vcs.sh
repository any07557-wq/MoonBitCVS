#!/usr/bin/env bash
set -euo pipefail

MOONVCS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$MOONVCS_ROOT/scripts/build-vcs.sh"
MOONVCS_BIN="$MOONVCS_ROOT/target/bin/moonvcs"
MOONVCS_TEST_ROOT="$(mktemp -d /tmp/moonvcs-e2e.XXXXXX)"

cleanup() {
  if [[ "$MOONVCS_TEST_ROOT" == /tmp/moonvcs-e2e.* && -d "$MOONVCS_TEST_ROOT" ]]; then
    rm -rf -- "$MOONVCS_TEST_ROOT"
  fi
}
trap cleanup EXIT

pushd "$MOONVCS_TEST_ROOT" >/dev/null
MOONVCS_INIT_OUTPUT="$($MOONVCS_BIN init)"
printf 'hello MoonVCS\n' >example.txt
mkdir nested
printf 'nested file\n' >nested/note.txt
MOONVCS_ADD_OUTPUT="$($MOONVCS_BIN add .)"
MOONVCS_STATUS_BEFORE="$($MOONVCS_BIN status)"
MOONVCS_COMMIT_OUTPUT="$(MOONVCS_AUTHOR='Integration Test' \
  "$MOONVCS_BIN" commit -m 'initial')"
MOONVCS_STATUS_AFTER="$($MOONVCS_BIN status)"
MOONVCS_LOG_OUTPUT="$($MOONVCS_BIN log)"
MOONVCS_SHOW_OUTPUT="$($MOONVCS_BIN show HEAD)"
printf 'updated nested file\n' >nested/note.txt
pushd nested >/dev/null
MOONVCS_SUBDIR_ADD="$($MOONVCS_BIN add note.txt)"
MOONVCS_SECOND_COMMIT="$($MOONVCS_BIN commit -m second)"
popd >/dev/null
MOONVCS_SECOND_ID="$(printf '%s\n' "$MOONVCS_SECOND_COMMIT" | awk '/^Committed / {print $2}')"
MOONVCS_SECOND_LOG="$($MOONVCS_BIN log)"
MOONVCS_SECOND_SHOW="$($MOONVCS_BIN show HEAD)"
MOONVCS_OBJECT_COUNT="$(find .moonvcs/objects -type f | wc -l)"
for MOONVCS_OBJECT in .moonvcs/objects/*/*; do
  MOONVCS_OBJECT_NAME="${MOONVCS_OBJECT#.moonvcs/objects/}"
  MOONVCS_EXPECTED_ID="${MOONVCS_OBJECT_NAME/\//}"
  MOONVCS_ACTUAL_ID="$(sha256sum "$MOONVCS_OBJECT" | awk '{print $1}')"
  [[ "$MOONVCS_ACTUAL_ID" == "$MOONVCS_EXPECTED_ID" ]]
done
popd >/dev/null

[[ "$MOONVCS_INIT_OUTPUT" == *'Initialized empty MoonVCS repository'* ]]
[[ "$MOONVCS_ADD_OUTPUT" == *'staged example.txt '* ]]
[[ "$MOONVCS_ADD_OUTPUT" == *'staged nested/note.txt '* ]]
[[ "$MOONVCS_STATUS_BEFORE" == *'staged  example.txt'* ]]
[[ "$MOONVCS_COMMIT_OUTPUT" == *'Policy passed'* ]]
[[ "$MOONVCS_COMMIT_OUTPUT" == *'Committed '* ]]
[[ "$MOONVCS_STATUS_AFTER" == 'clean' ]]
[[ "$MOONVCS_LOG_OUTPUT" == *'Author: Integration Test'* ]]
[[ "$MOONVCS_LOG_OUTPUT" == *'    initial'* ]]
[[ "$MOONVCS_SHOW_OUTPUT" == commit\ * ]]
[[ "$MOONVCS_SHOW_OUTPUT" == *'author Integration Test'* ]]
[[ "$MOONVCS_SUBDIR_ADD" == 'staged nested/note.txt '* ]]
[[ "$MOONVCS_SECOND_LOG" == "commit $MOONVCS_SECOND_ID"* ]]
[[ "$MOONVCS_SECOND_LOG" == *'    initial'* ]]
[[ "$MOONVCS_SECOND_SHOW" == *'parent '* ]]
[[ "$MOONVCS_OBJECT_COUNT" -ge 9 ]]

printf '%s\n%s\n%s\n' \
  "$MOONVCS_COMMIT_OUTPUT" \
  "$MOONVCS_STATUS_AFTER" \
  "$MOONVCS_LOG_OUTPUT"
echo "MoonVCS phase-2 unit and CLI integration tests passed"
