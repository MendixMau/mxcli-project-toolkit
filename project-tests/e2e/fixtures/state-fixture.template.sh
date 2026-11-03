#!/usr/bin/env bash
# state-fixture.template.sh — put ONE existing row into an exact state the app's own UI cannot
# reach, and put it back. Rules and when this is allowed: skills/fixture-seeding.md
# "State fixtures". Copy to tests/e2e/fixtures/<name>.sh in the project and fill every FILL block.
#
#   <name>.sh check [expected]   read-only. 0 = in the expected state, 1 = another state,
#                                2 = drifted (not exactly one row). With no argument the expected
#                                state is the target of the last un-reverted `set`; with none, it
#                                prints the current value and exits 0.
#   <name>.sh dry-run <target>   the whole `set` transaction, guards included, then ROLLBACK.
#                                Run it before the first live `set`.
#   <name>.sh set <target>       one transaction: guards first (RAISE = nothing written), then the
#                                write. The pre-change value is saved only after COMMIT.
#   <name>.sh revert             back to the value saved before the first un-reverted `set`.
#                                Refuses when the row changed since, and a second time.
#
# Journeys ASSERT the state (through their seeds, or `check`); they never call `set`. A human or
# the main session runs `set`, with approval, as a precondition step of the run sheet.
#
# Local test database only. Connection comes from the usual PG* variables (PGHOST, PGHOSTADDR,
# PGPORT, PGDATABASE, PGUSER, PGPASSWORD, PGSERVICE); nothing here prints them. A PGHOST or
# PGHOSTADDR other than a local socket, localhost, 127.0.0.1 or ::1 is refused before connecting,
# and after connecting the server address itself must be a socket or loopback (this catches a
# PGSERVICE entry that points elsewhere), unless FIXTURE_ALLOW_HOST names the host exactly
# (e.g. a compose service name). Needs psql; bash 3.2 and Git Bash are fine.
#
# ── FILL: header — what this fixture writes, and what it does NOT do ────────────────────────
# Mirrors microflow: FILL e.g. Scenario.ACT_Clock_JumpTo (field for field)
# Writes:            FILL e.g. scenario$scenarioclock.currentmoment
# Does NOT do:       FILL e.g. no scheduled events replayed for the skipped minutes,
#                    no client refresh, no follow-on jobs
# Manual steps after: FILL e.g. reload the admin page so the client shows the new moment
# ─────────────────────────────────────────────────────────────────────────────────────────────
set -u

FIXTURE_NAME="${FIXTURE_NAME:-scenario-clock}"              # FILL
# Mendix table: "<module>$<entity>", lower-case, ALWAYS double-quoted (the $ is part of the name).
# No schema prefix: the dry-run and the temp-table check in the skill rely on the search path.
TABLE='"scenario$scenarioclock"'                             # FILL
# Stable key, never an object id (a base-data reload re-creates rows with new ids).
# 'true' means a singleton: the script refuses unless there is exactly one row.
KEY_SQL='true'                                               # FILL e.g. "code" = 'ORD-0001'
COL='currentmoment'                                          # FILL the column set/checked
TARGET_TYPE='timestamp'                                      # FILL COL's SQL type
# The target is read from the transaction-local setting fixture.target, never spliced into SQL.
TARGET_SQL="current_setting('fixture.target')::$TARGET_TYPE"

# Guards that run inside the transaction, after the row is locked, before any write.
# Available: t (the target, typed by TARGET_SQL) and cur (the locked row). RAISE refuses.
guards_sql() { cat <<'SQL'
  -- FILL. Typical: nothing races the write, the start state is the expected one, the target
  -- is legal by the app's own rules.
  IF NOT cur.paused THEN
    RAISE EXCEPTION 'FIXTURE REFUSED: the scenario clock is running; pause it first';
  END IF;
  IF t::date <> cur.currentmoment::date OR t < cur.currentmoment THEN
    RAISE EXCEPTION 'FIXTURE REFUSED: % is not later on the same day as %', t, cur.currentmoment;
  END IF;
SQL
}
# Derived fields the mirrored microflow also writes, as ", col = expr" (may be empty).
EXTRA_SET_SQL=''                                             # FILL e.g. , "lastjumpedat" = now()
# Extra refusals for `revert`: anything that ran on the changed state and cannot be undone.
revert_guards_sql() { cat <<'SQL'
  -- FILL e.g. IF EXISTS (SELECT 1 FROM "scenario$event" WHERE "processedat" > cur.currentmoment)
  --   THEN RAISE EXCEPTION 'FIXTURE REFUSED: events ran since set; use the app''s own reset'; END IF;
SQL
}
# ── end of FILL ──────────────────────────────────────────────────────────────────────────────

STATE_DIR="${FIXTURE_STATE_DIR:-${HOME:-/tmp}/.cache/mxtk-fixtures/$(basename "$PWD")}"
SAVED="$STATE_DIR/$FIXTURE_NAME.saved"

die() { echo "$FIXTURE_NAME: $*" >&2; exit 3; }

command -v psql >/dev/null 2>&1 || die "psql not found"
ALLOWED=""
for _hv in PGHOST PGHOSTADDR; do
  eval "_h=\${$_hv:-}"
  case "$_h" in
    ""|/*|localhost|127.0.0.1|::1) ;;
    *) [ "${FIXTURE_ALLOW_HOST:-}" = "$_h" ] \
         || die "refusing $_hv '$_h': local test database only (FIXTURE_ALLOW_HOST=<host> to name it)"
       ALLOWED=1 ;;
  esac
done

PSQL() { psql -X -q -At -v ON_ERROR_STOP=1 "$@"; }

# After connecting: the server must be on a socket or loopback, whatever PGSERVICE or a conninfo
# resolved to. Skipped only for a host FIXTURE_ALLOW_HOST named above.
if [ -z "$ALLOWED" ]; then
  _srv="$(PSQL -c "SELECT coalesce(host(inet_server_addr()), '')" 2>/dev/null)" || die "cannot connect to the database"
  case "$_srv" in
    ""|127.*|::1) ;;
    *) die "refusing server address '$_srv': local test database only (FIXTURE_ALLOW_HOST=<host> to name it)" ;;
  esac
fi

saved_get() { [ -f "$SAVED" ] && sed -n "s/^$1=//p" "$SAVED" | head -1; }

# The set/revert transaction. $1 = target text, $2 = guard block, $3 = COMMIT or ROLLBACK,
# $4 = the value revert expects to find (read by guards as current_setting('fixture.expect');
# never spliced into SQL). Prints "<old>\t<new>" for the one row it changed. A NULL current value
# is refused before the write: it could not be saved for revert.
write_tx() {
  PSQL -v target="$1" -v expect="${4:-}" <<SQL
BEGIN;
SELECT set_config('fixture.target', :'target', true) IS NULL AS _ \gset
SELECT set_config('fixture.expect', :'expect', true) IS NULL AS _ \gset
DO \$fx\$
DECLARE n int; cur record; t $TARGET_TYPE := $TARGET_SQL;
BEGIN
  SELECT count(*) INTO n FROM $TABLE WHERE $KEY_SQL;
  IF n <> 1 THEN
    RAISE EXCEPTION 'FIXTURE REFUSED: expected exactly 1 row in %, found %', '$FIXTURE_NAME', n;
  END IF;
  SELECT * INTO cur FROM $TABLE WHERE $KEY_SQL FOR UPDATE;
  IF cur.$COL IS NULL THEN
    RAISE EXCEPTION 'FIXTURE REFUSED: % is NULL now; a NULL cannot be saved for revert, so nothing is written', '$COL';
  END IF;
$2
END \$fx\$;
WITH old AS (SELECT id, $COL::text AS v FROM $TABLE WHERE $KEY_SQL FOR UPDATE)
UPDATE $TABLE x SET $COL = $TARGET_SQL $EXTRA_SET_SQL
  FROM old WHERE x.id = old.id
  RETURNING old.v || E'\t' || x.$COL::text;
$3;
SQL
}

cmd="${1:-}"; shift || true
case "$cmd" in
  check)
    exp="${1:-}"
    if [ -z "$exp" ] && [ "$(saved_get used)" = "0" ]; then exp="$(saved_get new)"; fi
    eq_sql="false"; [ -n "$exp" ] && eq_sql="coalesce(bool_and($COL = $TARGET_SQL), false)"
    out="$(PSQL -v target="$exp" <<SQL
SELECT set_config('fixture.target', :'target', false) IS NULL AS _ \gset
SELECT count(*)::text || E'\t' || coalesce(max($COL::text), '') || E'\t' || ($eq_sql)::text
  FROM $TABLE WHERE $KEY_SQL;
SQL
)" || die "check could not read the database"
    n="$(printf '%s' "$out" | cut -f1)"; cur="$(printf '%s' "$out" | cut -f2)"; eq="$(printf '%s' "$out" | cut -f3)"
    [ "$n" = "1" ] || { echo "$FIXTURE_NAME: DRIFTED ($n rows match the key, expected 1)"; exit 2; }
    if [ -z "$exp" ]; then echo "$FIXTURE_NAME: $cur (no expected state given)"; exit 0; fi
    [ "$eq" = "true" ] && { echo "$FIXTURE_NAME: in state ($cur)"; exit 0; }
    echo "$FIXTURE_NAME: NOT in state: is $cur, expected $exp"; exit 1 ;;
  dry-run|set)
    [ -n "${1:-}" ] || die "usage: $0 $cmd <target>"
    mode=COMMIT; [ "$cmd" = dry-run ] && mode=ROLLBACK
    res="$(write_tx "$1" "$(guards_sql)" "$mode")" || exit 4
    [ -n "$res" ] || die "the write matched no row"
    old="$(printf '%s' "$res" | cut -f1)"; new="$(printf '%s' "$res" | cut -f2)"
    if [ "$cmd" = dry-run ]; then echo "$FIXTURE_NAME: dry-run OK, would change $old -> $new (rolled back)"; exit 0; fi
    mkdir -p "$STATE_DIR" || die "cannot create $STATE_DIR"
    # A second set before a revert keeps the FIRST saved value: revert goes back to before both.
    if [ "$(saved_get used)" = "0" ]; then old="$(saved_get old)"; fi
    printf 'old=%s\nnew=%s\nat=%s\nused=0\n' "$old" "$new" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$SAVED"
    echo "$FIXTURE_NAME: set $new (saved $old for revert)" ;;
  revert)
    [ -f "$SAVED" ] || die "nothing to revert (no saved state at $SAVED)"
    [ "$(saved_get used)" = "0" ] || die "already reverted; a second revert is refused. Use the app's own reset"
    old="$(saved_get old)"; new="$(saved_get new)"
    g="  IF cur.$COL::text IS DISTINCT FROM current_setting('fixture.expect') THEN
    RAISE EXCEPTION 'FIXTURE REFUSED: % changed since set (now %); use the app''s own reset', '$FIXTURE_NAME', cur.$COL;
  END IF;
$(revert_guards_sql)"
    write_tx "$old" "$g" COMMIT "$new" >/dev/null || exit 4
    sed 's/^used=0$/used=1/' "$SAVED" > "$SAVED.tmp" && mv "$SAVED.tmp" "$SAVED"
    echo "$FIXTURE_NAME: reverted to $old" ;;
  *) echo "usage: $0 check [expected] | dry-run <target> | set <target> | revert" >&2; exit 64 ;;
esac
