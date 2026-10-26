#!/usr/bin/env bash
# test-state-fixture-template.sh — the state-fixture template (#566) on a real PostgreSQL:
# check / dry-run / set / revert, its guards, and its refusals.
#
# Usage: bash tests/wave2/test-state-fixture-template.sh   (no argument: the subject is the
#        template under project-tests/e2e/fixtures, found from this fixture's own location)
#
# Database: a throwaway cluster from initdb (looked up on PATH and under /usr/lib/postgresql/*/bin),
# or, when initdb cannot run (no binary, or running as root), an existing server named by
# FIXTURE_TEST_PGHOST / _PGPORT / _PGUSER / _PGPASSWORD, in which a scratch database is created
# and dropped. Neither available: every case SKIPs, stated, and the fixture exits 0.
#
# The table is Mendix-shaped ("<module>$<entity>", bigint id) — written by hand, because no
# Mendix runtime is available here to create one; the template only ever sees table/column
# names and SQL types, which is exactly what the hand-written table pins.
#
#   T1  check, no expected state            -> prints the value, exit 0
#   T2  dry-run                             -> exit 0, "would change", value unchanged after
#   T3  set, then check (no arg = last set) -> exit 0; check against the old value -> exit 1
#   T4  a second set, then revert           -> back to the value before the FIRST set
#   T5  a second revert                     -> refused (exit 3)
#   T6  guard: target earlier than now      -> refused (exit 4), value and saved state unchanged
#   T7  guard: clock running                -> refused, value unchanged
#   T8  row changed since set               -> revert refused, the later value kept
#   T9  drift: two rows match the key       -> check exit 2, set refused
#   T10 a quote in the target               -> refused by the cast, the table still there
#   T11 a remote PGHOST                     -> refused before any connection (exit 3)
#   T12 the password never appears in any output
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SUT="$HERE/../../project-tests/e2e/fixtures/state-fixture.template.sh"
[ -f "$SUT" ] || { echo "FAIL template not found at $SUT"; exit 1; }

W="$(mktemp -d "${TMPDIR:-/tmp}/statefx.XXXXXX")" || exit 2
PASS=0; FAIL=0; ALL_OUT="$W/all-output.txt"; : > "$ALL_OUT"
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/  FAIL-detail: /'; }

# ── a database ──────────────────────────────────────────────────────────────────────────────
PGBIN=""
_on_path="$(command -v initdb 2>/dev/null)"
for d in ${_on_path:+"$(dirname "$_on_path")"} /usr/lib/postgresql/*/bin; do
  [ -x "$d/initdb" ] && [ -x "$d/pg_ctl" ] && { PGBIN="$d"; break; }
done
CLEANUP=""
if [ -n "$PGBIN" ] && [ "$(id -u)" != 0 ]; then
  PW="fxpw-$$-not-echoed"
  printf '%s\n' "$PW" > "$W/pw"
  "$PGBIN/initdb" -D "$W/data" -U fx --pwfile="$W/pw" -A scram-sha-256 >/dev/null 2>&1 \
    || { echo "  SKIP initdb failed"; rm -rf "$W"; exit 0; }
  PORT=$(( 20000 + $$ % 20000 ))
  "$PGBIN/pg_ctl" -D "$W/data" -o "-p $PORT -k $W -c listen_addresses=localhost" -l "$W/pg.log" -w start >/dev/null 2>&1 \
    || { echo "  SKIP pg_ctl start failed"; rm -rf "$W"; exit 0; }
  CLEANUP="\"$PGBIN/pg_ctl\" -D \"$W/data\" -m immediate stop >/dev/null 2>&1"
  export PGHOST=localhost PGPORT="$PORT" PGUSER=fx PGPASSWORD="$PW" PGDATABASE=postgres
elif [ -n "${FIXTURE_TEST_PGHOST:-}" ]; then
  export PGHOST="$FIXTURE_TEST_PGHOST" PGPORT="${FIXTURE_TEST_PGPORT:-5432}" \
         PGUSER="${FIXTURE_TEST_PGUSER:-postgres}" PGPASSWORD="${FIXTURE_TEST_PGPASSWORD:-}" PGDATABASE=postgres
  PW="$PGPASSWORD"
else
  echo "  SKIP no initdb usable (absent, or running as root) and no FIXTURE_TEST_PGHOST — 12 cases not run"
  rm -rf "$W"; exit 0
fi
DB="statefx_$$"
psql -X -q -c "CREATE DATABASE $DB" >/dev/null 2>&1 || { echo "  SKIP cannot create a database"; eval "$CLEANUP"; rm -rf "$W"; exit 0; }
export PGDATABASE="$DB"
trap 'PGDATABASE=postgres psql -X -q -c "DROP DATABASE IF EXISTS $DB" >/dev/null 2>&1; eval "$CLEANUP"; rm -rf "$W"' EXIT

q() { psql -X -q -At -c "$1"; }
q 'CREATE TABLE "scenario$scenarioclock" (id bigint PRIMARY KEY, currentmoment timestamp, paused boolean)' >/dev/null
q "INSERT INTO \"scenario\$scenarioclock\" VALUES (281474976710657, '2026-10-23 13:00', true)" >/dev/null
val() { q 'SELECT currentmoment FROM "scenario$scenarioclock" ORDER BY id LIMIT 1'; }

cp "$SUT" "$W/clock.sh"
export FIXTURE_STATE_DIR="$W/state"
run() { out="$(bash "$W/clock.sh" "$@" 2>&1)"; rc=$?; printf '%s\n' "$out" >> "$ALL_OUT"; }

echo "== T1 check with no expected state =="
run check
[ "$rc" = 0 ] && case "$out" in *"2026-10-23 13:00:00"*) ok "T1 prints the value, exit 0" ;; *) bad "T1 value missing" "$out" ;; esac \
  || bad "T1 exit $rc" "$out"

echo "== T2 dry-run =="
run dry-run "2026-10-23 13:08"
[ "$rc" = 0 ] && case "$out" in *"would change 2026-10-23 13:00:00 -> 2026-10-23 13:08:00"*) ok "T2 dry-run reports the change" ;; *) bad "T2 output" "$out" ;; esac \
  || bad "T2 exit $rc" "$out"
[ "$(val)" = "2026-10-23 13:00:00" ] && ok "T2 value unchanged after dry-run" || bad "T2 dry-run wrote: $(val)"
[ ! -f "$W/state/scenario-clock.saved" ] && ok "T2 dry-run saved nothing" || bad "T2 dry-run wrote a saved state"

echo "== T3 set, check =="
run set "2026-10-23 13:08"
[ "$rc" = 0 ] && [ "$(val)" = "2026-10-23 13:08:00" ] && ok "T3 set wrote 13:08" || bad "T3 set rc=$rc val=$(val)" "$out"
run check;                       [ "$rc" = 0 ] && ok "T3 check (last set) exit 0" || bad "T3 check rc=$rc" "$out"
run check "2026-10-23 13:00";    [ "$rc" = 1 ] && ok "T3 check vs old value exit 1" || bad "T3 check-old rc=$rc" "$out"
run check "2026-10-23 13:08:00"; [ "$rc" = 0 ] && ok "T3 check with explicit expected exit 0" || bad "T3 explicit rc=$rc" "$out"

echo "== T4 second set, revert to before the first =="
run set "2026-10-23 13:12"
[ "$rc" = 0 ] || bad "T4 second set rc=$rc" "$out"
run revert
[ "$rc" = 0 ] && [ "$(val)" = "2026-10-23 13:00:00" ] && ok "T4 revert back to 13:00 (before the first set)" || bad "T4 revert rc=$rc val=$(val)" "$out"

echo "== T5 second revert =="
run revert
[ "$rc" = 3 ] && case "$out" in *"already reverted"*) ok "T5 second revert refused" ;; *) bad "T5 message" "$out" ;; esac || bad "T5 rc=$rc" "$out"

echo "== T6 guard: backwards =="
cp "$W/state/scenario-clock.saved" "$W/saved.before"
run set "2026-10-23 12:00"
[ "$rc" = 4 ] && case "$out" in *"FIXTURE REFUSED"*) ok "T6 refused with FIXTURE REFUSED" ;; *) bad "T6 message" "$out" ;; esac || bad "T6 rc=$rc" "$out"
[ "$(val)" = "2026-10-23 13:00:00" ] && ok "T6 value unchanged" || bad "T6 wrote $(val)"
cmp -s "$W/saved.before" "$W/state/scenario-clock.saved" && ok "T6 saved state untouched" || bad "T6 saved state changed"

echo "== T7 guard: clock running =="
q 'UPDATE "scenario$scenarioclock" SET paused = false' >/dev/null
run set "2026-10-23 13:08"
[ "$rc" = 4 ] && [ "$(val)" = "2026-10-23 13:00:00" ] && ok "T7 refused while running, value unchanged" || bad "T7 rc=$rc val=$(val)" "$out"
q 'UPDATE "scenario$scenarioclock" SET paused = true' >/dev/null

echo "== T8 changed since set =="
run set "2026-10-23 13:08"; [ "$rc" = 0 ] || bad "T8 setup set rc=$rc" "$out"
q "UPDATE \"scenario\$scenarioclock\" SET currentmoment = '2026-10-23 13:30'" >/dev/null
run revert
[ "$rc" = 4 ] && [ "$(val)" = "2026-10-23 13:30:00" ] && ok "T8 revert refused, later value kept" || bad "T8 rc=$rc val=$(val)" "$out"

echo "== T9 drift =="
q "INSERT INTO \"scenario\$scenarioclock\" VALUES (281474976710658, '2026-10-23 09:00', true)" >/dev/null
run check;  [ "$rc" = 2 ] && ok "T9 check DRIFTED exit 2" || bad "T9 check rc=$rc" "$out"
run set "2026-10-23 13:40"; [ "$rc" = 4 ] && ok "T9 set refused on 2 rows" || bad "T9 set rc=$rc" "$out"
q 'DELETE FROM "scenario$scenarioclock" WHERE id = 281474976710658' >/dev/null

echo "== T10 quote in the target =="
run set "2026-10-23 13:45'; DROP TABLE \"scenario\$scenarioclock\"; --"
[ "$rc" != 0 ] && [ "$(val)" = "2026-10-23 13:30:00" ] && ok "T10 refused, table intact" || bad "T10 rc=$rc val=$(val)" "$out"

echo "== T11 remote host =="
out="$(PGHOST=db.example.invalid bash "$W/clock.sh" check 2>&1)"; rc=$?; printf '%s\n' "$out" >> "$ALL_OUT"
[ "$rc" = 3 ] && case "$out" in *"local test database only"*) ok "T11 remote host refused" ;; *) bad "T11 message" "$out" ;; esac || bad "T11 rc=$rc" "$out"

echo "== T12 no password in output =="
if [ -n "${PW:-}" ] && grep -qF "$PW" "$ALL_OUT"; then bad "T12 the password appeared in output"; else ok "T12 password never printed"; fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
