#!/usr/bin/env python3
"""renamed_modules.py: installed Marketplace modules whose listing was renamed or republished under a new name (BT-6).

  renamed_modules.py <localedits.json> [--table playbooks/module-renames.tsv] [--out renamed.md]
  exit 0 none found, 1 at least one RENAMED / REPUBLISHED module (information for the plan, not a failure), 2 unreadable input

Why (batch-templates TOUR, DOCGEN): a module the Marketplace renamed keeps its content id (DataGrid 1.1.3 is now DataWidgets,
content 116540). localedits.py then found no package under the old name (UNKNOWN, download HTTP 500), triage printed no
RENAMED line although publisher-lessons.md T1-14 promised one, stepupdate had no route, and the proposal listed nothing: the
module sat silently outside the plan, the kept list and the proposal. ApprontoLicenser 7.0.1 (content 1445) was republished
as "Emixa Licenser module" 1.0.0, a new numbering, which looks like a downgrade. Nothing in the MPR or in localedits.json says
so; the answer is DATA, playbooks/module-renames.tsv, matched by content id (old name when the MPR has no id).

Producer of the input: steps/triage.md item 3 (localedits.py --json, mandatory). Consumers: bin/cloud/upgrade-pipeline.sh step
triage (writes renamed.md) and bin/proposal.py (a section-3 decision item per hit, and no plan line for that module).
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TABLE = os.path.join(HERE, "..", "playbooks", "module-renames.tsv")


def load_table(path=TABLE):
    rows = []
    for ln in open(path, encoding="utf-8").read().splitlines():
        if not ln.strip() or ln.startswith("#") or ln.startswith("id\t"):
            continue
        f = ln.split("\t")
        if len(f) >= 6:
            rows.append(dict(zip(("id", "cid", "old", "new", "kind", "route", "source"), f + [""])))
    return rows


def find(modules, table=None):
    """modules: [{name, cid, version}] (localedits.json). Returns one dict per module that is renamed or republished."""
    out = []
    for m in modules:
        for r in table if table is not None else load_table():
            if m.get("name") == r["new"]:
                continue  # already carries the new name
            by_cid = str(m.get("cid") or 0) == r["cid"]
            by_name = not m.get("cid") and m.get("name") == r["old"]
            if by_cid or by_name:
                out.append({"module": m.get("name"), "cid": r["cid"], "version": m.get("version"), "new": r["new"],
                            "kind": r["kind"], "route": r["route"], "row": r["id"], "source": r["source"]})
                break
    return out


def render(hits):
    L = ["# Renamed or republished Marketplace modules", ""]
    for h in hits:
        L.append(f"{h['kind']} {h['module']} {h['version']} (content {h['cid']}) -> {h['new']}: {h['route']} [{h['row']}, playbooks/module-renames.tsv]")
    if not hits:
        L.append("none of the installed modules is in playbooks/module-renames.tsv (the table lists the renames met so far, not every rename)")
    return "\n".join(L) + "\n"


if __name__ == "__main__":
    a = sys.argv[1:]
    if not a or a[0].startswith("-"):
        sys.exit(__doc__)
    table, out = TABLE, None
    if "--table" in a:
        table = a[a.index("--table") + 1]
    if "--out" in a:
        out = a[a.index("--out") + 1]
    try:
        mods = json.load(open(a[0]))
        hits = find(mods, load_table(table))
    except (OSError, ValueError, TypeError, AttributeError) as e:
        print(f"renamed_modules: cannot read {a[0]} ({type(e).__name__}: {e})", file=sys.stderr)
        sys.exit(2)
    txt = render(hits)
    if out:
        open(out, "w", encoding="utf-8").write(txt)
    sys.stdout.write(txt)
    sys.exit(1 if hits else 0)
