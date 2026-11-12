#!/usr/bin/env python3
"""sqlitepsql.py: a psql stand-in on SQLite for the pgmap.py / pgdata.js controls (E2E-9), so the data instrument is
checked without Postgres or Docker.

  sqlitepsql.py DB.sqlite [--init file.sql] [psql args ignored]    one SQL text on stdin -> psql -tA style rows

What it covers of psql: tab-separated rows (-tA -F '\\t'), exit 3 with "ERROR: ..." on stderr for a failing statement
(ON_ERROR_STOP), information_schema.columns from the SQLite schema, and the SELECT row_to_json(q) FROM (...) q wrapper
pgmap.py puts around a query (one JSON object per row). Anything else is run by SQLite as written; a text that is not a
SELECT is run as a script and committed (the engine control's "the app wrote a row").
"""
import json, re, sqlite3, sys

db = sqlite3.connect(sys.argv[1])
if len(sys.argv) > 3 and sys.argv[2] == "--init":
    db.executescript(open(sys.argv[3]).read()); db.commit(); sys.exit(0)
sql = sys.stdin.read().strip().rstrip(";").strip()
out = []
try:
    if "information_schema.columns" in sql:
        for (t,) in db.execute("select name from sqlite_master where type='table'"):
            out += [[t, c[1]] for c in db.execute(f'pragma table_info("{t}")')]
    elif (m := re.fullmatch(r"SELECT row_to_json\(q\) FROM \((.*)\) q", sql, re.S)):
        cur = db.execute(m.group(1))
        names = [d[0] for d in cur.description]
        out = [[json.dumps(dict(zip(names, r)))] for r in cur]
    elif re.match(r"(?is)\s*(select|with)\b", sql):
        out = [["" if v is None else v for v in r] for r in db.execute(sql)]
    else:
        db.executescript(sql + ";"); db.commit()
except sqlite3.Error as e:
    print(f"ERROR:  {e}", file=sys.stderr); sys.exit(3)
for r in out:
    print("\t".join(str(v) for v in r))
