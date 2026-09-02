#!/usr/bin/env bash
# coverage-check-all.sh — run coverage-check.sh once per BRD against its own per-BRD ledger,
# exit clean only when every one is.
#
# WHY THIS EXISTS. coverage-check.sh measures exactly one (BRD, ledger) pair per invocation.
# A module with several BRDs — real on t-wf-migration, five of them — either measures one and
# silently reports it as the module's coverage, or needs a human to remember to run it N times.
# review-module.sh's own denominator fix (2026-09-02) stopped the FIRST failure mode by stating
# "coverage · 1 of 5 BRDs" instead of staying silent about the other four. This script is the
# second half: it actually runs all N, once each module has split its ledger one-per-BRD.
#
# CONVENTION THIS EXPECTS. A directory of per-BRD ledgers beside where the single-file
# convention puts coverage-ledger.md, named after that same BRD id:
#   architecture/modules/<Module>/coverage-ledger/<BRDID>.md
# matched to analysis/.../brd/<BRDID>.brd.json by basename. A module with one BRD does not need
# this at all — the single-file convention (coverage-ledger.md, coverage-check.sh directly) is
# simpler and stays correct.
#
# Usage: coverage-check-all.sh <ledger-dir> <brd-glob>
#   coverage-check-all.sh architecture/modules/DashboardPublishing/coverage-ledger \
#                         'analysis/*/knowledge-base/brd/*.brd.json'
#
# Exit 0: every BRD clean. Exit 1: at least one has findings (UNCLAIMED/PHANTOM/etc). Exit 2:
# a BRD has no matching ledger file, or coverage-check.sh itself is not reachable.
set -uo pipefail

LEDGER_DIR="${1:?usage: coverage-check-all.sh <ledger-dir> <brd-glob>}"
BRD_GLOB="${2:?usage: coverage-check-all.sh <ledger-dir> <brd-glob>}"

# Same resolution order review-module.sh's own _tool() uses: beside this script (the
# installed-in-project-bin case), then $MXTK_ROOT/bin (coverage-check.sh lives in the
# toolkit's bin/, not project-bin/, on a project that only installed project-bin/ scripts --
# exactly t-wf-migration's layout, which is what caught this), then PATH.
COV="$(dirname "${BASH_SOURCE[0]}")/coverage-check.sh"
[ -x "$COV" ] || COV="${MXTK_ROOT:-}/bin/coverage-check.sh"
[ -x "$COV" ] || COV="${MXTK_ROOT:-}/project-bin/coverage-check.sh"
[ -x "$COV" ] || COV="$(command -v coverage-check.sh || true)"
if [ -z "$COV" ] || [ ! -x "$COV" ]; then
  echo "coverage-check-all: coverage-check.sh not found beside this script, in \$MXTK_ROOT/{bin,project-bin}, or on PATH" >&2
  exit 2
fi

shopt -s nullglob
brds=($BRD_GLOB)
shopt -u nullglob
if [ "${#brds[@]}" -eq 0 ]; then
  echo "coverage-check-all: no BRDs matched $BRD_GLOB" >&2
  exit 2
fi

FAIL=0
FAULT=0
for brd in "${brds[@]}"; do
  bid="$(basename "$brd" .brd.json)"
  ledger="$LEDGER_DIR/$bid.md"
  if [ ! -f "$ledger" ]; then
    echo "$bid: NO LEDGER at $ledger"
    FAULT=1
    continue
  fi
  out="$("$COV" --summary "$brd" "$ledger" 2>&1)"
  rc=$?
  line="$(printf '%s\n' "$out" | grep -E 'CLAIMED|LEDGERED|UNCLAIMED|PHANTOM|DOUBLE-CLAIMED|COUNT-MISMATCH' | tr '\n' ' ' | sed 's/  */ /g')"
  case "$rc" in
    0) echo "$bid: CLEAN — $line" ;;
    1) echo "$bid: FINDINGS — $line"; FAIL=1 ;;
    *) echo "$bid: FAULT (coverage-check.sh exit $rc) — $out"; FAULT=1 ;;
  esac
done

echo
echo "${#brds[@]} BRD(s) checked."
if [ "$FAULT" -eq 1 ]; then exit 2; fi
if [ "$FAIL" -eq 1 ]; then exit 1; fi
echo "All clean."
exit 0
