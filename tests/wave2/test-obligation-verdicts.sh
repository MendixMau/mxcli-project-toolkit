#!/usr/bin/env bash
# Usage: bash tests/wave2/test-obligation-verdicts.sh [path-to-gate-check.sh]
#   (or bin/lib/obligation-check.sh directly; a bin/<x>.sh argument maps to bin/lib/ beside it)
#
# test-obligation-verdicts.sh — an obligation discharged by a mark that says NO itself is FAIL, not
# PASS (field regression run, 2026-11-17; #835, #836 part A).
#
# THE BUG: `skeleton` printed "PASS — 1 of 1 discharged" over docs/skeleton-proof.md reading
# "3 of 6 rows - row 2 NOT MET ... Skeleton NOT proven"; `journeys` printed PASS over a summary.tsv
# whose positive-control row was FINDING (runner: "control verdict: FAIL"). Presence + denominator
# were read, the verdict in the mark never was.
#
# Golden input:
#  - summary.tsv: control-fail / quick come from the real project-bin/verify-module.sh
#    (CAPTURE=<dir> bash tests/wave2/test-verify-module-446.sh project-bin/verify-module.sh; a stub
#    runner exits 1 on --positive-control, as the real one does when a rung is unproven — see
#    test-journey-control-exit.sh — and verify-module.sh's own _report_result writes the row).
#    clean / finding are the older captures under fixtures/verify-446/.
#  - skeleton-proof.md: the failing line is the #835 report's text verbatim; the passing and
#    NOT RUN lines are the shapes skills/walking-skeleton.md completion step 6 prescribes.
set -uo pipefail

ARG="${1:?usage: test-obligation-verdicts.sh /path/to/bin/gate-check.sh (or bin/lib/obligation-check.sh)}"
case "$(basename "$ARG")" in
  obligation-check.sh) OBCHECK="$ARG" ;;
  *) OBCHECK="$(cd "$(dirname "$ARG")" && pwd)/lib/obligation-check.sh" ;;
esac
[ -r "$OBCHECK" ] || { echo "test-obligation-verdicts: no obligation-check.sh at $OBCHECK"; exit 2; }
HERE="$(cd "$(dirname "$0")" && pwd)"
FX="$HERE/fixtures/verify-446"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0; N=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

newproj() { N=$((N+1)); mkdir -p "$WORK/p$N/architecture/modules/MyFirstModule" "$WORK/p$N/.claude/loop/verify/MyFirstModule" "$WORK/p$N/docs"; printf '%s' "$WORK/p$N"; }
line() { bash "$OBCHECK" "$1" 2>&1 | grep -E "^Obligation $2 +(PASS|FAIL|PENDING|FAULT)"; }
note() { bash "$OBCHECK" "$1" 2>&1 | grep -E "^Obligation $2 +(NO CONTROL|INCOMPLETE)"; }
expect() { # label want out
  case "$3" in *"$2"*) ok "$1 → $2" ;; *) bad "$1: expected $2, got: ${3:-<no line>}" ;; esac
}

echo "journeys: the positive-control row is read"
for t in control-fail quick clean finding; do [ -r "$FX/$t.summary.tsv" ] || bad "capture missing: $t"; done
d="$(newproj)"; cp "$FX/control-fail.summary.tsv" "$d/.claude/loop/verify/MyFirstModule/summary.tsv"
expect "control FINDING" "FAIL — 0 of 1" "$(line "$d" journeys)"
d="$(newproj)"; cp "$FX/clean.summary.tsv" "$d/.claude/loop/verify/MyFirstModule/summary.tsv"
expect "control PASS" "PASS — 1 of 1" "$(line "$d" journeys)"
[ -z "$(note "$d" journeys)" ] && ok "control PASS → no extra note" || bad "control PASS printed a note"
d="$(newproj)"; cp "$FX/finding.summary.tsv" "$d/.claude/loop/verify/MyFirstModule/summary.tsv"
expect "other rung FINDING, control PASS" "PASS — 1 of 1" "$(line "$d" journeys)"
d="$(newproj)"; cp "$FX/quick.summary.tsv" "$d/.claude/loop/verify/MyFirstModule/summary.tsv"
expect "no control row (--quick): not a FAIL" "PASS — 1 of 1" "$(line "$d" journeys)"
case "$(note "$d" journeys)" in *"NO CONTROL VERDICT RECORDED"*MyFirstModule*) ok "no control row → said out loud" ;; *) bad "no control row not named" ;; esac

echo "skeleton: the verdict in docs/skeleton-proof.md is read"
sk() { local p; p="$(newproj)"; printf '%s\n' "$1" > "$p/docs/skeleton-proof.md"; printf '%s' "$p"; }
d="$(sk '3 of 6 rows - row 2 NOT MET (journey did not pass). Skeleton NOT proven')"
expect "NOT MET / NOT proven" "FAIL — 0 of 1" "$(line "$d" skeleton)"
d="$(sk 'Skeleton proven 2026-09-04: exec pass, journey pass/fail-control, look done — 5 of 5 rows')"
expect "5 of 5, line contains fail-control" "PASS — 1 of 1" "$(line "$d" skeleton)"
d="$(sk 'Skeleton proven 2026-09-04: exec pass, journey pass/fail-control — 4 of 5 — look NOT RUN')"
expect "4 of 5 NOT RUN" "PENDING — 0 of 1" "$(line "$d" skeleton)"
case "$(note "$d" skeleton)" in *"INCOMPLETE"*"4 of 5"*) ok "4 of 5 → INCOMPLETE named" ;; *) bad "INCOMPLETE line missing" ;; esac
d="$(sk 'Skeleton proven, trust me')"
expect "no denominator still FAULT" "FAULT" "$(line "$d" skeleton)"
d="$(sk 'Skeleton proven 2026/11/17: 5 of 5 rows')"
expect "date with slashes is not a denominator" "PASS — 1 of 1" "$(line "$d" skeleton)"

d="$(sk 'Criteria 1 of 6 .. 6 of 6 — see below
Skeleton proven 2026-09-04: exec pass, journey pass/fail-control, look done — 6 of 6 rows')"
expect "header N of M above a proven verdict line" "PASS — 1 of 1" "$(line "$d" skeleton)"
d="$(sk 'Row 1 of 5 - fail-control NOT MET earlier, fixed
Skeleton proven 2026-09-04 — 5 of 5 rows')"
expect "earlier NOT MET text on a non-verdict line" "PASS — 1 of 1" "$(line "$d" skeleton)"
d="$(sk 'Skeleton proven 2026-09-04 — 4 of 5 rows, row 3 NOT MET')"
expect "NOT MET only (no NOT proven)" "FAIL — 0 of 1" "$(line "$d" skeleton)"
d="$(sk 'Skeleton unproven — 2 of 5 rows')"
expect "unproven only" "FAIL — 0 of 1" "$(line "$d" skeleton)"
echo "journeys: a control row that is FAULT / SKIPPED is no verdict, said out loud"
for v in FAULT SKIPPED; do
  d="$(newproj)"; awk -F'\t' -v OFS='\t' -v v="$v" '$1 ~ /positive control/ {$2=v} {print}' "$FX/clean.summary.tsv" > "$d/.claude/loop/verify/MyFirstModule/summary.tsv"
  expect "control $v" "PASS — 1 of 1" "$(line "$d" journeys)"
  case "$(note "$d" journeys)" in *"NO CONTROL VERDICT RECORDED"*) ok "control $v → named" ;; *) bad "control $v not named" ;; esac
done

echo "passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ]
