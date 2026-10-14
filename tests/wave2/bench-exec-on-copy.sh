#!/usr/bin/env bash
# bench-exec-on-copy.sh — before/after measurement for exec.sh --on-copy (#350).
#
# Usage: bash tests/wave2/bench-exec-on-copy.sh [path-to-exec.sh]
#   BENCH_MXB_SECS=2          stub mxbuild duration per run (an INPUT, not a measurement: real
#                             mxbuild took 22-65 s per apply in the field, iterative-build-loop.md)
#   BENCH_SIZES="500 5000 20000"   synthetic mprcontents/ file counts
#   BENCH_RUNS=3              clean runs per path per size (the median is reported)
#   BENCH_FAIL_RUNS=10        failure-injection runs per path, per failure kind, per size
#   BENCH_UNIT_BYTES=1024     bytes per synthetic unit
#
# What it measures, per size, default path vs --on-copy, with the real exec.sh, snapshot-mpr.sh,
# restore-mpr.sh and _common.sh and stub mxcli/mxbuild (no real model, mxcli or mxbuild):
#   broken window  how long the live model holds an unverified write. A poller cksums the live
#                  .mpr + mprcontents/ in a loop. Default: from the first poll that sees the write
#                  to the stub mxbuild's end (clean) or to the first poll back at the original
#                  (failed gate, restored). On-copy: polls that saw a state that is neither the
#                  original nor the promoted one, and exec.sh's own swap timer.
#   overhead       on-copy copy + swap (exec.sh's timers) and the wall-clock delta of a whole run.
#   failure share  runs whose live model is byte-identical after a failed exec: (a) the gate
#                  reports a new error, (b) exec.sh is SIGKILLed while mxbuild runs (a crash, a
#                  closed terminal, Ctrl-C twice).
# Prints a markdown table, one row per size as it completes. Needs GNU date (%N) for millisecond timing. Takes minutes, not seconds.
set -uo pipefail

TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUBJECT="${1:-$TOOLKIT/project-bin/exec.sh}"
case "$SUBJECT" in /*) ;; *) SUBJECT="$PWD/$SUBJECT" ;; esac
MXB_SECS="${BENCH_MXB_SECS:-2}"
SIZES="${BENCH_SIZES:-500 5000 20000}"
RUNS="${BENCH_RUNS:-3}"
FRUNS="${BENCH_FAIL_RUNS:-10}"
UBYTES="${BENCH_UNIT_BYTES:-1024}"
case "$(date +%N)" in *[!0-9]*|'') echo "bench-exec-on-copy: needs GNU date (%N) for ms timing" >&2; exit 2 ;; esac
ms() { echo $(( $(date +%s%N) / 1000000 )); }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/benchcopy.XXXXXX")" || exit 2
export GIT_CEILING_DIRECTORIES="$WORK"   # no git repo: exec.sh's uncommitted-model guard stays quiet
POLLER=""
cleanup() { [ -n "$POLLER" ] && kill "$POLLER" 2>/dev/null; pkill -f "$WORK/" 2>/dev/null; rm -rf "$WORK"; }
trap cleanup EXIT

mkdir -p "$WORK/jdk/bin" "$WORK/stubs"
printf '#!/bin/sh\nexit 0\n' > "$WORK/jdk/bin/java"; chmod +x "$WORK/jdk/bin/java"
cat > "$WORK/stubs/mxbuild" <<'MXB'
#!/usr/bin/env bash
ef=""; for a in "$@"; do case "$a" in --write-errors=*) ef="${a#--write-errors=}" ;; esac; done
echo "$$" > "$STUB_LOG/mxbuild.pid"
echo "start $(( $(date +%s%N) / 1000000 ))" >> "$STUB_LOG/mxbuild.times"
sleep "$BENCH_MXB_SECS"
echo "end $(( $(date +%s%N) / 1000000 ))" >> "$STUB_LOG/mxbuild.times"
if [ "${STUB_MXB_ERR:-0}" = 1 ] && [ ! -f "$STUB_LOG/mxbuild.erred" ]; then
  : > "$STUB_LOG/mxbuild.erred"   # only the gate fails; the attribution rebuild on the restored model is clean
  printf '{"problems":[{"severity":"Error","errorCode":"CE0117","message":"Error(s) in expression.","locations":[{"module":"M","document":"D","element":"E"}]}]}' > "$ef"
  exit 1
fi
printf '{"problems":[]}' > "$ef"; exit 0
MXB
chmod +x "$WORK/stubs/mxbuild"

mktemplate() {  # $1 = dir, $2 = unit count
  local T="$1" n="$2" i d pad
  mkdir -p "$T/bin" "$T/mdlsource" "$T/javasource/m"
  pad="$(head -c "$UBYTES" /dev/zero | tr '\0' 'x')"
  printf 'model index\n%s\n' "$pad" > "$T/Bench.mpr"
  i=0
  while [ "$i" -lt "$n" ]; do
    d="$T/mprcontents/$(printf '%02x' $((i % 256)))/$(printf '%02x' $(((i / 256) % 256)))"
    [ -d "$d" ] || mkdir -p "$d"
    printf 'unit %d\n%s\n' "$i" "$pad" > "$d/u$i.mxunit"
    i=$((i + 1))
  done
  printf 'class Old {}\n' > "$T/javasource/m/Old.java"
  printf 'CREATE MODULE "Bench";\n' > "$T/mdlsource/b.mdl"
  cp "$TOOLKIT/project-bin/_common.sh" "$TOOLKIT/project-bin/restore-mpr.sh" "$TOOLKIT/project-bin/snapshot-mpr.sh" "$T/bin/"
  cp "$SUBJECT" "$T/bin/exec.sh"
  # mxcli exec: rewrites the .mpr and 10 units of whatever model -p names (a typical small script).
  cat > "$T/mxcli" <<'MXCLI'
#!/usr/bin/env bash
[ "${1:-}" = exec ] || exit 0
m=""; while [ $# -gt 0 ]; do [ "$1" = -p ] && m="$2"; shift; done
d="$(dirname "$m")"
echo "exec-start $(( $(date +%s%N) / 1000000 ))" >> "$STUB_LOG/exec.times"
echo "changed $$" >> "$m"
for u in $(find "$d/mprcontents" -name '*.mxunit' | head -10); do echo "changed" >> "$u"; done
exit 0
MXCLI
  chmod +x "$T/bin/"*.sh "$T/mxcli"
}
live_fp() {  # $1 = project: cksum of the live .mpr + every mprcontents file
  ( cd "$1" && { cksum Bench.mpr; find mprcontents -type f | LC_ALL=C sort | tr '\n' '\0' | xargs -0 cksum; } ) 2>/dev/null | cksum | cut -d' ' -f1
}
start_poller() {  # $1 = project, $2 = out file. Polls until killed.
  ( while :; do printf '%s %s\n' "$(ms)" "$(live_fp "$1")" >> "$2"; done ) &
  POLLER=$!
}
stop_poller() { [ -n "$POLLER" ] && { kill "$POLLER" 2>/dev/null; wait "$POLLER" 2>/dev/null; }; POLLER=""; }
run_exec() {  # $1 = project, $2 = log dir, rest = exec.sh args; prints exec.sh output
  local P="$1" L="$2"; shift 2
  ( cd "$P" && STUB_LOG="$L" BENCH_MXB_SECS="$MXB_SECS" JAVA_HOME="$WORK/jdk" SKIP_BASELINE=1 SP_RESTART=0 \
      MXTK_NO_INSTALL=1 MXTK_NO_SCORE=1 SKIP_DOCTOR=1 MXBUILD_PATH="$WORK/stubs/mxbuild" ./bin/exec.sh "$@" ) 2>&1
}
median() { sort -n | awk '{a[NR]=$1} END { if (NR == 0) print "-"; else print a[int((NR + 1) / 2)] }'; }

# One clean or gate-failing run with the poller. Prints "<window_ms> <mixed_polls> <polls> <wall_ms> <copy_ms> <swap_ms> <poll_period_ms>"
measure() {  # $1 = template, $2 = mode default|copy, $3 = STUB_MXB_ERR
  local P="$WORK/run" L="$WORK/log" PF="$WORK/poll" S0 SF OUT t0 t1 first win mixed n per cms sms flag=""
  rm -rf "$P" "$L" "$PF"; cp -R "$1" "$P"; mkdir -p "$L"
  [ "$2" = copy ] && flag="--on-copy"
  S0="$(live_fp "$P")"
  start_poller "$P" "$PF"; sleep 0.3
  t0=$(ms); OUT="$(STUB_MXB_ERR="$3" run_exec "$P" "$L" $flag mdlsource/b.mdl)"; t1=$(ms)
  sleep 0.3; stop_poller
  SF="$(live_fp "$P")"
  n=$(wc -l < "$PF" | tr -d ' ')
  per=$(awk 'NR==1{f=$1} {l=$1} END{ if (NR>1) printf "%d", (l-f)/(NR-1); else print 0 }' "$PF")
  mend=$(awk '$1=="end"{print $2; exit}' "$L/mxbuild.times" 2>/dev/null)
  if [ "$2" = default ]; then
    first=$(awk -v s="$S0" '$2!=s{print $1; exit}' "$PF")
    if [ "$3" = 1 ]; then  # window ends when the live model is back at the original
      win=$(awk -v s="$S0" -v f="${first:-0}" '$1>f && $2==s {print $1 - f; exit}' "$PF")
    else
      win=$(( ${mend:-0} - ${first:-0} ))
    fi
    mixed=0
  else
    win=$(printf '%s\n' "$OUT" | sed -n 's/.*promoted by rename in \([0-9]*\) ms.*/\1/p' | head -1)
    [ -n "$win" ] || win=0
    mixed=$(awk -v s="$S0" -v f="$SF" '$2!=s && $2!=f' "$PF" | wc -l | tr -d ' ')
  fi
  cms=$(printf '%s\n' "$OUT" | sed -n 's/.*model copied in \([0-9]*\) ms.*/\1/p' | head -1)
  sms=$(printf '%s\n' "$OUT" | sed -n 's/.*promoted by rename in \([0-9]*\) ms.*/\1/p' | head -1)
  echo "${win:-?} $mixed $n $((t1 - t0)) ${cms:-0} ${sms:-0} $per"
}
# Failure injection: prints 1 if the live model is byte-identical afterwards, else 0.
inject() {  # $1 = template, $2 = mode, $3 = gate|kill
  local P="$WORK/run" L="$WORK/log" S0 flag="" pid i
  rm -rf "$P" "$L"; cp -R "$1" "$P"; mkdir -p "$L"
  [ "$2" = copy ] && flag="--on-copy"
  S0="$(live_fp "$P")"
  if [ "$3" = gate ]; then
    STUB_MXB_ERR=1 run_exec "$P" "$L" $flag mdlsource/b.mdl >/dev/null
  else
    ( cd "$P" && exec env STUB_LOG="$L" BENCH_MXB_SECS="$MXB_SECS" JAVA_HOME="$WORK/jdk" SKIP_BASELINE=1 SP_RESTART=0 \
        MXTK_NO_INSTALL=1 MXTK_NO_SCORE=1 SKIP_DOCTOR=1 MXBUILD_PATH="$WORK/stubs/mxbuild" ./bin/exec.sh $flag mdlsource/b.mdl ) >/dev/null 2>&1 &
    pid=$!
    for i in $(seq 1 600); do [ -s "$L/mxbuild.pid" ] && break; sleep 0.05; done
    kill -KILL "$pid" 2>/dev/null; kill -KILL "$(cat "$L/mxbuild.pid" 2>/dev/null)" 2>/dev/null
    wait "$pid" 2>/dev/null
  fi
  [ "$(live_fp "$P")" = "$S0" ] && echo 1 || echo 0
}

echo "bench-exec-on-copy: subject $SUBJECT"
echo "stub mxbuild ${MXB_SECS}s per run (input) · $RUNS clean runs per path (median) · $FRUNS failure runs per path per kind · ${UBYTES}-byte units"
echo ""
echo "| units | broken window, default (ms) | broken window, on-copy (ms) | mixed-state polls on-copy | poll period (ms) | copy (ms) | swap (ms) | wall default → on-copy (ms) | gate-fail: live identical default / on-copy | killed mid-gate: live identical default / on-copy |
|---:|---:|---:|---:|---:|---:|---:|---:|---|---|"
for N in $SIZES; do
  T="$WORK/tpl-$N"; rm -rf "$T"; mktemplate "$T" "$N"
  echo "-- $N units: clean runs" >&2
  : > "$WORK/d"; : > "$WORK/c"
  for r in $(seq 1 "$RUNS"); do measure "$T" default 0 >> "$WORK/d"; measure "$T" copy 0 >> "$WORK/c"; done
  echo "-- $N units: gate-failure window" >&2
  DF="$(measure "$T" default 1)"
  DWIN=$(cut -d' ' -f1 "$WORK/d" | median); CWIN=$(cut -d' ' -f1 "$WORK/c" | median)
  MIX=$(awk '{m+=$2; n+=$3} END {printf "%d of %d", m, n}' "$WORK/c")
  PER=$(cut -d' ' -f7 "$WORK/c" | median)
  CPY=$(cut -d' ' -f5 "$WORK/c" | median); SWP=$(cut -d' ' -f6 "$WORK/c" | median)
  WD=$(cut -d' ' -f4 "$WORK/d" | median); WC=$(cut -d' ' -f4 "$WORK/c" | median)
  echo "-- $N units: failure injection" >&2
  GD=0; GC=0; KD=0; KC=0
  for r in $(seq 1 "$FRUNS"); do
    GD=$((GD + $(inject "$T" default gate))); GC=$((GC + $(inject "$T" copy gate)))
    KD=$((KD + $(inject "$T" default kill))); KC=$((KC + $(inject "$T" copy kill)))
  done
  echo "| $N | $DWIN clean · $(echo "$DF" | cut -d' ' -f1) failed gate | $CWIN | $MIX | $PER | $CPY | $SWP | $WD → $WC (+$((WC - WD))) | $GD/$FRUNS / $GC/$FRUNS | $KD/$FRUNS / $KC/$FRUNS |"
  rm -rf "$T"
done
