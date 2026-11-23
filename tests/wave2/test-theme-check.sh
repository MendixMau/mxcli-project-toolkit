#!/usr/bin/env bash
# test-theme-check.sh — the theme (SCSS) compile check the build gate was missing (#837).
#
# usage: bash tests/wave2/test-theme-check.sh [path-to-project-bin-dir | path-to-theme-check.sh]
#
# Field (a regression run, 2026-11-17, mxcli v0.32.0, Mendix 11.8.0): the exec gate and verify-model.sh
# both said "0 errors" and `mxcli run` then failed with "[CE6093] The theme could not be compiled ...
# main.scss 254:58". `mx check` never compiles the theme; a deploy build reports a broken one as an
# errors[] entry with no problem (exit 3, warm) or as CE6093 with no file or line (cold). Now
# project-bin/_common.sh mxtk_theme_check runs the dart-sass that ships beside mxbuild over the entry
# file mxbuild generated, and mxtk_gate_mxbuild / verify-model.sh / exec.sh / module-close.sh act on it.
#
# Golden input (tests/wave2/fixtures/theme-check/, README beside them): sass 1.49.11 stderr, an `mx check -j`
# file and an mxbuild --write-errors file, all captured on a real Mendix 11.8.0 app with a broken theme;
# the entry file mxbuild generated. The fake `sass` below only replays them; the parsing under test is
# _common.sh's.
#
#   T1  clean theme: exit 0, "✓ theme", denominator "11 of 13 entries" (2 entries name a module that
#       no longer exists: dropped and counted, never an error)
#   T2  syntax error (golden): exit 1, themesource/myfirstmodule/web/main.scss:4:24, "Expected expression."
#   T3  missing import (golden): exit 1, theme/web/main.scss:24:9, "Can't find stylesheet to import."
#   T4  not run is never green: no sass → exit 2 "NOT CHECKED"; no generated entry file → exit 2
#   T5  two-tree layout (.mpr under app/): the same result, paths relative to the model dir
#   T6  mxtk_theme_inject: empty file; the real mx check CE6093 (rewritten, not duplicated); the real
#       mxbuild errors[]-only file (errors[] kept, 1 Error problem added); a passing theme leaves the
#       file byte-identical
#   T7  mxtk_gate_mxbuild, check kind: `mx check` clean (the field's "0 errors") + broken theme → the errors
#       file counts 1 CE6093 with file:line; kind full likewise; a broken theme is NOT retried as infra
#   T8  verify-model.sh: broken theme → exit 1, CE6093 with file:line, NO stamp; clean → exit 0 stamped;
#       sass absent → exit 0 but the NOT CHECKED line is printed
#   T9  cache (MXTK_THEME_CACHE=1, exec.sh only): a pass is reused while no SCSS changed (sass not
#       started), a touched .scss recompiles, a failure voids it; without the variable it always compiles
#   T10 exec.sh end to end: a broken theme → exit 5, applied-unverified, verified=no, no stamp,
#       file:line printed, the write kept; clean → exit 0 verified=yes; theme broken since the stamp
#       → the stamp is not trusted (baseline measured), not a rollback of good work
#   T11 module-close.sh runs theme-check.sh and exits 1 on a broken theme
set -uo pipefail

TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PB="${1:-$TOOLKIT/project-bin}"
case "$PB" in /*) ;; *) PB="$PWD/$PB" ;; esac
[ -f "$PB" ] && PB="$(dirname "$PB")"
FX="$TOOLKIT/tests/wave2/fixtures/theme-check"
FXM="$TOOLKIT/tests/wave2/fixtures/mx-check"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL - $1${2:+: $2}"; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "missing '$3' in: $(printf '%s' "$2" | tail -4 | tr '\n' '|')" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1" "unexpected '$3'" ;; *) ok "$1" ;; esac; }
echo "== subject: $PB"
. "$TOOLKIT/bin/lib/portable.sh"
require_py
WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/theme-check.XXXXXX")" && pwd -P)" || exit 2
trap '[ -n "${KEEP:-}" ] || rm -rf "$WORK"' EXIT

# --- fake toolchain -----------------------------------------------------------------------------
mkdir -p "$WORK/modeler" "$WORK/jdk/bin"
printf '#!/bin/sh\nexit 0\n' > "$WORK/jdk/bin/java"
cat > "$WORK/modeler/mxbuild" <<'MXB'
#!/usr/bin/env bash
# stub mxbuild: writes the entry file a real one writes (deployment/sass/main.scss) beside the .mpr, then
# MXB_MODE: ok (empty errors file, exit 0) | errsonly (the captured warm-build errors[] file, exit 3)
mpr=""; ef=""
for a in "$@"; do case "$a" in --write-errors=*) ef="${a#--write-errors=}" ;; -*) ;; *) mpr="$a" ;; esac; done
d="$(cd "$(dirname "$mpr")" && pwd)"
n=$(( $(cat "$MXB_N" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$MXB_N"
mkdir -p "$d/deployment/sass"; cp "$FX/deployment-sass-main-11.8.0.scss" "$d/deployment/sass/main.scss"
case "${MXB_MODE:-ok}" in
  errsonly) cp "$FX/mxbuild-11.8.0-theme-errors-only.json" "$ef"; exit 3 ;;
  *) : > "$ef"; exit 0 ;;
esac
MXB
cat > "$WORK/modeler/mx" <<'MXC'
#!/bin/sh
# mx check <mpr> -j <out>: replays the clean capture (the field's "0 errors")
out=""; while [ $# -gt 0 ]; do [ "$1" = "-j" ] && { shift; out="$1"; }; shift; done
cp "$FXM/mx-check-11.13.0-clean.json" "$out"; exit 0
MXC
cat > "$WORK/sass" <<'SASS'
#!/bin/sh
# fake dart-sass: records its calls, replays a captured error when FAKE_SASS_ERR names one
echo "$*" >> "$WORK/sass.calls"
prev=""; prev2=""; for a in "$@"; do prev2="$prev"; prev="$a"; done
cp "$prev2" "$WORK/sass.entry" 2>/dev/null
[ -n "${FAKE_SASS_ERR:-}" ] && { cat "$FAKE_SASS_ERR" >&2; exit 65; }
exit 0
SASS
chmod +x "$WORK/modeler/"* "$WORK/jdk/bin/java" "$WORK/sass"
export FX FXM WORK MXB_N="$WORK/mxb.n"
export MXBUILD_PATH="$WORK/modeler/mxbuild" JAVA_HOME="$WORK/jdk" MXTK_SASS_PATH="$WORK/sass" MXTK_NO_INSTALL=1
calls() { [ -f "$WORK/sass.calls" ] && wc -l < "$WORK/sass.calls" | tr -d ' ' || echo 0; }

# mkproj <dir> <model-subdir|""> — a throwaway git project. The SCSS files are the ones the captured entry
# file names, except two modules ("probemod", "probemod3") that are gone: the real entry file kept naming them.
mkproj() {
  local P="$1" A="$1${2:+/$2}" m
  mkdir -p "$P/bin" "$A/mprcontents/ab" "$A/theme/web" "$A/deployment/sass" "$A/mdlsource"
  printf 'not a real model\n' > "$A/App.mpr"; printf 'bson\n' > "$A/mprcontents/ab/u.mxunit"
  printf 'CREATE ENUMERATION M.E (A);\n' > "$A/mdlsource/test.mdl"
  printf '.a { color: red; }\n' > "$A/theme/web/main.scss"; printf '$x: 1;\n' > "$A/theme/web/custom-variables.scss"
  printf '.i {}\n' > "$A/deployment/sass/custom-icons.scss"
  for m in administration nanoflowcommons webactions atlas_core atlas_web_content datawidgets feedbackmodule myfirstmodule; do
    mkdir -p "$A/themesource/$m/web"; printf '.m { color: blue; }\n' > "$A/themesource/$m/web/main.scss"
  done
  cp "$FX/deployment-sass-main-11.8.0.scss" "$A/deployment/sass/main.scss"
  cp "$PB"/* "$P/bin/" 2>/dev/null; chmod +x "$P/bin/"*.sh 2>/dev/null
  ( cd "$P" && git init -q . && printf '.mpr-snapshots/\n.mxtk/\n.claude/\ndocs/\ndeployment/\n' > .gitignore && git add -A \
      && git -c user.email=t@t -c user.name=t commit -qm fixture ) >/dev/null 2>&1
}
tc() { ( cd "$1" && shift && env "$@" bash bin/theme-check.sh ) 2>&1; }

echo "== T1: clean theme =="
P="$WORK/single"; mkproj "$P" ""
rm -f "$WORK/sass.calls"
OUT="$(tc "$P")"; RC=$?
[ "$RC" -eq 0 ] && ok "exit 0" || bad "T1 rc=$RC" "$OUT"
has "T1 says it compiled" "$OUT" "✓ theme: SCSS compiles (11 of 13 entries)"
ent="$(cat "$WORK/sass.entry" 2>/dev/null)"
has "T1 the entry is re-pointed at the real tree (load path)" "$ent" '@use "themesource/myfirstmodule/web/main.scss" as module9;'
hasnt "T1 a removed module's entry is dropped" "$ent" "probemod"
[ "$(printf '%s\n' "$ent" | grep -c '^@use')" -eq 11 ] && ok "T1 11 entries compiled" || bad "T1 entry count" "$ent"
has "T1 sass got the model dir as load path" "$(cat "$WORK/sass.calls")" "--load-path=$P"

echo "== T2: syntax error (captured) =="
OUT="$(tc "$P" FAKE_SASS_ERR="$FX/sass-11.8.0-syntax-error.stderr")"; RC=$?
[ "$RC" -eq 1 ] && ok "exit 1" || bad "T2 rc=$RC" "$OUT"
has "T2 file:line:col" "$OUT" "themesource/myfirstmodule/web/main.scss:4:24"
has "T2 sass's message" "$OUT" "Expected expression."
has "T2 names the code" "$OUT" "[CE6093]"

echo "== T3: missing import (captured) =="
OUT="$(tc "$P" FAKE_SASS_ERR="$FX/sass-11.8.0-missing-import.stderr")"; RC=$?
[ "$RC" -eq 1 ] && has "T3 file:line:col" "$OUT" "theme/web/main.scss:24:9" || bad "T3 rc=$RC" "$OUT"
has "T3 message" "$OUT" "Can't find stylesheet to import."

echo "== T4: not run is never green =="
OUT="$(tc "$P" MXTK_SASS_PATH=/nonexistent/sass)"; RC=$?
[ "$RC" -eq 2 ] && ok "no sass: exit 2" || bad "T4a rc=$RC" "$OUT"
has "T4a says NOT CHECKED and why" "$OUT" "NOT CHECKED — no sass compiler beside mxbuild"
hasnt "T4a is not a pass line" "$OUT" "✓"
mv "$P/deployment/sass/main.scss" "$WORK/entry.off"
OUT="$(tc "$P")"; RC=$?
[ "$RC" -eq 2 ] && has "T4b no generated entry file: NOT CHECKED" "$OUT" "no deployment/sass/main.scss yet" || bad "T4b rc=$RC" "$OUT"
mv "$WORK/entry.off" "$P/deployment/sass/main.scss"
printf '#!/bin/sh\necho "boom" >&2; exit 3\n' > "$WORK/sass.crash"; chmod +x "$WORK/sass.crash"
OUT="$(tc "$P" MXTK_SASS_PATH="$WORK/sass.crash")"; RC=$?
[ "$RC" -eq 2 ] && has "T4c sass crashed without an Error: report → not a verdict on the theme" "$OUT" "NOT CHECKED — sass exited 3" || bad "T4c rc=$RC" "$OUT"

echo "== T5: two-tree layout (.mpr under app/) =="
P2="$WORK/two"; mkproj "$P2" app
OUT="$(tc "$P2" FAKE_SASS_ERR="$FX/sass-11.8.0-syntax-error.stderr")"; RC=$?
[ "$RC" -eq 1 ] && has "T5 file:line:col, relative to app/" "$OUT" "themesource/myfirstmodule/web/main.scss:4:24" || bad "T5 rc=$RC" "$OUT"
OUT="$(tc "$P2")"; RC=$?
[ "$RC" -eq 0 ] && has "T5 clean, 11 of 13" "$OUT" "11 of 13 entries" || bad "T5 clean rc=$RC" "$OUT"
has "T5 load path is app/" "$(tail -1 "$WORK/sass.calls")" "--load-path=$P2/app"

echo "== T6: mxtk_theme_inject =="
inj() { ( cd "$P" && . bin/_common.sh && PY="$PY" && mxtk_theme_inject "$@"; echo "rc=$?" ) 2>&1; }
jq1() { "$PY" -c "import json,sys;d=json.load(open(sys.argv[1]));p=[x for x in d['problems'] if x['severity']=='Error'];print(len(p),sorted({x['errorCode'] for x in p}),len(d.get('errors',[])));print(p[0]['message'] if p else '')" "$1"; }
export FAKE_SASS_ERR="$FX/sass-11.8.0-syntax-error.stderr"
: > "$WORK/e1.json"; OUT="$(inj "$WORK/e1.json")"; has "T6a empty file: rc 1" "$OUT" "rc=1"
R="$(jq1 "$WORK/e1.json")"
has "T6a one Error CE6093" "$R" "1 ['CE6093'] 0"
has "T6a the message carries file:line:col" "$R" "The theme could not be compiled: themesource/myfirstmodule/web/main.scss:4:24 Expected expression."
cp "$FX/mx-check-11.8.0-CE6093.json" "$WORK/mc.json"
( . "$PB/_common.sh"; mxtk_mx_check_to_mxbuild "$WORK/mc.json" "$WORK/e2.json" ) >/dev/null 2>&1
R0="$(jq1 "$WORK/e2.json")"; has "T6b the real mx check capture, converted: 1 CE6093, no place" "$R0" "1 ['CE6093'] 0"
OUT="$(inj "$WORK/e2.json")"; R="$(jq1 "$WORK/e2.json")"
has "T6b rewritten in place, not duplicated" "$R" "1 ['CE6093'] 0"
has "T6b now with file:line:col" "$R" "main.scss:4:24"
cp "$FX/mxbuild-11.8.0-theme-errors-only.json" "$WORK/e3.json"
R0="$(jq1 "$WORK/e3.json")"; has "T6c the real warm-build file: 0 Error problems, 1 errors[]" "$R0" "0 [] 1"
OUT="$(inj "$WORK/e3.json")"; R="$(jq1 "$WORK/e3.json")"
has "T6c 1 Error problem added, errors[] kept" "$R" "1 ['CE6093'] 1"
unset FAKE_SASS_ERR
cp "$FX/mxbuild-11.8.0-theme-errors-only.json" "$WORK/e4.json"; B="$(cksum < "$WORK/e4.json")"
OUT="$(inj "$WORK/e4.json")"; has "T6d passing theme: rc 2 (nothing to add)" "$OUT" "rc=2"
[ "$(cksum < "$WORK/e4.json")" = "$B" ] && ok "T6d the file is byte-identical" || bad "T6d the file changed"

echo "== T7: the gate wrapper =="
gate() {  # <kind> <proj> [env...] → "<count>" of Error problems in the errors file
  local kind="$1" proj="$2"; shift 2
  ( cd "$proj" && env "$@" MXTK_GATE_KIND="$kind" bash -c '. bin/_common.sh; PY=$(resolve_py); export PY
      mxtk_gate_mxbuild "$(find_mpr)" 0 "$WORK/g.json" >/dev/null; echo "exit=$MXTK_MXBUILD_EXIT"' ) 2>&1
}
rm -f "$WORK/g.json"
OUT="$(gate check "$P" FAKE_SASS_ERR="$FX/sass-11.8.0-syntax-error.stderr")"
R="$(jq1 "$WORK/g.json")"
has "T7a check kind: mx check says 0 errors, the theme check makes it 1 CE6093" "$R" "1 ['CE6093'] 0"
has "T7a with file:line:col" "$R" "themesource/myfirstmodule/web/main.scss:4:24"
rm -f "$WORK/g.json"; OUT="$(gate check "$P")"; [ ! -s "$WORK/g.json" ] || [ "$(jq1 "$WORK/g.json" | head -1)" = "0 [] 0" ] && ok "T7b check kind, clean theme: still 0 errors" || bad "T7b" "$(cat "$WORK/g.json")"
rm -f "$WORK/g.json" "$WORK/mxb.n"
OUT="$(gate full "$P" MXB_MODE=errsonly FAKE_SASS_ERR="$FX/sass-11.8.0-syntax-error.stderr")"
R="$(jq1 "$WORK/g.json")"
has "T7c full kind, warm build (errors[] only, exit 3): becomes 1 CE6093 with file:line" "$R" "1 ['CE6093'] 1"
[ "$(cat "$WORK/mxb.n")" -eq 1 ] && ok "T7c a broken theme is not retried as an infra exit (1 mxbuild run)" || bad "T7c mxbuild ran $(cat "$WORK/mxb.n") times"
rm -f "$WORK/g.json" "$WORK/mxb.n"
OUT="$(gate full "$P" MXB_MODE=errsonly)"
[ "$(cat "$WORK/mxb.n")" -eq 2 ] && ok "T7d [guard] theme compiles but mxbuild exit 3: the infra retry still happens (2 runs)" || bad "T7d mxbuild ran $(cat "$WORK/mxb.n") times"

echo "== T8: verify-model.sh =="
vm() { ( cd "$1" && shift && env "$@" bash bin/verify-model.sh ) 2>&1; }
( cd "$P" && git checkout -q -- . 2>/dev/null; rm -rf .mxtk .claude/.model-verified ) >/dev/null 2>&1
OUT="$(vm "$P" FAKE_SASS_ERR="$FX/sass-11.8.0-syntax-error.stderr")"; RC=$?
[ "$RC" -eq 1 ] && ok "T8a broken theme: exit 1" || bad "T8a rc=$RC" "$OUT"
has "T8a CE6093 with file:line:col" "$OUT" "CE6093"
has "T8a place" "$OUT" "themesource/myfirstmodule/web/main.scss:4:24"
grep -q '^state: pass' "$P/.claude/.model-verified" 2>/dev/null && bad "T8a a pass stamp was written" || ok "T8a no pass stamp"
OUT="$(vm "$P" MXB_MODE=errsonly FAKE_SASS_ERR="$FX/sass-11.8.0-syntax-error.stderr")"; RC=$?
[ "$RC" -eq 1 ] && ok "T8b warm build (errors[] only): exit 1 with the place, not 'NOTHING was verified'" || bad "T8b rc=$RC" "$OUT"
hasnt "T8b" "$OUT" "NOTHING was verified"
OUT="$(vm "$P")"; RC=$?
[ "$RC" -eq 0 ] && ok "T8c clean theme: exit 0" || bad "T8c rc=$RC" "$OUT"
has "T8c says the theme compiled" "$OUT" "✓ theme: SCSS compiles"
grep -q '^state: pass' "$P/.claude/.model-verified" 2>/dev/null && ok "T8c stamped" || bad "T8c no stamp"
OUT="$(vm "$P" MXTK_SASS_PATH=/nonexistent/sass)"; RC=$?
[ "$RC" -eq 0 ] && has "T8d no sass: the gate still passes, but says NOT CHECKED" "$OUT" "⚠ theme: NOT CHECKED" || bad "T8d rc=$RC" "$OUT"

echo "== T9: the cache (exec.sh's per-row gate) =="
chk() { ( cd "$P" && env "$@" bash -c '. bin/_common.sh; mxtk_theme_check "" >/dev/null; echo "state=$MXTK_THEME_STATE cached=$MXTK_THEME_CACHED"' ) 2>&1; }
rm -rf "$P/.mxtk/theme-ok"; rm -f "$WORK/sass.calls"
OUT="$(chk MXTK_THEME_CACHE=1)"; has "T9a first call compiles" "$OUT" "state=pass cached=0"
[ -f "$P/.mxtk/theme-ok" ] && [ "$(cat "$P/.mxtk/theme-ok")" = "11 of 13" ] && ok "T9a the pass is remembered with its denominator" || bad "T9a marker" "$(cat "$P/.mxtk/theme-ok" 2>/dev/null)"
n0="$(calls)"; OUT="$(chk MXTK_THEME_CACHE=1)"
has "T9b nothing changed: reused" "$OUT" "state=pass cached=1"
[ "$(calls)" = "$n0" ] && ok "T9b sass was not started" || bad "T9b sass ran"
sleep 1; echo '.z{}' >> "$P/themesource/myfirstmodule/web/main.scss"
OUT="$(chk MXTK_THEME_CACHE=1)"; has "T9c an SCSS edit recompiles" "$OUT" "cached=0"
[ "$(calls)" -gt "$n0" ] && ok "T9c sass ran" || bad "T9c sass did not run"
sleep 1; mkdir -p "$P/themesource/newmod/web"; echo '.n{}' > "$P/themesource/newmod/web/main.scss"
n1="$(calls)"; OUT="$(chk MXTK_THEME_CACHE=1)"
[ "$(calls)" -gt "$n1" ] && ok "T9d a new module's theme folder recompiles" || bad "T9d" "$OUT"
n2="$(calls)"; OUT="$(chk)"
[ "$(calls)" -gt "$n2" ] && has "T9e without MXTK_THEME_CACHE the check always compiles (verify-model, module-close, theme-check.sh)" "$OUT" "cached=0" || bad "T9e sass did not run"
sleep 1; echo '.q{}' >> "$P/theme/web/main.scss"
OUT="$(chk MXTK_THEME_CACHE=1 FAKE_SASS_ERR="$FX/sass-11.8.0-syntax-error.stderr")"
has "T9f a failure is reported" "$OUT" "state=fail"
[ ! -e "$P/.mxtk/theme-ok" ] && ok "T9f and voids the remembered pass" || bad "T9f marker survived a failure"

echo "== T10: exec.sh end to end =="
E="$WORK/ex"; mkdir -p "$E/bin" "$E/mprcontents" "$E/mdlsource" "$E/theme/web" "$E/deployment/sass" "$E/themesource/myfirstmodule/web"
printf 'not a real model\n' > "$E/Fixture.mpr"; printf 'bson\n' > "$E/mprcontents/a.mxunit"
printf 'CREATE ENUMERATION "M"."E" (A);\n' > "$E/mdlsource/test.mdl"
printf '.a{}\n' > "$E/theme/web/main.scss"; printf '$x: 1;\n' > "$E/theme/web/custom-variables.scss"
printf '.m{}\n' > "$E/themesource/myfirstmodule/web/main.scss"; printf '.i{}\n' > "$E/deployment/sass/custom-icons.scss"
cp "$FX/deployment-sass-main-11.8.0.scss" "$E/deployment/sass/main.scss"
cp "$PB"/* "$E/bin/" 2>/dev/null
cat > "$E/bin/snapshot-mpr.sh" <<'SNAP'
#!/usr/bin/env bash
set -e
cd "$(dirname "$0")/.."
D=".mpr-snapshots/$(date +%Y%m%d-%H%M%S)-$$-$RANDOM"
mkdir -p "$D"; cp Fixture.mpr "$D/"; cp -r mprcontents "$D/"
echo "Snapshot saved: $D"
SNAP
cat > "$E/mxcli" <<'MXCLI'
#!/usr/bin/env bash
D="$(cd "$(dirname "$0")" && pwd)"
case "${1:-}" in
  check) exit 0 ;;
  exec) echo "written by the script" >> "$D/Fixture.mpr"; echo "x" >> "$D/mprcontents/a.mxunit"; echo "fake mxcli exec"; exit 0 ;;
esac
exit 0
MXCLI
chmod +x "$E/bin/"*.sh "$E/mxcli"
( cd "$E" && git init -q . && printf '.mpr-snapshots/\ndocs/\n.claude/\n.mxtk/\ndeployment/\n' > .gitignore && git add -A \
  && git -c user.email=t@t -c user.name=t commit -qm fixture ) >/dev/null 2>&1
ex() {  # <label> [env...]
  local l="$1"; shift
  ( cd "$E" && git checkout -q -- Fixture.mpr mprcontents && rm -rf .mpr-snapshots docs .mxtk
    { find .claude -mindepth 1 -maxdepth 1 ! -name worktrees -exec rm -rf {} + 2>/dev/null; true; } ) >/dev/null 2>&1
  mkdir -p "$WORK/tmp"
  ( cd "$E" && env "$@" TMPDIR="$WORK/tmp" SP_RESTART=0 MXTK_GATE_MODE=full ./bin/exec.sh mdlsource/test.mdl ) > "$WORK/out.$l" 2>&1
  echo $?
}
BRK="FAKE_SASS_ERR=$FX/sass-11.8.0-syntax-error.stderr"
RC="$(ex brk "$BRK")"; O="$(cat "$WORK/out.brk")"
[ "$RC" -eq 5 ] && ok "T10a broken theme: exit 5 (applied, UNVERIFIED)" || bad "T10a rc=$RC, expected 5" "$(tail -8 "$WORK/out.brk")"
has "T10a MXTK-RESULT line, backward compatible" "$O" "MXTK-RESULT exec verdict=applied-unverified applied=yes verified=no lint_new="
has "T10a the line with file:line:col" "$O" "✗ theme: [CE6093] the theme does not compile — themesource/myfirstmodule/web/main.scss:4:24: Expected expression."
grep -q 'written by the script' "$E/Fixture.mpr" && ok "T10a the write is kept (the theme is not the script's doing)" || bad "T10a the write was rolled back"
grep -q '^state: pass' "$E/.claude/.model-verified" 2>/dev/null && bad "T10a a pass stamp was written" || ok "T10a no pass stamp"
tail -1 "$E/docs/BUILD-LOG.md" | grep -q 'UNVERIFIED' && ok "T10a BUILD-LOG row says UNVERIFIED" || bad "T10a row" "$(tail -1 "$E/docs/BUILD-LOG.md")"
tail -1 "$E/docs/BUILD-LOG.md" | grep -q 'CE6093' && ok "T10a BUILD-LOG row names CE6093" || bad "T10a row lacks CE6093" "$(tail -1 "$E/docs/BUILD-LOG.md")"
RC="$(ex ok)"; O="$(cat "$WORK/out.ok")"
[ "$RC" -eq 0 ] && ok "T10b clean theme: exit 0" || bad "T10b rc=$RC" "$(tail -8 "$WORK/out.ok")"
has "T10b verified=yes" "$O" "verified=yes"
has "T10b the theme line" "$O" "✓ theme: SCSS compiles (4 of 13 entries)"
grep -q '^state: pass' "$E/.claude/.model-verified" 2>/dev/null && ok "T10b stamped" || bad "T10b no stamp"
# theme broken AFTER the stamp: the stamp fingerprints the model, not theme/ — the baseline must be measured
( cd "$E" && MXTK_THEME_CACHE=1 true ) ; mkdir -p "$WORK/tmp"
( cd "$E" && git checkout -q -- Fixture.mpr mprcontents 2>/dev/null )
( cd "$E" && env TMPDIR="$WORK/tmp" SP_RESTART=0 MXTK_GATE_MODE=full ./bin/exec.sh mdlsource/test.mdl ) > "$WORK/out.stampseed" 2>&1
( cd "$E" && git add Fixture.mpr mprcontents && git -c user.email=t@t -c user.name=t commit -qm seeded ) >/dev/null 2>&1
( cd "$E" && ./bin/model-stamp.sh check -q --clean ) >/dev/null 2>&1 && ok "T10c setup: a clean stamp exists" || bad "T10c setup: no clean stamp" "$(tail -4 "$WORK/out.stampseed")"
sleep 1; echo '.edited{}' >> "$E/themesource/myfirstmodule/web/main.scss"   # the edit that breaks it (the fake sass replays the capture)
( cd "$E" && env "$BRK" TMPDIR="$WORK/tmp" SP_RESTART=0 MXTK_GATE_MODE=full ./bin/exec.sh mdlsource/test.mdl ) > "$WORK/out.stampbrk" 2>&1; RC=$?
O="$(cat "$WORK/out.stampbrk")"
has "T10c the stamp is not trusted when the theme broke after it" "$O" "the stamp says clean, but the theme does not compile"
[ "$RC" -ne 1 ] && ok "T10c not rolled back as 'this script added CE6093' (exit $RC)" || bad "T10c exit 1: $(tail -6 "$WORK/out.stampbrk")"

echo "== T11: module-close.sh =="
MC="$WORK/mc"; mkproj "$MC" ""
printf '#!/usr/bin/env bash\necho "Checking app for errors... The app contains: 0 errors."\n' > "$MC/mxcli"; chmod +x "$MC/mxcli"
for s in metrics-ledger.sh conformance-check.sh verify-module.sh look-ledger.sh; do printf '#!/usr/bin/env bash\nexit 0\n' > "$MC/bin/$s"; done
chmod +x "$MC/bin/"*.sh
mcr() { ( cd "$MC" && env "$@" bash bin/module-close.sh Shop ) 2>&1; }
OUT="$(mcr FAKE_SASS_ERR="$FX/sass-11.8.0-syntax-error.stderr")"; RC=$?
[ "$RC" -eq 1 ] && ok "T11a broken theme: exit 1" || bad "T11a rc=$RC" "$OUT"
has "T11a the report says so" "$(cat "$MC/docs/progress/module-close/Shop.md" 2>/dev/null)" "themesource/myfirstmodule/web/main.scss:4:24"
OUT="$(mcr)"; RC=$?
[ "$RC" -eq 0 ] && ok "T11b clean theme: exit 0" || bad "T11b rc=$RC" "$OUT"

echo
echo "theme-check: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
