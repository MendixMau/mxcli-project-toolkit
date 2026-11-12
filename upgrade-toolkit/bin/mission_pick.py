#!/usr/bin/env python3
"""mission_pick.py JOURNEYS_DIR MISSIONS.json [--status N] [--list]

D97: a Task execution page shows the widgets of ONE mission type at ONE task status (shown_if on $Mission/Missiontype
and $Mission/TaskStatus). The name-hop journeys open the first mission in the list, so only that type's buttons ever
appeared. MISSIONS.json = {"list": "TasklistGallery", "types": ["ENTITY_MOVE", ...], "groups": {"EqpMove": "ENTITY_MOVE"}}
(types in the order the stand-in mission list shows them for one status). For every journey that clicks the list this
reads the type and status the final widget needs from its shown_if and rewrites the list row action to the type's nth
row ("nth"), writing "_mission": {type, status} on the journey. --status N keeps only journeys needing status N (the
stand-in list shows one status at a time: one apimock-recorded variant per status), --list prints the plan.
Heal changes the test, never the app: an unreadable condition keeps the first row."""
import glob, json, os, re, sys


def need(j, cfg):
    sh = " || ".join(x for s in j.get("steps", []) for x in s.get("shown_if", []))
    types = set(re.findall(r"MissionType\.(\w+)\)", sh))
    for k, v in cfg.get("groups", {}).items():
        if k in sh:
            types.add(v)
    wid = j["id"].rsplit(".", 1)[-1]
    if len(types) > 1:   # the widget's own name says which one it is for
        for k, v in cfg.get("groups", {}).items():
            if k.replace("Eqp", "Eqp") and k[:6].lower() in wid.lower() and v in types:
                types = {v}
                break
        types = {sorted(types)[0]} if len(types) > 1 else types
    st = set(re.findall(r"TaskStatus = (\d)", sh))
    status = 2 if st == {"2"} else (1 if st == {"1"} else 0)
    return (sorted(types)[0] if types else None), status


def main(a):
    d, cfg = a[0], json.load(open(a[1]))
    only = int(a[a.index("--status") + 1]) if "--status" in a else None
    out = []
    for f in sorted(glob.glob(os.path.join(d, "*", "*.journey.json"))):
        j = json.load(open(f))
        rows = [(i, k) for i, s in enumerate(j["steps"]) for k, q in enumerate(s["actions"])
                if q.get("do") == "row" and q.get("widget") == cfg["list"]]
        if not rows:
            continue
        t, st = need(j, cfg)
        nth = cfg["types"].index(t) if t in cfg["types"] else 0
        out.append((j["id"], t, st, nth))
        if "--list" in a:
            continue
        if only is not None and st != only:
            os.remove(f)
            continue
        for i, k in rows:
            if nth:
                j["steps"][i]["actions"][k]["nth"] = nth
        for st_ in j["steps"]:   # the app asks "release the current Task?" when a task page opens: a person answers Hold and Proceed
            if any(q.get("do") == "menuitem" and q.get("widget") == cfg.get("open", "VerticalbarOpenBtn") for q in st_["actions"]):
                st_["actions"].append({"do": "confirm", "label": "Cancel", "optional": True})
        j["_mission"] = {"type": t, "status": st, "nth": nth}
        json.dump(j, open(f, "w"), indent=1)
    for o in out:
        print(*o, sep="\t")


if __name__ == "__main__":
    main(sys.argv[1:])
