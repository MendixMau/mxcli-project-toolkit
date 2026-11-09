#!/usr/bin/env python3
"""build-tree.py — keep a private copy of the model directory for the toolkit's full builds.

    python3 -I bin/build-tree.py <model.mpr> <dest-dir>     # prints the copy's .mpr path last

WHY (#686). `mxbuild --target=deploy` writes <app dir>/deployment/ and takes no option to move it;
`--target=package --output=x.mda` writes there too (measured, mxbuild 11.13.0, PurchaseApp: 336
files under deployment/ rewritten, web/dist included). The running `mxcli run --local --watch` app
serves deployment/web, so every toolkit full build (exec.sh's gate, verify-model.sh from the
pre-push hook and module-close.sh) dropped its web client — /dist/index.js 404 until
`mxcli run restart` (PR #700 run-2 experiment, R22). Building a copy of the app directory leaves the
served folder alone: mxbuild then writes <dest>/deployment/.

The copy is the WHOLE model directory, as bin/doctor.sh's gate self-test copies it (two field
reports: a copy that leaves out a folder mxbuild reads fails the build falsely), minus what a build
never reads. It is kept between builds and synced incrementally: a file is copied only when its size
or mtime differs, and a file or folder that is gone from the model is removed from the copy, so a
deleted javasource file cannot linger and compile. <dest>/deployment/ is the build's own output and
is never touched here.

Excluded top-level names: version control, the build output, caches and the toolkit's own state, and
the project-output folders the toolkit keeps beside a single-tree model (analysis/, sources/,
knowledge-base/, docs/); MXTK_BUILD_TREE_EXCLUDE adds space-separated names. Studio Pro's
*.mpr.lock is never copied (it belongs to the real model, #577).

Exit 0 = synced (stdout: "synced N file(s), removed M", the model directory copied, then the copy's
.mpr path); 1 = it could not
copy (the caller builds in place and says so); 2 = usage. Python 3 stdlib only.
"""
import os
import shutil
import sys

EXCLUDE = {".git", ".svn", ".hg", "deployment", "node_modules", ".mpr-snapshots", ".mxtk", ".mxcli",
           ".claude", "analysis", "sources", "knowledge-base", "docs"}


def skip(name):
    return name in EXCLUDE or name.endswith(".mpr.lock")


def sync_dir(src, dst, top, stats):
    os.makedirs(dst, exist_ok=True)
    want = set()
    with os.scandir(src) as it:
        for e in it:
            if top and skip(e.name):
                continue
            want.add(e.name)
            s, d = e.path, os.path.join(dst, e.name)
            if e.is_dir():  # follows a symlinked folder: the build reads its content
                if os.path.lexists(d) and not os.path.isdir(d):
                    os.remove(d)
                sync_dir(s, d, False, stats)
                continue
            st = e.stat()
            try:
                dt = os.stat(d)
                same = os.path.isfile(d) and dt.st_size == st.st_size and int(dt.st_mtime) == int(st.st_mtime)
            except OSError:
                same = False
            if not same:
                if os.path.isdir(d) and not os.path.islink(d):
                    shutil.rmtree(d)
                shutil.copy2(s, d)
                stats[0] += 1
    with os.scandir(dst) as it:
        for e in list(it):
            if e.name in want or (top and (e.name == "deployment" or skip(e.name))):
                continue
            if e.is_dir() and not e.is_symlink():
                shutil.rmtree(e.path)
            else:
                os.remove(e.path)
            stats[1] += 1


def main(argv):
    if len(argv) != 3:
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 2
    for x in os.environ.get("MXTK_BUILD_TREE_EXCLUDE", "").split():
        EXCLUDE.add(x)
    mpr = os.path.realpath(argv[1])
    src = os.path.dirname(mpr)
    dst = os.path.abspath(argv[2])
    if not os.path.isfile(mpr):
        print("build-tree: no model at %s" % argv[1], file=sys.stderr)
        return 1
    if dst == src or dst.startswith(src + os.sep) and os.path.relpath(dst, src).split(os.sep)[0] not in EXCLUDE:
        print("build-tree: the copy %s would sit inside what it copies" % dst, file=sys.stderr)
        return 1
    stats = [0, 0]
    try:
        # The copy lives under a .mxtk/ folder that ignores itself, so no project .gitignore edit is needed.
        parts = dst.split(os.sep)
        if ".mxtk" in parts:
            mx = os.sep.join(parts[:len(parts) - parts[::-1].index(".mxtk")])
            os.makedirs(mx, exist_ok=True)
            gi = os.path.join(mx, ".gitignore")
            if not os.path.exists(gi):
                with open(gi, "w") as f:
                    f.write("*\n")
        sync_dir(src, dst, True, stats)
    except OSError as e:
        print("build-tree: copy failed: %s" % e, file=sys.stderr)
        return 1
    print("synced %d file(s), removed %d" % (stats[0], stats[1]))
    print(src)
    print(os.path.join(dst, os.path.basename(mpr)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
