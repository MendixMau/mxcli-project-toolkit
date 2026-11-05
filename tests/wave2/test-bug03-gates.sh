#!/usr/bin/env bash
# Fixture for wave-2 #3: the unanchored substring CONTENT gates — Stage 0 (triage sign-off),
# Stage 2 (validation stop condition) and Stage 7 (cutover decision row); T12 adds the
# existing-app-change parked state (Stage 0) and that mode's Stage 1 hint; T16 the Stage 4
# closing rows (brd-to-build-plan.md, #163); T19 the facts lock at Stage 2.
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
  # A minimal BRD of the documented shape (brd-generation.md: modules[], useCases[]). It was `{}`
  # until Stage 2 started asking brd-report.sh which sections each BRD owes (2026-11-05).
  printf '{"id":"F001","modules":["Core"],"useCases":[]}\n' > "$d/knowledge-base/brd/F001.brd.json"
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
printf '# Orders brief\n' > "$P/architecture/modules/Orders/module-brief.md"   # Stage 4 owes the first brief
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

echo "== T17: a mid-stage decision is not the stage approval (#477) =="
# #207 prefixes a FAIL with APPROVED OVER A FAILING GATE when the register says the stage was
# approved. It read ANY CONFIRMED row of that stage as the approval, so the field project's
# mid-Stage-5 "| 5 | Sub-agents run on Sonnet | CONFIRMED | user in chat |" (verbatim from the
# issue) raised it on a stage still being built, and status.sh told the lead to re-open an
# approval nobody gave. Stage 4 stands in for 5 here: its FAIL needs only a plan with no closing
# rows (T16), so no harness obligations have to be staged. The approval must still be flagged
# when it is real: an explicit exit row, or the project having moved on to a later stage.
# Positive control: on the pre-fix script t17a and t17f print the flag.
t17() {  # t17 <name> <register rows...> -> the Stage 4 line, and the summary line if any
  local P; P="$(mkproj "$1")"; shift
  printf '%s\n' "$@" >> "$P/PROJECT.md"
  mkdir -p "$P/architecture/modules/Orders"
  printf "# Plan\n\n$HDR| 1 | BUILD | 10-orders.mdl | | | none | built |\n" > "$P/architecture/build-plan.md"
  "$GATE" --no-html "$P" 2>&1 | grep -E '^Stage 4 |^Approved over a failing gate:'
}
flagged() { case "$1" in *'APPROVED OVER A FAILING GATE'*'Approved over a failing gate: Stage 4'*) return 0 ;; esac; return 1; }
MID='| 4 | Sub-agents run on Sonnet | CONFIRMED | user in chat |'
V="$(t17 t17a "$MID")"
case "$V" in *FAIL*) ;; *) bad "t17a setup: Stage 4 did not FAIL: $V" ;; esac
case "$V" in *'APPROVED OVER'*|*'Approved over'*) bad "a mid-stage decision raised APPROVED OVER A FAILING GATE (#477): $V" ;;
             *) ok "a mid-stage CONFIRMED decision does not read as the stage approval" ;; esac
V="$(t17 t17b "| 4 | Purchase requests above 5k need approval | CONFIRMED | |")"
case "$V" in *'APPROVED OVER'*) bad "a domain decision mentioning approval raised the flag: $V" ;;
             *) ok "a domain decision that mentions approval is not a stage approval" ;; esac
V="$(t17 t17c "$MID" "| 4 | Stage 4 approved | CONFIRMED | user in chat |")"
flagged "$V" && ok "an explicit 'Stage 4 approved' row over a FAIL is still flagged, in the note and the summary" \
  || bad "an explicit Stage-4 approval over a FAIL was not flagged: $V"
V="$(t17 t17d "| 4 | Stage 4 gate: signed off | CONFIRMED 2026-10-20 | |")"
flagged "$V" && ok "'Stage 4 gate: signed off' with a dated CONFIRMED is an approval" || bad "dated gate sign-off not flagged: $V"
V="$(t17 t17e "| 4 | Build plan approved | CONFIRMED | |")"
flagged "$V" && ok "a short '<artifact> approved' row is an approval" || bad "'Build plan approved' not flagged: $V"
V="$(t17 t17f "$MID" "| 5 | Test depth: journeys per module | CONFIRMED | |")"
flagged "$V" && ok "a CONFIRMED decision for a later stage means the project moved past Stage 4: flagged" \
  || bad "moving on to Stage 5 over a failing Stage 4 was not flagged: $V"
V="$(t17 t17g "| 4 | Stage 4 approved | ASSUMED | |" "| 3 | Stage 4 approved | CONFIRMED | |")"
case "$V" in *'APPROVED OVER'*) bad "an ASSUMED exit row, or another stage's row, raised the flag: $V" ;;
             *) ok "only a CONFIRMED exit row of Stage 4 itself counts" ;; esac
V="$(t17 t17h "$MID" "## Open questions" "" "| # | Question | Raised at | Status |" "|---|---|---|---|" "| 5 | Stage 4 approved? | Stage 4 | CONFIRMED |")"
case "$V" in *'APPROVED OVER'*) bad "an Open-questions row stood in for the approval: $V" ;;
             *) ok "an Open-questions row is not a stage approval (same table scoping as T13)" ;; esac

# Review of #483: the exit wordings people actually write, and rows that must not count.
V="$(t17 t17i "| 4 | Stage 4 — approved with conditions | CONFIRMED | |")"
flagged "$V" && ok "'Stage 4 — approved with conditions' (em dash) is an approval" || bad "em-dash exit row not flagged: $V"
V="$(t17 t17j "| 4 | Approved: Stage 4 build plan | CONFIRMED | |")"
flagged "$V" && ok "'Approved: Stage 4 build plan' is an approval" || bad "'Approved: Stage N' form not flagged: $V"
for d in 'Status values: draft, submitted, approved' 'Requests over 5k must be approved' 'Approval gate closed after 30 days' 'Stage 40 approved'; do
  V="$(t17 t17k "| 4 | $d | CONFIRMED | |")"
  case "$V" in *'APPROVED OVER'*) bad "a domain decision raised the flag: '$d'" ;;
               *) ok "domain wording is not an approval: '$d'" ;; esac
done
# A failing Stage 5 with no rows of its own: the LOOK obligation owes one unseen page.
t17s5() {  # t17s5 <name> <register rows...> -> the Stage 5 line, and the summary line if any
  local P; P="$(mkproj "$1")"; shift
  printf '%s\n' "$@" >> "$P/PROJECT.md"
  mkdir -p "$P/.claude/loop/look"
  printf '%s\t%s\t%s\t%s\n' "$(date +%s)" "2026-10-20T10:00:00Z" "Orders.Order_Overview" "10-orders.mdl" > "$P/.claude/loop/look/owed.tsv"
  "$GATE" --no-html "$P" 2>&1 | grep -E '^Stage 5 |^Approved over a failing gate:'
}
V="$(t17s5 t17l "| 7 | No legacy system, no cutover | CONFIRMED | |")"
case "$V" in *FAIL*) ;; *) bad "t17l setup: Stage 5 did not FAIL: $V" ;; esac
case "$V" in *'APPROVED OVER'*|*'Approved over'*) bad "an early 'no cutover' Stage-7 row flagged a mid-build Stage 5: $V" ;;
             *) ok "a Stage-7 'No legacy system, no cutover' row is not evidence Stage 5 was approved" ;; esac
V="$(t17s5 t17m "| 6 | Test depth: journeys per module | CONFIRMED | |")"
case "$V" in *'APPROVED OVER'*|*'Approved over'*) bad "a forward-filed Stage-6 row flagged a Stage 5 with no rows of its own: $V" ;;
             *) ok "a forward-filed Stage-6 decision does not approve a Stage 5 with no rows of its own" ;; esac

echo "== T18: build-ready names a multi-line {{PLACEHOLDER}} left in an agent stub (#509) =="
# The real templates: mdl-agent.md carries PROJECT_LOCAL_SOURCES_OF_TRUTH over four lines. The
# per-line grep never saw it, so an untouched stub read "no unfilled placeholders". WARN only.
TK="$(cd "$(dirname "$GATE")/.." && pwd)"
P="$(mkproj t18)"; mkdir -p "$P/.claude/agents"
for a in ba-agent architect-agent mdl-agent gate-agent test-agent review-agent; do
  # Fill every single-line placeholder so only the multi-line one is left.
  sed -E 's/\{\{[A-Z][A-Z0-9_]*[^}]*\}\}/filled/g' "$TK/agents/$a.md" > "$P/.claude/agents/$a.md"
done
OUT="$("$GATE" --no-html "$P" build-ready 2>&1)"
case "$OUT" in *'multi-line placeholder(s) still unfilled: {{PROJECT_LOCAL_SOURCES_OF_TRUTH'*) ok "names the multi-line placeholder" ;;
  *) bad "multi-line placeholder not named: $(printf '%s' "$OUT" | grep -i placeholder)" ;; esac
case "$OUT" in *'no unfilled placeholders'*) bad "still claims no unfilled placeholders" ;; *) ok "does not claim the stubs are complete" ;; esac
case "$OUT" in *'still have unfilled placeholders'*) bad "the multi-line case FAILs (WARN expected): $(printf '%s' "$OUT" | grep -i placeholder)" ;; *) ok "a multi-line placeholder is a WARN, not a FAIL" ;; esac
# Filled: the warning is gone.
perl -0777 -pi -e 's/\{\{PROJECT_LOCAL_SOURCES_OF_TRUTH.*?\}\}/filled/s' "$P/.claude/agents/mdl-agent.md"
OUT="$("$GATE" --no-html "$P" build-ready 2>&1)"
case "$OUT" in *'no unfilled placeholders'*) ok "a filled stub reads clean" ;; *) bad "filled stub not clean: $(printf '%s' "$OUT" | grep -i placeholder)" ;; esac

echo "== T19: Stage 2 reads the facts lock once there are 2+ BRDs =="
P="$(mkproj t19)"
printf '# Validation\n\n## Stop condition\n\nClean.\n' > "$P/knowledge-base/reports/validation-report.md"
V="$(verdict "$P" 2)"
case "$V" in *PASS*) case "$V" in *'facts lock'*) bad "1 BRD already gets a facts-lock note: $V" ;; *) ok "1 BRD: unchanged, no facts-lock note" ;; esac ;; *) bad "1 BRD: $V" ;; esac
printf '{ "id":"F001","modules":["Core"],"useCases":[],"domainEntities":[{"entity":"WIPStatus"}] }\n' > "$P/knowledge-base/brd/F001.brd.json"
printf '{ "id":"F002","modules":["Core"],"useCases":[],"domainEntities":[{"entity":"WIPStatus"}] }\n' > "$P/knowledge-base/brd/F002.brd.json"
V="$(verdict "$P" 2)"
case "$V" in *PASS*'no facts lock'*) ok "2 BRDs, no lock: still PASS, with a note naming facts-lock build" ;; *) bad "2 BRDs, no lock: $V" ;; esac
TK="$(cd "$(dirname "$GATE")/.." && pwd)"
mkdir -p "$P/analysis"; bash "$TK/bin/facts-lock.sh" "$P" build >/dev/null 2>&1
V="$(verdict "$P" 2)"
case "$V" in *PASS*) case "$V" in *'facts lock'*) bad "agreeing BRDs with a lock still noted: $V" ;; *) ok "lock built, BRDs agree: plain PASS" ;; esac ;; *) bad "lock built, BRDs agree: $V" ;; esac
printf '{ "id":"F002","modules":["Core"],"useCases":[],"domainEntities":[{"entity":"WipStatus"}] }\n' > "$P/knowledge-base/brd/F002.brd.json"
V="$(verdict "$P" 2)"
case "$V" in *FAIL*'WipStatus'*) ok "a BRD that contradicts a frozen name FAILs Stage 2 and quotes it" ;; *) bad "contradicted frozen name not caught: $V" ;; esac

# ---- 2026-11-05 regression experiment: five broken copies of a real project all read PASS at 0-4.
# The plan shapes below are the field shapes: rows of ONE table separated by blank lines (a claims
# block sits between them in the real plan), a BRIEF row naming its modules in a brace list.
echo "== T20: Stage 2 reads BRD shape through brd-report.sh — a deleted required section FAILs =="
P="$(mkproj t20)"
printf '# Validation\n\n## Stop condition\n\nClean.\n' > "$P/knowledge-base/reports/validation-report.md"
printf '{"id":"F001","provenance":"requirements","modules":["Purchasing"],"pages":[]}\n' > "$P/knowledge-base/brd/F001.brd.json"
V="$(verdict "$P" 2)"
case "$V" in *PASS*) ok "useCases absent on a non-code-extracted BRD: a brd-report fault, not a gate FAIL (review of #618)" ;;
             *) bad "documents-style BRD without useCases FAILed: $V" ;; esac
printf '{"id":"F001","provenance":"documents","modules":["Purchasing"]}\n' > "$P/knowledge-base/brd/F001.brd.json"
V="$(verdict "$P" 2)"
case "$V" in *PASS*) ok "documents provenance, no useCases: PASS" ;; *) bad "documents BRD without useCases FAILed: $V" ;; esac
printf '{"id":"F001","provenance":"code-extracted","modules":["Orders"],"domainEntities":[],"microflows":[],"useCases":[]}\n' > "$P/knowledge-base/brd/F001.brd.json"
V="$(verdict "$P" 2)"
case "$V" in *FAIL*'F001.brd.json: pages'*) ok "code-extracted BRD with its pages key deleted: FAIL names the BRD and the section" ;;
             *) bad "deleted pages on a code-extracted BRD not caught: $V" ;; esac
printf '{"id":"F001","provenance":"documents","useCases":[]}\n' > "$P/knowledge-base/brd/F001.brd.json"
V="$(verdict "$P" 2)"
case "$V" in *FAIL*'F001.brd.json: modules'*) ok "a BRD naming no module FAILs" ;; *) bad "no-module BRD: $V" ;; esac
printf '{"id":"F001","provenance":"documents","modules":["Purchasing"],"useCases":[]}\n' > "$P/knowledge-base/brd/F001.brd.json"
V="$(verdict "$P" 2)"
case "$V" in *PASS*) ok "a present-but-empty section is an answer, not a missing one: PASS" ;; *) bad "empty useCases read as missing: $V" ;; esac
printf '{"id":"F001","provenance":"code-extracted","modules":["Orders"],"domainEntities":[],"microflows":[],"useCases":[]}\n' > "$P/knowledge-base/brd/F001.brd.json"
printf '\n## Toolkit position\n\nWaived artifact brds:\n' >> "$P/PROJECT.md"
V="$(verdict "$P" 2)"
case "$V" in *FAIL*'pages'*) ok "a reasonless 'Waived artifact brds:' does not excuse it" ;; *) bad "reasonless artifact waiver excused it: $V" ;; esac
printf 'Waived artifact brds: backend-only module, no pages by design\n' >> "$P/PROJECT.md"
V="$(verdict "$P" 2)"
case "$V" in *PASS*'waived — backend-only module'*) ok "'Waived artifact brds: <reason>' excuses it and the PASS line says so" ;; *) bad "artifact waiver: $V" ;; esac
printf '{"id":"F001",\n' > "$P/knowledge-base/brd/F002.brd.json"
sed -i.bak '/^Waived artifact brds:/d' "$P/PROJECT.md"; rm -f "$P/PROJECT.md.bak"
V="$(verdict "$P" 2)"
case "$V" in *FAIL*'not valid JSON'*) ok "a BRD that is not JSON FAILs Stage 2" ;; *) bad "invalid JSON BRD: $V" ;; esac

echo "== T21: Stage 4 reads what the plan points at — dependencies, the first brief, the coverage ledger =="
s4proj() { # a Stage-4 PASS: closing rows, CONFIRMED, two modules, both briefs, field-shaped rows
  P="$(mkproj "$1")"; printf '| 4 | Build plan approved | CONFIRMED | |\n' >> "$P/PROJECT.md"
  mkdir -p "$P/architecture/modules/Purchasing" "$P/architecture/modules/Approval"
  printf '# brief\n' > "$P/architecture/modules/Purchasing/module-brief.md"
  printf '# brief\n' > "$P/architecture/modules/Approval/module-brief.md"
  printf '%s\n' '# Plan' '' '## Phase 1 — App scaffold and domain' '' \
    '| # | Kind | Step | Produces / Proves | Depends on | Skills | State |' '|---|---|---|---|---|---|---|' \
    '| 1 | `BRIEF` | Check `architecture/modules/{Purchasing,Approval}/module-brief.md` exist; create if absent | Briefs | — | none | not built |' \
    '| 2 | `BUILD` | 010-domain.mdl | domain | 1 | none | not built |' '' \
    '| 3 | `BUILD` | 020-approval.mdl | domain | 2 | none | not built |' '' \
    '| 4 | `PROVE` | mxcli check | 0 errors | 2–3 | none | not built |' '' \
    '| 5 | `HARNESS` | `bin/verify-module.sh Purchasing` | close | 4 | none | not built |' \
    '| 6 | `HARNESS` | `bin/verify-module.sh Approval` | close | 4 | none | not built |' \
    '| 7 | `HARNESS` | process-coherence-pass.md on Purchasing + Approval | coherence | 5, 6 | none | not built |' \
    '| 8 | `RUN` | `gate-check.sh <project> 5` | gate | 7 | none | not built |' > "$P/architecture/build-plan.md"
}
s4proj t21
V="$(verdict "$P" 4)"
case "$V" in *PASS*) ok "field-shaped plan (blank lines between rows, en-dash range) passes" ;; *) bad "false red on the field-shaped plan: $V" ;; esac
sed -i.bak 's/| 0 errors | 2–3 |/| 0 errors | 2–3, 99 |/' "$P/architecture/build-plan.md"; rm -f "$P/architecture/build-plan.md.bak"
V="$(verdict "$P" 4)"
case "$V" in *FAIL*'row 4 → 99'*) ok "a row depending on row 99 FAILs and names both" ;; *) bad "dangling dependency not caught: $V" ;; esac
"$GATE" "$P" --waive artifact/build-plan --reason "row 99 is the client-side cutover script, tracked in their plan" >/dev/null 2>&1
grep -q '^Waived artifact build-plan: row 99 is the client-side' "$P/PROJECT.md" && ok "--waive artifact/<id> --reason writes the register line" || bad "--waive artifact/ did not write: $(grep -i waived "$P/PROJECT.md")"
V="$(verdict "$P" 4)"
case "$V" in *PASS*'build-plan finding waived'*) ok "'Waived artifact build-plan: <reason>' excuses it" ;; *) bad "build-plan waiver: $V" ;; esac
s4proj t21b; rm "$P/architecture/modules/Purchasing/module-brief.md"
V="$(verdict "$P" 4)"
case "$V" in *FAIL*'no module brief for: Purchasing'*) ok "the first BRIEF row's module with no brief FAILs" ;; *) bad "missing first brief not caught: $V" ;; esac
printf '%s\n' '' '## Module brief — Purchasing' '' 'Access table here.' >> "$P/architecture/build-plan.md"
V="$(verdict "$P" 4)"
case "$V" in *PASS*) ok "a '## Module brief — <M>' section in the plan is a brief" ;; *) bad "plan brief section not accepted: $V" ;; esac
s4proj t21c; sed -i.bak 's/{Purchasing,Approval}/Purchasing/' "$P/architecture/build-plan.md"; rm -f "$P/architecture/build-plan.md.bak"
rm "$P/architecture/modules/Approval/module-brief.md"
V="$(verdict "$P" 4)"
case "$V" in *PASS*) ok "a later module's brief is just-in-time: not owed at Stage 4" ;; *) bad "JIT brief reported: $V" ;; esac
s4proj t21d
printf '{"id":"F001","modules":["Purchasing"],"useCases":[{"id":"UC1","title":"Submit"}]}\n' > "$P/knowledge-base/brd/F001.brd.json"
V="$(printf '%s\n' '| pointer | type | title | slice | writeMode | acceptance | status |' '|---|---|---|---|---|---|---|' '| /id | leaf | r | 1 | exec | r | x |' > "$P/architecture/coverage-ledger.md"; verdict "$P" 4)"
case "$V" in *PASS*'coverage ledger not measured'*) ok "BRDs where coverage-preflight does not look (root knowledge-base/): not measured, said, not FAILed" ;; *) bad "unmeasurable ledger: $V" ;; esac
mkdir -p "$P/analysis/src"; mv "$P/knowledge-base" "$P/analysis/src/knowledge-base"
printf '%s\n' '# Coverage ledger' '' '| pointer | type | title | slice | writeMode | acceptance | status |' '|---|---|---|---|---|---|---|' \
  '| /id | leaf | row 2 | 1 | exec | row 2 | not built |' '| /modules/0 | leaf | row 2 | 1 | exec | row 2 | not built |' \
  '| /useCases/0/* (2) | leaf | row 3 | 1 | exec | row 3 | not built |' > "$P/architecture/coverage-ledger.md"
V="$(verdict "$P" 4)"
case "$V" in *PASS*'coverage ledger clean'*) ok "a clean coverage ledger is measured and named on the PASS line" ;; *) bad "clean ledger: $V" ;; esac
sed -i.bak '/useCases\/0/d' "$P/architecture/coverage-ledger.md"; rm -f "$P/architecture/coverage-ledger.md.bak"
V="$(verdict "$P" 4)"
case "$V" in *FAIL*'coverage ledger has findings'*'UNCLAIMED 2'*) ok "a ledger missing two leaves FAILs Stage 4 with the count" ;; *) bad "ledger gap not caught: $V" ;; esac
rm "$P/architecture/coverage-ledger.md"
V="$(verdict "$P" 4)"
case "$V" in *PASS*) ok "no ledger at all is NOT MEASURED, not a FAIL" ;; *) bad "absent ledger: $V" ;; esac
[ -d "$P/docs/coverage" ] && bad "the gate wrote a derived ledger into the project" || ok "the gate wrote nothing into docs/coverage/"

echo "== T22: a waiver line with no reason is not a waiver =="
P="$(mkproj t22)"
printf '\n## Toolkit position\n\nWaived stage 4:\n' >> "$P/PROJECT.md"
V="$(verdict "$P" 4)"
case "$V" in *FAIL*"'Waived stage 4:'"*'has no reason'*) ok "'Waived stage 4:' with nothing after it FAILs Stage 4 and names the line" ;; *) bad "reasonless stage waiver: $V" ;; esac
sed -i.bak 's/^Waived stage 4:$/Waived stage 4: the client owns the build plan/' "$P/PROJECT.md"; rm -f "$P/PROJECT.md.bak"
V="$(verdict "$P" 4)"
case "$V" in *WAIVED*'the client owns the build plan'*) ok "the same line with a reason WAIVES as before" ;; *) bad "reasoned waiver: $V" ;; esac
P="$(mkproj t22b)"; printf '\nWaived stages: 3, 4\n' >> "$P/PROJECT.md"
V="$(verdict "$P" 3)"
case "$V" in *FAIL*"'Waived stages:'"*'has no reason'*) ok "the aggregate spelling with no reason FAILs too" ;; *) bad "reasonless aggregate waiver: $V" ;; esac

echo "== T23: review of #618 — fixes that failed on the first PR head =="
# (1) an unsigned plan behind a stage waiver: the stage waiver must not hide a deleted brief
s4proj t23a; sed -i.bak '/^| 4 | Build plan approved/d' "$P/PROJECT.md"; rm -f "$P/PROJECT.md.bak"
printf '\nWaived stage 4: decided in the client workshop\n' >> "$P/PROJECT.md"
V="$(verdict "$P" 4)"
case "$V" in *WAIVED*) ok "unsigned clean plan + reasoned stage waiver: WAIVED" ;; *) bad "unsigned clean plan: $V" ;; esac
rm "$P/architecture/modules/Purchasing/module-brief.md"
V="$(verdict "$P" 4)"
case "$V" in *FAIL*'no module brief for: Purchasing'*) ok "a stage waiver does not excuse a deleted brief on an unsigned plan" ;; *) bad "stage waiver hid the brief: $V" ;; esac
# (3) a RELATIVE project path still measures the coverage ledger
s4proj t23c; mkdir -p "$P/analysis/src"; mv "$P/knowledge-base" "$P/analysis/src/knowledge-base"
printf '{"id":"F001","modules":["Purchasing"],"useCases":[{"id":"UC1","title":"Submit"}]}\n' > "$P/analysis/src/knowledge-base/brd/F001.brd.json"
printf '%s\n' '| pointer | type | title | slice | writeMode | acceptance | status |' '|---|---|---|---|---|---|---|' \
  '| /id | leaf | row 2 | 1 | exec | row 2 | not built |' > "$P/architecture/coverage-ledger.md"
GABS="$(cd "$(dirname "$GATE")" && pwd)/$(basename "$GATE")"
V="$(cd "$WORK" && "$GABS" --no-html t23c 4 2>&1 | grep '^Stage 4 ' | head -1)"
case "$V" in *FAIL*'coverage ledger has findings'*'UNCLAIMED'*) ok "relative project path: the ledger is measured (and its gap found)" ;; *) bad "relative path coverage: $V" ;; esac
case "$V" in *'ledger: ;'*|*': ;'*) bad "an empty not-measured reason was printed: $V" ;; *) ok "no empty reason" ;; esac
# (4) a reasonless waiver on a PASSING stage, and on a stage the entry mode already skips, is a WARN
s4proj t23d; printf '\nWaived stage 4:\n' >> "$P/PROJECT.md"
V="$(verdict "$P" 4)"
case "$V" in *PASS*'WARN'*'has no reason'*) ok "reasonless waiver on a passing stage: PASS with a WARN" ;; *) bad "reasonless waiver on a passing stage: $V" ;; esac
P="$(mkproj t23e)"; printf 'Entry mode: greenfield\n\nWaived stage 3:\n' >> "$P/PROJECT.md"
V="$(verdict "$P" 3)"
case "$V" in *WAIVED*'greenfield'*'WARN'*) ok "reasonless waiver on a mode-skipped stage: WAIVED by the mode, with a WARN" ;; *) bad "reasonless waiver on a mode-skipped stage: $V" ;; esac
# (5) dotted row ids and requirement ids in Depends on
s4proj t23f
sed -i.bak 's/| 2 | `BUILD` | 010-domain.mdl | domain | 1 |/| 2 | `BUILD` | 010-domain.mdl | domain | 1, US-12, F001 |/; s/| 3 | `BUILD` | 020-approval.mdl | domain | 2 |/| 3.1 | `BUILD` | 020-approval.mdl | domain | 2 |/; s/| 0 errors | 2–3 |/| 0 errors | 2–3.1, 01 |/' "$P/architecture/build-plan.md"; rm -f "$P/architecture/build-plan.md.bak"
V="$(verdict "$P" 4)"
case "$V" in *PASS*) ok "dotted row ids (3.1), zero-padded refs (01) and requirement ids (US-12, F001) read right" ;; *) bad "dependency parser false red: $V" ;; esac

printf '\n%s: %d ok, %d FAIL\n' "$(basename "$0")" "$PASS" "$FAIL"
rm -rf "$WORK"
[ "$FAIL" -eq 0 ]
