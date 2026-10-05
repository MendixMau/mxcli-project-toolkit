#!/usr/bin/env bash
# Fixture for wave-2 #3: the unanchored substring CONTENT gates — Stage 0 (triage sign-off),
# Stage 2 (validation stop condition) and Stage 7 (cutover decision row); T12 adds the
# existing-app-change parked state (Stage 0) and that mode's Stage 1 hint; T16 the Stage 4
# closing rows (brd-to-build-plan.md, #163).
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

echo "== T6: Stage 0 does not PASS a missing triage.md =="
# Vocabulary widened 2026-08-20: an ABSENT artifact is PENDING ("not started"), and FAIL keeps
# the narrower meaning "something is there and it is wrong" — the discrimination T1/T3/T4 above
# are built on. The assertion here is the INTENT ("a missing triage.md does not pass"), not the
# word, so it survives that change and still catches the only bug it was ever guarding against.
V="$(verdict "$(mkproj t6)" 0)"
case "$V" in
  *PASS*)             bad "missing triage.md PASSED: $V" ;;
  *PENDING*|*FAIL*)   ok "missing triage.md does not pass (${V#*: })" ;;
  *)                  bad "no Stage 0 verdict at all for a missing triage.md: $V" ;;
esac

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
  *FAIL*) case "$V" in *'none with a field starting CONFIRMED'*) ok "notes-only mention fails, and distinguishes 'row present, not CONFIRMED'" ;;
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

echo "== T10: a stage run names the runbook lines to read — derived from the headings, not hard-coded =="
# Added 2026-09-09: the 11,700-word runbook was read whole every session. A stage run must say
# which span is the stage's own section and which is §1b, and the numbers must be the file's.
RB="$(cd "$(dirname "$GATE")/.." && pwd)/skills/conversion-runbook.md"
P="$(mkproj t10)"
printf '# Validation\n\n## Stop condition\n\nClean.\n' > "$P/knowledge-base/reports/validation-report.md"
L="$("$GATE" --no-html "$P" 2 2>&1 | grep '^Read for this gate:' | head -1)"
S2="$(grep -n '^### Stage 2 ' "$RB" | head -1 | cut -d: -f1)"
S1B="$(grep -n '^## 1b\.' "$RB" | head -1 | cut -d: -f1)"
case "$L" in
  'Read for this gate: skills/conversion-runbook.md §"Stage 2 — Requirements" (lines '"$S2"'–'*') + §1b Live Checklist (lines '"$S1B"'–'*)
    ok "names the Stage 2 section and §1b, each starting at its real heading line ($S2, $S1B)" ;;
  '') bad "no 'Read for this gate:' line in a stage-2 run" ;;
  *)  bad "wrong shape or wrong lines: $L" ;;
esac
# The span ends where the next heading starts: the line after B must be a ## or ### heading.
B="$(printf '%s' "$L" | sed -n 's/.*§"Stage 2 — Requirements" (lines [0-9]*–\([0-9]*\)).*/\1/p')"
NEXT="$(sed -n "$((B + 1))p" "$RB" 2>/dev/null)"
case "$NEXT" in '## '*|'### '*) ok "the stage span ends right before the next heading ('${NEXT%% —*}')" ;; *) bad "span end $B is not followed by a heading: '$NEXT'" ;; esac
# build-ready reads Stage 5's section.
L="$("$GATE" --no-html "$P" build-ready 2>&1 | grep '^Read for this gate:' | head -1)"
case "$L" in *'§"Stage 5 — Build"'*) ok "build-ready points at Stage 5's section" ;; *) bad "build-ready line: $L" ;; esac
# A full (no-stage) run prints no such line — there is no single stage to read for.
N="$("$GATE" --no-html "$P" 2>&1 | grep -c '^Read for this gate:')"
[ "$N" -eq 0 ] && ok "a whole-project run names no single span" || bad "whole-project run printed a stage span"

echo "== T11: Stage 7 entry-mode arm matches the documented phrase and the short token, never the bare substring 'existing' =="
# bug03's original fix (`*existing*`) waived Stage 7 for ANY entry mode that merely contained the
# word "existing", including a real migration project. The corrected arm must still waive the
# gate for the mode's documented phrase and its short token, while a migration project whose
# entry-mode line happens to contain "existing" keeps its Stage 7 gate PENDING.
P="$(mkproj t11)"
printf 'Toolkit commit: none\n\n| Stage | Decision | Status | Notes |\n|---|---|---|---|\n\nEntry mode: Migration from an existing Oracle Forms system\n' \
  > "$P/PROJECT.md"
V="$(verdict "$P" 7)"
case "$V" in
  *PENDING*) ok "a migration entry mode that merely contains 'existing' still PENDS stage 7" ;;
  *) bad "migration entry mode false-waived stage 7: $V" ;;
esac

P="$(mkproj t11-phrase)"
printf 'Toolkit commit: none\n\n| Stage | Decision | Status | Notes |\n|---|---|---|---|\n\nEntry mode: Change an existing app\n' \
  > "$P/PROJECT.md"
V="$(verdict "$P" 7)"
case "$V" in *WAIVED*) ok "the documented phrase 'Change an existing app' still waives stage 7" ;;
             *) bad "documented existing-app phrase no longer waives stage 7: $V" ;; esac

P="$(mkproj t11-token)"
printf 'Toolkit commit: none\n\n| Stage | Decision | Status | Notes |\n|---|---|---|---|\n\nEntry mode: existing-app\n' \
  > "$P/PROJECT.md"
V="$(verdict "$P" 7)"
case "$V" in *WAIVED*) ok "the short token 'existing-app' still waives stage 7" ;;
             *) bad "existing-app short token no longer waives stage 7: $V" ;; esac


echo "== T12: existing-app mode — a mapped app waiting on its change is PENDING, not FAIL =="
# existing-app-change.md §"Map the app first": the map runs before any slice is named, and the
# project may park there. The parked arm is narrow: this mode, the untouched placeholder, AND a
# rendered map. Drop any one and the old FAIL must come back.
mkexisting() {
  d="$WORK/$1"; mkdir -p "$d/analysis"
  printf 'Toolkit commit: none\n\n| Stage | Decision | Status | Notes |\n|---|---|---|---|\n\nEntry mode: %s\n' "$2" > "$d/PROJECT.md"
  printf '# Triage\n\n## Sign-off\n\nConfirmed by: [user] on [date]\n' > "$d/triage.md"
  echo "$d"
}
P="$(mkexisting t12-parked 'Change an existing app')"; printf '{}\n' > "$P/analysis/app-report.json"
V="$(verdict "$P" 0)"
case "$V" in *PENDING*'waiting on the change'*) ok "mapped + unsigned triage in this mode reads PENDING, parked" ;;
             *) bad "parked existing-app project not PENDING: $V" ;; esac
V="$(verdict "$P" 1)"
case "$V" in *'Path D'*) ok "Stage 1 hint names the live-model path in this mode" ;;
             *) bad "Stage 1 hint still points at extractors in existing-app mode: $V" ;; esac

P="$(mkexisting t12-unmapped 'Change an existing app')"
V="$(verdict "$P" 0)"
case "$V" in *FAIL*) ok "no map yet: the placeholder still FAILs in this mode" ;;
             *) bad "unmapped existing-app project escaped the placeholder FAIL: $V" ;; esac

P="$(mkexisting t12-migration 'Migration')"; printf '{}\n' > "$P/analysis/app-report.json"
V="$(verdict "$P" 0)"
case "$V" in *FAIL*) ok "another mode with a stray app-report.json still FAILs the placeholder" ;;
             *) bad "the parked arm leaked into migration mode: $V" ;; esac
V="$(verdict "$P" 1)"
case "$V" in *'Path D'*) bad "migration project got the existing-app Stage 1 hint: $V" ;;
             *) ok "other modes keep the extractor / kb-generation hint" ;; esac

echo "== T13: only the Decisions table counts — an Open-questions row numbered 7 is not a cutover decision =="
# Both register readers scanned every pipe row in the file, so the template's Open-questions
# table ("| # | Question | Raised at | Status |") could stand in for a stage decision whenever
# a question's number matched the stage and its Status cell said CONFIRMED.
P="$(mkproj t13)"
{ printf 'Toolkit commit: none\n\n## Decisions\n\n| Stage | Decision | Status | Notes |\n|---|---|---|---|\n'
  printf '| 3 | Adopt Atlas design system | CONFIRMED | unrelated |\n'
  printf '\n## Open questions\n\n| # | Question | Raised at | Status |\n|---|---|---|---|\n'
  printf '| 7 | Who owns the cutover weekend? | Stage 5 | CONFIRMED |\n'
  printf '| 4 | Build plan order ok? | Stage 4 | CONFIRMED |\n'
} > "$P/PROJECT.md"
V="$(verdict "$P" 7)"
case "$V" in *PASS*) bad "an Open-questions row passed Stage 7: $V" ;;
             *'no cutover decision row'*) ok "Open-questions row #7 is not a Stage-7 candidate" ;;
             *) bad "wrong diagnosis: $V" ;; esac
mkdir -p "$P/architecture"; printf '# Build plan\n' > "$P/architecture/build-plan.md"
V="$(verdict "$P" 4)"
case "$V" in *PASS*) bad "an Open-questions row passed Stage 4: $V" ;;
             *FAIL*) ok "Open-questions row #4 is not a Stage-4 decision" ;;
             *) bad "no Stage 4 FAIL: $V" ;; esac
{ printf '\n## Decisions (later)\n\n| Stage | Decision | Status | Notes |\n|---|---|---|---|\n'
  printf '| 4 | Build plan approved | CONFIRMED | |\n'
} >> "$P/PROJECT.md"
V="$(verdict "$P" 4)"
case "$V" in *PASS*) ok "a Stage-4 row in a second Stage-headed table still counts" ;;
             *) bad "false red on a real Stage-4 row: $V" ;; esac

echo "== T14: Stage 7 accepts a dated status, like every other stage (TD-07) =="
P="$(mkproj t14)"
{ printf 'Toolkit commit: none\n\n| Stage | Decision | Status | Notes |\n|---|---|---|---|\n'
  printf '| 7 | Cutover plan | CONFIRMED 2026-08-10 | signed off |\n'
} > "$P/PROJECT.md"
V="$(verdict "$P" 7)"
case "$V" in *PASS*) ok "'CONFIRMED 2026-08-10' passes Stage 7" ;; *) bad "dated CONFIRMED rejected at Stage 7: $V" ;; esac
{ printf 'Toolkit commit: none\n\n| Stage | Decision | Status | Notes |\n|---|---|---|---|\n'
  printf '| 7 | Cutover plan | NOT CONFIRMED | pending sponsor |\n'
} > "$P/PROJECT.md"
V="$(verdict "$P" 7)"
case "$V" in *FAIL*) ok "'NOT CONFIRMED' still fails Stage 7" ;; *) bad "'NOT CONFIRMED' did not fail: $V" ;; esac

echo "== T15: a register with no Stage-headed table falls back to scanning every row =="
P="$(mkproj t15)"
{ printf 'Toolkit commit: none\n\n| 7 | Cutover plan | CONFIRMED | |\n'; } > "$P/PROJECT.md"
V="$(verdict "$P" 7)"
case "$V" in *PASS*) ok "header-less register keeps the old behaviour" ;; *) bad "header-less register regressed: $V" ;; esac

echo "== T16: Stage 4 reads the plan — the three closing rows are counted (#163, field case 2026-10-02) =="
# check_stage_4 tested only that build-plan.md existed and was approved. A 137-row plan for 7
# modules with 0 close rows, 0 coherence rows and no final gate row printed PASS, and the build
# reached DONE with look/sweep/journeys at 0 of 7. Positive control: the pre-fix script PASSES
# the first case below.
HDR='| # | Kind | Step | Produces | Depends on | Skills | State |\n|---|---|---|---|---|---|---|\n'
P="$(mkproj t16)"; printf '| 4 | Build plan approved | CONFIRMED | |\n' >> "$P/PROJECT.md"
mkdir -p "$P/architecture/modules/Orders" "$P/architecture/modules/Customers" "$P/architecture/modules/Billing"
printf "# Plan\n\n$HDR| 1 | BRIEF | Orders brief | | | none | built |\n| 2 | BUILD | 10-orders.mdl | | 1 | none | built |\n| 3 | PROVE | acceptance test | | 2 | none | built |\n" \
  > "$P/architecture/build-plan.md"
V="$(verdict "$P" 4)"
case "$V" in *FAIL*'Billing Customers Orders'*'0 of 1 coherence'*'last numbered row'*) ok "a plan with no closing rows FAILs and names each missing one" ;;
             *) bad "a plan with no closing rows was not refused with its gaps named: $V" ;; esac
printf "# Plan\n\n$HDR| 1 | BUILD | 10-orders.mdl | | | none | built |\n| 2 | HARNESS | \`bin/verify-module.sh Orders\`, then LOOK + CONFIRM | | 1 | none | |\n| 3 | HARNESS | bin/verify-module.sh Customers | | | none | |\n| 4 | HARNESS | process-coherence-pass.md on Orders + Customers | | | none | |\n| 5 | HARNESS | bin/verify-module.sh Billing | | | none | |\n| 6 | RUN | \`gate-check.sh <project> 5\` | | | none | |\n\n## Open questions\n\n| # | Question | Status |\n|---|---|---|\n| 1 | who signs off | open |\n" \
  > "$P/architecture/build-plan.md"
V="$(verdict "$P" 4)"
case "$V" in *PASS*'3 of 3 modules'*) ok "a plan with every closing row passes; a numbered question table after it is not a step" ;;
             *) bad "false red on a complete plan: $V" ;; esac
sed -i.bak 's/gate-check.sh <project> 5/gate-check.sh <project> 3/' "$P/architecture/build-plan.md"
V="$(verdict "$P" 4)"
case "$V" in *FAIL*'last numbered row'*) ok "a final gate row for the wrong stage is not the closing row" ;;
             *) bad "a final 'gate-check.sh 3' row passed: $V" ;; esac
P="$(mkproj t16b)"; printf '| 4 | Build plan approved | CONFIRMED | |\n' >> "$P/PROJECT.md"; mkdir -p "$P/architecture"
printf "# Plan\n\n$HDR| 1 | BUILD | 10.mdl | | | none | |\n| 2 | RUN | gate-check.sh . 5 | | | none | |\n" > "$P/architecture/build-plan.md"
V="$(verdict "$P" 4)"
case "$V" in *FAIL*'no module has one'*) ok "with no briefs yet, a plan still owes at least one module close row" ;;
             *) bad "a plan with no module dirs and no close row passed: $V" ;; esac

printf '\n%s: %d ok, %d FAIL\n' "$(basename "$0")" "$PASS" "$FAIL"
rm -rf "$WORK"
[ "$FAIL" -eq 0 ]
