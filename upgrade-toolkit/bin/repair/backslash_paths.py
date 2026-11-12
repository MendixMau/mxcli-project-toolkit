#!/usr/bin/env python3
"""backslash_paths.py: find files a module update wrote with Windows separators in the name, and move them home.

Why: in run E1, `mxcli marketplace update` of OQL 4.2.0 wrote 17 files as literal names like
'javasource\\oql\\actions\\AddBooleanParameter.java' in the app root (on macOS/Linux a backslash is a normal file
name character) and deleted the real javasource/oql/actions/*.java. mx check passed; the Java build failed.

  backslash_paths.py <project dir> [--apply]

Reports every file or folder whose name holds a backslash, with the target path. --apply moves each one to its
real path (creating folders) and refuses to overwrite an existing different file. Exit: 0 = none (or all moved),
1 = found (report mode) or a move was refused, 2 = input error.
"""
import argparse, filecmp, os, sys


def find(root):
    out = []
    for d, dirs, files in os.walk(root):
        dirs[:] = [x for x in dirs if x not in (".git", "node_modules", "deployment", ".mendix-cache")]
        for f in files + dirs:
            if "\\" in f:
                src = os.path.join(d, f)
                out.append((src, os.path.join(d, *f.split("\\"))))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("project"); ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()
    if not os.path.isdir(a.project):
        print(f"backslash_paths: {a.project}: not a folder", file=sys.stderr); sys.exit(2)
    rows = find(a.project)
    refused = 0
    for src, dst in rows:
        rs, rd = os.path.relpath(src, a.project), os.path.relpath(dst, a.project)
        if not a.apply:
            print(f"BACKSLASH {rs}  ->  {rd}" + ("  (target exists)" if os.path.exists(dst) else ""))
            continue
        if os.path.exists(dst) and not (os.path.isfile(dst) and filecmp.cmp(src, dst, shallow=False)):
            print(f"REFUSED   {rs}: {rd} exists with other content"); refused += 1; continue
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        os.replace(src, dst)
        print(f"MOVED     {rs}  ->  {rd}")
    print(f"summary: {len(rows)} names with a backslash" + (f", {refused} refused" if a.apply else ""))
    sys.exit(1 if (refused or (rows and not a.apply)) else 0)


if __name__ == "__main__":
    main()
