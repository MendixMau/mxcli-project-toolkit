#!/usr/bin/env bash
# Fixture for project-bin/lint-gate.sh's receipt check (#264) and exec.sh's reading of it.
#
# Usage: bash test-lint-receipt-revert.sh [path-to-lint-gate.sh]
#   INSTALLER=<install-lint-rules.sh> swaps the installer under test in T9-T11.
#
# Field case (two toolkit-built apps, mxcli v0.25.0, 2026-10-07 and 2026-10-11): `mxcli init`
# re-seeded .claude/lint-rules/ and the toolkit rules lost their `# mxtk-lint-rule:` header.
# CONV010 went 26 -> 169 and the next exec (a pages-only script) was logged as the rise; in the
# other app the stock rules sat for five days and the baseline absorbed their counts. The
# installer's receipt (.claude/.mxtk-lint-receipt) already records each rule's md5 as installed;
# lint-gate never read it.
#
# Golden input: the receipt and rules are produced by running the REAL installer
# (bin/lib/install-lint-rules.sh, the function init-project.sh and sync-project.sh call) into a
# scratch project — never a hand-written receipt. The re-seed is simulated the way the field
# showed it: header block gone (entity_business_key's stock body IS the toolkit body minus the
# header — the installer's "headered" branch), and a rule file removed (init drops rules it does
# not know). Lint output is read through LINT_JSON; no mxcli or .mpr is needed. exec.sh's
# run_lint_gate() is extracted from the real file and executed.
set -uo pipefail
TK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="${1:-$TK/project-bin/lint-gate.sh}"
EXEC="$TK/project-bin/exec.sh"
. "$TK/bin/lib/portable.sh"
require_py
WORK="$(mktemp -d "${TMPDIR:-/tmp}/lint-receipt.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; }

P="$WORK/proj"; mkdir -p "$P/bin" "$P/.claude"
cp "$GATE" "$P/bin/lint-gate.sh"; [ -f "$TK/project-bin/_common.sh" ] && cp "$TK/project-bin/_common.sh" "$P/bin/"
printf 'mpr' > "$P/App.mpr"; printf '#!/bin/sh\nexit 0\n' > "$P/mxcli"; chmod +x "$P/mxcli" "$P/bin/lint-gate.sh"
install_rules() { ( . "$TK/bin/lib/install-lint-rules.sh"; mxtk_install_lint_rules "$TK" "$P" 0 "" ) 2>&1; }

v() { i=0; while [ "$i" -lt "$3" ]; do
  printf '{"ruleId":"%s","severity":"%s","message":"finding %s","module":"Orders","document":"Doc%s","documentType":"microflow","documentId":"id-%s-%s","suggestion":"s"},' \
    "$1" "$2" "$i" "$i" "$1" "$i"; i=$((i+1)); done; }
mk() { printf '{"violations":[%s{"ruleId":"MPR001","severity":"warning","message":"m","module":"Orders","document":"E","documentType":"entity","documentId":"x","suggestion":"s"}],"summary":{}}' "$1" > "$WORK/lint.json"; }
gate() { (cd "$P" && LINT_JSON="$WORK/lint.json" bash bin/lint-gate.sh "$@"); }
fn="$WORK/run_lint_gate.sh"; sed -n '/^run_lint_gate() {/,/^}/p' "$EXEC" > "$fn"
exec_detail() { (cd "$P" && PROJECT_ROOT="$P" LINT_JSON="$WORK/lint.json" bash -c ". '$fn'; LINT_RC=0; run_lint_gate >/dev/null; echo \"\$LINT_RC|\$LINT_DETAIL\""); }
strip_header() { sed '1,/^# --- end mxtk-lint-rule header ---$/d' "$1" > "$1.tmp" && mv "$1.tmp" "$1"; }

echo "T0 golden input: the real installer writes the rules and the receipt"
out=$(install_rules)
R="$P/.claude/.mxtk-lint-receipt"
[ -f "$R" ] && ok "receipt written by install-lint-rules.sh" || bad "installer wrote no receipt" "$out"
n=$(grep -cv '^#' "$R" 2>/dev/null || echo 0)
[ "$n" -ge 3 ] && ok "receipt lists $n rules" || bad "receipt lists $n rules"
grep -q '^conv010_act_microflow_content.star  [0-9a-f]\{32\}  stock$' "$R" && ok "conv010 row: name + md5 + kind stock" || bad "conv010 row missing" "$(cat "$R")"
grep -q '^ux001_confirm_before_destructive.star  [0-9a-f]\{32\}  toolkit$' "$R" && ok "ux001 row: kind toolkit" || bad "ux001 row kind wrong" "$(cat "$R")"
grep -q '^mxtk_ux003_action_user_feedback.star  [0-9a-f]\{32\}  configurable$' "$R" && ok "mxtk_ux003 row: kind configurable" || bad "mxtk_ux003 row kind wrong" "$(cat "$R")"

echo "T1 rules as installed: no receipt complaint, normal ratchet"
mk "$(v CONV010 warning 26)"
out=$(gate --update-baseline 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "baseline written over installed rules" || bad "rc=$rc" "$out"
out=$(gate 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "unchanged run passes (rc 0)" || bad "rc=$rc" "$out"
case "$out" in *REVERTED*) bad "false receipt alarm on untouched rules" "$out" ;; *) ok "no receipt alarm" ;; esac

echo "T2 re-seed: header gone on two rules, one rule removed -> BLIND, not a rise"
strip_header "$P/.claude/lint-rules/conv010_act_microflow_content.star"
strip_header "$P/.claude/lint-rules/data_change_microflows.star"
rm -f "$P/.claude/lint-rules/entity_business_key.star"
mk "$(v CONV010 warning 169)"
out=$(gate 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "exit 1 (the blind code)" || bad "rc=$rc" "$out"
case "$out" in *"BLIND — lint rules reverted to stock"*) ok "says BLIND, reverted to stock" ;; *) bad "no BLIND verdict" "$out" ;; esac
case "$out" in *"FAIL —"*|*"got worse"*) bad "reported as a rise" "$out" ;; *) ok "CONV010 26 -> 169 not reported as a rise" ;; esac
for f in conv010_act_microflow_content.star data_change_microflows.star entity_business_key.star; do
  case "$out" in *"$f"*) ok "names $f" ;; *) bad "does not name $f" "$out" ;; esac
done
case "$out" in *ux001_confirm_before_destructive.star*) bad "names an untouched rule" "$out" ;; *) ok "untouched rules not named" ;; esac
case "$out" in *"bin/sync-project.sh $P"*) ok "points at the remedy (sync-project.sh <root>)" ;; *) bad "no remedy command" "$out" ;; esac
"$PY" -c 'import json,sys;d=json.load(open(sys.argv[1]));sys.exit(0 if d["verdict"]=="BLIND-RULES-REVERTED" and "total" not in d else 1)' \
  "$P/.claude/loop/lint-last.json" 2>/dev/null && ok "lint-last.json: BLIND-RULES-REVERTED, no stale total" \
  || bad "lint-last.json wrong" "$(cat "$P/.claude/loop/lint-last.json" 2>/dev/null)"

echo "T3 exec.sh logs it as LINT BLIND (rc 3), naming the files"
d=$(exec_detail)
case "$d" in "3|lint BLIND: rules reverted to stock (conv010_act_microflow_content.star,data_change_microflows.star,entity_business_key.star)"*) ok "exec detail: ${d#*|}" ;;
  *) bad "exec did not log a reverted-rules BLIND" "$d" ;; esac

echo "T4 --update-baseline over reverted rules is refused, baseline untouched"
before=$(cat "$P/.claude/lint-baseline.json")
out=$(gate --update-baseline --reason "x" 2>&1); rc=$?
[ "$rc" -eq 2 ] && ok "refused (rc 2)" || bad "stock counts baselined (rc $rc)" "$out"
[ "$(cat "$P/.claude/lint-baseline.json")" = "$before" ] && ok "baseline unchanged" || bad "baseline rewritten"

echo "T5 LINT_RULES_REVERTED_OK=1 lints anyway, with the warning"
out=$(cd "$P" && LINT_RULES_REVERTED_OK=1 LINT_JSON="$WORK/lint.json" bash bin/lint-gate.sh 2>&1); rc=$?
case "$out" in *"REVERTED TO STOCK"*"FAIL —"*) ok "warned, then compared (rise visible)" ;; *) bad "override did not lint" "$out" ;; esac
before=$(cat "$P/.claude/lint-baseline.json")
out=$(cd "$P" && LINT_RULES_REVERTED_OK=1 LINT_JSON="$WORK/lint.json" bash bin/lint-gate.sh --update-baseline --reason "x" 2>&1); rc=$?
[ "$rc" -eq 2 ] && [ "$(cat "$P/.claude/lint-baseline.json")" = "$before" ] && ok "override does not get past the --update-baseline refusal" \
  || bad "stock counts baselined under the override (rc $rc)" "$out"

echo "T6 the remedy is not blocked and clears it (the installer sync-project.sh runs)"
out=$(install_rules)
case "$out" in *conv010_act_microflow_content.star*) ok "installer restored conv010" ;; *) bad "installer did not touch conv010" "$out" ;; esac
mk "$(v CONV010 warning 26)"
out=$(gate 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "after the remedy: rc 0, no alarm" || bad "still blocked after the remedy (rc $rc)" "$out"

echo "T7 a hand edit that keeps the header is not called a revert"
printf '\n# local tweak\n' >> "$P/.claude/lint-rules/data_change_microflows.star"
out=$(gate 2>&1); rc=$?
case "$out" in *REVERTED*) bad "hand edit flagged as a revert" "$out" ;; *) ok "headered edit left to the installer's report" ;; esac

echo "T8 no receipt (pre-receipt install): no check"
rm -f "$R"; strip_header "$P/.claude/lint-rules/conv010_act_microflow_content.star"
out=$(gate 2>&1); rc=$?
case "$out" in *REVERTED*) bad "alarm with no receipt to compare" "$out" ;; *) ok "no receipt -> no alarm (rc $rc)" ;; esac

# ---- review follow-ups: an mxcli newer than STOCK-HASHES, deliberate opt-out, manifest drops ----
# A scratch toolkit copy: lint-rules/ + bin/lib/. INSTALLER=<file> swaps in another
# install-lint-rules.sh (used to prove these cases fail on master's installer).
TK2="$WORK/tk2"; mkdir -p "$TK2/bin"
cp -R "$TK/lint-rules" "$TK2/lint-rules"; cp -R "$TK/bin/lib" "$TK2/bin/lib"
[ -n "${INSTALLER:-}" ] && cp "$INSTALLER" "$TK2/bin/lib/install-lint-rules.sh"
newproj() { _p="$WORK/$1"; mkdir -p "$_p/bin" "$_p/.claude"; cp "$P/bin/lint-gate.sh" "$_p/bin/"
  [ -f "$P/bin/_common.sh" ] && cp "$P/bin/_common.sh" "$_p/bin/"
  cp "$P/.claude/lint-baseline.json" "$_p/.claude/"; printf 'mpr' > "$_p/App.mpr"; cp "$P/mxcli" "$_p/mxcli"; echo "$_p"; }
inst2() { ( [ -n "${2:-}" ] && MXTK_LINT_RULES="$2"; . "$TK2/bin/lib/install-lint-rules.sh"; mxtk_install_lint_rules "$TK2" "$1" 0 "" ) 2>&1; }
gate2() { (cd "$1" && LINT_JSON="$WORK/lint.json" bash bin/lint-gate.sh); }
mk "$(v CONV010 warning 26)"

echo "T9 a genuine stock body whose hash STOCK-HASHES does not list (mxcli upgrade, then init)"
EBK=entity_business_key.star
STOCK="$WORK/ebk-stock.star"; sed '1,/^# --- end mxtk-lint-rule header ---$/d' "$TK/lint-rules/$EBK" > "$STOCK"
# Genuine: this body's md5 is the v0.24.0/v0.25.0 stock hash recorded in the REAL STOCK-HASHES.txt.
sm=$(portable_md5 "$STOCK")
grep -q "^$EBK  *$sm " "$TK/lint-rules/STOCK-HASHES.txt" && ok "stock body is genuine (md5 $sm is in STOCK-HASHES.txt)" \
  || bad "stock body md5 $sm not a recorded stock hash"
# Unknown version: the scratch toolkit forgets that hash, and its rule has moved off stock (as
# conv010 and data_change have), so neither the stock nor the "headered" branch can match.
grep -v "^$EBK " "$TK/lint-rules/STOCK-HASHES.txt" > "$TK2/lint-rules/STOCK-HASHES.txt"
printf '# toolkit fix, not in stock\n' >> "$TK2/lint-rules/$EBK"
P9=$(newproj p9); inst2 "$P9" >/dev/null
cp "$STOCK" "$P9/.claude/lint-rules/$EBK"
out=$(gate2 "$P9" 2>&1); rc=$?
[ "$rc" -eq 1 ] && case "$out" in *"BLIND — lint rules reverted"*"$EBK"*|*"$EBK"*"BLIND — lint rules reverted"*) true ;; *) false ;; esac \
  && ok "lint-gate: BLIND, names $EBK" || bad "lint-gate did not flag the unknown-hash re-seed (rc $rc)" "$out"
case "$out" in *"--upgrade-lint-rules all"*) ok "message carries the LOCALLY MODIFIED fallback" ;; *) bad "no --upgrade-lint-rules fallback" "$out" ;; esac
out=$(inst2 "$P9")
case "$out" in *"$EBK — header missing — restored from toolkit, your copy kept as $EBK.reseeded-"*) ok "installer restores it, labelled 'header missing', copy named" ;; *) bad "installer did not restore it" "$out" ;; esac
case "$out" in *"REVERTED TO STOCK"*) bad "a body matching no known stock hash called REVERTED TO STOCK" "$out" ;; *) ok "not labelled REVERTED TO STOCK (body matches no known stock hash)" ;; esac
cmp -s "$TK2/lint-rules/$EBK" "$P9/.claude/lint-rules/$EBK" && ok "file is the toolkit version again" || bad "file not restored"
ls "$P9/.claude/lint-rules/$EBK".reseeded-* >/dev/null 2>&1 && ok "found copy kept beside it" || bad "found copy not kept"
out=$(gate2 "$P9" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "after sync: rc 0 (remedy clears it)" || bad "still blind after sync (rc $rc)" "$out"
# Backups are capped: with 5 older copies already there, one more re-seed leaves the newest 3.
for i in 1 2 3 4 5; do printf 'old %s\n' "$i" > "$P9/.claude/lint-rules/$EBK.reseeded-2020010100000$i"; done
cp "$STOCK" "$P9/.claude/lint-rules/$EBK"; inst2 "$P9" >/dev/null
n=$(ls "$P9/.claude/lint-rules/$EBK".reseeded-* 2>/dev/null | wc -l | tr -d ' ')
[ "$n" -eq 3 ] && ok "backups capped at 3" || bad "backups not capped ($n)"
kept_old=""; for i in 1 2 3; do [ -f "$P9/.claude/lint-rules/$EBK.reseeded-2020010100000$i" ] && kept_old="$kept_old $i"; done
[ -z "$kept_old" ] && ok "the oldest backups are the ones removed" || bad "oldest backups kept:$kept_old"

echo "T10 opt-out: a non-stock rule removed by the user's decision, with a reason"
P10=$(newproj p10); inst2 "$P10" >/dev/null
T2F=txt002_non_iso_date_in_user_text.star
printf '%s\n' "$T2F" > "$P10/.claude/lint-rules-disabled.txt"     # no reason
rm -f "$P10/.claude/lint-rules/$T2F"
out=$(gate2 "$P10" 2>&1); rc=$?
case "$out" in *"$T2F has no '# reason: ...' — ignored"*"BLIND — lint rules reverted"*) ok "no reason: line ignored with a warning, removal still BLIND" ;; *) bad "reasonless opt-out honoured (rc $rc)" "$out" ;; esac
out=$(inst2 "$P10")
case "$out" in *"$T2F has no '# reason: …' — IGNORED"*) ok "installer warns about the reasonless line" ;; *) bad "no installer warning" "$out" ;; esac
[ -f "$P10/.claude/lint-rules/$T2F" ] && ok "reasonless opt-out: sync restores the rule" || bad "reasonless opt-out honoured by sync"
# `#reason:` with no blank: both tools must accept the same syntax.
printf '# decided with the user 2026-10-13\n%s  #reason: display standard is dd/MM/yyyy (PROJECT.md decision D-14)\n' "$T2F" > "$P10/.claude/lint-rules-disabled.txt"
rm -f "$P10/.claude/lint-rules/$T2F"
out=$(gate2 "$P10" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "with a reason: lint-gate rc 0, no alarm before any sync" || bad "reasoned opt-out read as a re-seed (rc $rc)" "$out"
out=$(inst2 "$P10")
[ ! -f "$P10/.claude/lint-rules/$T2F" ] && ok "sync does not restore it" || bad "sync restored a disabled rule" "$out"
if grep -q "^$T2F " "$P10/.claude/.mxtk-lint-receipt"; then bad "disabled rule's receipt row kept"; else ok "disabled rule's receipt row pruned"; fi
rm -f "$P10/.claude/lint-rules/txt001_build_words_in_user_text.star"
out=$(gate2 "$P10" 2>&1); rc=$?
case "$out" in *txt001_build_words_in_user_text.star*) ok "an unlisted removal is still caught" ;; *) bad "unlisted removal missed" "$out" ;; esac
inst2 "$P10" >/dev/null

echo "T12 opt-out is refused for a stock-seeded rule"
C10=conv010_act_microflow_content.star
printf '%s  # reason: we do not use ACT_ prefixes\n' "$C10" >> "$P10/.claude/lint-rules-disabled.txt"
rm -f "$P10/.claude/lint-rules/$C10"
out=$(gate2 "$P10" 2>&1); rc=$?
case "$out" in *"$C10 is stock-seeded and cannot be disabled — ignored"*"$C10: gone"*"BLIND — lint rules reverted"*) ok "lint-gate: refused, still BLIND" ;; *) bad "stock opt-out honoured by lint-gate (rc $rc)" "$out" ;; esac
out=$(inst2 "$P10")
case "$out" in *"$C10 cannot be disabled — IGNORED"*) ok "installer refuses it with a warning" ;; *) bad "no refusal from the installer" "$out" ;; esac
[ -f "$P10/.claude/lint-rules/$C10" ] && ok "sync restores the stock-seeded rule" || bad "stock-seeded rule left missing"

echo "T13 a headerless toolkit-only rule (ux001) is a local edit: never overwritten, not BLIND"
P13=$(newproj p13); inst2 "$P13" >/dev/null
U1="$P13/.claude/lint-rules/ux001_confirm_before_destructive.star"
strip_header "$U1"; printf '# local tweak\n' >> "$U1"; um=$(portable_md5 "$U1")
out=$(gate2 "$P13" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "lint-gate: rc 0, no BLIND for a toolkit-only rule" || bad "headerless ux001 called a re-seed (rc $rc)" "$out"
out=$(inst2 "$P13")
case "$out" in *"ux001_confirm_before_destructive.star is LOCALLY MODIFIED"*) ok "installer reports LOCALLY MODIFIED" ;; *) bad "not reported as a local edit" "$out" ;; esac
[ "$(portable_md5 "$U1")" = "$um" ] && ok "ux001 not overwritten" || bad "ux001 overwritten"

echo "T14 a configured, headerless mxtk_ux003 is not overwritten and not BLIND"
C2="$P13/.claude/lint-rules/mxtk_ux003_action_user_feedback.star"
strip_header "$C2"; printf 'PROJECT_MODULES = "Orders"\n' >> "$C2"; cm=$(portable_md5 "$C2")
out=$(gate2 "$P13" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "lint-gate: rc 0 for a configured mxtk_ux003" || bad "configured mxtk_ux003 called a re-seed (rc $rc)" "$out"
out=$(inst2 "$P13")
[ "$(portable_md5 "$C2")" = "$cm" ] && ok "mxtk_ux003 not overwritten" || bad "mxtk_ux003 overwritten" "$out"

echo "T11 a rule the toolkit stops shipping: its receipt row is pruned, no permanent 'gone'"
P11=$(newproj p11); inst2 "$P11" >/dev/null
rm -f "$P11/.claude/lint-rules/ui001_widget_layout_traps.star"   # project tidies the retired rule away
FEWER=$(printf '%s\n' $(. "$TK2/bin/lib/install-manifest.sh" >/dev/null 2>&1; echo "$MXTK_LINT_RULES") | grep -v '^ui001_widget_layout_traps.star$' | paste -sd' ' -)
out=$(inst2 "$P11" "$FEWER")
if grep -q '^ui001_widget_layout_traps.star ' "$P11/.claude/.mxtk-lint-receipt"; then bad "row for a dropped rule kept" "$out"; else ok "row for the dropped rule pruned"; fi
case "$out" in *"dropped row"*ui001*) ok "installer says so" ;; *) bad "prune not reported" "$out" ;; esac
[ ! -f "$P11/.claude/lint-rules/ui001_widget_layout_traps.star" ] && ok "dropped rule not reinstalled" || bad "dropped rule reinstalled"
out=$(gate2 "$P11" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "lint-gate: rc 0 after the prune" || bad "permanent 'gone' (rc $rc)" "$out"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
