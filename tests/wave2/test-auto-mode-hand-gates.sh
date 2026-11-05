#!/usr/bin/env bash
# Fixture for #624: under `Interview mode: auto` a ✋ Stage 3/4 decision recorded ASSUMED with
# consentBy: auto-mode passes its gate; in every other mode it does not; every run lists the
# auto-mode ✋ decisions still unconfirmed; Stage 6 (release readiness) FAILs until a person
# confirms each one (Status CONFIRMED, consentBy a person).
#
#   tests/wave2/test-auto-mode-hand-gates.sh bin/gate-check.sh
#
# Positive control: on the pre-#624 script (origin/master 5160151) 16 of 25 checks fail — T1/T2
# (Stage 3/4 FAIL under auto), the FAIL-hint and pending-line checks of T3, all of T4/T5 (no
# release check). Keep the script under the toolkit's bin/ — TOOLKIT_DIR comes from it.
# The row and sign-off shapes are the ones a real unattended project wrote (#624 field run).
set -uo pipefail
GATE="${1:?usage: test-auto-mode-hand-gates.sh /path/to/gate-check.sh}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/auto624.XXXXXX")"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
export MXTK_NO_FETCH=1
unset CLAUDE_INTERVIEW_MODE

AUTO3='| 3 | Module boundaries: Orders, Approval | ASSUMED | consentBy: auto-mode, consentAt: 2026-11-05T10:00Z; rejected: one module |'
AUTO4='| 4 | Build plan approved | ASSUMED | consentBy: auto-mode, consentAt: 2026-11-05T10:05Z |'

# $1 name, $2 the Interview mode line ("" = none), $3/$4 the Stage 3/4 decision rows.
mkproj() {
  d="$WORK/$1"; mkdir -p "$d/architecture/modules/Orders" "$d/design/wireframes" "$d/knowledge-base/brd" "$d/ui-reviews"
  printf '{"id":"F001","modules":["Orders"],"useCases":[]}\n' > "$d/knowledge-base/brd/F001.brd.json"
  { echo "# PROJECT.md — fixture"; echo "Toolkit commit: none"; echo "Entry mode: requirements-driven"
    [ -n "$2" ] && echo "Interview mode: $2"
    printf '\n## Decisions\n\n| Stage | Decision | Status | Notes |\n|---|---|---|---|\n'
    echo "$3"; echo "$4"; } > "$d/PROJECT.md"
  printf '# fit-gap\nrow\n' > "$d/architecture/fit-gap.md"
  printf '# bp\nx\n' > "$d/architecture/blueprint.md"
  sleep 1
  printf '<html>\n' > "$d/architecture/blueprint.html"
  printf '<html>\n' > "$d/design/design-system.html"
  printf '<html>\n' > "$d/design/wireframes/orders.html"
  printf '# brief\n' > "$d/architecture/modules/Orders/module-brief.md"
  printf '%s\n' '# Plan' '' \
    '| # | Kind | Step | Produces / Proves | Depends on | Skills | State |' '|---|---|---|---|---|---|---|' \
    '| 1 | `BRIEF` | Check `architecture/modules/Orders/module-brief.md` exists | Brief | — | none | not built |' \
    '| 2 | `BUILD` | 010-domain.mdl | domain | 1 | none | not built |' \
    '| 3 | `PROVE` | mxcli check | 0 errors | 2 | none | not built |' \
    '| 4 | `HARNESS` | `bin/verify-module.sh Orders` | close | 3 | none | not built |' \
    '| 5 | `HARNESS` | process-coherence-pass.md on Orders | coherence | 4 | none | not built |' \
    '| 6 | `RUN` | `gate-check.sh <project> 5` | gate | 5 | none | not built |' > "$d/architecture/build-plan.md"
  printf '<html>report</html>\n' > "$d/test-report.html"
  printf '<html>review</html>\n' > "$d/ui-reviews/ui-review-2026-11-05.html"
  echo "$d"
}
run()  { "$GATE" --no-html "$1" 2>&1; }
line() { printf '%s\n' "$1" | grep "^Stage $2 " | head -1; }
NOTE='✋ decision(s) assumed by auto-mode — confirm before release'

echo "== T1: Interview mode: auto — auto-mode ASSUMED rows pass Stages 3 and 4 =="
P="$(mkproj t1 auto "$AUTO3" "$AUTO4")"; O="$(run "$P")"
case "$(line "$O" 3)" in *PASS*auto-mode*) ok "Stage 3 PASS, and the line says auto-mode" ;; *) bad "Stage 3 under auto: $(line "$O" 3)" ;; esac
case "$(line "$O" 4)" in *PASS*auto-mode*) ok "Stage 4 PASS, and the line says auto-mode" ;; *) bad "Stage 4 under auto: $(line "$O" 4)" ;; esac
case "$O" in *"2 $NOTE: PROJECT.md:"*"(Stage 3), PROJECT.md:"*"(Stage 4)"*) ok "the run lists both as unconfirmed, by id" ;; *) bad "no/incorrect pending line: $(printf '%s\n' "$O" | grep -i 'auto-mode —')" ;; esac

echo "== T2: the alias 'unattended' resolves to auto =="
P="$(mkproj t2 unattended "$AUTO3" "$AUTO4")"; O="$(run "$P")"
case "$(line "$O" 3)$(line "$O" 4)" in *PASS*PASS*) ok "Stages 3 and 4 PASS under 'unattended'" ;; *) bad "alias: $(line "$O" 3) / $(line "$O" 4)" ;; esac

echo "== T3: every other mode — the same rows still FAIL Stages 3 and 4 =="
for m in "" steering assist; do
  P="$(mkproj "t3${m:-none}" "$m" "$AUTO3" "$AUTO4")"; O="$(run "$P")"
  case "$(line "$O" 3)" in *FAIL*"no Stage-3 CONFIRMED"*"passes only under Interview mode: auto"*) ok "Stage 3 FAIL under '${m:-<unset>}', saying why" ;; *) bad "Stage 3 under '${m:-<unset>}': $(line "$O" 3)" ;; esac
  case "$(line "$O" 4)" in *FAIL*"no Stage-4 CONFIRMED"*) ok "Stage 4 FAIL under '${m:-<unset>}'" ;; *) bad "Stage 4 under '${m:-<unset>}': $(line "$O" 4)" ;; esac
  case "$O" in *"2 $NOTE"*) ok "the pending line still prints under '${m:-<unset>}'" ;; *) bad "pending line hidden under '${m:-<unset>}'" ;; esac
done
P="$(mkproj t3c auto "| 3 | Module boundaries | ASSUMED | consentBy: auto-mode |" "| 4 | Plan | ASSUMED | consentBy: Product owner, consentAt: 2026-11-05 |")"; O="$(run "$P")"
case "$(line "$O" 3)" in *FAIL*) ok "auto mode: an auto-mode ASSUMED with no consentAt does not pass" ;; *) bad "no-consentAt row passed: $(line "$O" 3)" ;; esac
case "$(line "$O" 4)" in *FAIL*) ok "auto mode: ASSUMED with a person's consent is still not CONFIRMED at a ✋ gate" ;; *) bad "human ASSUMED passed Stage 4: $(line "$O" 4)" ;; esac

echo "== T4: release readiness — Stage 6 FAILs while an auto-mode ✋ decision is unconfirmed =="
P="$(mkproj t4 auto "$AUTO3" "$AUTO4")"; O="$(run "$P")"
case "$(line "$O" 6)" in *FAIL*"2 hand-gate decision(s) assumed by auto-mode"*"(Stage 3)"*"underlying check: PASS"*) ok "Stage 6 FAIL names the ids and keeps the underlying verdict" ;; *) bad "Stage 6: $(line "$O" 6)" ;; esac
"$GATE" --no-html "$P" 6 >/dev/null 2>&1; rc=$?; [ "$rc" = 1 ] && ok "gate-check <project> 6 exits 1" || bad "Stage 6 query exit $rc with an unconfirmed release"
"$GATE" --no-html "$P" 4 >/dev/null 2>&1; rc=$?; [ "$rc" = 0 ] && ok "gate-check <project> 4 exits 0 under auto (the unattended run proceeds)" || bad "Stage 4 query exit $rc under auto"
printf '\nWaived stage 6: no test pass in this slice\n' >> "$P/PROJECT.md"; O="$(run "$P")"
case "$(line "$O" 6)" in *FAIL*"assumed by auto-mode"*) ok "a stage-6 waiver does not excuse an unconfirmed decision" ;; *) bad "waiver hid it: $(line "$O" 6)" ;; esac

echo "== T5: a row marked CONFIRMED but still stamped auto-mode is not a confirmation =="
P="$(mkproj t5 auto "| 3 | Module boundaries | CONFIRMED | consentBy: auto-mode, consentAt: 2026-11-05 |" "$AUTO4")"; O="$(run "$P")"
case "$(line "$O" 6)" in *FAIL*"2 hand-gate"*) ok "still counted until consentBy names a person" ;; *) bad "auto-mode CONFIRMED cleared it: $(line "$O" 6)" ;; esac
printf '%s\n' '' '## Sign-off' '' 'Confirmed by: auto-mode 2026-11-05' > "$P/triage.md"; O="$(run "$P")"
case "$O" in *"3 $NOTE"*"triage.md (Stage 0 sign-off)"*) ok "a triage.md signed by auto-mode is listed too" ;; *) bad "triage auto sign-off missed: $(printf '%s\n' "$O" | grep 'auto-mode —')" ;; esac
printf '%s\n' '' '## Sign-off' '' 'Confirmed by: ASSUMED under Interview mode: auto on 2026-10-27 (user asked for an unattended run).' > "$P/triage.md"; O="$(run "$P")"
case "$O" in *"3 $NOTE"*"triage.md (Stage 0 sign-off)"*) ok "the field shape 'ASSUMED under Interview mode: auto' is listed too" ;; *) bad "field-shape triage sign-off missed" ;; esac

echo "== T6: confirm clears it — CONFIRMED with consentBy a person =="
P="$(mkproj t6 auto "| 3 | Module boundaries: Orders, Approval | CONFIRMED | consentBy: Product owner, consentAt: 2026-11-06 |" "| 4 | Build plan approved | CONFIRMED | consentBy: Product owner, consentAt: 2026-11-06 |")"; O="$(run "$P")"
case "$(line "$O" 3)$(line "$O" 4)" in *PASS*PASS*) ok "Stages 3 and 4 PASS on the human confirmation" ;; *) bad "$(line "$O" 3) / $(line "$O" 4)" ;; esac
case "$(line "$O" 6)" in *PASS*) ok "Stage 6 PASS once confirmed" ;; *) bad "Stage 6 after confirm: $(line "$O" 6)" ;; esac
case "$O" in *"$NOTE"*) bad "pending line still printed after confirm" ;; *) ok "no pending line once confirmed" ;; esac
# Same after the mode is switched back: the confirmation, not the mode, is what clears it.
sed -i.bak 's/^Interview mode: auto$/Interview mode: steering/' "$P/PROJECT.md"; rm -f "$P/PROJECT.md.bak"; O="$(run "$P")"
case "$(line "$O" 3)$(line "$O" 4)$(line "$O" 6)" in *PASS*PASS*PASS*) ok "steering: confirmed rows pass 3, 4 and 6" ;; *) bad "steering after confirm: $(line "$O" 6)" ;; esac

rm -rf "$WORK"
echo ""; echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
