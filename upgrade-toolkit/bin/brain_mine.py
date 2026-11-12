#!/usr/bin/env python3
"""brain_mine.py: candidate replacement patterns mined from the brain's release-note tables, no LLM (B6-2).

The replacement map (playbooks/replacements.tsv) was written from research; the brain already holds the same kind of
fact as release-note rows: a component marked Deprecated in the index, a row of type deprecation or removal, a row
whose 'replaced by' cell names the successor. This script reads them all and writes the candidates, grouped two ways:

  1. Deprecated components   index rows with support 'Deprecated' (the whole component is end of life)
  2. Recurring successors     the same 'replaced by' target named by rows of several components (a pattern: Combo Box
                              replaces the reference selector in N modules), most components first
  3. Rows                     every deprecation/removal row and every row with a 'replaced by' cell, per component

Each candidate says whether replacements.tsv already covers it (the R ids whose pattern, replacement or detect text
names the component or the successor) or 'new'. A candidate is a lead for a human to promote into the table, never a
table row itself: the brain names components by display name, the table detects by module name (B6-1 UNVERIFIED).

usage: brain_mine.py [--brain DIR] [--table replacements.tsv] [--to VER] [--min N] [--out brain-patterns.md]
                     [--tsv candidates.tsv]
  --brain  default $UPG_BRAIN or ~/Mendix/<company>-brain (read only, never written)
  --table  default playbooks/replacements.tsv next to this bin/
  --to     drop rows of component versions whose min Mendix is above VER (not installable on the target)
  --min    components a successor needs to count as recurring (default 2)
  --tsv    also write every row candidate as TSV (component, slug, version, min_mendix, type, affected, replaced_by,
           covered, change)
Prints one summary line: 'brain-mine: D deprecated components, P recurring successors, R rows, N new (not in table)'.
Exit 0 on a written report, 2 when the brain or the table cannot be read.
"""
import argparse
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from release_impact import tables, squash, vt, cmpv  # noqa: E402
from replacement_check import read_table, TableError  # noqa: E402

KEEP_TYPES = {"deprecation", "removal"}
# successor cells that name no component: a version, a placeholder, a sentence fragment
NOT_A_TARGET = re.compile(r"^(n/?a|none|-|—|\?|see .*|v?\d+(\.\d+)*)$", re.I)


def norm_target(s):
    s = re.sub(r"\s+", " ", re.sub(r"\b(the|new|mendix|widget|module|connector)\b", " ", s, flags=re.I)).strip(" .,")
    return squash(s)


def load_brain(root):
    v = Path(root) / "baseline" / "versions"
    mods = v / "modules"
    if not mods.is_dir():
        raise OSError(f"no brain module tables at {mods}")
    deprecated = []
    idx = v / "modules-index.md"
    if idx.exists():
        for head, rows in tables(idx.read_text(errors="replace")):
            if "module" not in head or "support" not in head:
                continue
            h = {k: i for i, k in enumerate(head)}
            for r in rows:
                if len(r) < len(head) or r[h["support"]].lower() != "deprecated":
                    continue
                m = re.match(r"^\[\s*(.*?)\]\(modules/([^)]+)\.md\)", r[h["module"]])
                name, slug = (m.group(1), m.group(2)) if m else (r[h["module"]], "")
                deprecated.append({"component": name, "slug": slug, "latest": r[h.get("latest", 0)],
                                   "min": r[h["min mendix (latest)"]] if "min mendix (latest)" in h else "?"})
    rows = []
    for f in sorted(mods.glob("*.md")):
        text = f.read_text(errors="replace")
        first = text.split("\n", 1)[0]
        m = re.match(r"^#\s*(.*?)\s*\(Marketplace component (\d+)\)", first)
        comp = m.group(1) if m else first.lstrip("# ").strip()
        minv = {}
        for head, body in tables(text):
            if head[:1] == ["version"] and "min mendix" in head:
                i = head.index("min mendix")
                minv.update({r[0]: r[i] for r in body if len(r) > i})
            if not {"version", "type", "change", "replaced by"} <= set(head):
                continue
            h = {k: i for i, k in enumerate(head)}
            for r in body:
                if len(r) < len(head):
                    continue
                typ, rep = r[h["type"]].lower(), r[h["replaced by"]]
                if NOT_A_TARGET.match(rep or "-"):
                    rep = ""
                if typ not in KEEP_TYPES and not rep:
                    continue
                rows.append({"component": comp, "slug": f.stem, "version": r[h["version"]],
                             "min": minv.get(r[h["version"]], "?"), "type": typ,
                             "affected": r[h["affected"]] if "affected" in h else "", "replaced_by": rep,
                             "change": r[h["change"]]})
    return deprecated, rows


def coverage(table):
    """[(R id, squashed text of pattern + replacement + detect)]"""
    return [(r["id"], squash(" ".join((r["pattern"], r["replacement"], r["detect"])))) for r in table]


def covered_by(names, cov):
    # the name as written and without filler words (Combo Box widget -> combobox), so a suffix does not hide a match
    keys = [k for n in names if n for k in {squash(n), norm_target(n)} if len(k) >= 4]
    return [rid for rid, txt in cov if any(k in txt for k in keys)]


def main():
    here = Path(__file__).resolve().parent
    ap = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    ap.add_argument("--brain", default=os.environ.get("UPG_BRAIN")
                    or str(Path.home() / "Mendix/<company>-brain"))
    ap.add_argument("--table", default=str(here.parent / "playbooks" / "replacements.tsv"))
    ap.add_argument("--to")
    ap.add_argument("--min", type=int, default=2)
    ap.add_argument("--out", default="brain-patterns.md")
    ap.add_argument("--tsv")
    a = ap.parse_args()
    try:
        deprecated, rows = load_brain(a.brain)
        cov = coverage(read_table(a.table))
    except (OSError, TableError) as e:
        print(f"brain_mine: {e}", file=sys.stderr)
        sys.exit(2)
    if a.to:
        to = vt(a.to)
        rows = [r for r in rows if not (vt(r["min"]) and cmpv(vt(r["min"]), to) > 0)]
    for d in deprecated:
        d["covered"] = covered_by([d["component"], d["slug"]], cov)
    for r in rows:
        r["covered"] = covered_by([r["component"], r["replaced_by"]] + [x for x in r["affected"].split(",")
                                                                        if len(squash(x)) >= 6], cov)

    groups = {}
    for r in rows:
        if r["replaced_by"]:
            g = groups.setdefault(norm_target(r["replaced_by"]), {"names": {}, "comps": {}, "rows": 0})
            g["names"][r["replaced_by"]] = g["names"].get(r["replaced_by"], 0) + 1
            g["comps"][r["component"]] = r["affected"]
            g["rows"] += 1
    recurring = sorted(((max(g["names"], key=g["names"].get), g) for k, g in groups.items()
                        if k and len(g["comps"]) >= a.min), key=lambda x: (-len(x[1]["comps"]), x[0].lower()))

    new = sum(1 for d in deprecated if not d["covered"]) + sum(1 for r in rows if not r["covered"])
    cell = lambda s: str(s).replace("|", "/").replace("\n", " ")  # noqa: E731
    cv = lambda ids: ", ".join(ids) if ids else "**new**"  # noqa: E731
    out = [f"# Brain patterns: replacement candidates (B6-2)", "",
           f"Mined by bin/brain_mine.py from {a.brain} (read only) against {a.table}. No LLM. A candidate is a lead "
           "to promote into replacements.tsv by hand, never a table row: the brain names components by display name.",
           "", f"## 1. Deprecated components ({len(deprecated)})", "",
           "| component | latest | min Mendix | covered |", "|---|---|---|---|"]
    out += [f"| [{cell(d['component'])}](modules/{d['slug']}.md) | {d['latest']} | {d['min']} | {cv(d['covered'])} |"
            for d in deprecated]
    out += ["", f"## 2. Recurring successors ({len(recurring)}, named by {a.min}+ components)", "",
            "| successor | components | rows | which (affected) | covered |", "|---|---|---|---|---|"]
    for name, g in recurring:
        which = "; ".join(f"{c} ({cell(x)})" if x else c for c, x in sorted(g["comps"].items()))
        out.append(f"| {cell(name)} | {len(g['comps'])} | {g['rows']} | {cell(which)} | "
                   f"{cv(covered_by([name], cov))} |")
    out += ["", f"## 3. Rows ({len(rows)})", "",
            "| component | version | min Mendix | type | affected | replaced by | covered | change |",
            "|---|---|---|---|---|---|---|---|"]
    out += [f"| {cell(r['component'])} | {r['version']} | {r['min']} | {r['type']} | {cell(r['affected'])} | "
            f"{cell(r['replaced_by'])} | {cv(r['covered'])} | {cell(r['change'])} |" for r in rows]
    line = (f"brain-mine: {len(deprecated)} deprecated components, {len(recurring)} recurring successors, "
            f"{len(rows)} rows, {new} new (not in table)")
    Path(a.out).write_text("\n".join(out + ["", line, ""]))
    if a.tsv:
        keys = ["component", "slug", "version", "min", "type", "affected", "replaced_by", "covered", "change"]
        with open(a.tsv, "w") as f:
            f.write("\t".join(k if k != "min" else "min_mendix" for k in keys) + "\n")
            for r in rows:
                f.write("\t".join(cell(",".join(r[k]) if k == "covered" else r[k]).replace("\t", " ")
                                  for k in keys) + "\n")
    print(line)


if __name__ == "__main__":
    main()
