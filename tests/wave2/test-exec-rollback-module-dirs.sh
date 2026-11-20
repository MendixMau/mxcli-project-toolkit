#!/usr/bin/env bash
# test-exec-rollback-module-dirs.sh - a rolled-back exec leaves no module source folder behind.
#
# usage: bash tests/wave2/test-exec-rollback-module-dirs.sh [path-to-exec.sh]
#
# Field (real-mxcli run, mxcli v0.32.0-374, MxBuild 11.8.0, 2026-11-20): `create module SlipTwo` plus a
# microflow with a member typo passed `mxcli check`, was written, failed the mx check gate (CE1613)
# and was rolled back. The gate's own `mx check` generates themesource/<module>/ for every module
# that lacks one (mxcli exec writes nothing there); the snapshot covers the .mpr and mprcontents/
# only, so themesource/sliptwo/ stayed behind, untracked, for a module the model no longer has.
#
# Golden input, captured verbatim from that run, in fixtures/exec-rollback-module-dirs/:
#   rollback-untracked-v0.32.0.txt   `git status --porcelain --untracked-files=all` after the rollback
#   generated-by-mx-check/sliptwo/   the five files themselves, byte for byte (the real folder also
#                                    holds an empty public/, which git cannot carry)
# The stub mxbuild copies that folder into themesource/ beside the .mpr whenever the model holds the
# script's write, as the real `mx check` does.
#
#   A  single tree: gate fails -> restored, themesource/sliptwo/ moved into the snapshot  (fails on master)
#   B  .mpr under app/: same, app/themesource/sliptwo/ moved                               (fails on master)
#   C  a folder that existed before the write is kept: tracked, untracked, and ignored ones
#   D  a clean apply keeps the new module's folder
#   E  a folder something else created during the exec window (themesource/peerwork/, made by
#      the stub mxbuild) survives the rollback: only the script's own module is moved
#
# Synthetic project, stub mxcli / mxbuild / java. The real snapshot-mpr.sh and restore-mpr.sh run.
set -uo pipefail

TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUBJECT="${1:-$TOOLKIT/project-bin/exec.sh}"
case "$SUBJECT" in /*) ;; *) SUBJECT="$PWD/$SUBJECT" ;; esac
GOLD="$TOOLKIT/tests/wave2/fixtures/exec-rollback-module-dirs"
WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/exec-moddirs.XXXXXX")" && pwd -P)" || exit 2
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL - $1${2:+: $2}"; }
echo "== subject: $SUBJECT"

# The captured status lists exactly the files the captured folder holds.
_want="$(sed -n 's#^?? themesource/##p' "$GOLD/rollback-untracked-v0.32.0.txt" | LC_ALL=C sort)"
_have="$(cd "$GOLD/generated-by-mx-check" && find . -type f | sed 's#^\./##' | LC_ALL=C sort)"
[ -n "$_want" ] && [ "$_want" = "$_have" ] && ok "[golden] status capture and folder capture agree ($(printf '%s\n' "$_want" | grep -c .) files)" \
  || bad "[golden] status capture and folder capture disagree" "$_want / $_have"

mkdir -p "$WORK/jdk/bin"; printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/jdk/bin/java"
cat > "$WORK/mxbuild" <<MXB
#!/usr/bin/env bash
GOLD="$GOLD"
MXB
cat >> "$WORK/mxbuild" <<'MXB'
err=""; proj=""; for a in "$@"; do case "$a" in --write-errors=*) err="${a#--write-errors=}" ;; *.mpr) proj="$a" ;; esac; done
n=$(( $(cat "$MXB_N" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$MXB_N"
mode="$(printf '%s\n' "$MXB_MODES" | tr ',' '\n' | sed -n "${n}p")"; mode="${mode:-ok}"
# Like the real mx check: generate themesource/<module>/ for a module that has none. The model
# holds module SlipTwo once the script's write is in it.
M="$(dirname "${proj:-$MXB_MODEL}")"; [ -f "$M/Fixture.mpr" ] || M="$MXB_MODEL"
if grep -q written "$M/Fixture.mpr" 2>/dev/null && [ ! -d "$M/themesource/sliptwo" ]; then
  cp -R "$GOLD/generated-by-mx-check/sliptwo" "$M/themesource/sliptwo"
fi
# E: another session writes its own new folder during the window.
if [ -n "${MXB_PEER:-}" ] && [ "$mode" = err ]; then mkdir -p "$M/themesource/peerwork"; printf 'peer\n' > "$M/themesource/peerwork/x.scss"; fi
case "$mode" in
  ok)  [ -n "$err" ] && printf '{"problems":[]}' > "$err"; exit 0 ;;
  err) [ -n "$err" ] && printf '{"problems":[{"severity":"Error","code":"CE1613","message":"The selected attribute '"'"'SlipTwo.Thing.Nmae'"'"' no longer exists.","element":{"document":"SlipTwo.ACT_Thing"}}]}' > "$err"; exit 1 ;;
esac
MXB
chmod +x "$WORK/mxbuild" "$WORK/jdk/bin/java"

# mk <dir> <model subdir or ""> : a committed project with tracked themesource/sales, an untracked
# themesource/userwork (theme work not yet committed) and an ignored javasource/sales/proxies.
mk() {
  P="$1"; M="$P${2:+/$2}"
  mkdir -p "$P/bin" "$P/mdlsource" "$M/mprcontents" "$M/themesource/sales" "$M/javasource/sales/proxies"
  printf 'not a real model\n' > "$M/Fixture.mpr"; printf 'bson\n' > "$M/mprcontents/a.mxunit"
  printf '{}\n' > "$M/themesource/sales/settings.json"; printf 'x\n' > "$M/javasource/sales/proxies/P.java"
  printf 'mdl 1;\ncreate module SlipTwo;\n' > "$P/mdlsource/test.mdl"
  cp "$TOOLKIT/project-bin/_common.sh" "$TOOLKIT/project-bin/restore-mpr.sh" "$TOOLKIT/project-bin/snapshot-mpr.sh" "$P/bin/"
  cp "$SUBJECT" "$P/bin/exec.sh"
  cat > "$P/mxcli" <<MXCLI
#!/usr/bin/env bash
case "\${1:-}" in
  exec) echo "written" >> "$M/Fixture.mpr"; echo x >> "$M/mprcontents/a.mxunit"; echo "Created module: SlipTwo"; exit 0 ;;
esac
exit 0
MXCLI
  chmod +x "$P/bin/"*.sh "$P/mxcli"
  ( cd "$P" && git init -q . && printf '.mpr-snapshots/\ndocs/\n.claude/\n/javasource/*/proxies/\n/app/javasource/*/proxies/\n' > .gitignore \
    && git add -A && git -c user.email=t@t -c user.name=t commit -qm fixture ) >/dev/null 2>&1
  mkdir -p "$M/themesource/userwork"; printf 'mine\n' > "$M/themesource/userwork/main.scss"
}
run() {  # run <project> <modes> -> RC   (MXB_MODEL: the model dir, for the stub mxbuild)
  rm -f "$WORK/n"; mkdir -p "$WORK/tmp"
  _m="$1"; [ -d "$1/app" ] && _m="$1/app"
  ( cd "$1" && MXB_MODEL="$_m" MXB_PEER="${MXB_PEER:-}" TMPDIR="$WORK/tmp" SP_RESTART=0 MXTK_NO_INSTALL=1 SKIP_LINT=fixture MXB_N="$WORK/n" MXB_MODES="$2" \
      MXBUILD_PATH="$WORK/mxbuild" JAVA_HOME="$WORK/jdk" ./bin/exec.sh mdlsource/test.mdl ) >"$WORK/out" 2>&1
  RC=$?
}
kept_old() {  # kept_old <model dir> <label>
  [ -f "$1/themesource/sales/settings.json" ] && ok "$2: tracked themesource/sales kept" || bad "$2: tracked folder removed"
  [ -f "$1/themesource/userwork/main.scss" ] && ok "$2: untracked pre-existing themesource/userwork kept" || bad "$2: user's untracked folder removed"
  [ -f "$1/javasource/sales/proxies/P.java" ] && ok "$2: ignored javasource/sales/proxies kept" || bad "$2: ignored folder removed"
}

echo "== A: single tree, gate fails =="
mk "$WORK/a" ""
run "$WORK/a" ok,err,ok
grep -q 'verdict=restored' "$WORK/out" && ok "A: restored" || bad "A: not restored" "rc=$RC $(tail -5 "$WORK/out")"
[ ! -e "$WORK/a/themesource/sliptwo" ] && ok "A: themesource/sliptwo/ gone from the model folder" || bad "A: themesource/sliptwo/ left behind"
ls "$WORK/a/.mpr-snapshots"/*/stray-module-dirs/themesource/sliptwo/settings.json >/dev/null 2>&1 \
  && ok "A: moved into the snapshot (stray-module-dirs/), recoverable" || bad "A: not found under the snapshot"
[ -z "$(git -C "$WORK/a" status --porcelain --untracked-files=all -- themesource | grep -v userwork)" ] \
  && ok "A: no untracked file left under themesource/ but the user's" || bad "A: untracked files remain" "$(git -C "$WORK/a" status --porcelain -- themesource)"
grep -q 'Moved themesource/sliptwo/ (source folder of module SlipTwo, which this script created) to .*stray-module-dirs/themesource/sliptwo' "$WORK/out" \
  && ok "A: the move and its destination said on screen" || bad "A: move not said" "$(grep -i 'moved\|removed' "$WORK/out")"
grep -q 'not in the restored model' "$WORK/out" && bad "A: old wording" || ok "A: no 'not in the restored model' claim"
kept_old "$WORK/a" "C(single)"

echo "== B: .mpr under app/, gate fails =="
mk "$WORK/b" "app"
run "$WORK/b" ok,err,ok
grep -q 'verdict=restored' "$WORK/out" && ok "B: restored" || bad "B: not restored" "rc=$RC $(tail -5 "$WORK/out")"
[ ! -e "$WORK/b/app/themesource/sliptwo" ] && ok "B: app/themesource/sliptwo/ gone from the model folder" || bad "B: app/themesource/sliptwo/ left behind"
ls "$WORK/b/.mpr-snapshots"/*/stray-module-dirs/app/themesource/sliptwo/settings.json >/dev/null 2>&1 \
  && ok "B: moved into the snapshot" || bad "B: not found under the snapshot"
kept_old "$WORK/b/app" "C(app/)"

echo "== D: clean apply keeps the new folder =="
mk "$WORK/d" ""
run "$WORK/d" ok,ok
[ "$RC" -eq 0 ] && [ -f "$WORK/d/themesource/sliptwo/settings.json" ] && ok "D: applied, themesource/sliptwo/ kept" \
  || bad "D: clean apply lost the folder" "rc=$RC $(tail -5 "$WORK/out")"

echo "== E: a folder another writer created in the window survives the rollback =="
mk "$WORK/e" ""
MXB_PEER=1 run "$WORK/e" ok,err,ok
grep -q 'verdict=restored' "$WORK/out" && ok "E: restored" || bad "E: not restored" "rc=$RC $(tail -5 "$WORK/out")"
[ -f "$WORK/e/themesource/peerwork/x.scss" ] && ok "E: themesource/peerwork/ (not the script's module) kept in place" \
  || bad "E: a peer's new folder was removed" "$(grep -i 'moved\|removed' "$WORK/out")"
[ ! -e "$WORK/e/themesource/sliptwo" ] && ok "E: the script's own module folder still moved" || bad "E: sliptwo left behind"

echo ""
echo "== $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
