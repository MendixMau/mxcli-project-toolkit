#!/usr/bin/env python3
"""crosscalls.py: which modules on the update plan are called by a module that STAYS (T5-15, T5F-4).

A module that stays KEPT (a refusal, a stranded module, a local-edit module) keeps calling the API it was built
against. When a planned module jumps to its next major, that API changes under it, and the first sign is late:
T5-15, AmazonBedrockConnector 3.0.0 (kept) called the old Java of AWSAuthentication; after AWSAuthentication 4.x the
build broke at javac. T5F-4, the same hole seen by mx check: CE0117 in a kept Administration after the MendixSSO
update. triage.md and upgrade.md only covered association targets (idcheck --xmod); this covers every other way a
module reaches into another one.

Reads the model the way the other bin/ scripts do (mprmodel.py: MPR v1 or v2, no Studio Pro) plus javasource/.
For every pair (kept module K, planned module P, K != P) it lists the references from K into P:
  Microflow / Nanoflow / Java action / entity / association / enumeration / page / snippet / layout / ... : any
      qualified name `P.Name` that appears in a document of K (microflow calls, Java action calls, generalizations,
      association children, page and snippet use), typed by what P.Name is. Excluded documents do not build and are
      not counted.
  java import: `import <p>.x.Class;` in javasource/<k>/ where <p> is the Java package of P (its name, lower case).

PV-3: a kept module also reaches into a planned one through pages, snippets and layouts (a Show page activity, a snippet
call, a page layout); those are listed first in the examples. A planned module whose plan version keeps the major is not
capped on that alone, but when the package of the plan version is in the cache (--cache, default UPG_CACHE or
~/.cache/upgrade-toolkit/mpk, <content id>-<version>.mpk, never downloaded here) every referenced target is looked up in
it: a target the package no longer has is a GONE row and caps the module (Product View 360: OIDC 4.7.0 dropped the page
that a kept TcConnector shows; it surfaced only as CE1613 at mx check). Without the package the NOTE says the targets were
not checked against the plan version.

Usage:
  crosscalls.py APP (--kept A,B | --kept-file kept.txt) (--planned C,D | --plan-file plan.txt)
                [--newest C=3.9.0,D=2.4.1] [--javasource DIR] [--cache DIR] [--json out.json]
  APP            the app folder (the .mpr, mprcontents/ and javasource/ side by side) or the .mpr itself
  --kept-file    stepupdate's .stepupdate/kept.txt: one module per line, the first word is the module
  --plan-file    stepupdate's plan.txt: "<content id> <version> <Module>" per line, # comments allowed
  --kept ''      an explicitly empty kept list is legal (nothing stays, nothing can be capped); NOT giving either
                 kept option is an input error, so a forgotten argument is never read as "nothing is kept"
A module that is both kept and planned is a kept module (stepupdate keeps plan lines it refused); it is not a P.
With a plan file, a planned module whose plan version has the SAME major as the installed one is listed as NOTE
(minor and patch releases keep the API) and does not cap. Anything else caps, a plan version of unknown major too.
--newest names the newest version of the current major per capped module (`mxcli marketplace versions <cid>`); without
it the line says "newest <major>.x" and the installed version, to be looked up.

Output: a header with the denominators (kept modules, planned modules, documents and Java files scanned), then per
capped planned module
  CAP <P> at <newest version of current major>: called by kept <K> (<n> refs, e.g. ...)
Exit: 0 = no cap, 1 = at least one planned module is called by a kept module (hold it at its current major, or
update the kept module too), 2 = input error (a named module is not in the model, no model, no kept option).
"""
import argparse, json, os, re, sys, zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mprmodel  # noqa: E402

JIMPORT = re.compile(r"^\s*import\s+(?:static\s+)?([A-Za-z_][\w]*)\.([\w.*]+)\s*;", re.M)
KIND = {"Microflows$Microflow": "microflow", "Microflows$Nanoflow": "nanoflow", "JavaActions$JavaAction": "java action",
        "Forms$Page": "page", "Forms$Snippet": "snippet", "Forms$Layout": "layout", "Enumerations$Enumeration": "enumeration",
        "Constants$Constant": "constant", "Microflows$Rule": "rule", "Microflows$JavaScriptAction": "javascript action"}


def names(text):
    return [n for n in re.split(r"[,\s]+", text or "") if n]


def read_first_words(path, plan):
    out = []
    for line in open(path, encoding="utf-8", errors="replace"):
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        w = line.split()
        if plan:
            if len(w) >= 3:
                out.append((w[2], w[1]))
        else:
            out.append((w[0], ""))
    return out


def major(v):
    m = re.match(r"\s*(\d+)", v or "")
    return int(m.group(1)) if m else None


def entity_names(model):
    """qualified entity and association names per module, from the domain models (a ref `P.Customer` is an entity)."""
    ent = {}
    for qn, d in model.docs.items():
        if d.type != "DomainModels$DomainModel":
            continue
        for e in d.data.get("Entities") or []:
            if isinstance(e, dict) and e.get("Name"):
                ent[f"{d.module}.{e['Name']}"] = "entity"
        for k in ("Associations", "CrossAssociations"):
            for a in d.data.get(k) or []:
                if isinstance(a, dict) and a.get("Name"):
                    ent[f"{d.module}.{a['Name']}"] = "association"
    return ent


def model_refs(model, kept, planned):
    """{(K, P): [(kind, from document, target)]} over every non-excluded document of K."""
    ent = entity_names(model)
    out, ndocs = {}, 0
    docs = [d for d in model.all_docs] + [d for d in model.docs.values() if d.type == "DomainModels$DomainModel"]
    for d in docs:
        if d.module not in kept or d.data.get("Excluded"):
            continue
        ndocs += 1
        seen = set()
        for s in mprmodel.strings(d.data):
            for mod, name in mprmodel.QN.findall(s):
                if mod in planned and mod != d.module and (mod, name) not in seen:
                    seen.add((mod, name))
                    tq = f"{mod}.{name}"
                    t = model.docs.get(tq)
                    kind = KIND.get(t.type) if t else None
                    kind = kind or (t.type.split("$")[-1].lower() if t else ent.get(tq, "name"))
                    src = f"{d.module}.{d.data.get('Name')}" if d.type != "DomainModels$DomainModel" else f"{d.module} domain model"
                    out.setdefault((d.module, mod), []).append((kind, src, tq))
    return out, ndocs


FIRST = {"page": 0, "snippet": 1, "layout": 2}


def example_order(x):
    return (FIRST.get(x[0], 3), x)


def package_model(cache, cid, version):
    """The model of <cache>/<cid>-<version>.mpk (or its extracted project.mpr), or None when it is not cached."""
    if not cid or not version:
        return None
    mpk = os.path.join(cache, f"{cid}-{version}.mpk")
    xdir = mpk[:-4]
    xmpr = os.path.join(xdir, "project.mpr")
    if not os.path.exists(xmpr):
        if not os.path.exists(mpk):
            return None
        try:
            with zipfile.ZipFile(mpk) as z:
                names = [n for n in z.namelist() if n.endswith(".mpr")]
                if not names:
                    return None
                z.extract(names[0], xdir)
                if names[0] != "project.mpr":
                    os.rename(os.path.join(xdir, names[0]), xmpr)
        except (OSError, zipfile.BadZipFile):
            return None
    try:
        return mprmodel.Model.load(xmpr)
    except (SystemExit, Exception):
        return None


def gone_targets(pkg, callers):
    """[(kind, source doc, target)] the package does not have. Only targets that exist in the installed model count (kind
    "name" is a string that merely looks like a qualified name, a module role for one)."""
    have = {d.qn for d in pkg.all_docs} | set(entity_names(pkg))
    return sorted({(kind, src, tgt) for v in callers.values() for kind, src, tgt in v if kind != "name" and tgt not in have})


def java_refs(jdir, kept, planned):
    """{(K, P): [("java import", file, import)]} from javasource/<k>/**.java importing a package named after P."""
    out, nfiles = {}, 0
    if not os.path.isdir(jdir):
        return out, 0
    pk = {p.lower(): p for p in planned}
    dirs = {d.lower(): d for d in os.listdir(jdir)}
    for k in kept:
        kd = dirs.get(k.lower())
        if not kd:
            continue
        for root, _, files in os.walk(os.path.join(jdir, kd)):
            for f in files:
                if not f.endswith(".java"):
                    continue
                nfiles += 1
                rel = os.path.relpath(os.path.join(root, f), jdir)
                text = open(os.path.join(root, f), encoding="utf-8", errors="replace").read()
                for pkg, rest in JIMPORT.findall(text):
                    p = pk.get(pkg.lower())
                    if p and p != k:
                        out.setdefault((k, p), []).append(("java import", rel, f"{pkg}.{rest}"))
    return out, nfiles


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("app")
    ap.add_argument("--kept")
    ap.add_argument("--kept-file")
    ap.add_argument("--planned")
    ap.add_argument("--plan-file")
    ap.add_argument("--newest", default="")
    ap.add_argument("--javasource")
    ap.add_argument("--cache", default=os.environ.get("UPG_CACHE") or os.path.expanduser("~/.cache/upgrade-toolkit/mpk"))
    ap.add_argument("--json")
    a = ap.parse_args()

    if a.kept is None and not a.kept_file:
        print("crosscalls: give --kept A,B (or --kept '' for none) or --kept-file kept.txt", file=sys.stderr)
        return 2
    if not a.planned and not a.plan_file:
        print("crosscalls: give --planned C,D or --plan-file plan.txt", file=sys.stderr)
        return 2
    kept = names(a.kept) + ([n for n, _ in read_first_words(a.kept_file, False)] if a.kept_file else [])
    kept = list(dict.fromkeys(kept))
    planv = {}
    for n, v in (read_first_words(a.plan_file, True) if a.plan_file else []):
        planv[n] = v
    planned = list(dict.fromkeys(names(a.planned) + list(planv)))
    both = [n for n in planned if n in kept]
    planned = [n for n in planned if n not in kept]
    newest = dict(x.split("=", 1) for x in names(a.newest) if "=" in x)

    p = a.app
    try:
        model = mprmodel.Model.load(p)
    except SystemExit as e:
        print(e, file=sys.stderr)
        return 2
    unknown = [n for n in kept + planned if n not in model.modules]
    if unknown:
        print(f"crosscalls: not a module of the model: {', '.join(unknown)} (a typo or a removed module; nothing judged)", file=sys.stderr)
        return 2
    base = os.path.dirname(os.path.abspath(model.path))
    jdir = a.javasource or os.path.join(base, "javasource")

    mr, ndocs = model_refs(model, set(kept), set(planned))
    jr, nfiles = java_refs(jdir, kept, planned)
    refs = {}
    for src in (mr, jr):
        for key, v in src.items():
            refs.setdefault(key, []).extend(v)

    print(f"crosscalls: kept {len(kept)} ({', '.join(kept) or '-'}), planned {len(planned)}; scanned {ndocs} documents of the kept "
          f"modules and {nfiles} Java files under {jdir}")
    if both:
        print(f"note: {', '.join(both)} is on both lists: treated as kept, not planned")
    caps, notes, res = 0, [], {}
    for pm in planned:
        callers = {k: refs[(k, pm)] for k in kept if (k, pm) in refs}
        if not callers:
            continue
        inst = model.modules[pm].get("version") or ""
        pv = planv.get(pm, "")
        mj = major(inst)
        parts = []
        for k, v in callers.items():
            eg = "; ".join(f"{kind} {src} -> {tgt}" for kind, src, tgt in sorted(set(v), key=example_order)[:3])
            parts.append(f"{k} ({len(v)} refs, e.g. {eg})")
        res[pm] = {"installed": inst, "plan": pv, "callers": {k: [list(x) for x in sorted(set(v))] for k, v in callers.items()}}
        if pv and mj is not None and major(pv) == mj:
            pkg = package_model(a.cache, model.modules[pm].get("package_id"), pv)
            gone = gone_targets(pkg, callers) if pkg else None
            if gone:
                print(f"CAP {pm} at {inst} (installed {inst}, plan {pv}): same major, but the {pv} package no longer has "
                      f"{len(gone)} target(s) that kept modules use")
                for kind, src, tgt in gone:
                    print(f"  GONE {kind} {tgt} (used by {src})")
                res[pm]["cap"] = True
                res[pm]["gone"] = [list(x) for x in gone]
                caps += 1
                continue
            how = ("every target exists in the plan version package" if pkg else
                   "targets NOT checked against the plan version: its package is not in the cache, so a page, flow or "
                   "entity the new version dropped would show only as CE1613 at mx check")
            notes.append(f"NOTE {pm} {inst} -> {pv} keeps its major: called by kept " + ", ".join(parts) + f" (not capped; {how})")
            res[pm]["cap"] = False
            continue
        top = newest.get(pm) or (f"newest {mj}.x" if mj is not None else "newest of its current major")
        print(f"CAP {pm} at {top} (installed {inst or 'unknown'}" + (f", plan {pv}" if pv else "") + "): called by kept " + ", ".join(parts))
        res[pm]["cap"] = True
        caps += 1
    for n in notes:
        print(n)
    print(f"crosscalls: {caps} planned module(s) capped, {len(notes)} noted, {len(planned) - caps - len(notes)} not called by a kept module")
    if caps:
        print("  hold each CAP module at its current major in the plan (or update the kept caller too), re-run after the plan changes")
    if a.json:
        json.dump({"kept": kept, "planned": planned, "caps": res}, open(a.json, "w"), indent=1)
    return 1 if caps else 0


if __name__ == "__main__":
    sys.exit(main())
