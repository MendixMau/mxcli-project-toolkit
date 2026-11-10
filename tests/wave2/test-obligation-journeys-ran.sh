#!/usr/bin/env bash
# Usage: bash tests/wave2/test-obligation-journeys-ran.sh [path-to-gate-check.sh]
#   (or bin/lib/obligation-check.sh directly; a bin/<x>.sh argument maps to bin/lib/ beside it)
#
# test-obligation-journeys-ran.sh — the journeys obligation is discharged by a journeys RUN, not by
# the summary file existing (#709).
#
# THE BUG: bin/lib/obligations.tsv's `journeys` row is `match=path` on
# .claude/loop/verify/<Module>/summary.tsv, and `_ob_find` only tested `[ -s file ]`.
# project-bin/verify-module.sh writes that file's header on every run, so a module whose runtime
# was down, whose journeys were skipped by flag, or whose runner faulted read as discharged.
#
# Golden input is CAPTURED, never hand-written: every summary.tsv below is a real
# project-bin/verify-module.sh output already committed under tests/wave2/fixtures/
# (verify-446/ and verify-659/, see their CAPTURE notes). Each one is dropped into a scratch
# project as-is and the real obligation-check.sh reads it.
set -uo pipefail

ARG="${1:?usage: test-obligation-journeys-ran.sh /path/to/bin/gate-check.sh (or /path/to/bin/lib/obligation-check.sh)}"
case "$(basename "$ARG")" in
  obligation-check.sh) OBCHECK="$ARG" ;;
  *) OBCHECK="$(cd "$(dirname "$ARG")" && pwd)/lib/obligation-check.sh" ;;
esac
[ -r "$OBCHECK" ] || { echo "test-obligation-journeys-ran: no obligation-check.sh at $OBCHECK"; exit 2; }
HERE="$(cd "$(dirname "$0")" && pwd)"
FX="$HERE/fixtures"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

# project <name> <captured summary.tsv> → a scratch project whose one module has that summary
project() {
  local d="$WORK/$1"
  mkdir -p "$d/architecture/modules/MyFirstModule" "$d/.claude/loop/verify/MyFirstModule"
  cp "$2" "$d/.claude/loop/verify/MyFirstModule/summary.tsv"
  printf '%s' "$d"
}
verdict() { bash "$OBCHECK" "$1" 2>&1 | grep -E '^Obligation journeys'; }

expect() {  # expect <label> <captured tsv> <PASS|PENDING>
  local label="$1" tsv="$2" want="$3" d out
  [ -r "$tsv" ] || { bad "$label: capture missing at $tsv"; return; }
  d="$(project "$label" "$tsv")"
  out="$(verdict "$d")"
  case "$want:$out" in
    PASS:*"journeys"*"PASS"*) ok "$label → PASS" ;;
    PENDING:*"PENDING"*"MyFirstModule"*)
      case "$out" in
        *"NOT RUN:"*MyFirstModule*) ok "$label → PENDING, NOT RUN named" ;;
        *) bad "$label: PENDING but no NOT RUN reason line: $out" ;;
      esac ;;
    *) bad "$label: expected $want, got: ${out:-<no journeys line>}" ;;
  esac
}

echo "journeys obligation: discharged by a run, not by summary.tsv existing (#709)"
expect clean          "$FX/verify-446/clean.summary.tsv"          PASS     # journeys PASS
expect finding        "$FX/verify-446/finding.summary.tsv"        PASS     # journeys ran; findings are the gate's business
expect skip-journeys  "$FX/verify-446/skip-journeys.summary.tsv"  PENDING  # --skip-journeys
expect credentials    "$FX/verify-659/credentials.summary.tsv"    PENDING  # not run: credentials
expect runner-setup   "$FX/verify-659/runner-setup.summary.tsv"   PENDING  # runner FAULT, exit 2

# A summary.tsv with only verify-module.sh's header — what an aborted run leaves — is not a run.
# The header line is lifted from a capture, not typed.
head -1 "$FX/verify-446/clean.summary.tsv" > "$WORK/header-only.tsv"
expect header-only    "$WORK/header-only.tsv"                     PENDING

echo "passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ]
