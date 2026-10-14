#!/usr/bin/env bash
# Fixture for project-bin/lint-gate.sh (baseline acceptance) and exec.sh's lint step.
#
# Usage: bash test-lint-gate-accept.sh [path-to-lint-gate.sh]
#
# 2026-10-12, three toolkit-built apps reviewed after a four-day build:
#   - exec.sh's rule-id pattern ([A-Z]+[0-9]+) never matched mxcli's hyphenated built-in ids,
#     so MDL-FLOW01 appeared in 0 of 475 "LINT ROSE" BUILD-LOG rows across the three apps.
#   - lint-gate exits 1 for PASS-BLIND as well as for a rise; exec.sh logged a blind CONV020
#     as "lint ROSE: see output" (20 rows), so red stopped meaning anything (#229).
#   - --update-baseline took no reason: 61 self-accepted re-baselines, security warnings
#     included, and nothing summed them.
#   - (#348, 2026-10-14) the agent could type --approved-in-chat itself: a rise now waits for
#     bin/baseline-approve.sh, run by the person (simulated under a pseudo-terminal here).
# This proves each fix discriminates. No mxcli or .mpr is needed: lint-gate's LINT_JSON mode
# reads a captured result. The violation objects copy the key set of a real
# `mxcli lint --format json` capture (mxcli v0.25.0: ruleId, severity, message, module,
# document, documentType, documentId, suggestion; top level violations + summary), with
# generic names. exec.sh's run_lint_gate() is extracted from the real file and executed,
# not re-implemented here.
set -uo pipefail
TK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="${1:-$TK/project-bin/lint-gate.sh}"
EXEC="$TK/project-bin/exec.sh"
. "$TK/bin/lib/portable.sh"
require_py
WORK="$(mktemp -d "${TMPDIR:-/tmp}/lint-gate-accept.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; }

P="$WORK/proj"; mkdir -p "$P/bin" "$P/.claude"
cp "$GATE" "$P/bin/lint-gate.sh"; [ -f "$TK/project-bin/_common.sh" ] && cp "$TK/project-bin/_common.sh" "$P/bin/"
# The lock pair is installed beside lint-gate.sh (#348); human_approve is the person's step.
for f in baseline-lock.sh baseline-approve.sh; do [ -f "$(dirname "$GATE")/$f" ] && cp "$(dirname "$GATE")/$f" "$P/bin/"; done
. "$TK/tests/wave2/fixtures/baseline-lock/human.sh"
printf 'mpr' > "$P/App.mpr"; printf '#!/bin/sh\nexit 0\n' > "$P/mxcli"; chmod +x "$P/mxcli" "$P/bin/lint-gate.sh"

# v <ruleId> <severity> <n> [module] -> n violation objects
v() { i=0; while [ "$i" -lt "$3" ]; do
  printf '{"ruleId":"%s","severity":"%s","message":"finding %s","module":"%s","document":"Doc%s","documentType":"microflow","documentId":"id-%s-%s","suggestion":"s"},' \
    "$1" "$2" "$i" "${4:-Orders}" "$i" "$1" "$i"; i=$((i+1)); done; }
mk() { printf '{"violations":[%s{"ruleId":"MPR001","severity":"warning","message":"m","module":"Orders","document":"E","documentType":"entity","documentId":"x","suggestion":"s"}],"summary":{}}' "$1" > "$WORK/lint.json"; }
gate() { (cd "$P" && LINT_JSON="$WORK/lint.json" bash bin/lint-gate.sh "$@"); }
base_total() { "$PY" -c 'import json,sys;print(sum(json.load(open(sys.argv[1]))["counts"].values()))' "$P/.claude/lint-baseline.json"; }

echo "T1 first baseline needs no reason and logs nothing"
mk "$(v CONV009 info 2)$(v MDL-FLOW01 info 1)$(v SEC003 warning 1)"
out=$(gate --update-baseline 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "first baseline written (rc 0)" || bad "first baseline rc=$rc" "$out"
[ ! -f "$P/.claude/lint-acceptances.tsv" ] && ok "no acceptance row for a first baseline" || bad "acceptance log written on first baseline"

echo "T2 a rise in a hyphenated rule is named in exec.sh's row detail"
mk "$(v CONV009 info 3)$(v MDL-FLOW01 info 3)$(v SEC003 warning 1)"
fn="$WORK/run_lint_gate.sh"
sed -n '/^run_lint_gate() {/,/^}/p' "$EXEC" > "$fn"
[ -s "$fn" ] && ok "run_lint_gate() extracted from exec.sh" || bad "could not extract run_lint_gate from $EXEC"
detail=$(cd "$P" && PROJECT_ROOT="$P" LINT_JSON="$WORK/lint.json" bash -c ". '$fn'; LINT_RC=0; run_lint_gate >/dev/null; echo \"\$LINT_RC|\$LINT_DETAIL\"")
case "$detail" in 1\|*MDL-FLOW01*) ok "MDL-FLOW01 named: ${detail#*|}" ;; *) bad "hyphenated id missing from detail" "$detail" ;; esac
case "$detail" in *CONV009*) ok "CONV009 still named" ;; *) bad "CONV009 missing" "$detail" ;; esac

echo "T3 accepting a rise without --reason is refused and the baseline is untouched"
before=$(base_total)
out=$(gate --update-baseline 2>&1); rc=$?
[ "$rc" -eq 2 ] && ok "refused (rc 2)" || bad "rise accepted without a reason (rc $rc)" "$out"
[ "$(base_total)" = "$before" ] && ok "baseline unchanged ($before)" || bad "baseline changed to $(base_total)"

echo "T4 with --reason the rise still waits for the person; after their approval it is accepted and logged"
out=$(gate --update-baseline --reason "two flows split later in slice 3" 2>&1); rc=$?
[ "$rc" -eq 2 ] && [ "$(base_total)" = "$before" ] && ok "a reason alone is not approval (rc 2, baseline unchanged)" || bad "rise accepted on the agent's word (rc $rc)" "$out"
case "$out" in *"bin/baseline-approve.sh lint"*) ok "refusal names the person's command" ;; *) bad "refusal does not name bin/baseline-approve.sh" "$out" ;; esac
human_approve "$P" lint; hrc=$?
[ "$hrc" -eq 3 ] && echo "  skip (no usable \`script\` for a pseudo-terminal) — T4-T7 need it" && exit 0
out=$(gate --update-baseline --reason "two flows split later in slice 3" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "accepted after the person approved" || bad "rc=$rc" "$out"
row=$(tail -1 "$P/.claude/lint-acceptances.tsv" 2>/dev/null)
case "$row" in *CONV009+1*MDL-FLOW01+2*"two flows split later"*) ok "row: rises and reason recorded" ;; *) bad "acceptance row wrong" "$row" ;; esac

echo "T5 --approved-in-chat is no longer evidence; a security-tier rise needs the person's approval"
mk "$(v CONV009 info 3)$(v MDL-FLOW01 info 3)$(v SEC003 warning 2)$(v CONV006 warning 1)"
out=$(gate --update-baseline --approved-in-chat --reason "user approved demo-user warning in chat" 2>&1); rc=$?
[ "$rc" -eq 2 ] && ok "SEC003/CONV006 rise refused on the flag alone (#348)" || bad "the agent's own flag moved the baseline (rc $rc)" "$out"
case "$out" in *SEC003*CONV006*|*CONV006*SEC003*) ok "refusal names both security rules" ;; *) bad "refusal does not name the rules" "$out" ;; esac
grep -q "SECURITY-TIER" "$P/.claude/baseline-pending/lint.summary" 2>/dev/null && ok "the proposal the person reviews flags the security tier" || bad "proposal summary does not flag security"
human_approve "$P" lint
out=$(gate --update-baseline --approved-in-chat --reason "user approved demo-user warning in chat" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "accepted after the person approved" || bad "rc=$rc" "$out"
tail -1 "$P/.claude/lint-acceptances.tsv" | grep -q $'\tyes\t' && ok "row marks the security approval" || bad "security flag missing" "$(tail -1 "$P/.claude/lint-acceptances.tsv")"

echo "T6 a pure ratchet-down needs no reason"
mk "$(v CONV009 info 1)$(v MDL-FLOW01 info 3)$(v SEC003 warning 2)$(v CONV006 warning 1)"
rows=$(wc -l < "$P/.claude/lint-acceptances.tsv")
out=$(gate --update-baseline 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "ratchet-down accepted without a reason" || bad "rc=$rc" "$out"
[ "$(wc -l < "$P/.claude/lint-acceptances.tsv")" -eq "$rows" ] && ok "no acceptance row for a drop" || bad "drop was logged as an acceptance"

echo "T7 the project's security list replaces the default"
printf '# ours\nCONV007\n' > "$P/.claude/lint-security-rules.txt"
mk "$(v CONV009 info 1)$(v MDL-FLOW01 info 3)$(v SEC003 warning 2)$(v CONV006 warning 1)$(v CONV007 info 1)"
gate --update-baseline --reason "x" >/dev/null 2>&1
grep -q "SECURITY-TIER: CONV007" "$P/.claude/baseline-pending/lint.summary" 2>/dev/null && ok "CONV007 flagged as security once listed" || bad "listed rule not treated as security" "$(cat "$P/.claude/baseline-pending/lint.summary" 2>/dev/null)"
rm -f "$P/.claude/lint-security-rules.txt"

echo "T8 PASS-BLIND is logged as BLIND, not as a rise"
mk "$(v CONV009 info 1)$(v MDL-FLOW01 info 3)$(v SEC003 warning 2)$(v CONV006 warning 1)"
"$PY" - "$WORK/lint.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
d["violations"].append({"ruleId":"CONV020","severity":"warning","module":"_rule","document":"","documentType":"",
  "documentId":"","message":"CONV020 is unconfigured: PROJECT_MODULES is empty, so this rule inspected NOTHING.","suggestion":"s"})
json.dump(d,open(sys.argv[1],"w"))
PY
out=$(gate 2>&1); grc=$?
[ "$grc" -eq 1 ] && ok "lint-gate still exits 1 for PASS-BLIND" || bad "gate rc=$grc" "$out"
detail=$(cd "$P" && PROJECT_ROOT="$P" LINT_JSON="$WORK/lint.json" bash -c ". '$fn'; LINT_RC=0; run_lint_gate >/dev/null; echo \"\$LINT_RC|\$LINT_DETAIL\"")
case "$detail" in "3|lint BLIND: CONV020"*) ok "exec detail: ${detail#*|}" ;; *) bad "blind run not told apart from a rise" "$detail" ;; esac

echo "T9 the metrics ledger does not class a blind run as a clean apply"
ML="$TK/project-bin/metrics-ledger.sh"
if [ -f "$ML" ]; then
  cp "$ML" "$P/bin/"; mkdir -p "$P/.claude/loop"
  printf '{"verdict":"PASS-BLIND","total":7,"counts":{}}\n' > "$P/.claude/loop/lint-last.json"
  (cd "$P" && bash bin/metrics-ledger.sh exec --script 090-x.mdl --gate pass --result "⚠️ applied, LINT BLIND" \
     --elapsed 5 --mxbuild-errors 0 --lint-rc 3 --restored 0 --scored 0) >/dev/null 2>&1
  r=$(tail -1 "$P/.claude/loop/metrics-ledger.tsv" 2>/dev/null)
  [ "$(printf '%s' "$r" | cut -f4)" = applied-lint-blind ] && ok "result class applied-lint-blind" || bad "blind row classed '$(printf '%s' "$r" | cut -f4)'"
  [ "$(printf '%s' "$r" | cut -f8)" = 7 ] && ok "lint_total kept for a blind run (lint did run)" || bad "lint_total '$(printf '%s' "$r" | cut -f8)'"
else
  echo "  skip (no project-bin/metrics-ledger.sh in this tree)"
fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
