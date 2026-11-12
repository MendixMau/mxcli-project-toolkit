#!/usr/bin/env python3
"""appshape.py: is this project an APP (something that runs) or a MODULE-ONLY template (BT-2)?

  appshape.py <project dir | App.mpr>      exit 0 APP, 1 MODULE-ONLY, 2 not decidable (never a stop)

Why (batch-templates INCL, Incentro Layouts): a Marketplace download that is a module (layouts, no theme design properties, no
navigation home page) was taken through fetch and triage and stopped at the baseline with "OLD app does not build" and 15 errors
(`Design property ... is not supported by your theme`, `Select a default home page`). That reads as a toolkit failure; the
truth is that the source is not an app, so there is no baseline to freeze. The deciding fact is the one mxbuild would
fail on: no navigation profile has a home page (profile default, a role-based home page, page or microflow). The theme
(no design-properties.json under theme/) is printed as supporting evidence only.

Producer of the call: bin/cloud/upgrade-pipeline.sh step triage (mandatory), which stops with exit 13 and a NEEDS-JUDGMENT
item; UPG_ALLOW_MODULE_ONLY=1 goes on anyway. Read-only; works on MPR v1 and v2 (mprmodel.py).
"""
import glob
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mprmodel import Model  # noqa: E402


def shape(path):
    """('APP'|'MODULE-ONLY'|'UNKNOWN', [facts])"""
    m = Model.load(path)
    nav = m.singletons.get("Navigation$NavigationDocument")
    if not nav:
        return "UNKNOWN", ["no navigation document in the model"]
    homes, profiles = [], 0
    for prof, n in m.navigation().items():
        profiles += 1
        for h in n["homes"]:
            if h.get("page") or h.get("microflow"):
                homes.append(f"{prof}: {h.get('page') or h.get('microflow')}")
    mods = sorted(k for k in m.modules if k != "System")
    facts = [f"modules: {', '.join(mods) or 'none'}", f"navigation profiles: {profiles}", f"home pages set: {len(homes)}"]
    if homes:
        return "APP", facts + [f"home: {homes[0]}"]
    root = os.path.dirname(path) if os.path.isfile(path) else path
    if not any(glob.glob(os.path.join(root, "theme", "**", "design-properties.json"), recursive=True)):
        facts.append("theme: no design-properties.json under theme/")
    return "MODULE-ONLY", facts


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    try:
        verdict, facts = shape(sys.argv[1])
    except SystemExit:
        raise
    except Exception as e:  # an unreadable model is not a reason to stop the run here
        print(f"appshape: UNKNOWN ({type(e).__name__}: {e})")
        sys.exit(2)
    print(f"appshape: {verdict}; " + "; ".join(facts))
    sys.exit({"APP": 0, "MODULE-ONLY": 1}.get(verdict, 2))
