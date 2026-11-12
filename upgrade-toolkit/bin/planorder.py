#!/usr/bin/env python3
"""planorder.py: is the update plan in an order that keeps cross-module associations (PV-2)?

A module update that recreates a module (idcheck says MODULE_RECREATED: every unit id is new) drops the associations that
OTHER modules own into it. When the owning module is on the plan too, importing the owner AFTER the target restores the
association with its old GUID in one step. In the wrong order the owner is imported first, the target's update then
drops the association, and mx check shows CE1613 at every flow that used it (Product View 360: OIDC updated before
UserCommons, 17 errors; reimporting OIDC 4.7.0 after UserCommons fixed all of them).

  planorder.py APP plan.txt [--write] [--json out.json]
  APP         the app folder or the .mpr (read with idcheck.py's loader, MPR v1 or v2)
  plan.txt    stepupdate's plan: "<content id> <version> <Module>" per line, # comments allowed
  --write     rewrite plan.txt in the order that satisfies every pair (stable: lines keep their relative order otherwise);
              the old file is kept as plan.txt.orig

For every association owned by a planned module A whose end entity lives in another planned module B:
  ORDER <A> owns <n> association(s) into <B> (e.g. ...): the plan updates <A> (line i) before <B> (line j); put <B> first
  (or reimport <A> after <B>)
A target that is on the plan while its owner is NOT (the owner stays kept) is listed as NOTE: its update drops those
associations and nothing reimports them; use the replay route of steps/upgrade.md item 1 or keep the target.
A cycle (A into B and B into A) cannot be ordered: CYCLE, reimport the owner of the second association after both.
Exit: 0 = order is fine, 1 = at least one ORDER or CYCLE line, 2 = input error.
"""
import argparse, json, os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import idcheck  # noqa: E402


def read_plan(path):
    out = []
    for i, line in enumerate(open(path, encoding="utf-8", errors="replace")):
        raw = line.rstrip("\n")
        body = raw.split("#", 1)[0].strip()
        w = body.split()
        out.append((raw, w[2] if len(w) >= 3 else None))
    return out


def edges(model, planned):
    """{(owner A, target B): [association names]} for associations between two planned modules."""
    e = {}
    for qn, a in model["association"].items():
        owner = a["module"]
        for end in (a.get("parent"), a.get("child")):
            if end and "." in end:
                b = end.split(".")[0]
                if b != owner and owner in planned and b in planned:
                    e.setdefault((owner, b), set()).add(qn)
    return {k: sorted(v) for k, v in e.items()}


def kept_owner_notes(model, planned):
    n = {}
    for qn, a in model["association"].items():
        owner = a["module"]
        for end in (a.get("parent"), a.get("child")):
            if end and "." in end:
                b = end.split(".")[0]
                if b != owner and b in planned and owner not in planned and owner != "System":
                    n.setdefault((owner, b), set()).add(qn)
    return {k: sorted(v) for k, v in n.items()}


def order(mods, e):
    """Stable topological order: target B before owner A. Returns (order, cyclic modules)."""
    before = {m: {b for (a, b) in e if a == m} for m in mods}      # m needs these first
    done, out = set(), []
    left = list(mods)
    while left:
        for m in left:
            if before[m] <= done:
                out.append(m); done.add(m); left.remove(m)
                break
        else:
            return out + left, left
    return out, []


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("app"); ap.add_argument("plan")
    ap.add_argument("--write", action="store_true"); ap.add_argument("--json")
    a = ap.parse_args()
    if not os.path.isfile(a.plan):
        print(f"planorder: no plan file {a.plan}", file=sys.stderr); return 2
    try:
        dm, _ = idcheck.load(a.app)
        model = idcheck.build(dm)
    except SystemExit as ex:
        print(f"planorder: {ex}", file=sys.stderr); return 2
    lines = read_plan(a.plan)
    mods = [m for _, m in lines if m]
    pos = {m: i + 1 for i, (_, m) in enumerate(lines) if m}   # file line numbers
    e = edges(model, set(mods))
    bad = []
    for (own, tgt), names in sorted(e.items()):
        if pos[own] < pos[tgt]:
            bad.append((own, tgt, names))
            eg = ", ".join(names[:2])
            print(f"ORDER {own} owns {len(names)} association(s) into {tgt} (e.g. {eg}): the plan updates {own} (line {pos[own]}) "
                  f"before {tgt} (line {pos[tgt]}); put {tgt} first, or reimport {own} after {tgt}")
    newmods, cyc = order(mods, e)
    for m in cyc:
        print(f"CYCLE {m} is part of a cross-module association cycle on the plan: cannot be ordered, reimport its owner after both")
    for (own, tgt), names in sorted(kept_owner_notes(model, set(mods)).items()):
        print(f"NOTE {tgt} is planned, its owner {own} is not (kept): the {tgt} update drops {len(names)} association(s) "
              f"({', '.join(names[:2])}) and nothing reimports them; replay route (steps/upgrade.md item 1) or keep {tgt}")
    if not bad and not cyc:
        print(f"planorder: {len(mods)} planned module(s), {len(e)} cross-module pair(s) between them, order fine")
    if a.write and bad and not cyc:
        by = {m: raw for raw, m in lines if m}
        out, k = [], 0
        for raw, m in lines:
            if m:
                out.append(by[newmods[k]]); k += 1
            else:
                out.append(raw)
        if not os.path.exists(a.plan + ".orig"):
            os.replace(a.plan, a.plan + ".orig")
        open(a.plan, "w").write("\n".join(out) + "\n")
        print(f"planorder: plan rewritten ({', '.join(newmods)}); the old one is {a.plan}.orig")
    if a.json:
        json.dump({"order": newmods, "violations": [{"owner": o, "target": t, "associations": n} for o, t, n in bad], "cycle": cyc},
                  open(a.json, "w"), indent=1)
    return 1 if (bad or cyc) else 0


if __name__ == "__main__":
    sys.exit(main())
