#!/usr/bin/env python3
"""patch_unique.py PATCH APPDIR: exit 0 when a context-free apply of PATCH is unambiguous.

F15 (Purchase Request 10.24, real run): a module update rewrites lines next to a local edit, so the saved patch's
context no longer matches. `git apply -C0` then lands each hunk by its removed lines alone, which is only safe when
those lines occur exactly once in the target file. A hunk that removes nothing (pure addition) has no anchor: refuse.
Exit 1 lists every hunk that is ambiguous or missing.
"""
import os
import sys


def hunks(patch):
    path, cur = None, None
    for line in open(patch, encoding="utf-8", errors="replace").read().splitlines():
        if line.startswith("+++ "):
            path = line[4:].split("\t")[0]
            path = path[2:] if path.startswith("b/") else path
        elif line.startswith("@@"):
            if cur is not None:
                yield cur
            cur = (path, line, [])
        elif cur is not None and line.startswith("-") and not line.startswith("---"):
            cur[2].append(line[1:])
        elif cur is not None and line.startswith("+"):
            pass
        elif cur is not None and cur[2] and not line.startswith("-"):
            cur[2].append(None)  # a break inside the hunk: removed blocks are matched one run at a time
    if cur is not None:
        yield cur


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: patch_unique.py PATCH APPDIR")
    patch, app = sys.argv[1], sys.argv[2]
    bad = []
    for path, head, removed in hunks(patch):
        blocks, run = [], []
        for r in removed + [None]:
            if r is None:
                if run:
                    blocks.append(run)
                run = []
            else:
                run.append(r)
        if not blocks:
            bad.append(f"{path} {head}: removes nothing, no anchor")
            continue
        try:
            text = open(os.path.join(app, path), encoding="utf-8", errors="replace").read().splitlines()
        except OSError:
            bad.append(f"{path}: not found")
            continue
        for b in blocks:
            n = sum(1 for i in range(len(text) - len(b) + 1) if text[i:i + len(b)] == b)
            if n != 1:
                bad.append(f"{path} {head}: removed block found {n} times: {b[0].strip()!r}")
    for b in bad:
        print("AMBIGUOUS " + b)
    if bad:
        sys.exit(1)
    print("unique: every removed block occurs once")


if __name__ == "__main__":
    main()
