#!/usr/bin/env python3
"""rolecheck.py: module roles that a module update ADDED and no user role holds (PLM-26, NR2-16), and mapped module roles
that no longer exist (MC-8, MC-9).

Why: Atlas_Core 3.21 added the module roles Atlas_Core.User and Atlas_Core.Administrator. Nothing mapped them to a user
role, `mx check` was clean, the build was green, and 13 of 15 smoke pages failed with "Executing action failed for
security reasons" (HTTP 560, a microflow the layout calls is only allowed for the new role). It showed at the smoke rung,
after a full gate run. The model says it earlier: a module role that exists in the NEW model and not in the OLD one,
held by no user role (Security$ProjectSecurity.UserRoles[].ModuleRoles), is unmapped.

  rolecheck.py <OLD project|mpr> <NEW project|mpr> [--waive FILE] [--json out.json]

stepupdate.sh runs it after every module update (previous step against this one, waive file
<app>/.stepupdate/roles-waived.txt) and repeats the open rows in its summary (exit 1).

Output, one line per added module role:
  UNMAPPED Mod.Role  (Mod x -> y): held by no user role; proposal: <user roles that hold a role of the same name in
                     another module, else the user roles that hold a role of module Mod, else "decide">
  mapped   Mod.Role  held by User, Administrator
  WAIVED   Mod.Role  (reason)
A module that is new in NEW counts too (all its roles are added).
Two more rows for the opposite case (MC-9: Atlas_Web_Content 3.9.0 removed UserRole, which the app had mapped; nothing
said so, and mxcli ALTER USER ROLE later wrote the same dangling reference without an error, MC-8):
  REMOVED-MAPPED Mod.Role  the update removed a module role that a user role of the NEW model still references
  DANGLING       Mod.Role  a user role references a module role that does not exist in NEW (never did, or removed
                           in an earlier step; this needs no OLD model, so a mapping written after the update shows too)
Fix both by dropping the reference or mapping the role that replaced it (Studio Pro, or mxcli ALTER USER ROLE ... REMOVE
MODULE ROLES), then rerun. Run it right after any role-mapping MDL, not only after an update.
waive file: one line per accepted role, "Mod.Role # reason". A line without a reason is not accepted (INVALID, exit 2).
Exit: 0 nothing unmapped or dangling, 1 at least one UNMAPPED, REMOVED-MAPPED or DANGLING, 2 input error.
"""
import argparse, json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


def module_roles(model):
    out = {}
    for qn, d in model.docs.items():
        if d.type == "Security$ModuleSecurity":
            for r in d.data.get("ModuleRoles") or []:
                if isinstance(r, dict) and r.get("Name"):
                    out.setdefault(d.module, set()).add(r["Name"])
    return out


def held_by(model):
    idx = {}
    for ur, mrs in model.user_roles().items():
        for mr in mrs:
            idx.setdefault(mr, set()).add(ur)
    return idx


def check(old, new, waived):
    """[(status, "Mod.Role", text)] for every module role added by the update."""
    orl, nrl = module_roles(old), module_roles(new)
    held = held_by(new)
    ov, nv = old.modules, new.modules
    rows = []
    for mod in sorted(nrl):
        for role in sorted(nrl[mod] - orl.get(mod, set())):
            qn = f"{mod}.{role}"
            holders = sorted(held.get(qn, ()))
            if qn in waived:
                rows.append(("WAIVED", qn, f"({waived[qn]})")); continue
            if holders:
                rows.append(("mapped", qn, f"held by {', '.join(holders)}")); continue
            same = sorted({u for q, us in held.items() if q.split(".", 1)[1].lower() == role.lower() and q != qn for u in us})
            sib = sorted({u for q, us in held.items() if q.split(".", 1)[0] == mod for u in us})
            prop = (f"user roles holding a role named {role} in another module: {', '.join(same)}" if same else
                    f"user roles holding another {mod} role: {', '.join(sib)}" if sib else "decide")
            vo = (ov.get(mod) or {}).get("version") if isinstance(ov.get(mod), dict) else None
            vn = (nv.get(mod) or {}).get("version") if isinstance(nv.get(mod), dict) else None
            ver = f" ({mod} {vo or 'new'} -> {vn or '?'})"
            rows.append(("UNMAPPED", qn, f"{ver.strip()}: held by no user role; proposal: {prop}"))
    rows += dangling(old, new, waived)
    return rows


def dangling(old, new, waived):
    """REMOVED-MAPPED and DANGLING rows: module roles that user roles of NEW reference and NEW does not have (MC-8, MC-9)."""
    orl, nrl = module_roles(old), module_roles(new)
    rows = []
    for ur, mrs in sorted(new.user_roles().items()):
        for qn in mrs:
            mod, _, role = qn.partition(".")
            if not role or mod not in new.modules or role in nrl.get(mod, set()):
                continue   # not a module role reference, a module not in the model (idcheck's business) or fine
            if qn in waived:
                rows.append(("WAIVED", qn, f"({waived[qn]})")); continue
            if role in orl.get(mod, set()):
                rows.append(("REMOVED-MAPPED", qn, f"removed by the update, still held by user role {ur}; "
                             f"{mod} now has: {', '.join(sorted(nrl.get(mod, set()))) or 'no module roles'}"))
            else:
                rows.append(("DANGLING", qn, f"held by user role {ur} but {mod} has no such module role "
                             f"(it has: {', '.join(sorted(nrl.get(mod, set()))) or 'none'})"))
    return rows


def read_waive(path):
    waived = {}
    if path and os.path.exists(path):
        for n, line in enumerate(open(path), 1):
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            role, _, why = line.partition("#")
            if not why.strip():
                print(f"rolecheck: {path} line {n}: '{role.strip()}' has no reason after '#'; a waiver without a reason is not accepted",
                      file=sys.stderr); sys.exit(2)
            waived[role.strip()] = why.strip()
    return waived


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("old"); ap.add_argument("new"); ap.add_argument("--waive"); ap.add_argument("--json")
    a = ap.parse_args()
    import mprmodel
    try:
        old, new = mprmodel.Model.load(a.old), mprmodel.Model.load(a.new)
    except (SystemExit, Exception) as e:
        print(f"rolecheck: cannot read the models: {e}", file=sys.stderr); sys.exit(2)
    rows = check(old, new, read_waive(a.waive))
    bad = [r for r in rows if r[0] == "UNMAPPED"]
    gone = [r for r in rows if r[0] in ("REMOVED-MAPPED", "DANGLING")]
    added = [r for r in rows if r[0] not in ("REMOVED-MAPPED", "DANGLING") and not (r[0] == "WAIVED" and r[1] in {g[1] for g in gone})]
    print(f"rolecheck: {len(added)} module role(s) added by the update, {len(bad)} unmapped; "
          f"{len(gone)} mapped role(s) that no longer exist")
    for st, qn, tx in rows:
        print(f"{st:<8} {qn}  {tx}")
    bad += gone
    if bad:
        print("verdict: REVIEW (map each in Studio Pro or with mxcli, drop a reference to a removed role, or waive with a reason in the waive file, BEFORE the smoke rung)")
    if a.json:
        json.dump([{"status": s, "role": q, "detail": t} for s, q, t in rows], open(a.json, "w"), indent=1)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
