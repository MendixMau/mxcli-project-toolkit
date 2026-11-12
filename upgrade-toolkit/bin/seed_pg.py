#!/usr/bin/env python3
"""Seed every persistent entity of a Mendix app on PostgreSQL with N synthetic objects, plus association pairs.

Generic: driven only by the runtime's own mapping tables (mendixsystem$entity, $attribute, $association,
$entityidentifier). No model access needed. Purpose: give a data-survival upgrade test something to survive.
Values are synthetic ("s<short>x<seq>", unique per entity even across specializations that share a unique
column such as System.User.Name; 1000+seq, fixed dates). Hashed-string columns stay NULL (valid "empty").

Enumerations (T6R-13): valid enum values are not in the database, they are in the model. With --mpr <App.mpr> an enum
column gets the enumeration's FIRST value (read with mprmodel.py); without it, or for an enum attribute the model does not
name, the column stays NULL and the summary says how many and which, so an empty enum is never silent (a NULL status
emptied the T6R DepartmentManager dashboard; batch 1 and T6R both needed a hand-written enumfill.py).
FileDocuments (T6R-13): a seeded FileDocument row has no file in the runtime's file store; a page that shows it throws
FileNotFoundInStorageException (T6R DepartmentManager home, fixed by hand with "delete department images"). Objects of
System.FileDocument and every specialization (System.Image, ...) are therefore NOT seeded by default and are named in
the summary; --with-filedocuments seeds them anyway (rows with hascontents=false), for a test that needs the rows.

Run it with the app STOPPED (the runtime caches id sequences), then start the app again.

  seed_pg.py --psql "docker exec -i mig-pg psql -U mendix -d mydb" [--mpr app/App.mpr] [--per-entity 3] [--skip-module M]
             [--per-entity-override Module.Entity=N] [--seed-singletons] [--seed-system] [--with-filedocuments] [--dry-run]

Never seeded unless asked (N3-7, T7-9, T7R-3, T6-3: junk rows broke the baseline start or the old app's admin login):
 - System module objects and associations (Language, UserRole, Session, ChangeHash, TaskQueueToken ...: the runtime
   owns them; a seeded System.Language made the old app fail to start). --skip-module ADDS to this; --seed-system lifts it.
 - singletons: an entity whose own table holds exactly 1 row when the seed runs (run it after the first start), such
   as a configuration object read with "retrieve first"; seeding more made the admin login fail with "multiple
   instances". Listed on stderr as "singleton: ...". Specializations of System entities (Account, images) are never
   singletons: a fresh app holds exactly one admin Account. --seed-singletons lifts it.
 --per-entity-override Module.Entity=N (repeatable) sets the count for one entity and wins over both rules.

Mendix object id = (short_id << 48) | sequence; object_sequence is the NEXT id the runtime hands out (inclusive: BT-5, TOUR 9.4: ids 2..6 seeded and object_sequence 6 made the first create collide on id 6), so it is set one past the last seeded id.
A specialization gets one row per inheritance level with the same id; the root table's submetaobjectname = leaf entity.
The mapping is read through pgmap.py (E2E-9: one reader for seeding and the journey data rungs). Association storage
comes from the mapping row, never from the column name alone: a row pgmap cannot place (table and column storage
disagree) is skipped with a warning, not seeded on a guess.
"""
import argparse, os, shlex, subprocess, sys, uuid

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pgmap


def q(psql, sql):
    r = subprocess.run(shlex.split(psql) + ["-tA", "-F", "\t", "-v", "ON_ERROR_STOP=1"], input=sql, capture_output=True, text=True)
    if r.returncode: sys.exit(f"psql failed: {r.stderr[:2000]}")
    return [l.split("\t") for l in r.stdout.splitlines() if l]


def lit(v):
    return "NULL" if v is None else "'" + str(v).replace("'", "''") + "'"


def enum_firsts(mpr):
    """{(Module.Entity, Attribute): first enumeration value} from the model (T6R-13)."""
    import mprmodel
    m = mprmodel.Model.load(mpr)
    dicts = lambda x: [v for v in (x or []) if isinstance(v, dict)]
    first = {d.qn: next((v.get("Name") for v in dicts(d.data.get("Values")) if v.get("Name")), None)
             for d in m.of_type("Enumerations$Enumeration")}
    out = {}
    for d in [x for x in m.docs.values() if x.type == "DomainModels$DomainModel"]:
        for e in dicts(d.data.get("Entities")):
            for at in dicts(e.get("Attributes")):
                t = at.get("NewType") or at.get("Type") or {}
                if isinstance(t, dict) and t.get("$Type", "").endswith("EnumerationAttributeType"):
                    out[(f"{d.module}.{e.get('Name')}", at.get("Name"))] = first.get(t.get("Enumeration"))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--psql", required=True)
    ap.add_argument("--per-entity", type=int, default=3)
    ap.add_argument("--skip-module", action="append", default=[], help="do not create leaf objects of this module (ancestors still filled); System is always skipped")
    ap.add_argument("--per-entity-override", action="append", default=[], metavar="Module.Entity=N", help="objects for one entity (wins over the skip rules)")
    ap.add_argument("--seed-singletons", action="store_true", help="also seed entities that hold exactly 1 row")
    ap.add_argument("--seed-system", action="store_true", help="also seed System module objects and associations")
    ap.add_argument("--keep-system-user", action="store_true", default=True)
    ap.add_argument("--mpr", help="the app's .mpr: enum columns get the enumeration's first value (else NULL, reported)")
    ap.add_argument("--with-filedocuments", action="store_true", help="also seed FileDocument specializations (rows without files)")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    skip = set(a.skip_module) | (set() if a.seed_system else {"System"})
    psql, n = a.psql, a.per_entity
    override = {}
    for o in a.per_entity_override:
        k, _, v = o.rpartition("=")
        if not k or not v.isdigit(): sys.exit(f"--per-entity-override wants Module.Entity=N, got {o!r}")
        override[k] = int(v)

    try:
        ents = pgmap.entities(psql)
        ident = {r[0]: [int(r[1]), int(r[2])] for r in q(psql, 'select id, short_id, object_sequence from "mendixsystem$entityidentifier"')}
        attrs = pgmap.attributes(psql)
        cols = pgmap.columns(psql)
        assocs = pgmap.associations(psql, ents)
    except pgmap.PsqlError as e:
        sys.exit(f"psql failed: {str(e)[:2000]}")

    def chain(eid):  # leaf .. root
        out = []
        while eid and eid in ents:
            out.append(eid); eid = ents[eid]["super"]
        return out

    enums = {}
    if a.mpr:
        if not os.path.isfile(a.mpr): sys.exit(f"seed_pg: --mpr {a.mpr}: no such file")
        enums = enum_firsts(a.mpr)
    enum_null, enum_set = set(), set()
    fd_root = next((k for k, e in ents.items() if e["name"] == "System.FileDocument"), None)
    fd_skipped = []
    unknown = sorted(set(override) - {e["name"] for e in ents.values()})
    if unknown: sys.exit(f"--per-entity-override: no such persistent entity: {', '.join(unknown)}")

    def count_for(eid):
        e = ents[eid]
        if e["name"] in override: return override[e["name"]]
        return 0 if e["name"].split(".")[0] in skip else n

    # singletons: entities about to be seeded whose own table holds exactly 1 row (one query, -- rowcounts marks it)
    single = set()
    if not a.seed_singletons:
        cand = [eid for eid, e in ents.items() if eid in ident and e["name"] not in override and count_for(eid)
                and e["table"] in cols and ents[chain(eid)[-1]]["name"].split(".")[0] != "System"]  # users, files: never
        if cand:
            sql = "-- rowcounts\n" + "\nunion all\n".join(f'select {lit(eid)}, count(*) from "{ents[eid]["table"]}"' for eid in cand) + ";"
            single = {r[0] for r in q(psql, sql) if r[0] in cand and r[1] == "1"}
        for eid in sorted(single, key=lambda x: ents[x]["name"]):
            print(f"singleton: {ents[eid]['name']} holds 1 row: not seeded (--seed-singletons or --per-entity-override to seed it)", file=sys.stderr)

    def val(typ, length, seq, col, short=0):
        if typ == 0 or typ == 3: return 1000 + seq           # autonumber, integer
        if typ == 4: return 100000 + seq                     # long
        if typ == 5: return f"{seq}.25"                       # decimal
        if typ == 10:                                         # boolean; never make a synthetic user anonymous (runtimes clean those up at startup)
            return "false" if col in ("isanonymous", "blocked", "webserviceuser") else ("true" if seq % 2 else "false")
        if typ == 20: return f"2025-01-{1 + seq % 28:02d} 10:00:00"
        if typ == 30:
            if "password" in col: return None                 # hashed strings: leave empty
            if col == "__uuid__": return str(uuid.uuid4())    # file UUIDs must be unique across ALL FileDocument specializations
            s = f"s{short}x{seq}"                              # unique across entities (two User specializations both had "s2")
            return s[-length:] if length and len(s) > length else s
        return None                                           # 40 enum: set from --mpr in the row loop; 50 binary: NULL

    stmts, created, seq_by_leaf = [], {}, {}
    for eid, e in ents.items():
        cnt = count_for(eid) if e["name"] in override or eid not in single else 0
        if not cnt or eid not in ident: continue
        if fd_root and fd_root in chain(eid) and not a.with_filedocuments:
            fd_skipped.append(e["name"]); continue
        short, seq0 = ident[eid]
        ids = []
        for k in range(cnt):
            seq = seq0 + 1 + k
            oid = (short << 48) | seq
            ids.append(oid)
            levels = list(reversed(chain(eid)))                # root first (FKs point upwards)
            for lv in levels:
                t = ents[lv]["table"]
                row = {"id": oid}
                if lv == levels[0] and "submetaobjectname" in cols.get(t, ()): row["submetaobjectname"] = e["name"]
                for name, col, typ, length in attrs.get(lv, []):
                    if col in cols.get(t, ()) and col not in ("id", "submetaobjectname"):  # System.User/FileDocument expose submetaobjectname as an attribute; never overwrite it
                        v = val(typ, length, seq, col, short)
                        if typ == 40:
                            v = enums.get((ents[lv]["name"], name))
                            (enum_null if v is None else enum_set).add(f'{ents[lv]["name"]}.{name}')
                        if v is not None: row[col] = v
                if t == "system$filedocument":
                    row.update({k2: v2 for k2, v2 in {"hascontents": "false", "size": -1, "deleteafterdownload": "false"}.items() if k2 in cols.get(t, ())})
                stmts.append(f'INSERT INTO "{t}" ({", ".join(chr(34) + c + chr(34) for c in row)}) VALUES ({", ".join(lit(v) for v in row.values())});')
        created[eid] = ids
        stmts.append(f'UPDATE "mendixsystem$entityidentifier" SET object_sequence = {seq0 + cnt + 1} WHERE id = {lit(eid)};')

    # objects usable on each side of an association: own objects plus objects of any specialization
    def objs(eid):
        out = list(created.get(eid, []))
        for other, ids in created.items():
            if other != eid and eid in chain(other): out += ids
        return out

    npairs = 0
    for A in assocs:
        name, table, pid, cid, pcol, ccol = A["name"], A["table"], A["parent"], A["child"], A["pcol"], A["ccol"]
        if name.split(".")[0] in skip: continue
        if A["storage"] is None:
            print(f"seed_pg: association {name} not seeded: {A['why']}", file=sys.stderr); continue
        P, C = objs(pid), objs(cid)
        if not P or not C: continue
        if A["storage"] == "column":                           # column storage: FK column on the owner's table
            for i, p in enumerate(P[:n]):
                stmts.append(f'UPDATE "{table}" SET "{ccol}" = {C[i % len(C)]} WHERE id = {p};'); npairs += 1
        else:
            for i in range(min(n, len(P))):
                c = C[(i + (1 if pid == cid else 0)) % len(C)]
                stmts.append(f'INSERT INTO "{table}" ("{pcol}", "{ccol}") VALUES ({P[i]}, {c}) ON CONFLICT DO NOTHING;'); npairs += 1

    sql = "BEGIN;\n" + "\n".join(stmts) + "\nCOMMIT;\n"
    print(f"entities seeded: {len(created)}, objects: {sum(map(len, created.values()))}, association pairs: {npairs}, statements: {len(stmts)}", file=sys.stderr)
    print(f"enum columns with a value from the model: {len(enum_set)}" + (f"; LEFT NULL: {len(enum_null)} ({', '.join(sorted(enum_null))})"
          + ("" if a.mpr else ": pass --mpr <App.mpr>") if enum_null else ""), file=sys.stderr)
    if fd_skipped:
        print(f"FileDocument entities NOT seeded (no file in the file store; --with-filedocuments to seed rows anyway): "
              f"{len(fd_skipped)} ({', '.join(sorted(fd_skipped))})", file=sys.stderr)
    if a.dry_run: print(sql); return
    q(psql, sql)
    print("seed committed", file=sys.stderr)


if __name__ == "__main__":
    main()
