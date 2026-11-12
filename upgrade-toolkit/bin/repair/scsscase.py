#!/usr/bin/env python3
"""scsscase.py: rewrite SCSS imports whose path has the wrong letter case to the case on disk.

Why: publisher themes import e.g. "../web/buildingblocks/commandBar/commandBar" while the folder is
`commandbar/_commandbar.scss`. Windows and macOS (case-insensitive) build it; mxbuild on Linux fails the theme
compile. Found independently in T2-5 and N1-7, each time fixed by a hand-written script.

  scsscase.py <project dir> [--check]

Scans theme/ and themesource/ for *.scss and rewrites @import / @use / @forward paths (relative to the importing
file) that do not exist case-sensitively but do case-insensitively, to the on-disk case. Prints one FIX line per
rewrite and a summary. Writes by default; --check reports without writing. An import that resolves neither way
(or an http, ~, sass: or .css one) is never touched. Idempotent. Exit: 0 = nothing to fix (or all fixed),
1 = fixes needed (--check), 2 = input error.
"""
import argparse, os, re, sys

SKIP_DIRS = {".git", "node_modules", "deployment", ".mendix-cache"}
DIRECTIVE = re.compile(r"""@(?:import|use|forward)\s+((?:"[^"\n]*"|'[^'\n]*')(?:\s*,\s*(?:"[^"\n]*"|'[^']*'))*)""")
STRING = re.compile(r"""(["'])([^"'\n]*)\1""")
# (prefix, suffix) Sass adds to the last segment when looking for a file; ("", "") also finds a folder
VARIANTS = [("", ""), ("", ".scss"), ("_", ".scss"), ("", ".sass"), ("_", ".sass"), ("_", "")]


def isfile_or_dir(p):
    return os.path.exists(p)


def resolve(base, imp):
    """Return the import with on-disk case, or None when unresolvable, or imp itself when already exact."""
    parts = imp.split("/")
    cur, out = base, []
    for k, part in enumerate(parts):
        if part in ("", ".", ".."):
            out.append(part); cur = os.path.normpath(os.path.join(cur, part)) if part else cur; continue
        if not os.path.isdir(cur):
            return None
        names = os.listdir(cur)
        last = k == len(parts) - 1
        variants = VARIANTS if last else [("", "")]
        for pre, suf in variants:                       # exact case first: nothing to change for this segment
            if pre + part + suf in names:
                out.append(part); cur = os.path.join(cur, pre + part + suf); break
        else:
            for pre, suf in variants:
                want = (pre + part + suf).lower()
                hit = sorted(n for n in names if n.lower() == want)
                if hit:
                    n = hit[0]
                    out.append(n[len(pre):len(n) - len(suf)] if suf else n[len(pre):])
                    cur = os.path.join(cur, n); break
            else:
                return None
    return "/".join(out)


def scan(root):
    for top in ("theme", "themesource"):
        for d, dirs, files in os.walk(os.path.join(root, top)):
            dirs[:] = sorted(x for x in dirs if x not in SKIP_DIRS)
            for f in sorted(files):
                if f.endswith(".scss"):
                    yield os.path.join(d, f)


def fix_file(path, fixes):
    with open(path, encoding="utf-8", errors="surrogateescape", newline="") as fh:
        lines = fh.read().split("\n")
    base = os.path.dirname(path)
    changed = False
    for i, line in enumerate(lines):
        def on_directive(m):
            def on_string(s):
                imp = s.group(2)
                if re.match(r"^(https?:|//|~|sass:|url\()", imp) or imp.endswith(".css") or "#{" in imp:
                    return s.group(0)
                new = resolve(base, imp)
                if new is None or new == imp:
                    return s.group(0)
                fixes.append((path, i + 1, imp, new))
                return s.group(1) + new + s.group(1)
            return STRING.sub(on_string, m.group(0))
        new_line = DIRECTIVE.sub(on_directive, line)
        if new_line != line:
            lines[i] = new_line; changed = True
    return "\n".join(lines) if changed else None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("project"); ap.add_argument("--check", action="store_true")
    a = ap.parse_args()
    if not os.path.isdir(a.project):
        print(f"scsscase: {a.project}: not a folder", file=sys.stderr); sys.exit(2)
    nfiles = nfix = 0
    for p in scan(a.project):
        fixes = []
        text = fix_file(p, fixes)
        if text is None:
            continue
        nfiles += 1; nfix += len(fixes)
        rp = os.path.relpath(p, a.project)
        for _, ln, old, new in fixes:
            print(f"{'WOULD FIX' if a.check else 'FIXED    '} {rp}:{ln}: {old}  ->  {new}")
        if not a.check:
            with open(p, "w", encoding="utf-8", errors="surrogateescape", newline="") as fh:
                fh.write(text)
    print(f"summary: {nfix} import(s) with wrong case in {nfiles} file(s)" + (" (not written)" if a.check and nfix else ""))
    sys.exit(1 if (a.check and nfix) else 0)


if __name__ == "__main__":
    main()
