#!/usr/bin/env python3
"""cachebust.py: CE6911 "index.html missing the cachebust template tag(s)": put {{cachebust}} back in theme/web/*.html.

Why (T8R-5, REPAIR R-4, GATE G-5): a 9.x theme/web/index.html carries the cache-bust number hard-coded, e.g.
`mxclientsystem/mxui/mxui.js?637643641483639052` (34 places in FSM) and `cacheBust: "637643641483639052"` in the
dojoConfig. After `mx convert` to 10, mx check says CE6911 for the query strings, which were fixed by hand with a sed;
the dojoConfig value is NOT flagged and stayed until the gate (T8R2 gate patch), so the client kept a stale cache key.

  cachebust.py <project dir> [--apply]

Scans theme/web/*.html (index.html, index-rtl.html, login.html ...) for a query string `?<15 or more digits>` and for
`cacheBust: "<digits>"`, and reports each as WOULD FIX file:line. --apply rewrites both to `{{cachebust}}` (the template
tag Mendix 10 fills in at build time). Nothing else is touched. Idempotent. No theme/web/*.html at all is legal (the
app uses Mendix's built-in index.html; CE6911 cannot occur) and says so.
Exit: 0 = nothing to fix (or all fixed), 1 = fixes needed (dry run), 2 = input error (no .mpr in the directory).
"""
import argparse, glob, os, re, sys

QUERY = re.compile(r"\?(\d{15,})(?=[\"'&#\s>]|$)")
DOJO = re.compile(r"""(cacheBust\s*:\s*)(["'])(\d{6,})\2""")


def fix_line(line):
    n = len(QUERY.findall(line)) + len(DOJO.findall(line))
    new = DOJO.sub(lambda m: f"{m.group(1)}{m.group(2)}{{{{cachebust}}}}{m.group(2)}", QUERY.sub("?{{cachebust}}", line))
    return new, n


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("project"); ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()
    if not os.path.isdir(a.project) or not glob.glob(os.path.join(a.project, "*.mpr")):
        print(f"cachebust: {a.project}: not a Mendix project directory (no .mpr)", file=sys.stderr); sys.exit(2)
    files = sorted(glob.glob(os.path.join(a.project, "theme", "web", "*.html")))
    if not files:
        print("no theme/web/*.html: the app uses Mendix's built-in index.html; nothing to fix"); sys.exit(0)
    total = 0
    for f in files:
        rel = os.path.relpath(f, a.project)
        lines = open(f, encoding="utf-8", newline="").read().splitlines(keepends=True)
        out, here = [], 0
        for i, line in enumerate(lines, 1):
            new, n = fix_line(line)
            if n:
                here += n
                print(f"{'FIXED' if a.apply else 'WOULD FIX'} {rel}:{i}: {line.strip()[:100]}")
            out.append(new)
        if here and a.apply:
            with open(f, "w", encoding="utf-8", newline="") as fh:
                fh.write("".join(out))
        total += here
    print(f"summary: {total} hard-coded cache-bust value(s) in {len(files)} file(s)"
          + ("; dry run, nothing written (--apply)" if total and not a.apply else ""))
    sys.exit(1 if total and not a.apply else 0)


if __name__ == "__main__":
    main()
