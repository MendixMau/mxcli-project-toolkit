#!/usr/bin/env bash
# test-show-modules-v032.sh - the three module-table parsers on real mxcli v0.32 output.
#
# usage: bash tests/wave2/test-show-modules-v032.sh [toolkit root]
#
# mxcli v0.32 adds Version and Type columns after Source in `show modules` / `list modules` (empty
# for System) and ends every table with "(N modules)" / "(N pages)". The older captures in
# fixtures/show-modules/ and fixtures/rehost-list-modules/ predate both. Golden input, verbatim from
# mxcli v0.32.0-374-g591bcd73e on a blank Mendix 11.8.0 app plus a Sales module (provenance in the
# two CAPTURE.txt files).
#
#   A  pipelines/mendix-mpr/lib/own-modules.awk: own = MyFirstModule Sales; marketplace = the 7
#      "Marketplace vX" rows; the "(10 modules)" line is no module
#   B  project-bin/page-scope.sh (stub mxcli replaying the captures): exit 0, the first-party modules
#      are MyFirstModule and Sales (Administration and Atlas* are not), pages = the two real ones
#   C  project-bin/review-module.sh's module-exists grep (its SHOW MODULES fallback): Sales and System
#      match, an absent name and the trailer do not
#
# Regression guard: all three already read v0.32 correctly on master; this pins it.
set -uo pipefail
TK="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
TK="$(cd "$TK" && pwd)"
HERE="$(cd "$(dirname "$0")" && pwd)"
SM="$HERE/fixtures/show-modules"; LM="$HERE/fixtures/rehost-list-modules"
. "$TK/bin/lib/portable.sh"; require_py || { echo "SKIP: no Python"; exit 0; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/sm-v032.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; return 0; }

echo "== A: own-modules.awk on list modules v0.32.0 =="
AWK="$TK/pipelines/mendix-mpr/lib/own-modules.awk"
r="$(awk -F'|' -f "$AWK" "$LM/list-modules-v0.32.0.txt" | tr '\n' ' ' | sed 's/ $//')"
[ "$r" = "MyFirstModule Sales" ] && ok "A: own = $r" || bad "A: own" "got '$r'"
r="$(awk -F'|' -v want=marketplace -f "$AWK" "$LM/list-modules-v0.32.0.txt" | tr '\n' ' ' | sed 's/ $//')"
[ "$r" = "Administration Atlas_Core Atlas_Web_Content DataWidgets FeedbackModule NanoflowCommons WebActions" ] \
  && ok "A: marketplace = 7 rows" || bad "A: marketplace" "got '$r'"
grep -q '^(10 modules)$' "$LM/list-modules-v0.32.0.txt" && ok "A: [golden] the capture carries the (10 modules) trailer" || bad "A: trailer missing from capture"

mkstub() {  # mkstub <dir>
  cat > "$1/mxcli" <<STUB
#!/usr/bin/env bash
case "\$*" in
  *"SHOW MODULES"*|*"show modules"*) cat "$SM/show-modules-v0.32.0.out"; exit "\$(cat "$SM/show-modules-v0.32.0.exit")" ;;
  *"SHOW PAGES IN Sales"*)         cat "$SM/show-pages-in-sales-v0.32.0.out"; exit 0 ;;
  *"SHOW PAGES IN MyFirstModule"*) cat "$SM/show-pages-in-myfirstmodule-v0.32.0.out"; exit 0 ;;
esac
echo "Error: not available in this fixture"; exit 1
STUB
  chmod +x "$1/mxcli"
}

echo "== B: page-scope.sh on show modules / SHOW PAGES v0.32.0 =="
P="$WORK/ps"; mkdir -p "$P/bin"; : > "$P/ProbeApp.mpr"
cp "$TK/project-bin/page-scope.sh" "$TK/project-bin/_common.sh" "$P/bin/"; mkstub "$P"
( cd "$P" && PROJECT_ROOT="$P" MPR_FILE=ProbeApp.mpr MXCLI_BIN="$P/mxcli" bash bin/page-scope.sh --no-roles ) > "$WORK/ps.out" 2>&1; RC=$?
J="$P/.claude/loop/page-scope.json"
mods="$("$PY" -c 'import json,sys; d=json.load(open(sys.argv[1])); print(" ".join(sorted(d["counts"]["perModule"])))' "$J" 2>/dev/null)"
scope="$("$PY" -c 'import json,sys; print(" ".join(sorted(json.load(open(sys.argv[1]))["inScope"])))' "$J" 2>/dev/null)"
[ "$RC" -eq 0 ] && ok "B: exit 0" || bad "B: exit $RC" "$(cat "$WORK/ps.out")"
[ "$scope" = "MyFirstModule.Home_Web Sales.Customer_Edit" ] && ok "B: in scope = $scope" || bad "B: inScope" "got '$scope'"
[ "$mods" = "MyFirstModule Sales" ] && ok "B: first-party modules = $mods" || bad "B: first-party modules" "got '$mods'"

echo "== C: review-module.sh module-exists probe on show modules v0.32.0 =="
# The probe's own grep line, read out of review-module.sh and run on the capture. Running the whole
# script costs 60 s per call here: with no catalog it reaches the SHOW MODULES probe, whose
# with_timeout watchdog keeps the command substitution's pipe open until its sleep ends.
RMS="$TK/project-bin/review-module.sh"
LINE="$(grep -n 'grep -qE -- "^\\| \*\$MODULE +\\|" <<<"\$MODLIST"' "$RMS" | head -1)"
[ -n "$LINE" ] && ok "C: [setup] the probe line is in review-module.sh (line ${LINE%%:*})" || bad "C: probe grep line not found in review-module.sh"
MODLIST="$(cat "$SM/show-modules-v0.32.0.out")"
probe() { MODULE="$1"; grep -qE -- "^\| *$MODULE +\|" <<<"$MODLIST"; }
probe Sales && ok "C: Sales found in the v0.32 table" || bad "C: Sales not found"
probe System && ok "C: System (empty Version/Type cells) found" || bad "C: System not found"
probe Nope && bad "C: an absent module matched" || ok "C: an absent module does not match"
probe modules && bad "C: the (10 modules) trailer matched as a module" || ok "C: the trailer is no module"

echo ""
echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
