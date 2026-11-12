#!/usr/bin/env python3
"""setup_sql.py: apply the app's test-setup rows (work/test-setup.sql) to a database copy, the same file for the old and the new app.

Why: some pages need a row the app itself creates in real use (a per-user settings row written at the first sign-in through an
identity provider, a station id) and the test users are made by smoke_users.py, so the row never exists in a test copy. The
journeys then fail on the old app for a setup reason. The row goes in here, on both sides, never into the frozen baseline.

Rules for the file: plain SQL, one transaction, safe on a fresh copy of the frozen database; take ids as max(id)+n of the same table
(the id prefix of the entity stays right); say in a comment why each row exists. It is test data: the report lists it as such.

  setup_sql.py --psql 'docker exec -i mig-pg psql -U mendix -d DB' --file work/test-setup.sql
Exit: 0 applied (or no file), 1 failed, 2 usage.
"""
import argparse, shlex, subprocess, sys
from pathlib import Path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--psql", required=True)
    ap.add_argument("--file", required=True)
    a = ap.parse_args()
    f = Path(a.file)
    if not f.is_file():
        print(f"setup_sql: no {f}, nothing to apply")
        return 0
    r = subprocess.run(shlex.split(a.psql) + ["-v", "ON_ERROR_STOP=1", "-1", "-q"], input=f.read_text(), capture_output=True, text=True)
    if r.returncode != 0:
        print(f"setup_sql: failed:\n{r.stdout[-400:]}{r.stderr[-600:]}", file=sys.stderr)
        return 1
    print(f"setup_sql: applied {f.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
