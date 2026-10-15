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
  echo "  → <toolkit>/bin/sync-project.sh $PROJECT_ROOT --upgrade-bin _common.sh   (backs up a hand-edited copy first)" >&2; exit 2; }

# A model whose after-startup is an mxcli test injection must not be copied and tested: the copy
# carries it, and mxcli test then chains the injection to itself (#244 observation 1).
if mxtest_left "$MODEL_DIR" "$MODEL_DIR/$MPR_NAME"; then
  mxtest_refusal "test-scratch"
  echo "  Nothing was copied or run." >&2
  exit 3
fi

# Both locks are _common.sh's mxtk_lock_take / mxtk_lock_release — the same code exec.sh uses on
# .exec.lock, so the two scripts exclude each other by construction. A dead holder is reaped
# under a ticket, never by age (see the block header in _common.sh).
command -v mxtk_lock_take >/dev/null 2>&1 || {
  echo "test-scratch: bin/_common.sh is older than this script (no mxtk_lock_take)." >&2
  echo "  → <toolkit>/bin/sync-project.sh $PROJECT_ROOT --upgrade-bin _common.sh   (backs up a hand-edited copy first)" >&2; exit 2; }
take_lock() {  # $1 = lock file, $2 = what it guards (for messages). 0 = taken, 1 = live holder
  local rc=0
  mxtk_lock_take "$1" "test-scratch.sh" 8 || rc=$?
  case "$rc" in
    0) [ -z "$MXTK_LOCK_REAPED" ] || echo "  (stale lock on $2 from PID ${MXTK_LOCK_REAPED%% *}, not running — taking it over)"
       return 0 ;;
    1) mxtk_lock_fields "$MXTK_LOCK_HELD"
       echo "✗ test-scratch: $2 is held by PID $MXTK_LOCK_HPID ($MXTK_LOCK_HLABEL) — wait for it to finish." >&2
       return 1 ;;
  esac
  echo "✗ test-scratch: could not take the lock on $2 after 8 attempts." >&2
  mxtk_lock_blocked_text >&2; return 1
}
release() { mxtk_lock_release "$1"; }

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
