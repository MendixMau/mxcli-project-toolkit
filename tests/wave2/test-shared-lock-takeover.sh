#!/usr/bin/env bash
# test-shared-lock-takeover.sh — exec.sh and test-scratch.sh share .mpr-snapshots/.exec.lock; contending
# on one DEAD-holder lock, they must never both hold it.
#
# Usage: bash tests/wave2/test-shared-lock-takeover.sh [path-to-test-scratch.sh] [path-to-exec.sh]
#
# WHY (review of #304, PR #324): both scripts take the same per-project lock and both take over a dead
# holder's lock. Two private protocols would not exclude EACH OTHER. Since the reap-ticket change the
# lock code lives once, in _common.sh (mxtk_lock_take / mxtk_lock_release), so the old awk-lifted
# "keep in step" copies are gone.
#
# How: checks that both scripts call the shared code on .mpr-snapshots/.exec.lock and keep no private
# lock code, then races it as each script calls it (label, attempts) — two contender scripts whose
# names contain "exec.sh" / "test-scratch.sh", so the liveness rule recognises each as a holder,
# sourcing the _common.sh beside the given test-scratch.sh. Rounds of 5 + 5 contenders start together
# on a lock whose holder pid is dead; each holder marks itself in a shared dir while it holds the
# lock. Two marks at once = two holders = FAIL. The protocol itself: test-lock-reap.sh and
# bench-lock-race.sh.
set -uo pipefail
TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TS="${1:-$TOOLKIT/project-bin/test-scratch.sh}"; EX="${2:-$TOOLKIT/project-bin/exec.sh}"
COMMON="$(cd "$(dirname "$TS")" && pwd)/_common.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/sharedlock.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT
echo "== test-scratch: $TS"
echo "== exec.sh: $EX"
echo "== _common.sh: $COMMON"

grep -q '^mxtk_lock_take() {' "$COMMON" && ok "[setup] _common.sh has the shared lock" || { bad "[setup] no mxtk_lock_take in $COMMON"; echo "PASS=$PASS FAIL=$FAIL"; exit 1; }
for f in "$EX" "$TS"; do
  n="$(basename "$f")"
  grep -q 'mxtk_lock_take "\$' "$f" && grep -q 'mxtk_lock_release "\$' "$f" && ok "$n takes and releases through _common.sh" || bad "$n does not call mxtk_lock_take/mxtk_lock_release"
  grep -qE '^(exec_lock_(live|try|takeover|release)|holder_live|take_over)\(\)' "$f" && bad "$n still defines its own lock code" || ok "$n keeps no private lock code"
  grep -q '\.mpr-snapshots/\.exec\.lock' "$f" && ok "$n locks .mpr-snapshots/.exec.lock" || bad "$n names another lock file"
done

LOCK="$WORK/.exec.lock"; HOLD="$WORK/holding"; mkdir -p "$HOLD"
hold() {  # body shared by both contenders: mark, look for another mark, unmark
  cat <<'H'
touch "$HOLD/$$"; n=$(ls "$HOLD" | wc -l | tr -d ' ')
[ "$n" -gt 1 ] && echo "OVERLAP $$ with $(ls "$HOLD" | tr '\n' ' ')" >> "$WORK/overlaps"
echo "$ROLE $$" >> "$WORK/holders"; sleep 0.3; rm -f "$HOLD/$$"
H
}
{ printf 'LOCK="$1"; ROLE=exec; PROJECT_ROOT=%q; . %q\n' "$WORK" "$COMMON"
  echo 'mxtk_lock_take "$LOCK" "exec-contender.mdl" 6 >/dev/null 2>&1 || exit 1'; hold
  echo 'mxtk_lock_release "$LOCK"'; } > "$WORK/contender-exec.sh"
{ printf 'LOCK="$1"; ROLE=scratch; PROJECT_ROOT=%q; . %q\n' "$WORK" "$COMMON"
  echo 'mxtk_lock_take "$LOCK" "test-scratch.sh" 8 >/dev/null 2>&1 || exit 1'; hold
  echo 'mxtk_lock_release "$LOCK"'; } > "$WORK/contender-test-scratch.sh"

sleep 0 & DEAD=$!; wait "$DEAD"   # a pid that is certainly not running now
ROUNDS=4
for r in $(seq 1 "$ROUNDS"); do
  printf '%s %s exec.sh\n' "$DEAD" "$(date +%s)" > "$LOCK"
  PIDS=""
  for i in 1 2 3 4 5; do
    WORK="$WORK" HOLD="$HOLD" bash "$WORK/contender-exec.sh" "$LOCK" >/dev/null 2>&1 & PIDS="$PIDS $!"
    WORK="$WORK" HOLD="$HOLD" bash "$WORK/contender-test-scratch.sh" "$LOCK" >/dev/null 2>&1 & PIDS="$PIDS $!"
  done
  for p in $PIDS; do wait "$p"; done
done
N="$(wc -l < "$WORK/holders" 2>/dev/null | tr -d ' ')"
[ "${N:-0}" -ge "$ROUNDS" ] && ok "the dead holder's lock was taken over in every round ($N holds over $ROUNDS rounds)" || bad "only ${N:-0} holds in $ROUNDS rounds"
grep -q '^exec ' "$WORK/holders" 2>/dev/null && grep -q '^scratch ' "$WORK/holders" 2>/dev/null \
  && ok "both scripts won the lock at some point (they really contended)" || echo "  note: one script won every round: $(cut -d' ' -f1 "$WORK/holders" 2>/dev/null | sort | uniq -c | tr '\n' ' ')"
if [ -s "$WORK/overlaps" ]; then bad "two holders at once: $(head -3 "$WORK/overlaps" | tr '\n' ' ')"; else ok "never two holders at once"; fi
LEFT="$(ls -a "$WORK" | grep -E '^\.exec\.lock\.' | tr '\n' ' ')"
[ -n "$LEFT" ] && bad "files left beside the lock: $LEFT" || ok "no ticket, temp or takeover file left behind"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
