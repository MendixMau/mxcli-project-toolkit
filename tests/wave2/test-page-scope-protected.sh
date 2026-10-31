#!/usr/bin/env bash
# Fixture for project-bin/page-scope.sh's module derivation on mxcli v0.28+ (mendixlabs/mxcli
# #1498): SHOW MODULES writes "Protected AddOn|Solution" in the Source column for a module
# whose export level is Protected. That is not where the module came from, so a first-party
# Protected module stays in the page denominator; "Marketplace vX, Protected …" stays out.
#
# usage: bash tests/wave2/test-page-scope-protected.sh [/path/to/project-bin/page-scope.sh]
#
# Golden input is captured (fixtures/show-modules/CAPTURE.txt): the stub mxcli replays real
# `show modules` / `SHOW PAGES IN` output of v0.28.0 and v0.29.0. No real model or mxcli runs.
# Positive control: against page-scope.sh before the v0.29 compat fix, A and B FAULT (exit 2,
# "SHOW MODULES yielded no first-party module") and D's provenance lacks the Protected clause —
# 3 pass, 3 fail. Field run: the same fix on
# the "protected" model with the real v0.29.0 binary wrote MyFirstModule.Home_Web; master
# FAULTed (2026-10-30).
set -uo pipefail
TK="$(cd "$(dirname "$0")/../.." && pwd)"
SUBJECT="${1:-$TK/project-bin/page-scope.sh}"
case "$SUBJECT" in /*) ;; *) SUBJECT="$PWD/$SUBJECT" ;; esac
FX="$TK/tests/wave2/fixtures/show-modules"
. "$TK/bin/lib/portable.sh"; require_py || { echo "SKIP: no Python"; exit 0; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ps-prot.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; return 0; }

P="$WORK/proj"; mkdir -p "$P/bin"; : > "$P/App.mpr"
cp "$SUBJECT" "$P/bin/page-scope.sh"; cp "$TK/project-bin/_common.sh" "$P/bin/_common.sh"
cat > "$P/mxcli" <<STUB
#!/usr/bin/env bash
case "\$*" in
  *"SHOW MODULES"*)   cat "$FX/\$(cat "$P/.cap").out"; exit "\$(cat "$FX/\$(cat "$P/.cap").exit")" ;;
  *"SHOW PAGES IN MyFirstModule"*) cat "$FX/show-pages-in-myfirstmodule-v0.29.0.out"; exit 0 ;;
esac
exit 0
STUB
chmod +x "$P/mxcli"
run() { echo "$1" > "$P/.cap"; rm -f "$P/.claude/loop/page-scope.json"
  ( cd "$P" && PROJECT_ROOT="$P" MPR_FILE=App.mpr MXCLI_BIN="$P/mxcli" bash bin/page-scope.sh --no-roles ) > "$WORK/out" 2>&1; }
scope() { "$PY" -c 'import json,sys; print(" ".join(json.load(open(sys.argv[1]))["inScope"]))' "$P/.claude/loop/page-scope.json" 2>/dev/null; }

echo "== A: v0.29.0, first-party module set to Protected: still in scope =="
run show-modules-protected-v0.29.0; RC=$?
[ "$RC" -eq 0 ] && [ "$(scope)" = "MyFirstModule.Home_Web" ] && ok "exit 0, MyFirstModule.Home_Web in scope" || bad "A rc=$RC scope='$(scope)'" "$(cat "$WORK/out")"
echo "== B: the same on v0.28.0 =="
run show-modules-protected-v0.28.0; RC=$?
[ "$RC" -eq 0 ] && [ "$(scope)" = "MyFirstModule.Home_Web" ] && ok "exit 0, in scope" || bad "B rc=$RC" "$(cat "$WORK/out")"
echo "== C: Marketplace v2.1.0, Protected AddOn: out of scope (still a marketplace module) [guard] =="
run show-modules-marketplace-protected-v0.29.0; RC=$?
[ "$RC" -eq 2 ] && grep -q "yielded no first-party module" "$WORK/out" && ok "FAULT: no first-party module (the marketplace one is excluded)" || bad "C rc=$RC" "$(cat "$WORK/out")"
[ ! -e "$P/.claude/loop/page-scope.json" ] && ok "nothing written" || bad "C wrote a scope"
echo "== D: Source empty (as committed): in scope [guard] =="
run show-modules-source-v0.29.0; RC=$?
[ "$RC" -eq 0 ] && [ "$(scope)" = "MyFirstModule.Home_Web" ] && ok "exit 0, in scope" || bad "D rc=$RC" "$(cat "$WORK/out")"
grep -q 'empty Source column (or only' "$P/.claude/loop/page-scope.json" 2>/dev/null && ok "provenance names the rule, Protected included" || bad "D provenance" "$(cat "$P/.claude/loop/page-scope.json" 2>/dev/null | head -30)"

echo ""
echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
