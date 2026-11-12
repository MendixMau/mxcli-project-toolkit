#!/usr/bin/env python3
"""idcheck.py: find domain model elements whose runtime identity (GUID) changed between two app versions.

The Mendix runtime maps tables, columns and association storage to the element GUID, not to its name
(mendixsystem$entity / $attribute / $association .id). Same qualified name + new GUID means the schema sync
drops the old column or table and creates an empty new one: data is lost, while mx check, mxbuild and the
runtime start all report success.

Inputs (old and new, any mix):
  app.mda              deployment package (reads model/model.mdp inside the zip)
  model.mdp            runtime model file
  app.mpr / <dir>      project file (MPR v1 with Contents in sqlite, or MPR v2 with mprcontents/), no build needed

Usage:
  idcheck.py OLD NEW [--json out.json] [--md out.md] [--red-only]
             [--approved approved.txt] [--baseline ORIGINAL]
  idcheck.py APP --xmod                 list cross-module associations per TARGET module (update those targets last)
Exit: 0 = no open data-bearing finding, 1 = open data-bearing findings (RED), 2 = input error.

Step mode (one module update at a time): OLD = the previous commit (git show HEAD:app.mpr > prev.mpr), NEW = the
working copy, --approved = findings already accepted in writing (one fnmatch pattern per line on the element name
or on "FINDING kind name", then " # reason"), --baseline = the ORIGINAL app before the upgrade. A step finding is
then approved automatically when it is net zero against the original: REMOVED of an element the original never had
(a step added it, a later step removed it again), or GUID_CHANGED back to the original GUID. Every auto-approval is
printed with its reason. Comparing every step against the original instead goes blind after the first accepted
finding, because every later step then exits 1 as well.

MPR vs MDA: the MPR has no System module, the MDA has. When the two inputs differ in kind, System is left out of
both sides, and the summary says so.

Findings:
  GUID_CHANGED  same qualified name, different GUID                 -> DROP + ADD, data lost
  REMOVED       name and GUID both gone                              -> column/table dropped (may be intended)
  PERSISTENCE_LOST  entity or association became non-persistent    -> table dropped (may be intended)
  RENAMED       GUID kept, name changed                              -> safe, runtime renames (INFO)
  warn MODULE_RECREATED  (MPR on both sides) a module with 3 or more units shares no unit id with its old self: it was
                deleted and re-imported, not updated (NS-7: DataWidgets 2.27.6 in notification-service cc318c0b, every
                unit new and 12 own pages rewritten, reverted the next day). A warning: the exit code does not change.
  RED = the element holds data: persistent entity, stored attribute of a persistent entity,
        association whose both ends are persistent.
"""
import argparse, fnmatch, glob, io, json, os, sqlite3, sys, uuid, zipfile

try:
    import bson  # pymongo's bson
except ImportError:
    sys.exit("idcheck: needs the 'bson' module (pip install pymongo)")


def guid_str(b):
    if isinstance(b, (bytes, bytearray)) and len(b) == 16:
        return str(uuid.UUID(bytes_le=bytes(b)))  # .NET mixed endian, same form as mendixsystem$*.id
    if hasattr(b, "hex") and not isinstance(b, str):
        return str(uuid.UUID(bytes_le=bytes(b)))
    return str(b)


def items(x):
    """MPR stores lists as [typecode, item, item...]; mdp as plain lists."""
    if not x:
        return []
    return [i for i in x if isinstance(i, dict)]


# ---------------------------------------------------------------- readers

def read_mdp_bytes(data):
    """Return list of (module_name_or_None, DomainModel dict). mdp entities carry QualifiedName."""
    out = []
    for d in bson.decode_file_iter(io.BytesIO(data)):
        if d.get("$Type") == "DomainModels$DomainModel":
            out.append((None, d))
    return out


MODULE_UNITS = {}   # mpr path -> {module name: set of unit ids}, filled by read_mpr (NS-7)


def read_mpr(path):
    proj_dir = os.path.dirname(os.path.abspath(path))
    con = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    # Pure v2 projects (all units in mprcontents/) have no Contents column at all.
    cols = {r[1] for r in con.execute("pragma table_info(Unit)")}
    blob_col = "Contents" if "Contents" in cols else "NULL"
    rows = con.execute(f"select UnitID, ContainerID, {blob_col} from Unit").fetchall()
    v2 = os.path.isdir(os.path.join(proj_dir, "mprcontents"))
    v2files = {}
    if v2:
        for f in glob.glob(os.path.join(proj_dir, "mprcontents", "**", "*.mxunit"), recursive=True):
            v2files[os.path.basename(f)[:-7].lower()] = f
    units = {}
    for uid, cid, blob in rows:
        if blob is None and v2:
            key = str(uuid.UUID(bytes_le=bytes(uid))).lower()
            f = v2files.get(key) or v2files.get(str(uuid.UUID(bytes=bytes(uid))).lower())
            if f:
                blob = open(f, "rb").read()
        if not blob:
            continue
        try:
            units[bytes(uid)] = (bytes(cid) if cid else None, bson.decode(blob))
        except Exception:
            continue
    # NS-7: unit ids per module (by module NAME: a re-imported module has a new ModuleImpl id too)
    parent = {bytes(u): (bytes(c) if c else None) for u, c, _ in rows}
    modname = {u: d.get("Name") for u, (_, d) in units.items() if d.get("$Type") == "Projects$ModuleImpl"}
    per = {}
    for u in parent:
        x, seen = u, set()
        while x is not None and x not in modname and x not in seen:
            seen.add(x); x = parent.get(x)
        if x in modname:
            per.setdefault(modname[x], set()).add(u)
    MODULE_UNITS[os.path.abspath(path)] = per
    out = []
    for uid, (cid, d) in units.items():
        if d.get("$Type") != "DomainModels$DomainModel":
            continue
        mod = units.get(cid, (None, {}))[1].get("Name")
        out.append((mod, d))
    return out


LOADED = {}   # input argument -> the .mpr it resolved to


def load(path):
    p = path
    if os.path.isdir(p):
        mprs = glob.glob(os.path.join(p, "*.mpr"))
        if len(mprs) != 1:
            sys.exit(f"idcheck: {p}: expected exactly one .mpr, found {len(mprs)}")
        p = mprs[0]
    if p.endswith(".mda"):
        with zipfile.ZipFile(p) as z:
            return read_mdp_bytes(z.read("model/model.mdp")), "mda"
    if p.endswith(".mdp"):
        return read_mdp_bytes(open(p, "rb").read()), "mdp"
    if p.endswith(".mpr"):
        LOADED[path] = os.path.abspath(p)
        return read_mpr(p), "mpr"
    sys.exit(f"idcheck: unknown input {path}")


def recreated(old_path, new_path, minimum=3):
    """NS-7: modules on both sides that share NO unit id (at least `minimum` units before): deleted and imported again
    instead of updated in place. [(module, n old units, n new units)]"""
    o, n = MODULE_UNITS.get(LOADED.get(old_path), {}), MODULE_UNITS.get(LOADED.get(new_path), {})
    return [(m, len(o[m]), len(n[m])) for m in sorted(set(o) & set(n)) if len(o[m]) >= minimum and not o[m] & n[m]]


# ---------------------------------------------------------------- model -> element table

def _norm(x):
    if isinstance(x, dict):
        return {k: _norm(v) for k, v in x.items() if k not in ("$ID", "GUID", "Location")}
    if isinstance(x, list):
        return [_norm(i) for i in x if not isinstance(i, int)]
    if isinstance(x, (bytes, bytearray)) or hasattr(x, "subtype"):
        return "B"
    return x


def _fingerprint(rules):
    """Access rules as a version-neutral projection (newer Studio Pro versions add keys such as captions)."""
    out = []
    for r in items(rules):
        out.append((sorted(str(m) for m in (r.get("AllowedModuleRoles") or []) if not isinstance(m, int)),
                    bool(r.get("AllowCreate")), bool(r.get("AllowDelete")),
                    r.get("DefaultMemberAccessRights"), (r.get("XPathConstraint") or "").strip(),
                    sorted((m.get("Attribute") or m.get("Association") or "", m.get("AccessRights"))
                           for m in items(r.get("MemberAccesses")))))
    return json.dumps(sorted(out, key=str), default=str)


def build(domain_models):
    """Return dict kind -> {qualified_name: info}. info: guid, persistent, stored, ..."""
    ents, attrs, assocs = {}, {}, {}
    gen = {}  # entity qn -> (Persistable or None, generalization qn)
    raw_assocs = []
    for mod, dm in domain_models:
        id2qn = {}
        for e in items(dm.get("Entities")):
            qn = e.get("QualifiedName") or f"{mod}.{e.get('Name')}"
            id2qn[bytes(e["$ID"])] = qn
            mg = e.get("MaybeGeneralization") or {}
            if mg.get("$Type") == "DomainModels$Generalization":
                gen[qn] = (None, mg.get("Generalization"))
            else:
                gen[qn] = (bool(mg.get("Persistable", True)), None)
            ents[qn] = {"guid": guid_str(e.get("GUID")), "module": qn.split(".")[0],
                        "acl": _fingerprint(e.get("AccessRules")), "gen": mg.get("Generalization"),
                        "vrules": sorted((str(v.get("Attribute") or ""), str((v.get("RuleInfo") or {}).get("$Type", "")).split("$")[-1])
                                         for v in items(e.get("ValidationRules")))}
            for a in items(e.get("Attributes")):
                val = (a.get("Value") or {}).get("$Type", "")
                aqn = f"{qn}.{a.get('Name')}"
                attrs[aqn] = {"guid": guid_str(a.get("GUID")), "entity": qn, "module": qn.split(".")[0],
                              "stored": "Calculated" not in val,
                              "type": (a.get("Type") or {}).get("$Type", "").split("$")[-1]}
        for kind in ("Associations", "CrossAssociations"):
            for a in items(dm.get(kind)):
                qn = a.get("QualifiedName") or f"{mod}.{a.get('Name')}"
                raw_assocs.append((qn, a, id2qn))
    def persistent(qn, depth=0):
        if qn not in gen or depth > 20:
            return True  # System entities etc.: assume persistent (conservative)
        p, parent = gen[qn]
        return p if parent is None else persistent(parent, depth + 1)
    def is_user(qn, depth=0):
        if qn == "System.User":
            return True
        if qn not in gen or depth > 20:
            return False
        return bool(gen[qn][1]) and is_user(gen[qn][1], depth + 1)
    for qn, info in ents.items():
        info["persistent"] = persistent(qn)
        info["user"] = is_user(qn)
    for aqn, info in attrs.items():
        info["persistent"] = ents[info["entity"]]["persistent"] and info["stored"]
    for qn, a, id2qn in raw_assocs:
        parent = id2qn.get(bytes(a.get("ParentPointer") or b""), a.get("Parent"))
        child = a.get("Child") or id2qn.get(bytes(a.get("ChildPointer") or b""))
        pp = persistent(parent) if parent else True
        cp = persistent(child) if child else True
        assocs[qn] = {"guid": guid_str(a.get("GUID")), "module": qn.split(".")[0], "parent": parent,
                      "child": child, "type": a.get("Type"), "persistent": pp and cp}
    return {"entity": ents, "attribute": attrs, "association": assocs}


def compare(old, new):
    findings = []
    for kind in ("entity", "attribute", "association"):
        o, n = old[kind], new[kind]
        n_by_guid = {v["guid"]: k for k, v in n.items()}
        for qn, oi in sorted(o.items()):
            if qn in n:
                if n[qn]["guid"] != oi["guid"]:
                    findings.append({"finding": "GUID_CHANGED", "kind": kind, "name": qn, "module": oi["module"],
                                     "old_guid": oi["guid"], "new_guid": n[qn]["guid"],
                                     "data": bool(oi["persistent"] and n[qn]["persistent"])})
                elif oi["persistent"] and not n[qn]["persistent"] and kind != "attribute":
                    findings.append({"finding": "PERSISTENCE_LOST", "kind": kind, "name": qn, "module": oi["module"],
                                     "old_guid": oi["guid"], "data": True})
            elif oi["guid"] in n_by_guid:
                findings.append({"finding": "RENAMED", "kind": kind, "name": qn, "module": oi["module"],
                                 "new_name": n_by_guid[oi["guid"]], "old_guid": oi["guid"], "data": False})
            else:
                findings.append({"finding": "REMOVED", "kind": kind, "name": qn, "module": oi["module"],
                                 "old_guid": oi["guid"], "data": bool(oi["persistent"])})
    # an attribute removed only because its whole entity was removed: mark as covered
    gone = {f["name"] for f in findings if f["kind"] == "entity"
            and f["finding"] in ("REMOVED", "GUID_CHANGED", "PERSISTENCE_LOST")}
    for f in findings:
        if f["kind"] == "attribute" and f["name"].rsplit(".", 1)[0] in gone:
            f["covered_by_entity"] = True
    return findings


def drop_module(model, mod):
    for kind in model:
        model[kind] = {k: v for k, v in model[kind].items() if v["module"] != mod}


def read_approved(path):
    out = []
    for line in open(path):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        pat, _, why = line.partition("#")
        out.append((pat.strip(), why.strip() or "approved"))
    return out


def apply_approvals(findings, approved, base):
    """Mark findings approved (listed in writing) or transient (net zero against the original)."""
    for x in findings:
        if not x["data"]:
            continue
        key = f"{x['finding']} {x['kind']} {x['name']}"
        for pat, why in approved:
            if fnmatch.fnmatch(x["name"], pat) or fnmatch.fnmatch(key, pat):
                x["approved"] = f"approved: {why}"
                break
        if base is not None and "approved" not in x:
            orig = base[x["kind"]].get(x["name"])
            if x["finding"] == "REMOVED" and orig is None:
                x["approved"] = "transient: not in the original app, net zero"
            elif x["finding"] == "GUID_CHANGED" and orig is not None and orig["guid"] == x["new_guid"]:
                x["approved"] = "restores the original GUID"
    return findings


def xmod(model):
    """Cross-module associations: owner module differs from the module of an end entity. Grouped by that target."""
    by_target = {}
    for qn, a in model["association"].items():
        for end in (a.get("parent"), a.get("child")):
            if end and "." in end and end.split(".")[0] != a["module"]:
                by_target.setdefault(end.split(".")[0], []).append((qn, end, a["persistent"]))
    lines = ["# cross-module associations by target module",
             "A headless update of a TARGET module can drop these (seen: MxModelReflection 8.0.2 -> 8.0.4 removed 27).",
             "Update target modules last, one per commit, with a step idcheck.", ""]
    for t in sorted(by_target, key=lambda t: (-len(by_target[t]), t)):
        rows = sorted(set(by_target[t]))
        lines.append(f"{t}: {len(rows)} associations ({sum(1 for r in rows if r[2])} data-bearing)")
        for qn, end, p in rows:
            lines.append(f"  {'RED ' if p else 'info'} {qn} -> {end}")
    return lines, by_target


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("old"); ap.add_argument("new", nargs="?")
    ap.add_argument("--json"); ap.add_argument("--md")
    ap.add_argument("--all", action="store_true", help="kept for old callers: info lines are printed by default now")
    ap.add_argument("--red-only", action="store_true", help="print only data-bearing lines")
    ap.add_argument("--approved", help="accepted findings, one pattern per line (element name or 'FINDING kind name') # reason")
    ap.add_argument("--baseline", help="ORIGINAL app (step mode): auto-approve findings that are net zero against it")
    ap.add_argument("--xmod", action="store_true", help="list cross-module associations of OLD by target module and exit")
    a = ap.parse_args()
    if a.xmod:
        dm, _ = load(a.old)
        lines, by_target = xmod(build(dm))
        out = "\n".join(lines); print(out)
        if a.md: open(a.md, "w").write(out + "\n")
        if a.json: json.dump({t: [r[0] for r in v] for t, v in by_target.items()}, open(a.json, "w"), indent=1)
        sys.exit(0)
    if not a.new:
        ap.error("NEW is required unless --xmod")
    (odm, ofmt), (ndm, nfmt) = load(a.old), load(a.new)
    old, new = build(odm), build(ndm)
    note = ""
    if ofmt != nfmt and "mpr" in (ofmt, nfmt):
        drop_module(old, "System"); drop_module(new, "System")
        note = "System excluded on both sides (an MPR has no System module, an MDA has)"
    if not old["entity"] or not new["entity"]:
        print("idcheck: INVALID, no entities read from one side", file=sys.stderr); sys.exit(2)
    base = None
    if a.baseline:
        bdm, bfmt = load(a.baseline); base = build(bdm)
    f = compare(old, new)
    apply_approvals(f, read_approved(a.approved) if a.approved else [], base)
    red = [x for x in f if x["data"]]
    open_red = [x for x in red if "approved" not in x]
    lines = [f"# idcheck {a.old} ({ofmt}) -> {a.new} ({nfmt})", "",
             f"elements old: {len(old['entity'])} entities, {len(old['attribute'])} attributes, {len(old['association'])} associations",
             f"elements new: {len(new['entity'])} entities, {len(new['attribute'])} attributes, {len(new['association'])} associations"]
    if note:
        lines.append(note)
    lines += [f"findings: {len(f)} total, {len(red)} RED (data-bearing), {len(red) - len(open_red)} of them approved, "
              f"{len(open_red)} open", ""]
    order = {"GUID_CHANGED": 0, "PERSISTENCE_LOST": 1, "REMOVED": 2, "RENAMED": 3}
    for x in sorted(f, key=lambda x: ("approved" in x, not x["data"], order[x["finding"]], x["kind"], x["name"])):
        if not x["data"] and a.red_only:
            continue
        tag = ("appr" if "approved" in x else "RED ") if x["data"] else "info"
        extra = ""
        if x["finding"] == "GUID_CHANGED":
            extra = f"{x['old_guid']} -> {x['new_guid']}" + ("  (DROP + ADD: data lost)" if x["data"] else "  (no data)")
        elif x["finding"] == "RENAMED":
            extra = f"-> {x['new_name']}"
        elif x["finding"] == "REMOVED":
            extra = "(column/table dropped; intended?)" if x["data"] else "(no data)"
        elif x["finding"] == "PERSISTENCE_LOST":
            extra = "(now non-persistent: table dropped; intended?)"
        if x.get("covered_by_entity"):
            extra += " [entity also gone]"
        if "approved" in x:
            extra += f"  [{x['approved']}]"
        lines.append(f"{tag} {x['finding']:12} {x['kind']:11} {x['name']}  {extra}")
    rec = recreated(a.old, a.new) if ofmt == nfmt == "mpr" else []
    if rec:
        lines.append("")
    for m, no, nn in rec:
        lines.append(f"warn MODULE_RECREATED {m}: all {no} unit ids new ({nn} units now): the module was deleted and imported "
                     f"again, not updated in place; documents that use it (pages, snippets) were rewritten too: review them, "
                     f"or redo the update with Studio Pro's module update (NS-7)")
    verdict = "FAIL" if any(x["finding"] == "GUID_CHANGED" for x in open_red) else ("REVIEW" if open_red else "PASS")
    lines += ["", f"verdict: {verdict}  (FAIL = open data-bearing GUID change; REVIEW = open data-bearing removals or"
              " persistence loss only: confirm each is intended, then add it to the approved list / allow-list)"]
    out = "\n".join(lines)
    print(out)
    if a.md:
        open(a.md, "w").write(out + "\n")
    if a.json:
        json.dump({"old": a.old, "new": a.new, "verdict": verdict, "note": note, "findings": f,
                   "recreated_modules": [{"module": m, "old_units": no, "new_units": nn} for m, no, nn in rec]},
                  open(a.json, "w"), indent=1)
    sys.exit(1 if open_red else 0)


if __name__ == "__main__":
    main()
