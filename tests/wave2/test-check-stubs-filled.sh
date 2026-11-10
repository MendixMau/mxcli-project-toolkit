#!/usr/bin/env bash
# Fixture for bin/check-stubs-filled.sh. usage: test-check-stubs-filled.sh /path/to/check-stubs-filled.sh
# Stubs come from the REAL bin/init-agents.sh (not hand-written), so the slot syntax is the shipped one.
set -uo pipefail
CK="${1:?usage: test-check-stubs-filled.sh /path/to/check-stubs-filled.sh}"
case "$CK" in /*) ;; *) CK="$PWD/$CK" ;; esac
TK="$(cd "$(dirname "$CK")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok(){ echo "PASS $1"; }; bad(){ echo "FAIL $1"; fail=1; }
bash "$TK/bin/init-agents.sh" "$T" >/dev/null 2>&1
out="$(bash "$CK" "$T" 2>&1)"; rc=$?
[ $rc -eq 3 ] && ok "T1 fresh stub exits 3" || bad "T1 rc=$rc"
echo "$out" | grep -q "UNFILLED mdl-agent" && echo "$out" | grep -q "APP_PURPOSE" && ok "T2 names the slots" || bad "T2 $out"
# fill every real slot, keep the DOUBLE_BRACE prose
f="$T/.claude/agents/mdl-agent.md"
sed -E '/DOUBLE_BRACE/!s/\{\{[^}]*\}\}/filled/g' "$f" > "$f.n" && mv "$f.n" "$f"
out="$(bash "$CK" "$T" 2>&1)"; rc=$?
[ $rc -eq 0 ] && echo "$out" | grep -q "mdl-agent: filled" && ok "T3 filled stub exits 0 (DOUBLE_BRACE prose ignored)" || bad "T3 rc=$rc $out"
out="$(bash "$CK" "$T" nosuch 2>&1)"; rc=$?
[ $rc -eq 0 ] && echo "$out" | grep -q "no stub" && ok "T4 absent stub said out loud, exit 0" || bad "T4 rc=$rc"
bash "$CK" >/dev/null 2>&1; [ $? -eq 2 ] && ok "T5 usage exit 2" || bad "T5"
exit $fail
