#!/usr/bin/env python3
"""fakepsql.py: answer seed_pg.py's mapping-table queries from a JSON fixture, so its SQL can be checked without Postgres.

  fakepsql.py fixture.json [psql args ignored]     reads one SQL statement on stdin, prints tab-separated rows

fixture: {"entities": [[id, name, table, super_id|null], ...], "identifiers": [[id, short_id, seq], ...],
          "attributes": [[entity_id, name, column, type, length], ...], "columns": [[table, column], ...],
          "associations": [[name, table, parent_id, child_id, parent_col, child_col], ...],
          "usercounts": [[submetaobjectname, n], ...],   (smoke_users.py: rows of system$user per entity)
          "rowcounts": [[entity_id, rows], ...]}   answers the "-- rowcounts" singleton query (default: none)
"""
import json, sys

fx = json.load(open(sys.argv[1]))
sql = sys.stdin.read()
if "group by" in sql and 'system$user"' in sql:   # smoke_users.py: users per entity
    for r in fx.get("usercounts", []): print("\t".join(str(v) for v in r))
    sys.exit(0)
for key, marker in (("rowcounts", "-- rowcounts"), ("entities", "mendixsystem$entity\""), ("identifiers", "mendixsystem$entityidentifier"),
                    ("attributes", "mendixsystem$attribute"), ("columns", "information_schema.columns"),
                    ("associations", "mendixsystem$association")):
    if marker in sql and not (key == "entities" and "entityidentifier" in sql):
        for r in fx.get(key, []):
            print("\t".join("" if v is None else str(v) for v in r))
        break
