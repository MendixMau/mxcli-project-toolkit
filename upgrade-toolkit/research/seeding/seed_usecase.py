#!/usr/bin/env python3
"""seed_usecase.py: seed a Mendix app (PostgreSQL) from a hand-written use-case spec, not from a row count.

    seed_usecase.py --psql "docker exec -i mig-pg psql -U mendix -d X_seed" --mpr app/App.mpr spec.json [--apply] [--now 2026-10-13]

Where seed_pg.py fills EVERY entity with N synthetic rows ("s7x1002", first enum value), this fills the entities a use case
needs with plausible rows in the states the pages filter on, and links them. Same channel, same id scheme, same mapping
reader (pgmap.py). Run with the app STOPPED, on a database COPY (createdb -T X_frozen X_seed): the spec is not idempotent
on its own, the copy is. Without --apply it prints the SQL.

spec.json:
  {"objects": [
     {"ref": "dep_a", "entity": "Masterdata.Department", "attrs": {"DisplayName": "Assembly line A"}},
     {"ref": "cl1",   "entity": "Checklist_Template.Checklist",
      "attrs": {"Name": "Daily safety walk", "IsActive": true, "RetiredDateTime": null},
      "links": {"Checklist_Department": "dep_a", "Checklist_Employee_Responsible": ["emp1", "emp2"]}}
  ]}
  - entity: the LEAF entity (a specialization gets one row per inheritance level, same id).
  - attrs: by model name; anything left out gets the MODEL default (read from --mpr: Mendix applies defaults in the
    runtime, never in the database, so a raw INSERT without them leaves booleans NULL and enums empty); a required attribute
    (validation rule) with neither value nor default is an ERROR, listed before anything is written.
  - dates: "2026-10-13 09:30:00", or relative to --now (default today): "+2d", "-5d", "-3h", "+1w 08:00".
  - links: {AssociationName: ref | [refs]}; this object is the association's PARENT (the owner of the reference:
    "Defect_Inspection: Defect -> Inspection" is set on the Defect). The short name is looked up in the entity's module first.
  - {"ref": "u_insp", "entity": "Administration.Account", "lookup": {"Name": "smoke_inspector"}} points at an EXISTING row (the
    smoke user of a role, made by smoke_users.py before this runs) so an Employee can be linked to it.
  - never: System.User / Account rows (smoke_users.py hashes passwords), FileDocument / Image specializations (no file
    in the store -> FileNotFoundInStorageException; they are refused here), non-persistent entities.
Exit: 0 ok (printed, or applied), 1 spec error (nothing written), 2 psql / mapping problem.
"""
import argparse, datetime, json, os, re, sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "bin"))
import pgmap, mprmodel  # noqa: E402


def lit(v):
    return "NULL" if v is None else "'" + str(v).replace("'", "''") + "'"


def model_info(mpr):
    """{entity: {"defaults": {attr: default}, "required": {attr}, "enum": {attr}}} from the .mpr."""
    m = mprmodel.Model.load(mpr)
    info = {}
    for d in m.docs.values():
        if d.type != "DomainModels$DomainModel":
            continue
        for e in d.data.get("Entities", [])[1:]:
            if not isinstance(e, dict):
                continue
            qn = d.module + "." + e["Name"]
            req = {str(r.get("Attribute", "")).split(".")[-1] for r in e.get("ValidationRules", [])[1:]
                   if isinstance(r, dict) and "Required" in (r.get("RuleInfo") or {}).get("$Type", "")}
            dflt = {}
            for a in e.get("Attributes", [])[1:]:
                v = a.get("Value") or {}
                if v.get("$Type", "").endswith("StoredValue") and v.get("DefaultValue") not in ("", None):
                    dflt[a["Name"]] = v["DefaultValue"]
            info[qn] = {"defaults": dflt, "required": req}
    return info


def when(s, now):
    if not isinstance(s, str):
        return s
    m = re.fullmatch(r"([+-]\d+)([dhw])(?: (\d\d:\d\d(?::\d\d)?))?", s.strip())
    if not m:
        return s
    n, u, t = int(m.group(1)), m.group(2), m.group(3)
    delta = {"d": datetime.timedelta(days=n), "h": datetime.timedelta(hours=n), "w": datetime.timedelta(weeks=n)}[u]
    dt = now + delta
    if t:
        hh, mm = t.split(":")[:2]
        dt = dt.replace(hour=int(hh), minute=int(mm), second=0)
    return dt.strftime("%Y-%m-%d %H:%M:%S")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("spec")
    ap.add_argument("--psql", required=True)
    ap.add_argument("--mpr", required=True, help="the app's .mpr: defaults and required rules")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--now", help="YYYY-MM-DD base for relative dates (default today)")
    a = ap.parse_args()
    spec = json.load(open(a.spec))
    now = datetime.datetime.strptime(a.now, "%Y-%m-%d").replace(hour=10) if a.now else datetime.datetime.now().replace(microsecond=0)
    try:
        ents = pgmap.entities(a.psql)
        attrs = pgmap.attributes(a.psql)
        cols = pgmap.columns(a.psql)
        assocs = pgmap.associations(a.psql, ents)
        ident = {r[0]: [int(r[1]), int(r[2])] for r in pgmap.q(a.psql, 'select id, short_id, object_sequence from "mendixsystem$entityidentifier"')}
    except pgmap.PsqlError as e:
        print("seed_usecase: " + str(e), file=sys.stderr); sys.exit(2)
    info = model_info(a.mpr)
    by_name = {e["name"]: k for k, e in ents.items()}

    def chain(eid):
        out = []
        while eid and eid in ents:
            out.append(eid); eid = ents[eid]["super"]
        return out

    errors, rows, ids, seqs = [], [], {}, {k: v[1] for k, v in ident.items()}
    for o in spec["objects"]:
        ref, en = o.get("ref"), o.get("entity")
        if en not in by_name:
            errors.append(f"{ref}: no persistent entity {en} in the database mapping"); continue
        eid = by_name[en]
        ch = chain(eid)
        root = ents[ch[-1]]["name"]
        if not o.get("lookup") and (root in ("System.FileDocument", "System.Image") or root == "System.User" or en.startswith("System.")):
            errors.append(f"{ref}: {en} is a System/FileDocument/Image family entity: not seedable here (users: smoke_users.py)"); continue
        if ref in ids:
            errors.append(f"duplicate ref {ref}"); continue
        if o.get("lookup"):                       # an existing row (e.g. the smoke user of a role): not inserted, only linked
            w = o["lookup"]
            joins, conds = [], []
            lv0 = ch[0]
            for lv in ch:
                for (n, c, t, ln) in attrs.get(lv, []):
                    if n in w:
                        a_ = "t%d" % ch.index(lv)
                        if lv != lv0 and a_ not in joins:
                            joins.append(a_)
                        conds.append(f'"{a_}"."{c}" = {lit(w[n])}')
            if len(conds) != len(w):
                errors.append(f"{ref}: lookup attribute not found on {en}"); continue
            frm = f'"{ents[lv0]["table"]}" "t0"' + "".join(f' JOIN "{ents[ch[int(j[1:])]]["table"]}" "{j}" ON "{j}".id = "t0".id' for j in joins)
            try:
                got = pgmap.q(a.psql, f'select "t0".id from {frm} where {" and ".join(conds)}')
            except pgmap.PsqlError as e:
                errors.append(f"{ref}: lookup failed: {str(e)[:200]}"); continue
            if len(got) != 1:
                errors.append(f"{ref}: lookup {w} on {en} matched {len(got)} rows, want 1"); continue
            ids[ref] = (int(got[0][0]), eid)
            continue
        short = ident[eid][0]
        seqs[eid] += 1
        oid = (short << 48) | seqs[eid]
        ids[ref] = (oid, eid)
        given = o.get("attrs", {})
        known = {n: (lv, c, t, ln) for lv in ch for (n, c, t, ln) in attrs.get(lv, [])}
        bad = sorted(set(given) - set(known))
        if bad:
            errors.append(f"{ref}: {en} has no attribute {', '.join(bad)}")
        per_level = {}
        for lv in reversed(ch):
            ename = ents[lv]["name"]
            mi = info.get(ename, {"defaults": {}, "required": set()})
            row = {"id": oid}
            if lv == ch[-1] and "submetaobjectname" in cols.get(ents[lv]["table"], ()):
                row["submetaobjectname"] = en
            for (n, c, t, ln) in attrs.get(lv, []):
                if c not in cols.get(ents[lv]["table"], ()) or c in ("id", "submetaobjectname"):
                    continue
                if n in given:
                    v = given[n]
                elif n in mi["defaults"]:
                    v = mi["defaults"][n]
                elif t == 0:
                    v = seqs[eid]
                else:
                    v = None
                if t == 20:
                    v = when(v, now)
                if t == 10 and isinstance(v, str):
                    v = v.lower() == "true"
                if isinstance(v, bool):
                    v = "true" if v else "false"
                if v is None and n in mi["required"]:
                    errors.append(f"{ref}: required attribute {ename}.{n} has no value and no model default")
                if t == 30 and isinstance(v, str) and ln and len(v) > ln:
                    errors.append(f"{ref}: {ename}.{n} is {len(v)} chars, limit {ln}")
                if v is not None:
                    row[c] = v
            for fixed in ("createddate", "changeddate"):
                if fixed in cols.get(ents[lv]["table"], ()) and fixed not in row:
                    row[fixed] = now.strftime("%Y-%m-%d %H:%M:%S")
            per_level[lv] = row
        for lv in reversed(ch):
            rows.append((ents[lv]["table"], per_level[lv]))
    stmts = []
    for t, row in rows:
        stmts.append(f'INSERT INTO "{t}" ({", ".join(chr(34) + c + chr(34) for c in row)}) VALUES ({", ".join(lit(v) for v in row.values())});')
    # links
    asc = {x["name"]: x for x in assocs}
    nlinks = 0
    for o in spec["objects"]:
        ref = o.get("ref")
        if ref not in ids:
            continue
        oid, eid = ids[ref]
        for an, targets in (o.get("links") or {}).items():
            full = an if "." in an else o["entity"].split(".")[0] + "." + an
            A = asc.get(full) or asc.get(an)
            if not A:
                errors.append(f"{ref}: no association {an}"); continue
            if A["storage"] is None:
                errors.append(f"{ref}: association {A['name']} not seedable: {A['why']}"); continue
            if A["parent"] not in chain(eid):
                errors.append(f"{ref}: {A['name']} is owned by {ents[A['parent']]['name']}, not by {o['entity']} (set it on the other object)"); continue
            for t in (targets if isinstance(targets, list) else [targets]):
                if t not in ids:
                    errors.append(f"{ref}: link target {t} is not a ref"); continue
                cid, ceid = ids[t]
                if A["child"] not in chain(ceid):
                    errors.append(f"{ref}: {A['name']} points at {ents[A['child']]['name']}, {t} is {ents[ceid]['name']}"); continue
                if A["storage"] == "column":
                    stmts.append(f'UPDATE "{A["table"]}" SET "{A["ccol"]}" = {cid} WHERE id = {oid};')
                else:
                    stmts.append(f'INSERT INTO "{A["table"]}" ("{A["pcol"]}", "{A["ccol"]}") VALUES ({oid}, {cid}) ON CONFLICT DO NOTHING;')
                nlinks += 1
    for eid, s in seqs.items():
        if s != ident[eid][1]:
            stmts.append(f'UPDATE "mendixsystem$entityidentifier" SET object_sequence = {s} WHERE id = {lit(eid)};')
    if errors:
        print("seed_usecase: %d error(s), nothing written:" % len(errors), file=sys.stderr)
        for e in errors:
            print("  - " + e, file=sys.stderr)
        sys.exit(1)
    sql = "BEGIN;\n" + "\n".join(stmts) + "\nCOMMIT;\n"
    per = {}
    for o in spec["objects"]:
        per[o["entity"]] = per.get(o["entity"], 0) + 1
    print("seed_usecase: %d objects (%s), %d association pairs, %d statements" % (len(ids), ", ".join(f"{k.split('.')[-1]} {v}" for k, v in sorted(per.items())), nlinks, len(stmts)), file=sys.stderr)
    if not a.apply:
        print(sql); return
    try:
        pgmap.q(a.psql, sql)
    except pgmap.PsqlError as e:
        print("seed_usecase: psql failed: " + str(e), file=sys.stderr); sys.exit(2)
    print("seed committed", file=sys.stderr)


if __name__ == "__main__":
    main()
