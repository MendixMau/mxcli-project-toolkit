#!/usr/bin/env bash
# mxcli-replay.sh — stands in for mxcli in test-contract-check.sh.
#
# Replay (default): answers `mxcli -p <dir>/<x>.mpr --json -c "<stmts>"` with the stdout that the
# REAL mxcli printed for the same call, captured under $CC_CAPTURES/<state>/<app>.<kind>.json,
# where <app> is the name of the folder holding the .mpr, <kind> is `describe` when the statements
# are describes and `select` otherwise, and <state> comes from $CC_STATE_<app> (default: base).
#
# Record: with CC_RECORD=<real mxcli>, runs it and writes its stdout to that same path first.
# That is how every file under captures/ was made (CAPTURE.txt); none is hand-written.
set -u
mpr=""; stmts=""
while [ $# -gt 0 ]; do
  case "$1" in
    -p) mpr="$2"; shift 2 ;;
    -c) stmts="$2"; shift 2 ;;
    --version) echo "mxcli-replay"; exit 0 ;;
    *) shift ;;
  esac
done
app="$(basename "$(dirname "$mpr")")"
[ "$app" = "app" ] && app="$(basename "$(dirname "$(dirname "$mpr")")")"   # two-tree layout
case "$stmts" in describe*) kind=describe ;; *) kind=select ;; esac
eval "state=\${CC_STATE_$app:-base}"
f="${CC_CAPTURES:?CC_CAPTURES not set}/$state/$app.$kind.json"
if [ -n "${CC_RECORD:-}" ]; then
  mkdir -p "$(dirname "$f")"
  "$CC_RECORD" -p "$mpr" --json -c "$stmts" > "$f"; rc=$?
  cat "$f"; exit $rc
fi
[ -f "$f" ] || { echo "mxcli-replay: no capture $f" >&2; exit 3; }
cat "$f"
