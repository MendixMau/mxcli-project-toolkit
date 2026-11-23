#!/usr/bin/env bash
# test-init-leakguard-nudge.sh - init-project.sh's closing leak-guard line names the denylist it wrote.
#
# usage: bash tests/wave2/test-init-leakguard-nudge.sh [path-to-init-project.sh]
#
# Field (real-mxcli scaffold, mxcli v0.32.0-374, Mendix 11.8.0, 2026-11-20): with
# MXTK_LEAKGUARD_DENYFILE set, init printed 'Registered "<name>" with the toolkit leak guard (<file>)'
# and, 230 lines later, 'Leak guard: no <toolkit>/.leakguard-deny found on this machine. Create it',
# because the nudge tested the default path, not the file the override named.
#
#   A  the override file is written and holds the project name                   (guard)
#   B  the nudge names the override file and does not say "no ... found"          (fails on master)
#
# One init run on a scratch project (about 25 s). Writes nothing outside its temp dir.
set -u
TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUBJECT="${1:-$TOOLKIT/bin/init-project.sh}"
case "$SUBJECT" in /*) ;; *) SUBJECT="$PWD/$SUBJECT" ;; esac
WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/init-lgnudge.XXXXXX")" && pwd -P)" || exit 2
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL - $1${2:+: $2}"; }

mkdir -p "$WORK/leakprobe"; : > "$WORK/leakprobe/Fixture.mpr"
DENY="$WORK/deny.txt"
MXTK_LEAKGUARD_DENYFILE="$DENY" MXTK_NO_GUIDE=1 MXTK_SYNC_SKIP_CLONE_CHECK=1 \
  bash "$SUBJECT" "$WORK/leakprobe" </dev/null >"$WORK/out" 2>&1

grep -q '\\bleakprobe\\b' "$DENY" 2>/dev/null && ok "A: override denylist written with the project name" \
  || bad "A: override denylist not written" "$(cat "$DENY" 2>/dev/null)"
NUDGE="$(grep -A1 '^Leak guard:' "$WORK/out")"
case "$NUDGE" in *"no "*".leakguard-deny found"*|*"no $DENY found"*) bad "B: nudge says the denylist is missing" "$NUDGE" ;;
  *"$DENY"*) ok "B: nudge names $DENY" ;;
  *) bad "B: nudge does not name the override file" "$NUDGE" ;; esac

echo ""
echo "== $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
