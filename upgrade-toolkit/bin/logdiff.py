#!/usr/bin/env python3
"""logdiff.py: compare the START log of the old and the new app, not only its ERROR lines.

Why: in run E1 two regressions were visible only as INFO lines of the after-startup phase. The old app logged
"MFAmodule: MFA module login active", the new one "... login NOT active" (a constant reset by a module update), and a
deprecated after-startup microflow logged "Change your ASU to v2". The ERROR-only log check passed.

  logdiff.py OLD.log NEW.log [--allow allow.txt] [--md out.md] [--json out.json]

Reads Mendix runtime log lines "YYYY-MM-DD hh:mm:ss.mmm LEVEL - Node: message" (docker logs of runapp.py, or the
runtime log file). Only the START window counts: from the first line to "Mendix Runtime successfully started" (or
the end of the file if that line is missing). Inside it, the AFTER-STARTUP section runs from "Running after-startup-
action" to "Successfully ran after-startup-action". Signature = level + node + message with numbers, ids and quoted
values masked.

Verdicts:
  START_FAILED       new log has no "successfully started" line, the old one has          FAIL
  NEW_ERROR          ERROR/CRITICAL signature not in the old start window                 FAIL
  MOVED              that ERROR signature is in the old log after the start window        REVIEW
                     (logged lazily before, in the start window now: SAML in run E4)
  CHANGED / NEW / GONE  any INFO/WARNING line of the after-startup section that differs    REVIEW
                     (lines of one node are paired: "login active" -> "login NOT active")
  NEW_WARNING        WARNING signature elsewhere in the start window, not in the old one  REVIEW
  other INFO lines   outside after-startup (platform start noise)                         INFO, counted only
allow.txt: one fnmatch pattern per line on the signature ("WARNING Node: message"), then " # reason". An allowed
REVIEW or FAIL becomes PASS*. Exit: 0 = nothing open, 1 = open FAIL or REVIEW, 2 = input error.
"""
import argparse, fnmatch, json, re, sys
from difflib import SequenceMatcher

LINE = re.compile(r"^(?:\S+ )?(\d{4}-\d\d-\d\d[ T]\d\d:\d\d:\d\d(?:[.,]\d+)?) (TRACE|DEBUG|INFO|WARNING|WARN|ERROR|CRITICAL) - ([^:]+?): ?(.*)$")
STARTED = "Mendix Runtime successfully started"
AS_BEGIN, AS_END = "Running after-startup-action", "Successfully ran after-startup-action"


def sig(level, node, msg):
    m = re.sub(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", "~", msg)
    m = re.sub(r"\b[0-9a-f]{12,}\b", "~", m)
    m = re.sub(r"'[^']*'", "'~'", m)
    m = re.sub(r"\d+", "#", m)
    lv = "WARNING" if level == "WARN" else level
    return f"{lv} {node.strip()}: {m.strip()}"[:240]


def parse(path):
    lines = open(path, errors="replace").read().splitlines()
    out, started, phase = [], False, "start"
    for raw in lines:
        m = LINE.match(raw)
        if not m:
            continue
        _, level, node, msg = m.groups()
        text = f"{node}: {msg}"
        if AS_BEGIN in text:
            phase = "after"
        out.append({"phase": phase, "level": "WARNING" if level == "WARN" else level, "node": node.strip(),
                    "sig": sig(level, node, msg)})
        if AS_END in text:
            phase = "start"
        if STARTED in text:
            started = True
            break
    return out, started, len(lines)


def error_sigs(path):
    """ERROR/CRITICAL signatures of the WHOLE file (not only the start window), same masking as parse()."""
    out = set()
    for raw in open(path, errors="replace").read().splitlines():
        m = LINE.match(raw)
        if m and m.group(2) in ("ERROR", "CRITICAL"):
            out.add(sig(m.group(2), m.group(3), m.group(4)))
    return out


def compare(o, ost, n, nst, allow=(), old_all=()):
    """o/n: parse() lines; returns (rows, info_new). allow: [(pattern, reason)] on the signature.
    old_all: error_sigs() of the whole old log; a new start-window ERROR found there is MOVED (REVIEW), not NEW_ERROR."""
    rows = []

    def add(verdict, kind, s, detail=""):
        if verdict in ("FAIL", "REVIEW"):
            for pat, why in allow:
                if fnmatch.fnmatch(s, pat):
                    verdict, detail = "PASS*", (detail + f" (accepted: {why})").strip(); break
        rows.append((verdict, kind, s, detail))

    if ost and not nst:
        add("FAIL", "START_FAILED", "new start window has no 'successfully started' line", f"{len(n)} log lines before the end")
    if not ost:
        add("INFO", "BASELINE", "old log has no 'successfully started' line: the whole file is the window")
    osig = {x["sig"] for x in o}
    for s in sorted({x["sig"] for x in n if x["level"] in ("ERROR", "CRITICAL")} - osig):
        if s in old_all:
            add("REVIEW", "MOVED", s, "ERROR is in the old log too, after the start window: logged earlier now")
        else:
            add("FAIL", "NEW_ERROR", s)
    oa = [x for x in o if x["phase"] == "after" and x["level"] in ("INFO", "WARNING", "ERROR", "CRITICAL")]
    na = [x for x in n if x["phase"] == "after" and x["level"] in ("INFO", "WARNING", "ERROR", "CRITICAL")]
    if ost and not oa:
        add("INFO", "NO_AFTER_STARTUP", "old log has no after-startup section", "")
    gone = [x for x in oa if x["sig"] not in {y["sig"] for y in na}]
    new = [x for x in na if x["sig"] not in {y["sig"] for y in oa}]
    for g in list(gone):  # pair a gone and a new line of the same node when they look alike
        cands = [x for x in new if x["node"] == g["node"]]
        if cands:
            best = max(cands, key=lambda x: SequenceMatcher(None, g["sig"], x["sig"]).ratio())
            if SequenceMatcher(None, g["sig"], best["sig"]).ratio() > 0.5:
                add("REVIEW", "CHANGED", best["sig"], f"was: {g['sig']}")
                new.remove(best); gone.remove(g)
    for x in new:
        if x["level"] not in ("ERROR", "CRITICAL"):
            add("REVIEW", "NEW", x["sig"], "after-startup line not in the old log")
    for x in gone:
        add("REVIEW", "GONE", x["sig"], "after-startup line of the old log is missing")
    for s in sorted({x["sig"] for x in n if x["level"] == "WARNING" and x["phase"] != "after"} - osig):
        add("REVIEW", "NEW_WARNING", s)
    info_new = len({x["sig"] for x in n if x["level"] == "INFO" and x["phase"] != "after"} - osig)
    return rows, info_new


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("old"); ap.add_argument("new")
    ap.add_argument("--allow"); ap.add_argument("--md"); ap.add_argument("--json")
    a = ap.parse_args()
    (o, ost, on), (n, nst, nn) = parse(a.old), parse(a.new)
    if not o or not n:
        print(f"logdiff: INVALID, no Mendix log lines in {'old' if not o else 'new'} log", file=sys.stderr); sys.exit(2)
    allow = []
    if a.allow:
        for line in open(a.allow):
            if line.strip() and not line.lstrip().startswith("#"):
                pat, _, why = line.partition("#"); allow.append((pat.strip(), why.strip() or "allowed"))
    rows, info_new = compare(o, ost, n, nst, allow, error_sigs(a.old))
    order = {"FAIL": 0, "REVIEW": 1, "PASS*": 2, "INFO": 3}
    rows.sort(key=lambda r: (order[r[0]], r[1], r[2]))
    counts = {k: sum(1 for r in rows if r[0] == k) for k in order}
    oa = [x for x in o if x["phase"] == "after"]; na = [x for x in n if x["phase"] == "after"]
    lines = [f"# logdiff {a.old} -> {a.new}", "",
             f"start window: old {len(o)} lines (started: {ost}), new {len(n)} lines (started: {nst}); "
             f"after-startup lines old {len(oa)}, new {len(na)}; other new INFO signatures outside after-startup: {info_new}",
             " | ".join(f"{k} {v}" for k, v in counts.items()), ""]
    lines += [f"{v:6} {k:16} {s}" + (f"\n{'':24}{d}" if d else "") for v, k, s, d in rows]
    out = "\n".join(lines)
    print(out)
    if a.md:
        open(a.md, "w").write(out + "\n")
    if a.json:
        json.dump([dict(zip(("verdict", "kind", "signature", "detail"), r)) for r in rows], open(a.json, "w"), indent=1)
    sys.exit(1 if counts["FAIL"] or counts["REVIEW"] else 0)


if __name__ == "__main__":
    main()
