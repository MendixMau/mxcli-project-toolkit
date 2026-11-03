#!/usr/bin/env bash
# Fixture for exec.sh's self-heal of a stock re-seed of the toolkit lint rules (#461).
#
# Field case (Windows, mxcli v0.27.0, toolkit release/v1.0): mxcli's own SessionStart hook runs
# `mxcli init --sync-skills`, which rewrote four bundled lint rules from the binary after a
# context compaction. The next exec.sh applied the script, mxbuild was clean, and the run still
# ended as "LINT RULES REVERTED TO STOCK ... BLIND" until someone reran sync-project.sh.
#
# The hook is simulated the way it acts: a toolkit rule file is overwritten with the stock body.
# entity_business_key's stock body IS the toolkit body minus the header, a hash recorded in the
# real STOCK-HASHES.txt. Rules and receipt come from the REAL installer; run_lint_gate() is
# extracted from the real exec.sh and run with find_toolkit_root from the real _common.sh.
# Lint output is read through LINT_JSON; no mxcli or .mpr is needed.
set -uo pipefail
TK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXEC="$TK/project-bin/exec.sh"
. "$TK/bin/lib/portable.sh"
require_py
WORK="$(mktemp -d "${TMPDIR:-/tmp}/lint-autorestore.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; }

P="$WORK/proj"; mkdir -p "$P/bin" "$P/.claude"
cp "$TK/project-bin/lint-gate.sh" "$P/bin/"; cp "$TK/project-bin/_common.sh" "$P/bin/"
printf 'mpr' > "$P/App.mpr"; printf '#!/bin/sh\nexit 0\n' > "$P/mxcli"; chmod +x "$P/mxcli" "$P/bin/lint-gate.sh"
( . "$TK/bin/lib/install-lint-rules.sh"; mxtk_install_lint_rules "$TK" "$P" 0 "" ) >/dev/null 2>&1
printf '| Toolkit root | `%s` |\n' "$TK" > "$P/CLAUDE.local.md"

v() { i=0; while [ "$i" -lt "$2" ]; do
  printf '{"ruleId":"%s","severity":"warning","message":"f%s","module":"Orders","document":"Doc%s","documentType":"microflow","documentId":"id-%s-%s","suggestion":"s"},' "$1" "$i" "$i" "$1" "$i"; i=$((i+1)); done; }
printf '{"violations":[%s{"ruleId":"MPR001","severity":"warning","message":"m","module":"Orders","document":"E","documentType":"entity","documentId":"x","suggestion":"s"}],"summary":{}}' "$(v CONV010 26)" > "$WORK/lint.json"
(cd "$P" && LINT_JSON="$WORK/lint.json" bash bin/lint-gate.sh --update-baseline >/dev/null 2>&1)

fn="$WORK/run_lint_gate.sh"; sed -n '/^run_lint_gate() {/,/^}/p' "$EXEC" > "$fn"
# runs the real function; echoes its screen output, then RC|DETAIL
run_exec() { (cd "$P" && PROJECT_ROOT="$P" LINT_JSON="$WORK/lint.json" "$@" bash -c \
  ". '$P/bin/_common.sh'; . '$fn'; LINT_RC=0; run_lint_gate; echo \"RESULT \$LINT_RC|\$LINT_DETAIL\"") 2>&1; }
EBK="$P/.claude/lint-rules/entity_business_key.star"
C10="$P/.claude/lint-rules/conv010_act_microflow_content.star"
reseed() { sed '1,/^# --- end mxtk-lint-rule header ---$/d' "$TK/lint-rules/entity_business_key.star" > "$EBK"
           sed '1,/^# --- end mxtk-lint-rule header ---$/d' "$TK/lint-rules/conv010_act_microflow_content.star" > "$C10"; }
toolkit_md5() { portable_md5 "$TK/lint-rules/$1"; }

echo "T1 untouched rules: no restore, no mention"
out=$(run_exec)
case "$out" in *"RESULT 0|lint unchanged vs baseline") ok "rc 0, plain detail" ;; *) bad "unexpected result" "$out" ;; esac
case "$out" in *restoring*|*auto-restored*) bad "restore ran on untouched rules" "$out" ;; *) ok "no restore message" ;; esac

echo "T2 the hook overwrote two rules with stock: exec restores them and lints, not BLIND"
reseed
[ "$(portable_md5 "$EBK")" != "$(toolkit_md5 entity_business_key.star)" ] && ok "precondition: rule differs from the toolkit copy" || bad "reseed did not change the rule"
out=$(run_exec)
case "$out" in *"RESULT 0|"*) ok "exec result rc 0 (lint ran)" ;; *) bad "still failing after the restore" "$out" ;; esac
case "$out" in *"auto-restored after a stock re-seed (conv010_act_microflow_content.star,entity_business_key.star)"*) ok "row detail names both rules" ;; *) bad "detail does not name the restored rules" "$out" ;; esac
case "$out" in *"restoring the toolkit versions"*) ok "screen says it restored" ;; *) bad "restore not logged on screen" "$out" ;; esac
case "$out" in *BLIND*"RESULT 3"*|*"RESULT 3"*) bad "reported BLIND" "$out" ;; *) ok "not BLIND" ;; esac
cmp -s "$TK/lint-rules/entity_business_key.star" "$EBK" && ok "entity_business_key is the toolkit version again" || bad "entity_business_key not restored"
cmp -s "$TK/lint-rules/conv010_act_microflow_content.star" "$C10" && ok "conv010 is the toolkit version again" || bad "conv010 not restored"
out=$(cd "$P" && LINT_JSON="$WORK/lint.json" bash bin/lint-gate.sh 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "a plain lint-gate run afterwards passes too" || bad "gate rc $rc after the restore" "$out"

echo "T3 a hand-edited rule (header kept) is not touched by the self-heal"
printf '\n# local tweak\n' >> "$EBK"; before=$(portable_md5 "$EBK")
reseed_c10() { sed '1,/^# --- end mxtk-lint-rule header ---$/d' "$TK/lint-rules/conv010_act_microflow_content.star" > "$C10"; }
reseed_c10
out=$(run_exec)
[ "$(portable_md5 "$EBK")" = "$before" ] && ok "edited rule left as the project had it" || bad "edited rule overwritten"
cmp -s "$TK/lint-rules/conv010_act_microflow_content.star" "$C10" && ok "the re-seeded one beside it was restored" || bad "re-seeded rule not restored"

echo "T4 MXTK_NO_LINT_RESTORE=1 keeps the old behaviour: BLIND, rules untouched"
( . "$TK/bin/lib/install-lint-rules.sh"; mxtk_install_lint_rules "$TK" "$P" 0 "all" ) >/dev/null 2>&1
reseed
out=$(run_exec env MXTK_NO_LINT_RESTORE=1)
case "$out" in *"RESULT 3|lint BLIND: rules reverted to stock"*) ok "BLIND rc 3 with the opt-out" ;; *) bad "opt-out did not keep BLIND" "$out" ;; esac
[ "$(portable_md5 "$EBK")" != "$(toolkit_md5 entity_business_key.star)" ] && ok "rule left stock" || bad "restored despite opt-out"

echo "T5 no toolkit root found: BLIND as before, nothing invented"
mv "$P/CLAUDE.local.md" "$WORK/cl.md"
out=$(run_exec env MXTK_ROOT=/nonexistent)
case "$out" in *"RESULT 3|lint BLIND: rules reverted to stock"*) ok "BLIND rc 3 without a toolkit root" ;; *) bad "no-root case wrong" "$out" ;; esac
mv "$WORK/cl.md" "$P/CLAUDE.local.md"

echo "T6 after the restore the next run is plain again"
out=$(run_exec)
case "$out" in *"RESULT 0|"*) ok "restored on the next run" ;; *) bad "not clean" "$out" ;; esac
out=$(run_exec)
case "$out" in *"RESULT 0|lint unchanged vs baseline") ok "and the one after is plain, no mention" ;; *) bad "restore noise on a clean run" "$out" ;; esac

echo; echo "passed $PASS, failed $FAIL"; [ "$FAIL" -eq 0 ]
