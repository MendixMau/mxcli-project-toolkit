#!/usr/bin/env python3
"""rebase_dates.py: move every date of a seeded database forward so the newest one is "a few hours ago".

    rebase_dates.py --psql "docker exec -i mig-pg psql -U mendix -d X_seed" [--anchor 'inspection$inspection.createdon'] [--hours-ago 6] [--apply]

Why: a publisher snapshot (data-snapshot.zip) is dated the day it was exported. Pages that say "this week", "last 30 days",
"overdue" then show 0 / everything-overdue, and no status that depends on a date can be reached (Visual Inspection: "Defects this
week 0", "Inspections this week 0" on the manager dashboard, on a database that holds 84 defects). One uniform shift keeps every
gap between dates (an inspection is still before its defects), so the story stays consistent.
Shifts every timestamp column of every non-System, non-mendixsystem table by the same interval. Without --apply it prints the
interval and the columns. Run on a COPY, with the app stopped.
"""
import argparse, shlex, subprocess, sys

ap = argparse.ArgumentParser()
ap.add_argument("--psql", required=True); ap.add_argument("--anchor"); ap.add_argument("--hours-ago", type=float, default=6)
ap.add_argument("--apply", action="store_true")
a = ap.parse_args()

def q(sql):
    r = subprocess.run(shlex.split(a.psql) + ["-X", "-tA", "-F", "|", "-v", "ON_ERROR_STOP=1"], input=sql, capture_output=True, text=True)
    if r.returncode: sys.exit("psql: " + r.stderr[:400])
    return [l.split("|") for l in r.stdout.splitlines() if l]

cols = q("select table_name, column_name from information_schema.columns where table_schema='public' and data_type like 'timestamp%' "
         "and table_name not like 'system$%' and table_name not like 'mendixsystem$%' order by 1,2")
if not cols: sys.exit("rebase_dates: no timestamp columns")
if a.anchor: at, ac = a.anchor.rsplit(".", 1); mx = q(f'select max("{ac}") from "{at}"')[0][0]
else:
    mx = max(r[0] for r in (q(f'select max("{c}") from "{t}"')[0] for t, c in cols) if r)
delta = q(f"select extract(epoch from (now() - interval '{a.hours_ago} hours' - timestamp '{mx}'))::bigint")[0][0]
print(f"newest value {mx}; shift {int(delta)//86400} days {int(delta)%86400//3600} hours; {len(cols)} columns in {len({t for t, _ in cols})} tables", file=sys.stderr)
if int(delta) <= 0: print("nothing to do: the newest value is already after the target", file=sys.stderr); sys.exit(0)
sql = "BEGIN;\n" + "\n".join(f'UPDATE "{t}" SET "{c}" = "{c}" + interval \'{delta} seconds\' WHERE "{c}" IS NOT NULL;' for t, c in cols) + "\nCOMMIT;\n"
if not a.apply: print(sql); sys.exit(0)
q(sql); print("rebased", file=sys.stderr)
