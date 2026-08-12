#!/usr/bin/env bash
# Fixture for wave-2 #3: the unanchored substring CONTENT gates — Stage 0 (triage sign-off),
# Stage 2 (validation stop condition) and Stage 7 (cutover decision row).
#
# Stage P is covered by test-stage-p.sh and is deliberately not retested here.
#
# Run it against the PRE-fix script too — that is the positive control. A suite that has only
# ever seen the fix cannot show that it discriminates. Expected on the pre-fix script (2ea198c):
# T1, T3, T4 and T7 fail (each is a confirmed false green there).
#
#   tests/wave2/test-bug03-gates.sh /path/to/gate-check.sh
#
# NOTE: gate-check.sh derives TOOLKIT_DIR from BASH_SOURCE, so a copy under /tmp silently
# changes every protocol-freshness verdict. Keep both scripts under the toolkit's bin/.
set -uo pipefail

GATE="${1:?usage: test-bug03-gates.sh /path/to/gate-check.sh}"
WORK="$(mktemp -d /tmp/bug03.XXXXXX)"
PASS=0; FAIL=0

ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

# A flat project (no analysis/<name>/ workstream) so the register and stage-file resolvers are
# no-ops here and only the content checks are under test.
mkproj() {
  d="$WORK/$1"; mkdir -p "$d/knowledge-base/brd" "$d/knowledge-base/reports"
  printf 'Toolkit commit: none\n\n| Stage | Decision | Status | Notes |\n|---|---|---|---|\n' > "$d/PROJECT.md"
  printf '{}\n' > "$d/knowledge-base/brd/F001.brd.json"
  echo "$d"
}

verdict() { "$GATE" --no-html "$1" 2>&1 | grep "^Stage $2 " | head -1; }

echo "== T1: Stage 2 must FAIL on a report that says it is NOT clean =="
# The headline false green: `grep -A2 '^## Stop condition' | grep -qi clean` matched the word
# in any polarity, and the verdict text then ASSERTED "Stop condition is Clean".
P="$(mkproj t1)"
printf '# Validation\n\n## Stop condition\n\nNOT clean, 14 findings outstanding.\n' \
  > "$P/knowledge-base/reports/validation-report.md"
V="$(verdict "$P" 2)"
case "$V" in
  *FAIL*) case "$V" in *'NOT clean'*) ok "negated stop condition fails, and quotes the line" ;;
                       *) bad "fails but does not quote the offending line: $V" ;; esac ;;
  *) bad "PASSED a report reading 'NOT clean, 14 findings outstanding': $V" ;;
esac

echo "== T2: Stage 2 still PASSES a genuinely clean report =="
P="$(mkproj t2)"
printf '# Validation\n\n## Stop condition\n\nClean — 0 findings outstanding.\n' \
  > "$P/knowledge-base/reports/validation-report.md"
V="$(verdict "$P" 2)"
case "$V" in *PASS*) ok "clean report still passes" ;; *) bad "false red on a clean report: $V" ;; esac

echo "== T3: Stage 0 must FAIL on the unfilled template sign-off =="
P="$(mkproj t3)"
printf '# Triage\n\n## Sign-off\n\nConfirmed by: [user] on [date]\n' > "$P/triage.md"
V="$(verdict "$P" 0)"
case "$V" in
  *FAIL*) case "$V" in *'[user] on [date]'*) ok "template placeholder fails, and is quoted back" ;;
                       *) bad "fails but does not name the placeholder: $V" ;; esac ;;
  *) bad "PASSED an unfilled 'Confirmed by: [user] on [date]' template: $V" ;;
esac

echo "== T4: Stage 0 must FAIL when 'Confirmed by:' is outside the ## Sign-off section =="
# The two greps were INDEPENDENT, so the string did not have to be in the section at all —
# a quoted email or a code fence satisfied the human-sign-off gate.
P="$(mkproj t4)"
printf '# Triage\n\n## Notes\n\n> Confirmed by: Someone, in an unrelated quoted email\n\n## Sign-off\n\nTBD\n' \
  > "$P/triage.md"
V="$(verdict "$P" 0)"
case "$V" in *FAIL*) ok "out-of-section 'Confirmed by:' no longer signs the gate off" ;;
             *) bad "PASSED on a 'Confirmed by:' outside ## Sign-off: $V" ;; esac

echo "== T5: Stage 0 still PASSES a real sign-off =="
P="$(mkproj t5)"
printf '# Triage\n\n## Sign-off\n\nConfirmed by: Maurits Visser on 2026-08-11\n' > "$P/triage.md"
V="$(verdict "$P" 0)"
case "$V" in *PASS*) ok "real signature still passes" ;; *) bad "false red on a real sign-off: $V" ;; esac

echo "== T6: Stage 0 still fails a missing triage.md =="
P="$(mkproj t6)"
V="$(verdict "$P" 0)"
case "$V" in *FAIL*) ok "missing triage.md still fails" ;; *) bad "missing triage.md passed: $V" ;; esac

echo "== T7: Stage 7 must FAIL when only the NOTES of an unrelated row mention the cutover =="
# Row SELECTION scanned $0, the whole row including free text. The status check was already
# field-exact (d8117be) but it was being applied to the wrong rows.
P="$(mkproj t7)"
{ printf 'Toolkit commit: none\n\n| Stage | Decision | Status | Notes |\n|---|---|---|---|\n'
  printf '| 3 | Adopt Atlas design system | CONFIRMED | groundwork for the eventual cutover |\n'
  printf '| 7 | Cutover plan | UNCONFIRMED | still drafting |\n'
} > "$P/PROJECT.md"
V="$(verdict "$P" 7)"
case "$V" in
  *FAIL*) case "$V" in *'none with a field exactly CONFIRMED'*) ok "notes-only mention fails, and distinguishes 'row present, not CONFIRMED'" ;;
                       *) bad "fails but with the wrong diagnosis: $V" ;; esac ;;
  *) bad "PASSED on a CONFIRMED row that merely MENTIONS the cutover in its notes: $V" ;;
esac

echo "== T8: Stage 7 still PASSES a real CONFIRMED cutover row =="
P="$(mkproj t8)"
{ printf 'Toolkit commit: none\n\n| Stage | Decision | Status | Notes |\n|---|---|---|---|\n'
  printf '| 3 | Adopt Atlas design system | CONFIRMED | unrelated |\n'
  printf '| 7 | Cutover plan | CONFIRMED | signed off 2026-08-10 |\n'
} > "$P/PROJECT.md"
V="$(verdict "$P" 7)"
case "$V" in *PASS*) ok "real cutover decision still passes" ;; *) bad "false red on a real cutover row: $V" ;; esac

echo "== T9: Stage 7 distinguishes 'no cutover row at all' from 'row not CONFIRMED' =="
P="$(mkproj t9)"
V="$(verdict "$P" 7)"
case "$V" in *'no cutover decision row'*) ok "empty table reports the absent row, not a bad status" ;;
             *) bad "wrong diagnosis for an empty Decisions table: $V" ;; esac

printf '\n%s: %d ok, %d FAIL\n' "$(basename "$0")" "$PASS" "$FAIL"
rm -rf "$WORK"
[ "$FAIL" -eq 0 ]
