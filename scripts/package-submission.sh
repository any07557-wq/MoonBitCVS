#!/usr/bin/env bash
# Source/evidence only, with an explicit allowlist; never archive the workspace wholesale.
set -euo pipefail
MOONVCS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ "$#" -eq 0 ]] || { echo 'Usage: scripts/package-submission.sh' >&2; exit 1; }
MOONVCS_SOURCE_ITEMS=(
  README.md ARCHITECTURE.md SECURITY.md ROADMAP.md DEMO.md TESTING.md INSTALL.md
  LICENSE .gitignore docs examples scripts tests vcs plugins wit host
  BRANCH_SWITCH.md
)
for MOONVCS_ITEM in "${MOONVCS_SOURCE_ITEMS[@]}"; do
  [[ -e "$MOONVCS_ROOT/$MOONVCS_ITEM" ]] || { echo "Missing source item: $MOONVCS_ITEM" >&2; exit 1; }
done
MOONVCS_EVIDENCE_ITEMS=(
  target/reports/phase7-verify.json
  target/reports/phase7-environment.json
  target/reports/phase7-environment.log target/reports/phase7-repeat-smoke.log
  target/reports/phase7-clean-build.json target/reports/phase7-clean-build.log
  target/reports/phase7-benchmark.json target/reports/phase7-benchmark.log
  target/reports/phase7-regression.log
  target/reports/phase7-regression-before-fix.log target/reports/phase7-verify-before-fix.json
  target/reports/phase8-regression.log target/reports/phase8-smoke.log
)
for MOONVCS_ITEM in "${MOONVCS_EVIDENCE_ITEMS[@]}"; do
  [[ -f "$MOONVCS_ROOT/$MOONVCS_ITEM" ]] || { echo "Missing evidence: $MOONVCS_ITEM; run documented verification first" >&2; exit 1; }
done
for MOONVCS_REPORT_DIR in "$MOONVCS_ROOT"/target/reports/phase8-prepare-* \
  "$MOONVCS_ROOT"/target/reports/phase8-run-* "$MOONVCS_ROOT"/target/reports/phase8-recording.*; do
  [[ -d "$MOONVCS_REPORT_DIR" ]] || continue
  for MOONVCS_NAME in result.json terminal.txt terminal.typescript timing.log; do
    MOONVCS_REPORT_FILE="$MOONVCS_REPORT_DIR/$MOONVCS_NAME"
    if [[ -f "$MOONVCS_REPORT_FILE" ]]; then
      MOONVCS_EVIDENCE_ITEMS+=("${MOONVCS_REPORT_FILE#"$MOONVCS_ROOT"/}")
    fi
  done
done
for MOONVCS_ITEM in \
  target/reports/roadmap-baseline.log target/reports/roadmap-regression.log \
  target/reports/roadmap-regression-final.log target/reports/recovery-root-symlink-before.log \
  target/reports/roadmap-regression-portable.log \
  target/reports/roadmap-environment.json target/reports/roadmap-environment.log \
  target/reports/roadmap-staging-before.json \
  target/reports/fresh02-controller.json target/reports/fresh03-controller.json \
  target/reports/fresh02-archive-preflight.log target/reports/fresh03-registry-regression.log \
  target/reports/fresh03-host-regression.log \
  target/reports/diff-build.log target/reports/diff-cli-initial.log \
  target/reports/diff-regression.log target/reports/diff-regression-final.log \
  target/reports/diff-partial-snapshot.log target/reports/diff-source-sha256.txt \
  target/reports/fresh02-original/scripts/fresh-install.py \
  target/roadmap-fresh-02/report.json \
  target/roadmap-fresh-03/report.json target/roadmap-fresh-03/source-manifest.json \
  "$MOONVCS_ROOT"/target/roadmap-fresh-03/*.log \
  target/reports/round2-regression.log target/reports/round2-environment.json \
  target/reports/round2-regression-final.log \
  target/reports/round2-environment.log target/reports/recovery-round2.log \
  target/reports/lazy-get-round2-build.log target/reports/lazy-get-round2-native.log \
  target/reports/lazy-get-round2-build-final.log target/reports/lazy-get-round2-compare-final.log \
  target/reports/lazy-get-round2-compare.log target/reports/lazy-get-round2-io-test.log \
  target/reports/lazy-get-round2-io-before.log \
  target/lazy-get-round2-compare/result.json \
  target/lazy-get-round2-compare/before-io.json target/lazy-get-round2-compare/after-io.json \
  target/lazy-get-round2-compare-final/result.json \
  target/lazy-get-round2-compare-final/before-io.json target/lazy-get-round2-compare-final/after-io.json \
  target/moonbit-archive-round2/archive-report.json \
  target/reports/toolchain-archive-round2-download.log \
  target/reports/toolchain-archive-round2-local-verify.log \
  target/roadmap-profile-01/result.json target/roadmap-profile-01/callgrind.out \
  target/roadmap-profile-01/cpu-instructions.txt target/roadmap-profile-01/io-counts.json \
  target/roadmap-profile-01/collector.log \
  target/roadmap-profile-01/cpu.er/log.xml target/roadmap-profile-01/cpu-unrestricted.er/log.xml \
  target/roadmap-fresh-01/report.json target/roadmap-fresh-01/source-manifest.json \
  "$MOONVCS_ROOT"/target/roadmap-fresh-01/*.log \
  "$MOONVCS_ROOT"/target/roadmap-fresh-01/source-manifest-attempt-*.json; do
  if [[ "$MOONVCS_ITEM" == "$MOONVCS_ROOT"/* ]]; then
    MOONVCS_ITEM="${MOONVCS_ITEM#"$MOONVCS_ROOT"/}"
  fi
  if [[ -f "$MOONVCS_ROOT/$MOONVCS_ITEM" ]]; then
    MOONVCS_EVIDENCE_ITEMS+=("$MOONVCS_ITEM")
  fi
done
# Current prototype evidence: enumerate files, never include recovery repositories.
for MOONVCS_NAME in \
  branch-switch-baseline.log branch-switch-native-initial.log branch-switch-native.log \
  branch-switch-build.log branch-switch-cli-initial.log branch-switch-diff-compat.log \
  branch-switch-regression.log branch-switch-regression-final.log \
  branch-switch-empty-tree-before.log branch-switch-closure-regression.log \
  branch-switch-source-sha256.txt branch-switch-closure-source-sha256.txt \
  branch-switch-closure-cli.sha256 branch-switch-closeout-build-y3yW22V4.log; do
  MOONVCS_ITEM="target/reports/$MOONVCS_NAME"
  [[ -f "$MOONVCS_ROOT/$MOONVCS_ITEM" ]] || { echo "Missing prototype evidence: $MOONVCS_ITEM" >&2; exit 1; }
  MOONVCS_EVIDENCE_ITEMS+=("$MOONVCS_ITEM")
done
for MOONVCS_NAME in \
  environment.json environment.log tested-source.sha256 tested-source-final.sha256 \
  tested-runtime.sha256 delivered-source.sha256 evidence.sha256 \
  regression-final.log regression-run.txt source-check.log runtime-check.log \
  delivered-source-check.log new-regressions.log new-regressions-final.log \
  manual-recovery-01.log manual-recovery-02.log \
  manual-recovery-01/commands.jsonl manual-recovery-01/recover-before.json \
  manual-recovery-01/evidence-manifest.json \
  manual-recovery-02/commands.jsonl manual-recovery-02/recover-before.json \
  manual-recovery-02/evidence-manifest.json manual-recovery-02/result.json; do
  MOONVCS_ITEM="target/reports/branch-switch-closeout.VpnM81/$MOONVCS_NAME"
  [[ -f "$MOONVCS_ROOT/$MOONVCS_ITEM" ]] || { echo "Missing closeout evidence: $MOONVCS_ITEM" >&2; exit 1; }
  MOONVCS_EVIDENCE_ITEMS+=("$MOONVCS_ITEM")
done
mkdir -p "$MOONVCS_ROOT/target/releases"
MOONVCS_SUBMISSION_DIR="$(mktemp -d "$MOONVCS_ROOT/target/releases/submission.XXXXXX")"
tar -C "$MOONVCS_ROOT" --sort=name \
  --exclude=_build --exclude=target --exclude=.mooncakes --exclude=.toolchains \
  --exclude=__pycache__ --exclude=.moonvcs --exclude=.git \
  -czf "$MOONVCS_SUBMISSION_DIR/MoonVCS-source.tar.gz" "${MOONVCS_SOURCE_ITEMS[@]}"
tar -C "$MOONVCS_ROOT" --sort=name \
  -czf "$MOONVCS_SUBMISSION_DIR/MoonVCS-evidence.tar.gz" "${MOONVCS_EVIDENCE_ITEMS[@]}"
(
  cd "$MOONVCS_SUBMISSION_DIR"
  sha256sum MoonVCS-source.tar.gz MoonVCS-evidence.tar.gz >SHA256SUMS
)
echo "Local source/evidence submission: $MOONVCS_SUBMISSION_DIR"
echo 'No toolchain, runtime binaries, authentication, signature or blank-machine installation guarantee is included.'
echo 'Reports include machine paths/timestamps and expected rejected subcommands; inspect before publishing.'
echo 'Prototype closeout evidence is historical, not proof for a later archive. Run scripts/reproduce-submission.py against this exact package.'
