#!/usr/bin/env python3
"""cut-ledger.py — engine of bin/cut-ledger.sh (read that header; this file has no CLI of its own
beyond what the wrapper passes). Python 3 stdlib only."""
import argparse
import fnmatch
import json
import os
import re
import sqlite3
import sys

COLS = ["edge", "direction", "kind", "source_doc", "target_doc", "refs", "resolution", "evidence"]
RESOLUTIONS = ("resolved", "stub", "handoff", "retire", "platform")
REFS_COLS = ["SourceType", "SourceName", "TargetType", "TargetName", "RefKind"]


def die(msg):
    print(msg, file=sys.stderr)
    sys.exit(2)


def doc_of(name):
    """Qualified document name: the first two dotted parts (Module.Doc[.Member…] -> Module.Doc)."""
    p = name.split(".")
    return ".".join(p[:2]) if len(p) >= 2 else name


def read_slice(path):
    mods, docs = set(), set()
    for line in open(path, encoding="utf-8"):
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        (docs if "." in line else mods).add(line)
    if not mods and not docs:
        die("cut-ledger: slice file %s names nothing" % path)
    return mods, docs


def in_slice(name, mods, docs):
    return name.split(".")[0] in mods or doc_of(name) in docs


def read_refs(args):
    rows = []
    if args.catalog:
        db = sqlite3.connect("file:%s?mode=ro" % args.catalog, uri=True)
        if not db.execute("select 1 from sqlite_master where name='refs'").fetchone():
            die("cut-ledger: %s has no refs table (not an mxcli catalog; run graph-report)" % args.catalog)
        for r in db.execute("select %s from refs" % ", ".join(REFS_COLS)):
            rows.append(dict(zip(REFS_COLS, r)))
    else:
        with open(args.refs, encoding="utf-8") as f:
            head = f.readline().rstrip("\n").split("\t")
            if head != REFS_COLS:
                die("cut-ledger: %s header must be %s" % (args.refs, "\t".join(REFS_COLS)))
            bad = []
            for n, line in enumerate(f, 2):
                if not line.strip():
                    continue
                v = line.rstrip("\n").split("\t")
                if len(v) == len(REFS_COLS):
                    rows.append(dict(zip(REFS_COLS, v)))
                else:
                    bad.append(n)
            if bad:
                # A dropped line is a crossing edge nobody decided on; refusing beats a short ledger.
                die("cut-ledger: %s has %d line(s) without %d tab-separated fields (first: line %d)"
                    % (args.refs, len(bad), len(REFS_COLS), bad[0]))
    return rows


def read_rules(path):
    rules = []
    for n, line in enumerate(open(path, encoding="utf-8"), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        v = line.rstrip("\n").split("\t")
        if len(v) < 4:
            die("cut-ledger: %s:%d needs 4 tab-separated fields (direction, pattern, resolution, evidence)" % (path, n))
        d, pat, res, ev = v[0].strip(), v[1].strip(), v[2].strip(), v[3].strip()
        if d not in ("out", "in", "check", "*"):
            die("cut-ledger: %s:%d direction %r is not out|in|check|*" % (path, n, d))
        if res.split(":")[0] not in RESOLUTIONS:
            die("cut-ledger: %s:%d resolution %r is not one of %s (a ':detail' suffix is allowed)" % (path, n, res, "|".join(RESOLUTIONS)))
        if not ev:
            die("cut-ledger: %s:%d has no evidence; a resolution without evidence is a claim" % (path, n))
        rules.append((d, pat, res, ev, n))
    return rules


def match(rules, direction, other_doc, own_doc):
    """First rule whose direction fits and whose pattern matches the far-side doc.
    A pattern 'A -> B' matches own side A and far side B (both fnmatch)."""
    for d, pat, res, ev, n in rules:
        if d not in ("*", direction):
            continue
        if "->" in pat:
            a, b = [x.strip() for x in pat.split("->", 1)]
            if fnmatch.fnmatchcase(own_doc, a) and fnmatch.fnmatchcase(other_doc, b):
                return res, ev, n
        elif fnmatch.fnmatchcase(other_doc, pat):
            return res, ev, n
    return None


CHECK_NAME = re.compile(r"\[error\] \[CE1613\] \"The selected [^']*'([A-Za-z0-9_]+\.[^']+)' no longer exists")


def main():
    ap = argparse.ArgumentParser(prog="cut-ledger")
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--catalog")
    src.add_argument("--refs")
    ap.add_argument("--slice", required=True)
    ap.add_argument("--rules", required=True)
    ap.add_argument("--check-log", action="append", default=[])
    ap.add_argument("--exporter-json", action="append", default=[])
    ap.add_argument("--extra", action="append", default=[])
    ap.add_argument("--dump-refs")
    ap.add_argument("-o", "--out", required=True)
    args = ap.parse_args()

    mods, docs = read_slice(args.slice)
    refs = read_refs(args)
    rules = read_rules(args.rules)

    crossing = [r for r in refs if in_slice(r["SourceName"], mods, docs) != in_slice(r["TargetName"], mods, docs)]
    if args.dump_refs:
        with open(args.dump_refs, "w", encoding="utf-8") as f:
            f.write("\t".join(REFS_COLS) + "\n")
            for r in sorted(crossing, key=lambda r: (r["SourceName"], r["TargetName"], r["RefKind"])):
                f.write("\t".join(r[c] for c in REFS_COLS) + "\n")

    # one ledger row per (direction, kind, source doc, target doc); refs = how many catalog refs it carries
    agg = {}
    for r in crossing:
        direction = "out" if in_slice(r["SourceName"], mods, docs) else "in"
        key = (direction, r["RefKind"], doc_of(r["SourceName"]), doc_of(r["TargetName"]))
        agg[key] = agg.get(key, 0) + 1

    rows, used_rules = [], set()
    for (direction, kind, s, t), n in sorted(agg.items(), key=lambda kv: (kv[0][0] != "out", kv[0][3], kv[0][2], kv[0][1])):
        own, other = (s, t) if direction == "out" else (t, s)
        if other.split(".")[0] == "System" and direction == "out":
            res, ev = "platform", "System module exists in every Mendix app"
        else:
            m = match(rules, direction, other, own)
            if m:
                res, ev, rn = m
                used_rules.add(rn)
            else:
                res, ev = "UNRESOLVED", "no rule in %s matches %s" % (os.path.basename(args.rules), other)
        rows.append([direction, kind, s, t, str(n), res, ev])

    # mx check names the catalog never recorded (widget actions, layout placeholders, images, ...)
    covered = {r[3] for r in rows if r[0] == "out"} | {doc_of(r[3]) for r in rows if r[0] == "out"}
    check_extra = {}
    for log in args.check_log:
        for line in open(log, encoding="utf-8", errors="replace"):
            m = CHECK_NAME.search(line)
            if not m:
                continue
            name = m.group(1)
            if in_slice(name, mods, docs) or doc_of(name) in covered:
                continue
            check_extra[doc_of(name)] = check_extra.get(doc_of(name), 0) + 1
    for d, n in sorted(check_extra.items()):
        m = match(rules, "check", d, "") or match(rules, "out", d, "")
        if m:
            res, ev, rn = m
            used_rules.add(rn)
        else:
            res, ev = "UNRESOLVED", "named by mx check, not in the catalog, no rule matches"
        rows.append(["out", "check-only", "(mx check)", d, str(n), res, ev])

    # edges no catalog holds (second-order edges of a module brought along, app-level settings,
    # Java hand-offs): direction, kind, source_doc, target_doc, refs, resolution, evidence — verbatim
    for ex in args.extra:
        for n, line in enumerate(open(ex, encoding="utf-8"), 1):
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            v = line.rstrip("\n").split("\t")
            if len(v) != 7 or v[5].split(":")[0] not in RESOLUTIONS or not v[6].strip():
                die("cut-ledger: %s:%d needs 7 fields with a known resolution and evidence" % (ex, n))
            rows.append(v)

    # reconcile against the exporter's per-module counts: a module it names with no ledger row is reported
    exporter_notes = []
    out_mods = {}
    for r in rows:
        if r[0] == "out":
            out_mods[r[3].split(".")[0]] = out_mods.get(r[3].split(".")[0], 0) + 1
    for ej in args.exporter_json:
        txt = open(ej, encoding="utf-8").read()
        j = json.loads(txt[txt.index("{"):txt.rindex("}") + 1])
        for mod, units in sorted(j.get("crossing_refs_by_module", {}).items()):
            if mod not in out_mods:
                exporter_notes.append("%s: exporter counts %d unit(s) naming it, ledger has 0 out-edges to it" % (mod, units))

    with open(args.out, "w", encoding="utf-8") as f:
        f.write("\t".join(COLS) + "\n")
        for i, r in enumerate(rows, 1):
            f.write("\t".join(["E%03d" % i] + r) + "\n")

    tot = {}
    for r in rows:
        k = r[5].split(":")[0]
        tot[k] = tot.get(k, 0) + 1
    unused = [n for d, p, res, ev, n in rules if n not in used_rules]
    n_extra = len(rows) - len(agg) - len(check_extra)
    print("cut-ledger: %d crossing refs -> %d ledger rows (%d out, %d in from the catalog; %d check-only; %d extra) -> %s" % (
        len(crossing), len(rows), sum(1 for k in agg if k[0] == "out"), sum(1 for k in agg if k[0] == "in"),
        len(check_extra), n_extra, args.out))
    print("  by resolution: " + ", ".join("%s %d" % (k, tot[k]) for k in sorted(tot)))
    for note in exporter_notes:
        print("  exporter-only: " + note)
    if unused:
        print("  rules never used (lines): " + ", ".join(map(str, unused)))
    if tot.get("UNRESOLVED"):
        print("  UNRESOLVED rows: %d — every crossing edge needs a rule (resolved, stub, handoff, retire)" % tot["UNRESOLVED"])
        return 1
    return 0


if __name__ == "__main__":
    # Exit 1 means "an edge is UNRESOLVED" and nothing else: an unreadable input (missing file, a
    # path that is not a catalog, malformed exporter JSON) is a bad argument, exit 2, never 1.
    try:
        rc = main()
    except (OSError, ValueError, sqlite3.Error) as e:
        die("cut-ledger: cannot read an input: %s: %s" % (type(e).__name__, e))
    sys.exit(rc)
