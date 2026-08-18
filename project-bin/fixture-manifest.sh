#!/usr/bin/env bash
# fixture-manifest.sh — derive the fixture a journey set needs, then measure the gap.
#
# Step 1 of the seeding flow in skills/fixture-seeding.md. It answers, without
# guessing and without asking a human anything that is already written down:
#
#   what does this journey set REQUIRE   (derived from journeys/*.journey.json)
#   what does the running app HAVE       (measured via OQL against the live app)
#   what is missing, and whose fault is it
#
# The last column is the point. "Seeds return nothing" has at least three causes
# with three different owners — the runtime was still warming, the fixture is
# absent, or the seed SQL is malformed — and they are routinely conflated. A run
# that guesses wrong sends someone to debug the wrong subsystem.
#
# READ-ONLY. This script never writes to the model or the database. Seeding is a
# separate, approved step: a tool that repairs its own preconditions can no
# longer report that they were absent.
#
# Exit codes follow the journey-proof convention:
#   0  fixture sufficient — every declared precondition resolved
#   1  finding — the app is reachable and the fixture is short
#   2  fault — could not measure (app down, admin API unreachable, no journeys)
#
# Usage:
#   fixture-manifest.sh [--journeys DIR] [--json]
# Env (falls back to .docker/.env, then defaults):
#   ADMIN_HOST ADMIN_PORT M2EE_ADMIN_PASS MXCLI PROJECT_MPR

set -uo pipefail

JOURNEY_DIR="journeys"
AS_JSON=0
while [ $# -gt 0 ]; do
  case "$1" in
    --journeys) JOURNEY_DIR="$2"; shift 2 ;;
    --json)     AS_JSON=1; shift ;;
    -h|--help)  sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

# ── Resolve the project and the admin API ────────────────────────────────────
MXCLI="${MXCLI:-./mxcli}"
[ -x "$MXCLI" ] || { echo "FAULT: $MXCLI not executable — run from the project root" >&2; exit 2; }

if [ -z "${PROJECT_MPR:-}" ]; then
  PROJECT_MPR="$(ls -1 ./*.mpr 2>/dev/null | head -1)"
fi
[ -n "$PROJECT_MPR" ] || { echo "FAULT: no .mpr found; set PROJECT_MPR" >&2; exit 2; }

# .docker/.env OVERRIDES shell exports for docker-compose, so it is the honest
# source for the port the app is actually on. Read it, but let real env win.
if [ -f .docker/.env ]; then
  _p="$(grep -E '^ADMIN_PORT=' .docker/.env 2>/dev/null | tail -1 | cut -d= -f2 | tr -d ' \r')"
  _a="$(grep -E '^M2EE_ADMIN_PASS=' .docker/.env 2>/dev/null | tail -1 | cut -d= -f2 | tr -d ' \r')"
  [ -n "${_p:-}" ] && ADMIN_PORT="${ADMIN_PORT:-$_p}"
  [ -n "${_a:-}" ] && M2EE_ADMIN_PASS="${M2EE_ADMIN_PASS:-$_a}"
fi
ADMIN_HOST="${ADMIN_HOST:-localhost}"
ADMIN_PORT="${ADMIN_PORT:-8090}"
M2EE_ADMIN_PASS="${M2EE_ADMIN_PASS:-AdminPassword1!}"

[ -d "$JOURNEY_DIR" ] || { echo "FAULT: no journey directory at $JOURNEY_DIR" >&2; exit 2; }

# oql <sql> -> JSON array on stdout, non-zero on failure.
oql() {
  "$MXCLI" oql --direct --host "$ADMIN_HOST" --port "$ADMIN_PORT" \
    --token "$M2EE_ADMIN_PASS" --json "$1" 2>/dev/null
}
export -f oql 2>/dev/null || true

# ── Is the app even reachable? Distinguish this from an absent fixture. ──────
if ! oql "SELECT count(s.ID) AS n FROM System.Session AS s" >/dev/null 2>&1; then
  echo "FAULT: admin API unreachable at $ADMIN_HOST:$ADMIN_PORT."
  echo "       This is an instrument fault, NOT an empty fixture — do not seed on the"
  echo "       strength of it. Bring the stack up (bin/test-stack-up.sh) and re-run."
  exit 2
fi

# ── Derive, probe, classify ──────────────────────────────────────────────────
MXCLI="$MXCLI" ADMIN_HOST="$ADMIN_HOST" ADMIN_PORT="$ADMIN_PORT" \
M2EE_ADMIN_PASS="$M2EE_ADMIN_PASS" JOURNEY_DIR="$JOURNEY_DIR" AS_JSON="$AS_JSON" \
python3 <<'PY'
import json, os, re, subprocess, sys, glob

MXCLI = os.environ["MXCLI"]; HOST = os.environ["ADMIN_HOST"]
PORT  = os.environ["ADMIN_PORT"]; TOK = os.environ["M2EE_ADMIN_PASS"]
JDIR  = os.environ["JOURNEY_DIR"]; AS_JSON = os.environ["AS_JSON"] == "1"

def oql(sql):
    """Returns (rows, error). rows is a list of dicts; error is None on success."""
    p = subprocess.run([MXCLI, "oql", "--direct", "--host", HOST, "--port", PORT,
                        "--token", TOK, "--json", sql],
                       capture_output=True, text=True)
    if p.returncode != 0:
        return None, (p.stderr.strip().splitlines() or ["oql failed"])[-1][:200]
    try:
        return json.loads(p.stdout), None
    except json.JSONDecodeError:
        return None, "oql returned non-JSON: " + p.stdout.strip()[:160]

files = sorted(glob.glob(os.path.join(JDIR, "*.journey.json")))
if not files:
    print(f"FAULT: no *.journey.json in {JDIR}", file=sys.stderr); sys.exit(2)

personas, rows_req, seed_req, notes = {}, {}, [], []

for f in files:
    try:
        j = json.load(open(f, encoding="utf-8"))
    except Exception as e:
        notes.append((os.path.basename(f), f"UNREADABLE: {e}")); continue
    jid = j.get("id") or os.path.basename(f)
    p = j.get("persona")
    if p: personas.setdefault(p, []).append(jid)

    for s in j.get("seeds") or []:
        seed_req.append((jid, s.get("name", "?"), s.get("sql", "")))
    if not (j.get("seeds") or []):
        n = j.get("_seedNote")
        notes.append((jid, "declares no seeds" + (f" — {n}" if n else
                      " and gives NO _seedNote (unexplained: is that right?)")))

    # Entities the data rungs touch, and the associations that must be set.
    for st in j.get("steps") or []:
        d = st.get("data") or {}
        ent = d.get("creates")
        if ent:
            rows_req.setdefault(ent, set())
        for a in d.get("assocMustBeSet") or []:
            e = a.get("entity");  t = a.get("target")
            if e: rows_req.setdefault(e, set()).add(a.get("assoc", "?"))
            if t: rows_req.setdefault(t, set())

print("=" * 78)
print("FIXTURE MANIFEST — derived from the journeys' own declarations")
print("=" * 78)
print(f"journeys: {len(files)}   personas: {', '.join(personas) or '(none declared)'}")
print()

# ── 1. Identity. The gate: if the persona is wrong nothing downstream matters ─
print("── 1. IDENTITY " + "─" * 62)
ident_gap = False
for p, used_by in personas.items():
    rows, err = oql("SELECT u.Name AS n, u.Active AS a, u.Blocked AS b, "
                    f"u.FailedLogins AS f FROM System.User AS u WHERE u.Name = '{p}'")
    if err:
        print(f"  FAULT  {p}: could not query — {err}"); ident_gap = True; continue
    if not rows:
        print(f"  GAP    {p}: NO SUCH ACCOUNT — used by {', '.join(used_by)}")
        print( "         Seed via `create demo user` (manage-security.md), NOT a SQL INSERT:")
        print( "         Mendix stores the password hashed and write-only, so an INSERT")
        print( "         yields an account that exists and cannot log in.")
        ident_gap = True; continue
    r = rows[0]
    flags = []
    if str(r.get("a", "")).lower() in ("false", "0"): flags.append("INACTIVE")
    if str(r.get("b", "")).lower() in ("true", "1"):  flags.append("BLOCKED")
    fl = r.get("f", "0")
    if str(fl) not in ("0", "", "None"): flags.append(f"FailedLogins={fl}")
    if flags:
        print(f"  GAP    {p}: {', '.join(flags)}")
        print( "         A blocked account fails the NEXT run for a different reason than")
        print( "         the original one. Clear it before seeding anything else.")
        ident_gap = True
    else:
        print(f"  OK     {p}: active, unblocked, 0 failed logins  ({len(used_by)} journeys)")
print()

# ── 2. Seeds. The preconditions the journeys publish as SQL. ────────────────
print("── 2. SEED PRECONDITIONS " + "─" * 52)
seed_gap = False
if not seed_req:
    print("  (no journey declares a seed)")
for jid, name, sql in seed_req:
    if "{{" in sql:
        print(f"  SKIP   {jid}/{name}: templated on an earlier seed — resolved at run time")
        continue
    rows, err = oql(sql)
    if err:
        print(f"  FAULT  {jid}/{name}: seed SQL did not execute — {err}")
        print( "         MALFORMED SEED, not an absent fixture. Fix the query, do not seed.")
        seed_gap = True
    elif not rows:
        print(f"  GAP    {jid}/{name}: returns 0 rows")
        print(f"         {sql}")
        seed_gap = True
    else:
        v = list(rows[0].values())[0] if rows[0] else "?"
        print(f"  OK     {jid}/{name}: resolves to {v!r}")
print()

# ── 3. Row requirements from the data rungs. ────────────────────────────────
print("── 3. ENTITIES THE DATA RUNGS TOUCH " + "─" * 41)
row_gap = False
if not rows_req:
    print("  (no journey declares a data rung)")
for ent in sorted(rows_req):
    rows, err = oql(f"SELECT count(x.ID) AS n FROM {ent} AS x")
    assocs = sorted(a for a in rows_req[ent] if a != "?")
    suffix = ("   [assoc must be set: " + ", ".join(assocs) + "]") if assocs else ""
    if err:
        print(f"  FAULT  {ent}: {err}"); row_gap = True
    else:
        n = int(list(rows[0].values())[0]) if rows else 0
        tag = "OK    " if n > 0 else "GAP   "
        if n == 0: row_gap = True
        print(f"  {tag} {ent}: {n} row(s){suffix}")
if any(rows_req[e] - {"?"} for e in rows_req):
    print()
    print("  NOTE: every association above must be set on every seeded row. The rung-4")
    print("        assocMustBeSet claim checks exactly this, and demo-data.md's templates")
    print("        all show a SINGLE association per row — seeding from them leaves the")
    print("        second one null and the claim fails on data you just created.")
print()

# ── 4. Journeys that declare no seeds — deliberate, or an oversight? ────────
if notes:
    print("── 4. DECLARED-NO-SEED (read before seeding on their behalf) " + "─" * 16)
    for jid, n in notes:
        print(f"  {jid}: {n}")
    print()

# ── Verdict ─────────────────────────────────────────────────────────────────
print("=" * 78)
if ident_gap or seed_gap or row_gap:
    print("VERDICT: FIXTURE SHORT — see the GAP/FAULT rows above.")
    print()
    print("Before seeding, answer the questions the derivation CANNOT: which rows exist")
    print("is measurable, but whether a missing grant is a fixture defect or an app")
    print("defect is a decision. Take it to the user (fixture-seeding.md §4).")
    sys.exit(1)
print("VERDICT: FIXTURE SUFFICIENT — every declared precondition resolved.")
print("Note this proves the preconditions exist, not that the app is correct.")
sys.exit(0)
PY
