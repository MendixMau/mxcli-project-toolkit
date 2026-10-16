#!/usr/bin/env bash
# test-exec-gate-log.sh - exec.sh keeps the gate's full mxbuild output when the gate does not
# end clean.
#
# usage: bash tests/wave2/test-exec-gate-log.sh [path-to-exec.sh]
#
# Field (a migration project, 12 modules, 2026-10-16/17): exec.sh printed `head -20` of mxbuild's
# output and deleted the rest with its temp file, so the detail of a failed gate (a CE1613 among
# them) was lost. Now the full output goes to .mpr-snapshots/mxbuild-logs/<run>.log; the screen
# shows the top lines plus the log path, and the BUILD-LOG row names the log.
#
#   A  mxbuild fails with a long output: the log holds the whole output (including the tail the
#      screen cut off), the screen names the path, the row names the path [guard: survives rollback]
#   B  a clean run writes no log and the row has no log note [guard]
#   C  only the newest 30 logs are kept
#
# Synthetic only: throwaway git repo, stub mxcli, stub mxbuild, stub java. Nothing real runs.
set -uo pipefail

TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUBJECT="${1:-$TOOLKIT/project-bin/exec.sh}"
case "$SUBJECT" in /*) ;; *) SUBJECT="$PWD/$SUBJECT" ;; esac
WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/exec-gatelog.XXXXXX")" && pwd -P)" || exit 2
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
  exec) echo "written by the script" >> "$D/Fixture.mpr"; echo "x" >> "$D/mprcontents/a.mxunit"; echo "fake mxcli exec"; exit 0 ;;
esac
exit 0
MXCLI
chmod +x "$P/bin/"*.sh "$P/mxcli"
# mxbuild: MXB_MODES per call number, comma list: ok | long (exit 137, 40 lines of output, no errors file)
cat > "$WORK/mxbuild" <<'MXB'
#!/usr/bin/env bash
n=$(( $(cat "$MXB_N" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$MXB_N"
mode="$(printf '%s\n' "$MXB_MODES" | tr ',' '\n' | sed -n "${n}p")"; mode="${mode:-ok}"
err=""; for a in "$@"; do case "$a" in --write-errors=*) err="${a#--write-errors=}" ;; esac; done
case "$mode" in
  ok)    [ -n "$err" ] && printf '{"problems":[]}' > "$err"; exit 0 ;;
  long)  i=1; while [ "$i" -le 40 ]; do echo "mxbuild output line $i"; i=$((i+1)); done; echo "TAIL-MARKER the real failure detail"; exit 137 ;;
  err)   [ -n "$err" ] && printf '{"problems":[{"severity":"Error","code":"CE0001","message":"boom","element":{"document":"M.X"}}]}' > "$err"; exit 1 ;;
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
  ( cd "$P" && git checkout -q -- Fixture.mpr mprcontents && rm -rf $([ -n "${KEEP_SNAP:-}" ] || echo .mpr-snapshots) docs .claude ) >/dev/null 2>&1
  rm -f "$WORK/n"; mkdir -p "$WORK/tmp"
  ( cd "$P" && TMPDIR="$WORK/tmp" SP_RESTART=0 MXTK_NO_INSTALL=1 MXB_N="$WORK/n" MXB_MODES="$2" \
      MXBUILD_PATH="$WORK/mxbuild" JAVA_HOME="$WORK/jdk" ./bin/exec.sh mdlsource/test.mdl ) >"$WORK/out.$1" 2>&1
  echo $?
}
lastrow() { tail -1 "$LOG" 2>/dev/null; }
kept() { grep -q 'written by the script' "$P/Fixture.mpr"; }

echo "== A: baseline ok, mxbuild fails with a long output: full log kept =="
RC=$(run A ok,long)
LOGF="$(ls "$P"/.mpr-snapshots/mxbuild-logs/*.log 2>/dev/null | head -1)"
[ -n "$LOGF" ] && ok "a per-run log exists under .mpr-snapshots/mxbuild-logs/" || bad "A: no log" "$(ls -R "$P/.mpr-snapshots" 2>&1 | tail -5)"
grep -q 'TAIL-MARKER' "$LOGF" 2>/dev/null && grep -q 'mxbuild output line 1$' "$LOGF" && ok "log holds the whole output, tail included" || bad "A: log content" "$(tail -3 "$LOGF" 2>/dev/null)"
grep -q 'TAIL-MARKER' "$WORK/out.A" && bad "A: the screen printed the tail (not truncated)" || ok "screen still shows only the top lines"
grep -q "full mxbuild output: .mpr-snapshots/mxbuild-logs/" "$WORK/out.A" && ok "screen names the log path" || bad "A: no path on screen" "$(tail -12 "$WORK/out.A")"
lastrow | grep -q 'mxbuild log: .mpr-snapshots/mxbuild-logs/' && ok "BUILD-LOG row names the log" || bad "A: row" "$(lastrow)"
kept && bad "A: write kept" || ok "rollback still applies and the log survived it"

echo "== B: clean run: no log, no note [guard] =="
RC=$(run B ok,ok)
[ "$RC" -eq 0 ] && kept && ok "exit 0, write kept" || bad "B rc=$RC" "$(tail -8 "$WORK/out.B")"
[ -z "$(ls "$P"/.mpr-snapshots/mxbuild-logs/*.log 2>/dev/null)" ] && ok "no log on a clean gate" || bad "B: a log was written"
lastrow | grep -q 'mxbuild log' && bad "B: row mentions a log" || ok "row has no log note"

echo "== C: only the newest 30 logs are kept =="
( cd "$P" && git checkout -q -- Fixture.mpr mprcontents && rm -rf .mpr-snapshots docs .claude ) >/dev/null 2>&1
mkdir -p "$P/.mpr-snapshots/mxbuild-logs"
i=1; while [ "$i" -le 35 ]; do : > "$P/.mpr-snapshots/mxbuild-logs/20200101-0000$(printf %02d "$i")-$i.log"; i=$((i+1)); done
RC=$(KEEP_SNAP=1 run C ok,long)
N="$(ls "$P"/.mpr-snapshots/mxbuild-logs/*.log 2>/dev/null | wc -l | tr -d ' ')"
[ "$N" -eq 30 ] && ok "35 old + 1 new pruned to 30" || bad "C: $N logs"
[ -f "$P/.mpr-snapshots/mxbuild-logs/20200101-000001-1.log" ] && bad "C: the oldest log survived" || ok "the oldest are the ones removed"

echo ""
echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
