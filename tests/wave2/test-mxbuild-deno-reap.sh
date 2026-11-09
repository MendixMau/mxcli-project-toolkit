#!/usr/bin/env bash
# test-mxbuild-deno-reap.sh — project-bin/_common.sh stops the deno helper a toolkit-started
# mxbuild leaves behind, and only that one (#708).
#
#   usage: bash tests/wave2/test-mxbuild-deno-reap.sh project-bin/_common.sh
#
# Field origin (pipeline-mode experiment for #700, 2026-11-06, 16 GB container): every mxbuild
# left a modeler/tools/deno/<platform>/deno (WebExtensionsRunner, ~290 MB, parent PID 1) running
# for good; 47 of them held 13 GB and every later build was OOM-killed (exit 137).
#
# The stub mxbuild here starts a fake "deno" — a copy of this machine's `sleep` binary placed at
# modeler/tools/deno/<platform>/deno, so its process name IS deno — and exits, leaving it running
# the way the real one does. Cases:
#   R1  mxtk_mxbuild_error_count (the exec gate, its baseline and backstop, doctor's self-test):
#       the stub's deno is gone after the call; a deno this fixture started itself BEFORE the call,
#       and one it started WHILE the stub was running, are both still alive (a before/after pid
#       diff would have killed the second).
#   R2  mxtk_reaped (verify-model.sh, the pre-push hook, module-close, reload, doctor's probe):
#       same, and the command's exit code comes back unchanged.
#   R3  exit 137: the gate prints "build killed for lack of memory: N orphaned deno processes hold
#       X GB — run bin/doctor.sh --cleanup", and MXTK_MXBUILD_WHY (BUILD-LOG's reason) carries it.
# On master all three FAIL: nothing reaps (R1, R2) and exit 137 is unexplained (R3).
#
# Only processes this fixture started are ever signalled, by recorded pid; nothing on the machine
# is matched by name. Linux and macOS; skipped on Git Bash, where the reap is skipped by design.
set -u

COMMON="${1:?usage: $0 project-bin/_common.sh}"
COMMON="$(cd "$(dirname "$COMMON")" && pwd)/$(basename "$COMMON")"
case "${OSTYPE:-}" in msys*|cygwin*|win*) echo "SKIP: Git Bash (the reap is skipped there by design)"; exit 0 ;; esac
command -v ps >/dev/null 2>&1 || { echo "SKIP: no ps"; exit 0; }
SLEEP_BIN="$(command -v sleep)"; [ -x "$SLEEP_BIN" ] || { echo "SKIP: no sleep binary"; exit 0; }

T="$(mktemp -d "${TMPDIR:-/tmp}/mxtk-deno-reap.XXXXXX")"
# At exit: stop each fake deno this fixture started, by its recorded pid, and only while that pid
# is still a process named deno (a dead pid can be reused by an unrelated process).
cleanup() {
  local f p c
  for f in "$T"/*.pid; do
    [ -f "$f" ] || continue; p="$(cat "$f" 2>/dev/null)"; [ -n "$p" ] || continue
    c="$(ps -o comm= -p "$p" 2>/dev/null)"; case "${c##*/}" in deno) kill "$p" 2>/dev/null ;; esac
  done
  rm -rf "$T"
}
trap cleanup EXIT
PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ok    $*"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL  $*"; }

# alive <pid> — running and not a zombie
alive() { local s; s="$(ps -o stat= -p "$1" 2>/dev/null)"; [ -n "$s" ] && case "$s" in Z*) return 1 ;; esac; }
# gone_within <pid> — gone (or a zombie) within ~3 s; a TERM is not instant
gone_within() { local i=0; while alive "$1"; do [ "$i" -ge 30 ] && return 1; sleep 0.1; i=$((i + 1)); done; return 0; }

DENO_DIR="$T/mx/modeler/tools/deno/linux-x64"; mkdir -p "$DENO_DIR"
cp "$SLEEP_BIN" "$DENO_DIR/deno"; chmod +x "$DENO_DIR/deno"
FOREIGN_DIR="$T/other/modeler/tools/deno/linux-x64"; mkdir -p "$FOREIGN_DIR"
cp "$SLEEP_BIN" "$FOREIGN_DIR/deno"; chmod +x "$FOREIGN_DIR/deno"
mkdir -p "$T/jdk/bin"; printf '#!/bin/sh\nexit 0\n' > "$T/jdk/bin/java"; chmod +x "$T/jdk/bin/java"
# The stub: start the helper (stdout inherited, as the real one does), optionally linger, exit.
cat > "$T/mx/modeler/mxbuild" <<'MXB'
#!/usr/bin/env bash
"$FAKE_DENO" 600 < /dev/null &
echo $! > "$DENO_PIDFILE"
[ -z "${STUB_LINGER:-}" ] || sleep "$STUB_LINGER"
echo "stub mxbuild done"
exit "${STUB_RC:-0}"
MXB
chmod +x "$T/mx/modeler/mxbuild"
mkdir -p "$T/proj"; : > "$T/proj/App.mpr"

run_in() {  # run_in <extra env, may be empty> <body>
  env -i PATH="$PATH" HOME="$T" PROJECT_ROOT="$T/proj" JAVA_HOME="$T/jdk" MXBUILD_PATH="$T/mx/modeler/mxbuild" \
    FAKE_DENO="$DENO_DIR/deno" ${1:+$1} bash -c "set -u; source '$COMMON'; $2"
}
start_foreign() {  # start_foreign <pidfile> — a deno this fixture owns, outside any build
  "$FOREIGN_DIR/deno" 600 < /dev/null > /dev/null 2>&1 &
  echo $! > "$1"
}

# ── R1: the gate's runner ────────────────────────────────────────────────────
echo "== R1: mxtk_mxbuild_error_count reaps its own deno, leaves foreign ones =="
start_foreign "$T/f-before.pid"
# A foreign deno that appears WHILE the build runs (another session, Studio Pro):
( sleep 0.5; start_foreign "$T/f-during.pid" ) &
DURING_SH=$!
OUT=$(run_in "DENO_PIDFILE=$T/r1.pid STUB_LINGER=1.5" "mxtk_mxbuild_error_count '$T/proj/App.mpr' 0" 2>&1)
OWN="$(cat "$T/r1.pid" 2>/dev/null)"; FB="$(cat "$T/f-before.pid")"; FD="$(cat "$T/f-during.pid" 2>/dev/null)"
[ "$OUT" = "0" ] || fail "R1: count '$OUT' (expected 0 from a clean stub)"
if [ -n "$OWN" ] && gone_within "$OWN"; then ok "R1: the build's own deno (pid $OWN) was stopped"
else fail "R1: the build's own deno (pid ${OWN:-?}) is still running after the call"; fi
alive "$FB" && ok "R1: a deno started before the build is untouched" || fail "R1: the foreign deno started before the build was killed"
[ -n "$FD" ] && alive "$FD" && ok "R1: a deno started during the build is untouched" || fail "R1: the foreign deno started during the build was killed (or never started)"

# ── R2: the foreground wrapper ───────────────────────────────────────────────
echo "== R2: mxtk_reaped reaps its own deno and passes the exit code through =="
OUT=$(run_in "DENO_PIDFILE=$T/r2.pid STUB_RC=3" "mxtk_reaped '$T/mx/modeler/mxbuild' --target=deploy x > '$T/r2.out' 2>&1 < /dev/null; echo rc=\$?" 2>&1)
OWN="$(cat "$T/r2.pid" 2>/dev/null)"
[ "$OUT" = "rc=3" ] && ok "R2: exit code 3 passed through" || fail "R2: got '$OUT', expected rc=3"
if [ -n "$OWN" ] && gone_within "$OWN"; then ok "R2: the command's own deno (pid $OWN) was stopped"
else fail "R2: the command's own deno (pid ${OWN:-?}) is still running after mxtk_reaped"; fi
alive "$FB" && ok "R2: the foreign deno is still untouched" || fail "R2: the foreign deno was killed"

# ── R3: exit 137 is named ───────────────────────────────────────────────────
echo "== R3: an OOM-killed gate says so, with the orphan count =="
# One real orphan the message can count: parent gone, as after a killed mxbuild.
( "$DENO_DIR/deno" 600 < /dev/null > /dev/null 2>&1 & echo $! > "$T/orphan.pid" )
ERR=$(run_in "DENO_PIDFILE=$T/r3.pid STUB_RC=137" "mxtk_mxbuild_error_count '$T/proj/App.mpr' 0 >/dev/null; printf 'WHY=%s\n' \"\$MXTK_MXBUILD_WHY\"" 2>&1)
case "$ERR" in
  *"build killed for lack of memory: "[1-9]*" orphaned deno processes hold "*" GB — run bin/doctor.sh --cleanup"*) ok "R3: the plain OOM message is printed, with a non-zero orphan count" ;;
  *) fail "R3: no OOM message on exit 137; got: $(printf '%s' "$ERR" | head -3)" ;;
esac
case "$ERR" in *"WHY=build killed for lack of memory"*) ok "R3: MXTK_MXBUILD_WHY carries it (BUILD-LOG names the cause)" ;;
  *) fail "R3: MXTK_MXBUILD_WHY does not name the memory kill" ;; esac
OWN="$(cat "$T/r3.pid" 2>/dev/null)"
[ -n "$OWN" ] && gone_within "$OWN" && ok "[guard] R3: the killed build's deno was stopped too" || fail "R3: the killed build's deno (pid ${OWN:-?}) is still running"

wait "$DURING_SH" 2>/dev/null
echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
