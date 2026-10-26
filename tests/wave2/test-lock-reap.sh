#!/usr/bin/env bash
# test-lock-reap.sh — the shared lock in _common.sh (mxtk_lock_take / mxtk_lock_release): each
# reap-ticket rule on its own, the compatibility with lines and takeover files the pre-ticket code
# wrote, and a short run of the race harness.
#
# Usage: bash tests/wave2/test-lock-reap.sh [path-to-_common.sh]
#   LOCK_REAP_ROUNDS (default 15) sets the harness run; 0 skips it. The full proof is
#   tests/wave2/bench-lock-race.sh (200 rounds x 10, and --old for the old code's failure count).
#
# WHY (r-eng-backlog item 1, 2026-10-14): the old stale-lock takeover moved its `.takeover` file
# aside and put it back with `ln`; a third contender could create a new one in between, two
# contenders were then inside the takeover, and one's compare-then-rm deleted the other's fresh
# lock. Reap tickets replace it: a ticket per stale line, the next only when the previous one's pid
# is dead (never by age), and only the highest ticket's holder may remove the line it judged.
#
# Cases use the lock code's test anchors (MXTK_LOCK_TEST_PAUSE) to act at an exact point.
set -uo pipefail
TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMMON="${1:-$TOOLKIT/project-bin/_common.sh}"
case "$COMMON" in /*) ;; *) COMMON="$PWD/$COMMON" ;; esac
WORK="$(mktemp -d "${TMPDIR:-/tmp}/lockreap.XXXXXX")" || exit 2
WORK="$(cd "$WORK" && pwd -P)"
BG=""
trap 'for p in $BG; do kill -KILL "$p" 2>/dev/null; done; rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }
echo "== subject: $COMMON"
grep -q '^mxtk_lock_take() {' "$COMMON" && ok "[setup] mxtk_lock_take present" || { bad "[setup] no mxtk_lock_take in $COMMON"; echo "PASS=$PASS FAIL=$FAIL"; exit 1; }

L="$WORK/.exec.lock"
# lk <snippet> — run a snippet in a fresh shell named like an exec.sh (the liveness rule needs it),
# with _common.sh sourced, fast retries, and the lock path in $L.
cat > "$WORK/lk-exec.sh" <<'S'
PROJECT_ROOT="$WORK"; . "$COMMON"; MXTK_LOCK_RETRY_SLEEP=0.05
eval "$1"
S
lk() { WORK="$WORK" COMMON="$COMMON" L="$L" bash "$WORK/lk-exec.sh" "$1" 2>&1; }
live_holder() { bash -c 'exec -a "bash ./bin/exec.sh mdlsource/x.mdl" sleep 120' & LP=$!; BG="$BG $LP"; sleep 0.2; }
dead_pid() { sleep 0 & local p=$!; wait "$p" 2>/dev/null; echo "$p"; }
key() { printf '%s' "$1" | cksum | awk '{print $1 "-" $2}'; }
reset() { rm -f "$L" "$L".reap.* "$L".tmp.* "$L.takeover"; }
left() { ls -a "$WORK" | grep -E '^\.exec\.lock\.(reap|tmp)\.' | tr '\n' ' '; }

echo "-- a free lock: taken, released, nothing left beside it"
OUT="$(lk 'mxtk_lock_take "$L" "patch: a.mdl" 3; echo "rc=$?"; head -1 "$L"; mxtk_lock_release "$L"; [ -e "$L" ] && echo still-there')"
case "$OUT" in *rc=0*) ok "taken (rc 0)" ;; *) bad "not taken: $OUT" ;; esac
printf '%s\n' "$OUT" | grep -qE '^[0-9]+ [0-9]+ patch: a\.mdl nonce=[0-9]+$' && ok "line is '<pid> <epoch> <label> nonce=<n>'" || bad "line format: $OUT"
case "$OUT" in *still-there*) bad "release left the lock" ;; *) ok "release removed it" ;; esac
[ -z "$(left)" ] && ok "no ticket or temp file left" || bad "left: $(left)"

echo "-- release removes only our own line (same pid, other nonce = not ours)"
OUT="$(lk 'mxtk_lock_take "$L" x 3; printf "%s 1 x nonce=999\n" "$$" > "$L"; mxtk_lock_release "$L"; [ -e "$L" ] && echo kept')"
case "$OUT" in *kept*) ok "a line with our pid but another nonce is kept" ;; *) bad "release removed a line that was not ours" ;; esac
reset

echo "-- a live holder refuses, untouched, no ticket taken"
live_holder; printf '%s %s mdlsource/x.mdl nonce=1\n' "$LP" "$(date +%s)" > "$L"
OUT="$(lk 'mxtk_lock_take "$L" me 3; echo "rc=$? held=$MXTK_LOCK_HELD"')"
case "$OUT" in *"rc=1 held=$LP "*) ok "rc 1, MXTK_LOCK_HELD names the holder" ;; *) bad "$OUT" ;; esac
[ "$(cut -d' ' -f1 "$L")" = "$LP" ] && ok "the lock still names the live holder" || bad "lock changed: $(cat "$L")"
[ -z "$(left)" ] && ok "no ticket taken against a live holder" || bad "left: $(left)"
kill -KILL "$LP" 2>/dev/null; wait "$LP" 2>/dev/null; reset

echo "-- a dead holder is reaped: every line format the old and new code write"
D="$(dead_pid)"
for X in "$D $(date +%s) mdlsource/x.mdl nonce=42" "$D $(date +%s) patch: y.mdl" "$D"; do
  printf '%s\n' "$X" > "$L"
  OUT="$(lk 'mxtk_lock_take "$L" me 3; echo "rc=$?"; echo "reaped=$MXTK_LOCK_REAPED"; head -1 "$L"; mxtk_lock_release "$L"')"
  case "$OUT" in *rc=0*"reaped=$X"*) ok "reaped '$X'" ;; *) bad "'$X' not reaped: $OUT" ;; esac
  [ -z "$(left)" ] && ok "  its ticket cleared by the new holder" || bad "  left: $(left)"
done
reset

echo "-- ticket N+1 only when ticket N's pid is dead — never by age"
D="$(dead_pid)"; X="$D 1700000000 old.mdl nonce=7"; K="$(key "$X")"; printf '%s\n' "$X" > "$L"
live_holder; printf '%s 1\n' "$LP" > "$L.reap.$K.1"; touch -t 200001010000 "$L.reap.$K.1"
OUT="$(lk 'mxtk_lock_take "$L" me 3; echo "rc=$? blocker=$MXTK_LOCK_BLOCKER"; mxtk_lock_blocked_text')"
case "$OUT" in *rc=2*) ok "a live reaper's ticket (dated 2000) blocks: gave up (rc 2)" ;; *) bad "an old live ticket was overtaken: $OUT" ;; esac
case "$OUT" in *"blocker=$LP $L.reap.$K.1"*) ok "  MXTK_LOCK_BLOCKER names the reaper's pid and ticket file" ;; *) bad "  blocker not named: $OUT" ;; esac
case "$OUT" in *"kill -CONT $LP"*"kill $LP"*) ok "  and the message says to resume or end that pid (review of #379)" ;; *) bad "  no remedy in: $OUT" ;; esac
[ "$(cat "$L")" = "$X" ] && ok "the stale line was left to the live reaper" || bad "lock changed: $(cat "$L")"
[ ! -e "$L.reap.$K.2" ] && ok "no ticket 2 taken while ticket 1 lives" || bad "ticket 2 taken over a live ticket 1"
kill -KILL "$LP" 2>/dev/null; wait "$LP" 2>/dev/null
printf '%s 1\n' "$(dead_pid)" > "$L.reap.$K.2"
cat > "$WORK/seen.sh" <<'H'
#!/usr/bin/env bash
[ "$1" = ticket-taken ] && ls -a "$(dirname "$L")" | grep '\.reap\.' > "$WORK/seen"
exit 0
H
chmod +x "$WORK/seen.sh"
OUT="$(MXTK_LOCK_TEST_PAUSE="$WORK/seen.sh" lk 'export L WORK; mxtk_lock_take "$L" me 3; echo "rc=$?"; mxtk_lock_release "$L"')"
case "$OUT" in *rc=0*) ok "tickets 1 and 2 dead → taken" ;; *) bad "$OUT" ;; esac
grep -qx "\.exec\.lock\.reap\.$K\.3" "$WORK/seen" 2>/dev/null && ok "  as ticket 3 (the next after the highest)" || bad "  tickets seen: $(tr '\n' ' ' < "$WORK/seen" 2>/dev/null)"
[ -z "$(left)" ] && ok "  and every ticket of that line cleared after" || bad "  left: $(left)"
reset

echo "-- the line changed under the ticket (compare anchor): nothing removed"
D="$(dead_pid)"; printf '%s 1 old.mdl nonce=8\n' "$D" > "$L"; live_holder
cat > "$WORK/swap.sh" <<'H'
#!/usr/bin/env bash
[ "$1" = compare ] && printf '%s %s fresh.mdl nonce=9\n' "$LP" "$(date +%s)" > "$L"
exit 0
H
chmod +x "$WORK/swap.sh"
OUT="$(LP="$LP" MXTK_LOCK_TEST_PAUSE="$WORK/swap.sh" lk 'export L LP; mxtk_lock_take "$L" me 3; echo "rc=$?"')"
case "$OUT" in *rc=1*) ok "the new live line is respected (rc 1)" ;; *) bad "$OUT" ;; esac
[ "$(cut -d' ' -f1 "$L")" = "$LP" ] && ok "the fresh lock survives" || bad "the fresh lock was removed: $(cat "$L" 2>/dev/null)"
[ -z "$(left)" ] && ok "the reaper's ticket is gone (its line can never come back)" || bad "left: $(left)"
kill -KILL "$LP" 2>/dev/null; wait "$LP" 2>/dev/null; reset

echo "-- only the highest ticket may remove: a ticket N+1 appearing after ours stops the rm"
D="$(dead_pid)"; X="$D 1 old.mdl nonce=10"; K="$(key "$X")"; printf '%s\n' "$X" > "$L"
cat > "$WORK/over.sh" <<'H'
#!/usr/bin/env bash
[ "$1" = ticket-taken ] && [ ! -e "$WORK/over.done" ] && { : > "$WORK/over.done"; printf '999999 x\n' > "$L.reap.$K.2"; }
exit 0
H
chmod +x "$WORK/over.sh"
OUT="$(K="$K" MXTK_LOCK_TEST_PAUSE="$WORK/over.sh" lk 'export L K WORK; mxtk_lock_take "$L" me 1; echo "rc=$?"')"
[ "$(cat "$L" 2>/dev/null)" = "$X" ] && ok "the stale line was not removed by a lower ticket" || bad "removed under a higher ticket: $OUT"
reset; rm -f "$WORK/over.done"

echo "-- a reaper SIGKILLed at its rm anchor does not block the next (instrument rule 7)"
D="$(dead_pid)"; printf '%s 1 old.mdl nonce=11\n' "$D" > "$L"
cat > "$WORK/die.sh" <<'H'
#!/usr/bin/env bash
[ "$1" = rm ] && kill -KILL "$2"
exit 0
H
chmod +x "$WORK/die.sh"
( MXTK_LOCK_TEST_PAUSE="$WORK/die.sh" lk 'mxtk_lock_take "$L" me 3' ) >/dev/null 2>&1
[ -n "$(left)" ] && ok "[setup] the killed reaper left its ticket" || bad "[setup] no ticket left — case proves nothing"
OUT="$(lk 'mxtk_lock_take "$L" me 3; echo "rc=$?"; mxtk_lock_release "$L"')"
case "$OUT" in *rc=0*) ok "the next contender takes it at once" ;; *) bad "blocked by a dead reaper: $OUT" ;; esac
[ -z "$(left)" ] && ok "and clears the dead ticket" || bad "left: $(left)"
reset

echo "-- the new holder clears tickets of other lines and temp files of dead pids"
printf '1 x\n' > "$L.reap.123-45.1"; printf 'junk\n' > "$L.tmp.$(dead_pid)"
OUT="$(lk 'mxtk_lock_take "$L" me 3; echo "rc=$?"; mxtk_lock_release "$L"')"
[ -z "$(left)" ] && ok "cleared" || bad "left: $(left)"
reset

echo "-- an empty lock: fresh = being written (wait); over a minute old = stale"
: > "$L"
OUT="$(lk 'mxtk_lock_take "$L" me 2; echo "rc=$?"')"
case "$OUT" in *rc=2*) ok "a fresh empty lock is waited on, not reaped" ;; *) bad "$OUT" ;; esac
[ -e "$L" ] && [ ! -s "$L" ] && ok "  and left alone" || bad "  the fresh empty lock was touched"
touch -t 200001010000 "$L"
OUT="$(lk 'mxtk_lock_take "$L" me 2; echo "rc=$?"; mxtk_lock_release "$L"')"
case "$OUT" in *rc=0*) ok "an empty lock over a minute old is reaped" ;; *) bad "$OUT" ;; esac
reset

echo "-- an EMPTY stale lock replaced mid-reap by a fresh empty one is not removed (review of #379)"
# An empty line is not unique: the old code creates its lock empty and writes after. A reaper of an
# old empty lock, paused at compare while that lock is replaced by a fresh empty one, must not rm it.
: > "$L"; touch -t 200001010000 "$L"
cat > "$WORK/empty-swap.sh" <<'H'
#!/usr/bin/env bash
[ "$1" = compare ] && { rm -f "$L"; : > "$L"; }
exit 0
H
chmod +x "$WORK/empty-swap.sh"
OUT="$(MXTK_LOCK_TEST_PAUSE="$WORK/empty-swap.sh" lk 'export L; mxtk_lock_take "$L" me 1; echo "rc=$?"')"
[ -e "$L" ] && [ ! -s "$L" ] && [ -z "$(find "$L" -mmin +1 2>/dev/null)" ] && ok "the fresh empty lock survives" || bad "the fresh empty lock was removed: $OUT"
[ -z "$(left)" ] && ok "  and the reaper's ticket is gone" || bad "  left: $(left)"
reset

echo "-- mixed versions: an old-style <lock>.takeover"
D="$(dead_pid)"; printf '%s 1 old.mdl\n' "$D" > "$L"; live_holder
printf '%s %s\n' "$LP" "$(date +%s)" > "$L.takeover"
OUT="$(lk 'mxtk_lock_take "$L" me 2; echo "rc=$?"')"
case "$OUT" in *rc=2*) ok "a live old takeover in progress: we back off" ;; *) bad "$OUT" ;; esac
[ "$(cat "$L")" = "$D 1 old.mdl" ] && ok "  the stale line is left to it" || bad "  lock changed"
kill -KILL "$LP" 2>/dev/null; wait "$LP" 2>/dev/null
OUT="$(lk 'mxtk_lock_take "$L" me 2; echo "rc=$?"; mxtk_lock_release "$L"')"
case "$OUT" in *rc=0*) ok "its pid dead: reaped" ;; *) bad "$OUT" ;; esac
[ ! -e "$L.takeover" ] && ok "  and the dead takeover file cleared by the new holder" || bad "  takeover file left"
printf '%s 1 old.mdl\n' "$D" > "$L"; : > "$L.takeover"
OUT="$(lk 'mxtk_lock_take "$L" me 2; echo "rc=$?"')"
case "$OUT" in *rc=2*) ok "a fresh EMPTY takeover file (old code between create and write) is respected" ;; *) bad "$OUT" ;; esac
touch -t 200001010000 "$L.takeover"
OUT="$(lk 'mxtk_lock_take "$L" me 2; echo "rc=$?"; mxtk_lock_release "$L"')"
case "$OUT" in *rc=0*) ok "an empty one over a minute old is not" ;; *) bad "$OUT" ;; esac
reset

echo "-- mxtk_lock_fields"
OUT="$(lk 'for x in "12 1700 patch: a.mdl nonce=9" "12 1700 a.mdl" "12"; do mxtk_lock_fields "$x"; echo "[$MXTK_LOCK_HPID|$MXTK_LOCK_HSINCE|$MXTK_LOCK_HLABEL]"; done')"
[ "$OUT" = "[12|1700|patch: a.mdl]
[12|1700|a.mdl]
[12||?]" ] && ok "new, old and bare-pid lines parse; the nonce is never shown" || bad "$OUT"

echo "-- mixed versions do not deadlock: old-block and new contenders on one dead holder"
OLDB="$TOOLKIT/tests/wave2/fixtures/mxtest-guard/exec-lock-block.sh"
{ echo 'LOG_NAME=old.mdl'; echo 'ctake() {'; grep -v '^#' "$OLDB" | sed -e 's/sleep 1/sleep 0.05/' -e 's/^    exit 1$/    return 1/' -e 's/^  exit 1$/  return 2/'; echo '}'
  echo 'crelease() { exec_lock_release; }'; } > "$WORK/old-impl.sh"
printf 'PROJECT_ROOT="$WORK"; . "$COMMON"; MXTK_LOCK_RETRY_SLEEP=0.05\nctake() { mxtk_lock_take "$L" new 3; }\ncrelease() { mxtk_lock_release "$L"; }\n' > "$WORK/new-impl.sh"
cat > "$WORK/mix-exec.sh" <<'M'
LOCK="$L"; . "$IMPL"; end=$(( $(date +%s) + 20 ))
while [ "$(date +%s)" -lt "$end" ]; do ctake >/dev/null 2>&1 && { echo got >> "$WORK/mixgot"; sleep 0.05; crelease; exit 0; }; sleep 0.02; done
exit 1
M
MIXFAIL=0
for r in 1 2 3; do
  printf '%s 1 old.mdl\n' "$(dead_pid)" > "$L"; PIDS=""
  for i in 1 2 3; do
    WORK="$WORK" COMMON="$COMMON" L="$L" IMPL="$WORK/old-impl.sh" bash "$WORK/mix-exec.sh" & PIDS="$PIDS $!"
    WORK="$WORK" COMMON="$COMMON" L="$L" IMPL="$WORK/new-impl.sh" bash "$WORK/mix-exec.sh" & PIDS="$PIDS $!"
  done
  for p in $PIDS; do wait "$p" || MIXFAIL=$((MIXFAIL + 1)); done
  rm -f "$L.takeover"
done
[ "$MIXFAIL" -eq 0 ] && [ "$(wc -l < "$WORK/mixgot" | tr -d ' ')" -eq 18 ] && ok "all 18 contenders (9 old, 9 new) got the lock within 20 s" \
  || bad "$MIXFAIL contenders never got the lock; $(wc -l < "$WORK/mixgot" 2>/dev/null | tr -d ' ') acquisitions of 18"
reset

ROUNDS="${LOCK_REAP_ROUNDS:-15}"
if [ "$ROUNDS" -gt 0 ]; then
  echo "-- race harness: $ROUNDS rounds x 10 contenders, SIGKILLs at every anchor and at random"
  OUT="$(KILL_AT="ticket-taken compare rm created" bash "$TOOLKIT/tests/wave2/bench-lock-race.sh" --rounds "$ROUNDS" --common "$COMMON" 2>&1)"
  R="$(printf '%s\n' "$OUT" | grep '^RESULT' | tail -1)"
  case "$R" in *" overlaps=0 "*" stolen=0 starved=0 probe_fail=0 "*) ok "no overlap, no stolen lock, no starvation: $R" ;; *) bad "harness: $(printf '%s' "$OUT" | tail -6)" ;; esac
fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
