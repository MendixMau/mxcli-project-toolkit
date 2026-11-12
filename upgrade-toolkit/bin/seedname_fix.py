#!/usr/bin/env python3
"""seedname_fix.py: make a synthetic seeded value that is USED AS A MODEL NAME a real model name (steps/heal.md, class
test-setup, heal kind seedname).

Why: seed_pg.py fills every String column with "s<short>x<seq>". Some String attributes of an app are not data but
configuration: the name of an entity, of a member, of a microflow. A page that reads such a value (a Data widgets Combo
box whose option source does Core.getMetaObject(<value>)) raises "Entity does not exist: s294x2". The old client only
called the option source when the dropdown opened, the newer one calls it when the page opens, so the same junk
that never mattered on the old app now shows an error dialog on page open of the new app. That is a test-data cause
exposed by a real behaviour change, not broken app logic. The heal makes the value valid on BOTH sides.

  seedname_fix.py --psql "docker exec -i mig-pg psql -U mendix -d DB" --value s294x2 [--value ...]
                  [--entity System.User] [--set Table.column=VALUE ...] [--set-file F] [--dry-run]

For each --value: every persistent String attribute whose NAME says "entity" and that holds it is a "holder" (found through
pgmap.py, the runtime's own mapping, no model access; a seeded value is the same in every String column of one row, so the
name is what tells an entity name from the rest). In the holder's table, every value that looks seeded (^s<digits>x<digits>$) in the holder
column becomes the entity name (--entity, default System.User, must exist in the mapping), and in the same table every
seeded value of a String attribute whose name contains "member" or "attribute" becomes a persistent String attribute of
that entity ("Name" when it has one). --set Table.column=VALUE (or lines "table.column = value  # reason" in --set-file)
overrides a column explicitly; the explicit rule wins. Nothing else is touched. The summary lists every column and the
number of rows, so the heal is never silent. Run it on a COPY of the frozen database, with the app stopped.
Exit: 0 done (also when no holder was found, said on stderr); 1 bad argument; 2 psql failed.
"""
import argparse, os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pgmap

SEEDED = r"^s[0-9]+x[0-9]+$"
STRING = 30


def lit(v):
    return "'" + str(v).replace("'", "''") + "'"


def read_set_file(path):
    out = []
    for line in open(path, errors="replace"):
        line = line.split("#", 1)[0].strip()
        if line:
            out.append(line)
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--psql", required=True)
    ap.add_argument("--value", action="append", default=[], help="a seeded value an error named (repeatable)")
    ap.add_argument("--entity", default="System.User", help="the real entity name the holder gets (default System.User)")
    ap.add_argument("--set", action="append", default=[], metavar="Table.column=VALUE")
    ap.add_argument("--set-file", help="lines 'table.column = value  # reason'")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    explicit = {}
    for s in a.set + (read_set_file(a.set_file) if a.set_file and os.path.isfile(a.set_file) else []):
        k, _, v = s.partition("=")
        k, v = k.strip(), v.strip()
        if "." not in k or not v:
            print(f"seedname_fix: --set wants table.column=VALUE, got {s!r}", file=sys.stderr)
            return 1
        explicit[tuple(k.rsplit(".", 1))] = v
    bad = [v for v in a.value if not re.match(SEEDED, v)]
    if bad:
        print(f"seedname_fix: not a seeded value (s<digits>x<digits>): {', '.join(bad)}; refusing to touch other data", file=sys.stderr)
        return 1
    if not a.value and not explicit:
        print("seedname_fix: nothing to do (no --value, no --set)", file=sys.stderr)
        return 1
    try:
        ents = pgmap.entities(a.psql)
        attrs = pgmap.attributes(a.psql)
        cols = pgmap.columns(a.psql)
        tgt = next((k for k, e in ents.items() if e["name"] == a.entity), None)
        if not tgt:
            print(f"seedname_fix: entity {a.entity} is not in the mapping tables", file=sys.stderr)
            return 1
        # attributes of the target, own and inherited (System.User inherits nothing, an app entity may)
        tattrs, e = [], tgt
        while e and e in ents:
            tattrs += [x for x in attrs.get(e, []) if x[2] == STRING and "password" not in x[1]]
            e = ents[e]["super"]
        member = next((x[0] for x in tattrs if x[0] == "Name"), tattrs[0][0] if tattrs else None)
        stmts, report = [], []

        def upd(table, col, new, why):
            ids = [r[0] for r in pgmap.q(a.psql, f'select id, "{col}" from "{table}"', timeout=300) if len(r) > 1 and re.match(SEEDED, r[1])]
            if ids:
                stmts.append(f'UPDATE "{table}" SET "{col}" = {lit(new)} WHERE id IN ({", ".join(ids)});')
                report.append(f"{table}.{col}: {len(ids)} row(s) -> {new} ({why})")

        done = set()
        for v in a.value:
            holders = []
            for eid, e in ents.items():
                if e["table"] not in cols:
                    continue
                for name, col, typ, _ in attrs.get(eid, []):
                    if typ == STRING and col in cols[e["table"]]:
                        holders.append((eid, e, name, col))
            if not holders:
                continue
            sql = "\nunion all\n".join(f"select {lit(e['table'])}, {lit(col)}, count(*) from \"{e['table']}\" where \"{col}\" = {lit(v)}"
                                       for _, e, _, col in holders) + ";"
            hit = {(r[0], r[1]) for r in pgmap.q(a.psql, sql, timeout=300) if r[2] != "0"}
            if not hit:
                print(f"seedname_fix: no String column holds {v}: nothing healed for it", file=sys.stderr)
            for eid, e, name, col in holders:
                if (e["table"], col) not in hit or (e["table"], col) in done:
                    continue
                if not re.search(r"entity", name, re.I) and (e["table"], col) not in explicit:
                    # a synthetic value is the same in every String column of a row: only an attribute whose NAME says entity is an entity name
                    print(f"seedname_fix: {e['table']}.{col} also holds {v} but its name does not say entity: not changed (--set to change it)", file=sys.stderr)
                    continue
                done.add((e["table"], col))
                if (e["table"], col) not in explicit:
                    upd(e["table"], col, a.entity, f"holds {v}, which an error named as an entity")
                for n2, c2, t2, _ in attrs.get(eid, []):
                    if t2 == STRING and c2 != col and c2 in cols[e["table"]] and re.search(r"member|attribute", n2, re.I) \
                            and (e["table"], c2) not in explicit and member and (e["table"], c2) not in done:
                        done.add((e["table"], c2))
                        upd(e["table"], c2, member, f"same row as {name}: a member of {a.entity}")
        for (table, col), val in explicit.items():
            if table not in cols or col not in cols[table]:
                print(f"seedname_fix: --set {table}.{col}: no such table or column", file=sys.stderr)
                return 1
            upd(table, col, val, "explicit --set")
        if not stmts:
            print("seedname_fix: no seeded rows changed", file=sys.stderr)
            return 0
        sql = "BEGIN;\n" + "\n".join(stmts) + "\nCOMMIT;\n"
        for r in report:
            print("seedname_fix: " + r, file=sys.stderr)
        if a.dry_run:
            print(sql)
            return 0
        pgmap.q(a.psql, sql, timeout=300)
        print(f"seedname_fix: committed {len(stmts)} update(s)", file=sys.stderr)
        return 0
    except pgmap.PsqlError as ex:
        print(f"seedname_fix: psql failed: {str(ex)[:600]}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
