#!/usr/bin/env bash
# test-exec-result-line.sh - exec.sh prints one fixed MXTK-RESULT line on every path that decided
# a verdict, never as the last line of output, and without changing any exit code.
#
# usage: bash tests/wave2/test-exec-result-line.sh [path-to-exec.sh]
#
#   A  clean apply            -> verdict=applied applied=yes verified=yes lint_new=0 exit=0
#   B  lint rise (exit 4)     -> verdict=applied-lint ... lint_new=1 exit=4, last line unchanged
#   B2 the same under `Lint gate: hard` -> exit=1
#   C  bundle-only failure    -> verdict=applied-unverified verified=no exit=5, last line unchanged
#   D  gate finds a new error -> verdict=restored applied=no exit=1
#   E  uncommitted model      -> verdict=refused applied=no verified=skipped exit=1
#   F  usage error (exit 2)   -> no RESULT line (no verdict was reached)
#   G  mxcli exec exit 3, gate passes -> verdict=partial applied=partial exit=1
#   H  gate error + broken restore    -> verdict=failed applied=unknown exit=1
#   I  exec exit 3 + gate error + broken restore -> verdict=failed applied=unknown (same as H); I2 restore ok -> restored
#   J-L --patch: clean applied; script fails half-way -> restored (K) / failed when the restore is broken (K2); unverified gate -> restored (L)
#   M  lint_new words: skipped (SKIP_LINT, lint not installed), blind (lint-gate fault); B: unknown (rise not itemised)
#   Every case: exactly one RESULT line, and it is not the last line.
#
# Synthetic only: throwaway git repo, stub mxcli, stub mxbuild, stub java. Nothing real runs.
set -uo pipefail

TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUBJECT="${1:-$TOOLKIT/project-bin/exec.sh}"
case "$SUBJECT" in /*) ;; *) SUBJECT="$PWD/$SUBJECT" ;; esac
WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/exec-result.XXXXXX")" && pwd -P)" || exit 2

trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL - $1${2:+: $2}"; }
echo "== subject: $SUBJECT"

P="$WORK/proj"
mkdir -p "$P/bin" "$P/mprcontents" "$P/mdlsource" "$WORK/jdk/bin"
printf 'not a real model\n' > "$P/Fixture.mpr"
printf 'bson\n' > "$P/mprcontents/a.mxunit"
printf 'CREATE MODULE "Nope";\n' > "$P/mdlsource/test.mdl"
cp "$TOOLKIT/project-bin/_common.sh" "$TOOLKIT/project-bin/restore-mpr.sh" "$P/bin/"
cp "$SUBJECT" "$P/bin/exec.sh"
cat > "$P/bin/snapshot-mpr.sh" <<'SNAP'
#!/usr/bin/env bash
set -e
cd "$(dirname "$0")/.."
D=".mpr-snapshots/$(date +%Y%m%d-%H%M%S)-$$-$RANDOM"
mkdir -p "$D"; cp Fixture.mpr "$D/"; cp -r mprcontents "$D/"
echo "Snapshot saved: $D"
SNAP
# The write: `mxcli exec` appends to the model, as a real script would.
cat > "$P/mxcli" <<'MXCLI'
#!/usr/bin/env bash
D="$(cd "$(dirname "$0")" && pwd)"
case "${1:-}" in
  check) exit 0 ;;
  run) sleep 120; exit 0 ;;
  exec) echo "written by the script" >> "$D/Fixture.mpr"; echo "x" >> "$D/mprcontents/a.mxunit"; echo "fake mxcli exec"; exit "${MXCLI_EXEC_RC:-0}" ;;
esac
exit 0
MXCLI
chmod +x "$P/bin/"*.sh "$P/mxcli"
# mxbuild: MXB_MODES per call number, comma list: ok | infra (exit 1, no CE code, no errors file) | err (a CE0001 error list)
# MXB_WATCH_PID: record that process's state (ps stat) at the start of every call
# MXB_OTHER_PIDS: the same for more pids, as `<pid> <stat>` lines in MXB_OTHERS
# hang (mode): record the pid in MXB_HANGPID and sleep, so the test can SIGKILL exec.sh mid-gate
cat > "$WORK/mxbuild" <<'MXB'
#!/usr/bin/env bash
n=$(( $(cat "$MXB_N" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$MXB_N"
mode="$(printf '%s\n' "$MXB_MODES" | tr ',' '\n' | sed -n "${n}p")"; mode="${mode:-ok}"
[ -n "${MXB_WATCH_PID:-}" ] && ps -o stat= -p "$MXB_WATCH_PID" >> "$MXB_STATES"
for q in ${MXB_OTHER_PIDS:-}; do echo "$q $(ps -o stat= -p "$q")" >> "$MXB_OTHERS"; done
err=""; for a in "$@"; do case "$a" in --write-errors=*) err="${a#--write-errors=}" ;; esac; done
case "$mode" in
  ok)    [ -n "$err" ] && printf '{"problems":[]}' > "$err"; exit 0 ;;
  hang)  echo $$ > "$MXB_HANGPID"; exec sleep 60 ;;
  infra) echo "Directory not empty : deployment/web" >&2; exit 1 ;;
  err)   [ -n "$err" ] && printf '{"problems":[{"severity":"Error","code":"CE0001","message":"boom","element":{"document":"M.X"}}]}' > "$err"; exit 1 ;;
  # #448 field shapes (mxbuild exit 3, problems[] empty): a deploy-stage message, in the dict and
  # the plain-string errors[] form, and the deterministic version mismatch (never retried)
  bundle)  printf '{"errors":[{"message":"Compilation of the app bundle failed.","details":""}],"problems":[]}' > "$err"; echo "Compilation of the app bundle failed."; exit 3 ;;
  bundle2) printf '{"problems":[],"errors":["An error occurred while compiling Theme files"]}' > "$err"; exit 3 ;;
  version) printf '{"errors":[{"message":"The MPR file located at /x/App.mpr could not be opened: Project version '"'"'11.12.2'"'"' does not exactly match MxBuild version '"'"'11.14.0'"'"'. Use loose version check option for less strict version checking.","details":""}],"problems":[]}' > "$err"; exit 3 ;;
esac
MXB
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/jdk/bin/java"
chmod +x "$WORK/mxbuild" "$WORK/jdk/bin/java"
( cd "$P" && git init -q . && printf '.mpr-snapshots/\ndocs/\n.claude/\n' > .gitignore && git add -A \
  && git -c user.email=t@t -c user.name=t commit -qm fixture ) >/dev/null 2>&1

LOG="$P/docs/BUILD-LOG.md"
sum() { cat "$P/Fixture.mpr" "$P/mprcontents/a.mxunit" | cksum; }
BEFORE="$(sum)"   # the committed model; run() resets to it
# run <label> <modes> - resets the model, runs the default path, prints the exit code
run() {
  [ -n "${NORESET:-}" ] || ( cd "$P" && git checkout -q -- Fixture.mpr mprcontents && rm -rf .mpr-snapshots docs \
    && { find .claude -mindepth 1 -maxdepth 1 ! -name worktrees -exec rm -rf {} + 2>/dev/null; true; } ) >/dev/null 2>&1
  rm -f "$WORK/n"; mkdir -p "$WORK/tmp"
  ( cd "$P" && TMPDIR="$WORK/tmp" SP_RESTART=0 MXTK_NO_INSTALL=1 MXB_N="$WORK/n" MXB_MODES="$2" \
      MXBUILD_PATH="$WORK/mxbuild" JAVA_HOME="$WORK/jdk" ./bin/exec.sh ${EXEC_ARGS:-mdlsource/test.mdl} ) >"$WORK/out.$1" 2>&1
  echo $?
}
lastrow() { tail -1 "$LOG" 2>/dev/null; }
kept() { grep -q 'written by the script' "$P/Fixture.mpr"; }

cat > "$P/bin/lint-gate.sh" <<'LG'
#!/usr/bin/env bash
if [ "${LINT_MODE:-}" = fault ]; then echo "lint-gate fault"; exit 2; fi
if [ "${LINT_MODE:-}" = rose ]; then printf 'FAIL\n  SEC003     security   9 -> 10   (+1)\n'; exit 1; fi
echo PASS; exit 0
LG
chmod +x "$P/bin/lint-gate.sh"

# res <label> <expected line>: exactly one RESULT line, equal to <expected>, and not the last line
res() {
  _n="$(grep -c '^MXTK-RESULT ' "$WORK/out.$1")"
  _l="$(grep '^MXTK-RESULT ' "$WORK/out.$1")"
  [ "$_n" -eq 1 ] && ok "$1: exactly one RESULT line" || bad "$1: $_n RESULT lines" "$(tail -6 "$WORK/out.$1")"
  [ "$_l" = "$2" ] && ok "$1: $2" || bad "$1: line differs" "got: $_l"
  tail -1 "$WORK/out.$1" | grep -q '^MXTK-RESULT ' && bad "$1: the RESULT line is the LAST line" || ok "$1: not the last line"
}

echo "== A: clean apply =="
RC=$(run A ok,ok)
[ "$RC" -eq 0 ] && kept && ok "exit 0, kept" || bad "A rc=$RC" "$(tail -6 "$WORK/out.A")"
res A "MXTK-RESULT exec verdict=applied applied=yes verified=yes lint_new=0 exit=0"

echo "== B: lint rise: exit 4 =="
RC=$(LINT_MODE=rose run B ok,ok)
[ "$RC" -eq 4 ] && kept && ok "exit 4, kept" || bad "B rc=$RC" "$(tail -6 "$WORK/out.B")"
res B "MXTK-RESULT exec verdict=applied-lint applied=yes verified=yes lint_new=unknown exit=4"
tail -1 "$WORK/out.B" | grep -q '^gate passed, lint only' && ok "B: last line unchanged" || bad "B: last line" "$(tail -1 "$WORK/out.B")"
printf '# Project\n\n- **Lint gate:** `hard`\n' > "$P/PROJECT.md"
RC=$(LINT_MODE=rose run B2 ok,ok)
[ "$RC" -eq 1 ] && kept && ok "hard gate: exit 1, kept" || bad "B2 rc=$RC" "$(tail -6 "$WORK/out.B2")"
res B2 "MXTK-RESULT exec verdict=applied-lint applied=yes verified=yes lint_new=unknown exit=1"
rm -f "$P/PROJECT.md"

echo "== C: bundle-only failure twice: UNVERIFIED, exit 5 =="
RC=$(run C ok,bundle2,bundle2)
[ "$RC" -eq 5 ] && kept && ok "exit 5, kept" || bad "C rc=$RC" "$(tail -6 "$WORK/out.C")"
res C "MXTK-RESULT exec verdict=applied-unverified applied=yes verified=no lint_new=na exit=5"
tail -1 "$WORK/out.C" | grep -q 'UNVERIFIED (exit 5)' && ok "C: last line unchanged" || bad "C: last line" "$(tail -1 "$WORK/out.C")"

echo "== D: the gate finds a new error: restored =="
RC=$(run D ok,err)
[ "$RC" -eq 1 ] && ! kept && ok "exit 1, rolled back" || bad "D rc=$RC" "$(tail -6 "$WORK/out.D")"
res D "MXTK-RESULT exec verdict=restored applied=no verified=no lint_new=na exit=1"

echo "== E: uncommitted model changes: refused =="
echo "dirty" >> "$P/Fixture.mpr"
RC=$(NORESET=1 run E ok,ok)
[ "$RC" -eq 1 ] && ok "exit 1" || bad "E rc=$RC" "$(tail -6 "$WORK/out.E")"
res E "MXTK-RESULT exec verdict=refused applied=no verified=skipped lint_new=na exit=1"

echo "== F: usage error: exit 2, no RESULT line =="
( cd "$P" && git checkout -q -- Fixture.mpr mprcontents && rm -rf .mpr-snapshots docs ) >/dev/null 2>&1
( cd "$P" && TMPDIR="$WORK/tmp" MXTK_NO_INSTALL=1 MXBUILD_PATH="$WORK/mxbuild" JAVA_HOME="$WORK/jdk" ./bin/exec.sh ) >"$WORK/out.F" 2>&1; RC=$?
[ "$RC" -eq 2 ] && ! grep -q '^MXTK-RESULT' "$WORK/out.F" && ok "exit 2, no RESULT line" || bad "F rc=$RC" "$(tail -3 "$WORK/out.F")"

# Patch script: appends to the model like the stub exec; PATCH_RC makes it fail half-way.
cat > "$P/patch.sh" <<'PATCH'
#!/usr/bin/env bash
D="$(dirname "$1")"
echo "written by the script" >> "$1"; echo "x" >> "$D/mprcontents/a.mxunit"
exit "${PATCH_RC:-0}"
PATCH
chmod +x "$P/patch.sh"
GOODRESTORE="$P/bin/restore-mpr.sh.good"; cp "$P/bin/restore-mpr.sh" "$GOODRESTORE"
break_restore() { printf '#!/usr/bin/env bash\necho "restore broke" >&2\nexit 1\n' > "$P/bin/restore-mpr.sh"; }
fix_restore()   { cp "$GOODRESTORE" "$P/bin/restore-mpr.sh"; }

echo "== G: mxcli exec exits non-zero, gate passes: partial =="
RC=$(MXCLI_EXEC_RC=3 run G ok,ok)
[ "$RC" -eq 1 ] && kept && ok "exit 1, partial write kept" || bad "G rc=$RC" "$(tail -6 "$WORK/out.G")"
res G "MXTK-RESULT exec verdict=partial applied=partial verified=yes lint_new=na exit=1"

echo "== H: the gate finds a new error and the restore itself fails: failed =="
break_restore
RC=$(run H ok,err)
[ "$RC" -eq 1 ] && kept && ok "exit 1, model NOT rolled back" || bad "H rc=$RC" "$(tail -6 "$WORK/out.H")"
res H "MXTK-RESULT exec verdict=failed applied=unknown verified=no lint_new=na exit=1"

echo "== I: mxcli exec exits non-zero AND the gate fails AND the restore fails: failed on both paths =="
RC=$(MXCLI_EXEC_RC=3 run I ok,err)
[ "$RC" -eq 1 ] && kept && ok "exit 1, model NOT rolled back" || bad "I rc=$RC" "$(tail -6 "$WORK/out.I")"
res I "MXTK-RESULT exec verdict=failed applied=unknown verified=no lint_new=na exit=1"
fix_restore

echo "== I2: the same, restore works: restored =="
RC=$(MXCLI_EXEC_RC=3 run I2 ok,err)
[ "$RC" -eq 1 ] && ! kept && ok "exit 1, rolled back" || bad "I2 rc=$RC" "$(tail -6 "$WORK/out.I2")"
res I2 "MXTK-RESULT exec verdict=restored applied=no verified=no lint_new=na exit=1"

echo "== J: --patch, clean: applied =="
RC=$(EXEC_ARGS="--patch patch.sh" run J ok,ok)
[ "$RC" -eq 0 ] && kept && ok "exit 0, kept" || bad "J rc=$RC" "$(tail -6 "$WORK/out.J")"
res J "MXTK-RESULT exec verdict=applied applied=yes verified=yes lint_new=0 exit=0"

echo "== K: --patch script fails half-way: restored, gate not run =="
RC=$(PATCH_RC=7 EXEC_ARGS="--patch patch.sh" run K ok,ok)
[ "$RC" -eq 1 ] && ! kept && ok "exit 1, rolled back" || bad "K rc=$RC" "$(tail -6 "$WORK/out.K")"
res K "MXTK-RESULT exec verdict=restored applied=no verified=skipped lint_new=na exit=1"

echo "== K2: --patch script fails half-way and the restore fails: failed =="
break_restore
RC=$(PATCH_RC=7 EXEC_ARGS="--patch patch.sh" run K2 ok,ok)
[ "$RC" -eq 1 ] && kept && ok "exit 1, NOT rolled back" || bad "K2 rc=$RC" "$(tail -6 "$WORK/out.K2")"
res K2 "MXTK-RESULT exec verdict=failed applied=unknown verified=skipped lint_new=na exit=1"
fix_restore

echo "== L: --patch, gate cannot verify (bundle error twice): rolled back =="
RC=$(EXEC_ARGS="--patch patch.sh" run L ok,bundle2,bundle2)
[ "$RC" -eq 1 ] && ! kept && ok "exit 1, rolled back" || bad "L rc=$RC" "$(tail -6 "$WORK/out.L")"
res L "MXTK-RESULT exec verdict=restored applied=no verified=no lint_new=na exit=1"

echo "== M: lint_new words =="
RC=$(SKIP_LINT=1 run M ok,ok)
[ "$RC" -eq 0 ] && kept && ok "exit 0" || bad "M rc=$RC" "$(tail -6 "$WORK/out.M")"
res M "MXTK-RESULT exec verdict=applied applied=yes verified=yes lint_new=skipped exit=0"
mv "$P/bin/lint-gate.sh" "$P/bin/lint-gate.sh.off"
RC=$(run M2 ok,ok)
[ "$RC" -eq 0 ] && kept && ok "exit 0" || bad "M2 rc=$RC" "$(tail -6 "$WORK/out.M2")"
res M2 "MXTK-RESULT exec verdict=applied applied=yes verified=yes lint_new=skipped exit=0"
mv "$P/bin/lint-gate.sh.off" "$P/bin/lint-gate.sh"
RC=$(LINT_MODE=fault run M3 ok,ok)
[ "$RC" -eq 0 ] && kept && ok "exit 0" || bad "M3 rc=$RC" "$(tail -6 "$WORK/out.M3")"
res M3 "MXTK-RESULT exec verdict=applied applied=yes verified=yes lint_new=blind exit=0"

echo ""
echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
