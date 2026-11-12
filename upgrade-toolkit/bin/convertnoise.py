#!/usr/bin/env python3
"""convertnoise.py: does a convert commit hold only what mx convert makes, or something else besides? (NS-10, NS-13)

Why: notification-service 3fbf1566 is the convert to 11.12.4: 790 model units, 23 widget packages and a new metadata
file, all made by mx convert. The same commit also added 456 other paths (.ai-context/, .claude/, docs/,
tests/e2e/, an 87 MB mxcli binary, a .gitignore block). A reviewer cannot tell the convert from the rest, a revert of
the convert takes the rest with it, and a diff of the convert reads as one wall of change.

  convertnoise.py <app dir> [--rev HEAD]

--rev is the convert commit; it is compared with its first parent. Every changed path gets one class:
  model        *.mpr, mprcontents/**: the convert's own rewrite of the model. Known noise in it (3fbf1566): IsRequired
               added on 127 microflow units, "$value != empty" rewritten to "length(toString($value)) > 0" in 42
               places, AppStorePackageId -> AppStorePackageIdString on 41 modules
  noise        widgets/*.mpk whose only change is the removed "appstore.id" entry (contents otherwise byte equal),
               widgets/widgets-appstore-metadata.json (the convert writes it)
  regenerated  javasource/**, javascriptsource/** (action stubs and JSDoc the convert rewrites), userlib/**,
               vendorlib/** (jars the convert moves), theme-cache/** and **/_generated-exclusion-variables.scss
               (the convert regenerates both; MC-4: called FOREIGN on the 10.24 convert of a Mendix 10.12 app)
  WIDGET       a widgets/*.mpk whose contents changed beyond appstore.id: a widget version step, not the convert
  FOREIGN      anything else (tool files, docs, tests, .gitignore): not made by mx convert
WIDGET and FOREIGN paths belong in their own commits: commit the convert alone, then each other change.
Exit: 0 = convert only, 1 = WIDGET or FOREIGN paths (REVIEW), 2 = input error (no git repository, unknown rev, root
commit).
"""
import argparse, io, os, subprocess, sys, zipfile
from collections import Counter

MODEL = ("mprcontents/",)
REGEN = ("javasource/", "javascriptsource/", "userlib/", "vendorlib/")
META = "widgets/widgets-appstore-metadata.json"
GENERATED_THEME = "_generated-exclusion-variables.scss"   # themesource/<module>/web/ (MC-4)


def die(msg):
    print(msg, file=sys.stderr); sys.exit(2)


def entries(data):
    """{name: crc} of an .mpk's files (directory entries left out); None when it is no zip."""
    try:
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            return {i.filename: i.CRC for i in z.infolist() if not i.filename.endswith("/")}
    except Exception:
        return None


def classify(path, old, new):
    if path.endswith(".mpr") or path.startswith(MODEL):
        return "model"
    if path == META:
        return "noise"
    if path.startswith("widgets/") and path.endswith(".mpk"):
        if old is None or new is None:
            return "WIDGET"
        o, n = entries(old), entries(new)
        if o is not None and n is not None and "appstore.id" in o and "appstore.id" not in n:
            o.pop("appstore.id")
            if o == n:
                return "noise"
        return "WIDGET"
    if path.startswith(REGEN) or path.startswith("theme-cache/") or os.path.basename(path) == GENERATED_THEME:
        return "regenerated"
    return "FOREIGN"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("app"); ap.add_argument("--rev", default="HEAD")
    a = ap.parse_args()
    app = os.path.abspath(a.app)
    git = lambda *x, text=True: subprocess.run(["git", "-C", app, *x], capture_output=True, text=text)
    if git("rev-parse", "--verify", "--quiet", f"{a.rev}^{{commit}}").returncode != 0:
        die(f"convertnoise: {a.rev}: not a commit in the git repository of {app}")
    if git("rev-parse", "--verify", "--quiet", f"{a.rev}^1").returncode != 0:
        die(f"convertnoise: {a.rev} has no parent to compare with")
    prefix = git("rev-parse", "--show-prefix").stdout.strip()
    names = git("diff", "--relative", "--name-status", "--no-renames", f"{a.rev}^1", a.rev)
    cls, flagged = Counter(), []
    for ln in names.stdout.splitlines():
        if "\t" not in ln:
            continue
        st, p = ln.split("\t", 1)
        old = new = None
        if p.startswith("widgets/") and p.endswith(".mpk"):
            o = git("show", f"{a.rev}^1:{prefix}{p}", text=False)
            n = git("show", f"{a.rev}:{prefix}{p}", text=False)
            old = o.stdout if o.returncode == 0 else None
            new = n.stdout if n.returncode == 0 else None
        c = classify(p, old, new)
        cls[c] += 1
        if c in ("WIDGET", "FOREIGN"):
            flagged.append((c, p))
    subj = git("log", "-1", "--format=%h %s", a.rev).stdout.strip()
    total = sum(cls.values())
    head = (f"convertnoise: {subj}: {total} changed paths: {cls['model']} model, {cls['noise']} noise, "
            f"{cls['regenerated']} regenerated, {cls['WIDGET']} WIDGET, {cls['FOREIGN']} FOREIGN")
    lines = [f"WIDGET  {p}: contents changed beyond the appstore.id entry (a widget step, not the convert)"
             for c, p in flagged if c == "WIDGET"]
    groups = Counter()
    for c, p in flagged:
        if c == "FOREIGN":
            groups[p.split("/", 1)[0] + ("/" if "/" in p else "")] += 1
    lines += [f"FOREIGN {g} ({n} path{'s' if n != 1 else ''}): not made by mx convert" for g, n in sorted(groups.items())]
    verdict = ("verdict: REVIEW (the convert commit holds more than the convert: commit the convert alone, then each "
               "other change in its own commit)" if flagged else "verdict: PASS (convert only)")
    print("\n".join([head] + lines + [verdict]))
    sys.exit(1 if flagged else 0)


if __name__ == "__main__":
    main()
