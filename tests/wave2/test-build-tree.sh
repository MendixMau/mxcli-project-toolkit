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
[ -z "$(cd "$P" && git status --porcelain -- .mxtk)" ] && ok "B4 git status shows nothing under .mxtk/" || bad "B4 .mxtk shows in git status"

echo "-- B5 a compile error from the copy names the real file"
OUT="$(vm "$P" FAKE_JAVA_ERR=1)"; RC=$?
[ "$RC" -eq 1 ] && ok "B5 exit 1 (errors)" || bad "B5 exit $RC"
OUT2="$( cd "$P" && MXBUILD_PATH="$WORK/mxbuild" JAVA_HOME="$WORK/jdk" FAKE_JAVA_ERR=1 bash -c '. bin/_common.sh; PY=$(resolve_py); mxtk_gate_mxbuild "$(find_mpr)" 0 "$PWD/e.json"; printf "%s\n" "$MXTK_MXBUILD_OUT"' 2>&1 )"
has "B5 the gate's captured output names the project's file" "$OUT2" "$P/javasource/shop/actions/A.java:3: error"
hasnt "B5   never the copy's" "$OUT2" ".mxtk/build"

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

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
