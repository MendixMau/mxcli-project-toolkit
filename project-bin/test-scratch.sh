#!/usr/bin/env bash
# test-scratch.sh — run `mxcli test` on a scratch COPY of the model, under a lock on the test ports.
#
#   ./bin/test-scratch.sh [--keep] [--ports "8081 8091"] -- <mxcli test args, without -p>
#   e.g. ./bin/test-scratch.sh -- tests/unit/Orders.test.mdl --local
#
# Exit: mxcli's own exit code · 2 usage · 3 refused (nothing copied or run)
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
# `mxcli test` and `mxcli run --test-endpoint` point the model's after-startup microflow at
# MxTest.RegisterEndpoint (MxTest.TestRunner for a plain test run) and chain the original; only a
# clean exit puts it back. A run stopped by a signal leaves it, and the next injection then chains
# RegisterEndpoint to itself: StackOverflowError in the after-startup, the runtime never starts.
# Read straight from the model bytes — no mxcli, no running app: the setting is the BSON string
# element 0x02 "AfterStartupMicroflow" 0x00 of the project-settings unit (mprcontents/**/*.mxunit;
# inside the .mpr itself on a v1 model). Layout checked against real settings units (mxcli's own
# test models). A unit or .mpr without the bytes "MxTest." anywhere is not scanned at all (an 8 MB
# v1 .mpr costs a grep, not an 8 s od). MXTK_SKIP_MXTEST_GUARD=1 skips the check, out loud.
mxtest_after_startup() (  # $1 = file, or - for stdin. Prints the value ('' = none); 1 = no such element
  # A subshell with pipefail OFF: awk exits at the first match and od then dies of SIGPIPE; under
  # the caller's pipefail that 141 would hide the answer and switch the guard off on a large .mpr.
  set +o pipefail
  { if [ "$1" = - ]; then od -An -v -tx1; else od -An -v -tx1 "$1"; fi; } 2>/dev/null | awk '
    BEGIN { for (i = 0; i < 256; i++) hv[sprintf("%02x", i)] = i
            for (i = 32; i < 127; i++) { c = sprintf("%c", i); ch[sprintf("%02x", i)] = c; hx[c] = sprintf("%02x", i) }
            s = "AfterStartupMicroflow"; T = length(s) + 2; t[1] = "02"; t[T] = "00"
            for (i = 1; i <= length(s); i++) t[i + 1] = hx[substr(s, i, 1)]
            k = 0; st = 0; found = 0 }
    { for (f = 1; f <= NF; f++) { b = $f
        if (st == 0) { if (b == t[k + 1]) k++; else k = (b == t[1]) ? 1 : 0
                       if (k == T) { st = 1; L = 0; m = 1; n = 0; v = "" } }
        else if (st == 1) { L += hv[b] * m; m *= 256
                            if (++n == 4) { if (L < 1 || L > 1024) { st = 0; k = 0 } else if (L == 1) { found = 1; exit } else { st = 2; n = 0 } } }
        else { if (++n < L) v = v ((b in ch) ? ch[b] : "?"); else { found = 1; exit } } } }
    END { if (!found) exit 1; print v }'
)
MXTEST_LEFT=""; MXTEST_UNIT=""; MXTEST_HEAD=""
mxtest_left() {  # $1 = model dir, $2 = .mpr. 0 = after-startup is an mxcli test injection (sets MXTEST_*)
  local unit val cands
  MXTEST_LEFT=""; MXTEST_UNIT=""; MXTEST_HEAD=""
  if [ "${MXTK_SKIP_MXTEST_GUARD:-0}" = 1 ]; then
    echo "  ! MXTK_SKIP_MXTEST_GUARD=1 — NOT checking for a leftover mxcli test after-startup (#244). If the app" >&2
    echo "    then dies with StackOverflowError in MxTest.RegisterEndpoint, that is what this check was for." >&2
    return 1
  fi
  if [ -d "$1/mprcontents" ]; then
    cands="$(LC_ALL=C grep -rla --include='*.mxunit' 'AfterStartupMicroflow' "$1/mprcontents" 2>/dev/null)"
  else cands="$2"; fi
  # Every unit holding the text, not the first: a doc string elsewhere can mention the setting by
  # name. Only the BSON element counts, and only a unit that contains "MxTest." can hold the value.
  while IFS= read -r unit; do
    [ -n "$unit" ] && [ -f "$unit" ] || continue
    LC_ALL=C grep -qa 'MxTest\.' "$unit" 2>/dev/null || continue
    val="$(mxtest_after_startup "$unit")" || continue
    case "$val" in MxTest.RegisterEndpoint|MxTest.TestRunner) ;; *) continue ;; esac
    MXTEST_LEFT="$val"; MXTEST_UNIT="$unit"
    case "$unit" in *.mxunit)   # what HEAD has, so the repair can name it; "?" = not tracked / no git
      MXTEST_HEAD="$(git -C "$(dirname "$unit")" show "HEAD:./$(basename "$unit")" 2>/dev/null | mxtest_after_startup -)" || MXTEST_HEAD="?" ;;
    *) MXTEST_HEAD="?" ;; esac
    return 0
  done <<CANDS
$cands
CANDS
  return 1
}
mxtest_refusal() {  # $1 = tool name. Prints the refusal and the repair to stderr.
  local was="$MXTEST_HEAD" rel="${MXTEST_UNIT#"$PROJECT_ROOT"/}"
  echo "✗ $1: this model's after-startup microflow is $MXTEST_LEFT — left behind by an mxcli test or" >&2
  echo "  run --test-endpoint that did not exit cleanly (stopped by a signal or killed; BUG-157)," >&2
  echo "  or held right now by a live run --test-endpoint of this project." >&2
  echo "  Starting on it recurses (the next injection chains $MXTEST_LEFT to itself: StackOverflowError)," >&2
  echo "  or fails the build with CE1613 if the MxTest module is already gone. Either way the app never starts." >&2
  echo "  set in: $rel" >&2
  case "$was" in '?') was="<your own after-startup microflow, or '' for none>"
                      echo "  HEAD: not readable (no git, or the unit is untracked)" >&2 ;;
                 '')  echo "  HEAD: no after-startup microflow" >&2 ;;
                 *)   echo "  HEAD: $was" >&2 ;; esac
  if [ "$1" = test-scratch ]; then
    echo "  → If this project's app runs with --test-endpoint right now (skills/cloud-dev-environment.md), the" >&2
    echo "    live model is fine as it is — test a copy whose settings unit comes from HEAD instead (#244's" >&2
    echo "    workaround): git worktree add <dir> HEAD, copy the units under test into it, run mxcli test there" >&2
    echo "    on free ports. Or stop the live app with Ctrl+C in its own terminal (a clean stop restores it)." >&2
  else
    echo "  → If this project's app is running with --test-endpoint right now, this is its live injection:" >&2
    echo "    stop it with Ctrl+C in its own terminal (a clean stop restores the setting), then retry." >&2
  fi
  echo "  → Otherwise restore it, then retry:" >&2
  echo "      git checkout -- '$rel'      (then git status: the run may have left an MxTest module too)" >&2
  echo "    or through ./bin/exec.sh (an ALTER SETTINGS — say so in chat; it is what mxcli's own cleanup runs):" >&2
  echo "      mdl 1;" >&2
  echo "      alter settings runtime (AfterStartupMicroflow: '$was');" >&2
  echo "    or Studio Pro: App Settings → Runtime → After startup." >&2
  echo "  A false refusal? MXTK_SKIP_MXTEST_GUARD=1 skips this check (and says so)." >&2
}

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

# _common.sh carries the copy routine (mxtk_copy_model_tree, shared with exec.sh --on-copy). A
# hand-edited, older _common.sh that sync-project.sh held back does not have it.
if ! type mxtk_copy_model_tree >/dev/null 2>&1; then
  echo "✗ test-scratch: bin/_common.sh predates mxtk_copy_model_tree. Update it: <toolkit>/bin/sync-project.sh <project-root>" >&2
  echo "  (a locally edited _common.sh is held back by sync: --upgrade-bin _common.sh). Nothing was copied or run." >&2
  exit 3
fi

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

# 2. The copy. Refused over an interrupted exec.sh --on-copy promotion (its leftovers beside the
#    model; between its two renames there is no mprcontents/ to copy) — #384 review.
if type mxtk_promote_leftovers >/dev/null 2>&1 && _left="$(mxtk_promote_leftovers "$MODEL_DIR")"; then
  echo "✗ test-scratch: an exec.sh --on-copy promotion (PID $_left) was interrupted; the model may be half-swapped." >&2
  echo "  → ./bin/exec.sh --recover-promote, then re-run. Nothing was copied or run." >&2
  exit 3
fi
SCRATCH="$(mktemp -d "${MXTK_SCRATCH_DIR:-${TMPDIR:-/tmp}}/$(basename "$MPR_NAME" .mpr)-test.XXXXXX")" || exit 3
echo "→ test-scratch: copying $(basename "$MODEL_DIR")/ → $SCRATCH (no .git, .mpr-snapshots, deployment, .mxcli)"
if ! mxtk_copy_model_tree "$MODEL_DIR" "$SCRATCH"; then
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
