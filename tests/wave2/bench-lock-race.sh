#!/usr/bin/env bash
# bench-lock-race.sh — race harness for the shared lock (_common.sh mxtk_lock_take): rounds of
# contenders start together on a lock whose holder is dead, are SIGKILLed at the lock code's test
# anchors and at random 0–50 ms offsets, and every holder checks for a second live holder.
#
# Usage: bash tests/wave2/bench-lock-race.sh [--rounds N] [--contenders M] [--common <_common.sh>]
#                                            [--old [<file holding the pre-ticket exec.sh lock block>]]
#   default subject: project-bin/_common.sh (the reap-ticket lock)
#   --old: the pre-ticket protocol (`<lock>.takeover`, mv aside, ln back); default file
#          tests/wave2/fixtures/mxtest-guard/exec-lock-block.sh, a verbatim copy of master d16f578's
#          exec.sh block. Anchors are sed-injected at the same points: after its takeover file is
#          created (ticket-taken, compare), before its rm (rm), after its lock is created (created),
#          plus the two steps the new code no longer has: after a takeover file is judged stale
#          (judged) and after it is moved aside, before the compare and `ln` back (aside).
# Exit 0 iff no overlapping holders, every contender that was not killed acquired the lock before
# its deadline, and a probe after each round acquired it within PROBE_SECS. Last line:
#   RESULT subject=<new|old> rounds=R contenders=M overlaps=<events> overlap_rounds=<n> starved=<n> probe_fail=<n> kills=<n> acquired=<n>
#
# Knobs (env): KILL_AT (anchors where a contender may be SIGKILLed, default "ticket-taken compare
# rm"; every anchor also pauses 0–39 ms), KILL_PCT (chance per such anchor, default 25),
# RANDOM_KILL_PCT (chance a contender is also SIGKILLed at a random 0–50 ms offset, default 10),
# HOLD_SECS (default 0.05), RETRY_SECS (pause between attempts, default 0.02), DEADLINE (per
# contender, default 30 s), PROBE_SECS (default 15).
# Two signals, both must stay 0: an OVERLAP (a holder sees another live holder's mark) and a
# STOLEN lock (a live holder finds the lock file no longer names it — someone removed it).
# WHY: r-eng-backlog item 1 (2026-10-14). The harness must show the double holder on the old
# code before its silence on the new code means anything.
set -uo pipefail
TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ROUNDS=200; NC=10; COMMON="$TOOLKIT/project-bin/_common.sh"; OLD=""
while [ $# -gt 0 ]; do
  case "$1" in
    --rounds) shift; ROUNDS="$1" ;;
    --contenders) shift; NC="$1" ;;
    --common) shift; COMMON="$1" ;;
    --old) if [ $# -gt 1 ] && [ -f "$2" ]; then shift; OLD="$1"
           else OLD="$TOOLKIT/tests/wave2/fixtures/mxtest-guard/exec-lock-block.sh"; fi ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done
KILL_PCT="${KILL_PCT:-25}"; RANDOM_KILL_PCT="${RANDOM_KILL_PCT:-10}"; HOLD_SECS="${HOLD_SECS:-0.05}"
DEADLINE="${DEADLINE:-30}"; PROBE_SECS="${PROBE_SECS:-15}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/lockrace.XXXXXX")" || exit 2
WORK="$(cd "$WORK" && pwd -P)"
BG=""
trap 'for p in $BG; do kill -KILL "$p" 2>/dev/null; done; rm -rf "$WORK"' EXIT
LOCK="$WORK/.exec.lock"; HOLD="$WORK/holding"; mkdir -p "$HOLD"

# The implementation under test exposes ctake (0 = holding) and crelease.
if [ -n "$OLD" ]; then
  SUBJECT=old
  { echo 'LOG_NAME="old.mdl"'
    echo '_hk() { [ -z "${MXTK_LOCK_TEST_PAUSE:-}" ] || "$MXTK_LOCK_TEST_PAUSE" "$1" "$$" || true; }'
    echo 'ctake() {'
    grep -v '^#' "$OLD" | sed \
      -e 's/^  _now="\$(head -1 "\$LOCK" 2>\/dev\/null || true)"$/  _hk ticket-taken; _hk compare; &/' \
      -e 's/^  \[ "\$_now" = "\$1" \] && rm -f "\$LOCK"$/  [ "$_now" = "$1" ] \&\& { _hk rm; rm -f "$LOCK"; }/' \
      -e 's/^  if exec_lock_try; then LOCK_TAKEN=1; break; fi$/  if exec_lock_try; then LOCK_TAKEN=1; _hk created; break; fi/' \
      -e 's/^    if \[ "\$_tstale" = 1 \]; then$/    _hk judged; &/' \
      -e 's/^      if mv "\$_tk" "\$_tk.stale.\$\$" 2>\/dev\/null; then$/&  _hk aside;/' \
      -e 's/sleep 1/sleep "$RETRY"/' -e 's/^    exit 1$/    return 1/' -e 's/^  exit 1$/  return 2/'
    echo '}'
    echo 'crelease() { exec_lock_release; }'
  } > "$WORK/impl.sh"
  for a in 'ticket-taken' '_hk rm' '_hk created' '_hk judged' '_hk aside' 'return 1' 'return 2' 'sleep "$RETRY"'; do
    grep -qF -- "$a" "$WORK/impl.sh" || { echo "setup: could not inject '$a' into the old block ($OLD)" >&2; exit 2; }
  done
else
  SUBJECT=new
  { printf 'PROJECT_ROOT=%q; . %q\n' "$WORK" "$COMMON"
    echo 'ctake() { mxtk_lock_take "$LOCK" "contender" 3; }'
    echo 'crelease() { mxtk_lock_release "$LOCK"; }'
  } > "$WORK/impl.sh"
  grep -q '^mxtk_lock_take() {' "$COMMON" || { echo "setup: no mxtk_lock_take in $COMMON" >&2; exit 2; }
fi

# The hook run at each anchor: SIGKILL the contender KILL_PCT% of the time, else pause 0–39 ms.
cat > "$WORK/pause.sh" <<'P'
#!/usr/bin/env bash
case " ${KILL_AT:-$1} " in *" $1 "*) ;; *) KILL_PCT=0 ;; esac
if [ $((RANDOM % 100)) -lt "$KILL_PCT" ]; then echo "$1 $2" >> "$WORK/kills"; kill -KILL "$2"; exit 0; fi
sleep "0.0$((RANDOM % 4))$((RANDOM % 10))"
P
chmod +x "$WORK/pause.sh"

# A contender: its name contains "exec.sh", so the liveness rule (old and new) counts it as a holder.
cat > "$WORK/contender-exec.sh" <<'C'
LOCK="$1"; ROUND="$2"; RETRY="$RETRY_SECS"; MXTK_LOCK_RETRY_SLEEP="$RETRY_SECS"
. "$WORK/impl.sh"
alive() {  # same rule as the lock: alive, not a zombie, one of ours
  kill -0 "$1" 2>/dev/null || return 1
  case "$(sed 's/.*) //' "/proc/$1/stat" 2>/dev/null | cut -d' ' -f1)" in Z) return 1 ;; esac
  case "$(ps -o args= -p "$1" 2>/dev/null || true)" in *contender-exec.sh*) return 0 ;; esac
  return 1
}
check() {
  local m p
  for m in "$HOLD"/*; do
    [ -e "$m" ] || continue; p="${m##*/}"; [ "$p" = "$$" ] && continue
    alive "$p" && echo "round $ROUND: $$ holds while $p holds" >> "$WORK/overlaps"
  done
}
while [ ! -e "$WORK/go.$ROUND" ]; do sleep 0.01; done
end=$(( $(date +%s) + DEADLINE )); got=0
while [ "$(date +%s)" -lt "$end" ]; do
  if ctake >/dev/null 2>&1; then got=1; break; fi
  sleep "0.0$((RANDOM % 5 + 1))"
done
if [ "$got" != 1 ]; then case "$ROUND" in probe*) ;; *) echo "$$" >> "$WORK/starved" ;; esac; exit 1; fi
echo "$$" >> "$WORK/acquired"
mine() {  # the lock must still name us while we hold it; anything else means another took it
  [ "$(head -1 "$LOCK" 2>/dev/null | cut -d' ' -f1)" = "$$" ] || echo "round $ROUND: $$ lost its lock while holding it (now: $(head -1 "$LOCK" 2>/dev/null))" >> "$WORK/stolen"
}
touch "$HOLD/$$"; check; mine; sleep "$HOLD_SECS"; check; mine; rm -f "$HOLD/$$"
crelease
C

dead_pid() { sleep 0 & local p=$!; wait "$p" 2>/dev/null; echo "$p"; }
RETRY_SECS="${RETRY_SECS:-0.02}"; KILL_AT="${KILL_AT:-ticket-taken compare rm}"
export WORK HOLD KILL_PCT HOLD_SECS DEADLINE RETRY_SECS KILL_AT
PROBE_FAIL=0; ROUNDS_WITH_OVERLAP=0
T0=$(date +%s)
for r in $(seq 1 "$ROUNDS"); do
  rm -f "$HOLD"/*
  if [ $((r % 2)) = 1 ]; then printf '%s %s old.mdl\n' "$(dead_pid)" "$(date +%s)" > "$LOCK"   # pre-nonce line
  else printf '%s %s old.mdl nonce=round%s\n' "$(dead_pid)" "$(date +%s)" "$r" > "$LOCK"; fi
  [ -n "$OLD" ] && rm -f "$LOCK.takeover"   # the old harness's own reset; tickets are left as litter
  before="$(cat "$WORK/overlaps" 2>/dev/null | wc -l | tr -d ' ')"
  PIDS=""
  for c in $(seq 1 "$NC"); do
    MXTK_LOCK_TEST_PAUSE="$WORK/pause.sh" bash "$WORK/contender-exec.sh" "$LOCK" "$r" >/dev/null 2>&1 &
    PIDS="$PIDS $!"
  done
  BG="$PIDS"
  : > "$WORK/go.$r"
  for p in $PIDS; do   # random SIGKILLs at 0–50 ms
    if [ $((RANDOM % 100)) -lt "$RANDOM_KILL_PCT" ]; then
      ( sleep "0.0$((RANDOM % 5))$((RANDOM % 10))"; kill -KILL "$p" 2>/dev/null && echo "random $p" >> "$WORK/kills" ) &
    fi
  done
  for p in $PIDS; do wait "$p" 2>/dev/null; done
  wait 2>/dev/null
  after="$(cat "$WORK/overlaps" 2>/dev/null | wc -l | tr -d ' ')"
  [ "$after" -gt "$before" ] && ROUNDS_WITH_OVERLAP=$((ROUNDS_WITH_OVERLAP + 1))
  # Probe: no hooks, no kills — whatever the round left (a dead holder, dead tickets), it gets the lock.
  rm -f "$HOLD"/*
  ( cd "$WORK" && : > "$WORK/go.probe$r"; DEADLINE="$PROBE_SECS" bash "$WORK/contender-exec.sh" "$LOCK" "probe$r" ) >/dev/null 2>&1 \
    || { PROBE_FAIL=$((PROBE_FAIL + 1)); echo "  round $r: probe could not take the lock within ${PROBE_SECS}s ($(head -1 "$LOCK" 2>/dev/null))"; }
done
T1=$(date +%s)
OV="$(cat "$WORK/overlaps" 2>/dev/null | wc -l | tr -d ' ')"
ST="$(cat "$WORK/starved" 2>/dev/null | wc -l | tr -d ' ')"
KL="$(cat "$WORK/kills" 2>/dev/null | wc -l | tr -d ' ')"
AQ="$(cat "$WORK/acquired" 2>/dev/null | wc -l | tr -d ' ')"
SL="$(cat "$WORK/stolen" 2>/dev/null | wc -l | tr -d ' ')"
[ "$OV" -gt 0 ] && { echo "  first overlaps:"; head -5 "$WORK/overlaps" | sed 's/^/    /'; }
[ "$SL" -gt 0 ] && { echo "  first locks lost by a live holder:"; head -5 "$WORK/stolen" | sed 's/^/    /'; }
LITTER="$(ls -a "$WORK" | grep -c '^\.exec\.lock\.' || true)"
echo "  $((T1 - T0)) s; lock-side files left at the end: $LITTER"
echo "RESULT subject=$SUBJECT rounds=$ROUNDS contenders=$NC overlaps=$OV overlap_rounds=$ROUNDS_WITH_OVERLAP stolen=$SL starved=$ST probe_fail=$PROBE_FAIL kills=$KL acquired=$AQ"
[ "$OV" -eq 0 ] && [ "$SL" -eq 0 ] && [ "$ST" -eq 0 ] && [ "$PROBE_FAIL" -eq 0 ]
