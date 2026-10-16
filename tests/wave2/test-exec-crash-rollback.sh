#!/usr/bin/env bash
# test-exec-crash-rollback.sh — exec.sh on the DEFAULT path (no --patch, no --on-copy) when
# mxbuild crashes on the written model.
#
# usage: bash tests/wave2/test-exec-crash-rollback.sh [path-to-exec.sh]
#
# Field (2026-10-13, Mendix 11.14.0): a script passed `mxcli check`, mxbuild's loader then died
# with no errors file. exec.sh kept the write; the next exec printed "Baseline NOT measured" and
# built on a model nothing could load. Now: when mxbuild ran on the model BEFORE the write (the
# baseline is known) and exits non-zero with no error list AFTER it, the write is rolled back.
#
#   A  normal success: the write is kept, "applied" row [guard]
#   B  baseline ok, then mxbuild crashes (exit 137, no errors file): model byte-identical to
#      before, one "rolled back" row, nothing left half-applied
#   C  mxbuild crashes on the baseline too (baseline not measured): it may be the machine, so
#      the old behaviour stays, the write is kept and flagged [guard]
#   D  a clean error list after the write (an ordinary gate failure): still the normal
#      gate-failed rollback, not the crash row [guard]
#
# Synthetic only: throwaway git repo, stub mxcli, stub mxbuild, stub java. Nothing real runs.
set -uo pipefail

TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUBJECT="${1:-$TOOLKIT/project-bin/exec.sh}"
case "$SUBJECT" in /*) ;; *) SUBJECT="$PWD/$SUBJECT" ;; esac
WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/exec-crash.XXXXXX")" && pwd -P)" || exit 2
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1${2:+: $2}"; }
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
# mxbuild: MXB_MODE per call number, comma list: ok | crash (exit 137, no errors file) | err (a CE0001 error list)
cat > "$WORK/mxbuild" <<'MXB'
#!/usr/bin/env bash
n=$(( $(cat "$MXB_N" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$MXB_N"
mode="$(printf '%s\n' "$MXB_MODES" | tr ',' '\n' | sed -n "${n}p")"; mode="${mode:-ok}"
err=""; for a in "$@"; do case "$a" in --write-errors=*) err="${a#--write-errors=}" ;; esac; done
case "$mode" in
  ok)    [ -n "$err" ] && printf '{"problems":[]}' > "$err"; exit 0 ;;
  crash) echo "Unhandled exception: loader died" >&2; exit 137 ;;
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
# run <label> <modes> — resets the model, runs the default path, prints the exit code
run() {
  ( cd "$P" && git checkout -q -- Fixture.mpr mprcontents && rm -rf .mpr-snapshots docs .claude ) >/dev/null 2>&1
  rm -f "$WORK/n"; mkdir -p "$WORK/tmp"
  ( cd "$P" && TMPDIR="$WORK/tmp" SP_RESTART=0 MXTK_NO_INSTALL=1 MXB_N="$WORK/n" MXB_MODES="$2" \
      MXBUILD_PATH="$WORK/mxbuild" JAVA_HOME="$WORK/jdk" ./bin/exec.sh mdlsource/test.mdl ) >"$WORK/out.$1" 2>&1
  echo $?
}
lastrow() { tail -1 "$LOG" 2>/dev/null; }
kept() { grep -q 'written by the script' "$P/Fixture.mpr"; }

echo "== A: baseline ok, gate ok: kept, applied row [guard] =="
RC=$(run A ok,ok)
[ "$RC" -eq 0 ] && kept && ok "exit 0, write kept" || bad "A rc=$RC" "$(tail -8 "$WORK/out.A")"
lastrow | grep -q 'applied' && ok "applied row" || bad "A row" "$(lastrow)"
grep -q 'rolling the write back' "$WORK/out.A" && bad "A: rollback message on a clean run" || ok "no rollback message"

echo "== B: baseline ok, mxbuild crashes after the write: rolled back =="
RC=$(run B ok,crash)
kept && bad "B: the write was KEPT after a crash" || ok "write rolled back"
[ "$(sum)" = "$BEFORE" ] && ok "model identical to before the exec" || bad "B: model differs from before"
grep -q 'rolling the write back' "$WORK/out.B" && ok "says it is rolling back" || bad "B: no message" "$(tail -10 "$WORK/out.B")"
[ "$(grep -c 'gate could not run' "$LOG")" -eq 1 ] && lastrow | grep -q 'mxbuild exit 137 on the written model.*script rolled back' \
  && ok "one BUILD-LOG row, says rolled back with the exit code" || bad "B: row" "$(cat "$LOG" 2>/dev/null | tail -3)"

echo "== C: baseline crashes too (not measured): old behaviour, kept and flagged [guard] =="
RC=$(run C crash,crash)
kept && ok "write kept (machine may be the cause)" || bad "C: rolled back without a measured baseline"
grep -q 'Snapshot preserved' "$WORK/out.C" && ok "old message" || bad "C: message" "$(tail -8 "$WORK/out.C")"
lastrow | grep -q 'gate could not run | mxbuild exit 137 ·' && ok "old row, no rollback claim" || bad "C: row" "$(lastrow)"

echo "== D: a clean error list after the write: the ordinary gate-failed path [guard] =="
RC=$(run D ok,err)
kept && bad "D: a new error was KEPT" || ok "rolled back by the normal gate"
lastrow | grep -q 'gate failed' && ok "gate failed row, not the crash row" || bad "D: row" "$(lastrow)"
grep -q 'rolling the write back' "$WORK/out.D" && bad "D: took the crash branch" || ok "crash branch not taken"

echo ""
echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
