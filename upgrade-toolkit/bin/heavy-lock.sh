#!/bin/zsh
[ -n "${BASH_VERSION:-}" ] && exec zsh "$0" "$@"  # a zsh script: `bash script.sh` re-runs it under zsh (E6-1)
# heavy-lock.sh <label> <command...>: run a heavy Docker step (mxbuild, mx check, marketplace update, app start) while
# holding /tmp/heavy-docker.lock, so parallel sessions on one laptop do not run out of memory together.
# Waits while the lock exists (30 s poll, UPG_LOCK_POLL), takes it atomically (noclobber) with "<UPG_NAME> <label> <date>",
# runs, removes it on exit. The lock file is never removed by anyone but its holder.
# The label is required and is never a command: a first argument that is an executable path (heavy-lock.sh $B/mx10.sh ...)
# means the label was left out, and the script refuses instead of running "10.24.16" as the command (E6-14).
# Re-entry: a command run under the lock that calls heavy-lock.sh again (a guard's fixer that calls mx10.sh through it)
# runs straight through; HEAVY_LOCK_HELD names the lock this process tree holds. Never a deadlock on its own lock.
label=${1:?usage: heavy-lock.sh <label> <command...>}; shift
if [[ $label == */* && -x $label ]] || [[ $# == 0 ]]; then
  echo "heavy-lock: label missing: usage heavy-lock.sh <label> <command...> (got '$label' as the label${1:+, '$1' as the command})" >&2; exit 2
fi
L=${UPG_LOCK:-/tmp/heavy-docker.lock}
if [[ ${HEAVY_LOCK_HELD:-} == $L ]]; then "$@"; exit $?; fi
while true; do
  if ( set -o noclobber; echo "${UPG_NAME:-upgrade-toolkit} $label $(date) pid $$" > $L ) 2>/dev/null; then break; fi
  echo "[heavy-lock] waiting: $(cat $L 2>/dev/null)" >&2
  sleep ${UPG_LOCK_POLL:-30}
done
trap 'rm -f $L' EXIT INT TERM
export HEAVY_LOCK_HELD=$L
t0=$(date +%s)
"$@"; rc=$?
echo "[heavy-lock] $label rc=$rc $(( $(date +%s) - t0 ))s" >&2
exit $rc
