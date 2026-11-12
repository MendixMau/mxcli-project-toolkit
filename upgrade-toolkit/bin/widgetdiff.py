#!/usr/bin/env python3
"""widgetdiff.py: which widgets/*.mpk did the working copy change against a commit, and from which version to which? (NS-6)

Why: a module import also imports the widgets its package carries, and Studio Pro / mxcli replace the shared copies in
widgets/ without a word. notification-service cdd62cc5 ("added email connector module") swapped 9 widgets, Data grid
2.28.3 -> 2.30.6 among them; nobody saw it until the team reverted the data grid widgets on day 111 (d870f330). A module
step must name every widget it changed, so the person who planned "Email Connector" sees "Datagrid 2.28.3 -> 2.30.6".

  widgetdiff.py <app dir> [--rev HEAD]

One line per changed package: "<path> <name> <old> -> <new>", "<path> <name> added <new>" or "<path> <name> removed
(was <old>)". The version and name come from package.xml (clientModule name and version); "?" when it cannot be read.
Untracked .mpk files count as added. Nothing changed: no output.
Exit: 0 = read (with or without changes), 2 = input error (no git repository, unknown rev).
"""
import argparse, io, os, re, subprocess, sys, zipfile


def die(msg):
    print(msg, file=sys.stderr); sys.exit(2)


def meta(data):
    """(name, version) from an .mpk's package.xml; '?' for what cannot be read."""
    try:
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            x = z.read("package.xml").decode("utf-8", "replace")
    except Exception:
        return "?", "?"
    m = re.search(r"<clientModule\b[^>]*>", x)
    tag = m.group(0) if m else ""
    n, v = re.search(r'\bname="([^"]*)"', tag), re.search(r'\bversion="([^"]*)"', tag)
    return (n.group(1) if n else "?"), (v.group(1) if v else "?")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("app"); ap.add_argument("--rev", default="HEAD")
    a = ap.parse_args()
    app = os.path.abspath(a.app)
    git = lambda *x, text=True: subprocess.run(["git", "-C", app, *x], capture_output=True, text=text)
    if git("rev-parse", "--verify", "--quiet", f"{a.rev}^{{commit}}").returncode != 0:
        die(f"widgetdiff: {a.rev}: not a commit in the git repository of {app}")
    changed = git("diff", "--relative", "--name-status", "--no-renames", a.rev, "--", "widgets/")
    untracked = git("ls-files", "--others", "--exclude-standard", "--", "widgets/")
    rows = [ln.split("\t", 1) for ln in changed.stdout.splitlines() if "\t" in ln]
    rows += [["A", p] for p in untracked.stdout.splitlines() if p]
    prefix = git("rev-parse", "--show-prefix").stdout.strip()
    out = []
    for st, p in sorted(rows, key=lambda r: r[1]):
        if not p.endswith(".mpk"):
            continue
        new = open(os.path.join(app, p), "rb").read() if os.path.isfile(os.path.join(app, p)) else None
        old = git("show", f"{a.rev}:{prefix}{p}", text=False)
        old = old.stdout if old.returncode == 0 else None
        if old is not None and new is not None:
            (on, ov), (nn, nv) = meta(old), meta(new)
            out.append(f"{p} {nn if nn != '?' else on} {ov} -> {nv}")
        elif new is not None:
            nn, nv = meta(new)
            out.append(f"{p} {nn} added {nv}")
        elif old is not None:
            on, ov = meta(old)
            out.append(f"{p} {on} removed (was {ov})")
    if out:
        print("\n".join(out))
    sys.exit(0)


if __name__ == "__main__":
    main()
