#!/usr/bin/env python3
"""click_causes.py: why has an in-scope action no click path? One cause per reachable-no-path-yet action.

  click_causes.py actions.json --model OLD.mpr --scope journey-scope.json [--out causes.json] [--md causes.md]

journey_scope.py leaves a class `reachable-no-path-yet`: a role may run the action, a caller reaches its page, but the
inventory found no chain of clicks. That class is a work list, and "no click path" is not a cause. This tool walks the
callers of each host page UPWARD through snippets, layouts, pages and flows and names what stops the chain. One cause per
action, the first that holds:

  combobox-change   the action itself fires on a Combo box change: there is no click, a fill and a pick drive it.
  dynamic-name      a flow in the chain that opens the page is run by NAME: the name is assigned as text to an attribute (a task
                    type row holds "Module.ShowTaskPage") and a runtime call executes it. No reference chain shows
                    the click. Needs the data (a task row) that makes the app run it.
  role-mismatch     clicks reach the page, but only as a role that may not run the flow (inventory text).
  event-or-startup  the chain ends at something that is not a click: an after-startup or scheduled flow, an entity
                    event, a workflow, a service, a Java action.
  flow-shows-it     a flow shows the page directly (a popup raised by a rule inside a flow: the data decides).
  flow-chain        the chain climbs through flows and pages and reaches no entry the inventory could click.
  unknown           none of the above; listed with the nearest callers.

Menu items are not a cause any more: they are click hops (action_inventory.py menu_hops).

Output: causes.json {"counts": {...}, "actions": {id: {"cause", "detail", "opened_by": [...]}}} and an optional markdown
table. Read only: it never touches the model or the apps.
"""
import argparse
import collections
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mprmodel import Model  # noqa: E402

FLOW = ("Microflows$Microflow", "Microflows$Nanoflow")
PAGELIKE = ("Forms$Page", "Forms$Snippet", "Forms$Layout")
CAUSES = ("combobox-change", "role-mismatch", "dynamic-name", "event-or-startup", "flow-shows-it", "flow-chain", "unknown")


def reverse_index(model):
    rev = collections.defaultdict(set)
    for q, d in model.docs.items():
        if model.excluded(q):
            continue
        for r in model.refs(q):
            if r in model.docs and r != q:
                rev[r].add(q)
    return rev


def text_assigned(doc, name):
    """True when `name` occurs in the doc only as the Value of a change-object member (an expression literal), never
    as the target of a microflow call, show-page or nanoflow call."""
    hits = {"literal": 0, "call": 0}

    def walk(x, key):
        if isinstance(x, dict):
            for k, v in x.items():
                walk(v, k)
        elif isinstance(x, list):
            for v in x:
                walk(v, key)
        elif isinstance(x, str) and name in x:
            hits["literal" if key in ("Value", "Expression", "Text") else "call"] += 1
    walk(doc.data, "")
    return hits["literal"] > 0 and hits["call"] == 0


def climb(model, rev, host, limit=3000):
    """Upward closure of `host`: {doc: depth}, stopping nowhere but at the limit."""
    seen = {host: 0}
    front = [host]
    while front and len(seen) < limit:
        nxt = []
        for q in front:
            if q != host and model.docs[q].type in ("Menus$MenuDocument", "Forms$Layout"):
                continue   # a menu document or layout is a stop: what shows it is structure, not a way to open the host
            for c in rev.get(q, ()):
                if c not in seen:
                    seen[c] = seen[q] + 1
                    nxt.append(c)
        front = nxt
    return seen


def cause_of(model, rev, act, cache):
    todo = " ".join(act.get("todo") or [])
    if "combobox" in todo:
        return "combobox-change", "the action fires on a Combo box change: a fill and a pick drive it, not a click", []
    if "not as a role allowed" in todo:
        return "role-mismatch", "clicks reach the page as a role that may not run the flow", []
    hosts = act.get("via_pages") or [act["host"]]
    key = tuple(hosts)
    if key not in cache:
        up = {}
        for h in hosts:
            for q, dpt in climb(model, rev, h).items():
                up[q] = min(dpt, up.get(q, 99))
        cache[key] = up
    up = cache[key]
    flows = sorted(q for q in up if model.docs[q].type in FLOW)
    # run by name: a flow of the chain is assigned as TEXT in another document (a task type row holds "Module.Flow")
    lit = sorted({f"{c} names {f} as text" for f in flows for c in rev.get(f, ())
                  if model.docs[c].type in FLOW and model.docs[c].data is not None and text_assigned(model.docs[c], f)})
    if lit:
        return "dynamic-name", "run by name: " + "; ".join(lit[:2]), lit[:5]
    other = sorted(q for q in up if model.docs[q].type not in PAGELIKE and model.docs[q].type not in FLOW
                   and model.docs[q].type != "Menus$MenuDocument")
    if other:
        return "event-or-startup", "chain ends at " + ", ".join(f"{q} ({model.docs[q].type.split('$')[-1]})" for q in other[:3]), other[:5]
    direct = sorted(q for q in rev.get(hosts[0], ()) if model.docs[q].type in FLOW)
    if direct:
        return "flow-shows-it", "shown by flow " + ", ".join(direct[:3]) + " (the data decides, or the click that runs it sits behind another page)", direct[:5]
    if flows:
        return "flow-chain", "reached through flow " + ", ".join(flows[:3]), flows[:5]
    return "unknown", "no caller found for " + ", ".join(hosts[:2]), []


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("actions")
    ap.add_argument("--model", required=True)
    ap.add_argument("--scope", required=True)
    ap.add_argument("--out")
    ap.add_argument("--md")
    a = ap.parse_args()
    acts = {x["id"]: x for x in json.load(open(a.actions))["actions"]}
    scope = json.load(open(a.scope))["classes"]
    ids = sorted(i for i, v in scope.items() if v["class"] == "reachable-no-path-yet")
    model = Model.load(a.model)
    rev = reverse_index(model)
    cache, out = {}, {}
    for i in ids:
        c, d, ob = cause_of(model, rev, acts[i], cache)
        out[i] = {"cause": c, "detail": d, "opened_by": ob, "host": acts[i]["host"], "roles": acts[i].get("roles")}
    counts = collections.Counter(v["cause"] for v in out.values())
    res = {"tool": "click_causes.py", "counts": dict(counts), "total": len(out), "actions": out}
    if a.out:
        json.dump(res, open(a.out, "w"), indent=1)
    line = f"click causes: {len(out)} actions without a click path: " + ", ".join(f"{k} {counts[k]}" for k in CAUSES if counts[k])
    if a.md:
        rows = ["# Why an in-scope action has no click path", "", line, "", "| cause | n | example |", "|---|---|---|"]
        for k in CAUSES:
            ex = next((i for i, v in out.items() if v["cause"] == k), "")
            if counts[k]:
                rows.append(f"| {k} | {counts[k]} | {ex}: {out[ex]['detail'][:120] if ex else ''} |")
        open(a.md, "w").write("\n".join(rows) + "\n")
    print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
