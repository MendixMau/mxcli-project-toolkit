#!/usr/bin/env bash
# bench-mdl-scan.sh — before/after measurement of bin/mdl-scan.sh (#349). Prints a markdown table.
#
# Usage: bash tests/wave2/bench-mdl-scan.sh [path-to-mdl-scan.sh]
#
# Failing corpus: every captured bad MDL in tests/wave2/fixtures/mdl-scan/ — the STOP-row
#   fixtures (<id>.bad.mdl) AND uncovered/ (captured failures no scan rule targets, kept so the
#   catch rate is not graded on its own homework). Selection: open bug-log entries whose bad
#   MDL passes `mxcli check` and fails at mxbuild or Studio Pro open, i.e. each costs an apply.
#   A file counts only if its `-- evidence:` line is verbatim in bug-logs/mxcli-bugs.md.
# Clean corpus: MDL that applied at 0 errors — examples/stylegallery (field run in its README)
#   and the corrected forms (<id>.good.mdl) the same bug entries record as building clean,
#   plus clean/ (valid MDL an earlier scanner revision flagged; independent review of #355).
# A hit of a `warn` rule (scan exit 3) counts as caught: the agent sees it before the apply.
# Before = no scan: every failing script reaches the apply. After = the scan refuses the
#   caught ones before the lock and the snapshot.
# Time saved per caught script = one apply, taken from skills/iterative-build-loop.md
#   "Gate cost" (field run 2026-09-29), read from that file, not typed here. The restore after
#   a failed gate is not in that figure, so the saving is a lower bound.
set -uo pipefail
TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
SCAN="${1:-$TOOLKIT/bin/mdl-scan.sh}"
FX="$TOOLKIT/tests/wave2/fixtures/mdl-scan"
LEDGER="$TOOLKIT/bug-logs/mxcli-bugs.md"
LOOP="$TOOLKIT/skills/iterative-build-loop.md"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mdlbench.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT

FAILN=0; CAUGHT=0; CBLOCK=0; MISSED=""; UNPROVEN=0
for f in "$FX"/STOP-*.bad.mdl "$FX"/uncovered/*.mdl; do
  [ -f "$f" ] || continue
  ev="$(sed -n 's/^-- evidence: //p' "$f" | head -1)"
  if [ -z "$ev" ] || ! grep -qF -- "$ev" "$LEDGER"; then UNPROVEN=$((UNPROVEN+1)); continue; fi
  FAILN=$((FAILN+1))
  bash "$SCAN" "$f" >/dev/null 2>&1; rc=$?
  case "$rc" in
    0) MISSED="$MISSED $(basename "$f" .mdl)" ;;
    1) CAUGHT=$((CAUGHT+1)); CBLOCK=$((CBLOCK+1)) ;;
    *) CAUGHT=$((CAUGHT+1)) ;;
  esac
done
[ "$UNPROVEN" -eq 0 ] || { echo "bench: $UNPROVEN failing-corpus file(s) have no captured evidence in the ledger" >&2; exit 2; }
[ "$FAILN" -gt 0 ] || { echo "bench: failing corpus is empty" >&2; exit 2; }

CLEANN=0; FP=0; CLEANL=0
for f in "$TOOLKIT"/examples/stylegallery/mdlsource/gallery/*.mdl "$FX"/STOP-*.good.mdl "$FX"/clean/*.mdl; do
  [ -f "$f" ] || continue
  CLEANN=$((CLEANN+1)); CLEANL=$((CLEANL + $(wc -l < "$f")))
  bash "$SCAN" "$f" >/dev/null 2>&1 || FP=$((FP+1))
done
[ "$CLEANN" -gt 0 ] || { echo "bench: clean corpus is empty" >&2; exit 2; }

# Scan time: the clean corpus repeated to >= 10,000 lines, best of 5 (wall clock).
: > "$WORK/big.mdl"
while [ "$(wc -l < "$WORK/big.mdl")" -lt 10000 ]; do
  cat "$TOOLKIT"/examples/stylegallery/mdlsource/gallery/*.mdl >> "$WORK/big.mdl"
done
BIGL=$(wc -l < "$WORK/big.mdl" | tr -d ' ')
TIMEFORMAT=%R; BEST=""
for _ in 1 2 3 4 5; do
  t=$( { time bash "$SCAN" "$WORK/big.mdl" >/dev/null 2>&1; } 2>&1 )
  BEST=$(awk -v a="$BEST" -v b="$t" 'BEGIN { print (a == "" || b + 0 < a + 0) ? b : a }')
done
PER1K=$(awk -v t="$BEST" -v l="$BIGL" 'BEGIN { printf "%.1f", t * 1000 * 1000 / l }')

# Apply cost, read from the Gate cost field numbers ("22–30 s ... 55–65 s").
COSTLINE="$(grep -m1 -A1 -E '[0-9]+–[0-9]+ s per script' "$LOOP" | tr '\n' ' ' | sed 's/  */ /g')"   # the sentence wraps
LO=$(printf '%s\n' "$COSTLINE" | grep -oE '[0-9]+–[0-9]+ s' | head -1 | sed 's/–.*//')
HI=$(printf '%s\n' "$COSTLINE" | grep -oE '[0-9]+–[0-9]+ s' | tail -1 | sed 's/.*–//; s/ s//')
[ -n "$LO" ] && [ -n "$HI" ] || { echo "bench: Gate cost numbers not found in $LOOP" >&2; exit 2; }

pct() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.0f%%", 100 * a / b }'; }
echo "| measure | before (no scan) | after (mdl-scan) |"
echo "|---|---|---|"
echo "| failing corpus flagged before apply | 0 / $FAILN | $CAUGHT / $FAILN ($(pct "$CAUGHT" "$FAILN")) |"
echo "| of those, refused by a \`block\` rule / warned by a \`warn\` rule | — | $CBLOCK / $((CAUGHT - CBLOCK)) |"
echo "| failing scripts with no signal before the apply | $FAILN | $((FAILN - CAUGHT)) (missed:${MISSED:- none}) |"
echo "| false positives on clean corpus | — | $FP / $CLEANN files ($(pct "$FP" "$CLEANN")), $CLEANL lines |"
echo "| scan time per 1,000 lines | — | ${PER1K} ms (best of 5 over $BIGL lines) |"
echo "| apply time spent on flagged failures | $((CAUGHT * LO))–$((CAUGHT * HI)) s | 0 s once each flag is acted on |"
echo "| estimated time saved | — | $((CAUGHT * LO))–$((CAUGHT * HI)) s = $CAUGHT × ${LO}–${HI} s per apply, restore not counted |"
echo
echo "A \`warn\` hit saves the apply only when the agent fixes the script on the warning; a \`block\` hit always does."
echo
echo "Apply cost source: skills/iterative-build-loop.md, Gate cost: \"$(printf '%s' "$COSTLINE" | sed 's/^ *//')\""
