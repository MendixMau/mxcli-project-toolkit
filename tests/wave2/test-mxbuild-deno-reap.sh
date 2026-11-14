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
#   R4  mxtk_reaped puts the caller's own INT/TERM traps back (it used to reset them).
#   R5  Ctrl-C (INT to the whole foreground group) during mxtk_reaped, BASHPID unset as on bash
#       3.2: the build and its deno stop, and the caller's own INT trap runs (it no longer carries on).
# On master R1-R3 FAIL: nothing reaps (R1, R2) and exit 137 is unexplained (R3); R4 and R5 FAIL on
# the first version of this PR (R4: trap reset to default; R5: no INT reached the build's group).
#
# Only processes this fixture started are ever signalled, by recorded pid; nothing on the machine
# is matched by name. Linux and macOS; skipped on Git Bash, where the reap is skipped by design.
set -u

COMMON="${1:?usage: $0 project-bin/_common.sh}"
COMMON="$(cd "$(dirname "$COMMON")" && pwd)/$(basename "$COMMON")"
case "${OSTYPE:-}" in msys*|cygwin*|win*) echo "SKIP: Git Bash (the reap is skipped there by design)"; exit 0 ;; esac
command -v ps >/dev/null 2>&1 || { echo "SKIP: no ps"; exit 0; }
[ -x "$(command -v sleep)" ] || { echo "SKIP: no sleep binary"; exit 0; }
. "$(dirname "$0")/fake-proc.sh"

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
fake_proc_init "$T"
PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ok    $*"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL  $*"; }

# alive <pid> — running and not a zombie
alive() { local s; s="$(ps -o stat= -p "$1" 2>/dev/null)"; [ -n "$s" ] && case "$s" in Z*) return 1 ;; esac; }
# gone_within <pid> — gone (or a zombie) within ~3 s; a TERM is not instant
gone_within() { local i=0; while alive "$1"; do [ "$i" -ge 30 ] && return 1; sleep 0.1; i=$((i + 1)); done; return 0; }

DENO_DIR="$T/mx/modeler/tools/deno/linux-x64"; mkdir -p "$DENO_DIR"
fake_proc_make "$DENO_DIR/deno"
FOREIGN_DIR="$T/other/modeler/tools/deno/linux-x64"; mkdir -p "$FOREIGN_DIR"
fake_proc_make "$FOREIGN_DIR/deno"
mkdir -p "$T/jdk/bin"; printf '#!/bin/sh\nexit 0\n' > "$T/jdk/bin/java"; chmod +x "$T/jdk/bin/java"
# The stub: start the helper (stdout inherited, as the real one does), optionally linger, exit.
cat > "$T/mx/modeler/mxbuild" <<'MXB'
#!/usr/bin/env bash
"$FAKE_DENO" ${FAKE_PRE:-} 600 < /dev/null &
echo $! > "$DENO_PIDFILE"
[ -z "${STUB_LINGER:-}" ] || sleep "$STUB_LINGER"
echo "stub mxbuild done"
exit "${STUB_RC:-0}"
MXB
chmod +x "$T/mx/modeler/mxbuild"
mkdir -p "$T/proj"; : > "$T/proj/App.mpr"

run_in() {  # run_in <extra env, may be empty> <body>
  env -i PATH="$PATH" HOME="$T" PROJECT_ROOT="$T/proj" JAVA_HOME="$T/jdk" MXBUILD_PATH="$T/mx/modeler/mxbuild" \
    FAKE_DENO="$DENO_DIR/deno" FAKE_PRE="$FAKE_PRE" ${1:+$1} bash -c "set -u; source '$COMMON'; $2"
}
start_foreign() {  # start_foreign <pidfile> — a deno this fixture owns, outside any build
  "$FOREIGN_DIR/deno" ${FAKE_PRE:-} 600 < /dev/null > /dev/null 2>&1 &
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
( "$DENO_DIR/deno" ${FAKE_PRE:-} 600 < /dev/null > /dev/null 2>&1 & echo $! > "$T/orphan.pid" )
ERR=$(run_in "DENO_PIDFILE=$T/r3.pid STUB_RC=137" "mxtk_mxbuild_error_count '$T/proj/App.mpr' 0 >/dev/null; printf 'WHY=%s\n' \"\$MXTK_MXBUILD_WHY\"" 2>&1)
case "$ERR" in
  *"build killed for lack of memory: "[1-9]*" orphaned deno processes hold "*" GB — run bin/doctor.sh --cleanup"*) ok "R3: the plain OOM message is printed, with a non-zero orphan count" ;;
  *) fail "R3: no OOM message on exit 137; got: $(printf '%s' "$ERR" | head -3)" ;;
esac
case "$ERR" in *"WHY=build killed for lack of memory"*) ok "R3: MXTK_MXBUILD_WHY carries it (BUILD-LOG names the cause)" ;;
  *) fail "R3: MXTK_MXBUILD_WHY does not name the memory kill" ;; esac
OWN="$(cat "$T/r3.pid" 2>/dev/null)"
[ -n "$OWN" ] && gone_within "$OWN" && ok "[guard] R3: the killed build's deno was stopped too" || fail "R3: the killed build's deno (pid ${OWN:-?}) is still running"

# ── R4: the caller's own INT/TERM traps survive ─────────────────────────────
echo "== R4: mxtk_reaped leaves the caller's INT/TERM traps as they were =="
OUT=$(run_in "DENO_PIDFILE=$T/r4.pid" "trap 'echo caller-int' INT; trap 'echo caller-term' TERM
mxtk_reaped '$T/mx/modeler/mxbuild' > /dev/null 2>&1 < /dev/null; trap -p INT TERM" 2>&1)
case "$OUT" in *"echo caller-int"*"SIGINT"*) ok "R4: the caller's INT trap is still set" ;; *) fail "R4: caller's INT trap lost; trap -p now: $(printf '%s' "$OUT" | tr '\n' ' ')" ;; esac
case "$OUT" in *"echo caller-term"*"SIGTERM"*) ok "R4: the caller's TERM trap is still set" ;; *) fail "R4: caller's TERM trap lost" ;; esac

# ── R5: Ctrl-C (INT to the foreground group) during mxtk_reaped ─────────────
# The script runs in a process group of its own, standing in for a terminal's foreground group;
# INT goes to that whole group, as Ctrl-C does. BASHPID is unset as on bash 3.2.
echo "== R5: Ctrl-C during mxtk_reaped: the build and its deno stop, the caller's own INT trap runs =="
cat > "$T/r5.sh" <<R5
unset BASHPID
. '$COMMON'
trap 'echo caller-int-trap-ran > "$T/r5.trap"; exit 7' INT
mxtk_reaped '$T/mx/modeler/mxbuild' > /dev/null 2>&1 < /dev/null
echo caller-carried-on
R5
set -m
env -i PATH="$PATH" HOME="$T" PROJECT_ROOT="$T/proj" FAKE_DENO="$DENO_DIR/deno" FAKE_PRE="$FAKE_PRE" DENO_PIDFILE="$T/r5.pid" STUB_LINGER=30 \
  bash "$T/r5.sh" > "$T/r5.out" 2>&1 &
G=$!
set +m
i=0; while [ ! -s "$T/r5.pid" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
# Only this fixture's stub, by its full path (another mxbuild may well be running on this machine).
STUB_PID="$(ps -A -o pid=,pgid=,args= | awk -v g="$G" -v stub="$T/mx/modeler/mxbuild" '$2 != g && index($0, stub) && $0 !~ /awk/ { print $1; exit }')"
kill -INT -- "-$G" 2>/dev/null
wait "$G"; R5RC=$?
OUT="$(cat "$T/r5.out" "$T/r5.trap" 2>/dev/null)"   # the trap writes a file: it runs inside mxtk_reaped's > /dev/null
case "$OUT" in *caller-int-trap-ran*) ok "R5: the caller's own INT trap ran" ;; *) fail "R5: caller's INT trap did not run: $(printf '%s' "$OUT" | tr '\n' ' ')" ;; esac
[ "$R5RC" = 7 ] && ok "R5: the caller exited with its trap's code (7)" || fail "R5: caller exit $R5RC, expected 7"
case "$OUT" in *caller-carried-on*) fail "R5: the caller carried on past Ctrl-C" ;; esac
OWN="$(cat "$T/r5.pid" 2>/dev/null)"
[ -n "$OWN" ] && gone_within "$OWN" && ok "R5: the interrupted build's deno was stopped" || fail "R5: the interrupted build's deno (pid ${OWN:-?}) is still running"
if [ -n "$STUB_PID" ]; then gone_within "$STUB_PID" && ok "R5: the interrupted mxbuild itself was stopped" || fail "R5: the interrupted mxbuild (pid $STUB_PID) is still running"
else fail "R5: could not see the stub mxbuild in its own group while it ran"; fi

wait "$DURING_SH" 2>/dev/null
echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
