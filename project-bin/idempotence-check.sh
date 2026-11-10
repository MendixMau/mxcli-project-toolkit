#!/usr/bin/env bash
# idempotence-check.sh — "is this script re-runnable?", answered by ONE `mxcli diff` after exec.
#
#   ./bin/idempotence-check.sh [--mpr <app.mpr>] <script.mdl>   run `mxcli diff` and grade it
#   ./bin/idempotence-check.sh --parse <diff-output-file|->      grade captured output (fixtures)
#
# Replaces the second `exec.sh --commit-first` run the per-row loop used to prove idempotence.
# Field measure (speed-night experiment D, 2026-11-09, 40 scripts on a 197 MB app): `mxcli diff`
# 1.7 s vs 35 s for the gated second exec (122 s cold); it agreed with a raw second exec on all 40,
# and it caught a #667 duplicated menu item (navigation 5 -> 6 items) that the gated second exec
# passed, because a duplicated menu item is a VALID model and the mx gate has nothing to say.
# Not a speed trick that lost a check: the gate was never able to see this.
#
# The trap this script exists for: `mxcli diff` exits 0 even when it prints `Refused:`, and a
# refused diff ends in "Summary: 0 new, 0 modified, 0 removed — exec would write nothing", i.e. the
# SAME summary an idempotent script gets. Reading the exit code, or only the Summary line, grades
# a refusal as idempotent. So the grade is built from the output, in this order:
#   1. any `Refused:` line                       -> FAIL (REFUSED: exec would stop; reason echoed)
#   2. any `New:`/`Modified:`/`Removed:` line or `--- X (current)` diff header, or a Summary with a non-zero count
#                                                -> FAIL (CHANGES: exec would write; lines echoed)
#   3. a Summary whose three counts are all 0    -> PASS
#   4. no Summary line at all                    -> UNPARSEABLE (never PASS: silence is not green)
# Parsing is by the `N new, N modified, N removed` counts, not the em-dash tail, so a locale or
# terminal that mangles "—" cannot flip the grade. CR and ANSI colour are stripped first (Git Bash).
#
# Exit: 0 PASS (idempotent) · 1 FAIL (refused or would write) · 2 UNPARSEABLE / mxcli did not run.
# A script that is re-runnable BY DESIGN of its owner (create or modify, grants) should PASS. A stub
# or an `alter page insert` is refused on re-run by design (17 of 40 corpus scripts): for those the
# verdict is informational — run the check only where the row claims re-runnability.
#
# Producer: the per-row loop, right after a successful exec.sh (iterative-build-loop.md, "Idempotence
# check"). Golden input: tests/wave2/fixtures/idempotence-diff/ (verbatim mxcli v0.28.0 captures).
set -uo pipefail
_sd="${0%/*}"; [ "$_sd" != "$0" ] || _sd=.

PARSE=""; MPR_ARG=""; SCRIPT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --parse) PARSE="${2:-}"; [ -n "$PARSE" ] || { echo "idempotence-check: --parse needs a file or -" >&2; exit 2; }; shift 2 ;;
    --mpr)   MPR_ARG="${2:-}"; shift 2 ;;
    -h|--help) sed -n 2,12p "$0"; exit 0 ;;
    *) SCRIPT="$1"; shift ;;
  esac
done

grade() {  # stdin = diff output; prints verdict lines; returns 0/1/2
  local esc line refused="" changes="" summary="" n m r
  esc="$(printf '\033')"
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    line="$(printf '%s' "$line" | sed "s/${esc}\[[0-9;]*[A-Za-z]//g")"
    case "$line" in
      Refused:*) refused="${refused}${line}"$'\n' ;;
      New:*|Modified:*|Removed:*) changes="${changes}${line}"$'\n' ;;
      '--- '*' (current)') changes="${changes}changed: ${line#--- }"$'\n' ;;   # a modified page/microflow prints as a unified diff, not a Modified: line (field run, 2026-11-10)
      Summary:*) summary="$line" ;;
    esac
  done
  if [ -n "$refused" ]; then
    echo "idempotence: FAIL (REFUSED) — a second run would stop, so the script is not re-runnable as written"
    printf '%s' "$refused" | cut -c1-300 | sed 's/^/  /'
    return 1
  fi
  if [ -z "$summary" ]; then
    echo "idempotence: UNPARSEABLE — no 'Summary:' line in the diff output; not graded PASS" >&2
    return 2
  fi
  if [[ "$summary" =~ ([0-9]+)\ new,\ ([0-9]+)\ modified,\ ([0-9]+)\ removed ]]; then
    n="${BASH_REMATCH[1]}"; m="${BASH_REMATCH[2]}"; r="${BASH_REMATCH[3]}"
  else
    echo "idempotence: UNPARSEABLE — Summary line has no 'N new, N modified, N removed' counts: $summary" >&2
    return 2
  fi
  if [ -n "$changes" ] || [ "$n" -ne 0 ] || [ "$m" -ne 0 ] || [ "$r" -ne 0 ]; then
    echo "idempotence: FAIL (CHANGES) — a second run would write: $n new, $m modified, $r removed"
    printf '%s' "$changes" | cut -c1-300 | sed 's/^/  /'
    return 1
  fi
  echo "idempotence: PASS — a second run would write nothing (0 new, 0 modified, 0 removed)"
  return 0
}

if [ -n "$PARSE" ]; then
  if [ "$PARSE" = "-" ]; then grade; exit $?; fi
  [ -r "$PARSE" ] || { echo "idempotence-check: cannot read $PARSE" >&2; exit 2; }
  grade < "$PARSE"; exit $?
fi

[ -n "$SCRIPT" ] || { echo "usage: idempotence-check.sh [--mpr <app.mpr>] <script.mdl> | --parse <file|->" >&2; exit 2; }
[ -r "$SCRIPT" ] || { echo "idempotence-check: cannot read script $SCRIPT" >&2; exit 2; }
. "$_sd/_common.sh"
MXCLI="$(find_project_mxcli 2>/dev/null || true)"
[ -n "$MXCLI" ] || { echo "idempotence-check: no project mxcli found (looked for \$PROJECT_ROOT/mxcli[.exe])" >&2; exit 2; }
MPR="${MPR_ARG:-$(find_mpr)}" || exit 2
OUT="$("$MXCLI" diff -p "$MPR" "$SCRIPT" 2>&1)"; RC=$?
if [ "$RC" -ne 0 ]; then
  echo "idempotence: UNPARSEABLE — mxcli diff itself exited $RC (it normally exits 0 even on Refused):" >&2
  printf '%s\n' "$OUT" | tail -5 | sed 's/^/  /' >&2
  exit 2
fi
printf '%s\n' "$OUT" | grade
