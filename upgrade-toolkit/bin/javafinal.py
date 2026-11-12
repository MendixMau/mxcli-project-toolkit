#!/usr/bin/env python3
"""javafinal.py: 9 -> 10 precheck. Find user code that assigns to a Java action parameter field.

Why: Mendix 10 generates Java action parameters as `private final` fields. Own code like
`this.ContentType = "application/json";` inside BEGIN USER CODE is legal in 9 and a javac error in 10. mx check reports
0 errors; only mxbuild fails, minutes later (E5 F19: 3 rest_responses actions). Run this in triage on the 9.x app.

  javafinal.py <project dir or javasource dir> [--md out.md]

For every javasource/**/actions/*.java with a generated parameter field list (private fields declared before the
constructor), scans the BEGIN USER CODE and BEGIN EXTRA CODE blocks for `Name = `, `this.Name = `, `Name += ` and
`Name++`/`++Name` where Name is a parameter field and not a local variable declared in that block.
Fix pattern: copy into a local (`String contentType = this.ContentType;`) and use the local.
Exit: 0 = none, 1 = assignments found, 2 = no Java actions found.
"""
import argparse, glob, os, re, sys

FIELD = re.compile(r"^\s*private\s+(?:final\s+)?[\w.<>\[\], ]+?\s+(\w+)\s*;", re.M)
BLOCK = re.compile(r"//\s*BEGIN (USER|EXTRA) CODE(.*?)//\s*END \1 CODE", re.S)


def strip_comments_strings(s):
    s = re.sub(r"/\*.*?\*/", lambda m: "\n" * m.group(0).count("\n"), s, flags=re.S)
    s = re.sub(r"//[^\n]*", "", s)
    return re.sub(r'"(?:\\.|[^"\\])*"', '""', s)


def scan(path):
    src = open(path, errors="replace").read()
    ctor = re.search(r"\bpublic\s+\w+\s*\(\s*IContext\b", src)
    head = src[:ctor.start()] if ctor else ""
    params = [f for f in FIELD.findall(head) if f not in ("context",)]
    if not params:
        return None, []
    hits = []
    for m in BLOCK.finditer(src):
        body = strip_comments_strings(m.group(2))
        line0 = src[:m.start(2)].count("\n") + 1
        for p in params:
            local = re.search(rf"(?:[\w.<>\[\]]+)\s+{p}\s*[=;:,)]", body)  # `String Name = ...` shadows the field
            pat = rf"(?<![\w.])(this\.)?{p}\s*(?:[+\-*/]?=(?!=)|\+\+|--)|(?:\+\+|--)\s*(this\.)?{p}\b"
            for a in re.finditer(pat, body):
                if local and not a.group(0).startswith("this."):
                    continue
                ln = line0 + body[:a.start()].count("\n")
                hits.append((p, ln, src.splitlines()[ln - 1].strip()))
    return params, hits


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("project"); ap.add_argument("--md")
    a = ap.parse_args()
    root = a.project if os.path.basename(a.project.rstrip("/")) == "javasource" else os.path.join(a.project, "javasource")
    files = sorted(glob.glob(os.path.join(root, "**", "actions", "*.java"), recursive=True))
    actions, out = 0, []
    for f in files:
        params, hits = scan(f)
        if params is None:
            continue
        actions += 1
        for p, ln, text in hits:
            out.append(f"FINAL {os.path.relpath(f, root)}:{ln}  parameter {p} assigned in user code: {text[:120]}")
    if not actions:
        print(f"javafinal: no Java actions under {root}", file=sys.stderr); sys.exit(2)
    out.append(f"summary: {actions} Java actions scanned, {len(out)} assignments to parameter fields (javac error on Mendix 10)")
    print("\n".join(out))
    if a.md:
        open(a.md, "w").write("\n".join(out) + "\n")
    sys.exit(1 if len(out) > 1 else 0)


if __name__ == "__main__":
    main()
