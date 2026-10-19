#!/usr/bin/env bash
set -euo pipefail

MOONVCS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "$#" -eq 0 || "$1" != "--built" ]]; then
  "$MOONVCS_ROOT/scripts/build-vcs.sh"
fi
MOONVCS_BIN="$MOONVCS_ROOT/target/bin/moonvcs"
MOONVCS_TEST_ROOT="$(mktemp -d /tmp/moonvcs-policy-e2e.XXXXXX)"
cleanup() {
  if [[ "$MOONVCS_TEST_ROOT" == /tmp/moonvcs-policy-e2e.* && -d "$MOONVCS_TEST_ROOT" ]]; then
    rm -rf -- "$MOONVCS_TEST_ROOT"
  fi
}
trap cleanup EXIT

commit_count() {
  local count=0
  local object
  local kind
  for object in .moonvcs/objects/*/*; do
    kind="$(od -An -tu1 -j9 -N1 "$object")"
    if [[ "$kind" -eq 3 ]]; then count=$((count + 1)); fi
  done
  printf '%s' "$count"
}

expect_commit_failure() {
  local expected="$1"
  local message="$2"
  local code
  set +e
  MOONVCS_RESULT="$("$MOONVCS_BIN" commit -m "$message" 2>&1)"
  code=$?
  set -e
  [[ "$code" -eq "$expected" ]]
  [[ "$MOONVCS_RESULT" != *'Policy passed'* ]]
  [[ "$MOONVCS_RESULT" != *'harmless-cli-key-do-not-log'* ]]
  [[ "$MOONVCS_RESULT" != *'harmless-cli-token-do-not-log'* ]]
  [[ "$(cat .moonvcs/refs/heads/main)" == "$MOONVCS_HEAD" ]]
  [[ "$(sha256sum .moonvcs/index)" == "$MOONVCS_INDEX" ]]
  [[ "$(commit_count)" -eq 1 ]]
}

pushd "$MOONVCS_TEST_ROOT" >/dev/null
"$MOONVCS_BIN" init
printf 'APP_MODE=demo\n' >config.env
"$MOONVCS_BIN" add config.env >/dev/null
MOONVCS_CLEAN="$("$MOONVCS_BIN" commit -m initial)"
[[ "$MOONVCS_CLEAN" == *'Policy passed'* ]]
MOONVCS_HEAD="$(cat .moonvcs/refs/heads/main)"

mkdir nested
printf 'MOONVCS_API_KEY=harmless-cli-key-do-not-log\n' >config.env
printf 'MOONVCS_ACCESS_TOKEN=harmless-cli-token-do-not-log\n' >nested/access.env
"$MOONVCS_BIN" add config.env nested >/dev/null
MOONVCS_INDEX="$(sha256sum .moonvcs/index)"
MOONVCS_WORKING="$(sha256sum config.env nested/access.env)"
expect_commit_failure 2 'add config'
[[ "$MOONVCS_RESULT" == *'Commit rejected'* ]]
[[ "$MOONVCS_RESULT" == *'Policy: secret-scanner'* ]]
[[ "$MOONVCS_RESULT" == *'File: config.env'* ]]
[[ "$MOONVCS_RESULT" == *'File: nested/access.env'* ]]
[[ "$MOONVCS_RESULT" == *'Reason: suspicious credential'* ]]
[[ "$(sha256sum config.env nested/access.env)" == "$MOONVCS_WORKING" ]]
printf '%s\n' "$MOONVCS_RESULT"
MOONVCS_LOG="$("$MOONVCS_BIN" log)"
[[ "$MOONVCS_LOG" != *'harmless-cli-key-do-not-log'* ]]

# Working-directory repairs alone must not change the staged candidate.
printf 'APP_MODE=repaired\n' >config.env
printf 'AUTH_MODE=disabled\n' >nested/access.env
expect_commit_failure 2 'working tree repaired but Stage unchanged'

cp .moonvcs/policies.json .moonvcs/policies.saved
sed 's/secret-scanner.component.wasm/missing.component.wasm/g' \
  .moonvcs/policies.saved >.moonvcs/policies.json
expect_commit_failure 3 'required plugin missing'
[[ "$MOONVCS_RESULT" == *'required policy'* ]]

MOONVCS_SCANNER_DIGEST="$(sha256sum "$MOONVCS_ROOT/target/components/secret-scanner.component.wasm" | awk '{print $1}')"
MOONVCS_TRAP_DIGEST="$(sha256sum "$MOONVCS_ROOT/target/components/adversarial-fixture.component.wasm" | awk '{print $1}')"
sed -e 's/secret-scanner/adversarial-fixture/g' \
  -e 's/staged_content.read/commit_metadata.read/g' \
  -e 's/0.2.0/0.1.0/g' \
  -e "s/$MOONVCS_SCANNER_DIGEST/$MOONVCS_TRAP_DIGEST/g" \
  .moonvcs/policies.saved >.moonvcs/policies.json
expect_commit_failure 3 fixture:trap

cp .moonvcs/policies.saved .moonvcs/policies.json
"$MOONVCS_BIN" add config.env nested >/dev/null
MOONVCS_REPAIRED="$("$MOONVCS_BIN" commit -m 'repair config')"
[[ "$MOONVCS_REPAIRED" == *'Policy passed'* ]]
[[ "$MOONVCS_REPAIRED" == *'Commit created'* ]]
[[ "$(commit_count)" -eq 2 ]]
[[ "$("$MOONVCS_BIN" status)" == clean ]]
printf '%s\n' "$MOONVCS_REPAIRED"
popd >/dev/null
echo "MoonVCS real Wasm policy CLI tests passed"
