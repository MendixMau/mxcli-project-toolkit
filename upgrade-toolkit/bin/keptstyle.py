#!/usr/bin/env python3
"""keptstyle.py: do the themes of kept modules carry rules that hit platform widgets? (MC-11)

Why: a module that stays at its version (kept, stranded, held) keeps its own themesource styling. When the update plan
moves a platform widget (Data Grid 2, Gallery, Combo box and so on) to a new major, the widget's markup and class names
change, and a kept module's rule for the old class names either stops matching or restyles the new markup wrongly. The
model check, build and smoke walk see none of it; only a screenshot does. Asset Console kept a module whose theme
styled the data grid, and the grid looked wrong only on the client.

  keptstyle.py <app dir> --kept A,B   (or --kept-file .stepupdate/kept.txt)   [--json out.json]

Scans themesource/<Module>/**/*.scss|css of each kept module (and the app's own theme/ folders when --kept lists
`theme`) for selectors on platform widget classes: .widget-* (Data Grid 2, Gallery, Combo box, Pop-up menu, ...),
.mx-datagrid*, .mx-listview*, .mx-grid*, .mx-tabcontainer*, .mx-navbar*, .mx-dataview*, .mx-groupbox*. A selector
that only repeats the module's own class (.my-module .btn) is not a platform selector and is not listed.
Output: one `RISK <Module> <file>:<line> <selector>` line per hit, then a summary line. These are visual risks, not
errors: put each module with hits on the screens list so a screenshot of a page with that widget is taken and read.
Exit: 0 = no hits, 1 = hits (REVIEW), 2 = input error.
"""
import argparse, json, os, re, sys

PLATFORM = re.compile(
    r"\.(?:widget-[a-z0-9_-]+|mx-(?:datagrid|listview|grid|tabcontainer|navbar|dataview|groupbox|templategrid|"
    r"scrollcontainer|navigationtree|progress|button-bar)[a-z0-9_-]*)", re.I)
COMMENT = re.compile(r"/\*.*?\*/", re.S)
EXT = (".scss", ".css")


def die(msg):
    print(msg, file=sys.stderr); sys.exit(2)


def scan(path):
    try:
        text = open(path, encoding="utf8", errors="replace").read()
    except OSError:
        return []
    text = COMMENT.sub(lambda m: "\n" * m.group(0).count("\n"), text)
    hits = []
    for i, line in enumerate(text.splitlines(), 1):
        s = line.strip()
        # a selector line: ends with { or , or opens a nested block; declarations (a: b;) are skipped
        if not s or s.startswith("//") or (";" in s and "{" not in s):
            continue
        if not (s.endswith("{") or s.endswith(",") or "{" in s):
            continue
        m = PLATFORM.search(s)
        if m:
            hits.append((i, s.rstrip("{ ").strip()[:120], m.group(0)))
    return hits


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("app")
    ap.add_argument("--kept", default=None)
    ap.add_argument("--kept-file")
    ap.add_argument("--json")
    a = ap.parse_args()
    if not os.path.isdir(a.app):
        die("keptstyle: not a directory: " + a.app)
    if a.kept is None and not a.kept_file:
        die("keptstyle: give --kept A,B (or --kept ''), or --kept-file FILE")
    if a.kept_file:
        try:
            raw = open(a.kept_file).read()
        except OSError as e:
            die("keptstyle: " + str(e))
        kept = [x for x in re.split(r"[,\s]+", raw) if x and not x.startswith("#")]
    else:
        kept = [x for x in a.kept.split(",") if x.strip()]
    rows, mods = [], set()
    for mod in kept:
        roots = [os.path.join(a.app, "themesource", mod)]
        if mod == "theme":
            roots = [os.path.join(a.app, "theme")]
        for root in roots:
            for dp, dn, fn in os.walk(root):
                dn[:] = [d for d in dn if d not in ("node_modules", "public")]
                for f in sorted(fn):
                    if f.lower().endswith(EXT):
                        p = os.path.join(dp, f)
                        for ln, sel, cls in scan(p):
                            rows.append((mod, os.path.relpath(p, a.app), ln, sel, cls))
                            mods.add(mod)
    for mod, rel, ln, sel, cls in rows:
        print(f"RISK {mod} {rel}:{ln} {sel}")
    print(f"keptstyle: {len(kept)} kept module(s) scanned, {len(rows)} platform widget selector(s) in {len(mods)} module(s)"
          + ("; take a screenshot of a page with each affected widget (steps/triage.md, MC-11)" if rows else ""))
    if a.json:
        json.dump([dict(module=m, file=r, line=l, selector=s, cls=c) for m, r, l, s, c in rows], open(a.json, "w"), indent=1)
    sys.exit(1 if rows else 0)


main()
