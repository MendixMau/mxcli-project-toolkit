#!/usr/bin/env bash
# test-scratch.sh — run `mxcli test` on a scratch COPY of the model, under a lock on the test ports.
#
#   ./bin/test-scratch.sh [--keep] [--ports "8081 8091"] -- <mxcli test args, without -p>
#   e.g. ./bin/test-scratch.sh -- tests/unit/Orders.test.mdl --local
#
# Exit: mxcli's own exit code · 2 usage, or bin/_common.sh older than this script · 3 refused (nothing copied or run)
#
# WHY (#278, field run 2026-10-12; testing-shape.md § "mxcli test --local does NOT leave a warm
# run --local app alone"). `mxcli test` injects a TestRunner, sets security off, builds into
# <app dir>/deployment and restores — all in the LIVE project. One unlocked run in the live repo
# broke the running app (NoClassDefFoundError) with the .mpr unchanged; the remedy that worked was
# a scratch copy of the project plus a lock around the fixed test ports, and it lived only in that
# run's private helper. This is that helper:
#   1. takes this project's exec lock (.mpr-snapshots/.exec.lock, the same file and format as
#      exec.sh) for the COPY only, so the copy is never a half-written model — a live exec.sh
#      refuses this, a dead holder is taken over;
#   2. copies the model tree to a scratch dir, leaving out .git, .mpr-snapshots, deployment and
#      .mxcli (the last holds the LIVE app's run --local record; a copy carrying it would point
#      app-restart.sh and test-stack-up.sh at the live app);
#   3. takes a MACHINE-wide lock on the test ports (they are machine-global: two test runs on one
#      machine collide on 8081/8091 whatever project they belong to), refusing while another live
#      holder has it and taking over a dead one;
#   4. runs `mxcli test <args> -p <scratch>.mpr` in the scratch dir, then releases both and deletes
#      the copy (--keep leaves it, and says where).
# Refused (exit 3, nothing copied) when the live model's after-startup is still an mxcli test injection
# (MxTest.RegisterEndpoint / MxTest.TestRunner, left by a run stopped by a signal — #244, BUG-157):
# the copy would carry it and the test runtime would recurse in its after-startup. The repair is printed.
# --attach is refused: it hot-applies into the live app and runs against its database, which is
# the opposite of a scratch run. Never touches the live model, the live app, or Studio Pro.
# Bash 3.2 / Git Bash / macOS / Linux; no flock (absent on macOS and Git Bash).
set -uo pipefail
. "$(dirname "$0")/_common.sh"

KEEP=0; PORTS="${MXTK_TEST_PORTS:-8081 8091}"
while [ $# -gt 0 ]; do
  case "$1" in
    --keep)  KEEP=1 ;;
    --ports) shift; PORTS="${1:-}" ;;
    --)      shift; break ;;
    -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
    *) break ;;
  esac
  shift
done
[ $# -gt 0 ] || { echo "usage: $0 [--keep] [--ports \"8081 8091\"] -- <mxcli test args>" >&2; exit 2; }
for _a in "$@"; do
  case "$_a" in
    --attach) echo "✗ test-scratch: --attach runs against the LIVE app and its database — not a scratch run. Use mxcli test --attach directly, deliberately, and restart the app after (testing-shape.md)." >&2; exit 3 ;;
    -p|--project|-p=*|--project=*) echo "✗ test-scratch: do not pass -p; the scratch copy's .mpr is passed for you." >&2; exit 2 ;;
  esac
done

MPR="$(find_mpr)" || exit 2
MODEL_DIR="$(find_model_dir 2>/dev/null || dirname "$MPR")"
MPR_NAME="$(basename "$MPR")"
[ -f "$MODEL_DIR/$MPR_NAME" ] || MODEL_DIR="$(cd "$(dirname "$MPR")" && pwd)"
if [ -x "$PROJECT_ROOT/mxcli" ]; then MXCLI="$PROJECT_ROOT/mxcli"
elif [ -x "$MODEL_DIR/mxcli" ]; then MXCLI="$MODEL_DIR/mxcli"
elif command -v mxcli >/dev/null 2>&1; then MXCLI="$(command -v mxcli)"
else echo "✗ test-scratch: no mxcli (project root or PATH)." >&2; exit 3; fi

# ── After-startup left on an mxcli test injection (#244, BUG-157) ───────────
# The reader and the refusal (mxtest_after_startup / mxtest_left / mxtest_refusal) live in
# _common.sh, shared with app-restart.sh. A project whose bin/_common.sh predates them stops here
# with the remedy, instead of dying on "command not found" — or, worse, reading the failed call as
# "no injection left" and copying a model that recurses in its after-startup.
command -v mxtest_left >/dev/null 2>&1 && command -v mxtest_refusal >/dev/null 2>&1 || {
  echo "test-scratch: bin/_common.sh is older than this script (no mxtest_left / mxtest_refusal)." >&2
  echo "  → <toolkit>/bin/sync-project.sh $PROJECT_ROOT --only-bin _common.sh --upgrade-bin _common.sh   (installs just that file; backs up a hand-edited copy first)" >&2; exit 2; }

# A model whose after-startup is an mxcli test injection must not be copied and tested: the copy
# carries it, and mxcli test then chains the injection to itself (#244 observation 1).
if mxtest_left "$MODEL_DIR" "$MODEL_DIR/$MPR_NAME"; then
  mxtest_refusal "test-scratch"
  echo "  Nothing was copied or run." >&2
  exit 3
fi

# Same liveness rule as exec.sh's lock: alive, not a zombie, and (where ps can say) one of ours.
holder_live() {
  [ -n "${1:-}" ] || return 1
  case "$1" in *[!0-9]*) return 1 ;; esac
  kill -0 "$1" 2>/dev/null || return 1
  case "$(sed 's/.*) //' "/proc/$1/stat" 2>/dev/null | cut -d' ' -f1)" in Z) return 1 ;; esac
  _args="$(ps -o args= -p "$1" 2>/dev/null || true)"
  case "$_args" in ""|*exec.sh*|*test-scratch.sh*) return 0 ;; esac
  return 1
}
# Taking over a stale lock is serialised through a second O_EXCL file, <lock>.takeover — the SAME
# file name and protocol as exec.sh's exec_lock_takeover (this script shares .exec.lock with it, so
# the two must exclude each other; keep the bodies in step). Under it the lock is re-read and
# removed ONLY if it still holds exactly the stale line judged; nothing else ever removes a lock
# that is not its own. WHY (independent review of #304): the old takeover here moved the lock
# aside with `mv -f` — check-then-act — so two runs that judged the same dead holder could both
# end up holding it. A takeover file left by a holder killed mid-takeover is stale once its pid is
# dead or it is older than 10 s (an EMPTY one once it is over a minute old: find -mmin +1); it is moved aside, and put
# back with `ln` (fails if a new one exists — never clobbers) if what was moved is not the one
# judged stale. The machine-wide port lock uses the same protocol.
take_over() {  # $1 = lock file, $2 = the stale lock line. 0 iff it was removed (or already gone)
  local _tk="$1.takeover" _t _tpid _tsince _tstale _now _mine
  _mine="$$ $(date +%s)"
  if ! ( set -o noclobber; printf '%s\n' "$_mine" > "$_tk" ) 2>/dev/null; then
    _t="$(head -1 "$_tk" 2>/dev/null || true)"; _tpid="${_t%% *}"; _tsince="${_t#* }"
    case "$_tsince" in ''|*[!0-9]*) _tsince=0 ;; esac
    _tstale=0
    if [ -n "$_t" ]; then
      { ! kill -0 "$_tpid" 2>/dev/null || [ $(( $(date +%s) - _tsince )) -gt 10 ]; } && _tstale=1
    elif [ -n "$(find "$_tk" -mmin +1 2>/dev/null)" ]; then
      # -mmin +1, not +0: GNU find counts a 0-2 s old file as "+0" (and BSD rounds up), so +0 made a
      # FRESH empty takeover file — its creator between the create and the write — stale at once.
      _tstale=1   # empty for over a minute: its creator died between the create and the write
    fi
    if [ "$_tstale" = 1 ]; then
      if mv "$_tk" "$_tk.stale.$$" 2>/dev/null; then
        # Remove what was moved ONLY if it is what was judged stale; anything else is someone's
        # live takeover file: put it back (ln never clobbers), and if that fails leave it be.
        if [ "$(head -1 "$_tk.stale.$$" 2>/dev/null || true)" = "$_t" ]; then rm -f "$_tk.stale.$$"
        else ln "$_tk.stale.$$" "$_tk" 2>/dev/null && rm -f "$_tk.stale.$$"; fi
      fi
    fi
    return 1
  fi
  _now="$(head -1 "$1" 2>/dev/null || true)"
  [ "$_now" = "$2" ] && rm -f "$1"
  [ "$(head -1 "$_tk" 2>/dev/null || true)" = "$_mine" ] && rm -f "$_tk"   # only our own takeover file
  return 0
}
take_lock() {  # $1 = lock file, $2 = what it guards (for messages). 0 = taken, 1 = live holder
  local f="$1" held hpid i
  for i in 1 2 3 4 5 6 7 8; do
    if ( set -o noclobber; printf '%s %s %s\n' "$$" "$(date +%s)" "test-scratch.sh" > "$f" ) 2>/dev/null; then return 0; fi
    held="$(head -1 "$f" 2>/dev/null || true)"
    if [ -z "$held" ] && [ "$i" -lt 3 ]; then sleep 1; continue; fi
    hpid="${held%% *}"
    if holder_live "$hpid"; then
      echo "✗ test-scratch: $2 is held by PID $hpid ($(printf '%s' "$held" | cut -d' ' -f3-)) — wait for it to finish." >&2
      return 1
    fi
    if take_over "$f" "$held"; then
      echo "  (stale lock on $2 from PID ${hpid:-?}, not running — taking it over)"
    else
      sleep 1   # another run is taking the same stale lock over; see who won
    fi
  done
  echo "✗ test-scratch: could not take the lock on $2 after 8 attempts." >&2; return 1
}
release() { local f="$1" own; own="$(head -1 "$f" 2>/dev/null || true)"; [ "${own%% *}" = "$$" ] && rm -f "$f"; return 0; }

EXEC_LOCK="$PROJECT_ROOT/.mpr-snapshots/.exec.lock"
PORT_LOCK="${TMPDIR:-/tmp}/mxtk-test-ports-$(printf '%s' "$PORTS" | tr -c '0-9' '-').lock"
SCRATCH=""
cleanup() {
  release "$EXEC_LOCK"; release "$PORT_LOCK"
  if [ -n "$SCRATCH" ] && [ -d "$SCRATCH" ]; then
    if [ "$KEEP" = 1 ]; then echo "  scratch copy kept: $SCRATCH"; else rm -rf "$SCRATCH"; fi
  fi
}
trap cleanup EXIT

# 1+3. Port lock first (machine-wide, cheap to fail), then the project lock for the copy.
take_lock "$PORT_LOCK" "test ports $PORTS" || exit 3
for _p in $PORTS; do
  if curl -s -o /dev/null --max-time 2 "http://localhost:$_p/" 2>/dev/null; then
    echo "✗ test-scratch: :$_p already answers — another test runtime (or app) is up there. Not starting a second." >&2
    exit 3
  fi
done
mkdir -p "$(dirname "$EXEC_LOCK")"
take_lock "$EXEC_LOCK" "this project's model (an exec.sh is writing it)" || exit 3

# 2. The copy.
SCRATCH="$(mktemp -d "${MXTK_SCRATCH_DIR:-${TMPDIR:-/tmp}}/$(basename "$MPR_NAME" .mpr)-test.XXXXXX")" || exit 3
echo "→ test-scratch: copying $(basename "$MODEL_DIR")/ → $SCRATCH (no .git, .mpr-snapshots, deployment, .mxcli)"
if ! tar -C "$MODEL_DIR" --exclude=./.git --exclude=./.mpr-snapshots --exclude=./deployment \
       --exclude=./.mxcli --exclude=./node_modules -cf - . | tar -C "$SCRATCH" -xf -; then
  echo "✗ test-scratch: copy failed." >&2; exit 3
fi
release "$EXEC_LOCK"
[ -f "$SCRATCH/$MPR_NAME" ] || { echo "✗ test-scratch: $MPR_NAME missing from the copy." >&2; exit 3; }

# 4. Run.
echo "→ $(basename "$MXCLI") test $* -p $SCRATCH/$MPR_NAME   (ports $PORTS locked)"
( cd "$SCRATCH" && "$MXCLI" test "$@" -p "$SCRATCH/$MPR_NAME" )
RC=$?
echo "← mxcli test exit $RC — the live model and the live app were not touched."
exit "$RC"
