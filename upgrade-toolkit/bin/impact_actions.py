#!/usr/bin/env python3
"""impact_actions.py: which actions of an app are TOUCHED by a change (plan section 3, impact selection).

    impact_actions.py <actions.json> [--impact impact.json] [--repaired FILE] [--updated-modules FILE]
                      [--replacements replacements.json] [--convertcheck convert-mappings.json]
                      [--l1 l1-hits.json] [--out impact-actions.json]

An action (a row of actions.json from action_inventory.py --out, with its reach) is TOUCHED when anything in its reach
(the documents it reaches transitively) meets one of the sources below. An action whose reach meets none of them is
untouched, and its line says so. Three rules hold whatever the sources:
  - unknown reach: a reach holding a reference the model does not hold (reach_unknown), or no reach at all, is TOUCHED
    ("unknown reach"). Unknown is never read as untouched.
  - an unreadable add-on module (summary.unreadable_modules of actions.json) in the reach: TOUCHED ("addons").
  - a source row that names no document (a replacement HIT or UNKNOWN with no module, file or Module.Name in its
    evidence; an L1 hit with no doc): every action is TOUCHED, because no action can be shown clear of it.

Sources. Each is optional. A source that is not given is listed as "source not provided", never as "no hits":
  1 impact        impact_map.py OLD NEW --out impact.json (steps/journeys.md, "At the gate"). Its "changes": a document
                  change touches the action whose reach holds that document; a module change (kind "module") touches
                  the actions whose reach holds that module.
  2 repaired      the documents the repair changed, one Module.Name per line (# comments skipped). No step writes this
                  list yet (steps/repair.md): the caller passes it.
  3 modules       the updated modules, one name per line (the format of impact_map.py --updates). Produced by the module
                  update runner (steps/upgrade.md step 1).
  4 replacements  replacement_check.py app/ --to VER --json replacements.json (steps/triage.md step 10 writes --out
                  only; --json is needed here). Each HIT or UNKNOWN row: a Module.Name, module or javasource/<module>/
                  path in its evidence that the reach holds touches the action.
  5 convertcheck  convertcheck.py --mappings OLD NEW --json (steps/upgrade.md step 2): every page whose call-site
                  mappings the convert rewrote, verdict and all. A rewritten page in the reach touches the action.
  6 l1            L1 behaviour-rule hits, INCLUDING hits in documents the change did not touch: JSON
                  {"hits": [{"rule": "R31", "doc": "Module.Name"}]} (a bare list is accepted). A hit in a document an
                  action reaches touches it. The producer (an L1 scan of the whole model) is not built yet: until it is,
                  this source is "not provided".
  7 addons        the unreadable modules recorded in actions.json (always there when actions.json is written by
                  action_inventory.py). It is not a flag: it is read from the inventory.

Exit: 0 = written (touched and untouched are findings, not errors); 1 = malformed input (a file that is not what its
source says it is, an action with no id, a reach that is not a list); 2 = usage error (no such file). Read-only.
"""
import argparse, json, os, re, sys

QN = re.compile(r"@?([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)")
SOURCES = ("impact", "repaired", "modules", "replacements", "convertcheck", "l1", "addons")
FLAGS = {"impact": "--impact", "repaired": "--repaired", "modules": "--updated-modules", "replacements": "--replacements",
         "convertcheck": "--convertcheck", "l1": "--l1"}
REPL_STATUS = ("HIT", "UNKNOWN", "clear", "NOT APPLICABLE")


class Malformed(Exception):
    pass


def read_json(path, what):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, UnicodeDecodeError) as e:
        raise Malformed(f"{what} {path}: cannot read: {e}")
    except json.JSONDecodeError as e:
        raise Malformed(f"{what} {path}: not JSON: {e}")


def need(cond, msg):
    if not cond:
        raise Malformed(msg)


def read_names(path, what, dotted):
    """One name per line: Module.Name when dotted, a bare module name otherwise. # comments and blank lines skipped."""
    try:
        lines = open(path, encoding="utf-8").read().splitlines()
    except (OSError, UnicodeDecodeError) as e:
        raise Malformed(f"{what} {path}: cannot read: {e}")
    out = []
    for n, line in enumerate(lines, 1):
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        tok = s.split()[0]
        need(("." in tok) == dotted,
             f"{what} {path} line {n}: '{tok}' is not a {'Module.Name document' if dotted else 'module name'}")
        out.append(tok)
    return out


def is_names(x):
    return isinstance(x, list) and all(isinstance(i, str) for i in x)


def load_actions(path):
    d = read_json(path, "actions file")
    need(isinstance(d, dict) and isinstance(d.get("actions"), list),
         f"actions file {path}: no \"actions\" list (not an action_inventory.py --out file)")
    for i, a in enumerate(d["actions"]):
        need(isinstance(a, dict) and isinstance(a.get("id"), str) and a["id"], f"actions file {path}: action {i} has no id")
        need(a.get("reach") is None or is_names(a["reach"]),
             f"actions file {path}: action {a['id']} reach is not a list of names")
        need(a.get("reach_unknown") is None or is_names(a["reach_unknown"]),
             f"actions file {path}: action {a['id']} reach_unknown is not a list of names")
    summ = d.get("summary") if isinstance(d.get("summary"), dict) else {}
    need("unreadable_modules" not in summ or is_names(summ["unreadable_modules"]),
         f"actions file {path}: summary.unreadable_modules is not a list of names")
    return d["actions"], sorted(summ.get("unreadable_modules") or [])


def load_impact(path):
    d = read_json(path, "impact file")
    need(isinstance(d, dict) and isinstance(d.get("changes"), list),
         f"impact file {path}: no \"changes\" list (not an impact_map.py --out file)")
    for i, c in enumerate(d["changes"]):
        need(isinstance(c, dict) and isinstance(c.get("kind"), str) and isinstance(c.get("qn"), str) and c["qn"],
             f"impact file {path}: change {i} needs a kind and a qn")
    return d["changes"]


def load_replacements(path):
    d = read_json(path, "replacements file")
    need(isinstance(d, dict) and isinstance(d.get("rows"), list),
         f"replacements file {path}: no \"rows\" list (not a replacement_check.py --json file)")
    for i, r in enumerate(d["rows"]):
        need(isinstance(r, dict) and isinstance(r.get("id"), str) and r.get("status") in REPL_STATUS,
             f"replacements file {path}: row {i} needs an id and a status of {', '.join(REPL_STATUS)}")
        need(is_names(r.get("evidence", [])), f"replacements file {path}: row {r['id']} evidence is not a list of text")
    return d["rows"]


def load_convert(path):
    d = read_json(path, "convertcheck file")
    need(isinstance(d, list), f"convertcheck file {path}: not a list (not a convertcheck.py --mappings --json file)")
    for i, r in enumerate(d):
        need(isinstance(r, dict) and isinstance(r.get("verdict"), str) and isinstance(r.get("page"), str),
             f"convertcheck file {path}: row {i} needs text in verdict and page")
    return d


def load_l1(path):
    d = read_json(path, "L1 file")
    hits = d.get("hits") if isinstance(d, dict) else d
    need(isinstance(hits, list), f"L1 file {path}: no \"hits\" list")
    for i, h in enumerate(hits):
        need(isinstance(h, dict) and isinstance(h.get("rule"), str), f"L1 file {path}: hit {i} needs a rule")
        need(isinstance(h.get("doc", ""), str), f"L1 file {path}: hit {i} doc is not text")
    return hits


def module_of(name):
    return name.split(".", 1)[0]


FILE_EXT = {"mpk", "jar", "java", "js", "jsx", "ts", "tsx", "mjs", "scss", "css", "xml", "json", "zip", "md", "txt",
            "properties", "html", "png", "svg"}


def locate(text, names, modules):
    """(names and modules the evidence text points at, located). located: the text names a document (Module.Name, not
    a file), a module ("module X") or a javasource/<module>/ folder at all. Evidence that names only files or folders
    (widgets/*.mpk, userlib/*.jar, a native navigation profile) cannot be placed on any action: the caller touches all."""
    qns = [f"{a}.{b}" for a, b in QN.findall(text) if b.lower() not in FILE_EXT]
    words = re.findall(r"module[: ]+([A-Za-z_]\w*)", text)
    dirs = re.findall(r"javasource/([A-Za-z_]\w*)/", text)
    located = bool(qns or words or dirs)
    hit = {q for q in qns if q in names}
    hit |= {m for m in modules if m in words}
    hit |= {m for m in modules for d in dirs if m.lower() == d.lower()}
    return hit, located


def reasons_for(x, provided, unreadable):
    """Every reason the action is touched, as (source, match, detail)."""
    out = []
    reach = x.get("reach")
    unknown = x.get("reach_unknown") or []
    names = set(reach or []) | set(unknown)
    mods = {n for n in (reach or []) if "." not in n} | {module_of(n) for n in names if "." in n}
    if reach is None:
        out.append(("reach", None, "unknown reach: the inventory gives no reach for this action"))
    elif unknown:
        out.append(("reach", None, "unknown reach: " + ", ".join(unknown[:3]) + (" ..." if len(unknown) > 3 else "")))
    for src, rows in provided.items():
        if src == "impact":
            for c in rows:
                qn, kind = c["qn"], c["kind"]
                if kind == "module" or "." not in qn:
                    hit = qn in mods
                else:
                    hit = qn in names
                if hit:
                    out.append(("impact", qn, f"{kind} change" + (f": {c['detail']}" if c.get("detail") else "")))
        elif src == "repaired":
            out += [("repaired", q, "repaired document") for q in rows if q in names]
        elif src == "modules":
            out += [("modules", m, "updated module") for m in rows if m in mods]
        elif src == "replacements":
            for r in rows:
                if r["status"] not in ("HIT", "UNKNOWN"):
                    continue
                found, located = set(), False
                for ev in r.get("evidence", []):
                    f, l = locate(ev, names, mods)
                    found |= f
                    located = located or l
                if found:
                    out += [("replacements", m, f"{r['status']} {r['id']}") for m in sorted(found)]
                elif not located:
                    out.append(("replacements", None, f"{r['status']} {r['id']} names no document: cannot be placed"))
        elif src == "convertcheck":
            out += [("convertcheck", r["page"], f"call-site mappings rewritten ({r['verdict']})")
                    for r in rows if r["page"] in names]
        elif src == "l1":
            for h in rows:
                doc = h.get("doc") or ""
                if not doc:
                    out.append(("l1", None, f"L1 hit {h['rule']} names no document: cannot be placed"))
                elif doc in names or ("." not in doc and doc in mods):
                    out.append(("l1", doc, f"L1 hit {h['rule']}"))
        elif src == "addons":
            out += [("addons", m, "unreadable add-on module in reach") for m in rows if m in mods]
    return list(dict.fromkeys(out))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("actions", help="actions.json from action_inventory.py --out")
    ap.add_argument("--impact", help="impact_map.py --out JSON (source 1)")
    ap.add_argument("--repaired", help="repaired documents, Module.Name per line (source 2)")
    ap.add_argument("--updated-modules", dest="modules_file", help="updated module names, one per line (source 3)")
    ap.add_argument("--replacements", help="replacement_check.py --json (source 4)")
    ap.add_argument("--convertcheck", help="convertcheck.py --mappings --json (source 5)")
    ap.add_argument("--l1", help="L1 behaviour-rule hits JSON, including unchanged documents (source 6)")
    ap.add_argument("--out", help="write the per-action verdicts JSON here")
    a = ap.parse_args()
    given = {"actions": a.actions, "impact": a.impact, "repaired": a.repaired, "modules": a.modules_file,
             "replacements": a.replacements, "convertcheck": a.convertcheck, "l1": a.l1}
    for k, p in given.items():
        if p is not None and not os.path.isfile(p):
            print(f"impact_actions: {k} file {p}: no such file", file=sys.stderr)
            return 2
    try:
        acts, unreadable = load_actions(a.actions)
        loaders = {"impact": (a.impact, load_impact), "replacements": (a.replacements, load_replacements),
                   "convertcheck": (a.convertcheck, load_convert), "l1": (a.l1, load_l1)}
        provided = {}
        for src, (path, load) in loaders.items():
            if path:
                provided[src] = load(path)
        if a.repaired:
            provided["repaired"] = read_names(a.repaired, "repaired list", dotted=True)
        if a.modules_file:
            provided["modules"] = read_names(a.modules_file, "updated modules", dotted=False)
    except Malformed as e:
        print(f"impact_actions: malformed input: {e}", file=sys.stderr)
        return 1
    provided["addons"] = unreadable      # always provided: read from the inventory, not from a flag
    order = [s for s in SOURCES if s in provided]   # reasons print in the source order of SOURCES

    results, unknown_reach = [], 0
    for x in acts:
        rs = reasons_for(x, {s: provided[s] for s in order}, unreadable)
        if x.get("reach") is None or x.get("reach_unknown"):
            unknown_reach += 1
        results.append({"id": x["id"], "touched": bool(rs), "reach_size": len(x["reach"]) if x.get("reach") is not None else None,
                        "reasons": [{"source": s, "match": m, "detail": d} for s, m, d in rs]})

    touched = sum(1 for r in results if r["touched"])
    line = f"touched {touched} of {len(results)} actions (sources provided: {len(provided)} of {len(SOURCES)})"
    for r in results:
        if r["touched"]:
            print(f"TOUCHED {r['id']}: " + "; ".join(
                f"{x['source']} {x['match']} ({x['detail']})" if x["match"] else f"{x['source']} ({x['detail']})"
                for x in r["reasons"]))
        else:
            print(f"untouched {r['id']}")
    for s in SOURCES:
        if s not in provided:
            print(f"source not provided: {s} (no {FLAGS[s]} given)")
    print(line)
    if a.out:
        srcs = {}
        for s in SOURCES:
            if s == "addons":
                srcs[s] = {"provided": True, "from": os.path.abspath(a.actions), "modules": unreadable}
            elif s in provided:
                srcs[s] = {"provided": True, "file": os.path.abspath(given[s]), "rows": len(provided[s])}
            else:
                srcs[s] = {"provided": False, "reason": f"{FLAGS[s]} not given"}
        with open(a.out, "w", encoding="utf-8") as f:
            json.dump({"tool": "impact_actions.py", "actions_file": os.path.abspath(a.actions), "sources": srcs,
                       "sources_provided": sum(1 for v in srcs.values() if v["provided"]), "sources_total": len(SOURCES),
                       "summary": {"actions": len(results), "touched": touched, "untouched": len(results) - touched,
                                   "unknown_reach": unknown_reach},
                       "summary_line": line, "actions": results}, f, indent=1)
        print(f"wrote {a.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
