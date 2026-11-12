#!/usr/bin/env python3
"""capture_units.py: cut a golden fixture out of a REAL Mendix model, and build a v1 .mpr back from it (E2E-8).

The field-proof rule: golden input is captured, never hand-written -- hand-written units encode the assumption the
code makes. mkmodel.py builds synthetic models from a spec; this script instead copies chosen units verbatim from a
real .mpr (v1 or v2), with their module and folder chain, so a control runs on the shapes Studio Pro wrote.

  capture_units.py capture <model.mpr> <out.json> --doc QN ... [--stub QN ...] [--singleton $Type ...]
  capture_units.py build <fixture.json> <out dir>          writes <out dir>/App.mpr (MPR v1, Contents column)

--doc       a document copied whole (minus the PRUNED keys below)
--stub      a document cut to its header: $Type, Name, Excluded, AllowedRoles/AllowedModuleRoles, Parameters -- a
            page a fixture must hold (its roles, its parameters) but whose widgets are not under test
--singleton a project-level unit by $Type (Navigation$NavigationDocument, Security$ProjectSecurity, ...)
PRUNED keys hold presentation only (styling, tooltips, documentation, images) and are dropped everywhere, which keeps a
fixture small; nothing is added or edited (captions stay: a click path names its menu item by caption). Only Marketplace templates may be
captured into this repo (controls/run-controls.sh header: Marketplace and System names only).
"""
import argparse, json, os, sqlite3, sys
from pathlib import Path

import bson
from bson import json_util

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "bin"))
import mprmodel  # noqa: E402

PRUNED = {"Appearance", "Tooltip", "Documentation", "Image", "DesignProperties"}
HEADER = ("$ID", "$Type", "Name", "Excluded", "AllowedRoles", "AllowedModuleRoles", "Parameters", "ExportLevel")


def prune(x):
    if isinstance(x, dict):
        out = {}
        for k, v in x.items():
            if k in PRUNED:
                continue
            out[k] = prune(v)
        return out
    if isinstance(x, list):
        return [prune(v) for v in x]
    return x


def capture(a):
    m = mprmodel.Model.load(a.model)
    by_qn = {}
    for uid, (cid, cname, d) in m.units.items():
        name = d.get("Name")
        if name and d.get("$Type") not in ("Projects$Folder", "Projects$ModuleImpl", "Projects$Module"):
            mod, _ = m._module_of(uid)
            if mod:
                by_qn.setdefault(f"{mod}.{name}", uid)
    keep, missing = {}, []
    for qn, stub in [(q, False) for q in a.doc] + [(q, True) for q in a.stub]:
        uid = by_qn.get(qn)
        if uid is None:
            missing.append(qn)
            continue
        cid, cname, d = m.units[uid]
        keep[uid] = (cid, cname, {k: d[k] for k in HEADER if k in d} if stub else d)
        cur, seen = cid, set()
        while cur and cur in m.units and cur not in keep and cur not in seen:  # folder + module chain (the project
            seen.add(cur)                                                     # unit contains itself in v1 files)
            pc, pn, pd = m.units[cur]
            t = pd.get("$Type", "")
            if t in ("Projects$Folder", "Projects$ModuleImpl", "Projects$Module"):
                keep[cur] = (pc, pn, {k: pd[k] for k in ("$ID", "$Type", "Name", "AppStoreVersion", "FromAppStore",
                                                         "AppStorePackageId") if k in pd})
                if t != "Projects$Folder":
                    break
            cur = pc
    for t in a.singleton:
        hit = [u for u, (_, _, d) in m.units.items() if d.get("$Type") == t]
        if not hit:
            missing.append(t)
        for u in hit:
            cid, cname, d = m.units[u]
            keep[u] = (cid, cname, d)
    if missing:
        sys.exit("capture_units: not in the model: " + ", ".join(missing))
    units = [{"uid": u.hex(), "container": (c.hex() if c else None), "containment": n, "data": prune(d)}
             for u, (c, n, d) in sorted(keep.items())]
    out = {"source": os.path.basename(a.model), "captured_by": "controls/lib/capture_units.py", "pruned": sorted(PRUNED),
           "stubs": sorted(a.stub), "units": units}
    opts = json_util.JSONOptions(json_mode=json_util.JSONMode.CANONICAL)
    head = {k: v for k, v in out.items() if k != "units"}
    lines = [json_util.dumps(u, sort_keys=True, json_options=opts) for u in units]  # one unit per line: diffable
    Path(a.out).write_text(json_util.dumps(head, sort_keys=True, json_options=opts)[:-1] + ', "units": [\n'
                           + ",\n".join(lines) + "\n]}\n")
    print(f"captured {len(units)} units ({len(a.doc)} docs, {len(a.stub)} stubs, {len(a.singleton)} singleton types)"
          f" -> {a.out}")


def build(a):
    fx = json_util.loads(Path(a.fixture).read_text())
    os.makedirs(a.outdir, exist_ok=True)
    path = os.path.join(a.outdir, "App.mpr")
    if os.path.exists(path):
        os.remove(path)
    con = sqlite3.connect(path)
    con.execute("create table Unit (UnitID blob primary key, ContainerID blob, ContainmentName text, TreeConflict int,"
                " ContentsHash text, ContentsConflicts text, Contents blob)")
    con.execute("create table _MetaData (_ProductVersion text, _BuildVersion text, _SchemaHash text)")
    for u in fx["units"]:
        con.execute("insert into Unit (UnitID, ContainerID, ContainmentName, Contents) values (?, ?, ?, ?)",
                    (bytes.fromhex(u["uid"]), bytes.fromhex(u["container"]) if u["container"] else None,
                     u["containment"], bson.encode(u["data"])))
    con.commit()
    con.close()
    print(path)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("capture")
    c.add_argument("model"); c.add_argument("out")
    c.add_argument("--doc", nargs="*", default=[]); c.add_argument("--stub", nargs="*", default=[])
    c.add_argument("--singleton", nargs="*", default=[])
    b = sub.add_parser("build")
    b.add_argument("fixture"); b.add_argument("outdir")
    a = ap.parse_args()
    capture(a) if a.cmd == "capture" else build(a)


if __name__ == "__main__":
    main()
