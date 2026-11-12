#!/usr/bin/env python3
"""journey_scope.py: which actions of actions.json are worth a browser journey (the owner's rule: only test what is
used and reachable).

  journey_scope.py actions.json [--model OLD.mpr] [--localedits localedits.json] [--usage usage.json]
                   [--vendor MOD,MOD] [--code-root DIR] [--out scope.json] [--md scope.md]

Classes, one per action (the first that holds, in this order):
  reachable-with-path   the inventory found a click path a role can walk. In scope (its journey is generated and run,
                        also in a Marketplace module: an updated module can change behaviour).
  marketplace-module    no path, and the host sits in a Marketplace module (FromAppStore flag, localedits.json, or
                        --vendor) that the app does not customise: no domain or logic edit, and neither the host nor a
                        page showing it is a UI edit. Out of scope: the vendor owns it. A module whose edits are
                        UNKNOWN (package not readable) is counted here too, with "edits unknown" in the reason: it
                        cannot be compared and is not ours.
  unreachable           no route from any navigation entry or home page of any profile and role (menu items, home pages,
                        login page, pages with a URL, workflow task pages), through page, snippet, layout, microflow,
                        nanoflow and show-page references. An orphan page, dead code. A host whose name appears in the
                        app's Java or JavaScript sources is NOT called dead (code can open a page by name). Out of scope.
  no-role               no user role may both open the page and run the flow. Out of scope.
  reachable-no-path-yet in the graph and some role may run it, but the generator could not build the steps. In scope,
                        stays INVALID in the gate: real testability work (record a click path, or test at deploy).
With --usage (optional) every action in scope whose page and flow the usage file never shows becomes class `unused`
(out of scope); without the file nothing is said about usage.

Out of scope is INFO in the gate, never INVALID. The line triage prints:
  journeys in scope: N reachable, M out of scope (unreachable X, marketplace Y, no-role Z)

usage.json (optional, one file per run, from the production runtime, never invented):
  {"period": "2026-09-01/2026-10-01", "source": "request handler statistics",
   "pages": {"Module.Page": 120, ...}, "microflows": {"Module.Flow": 33, ...}}
A page or flow absent from both maps has zero uses. An action counts as used when its host page (for a snippet or
layout host: any page that shows it), or the flow it runs, has a count above zero. How to get the numbers from a Mendix
runtime: the Mendix Cloud portal's request-handler metrics and the runtime's request log list the executed microflows and
the opened pages by name with a count; or switch on page and microflow usage logging in your own logging module and
export it. The file records what you counted; the toolkit does not check it against the runtime.
"""
import argparse
import collections
import json
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mprmodel import Model  # noqa: E402

IN_SCOPE = ("reachable-with-path", "reachable-no-path-yet")
OUT_SCOPE = ("marketplace-module", "unreachable", "no-role", "unused")
CLASSES = IN_SCOPE + OUT_SCOPE


def nav_closure(model):
    """Documents reachable from what a user can open: every profile's menu items, home pages (per role), login page,
    pages with a URL, and workflow documents (user task pages open from the task inbox), then every reference from
    them (page -> snippet / layout / flow / page, flow -> page it shows). Role-blind on purpose: a role question is
    the no-role class."""
    seeds = set()
    for pr in model.navigation().values():
        for h in pr.get("homes", []):
            seeds.update(x for x in (h.get("page"), h.get("microflow")) if x)
        seeds.update(x["target"] for x in pr.get("menu", []) if x.get("target"))
        if pr.get("login_page"):
            seeds.add(pr["login_page"])
    for q, d in model.docs.items():
        if d.type == "Forms$Page" and str((d.data or {}).get("Url") or "").strip():
            seeds.add(q)          # opens from the address bar or a bookmark
        elif d.type.startswith("Workflows$"):
            seeds.add(q)
    seen = {q for q in seeds if q in model.docs}
    front = list(seen)
    while front:
        nxt = []
        for q in front:
            for r in model.refs(q):
                if r in model.docs and r not in seen and not model.excluded(r):
                    seen.add(r)
                    nxt.append(r)
        front = nxt
    return seen


def code_text(root):
    """The app's own Java and JavaScript sources as one string (not widget bundles, not the generated proxies/ folders,
    which name every microflow of a module whether anything calls it or not), or None without a root."""
    if not root:
        return None
    parts = []
    for sub, exts in (("javasource", (".java",)), ("javascriptsource", (".js", ".ts"))):
        base = Path(root) / sub
        if base.is_dir():
            for f in base.rglob("*"):
                if f.suffix in exts and not f.name.endswith(".min.js") and "proxies" not in f.parts:
                    try:
                        parts.append(f.read_text(errors="ignore"))
                    except OSError:
                        pass
    return "\n".join(parts)


def edits_by_module(path):
    """module -> {"known", "behaviour" (domain or logic edit), "ui" (edited document names)} from localedits.json."""
    out = {}
    for m in json.load(open(path)):
        out[m["name"]] = {"known": m.get("domain") is not None and m.get("logic") is not None,
                          "behaviour": bool(m.get("domain") or m.get("logic")),
                          "ui": {u.get("name") for u in (m.get("ui") or []) if isinstance(u, dict)}}
    return out


def used_ids(usage, acts, via):
    pages = {k for k, v in (usage.get("pages") or {}).items() if v}
    flows = {k for k, v in (usage.get("microflows") or {}).items() if v}
    used = set()
    for x in acts:
        hosts = set(via.get(x["host"], [])) | {x["host"]}
        if hosts & pages or (x.get("target") and x["target"] in flows):
            used.add(x["id"])
    return used


def classify(acts, model, edits, vendor, code, usage):
    closure = nav_closure(model)
    mods = {n for n, i in model.modules.items() if i.get("from_appstore")} | set(vendor or ()) | set(edits or ()) | {"System"}
    callers = model.callers_index()
    via = {}   # snippet / layout host -> the pages that reference it
    for x in acts:
        if x.get("host_type") != "Page":
            via[x["host"]] = sorted(c for c in callers.get(x["host"], ()) if c in model.docs and model.docs[c].type == "Forms$Page")
    def chain_of(host, pages):
        """The host, its pages and every document that references them, upward: all dead when nothing reaches the host,
        so a name of any of them in hand-written code is a way in the graph cannot see."""
        seen, front = {host, *pages}, [host, *pages]
        while front and len(seen) < 3000:
            nxt = [c for q in front for c in callers.get(q, ()) if c in model.docs and c not in seen and not model.excluded(c)]
            seen.update(nxt)
            front = nxt
        return sorted(seen)

    cls = {}
    for x in acts:
        host = x["host"]
        mod = host.split(".")[0]
        pages = x.get("via_pages") or ([host] if x.get("host_type") == "Page" else via.get(host, []))
        e = (edits or {}).get(mod)
        customised = bool(e and (e["behaviour"] or host in e["ui"] or any(p in e["ui"] for p in pages)))
        if x.get("path"):
            c, why = "reachable-with-path", x.get("path_text") or "click path found"
        elif mod in mods and not customised:
            note = ("edits unknown (package not readable), not compared" if e is not None and not e["known"]
                    else "no local edits" if e is not None else "no localedits data for it")
            c, why = "marketplace-module", f"{mod} is a Marketplace module the app does not customise ({note})"
        elif not (host in closure or any(p in closure for p in pages)):
            if code is not None and any(re.search(r"(?<![\w.])" + re.escape(q) + r"(?!\w)", code) for q in chain_of(host, pages)):
                c, why = ("reachable-no-path-yet" if x.get("roles") else "no-role"), \
                    "no menu or home route, but the app's Java or JavaScript names it or a caller of it: not called dead"
            else:
                c, why = "unreachable", ("no route from any navigation entry or home page of any role"
                                         + ("; name not in the app's Java or JavaScript" if code is not None
                                            else "; Java and JavaScript sources NOT scanned"))
        elif not x.get("roles"):
            c, why = "no-role", "no user role may open the page and run the flow"
        else:
            c, why = "reachable-no-path-yet", "in the navigation graph, no click path could be built: record one, or test at deploy"
        cls[x["id"]] = {"class": c, "reason": why}
    if usage is not None:
        used = used_ids(usage, acts, via)
        for i, v in cls.items():
            if v["class"] in IN_SCOPE:
                v["used"] = i in used
                if i not in used:
                    v["class"], v["reason"] = "unused", "the usage file shows neither its page nor its flow in use"
    return cls


def summarize(cls, usage):
    n = collections.Counter(v["class"] for v in cls.values())
    inn, out = sum(n[c] for c in IN_SCOPE), sum(n[c] for c in OUT_SCOPE)
    parts = [f"unreachable {n['unreachable']}", f"marketplace {n['marketplace-module']}", f"no-role {n['no-role']}"]
    if usage is not None:
        parts.append(f"unused {n['unused']}")
    line = f"journeys in scope: {inn} reachable, {out} out of scope ({', '.join(parts)})"
    work = (f"testability work: {n['reachable-no-path-yet']} reachable actions have no click path yet "
            "(record a click path, or test at deploy)")
    return {c: n[c] for c in CLASSES}, inn, out, line, work


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("actions")
    ap.add_argument("--model", help="the OLD .mpr (default: the \"model\" of actions.json)")
    ap.add_argument("--localedits", help="localedits.json of the run: which Marketplace modules the app customised")
    ap.add_argument("--usage", help="usage.json (optional): without it nothing is said about usage")
    ap.add_argument("--vendor", default="", help="comma list of own-looking modules that are really vendor code (triage NS-4)")
    ap.add_argument("--code-root", help="project folder with javasource/ and javascriptsource/ (default: next to the model, when it has them)")
    ap.add_argument("--out", help="scope.json")
    ap.add_argument("--md", help="a readable list of what is out of scope and why")
    a = ap.parse_args()
    try:
        doc = json.load(open(a.actions))
        acts = doc["actions"]
    except (OSError, ValueError, KeyError) as e:
        print(f"journey_scope: {a.actions}: not an action_inventory.py file ({e})", file=sys.stderr)
        return 1
    mpr = a.model or doc.get("model")
    if not mpr or not os.path.exists(mpr):
        print(f"journey_scope: model {mpr}: not found (give --model)", file=sys.stderr)
        return 1
    try:
        model = Model.load(mpr)
    except Exception as e:  # noqa: BLE001  an unreadable model is an error, never an empty scope
        print(f"journey_scope: cannot read {mpr}: {e}", file=sys.stderr)
        return 1
    if not model.docs:
        print(f"journey_scope: {mpr}: no documents read", file=sys.stderr)
        return 1
    here = Path(os.path.abspath(mpr)).parent
    root = a.code_root or (str(here) if (here / "javasource").is_dir() else None)
    code = code_text(root)
    try:
        edits = edits_by_module(a.localedits) if a.localedits else None
        usage = json.load(open(a.usage)) if a.usage else None
    except (OSError, ValueError) as e:
        print(f"journey_scope: {e}", file=sys.stderr)
        return 1
    cls = classify(acts, model, edits, [v for v in a.vendor.split(",") if v], code, usage)
    counts, inn, out, line, work = summarize(cls, usage)
    print(line)
    print(work)
    if code is None:
        print("note: no javasource/ next to the model and no --code-root: Java and JavaScript were NOT scanned, "
              "so an orphan that code opens by name would be called unreachable", file=sys.stderr)
    if a.out:
        Path(a.out).write_text(json.dumps({
            "tool": "journey_scope.py", "actions_file": os.path.abspath(a.actions), "model": os.path.abspath(mpr),
            "usage": bool(a.usage), "code_scanned": code is not None, "counts": counts, "in_scope": inn,
            "out_of_scope": out, "line": line, "testability_line": work, "classes": cls}, indent=1))
        print(f"wrote {a.out}")
    if a.md:
        L = ["# Journey scope", "", line, work, ""]
        for c in OUT_SCOPE:
            ids = sorted(i for i, v in cls.items() if v["class"] == c)
            if ids:
                L += [f"## out of scope: {c} ({len(ids)})", ""] + [f"- {i}: {cls[i]['reason']}" for i in ids] + [""]
        ids = sorted(i for i, v in cls.items() if v["class"] == "reachable-no-path-yet")
        if ids:
            L += [f"## testability work: reachable, no click path yet ({len(ids)})", ""] + [f"- {i}" for i in ids] + [""]
        Path(a.md).write_text("\n".join(L))
    return 0


if __name__ == "__main__":
    sys.exit(main())
