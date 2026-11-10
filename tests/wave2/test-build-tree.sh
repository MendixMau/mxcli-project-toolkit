#!/usr/bin/env bash
# test-build-tree.sh — the toolkit's full builds run in a synced copy of the model directory
# (.mxtk/build/model/), never in the deployment/ a running `mxcli run --local --watch` serves.
#
# Usage: bash tests/wave2/test-build-tree.sh [path-to-project-bin]
#        (default: the toolkit's project-bin/; the fixture installs all of it into stub projects)
#
# WHY (#686). mxbuild writes <app dir>/deployment/ whatever --target/--output say. Measured on
# mxbuild 11.13.0 with a 5-page app (PurchaseApp): --target=deploy left deployment/web with no
# dist/, and --target=package --output=x.mda rewrote 336 files under deployment/ (web/dist,
# run/bin, model). The watch app serves deployment/web, so a toolkit full build left it with no
# client (/dist/index.js 404) until `mxcli run restart`. The same app built in a copy made by
# bin/build-tree.py: BUILD SUCCEEDED, 0 files under the original deployment/ changed.
#
# The mxbuild here is a stub that does what the measurement showed: it removes
# <dir of the .mpr>/deployment/web/dist and writes a marker there. Nothing starts Java or Mendix.
#
# Covers
#   B1 verify-model.sh (pre-push hook, module-close.sh): the served folder is unchanged; the build
#      output is under .mxtk/build/model/deployment/; the stamp is written; it says where it built
#   B2 exec.sh's gate function (mxtk_gate_mxbuild): same, single-tree
#   B3 two-tree (app/X.mpr): app/deployment/ unchanged, the copy is the app folder
#   B4 the sync: a file deleted from the model leaves the copy; the copy's deployment/ survives a
#      sync; .git, .mxcli, sources/, *.mpr.lock are not copied; .mxtk/ ignores itself
#   B5 a compile error printed from the copy names the REAL file, not .mxtk/build/
#   B6 MXTK_GATE_IN_PLACE=1 builds in place, as before, and says so
#   B7 the pre-push hook prints the restart line only after an in-place build
#   B8 one build at a time in the copy: a live holder of .mpr-snapshots/.build.lock is waited for,
#      still held after MXTK_BUILD_LOCK_WAIT → in place with the reason; a dead holder's lock is
#      taken over; the lock is released after the build; 12 contenders on a stale lock → ≤1 holder
#   B9 check-design-portability.sh reads the copy's compiled theme when it is the newer one
set -uo pipefail

TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PB="${1:-$TOOLKIT/project-bin}"
case "$PB" in /*) ;; *) PB="$PWD/$PB" ;; esac
[ -f "$PB" ] && PB="$(dirname "$PB")"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 — missing '$3' in: $(printf '%s' "$2" | tail -5)" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1 — unexpected '$3'" ;; *) ok "$1" ;; esac; }
echo "== subject: $PB"
command -v python3 >/dev/null 2>&1 || { echo "  [skip] no python3"; echo "PASS=0 FAIL=0"; exit 0; }  # portability-ok: a presence probe in a fixture

WORK="$(mktemp -d "${TMPDIR:-/tmp}/buildtree.XXXXXX")" || exit 2
WORK="$(cd "$WORK" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/jdk/bin"; printf '#!/bin/sh\nexit 0\n' > "$WORK/jdk/bin/java"; chmod +x "$WORK/jdk/bin/java"
cat > "$WORK/mxbuild" <<'MXB'
#!/usr/bin/env bash
# Stub mxbuild: what --target=deploy was measured to do to <app dir>/deployment/.
mpr=""; ef=""
for a in "$@"; do case "$a" in --write-errors=*) ef="${a#--write-errors=}" ;; -*) ;; *) mpr="$a" ;; esac; done
d="$(cd "$(dirname "$mpr")" && pwd)"
echo "$d" >> "${FAKE_MXB_LOG:-/dev/null}"
mkdir -p "$d/deployment/web"; rm -rf "$d/deployment/web/dist"; echo built > "$d/deployment/web/built-by-mxbuild"
if [ -n "${FAKE_JAVA_ERR:-}" ]; then
  echo "$d/javasource/shop/actions/A.java:3: error: cannot find symbol"
  printf '{"problems":[{"severity":"Error","errorCode":"CE0001","message":"Java compile"}]}' > "$ef"; exit 1
fi
printf '{"problems":[]}' > "$ef"; exit 0
MXB
chmod +x "$WORK/mxbuild"

mkproj() {  # $1 = project dir, $2 = model subdir ("" or "app")
  local P="$1" A="$1${2:+/$2}"
  mkdir -p "$P/bin" "$A/mprcontents/ab/cd" "$A/javasource/shop/actions" "$A/deployment/web/dist" "$A/.mxcli" "$P/sources/legacy"
  printf 'not a real model\n' > "$A/Shop.mpr"; printf 'bson\n' > "$A/mprcontents/ab/cd/u.mxunit"
  printf 'class A {}\n' > "$A/javasource/shop/actions/A.java"; printf 'gone soon\n' > "$A/javasource/shop/actions/Old.java"
  printf '/* the watch client */\n' > "$A/deployment/web/dist/index.js"
  printf '{}\n' > "$A/.mxcli/run-local.json"; printf 'lock\n' > "$A/Shop.mpr.lock"; printf 'legacy\n' > "$P/sources/legacy/x.cs"
  cp "$PB"/* "$P/bin/" 2>/dev/null; chmod +x "$P/bin/"* 2>/dev/null
  ( cd "$P" && git init -q . && printf '.mpr-snapshots/\n' > .gitignore && git add -A \
      && git -c user.email=t@t -c user.name=t commit -qm fixture ) >/dev/null 2>&1
}
vm() { ( cd "$1" && shift && env MXBUILD_PATH="$WORK/mxbuild" JAVA_HOME="$WORK/jdk" "$@" bash bin/verify-model.sh ) 2>&1; }
served_ok() { [ "$(cat "$1/deployment/web/dist/index.js" 2>/dev/null)" = "/* the watch client */" ] && [ ! -e "$1/deployment/web/built-by-mxbuild" ]; }

echo "-- B1 verify-model.sh builds the copy; the served folder is untouched"
P="$WORK/single"; mkproj "$P" ""
OUT="$(vm "$P")"; RC=$?
[ "$RC" -eq 0 ] && ok "B1 exit 0" || bad "B1 exit $RC: $(printf '%s' "$OUT" | tail -4)"
served_ok "$P" && ok "B1 deployment/web/dist/index.js (the watch client) unchanged" || bad "B1 the served folder was rewritten"
[ -f "$P/.mxtk/build/model/deployment/web/built-by-mxbuild" ] && ok "B1 the build wrote under .mxtk/build/model/deployment/" || bad "B1 no build output in the copy"
has "B1 says where it built" "$OUT" "built in .mxtk/build/ — the running app's deployment/ was not touched"
grep -q '^state: pass' "$P/.claude/.model-verified" 2>/dev/null && ok "B1 the model is stamped" || bad "B1 no pass stamp: $(cat "$P/.claude/.model-verified" 2>/dev/null | head -3)"
[ "$(cat "$P/.claude/loop/last-full-build" 2>/dev/null)" = copy ] && ok "B1 records the build place for the hook and module-close" || bad "B1 no last-full-build record"

echo "-- B2 exec.sh's gate function builds the copy"
rm -rf "$P/.mxtk"; printf '/* the watch client */\n' > "$P/deployment/web/dist/index.js"
OUT="$( cd "$P" && MXBUILD_PATH="$WORK/mxbuild" JAVA_HOME="$WORK/jdk" bash -c '. bin/_common.sh; PY=$(resolve_py); mxtk_gate_mxbuild "$(find_mpr)" 0 "$PWD/e.json"; echo "rc=$? place=$MXTK_BUILD_PLACE"' 2>&1 )"
has "B2 the gate passes" "$OUT" "rc=0 place=copy"
served_ok "$P" && ok "B2 the served folder is unchanged after a gate build" || bad "B2 the gate rewrote the served folder"
[ -f "$P/.mxtk/build/model/deployment/web/built-by-mxbuild" ] && ok "B2 the gate's output is in the copy" || bad "B2 no output in the copy"

echo "-- B4 the sync"
[ -f "$P/.mxtk/build/model/javasource/shop/actions/Old.java" ] && ok "[setup] Old.java is in the copy" || bad "[setup] Old.java not copied"
( cd "$P" && git rm -q javasource/shop/actions/Old.java && git -c user.email=t@t -c user.name=t commit -qm rm ) >/dev/null 2>&1
vm "$P" >/dev/null
[ ! -e "$P/.mxtk/build/model/javasource/shop/actions/Old.java" ] && ok "B4 a file deleted from the model is gone from the copy" || bad "B4 Old.java lingers in the copy (it would still compile)"
[ -f "$P/.mxtk/build/model/deployment/web/built-by-mxbuild" ] && ok "B4 the copy's own deployment/ survives a sync" || bad "B4 the sync removed the build output"
for x in .git .mxcli sources Shop.mpr.lock .mxtk; do
  [ -e "$P/.mxtk/build/model/$x" ] && bad "B4 $x was copied" || ok "B4 $x is not copied"
done
[ "$(cat "$P/.mxtk/.gitignore" 2>/dev/null)" = "*" ] && ok "B4 .mxtk/ ignores itself" || bad "B4 .mxtk/.gitignore missing"
# #721 review: a read-only source file synced again after it changed (copy2 kept its mode, so the
# copy was read-only too: EACCES); and a change inside the same second with the same size.
BT="$P/bin/build-tree.py"; RO="$P/javasource/shop/actions/RO.java"
printf 'aaaa\n' > "$RO"; chmod 444 "$RO"
python3 -I "$BT" "$P/Shop.mpr" "$P/.mxtk/build/model" >/dev/null 2>&1 || bad "B4 [setup] first sync of a read-only file failed"  # portability-ok: fixture runs the script directly
chmod 644 "$RO"; printf 'bbbb\n' > "$RO"; chmod 444 "$RO"
OUT="$(python3 -I "$BT" "$P/Shop.mpr" "$P/.mxtk/build/model" 2>&1)"; RC=$?  # portability-ok: fixture runs the script directly
[ "$RC" -eq 0 ] && [ "$(cat "$P/.mxtk/build/model/javasource/shop/actions/RO.java")" = bbbb ] \
  && ok "B4 a changed read-only source file is re-copied (no EACCES)" || bad "B4 read-only resync: rc=$RC $OUT"
chmod 644 "$RO"
python3 - "$RO" <<'PY'  # portability-ok: fixture sets a sub-second mtime
import os, sys
f = sys.argv[1]; st = os.stat(f)
open(f, "w").write("cccc\n")
os.utime(f, ns=(st.st_atime_ns, st.st_mtime_ns + 1000))
PY
python3 -I "$BT" "$P/Shop.mpr" "$P/.mxtk/build/model" >/dev/null 2>&1  # portability-ok: fixture runs the script directly
[ "$(cat "$P/.mxtk/build/model/javasource/shop/actions/RO.java")" = cccc ] \
  && ok "B4 a same-size change within the same second is copied (mtime in nanoseconds)" || bad "B4 sub-second change missed"
rm -f "$RO"
[ -z "$(cd "$P" && git status --porcelain -- .mxtk)" ] && ok "B4 git status shows nothing under .mxtk/" || bad "B4 .mxtk shows in git status"

echo "-- B5 a compile error from the copy names the real file"
OUT="$(vm "$P" FAKE_JAVA_ERR=1)"; RC=$?
[ "$RC" -eq 1 ] && ok "B5 exit 1 (errors)" || bad "B5 exit $RC"
OUT2="$( cd "$P" && MXBUILD_PATH="$WORK/mxbuild" JAVA_HOME="$WORK/jdk" FAKE_JAVA_ERR=1 bash -c '. bin/_common.sh; PY=$(resolve_py); mxtk_gate_mxbuild "$(find_mpr)" 0 "$PWD/e.json"; printf "%s\n" "$MXTK_MXBUILD_OUT"' 2>&1 )"
has "B5 the gate's captured output names the project's file" "$OUT2" "$P/javasource/shop/actions/A.java:3: error"
hasnt "B5   never the copy's" "$OUT2" ".mxtk/build"

echo "-- B5b a glob character in the project path; the native C:\\ form mxbuild.exe prints (#721 review)"
G="$WORK/proj [x]"; mkproj "$G" ""
OUT2="$( cd "$G" && MXBUILD_PATH="$WORK/mxbuild" JAVA_HOME="$WORK/jdk" FAKE_JAVA_ERR=1 bash -c '. bin/_common.sh; PY=$(resolve_py); mxtk_gate_mxbuild "$(find_mpr)" 0 "$PWD/e.json"; printf "%s\n" "$MXTK_MXBUILD_OUT"' 2>&1 )"
has "B5b a path holding [ ] is rewritten to the real file" "$OUT2" "$G/javasource/shop/actions/A.java:3: error"
hasnt "B5b   never the copy's" "$OUT2" ".mxtk/build"
OUT2="$( bash -c '. "$1/_common.sh"; MXTK_BUILD_PLACE=copy
  MXTK_BUILD_DST="/c/w/p/.mxtk/build/model"; MXTK_BUILD_SRC="/c/w/p"
  MXTK_BUILD_DST_N="C:\w\p\.mxtk\build\model"; MXTK_BUILD_SRC_N="C:\w\p"
  t="C:\w\p\.mxtk\build\model\javasource\shop\A.java:3: error
C:/w/p/.mxtk/build/model/javasource/shop/A.java:4: error"
  mxtk_build_tree_unmap t; printf "%s\n" "$t"' _ "$PB" 2>&1 )"
has "B5b a native Windows-form line names the real file" "$OUT2" 'C:\w\p\javasource\shop\A.java:3: error'
has "B5b   and its forward-slash form too" "$OUT2" "C:/w/p/javasource/shop/A.java:4: error"
hasnt "B5b   never the copy's" "$OUT2" ".mxtk"

echo "-- B3 two-tree: app/Shop.mpr"
T="$WORK/twotree"; mkproj "$T" app
OUT="$(vm "$T")"; RC=$?
[ "$RC" -eq 0 ] && ok "B3 exit 0" || bad "B3 exit $RC: $(printf '%s' "$OUT" | tail -4)"
served_ok "$T/app" && ok "B3 app/deployment/ unchanged" || bad "B3 app/deployment/ was rewritten"
[ -f "$T/.mxtk/build/model/Shop.mpr" ] && [ -d "$T/.mxtk/build/model/mprcontents" ] && ok "B3 the copy is the app folder" || bad "B3 copy layout: $(ls "$T/.mxtk/build/model" 2>&1 | tr '\n' ' ')"

echo "-- B6 MXTK_GATE_IN_PLACE=1 → in place, said out loud"
OUT="$(vm "$P" MXTK_GATE_IN_PLACE=1)"
has "B6 says it builds in place" "$OUT" "building in place"
[ -e "$P/deployment/web/built-by-mxbuild" ] && ok "B6 the in-place build wrote deployment/ (the old behaviour)" || bad "B6 nothing in place"
[ "$(cat "$P/.claude/loop/last-full-build" 2>/dev/null)" = in-place ] && ok "B6 recorded as in-place" || bad "B6 record"

echo "-- B7 the pre-push hook prints the restart line only after an in-place build"
H="$WORK/hook"; mkproj "$H" ""
( cd "$H" && PROJECT_ROOT="$H" bash bin/install-project-hooks.sh ) >/dev/null 2>&1
printf '#!/usr/bin/env bash\nmkdir -p .claude/loop; echo "$FAKE_PLACE" > .claude/loop/last-full-build; exit 0\n' > "$H/bin/verify-model.sh"
mkdir -p "$H/.claude/loop"; echo "checks 1" > "$H/.claude/loop/gate-kind.state"
( cd "$H" && PROJECT_ROOT="$H" MXTK_STAMP_KIND=check MXTK_STAMP_ERRORS=0 bash bin/model-stamp.sh write pass exec.sh ) >/dev/null 2>&1
hook() { ( cd "$H" && printf 'refs/heads/m %s refs/heads/m %s\n' "$(git rev-parse HEAD)" 0000000000000000000000000000000000000000 \
  | env MXTK_PREPUSH_BUILD=always FAKE_PLACE="$1" .git/hooks/pre-push origin x ) 2>&1; }
if [ -x "$H/.git/hooks/pre-push" ]; then
  OUT="$(hook copy)"
  has "B7 [setup] the hook ran the full build" "$OUT" "running the full build first"
  hasnt "B7 built in the copy → no restart line" "$OUT" "mxcli run restart"
  OUT="$(hook in-place)"
  has "B7 built in place → the restart line" "$OUT" "mxcli run restart"
else bad "B7 [setup] no pre-push hook installed"; fi
grep -q '^# mxtk-pre-push full-build hook v3' "$H/.git/hooks/pre-push" && ok "B7 the installed hook is v3" || bad "B7 hook marker is not v3"
sed -i.bak 's/full-build hook v3/full-build hook v2/' "$H/.git/hooks/pre-push" && rm -f "$H/.git/hooks/pre-push.bak"
( cd "$H" && PROJECT_ROOT="$H" bash bin/install-project-hooks.sh --check ) >/dev/null 2>&1 \
  && bad "B7 --check passes a v2 hook (sync would never give it the new line)" || ok "B7 --check fails on a v2 hook, so sync-project.sh refreshes it"

echo "-- B8 one full build at a time in the copy (.mpr-snapshots/.build.lock)"
L="$P/.mpr-snapshots/.build.lock"; mkdir -p "$P/.mpr-snapshots"
[ ! -e "$L" ] && ok "B8 no lock left behind by the builds above" || bad "B8 a lock was left behind: $(cat "$L")"
bash -c 'exec -a "bash bin/exec.sh" sleep 300' & HOLD=$!   # a live holder whose command line names exec.sh
sleep 0.3
printf '%s %s exec.sh\n' "$HOLD" "$(date +%s)" > "$L"
( sleep 3; rm -f "$L" ) & REL=$!
OUT="$(vm "$P" MXTK_BUILD_LOCK_WAIT=30)"; RC=$?
wait "$REL" 2>/dev/null
[ "$RC" -eq 0 ] && ok "B8 exit 0" || bad "B8 exit $RC: $(printf '%s' "$OUT" | tail -3)"
has "B8 a live holder is waited for, out loud" "$OUT" "is using .mxtk/build/ — waiting for it"
has "B8   then the build runs in the copy" "$OUT" "built in .mxtk/build/"
printf '%s %s exec.sh\n' "$HOLD" "$(date +%s)" > "$L"
OUT="$(vm "$P" MXTK_BUILD_LOCK_WAIT=2)"; RC=$?
has "B8 still held after the wait → builds in place, saying why" "$OUT" "building in place: another full build (pid $HOLD)"
[ "$(cat "$L" 2>/dev/null)" != "" ] && [ "$(cut -d' ' -f1 "$L")" = "$HOLD" ] && ok "B8 the holder's lock is left alone" || bad "B8 the holder's lock was touched"
kill "$HOLD" 2>/dev/null; wait "$HOLD" 2>/dev/null
OUT="$(vm "$P")"; RC=$?
has "B8 a lock whose pid is gone is stale: taken over, built in the copy" "$OUT" "built in .mxtk/build/"
[ ! -e "$L" ] && ok "B8 released after the build" || bad "B8 lock left: $(cat "$L")"
# 12 contenders against one stale lock: never more than one holder (the #721 review reproduced 4
# with a plain check-then-rm takeover). Each contender is a script named like a real holder.
CS="$WORK/cs"; mkdir -p "$CS/bin"
cat > "$CS/bin/verify-model.sh" <<'CT'
#!/usr/bin/env bash
. "$1/bin/_common.sh"
MXTK_BUILD_LOCK_WAIT=60 mxtk_build_lock_take "$1" || { echo miss >> "$2/miss"; exit 0; }
: > "$2/in.$$"; ls "$2" | grep -c '^in\.' >> "$2/counts"; sleep 0.2; rm -f "$2/in.$$"
mxtk_build_lock_release
CT
chmod +x "$CS/bin/verify-model.sh"
sh -c 'exit 0' & DEADP=$!; wait "$DEADP" 2>/dev/null
printf '%s 1 verify-model.sh\n' "$DEADP" > "$L"
CP=""
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do bash "$CS/bin/verify-model.sh" "$P" "$CS" & CP="$CP $!"; done
for c in $CP; do wait "$c" 2>/dev/null; done
MAXH="$(sort -n "$CS/counts" 2>/dev/null | tail -1)"; NH="$(wc -l < "$CS/counts" 2>/dev/null | tr -d ' ')"
[ "${MAXH:-0}" = 1 ] && ok "B8 12 contenders on a stale lock: at most 1 holder at a time" || bad "B8 $MAXH holders at once"
[ "${NH:-0}" = 12 ] && ok "B8   and all 12 held it in turn" || bad "B8 only ${NH:-0} of 12 held it ($(cat "$CS/miss" 2>/dev/null | wc -l | tr -d ' ') gave up)"
[ ! -e "$L" ] && [ ! -e "$L.takeover" ] && ok "B8   no lock or takeover file left" || bad "B8 left: $(ls "$P/.mpr-snapshots")"

echo "-- B9 readers of the build output find the copy's (check-design-portability.sh, #721 review)"
D="$WORK/design"; mkdir -p "$D/.mxtk/build/model/deployment/web" "$D/deployment/web" "$D/design"; printf ".kpi{font-size:1.6rem}\n" > "$D/design/ds.css"
printf 'html{font-size:16px}\n' > "$D/.mxtk/build/model/deployment/web/theme.compiled.css"
OUT="$( cd "$D" && bash "$PB/check-design-portability.sh" 2>&1 )"
has "B9 only the copy has a compiled theme: its root font-size is read" "$OUT" "root font-size: 16px"
printf 'html{font-size:10px}\n' > "$D/deployment/web/theme.compiled.css"; touch -t 202601010000 "$D/deployment/web/theme.compiled.css"
OUT="$( cd "$D" && bash "$PB/check-design-portability.sh" 2>&1 )"
has "B9 the copy's theme is newer: it wins" "$OUT" "root font-size: 16px"
touch -t 202601010000 "$D/.mxtk/build/model/deployment/web/theme.compiled.css"; touch "$D/deployment/web/theme.compiled.css"
OUT="$( cd "$D" && bash "$PB/check-design-portability.sh" 2>&1 )"
has "B9 deployment/'s theme is newer: it wins" "$OUT" "root font-size: 10px"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
