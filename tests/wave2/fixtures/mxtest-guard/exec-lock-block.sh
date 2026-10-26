# exec-lock-block.sh — VERBATIM copy of project-bin/exec.sh's lock block (exec_lock_live .. the
# LOCK_TAKEN check) as on master d16f578 (first from PR #324 @ 79de404): the pre-ticket protocol.
# The OLD code for tests/wave2/bench-lock-race.sh --old (which must reproduce its double holder) and
# for test-lock-reap.sh's mixed-version case. Do not edit by hand.
exec_lock_live() {  # $1 = pid from the lock; 0 iff that process is alive and plausibly exec.sh
  [ -n "$1" ] || return 1
  case "$1" in *[!0-9]*) return 1 ;; esac
  kill -0 "$1" 2>/dev/null || return 1
  # Linux: an unreaped zombie still answers kill -0; /proc/<pid>/stat says Z after the "(comm) ".
  case "$(sed 's/.*) //' "/proc/$1/stat" 2>/dev/null | cut -d' ' -f1)" in Z) return 1 ;; esac
  _args="$(ps -o args= -p "$1" 2>/dev/null || true)"
  case "$_args" in ""|*exec.sh*|*test-scratch.sh*) return 0 ;; esac   # test-scratch.sh holds it while copying
  return 1
}
exec_lock_try() { ( set -o noclobber; printf '%s %s %s\n' "$$" "$(date +%s)" "$LOG_NAME" > "$LOCK" ) 2>/dev/null; }
exec_lock_release() {  # the trap: remove the lock only while it is still ours
  _own="$(cat "$LOCK" 2>/dev/null || true)"
  [ "${_own%% *}" = "$$" ] && rm -f "$LOCK"
  return 0
}
# Taking over a stale lock is serialised through a second O_EXCL file, $LOCK.takeover. Under
# it the lock is re-read and removed ONLY if it still holds exactly the stale line judged above;
# nothing else ever removes a lock that is not its own, so the compare-then-rm cannot hit a
# fresh lock. WHY (independent review of #304): the old takeover moved the lock aside and put
# it back with `mv -f` when it found a fresh one there — check-then-act. With 3+ contenders, B
# moved A's fresh lock aside, C's noclobber write landed in the gap, B saw a lock and deleted
# A's: 12 contenders gave up to 3 holders at once (tests/wave2/test-exec-lock-watch.sh).
# A takeover file left by a holder killed inside those few microseconds is stale once its pid is
# dead or it is older than 10 s (an EMPTY one once it is over a minute old — `find -mmin +1`;
# `+0` matched a file created a second ago, so a live contender's fresh takeover file was judged
# stale and a third contender got in: review of #324). It is moved aside, and put back with `ln`
# (never clobbers; left on disk if that fails) if what was moved is not the one judged stale.
# The holder removes the takeover file only while it still holds the line it wrote.
exec_lock_takeover() {  # $1 = the stale lock line; 0 iff it was removed (or already gone)
  _tk="$LOCK.takeover"; _mine="$$ $(date +%s)"
  if ! ( set -o noclobber; printf '%s\n' "$_mine" > "$_tk" ) 2>/dev/null; then
    _t="$(head -1 "$_tk" 2>/dev/null || true)"; _tpid="${_t%% *}"; _tsince="${_t#* }"
    case "$_tsince" in ''|*[!0-9]*) _tsince=0 ;; esac
    _tstale=0
    if [ -n "$_t" ]; then
      { ! kill -0 "$_tpid" 2>/dev/null || [ $(( $(date +%s) - _tsince )) -gt 10 ]; } && _tstale=1
    elif [ -n "$(find "$_tk" -mmin +1 2>/dev/null)" ]; then
      _tstale=1   # empty for over a minute: its creator died between the create and the write
    fi
    if [ "$_tstale" = 1 ]; then
      if mv "$_tk" "$_tk.stale.$$" 2>/dev/null; then
        # Remove what was moved ONLY if it is what was judged stale; anything else is someone's
        # live takeover file: put it back (ln never clobbers), and if that fails leave it be.
        # Same body as test-scratch.sh's take_over() — keep the two in step (PR #322).
        if [ "$(head -1 "$_tk.stale.$$" 2>/dev/null || true)" = "$_t" ]; then rm -f "$_tk.stale.$$"
        else ln "$_tk.stale.$$" "$_tk" 2>/dev/null && rm -f "$_tk.stale.$$"; fi
      fi
    fi
    return 1
  fi
  _now="$(head -1 "$LOCK" 2>/dev/null || true)"
  [ "$_now" = "$1" ] && rm -f "$LOCK"
  [ "$(head -1 "$_tk" 2>/dev/null || true)" = "$_mine" ] && rm -f "$_tk"   # only our own takeover file
  return 0
}
LOCK_TAKEN=0
for _try in 1 2 3 4 5 6; do
  if exec_lock_try; then LOCK_TAKEN=1; break; fi
  _held="$(head -1 "$LOCK" 2>/dev/null || true)"
  if [ -z "$_held" ] && [ "$_try" -lt 3 ]; then sleep 1; continue; fi   # being written right now
  _hpid="${_held%% *}"
  if exec_lock_live "$_hpid"; then
    _hrest="${_held#* }"; _hsince="${_hrest%% *}"; _hscript="${_hrest#* }"
    _age=""
    case "$_hsince" in ''|*[!0-9]*) ;; *) _age=" for $(( $(date +%s) - _hsince ))s" ;; esac
    [ "$_hrest" = "$_held" ] && _hscript="?"
    echo "✗ Another session holds this project's exec lock (PID $_hpid, running$_age, script: $_hscript)."
    echo "  → Wait for it to finish, then re-run. Nothing was written."
    echo "    (A dead holder is detected and taken over automatically — no manual rm is ever needed.)"
    exit 1
  fi
  if exec_lock_takeover "$_held"; then
    echo "  (stale exec lock from PID ${_hpid:-?}, which is not running — taking it over)"
  else
    sleep 1   # another contender is taking it over right now; look again
  fi
done
if [ "$LOCK_TAKEN" != 1 ]; then
  echo "✗ Could not take the exec lock $LOCK after 6 attempts — another session keeps re-taking it."
  echo "  → Wait for the other exec to finish, then re-run. Nothing was written."
  exit 1
fi
