#!/usr/bin/env python3
"""widget_defaults.py: the defaults a widget swap applies to properties that have no counterpart (playbooks/widget-config-defaults.tsv).

  widget_defaults.py --widget Gallery [--mapped p1,p2,...] [--table FILE]
  widget_defaults.py --widget Gallery --mapped ... --commit APP --subject "swap TemplateGrid to Gallery on Home" -- <path> [<path> ...]

Prints one line per table row of the target widget whose property is not in --mapped:
  defaulted: <property> = <value> (best practice, <source>)      verified=doc       the docs state what the value follows from
  defaulted: <property> = <value> (widget default, <source>)     verified=manifest  the widget's own XML default
  not defaulted: <property> (unverified, <reason>)               verified=unverified: listed, never applied
A property the source widget had is MAPPED (--mapped), never defaulted. The list ends with a count line (the denominator):
  widget_defaults: <widget>: N table row(s), M mapped, A defaulted, U not defaulted (unverified)
--commit hands the swap to bin/appcommit.sh (explicit paths only): the commit subject is the --subject followed by every
"defaulted:" line, so CHANGES.md (bin/changelog.py) shows them in the "why" cell of that change. Trailers: Changed-By: agent,
Upgrade-Change: convert widget-defaults-<widget>.
Producer of the table: playbooks/widget-config-defaults.tsv (hand-kept, every source opened). Consumer: the person or agent doing the swap
(steps/decide.md, widget swap), the reviewer reading CHANGES.md.
Exit: 0 listed (or committed), 2 input error (unknown widget, no table, appcommit refused)."""
import argparse, os, subprocess, sys

TK = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))


def load(path):
    rows, head = [], None
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            c = line.split("\t")
            if head is None:
                head = c
                continue
            rows.append(dict(zip(head, c + [""] * (len(head) - len(c)))))
    return rows


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--widget", required=True)
    ap.add_argument("--mapped", default="", help="comma list of target properties the swap mapped from the source widget")
    ap.add_argument("--table", default=os.path.join(TK, "playbooks", "widget-config-defaults.tsv"))
    ap.add_argument("--commit", metavar="APP")
    ap.add_argument("--subject", default="")
    ap.add_argument("--step", help="the step (S-n) this swap does; becomes the Upgrade-Step trailer (needs --work or UPG_STEPS_WORK)")
    ap.add_argument("--work")
    ap.add_argument("paths", nargs="*")
    a = ap.parse_args()
    try:
        rows = load(a.table)
    except OSError as e:
        print(f"widget_defaults: cannot read {a.table}: {e}", file=sys.stderr)
        return 2
    mine = [r for r in rows if r["target_widget"].lower() == a.widget.lower()]
    if not mine:
        print(f"widget_defaults: no row for target widget {a.widget} in {a.table}", file=sys.stderr)
        return 2
    mapped = {x.strip().lower() for x in a.mapped.split(",") if x.strip()}
    out, d, u, m = [], 0, 0, 0
    for r in mine:
        p = r["property"]
        if p.lower() in mapped:
            m += 1
            continue
        src = r["source"].split(" ; ")[0]
        if r["verified"] == "doc":
            out.append(f"defaulted: {p} = {r['default']} (best practice, {src})"); d += 1
        elif r["verified"] == "manifest":
            out.append(f"defaulted: {p} = {r['default']} (widget default, {src})"); d += 1
        else:
            out.append(f"not defaulted: {p} (unverified, {r['reason']})"); u += 1
    out.append(f"widget_defaults: {mine[0]['target_widget']}: {len(mine)} table row(s), {m} mapped, {d} defaulted, {u} not defaulted (unverified)")
    if not a.commit:
        print("\n".join(out))
        return 0
    if not a.paths or not a.subject:
        print("widget_defaults: --commit needs --subject and the explicit paths after --", file=sys.stderr)
        return 2
    why = a.subject + "; " + "; ".join(x for x in out if x.startswith("defaulted:"))
    why = why.replace("\n", " ")
    r = subprocess.run(["bash", os.path.join(TK, "bin", "appcommit.sh"), "--app", a.commit, "--by", "agent", "--kind", "convert",
                        "--rule", "widget-defaults-" + a.widget.lower(), "--why", why] + (["--step", a.step] if a.step else []) + (["--work", a.work] if a.work else []) + ["--"] + a.paths)
    print(out[-1])
    return 0 if r.returncode == 0 else 2


if __name__ == "__main__":
    sys.exit(main())
