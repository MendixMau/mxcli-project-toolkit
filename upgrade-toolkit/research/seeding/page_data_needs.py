#!/usr/bin/env python3
"""page_data_needs.py: which pages show lists / grids of which entity, under which constraint, for which role.

    python3 -I page_data_needs.py <app.mpr> [--module M ...] [--needs-from <journeys dir>]

For every page, snippet and layout (own modules by default) it walks the widget tree and reports each widget that reads a
data source: widget type + name, the entity it lists (entity ref, or the microflow / association it follows), the
XPath constraint (this is what silently empties a list: [Status = 'Open'], [Employee_Account = '[%CurrentUser%]']), and the
page's allowed module roles. With --needs-from (a gen_journeys.py --out-dir) it also prints, per widget name, how many generated
journeys declared "a row in <widget>" (_needs / _path_needs): the widgets whose emptiness the journeys will pay for.
Read-only; same reader as mprmodel.py. Heuristic on the BSON shape: every widget dict that carries a key containing
'DataSource' is reported with the Module.Entity strings found below it.
"""
import argparse, collections, glob, json, os, re, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "bin"))
import mprmodel  # noqa: E402

ENT = re.compile(r"^[A-Z][A-Za-z0-9_]*\.[A-Za-z][A-Za-z0-9_]*$")


def strings(x, out):
    if isinstance(x, dict):
        for k, v in x.items():
            if k in ("$ID", "$Type"): continue
            strings(v, out)
    elif isinstance(x, list):
        for v in x: strings(v, out)
    elif isinstance(x, str):
        out.append(x)


def walk(x, hits, path=""):
    if isinstance(x, dict):
        name = x.get("Name")
        typ = (x.get("$Type") or "").split("$")[-1]
        keys = [k for k in x if "datasource" in k.lower() or "datasource" in str(k).lower()]
        for k in keys:
            ds = x[k]
            if isinstance(ds, dict):
                s = []; strings(ds, s)
                dst = (ds.get("$Type") or "").split("$")[-1]
                xp = [t for t in s if t.startswith("[") or " = " in t or "[%" in t]
                hits.append((typ, name, dst, [t for t in s if ENT.match(t)][:4], xp[:2]))
        # pluggable widgets keep the source in Object.Properties[...].Value.DataSource
        for v in x.values(): walk(v, hits)
    elif isinstance(x, list):
        for v in x: walk(v, hits)


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("project"); ap.add_argument("--module", action="append"); ap.add_argument("--needs-from")
    a = ap.parse_args()
    m = mprmodel.Model.load(a.project)
    mods = set(a.module or [n for n, v in m.modules.items() if not v.get("from_appstore")])
    needs = collections.Counter()
    if a.needs_from:
        for f in glob.glob(os.path.join(a.needs_from, "journeys", "*", "*.json")):
            d = json.load(open(f))
            for x in d.get("_needs", []) + d.get("_path_needs", []):
                needs[re.sub(r"^a row in (\S+ )?(\S+).*", r"\2", x) if isinstance(x, str) else str(x)] += 1
    for d in sorted(m.docs.values(), key=lambda x: x.qn):
        if d.type not in ("Forms$Page", "Forms$Snippet", "Forms$Layout") or d.module not in mods: continue
        hits = []; walk(d.data, hits)
        if not hits: continue
        roles = d.data.get("AllowedRoles") or []
        rl = ",".join(r.split(".")[-1] for r in roles if isinstance(r, str))
        print("\n%s  [%s]%s" % (d.qn, d.type.split("$")[-1], ("  roles: " + rl) if rl else ""))
        seen = set()
        for typ, name, dst, ents, xp in hits:
            key = (name, dst, tuple(ents), tuple(xp))
            if key in seen: continue
            seen.add(key)
            n = needs.get(name or "", 0)
            print("  - %s %s: %s %s%s%s" % (typ, name, dst, ",".join(ents), ("  XPATH " + " | ".join(xp)) if xp else "", ("   <- needed by %d journeys" % n) if n else ""))


if __name__ == "__main__":
    main()
