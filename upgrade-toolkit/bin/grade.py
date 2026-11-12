#!/usr/bin/env python3
"""grade.py: how much of an upgrade run is done. Reads a gate-summary.md and prints one grade line plus buckets.

    grade.py GATE-SUMMARY.md [--notes FILE] [--stamp] [--history [HISTORY.md] --run ID --app NAME ...]

Definition (steps/report.md, READING-THE-VERDICT.md section 6):
  required rungs: build, idcheck, const, data, logdiff, smoke, journeys, screens, release (9). `widgets` is a 10th
  when the gate ran it (any verdict but NOT RUN). `rest` and `apis` are optional and are listed, never graded.
  Every required rung lands in one bucket:
    proven     PASS
    accepted   PASS*  (accepted in writing)
    waiting    INVALID or NOT RUN that a person must settle: guest process, release rows open, by-eye review, a rerun
    untestable INVALID, NOT RUN or EXCEPT that needs customer systems, keys or a licence
    open       FAIL (an open regression, or a failing rung). Never counted as done.
  grade = (proven + accepted) / required rungs. The grade never replaces the verdict word; it is printed next to it.

--notes FILE (default: grade-notes.tsv next to the summary): one line per item, tab separated
    rung <TAB> bucket <TAB> owner <TAB> text          bucket: waiting | untestable | open
  A note can downgrade a PASS or PASS* rung (the gate did not see it, e.g. a crash found by hand), or move an INVALID
  rung between waiting and untestable. It can never raise a rung to done. rung `-` adds an open item without touching
  a rung. owner: person | customer | toolkit.

Exit code is always 0 for a readable summary (the grade is information; the gate's own exit code is the verdict).
"""
import argparse, datetime, os, re, subprocess, sys

REQUIRED = ["build", "idcheck", "const", "data", "logdiff", "smoke", "journeys", "screens", "release"]
OPTIONAL = ["rest", "apis"]
BUCKETS = ["proven", "accepted", "waiting", "untestable", "open"]
LABEL = {"proven": "proven", "accepted": "accepted", "waiting": "waiting on a person",
         "untestable": "not testable here", "open": "open regression"}
UNTESTABLE = re.compile(r"licen[cs]e|\bkeys?\b|credential|NOT CHECKED|excluded|customer system|\bAWS\b|\bVPN\b|not reachable", re.I)
TOOLKIT_OWNED = re.compile(r"timed out|instrument not measuring|failed \(rc", re.I)
ROW = re.compile(r"^\| *(\d+) *\| *(\w+) *\| *([^|]+?) *\| *([^|]*?) *\| *(.*?) *\|$")


def parse(path):
    overall, rows, run = "?", {}, ""
    classes = {}
    for ln in open(path, encoding="utf-8", errors="replace"):
        ln = ln.rstrip("\n")
        if ln.startswith("Classes:"):
            classes = dict(x.split("=", 1) for x in ln[8:].split() if "=" in x)
        m = re.match(r"^Overall: \*\*(.+?)\*\*", ln)
        if m:
            overall = m.group(1)
        m = re.search(r", run (\w+)\.", ln) if ln.startswith("Work:") else None
        if m:
            run = m.group(1)
        m = ROW.match(ln.replace("\\|", "\x01"))
        if m:
            rows[m.group(2)] = (m.group(3).strip(), m.group(5).replace("\x01", "|"))
    return overall, rows, run, classes


def classify(rung, verdict, text, cls=""):
    """-> (bucket or None when not graded, owner). cls: the gate's own report class for the rung (Classes: line)."""
    if verdict == "PASS":
        return "proven", ""
    if verdict == "PASS*":
        return "accepted", ""
    if verdict == "FAIL":
        # the gate's Progress line and this grade count alike: only a regression is open; a FAIL that is waiting on a
        # review is waiting on a person, one with nothing failed is not measured yet (no Classes line: open, as before)
        if cls == "decision":
            return "waiting", "person"
        if cls == "unmeasured":
            return "waiting", "toolkit"
        return "open", "toolkit"
    if verdict == "EXCEPT":
        return "untestable", "customer"
    if UNTESTABLE.search(text):
        return "untestable", "customer"
    return "waiting", "toolkit" if TOOLKIT_OWNED.search(text) else "person"


def read_notes(path):
    out = []
    if path and os.path.isfile(path):
        for ln in open(path, encoding="utf-8"):
            ln = ln.rstrip("\n")
            if not ln.strip() or ln.lstrip().startswith("#"):
                continue
            p = (ln.split("\t") + ["", "", "", ""])[:4]
            out.append(tuple(x.strip() for x in p))
    return out


def grade(summary, notes_path=None):
    overall, rows, run, classes = parse(summary)
    graded = list(REQUIRED)
    if "widgets" in rows and rows["widgets"][0] not in ("NOT RUN", "(dry-run)"):
        graded.append("widgets")
    items = []   # (rung, bucket, owner, text)
    res = {}
    for r in graded:
        v, t = rows.get(r, ("NOT RUN", "no row in the summary"))
        b, o = classify(r, v, t, classes.get(r, ""))
        res[r] = [v, b, o, t]
    for rung, bucket, owner, text in read_notes(notes_path):
        if bucket not in ("waiting", "untestable", "open"):
            sys.exit("grade.py: note bucket %r: waiting, untestable or open only (a note cannot raise a rung)" % bucket)
        if rung in res:
            cur = res[rung]
            if cur[1] == "open" and bucket != "open":
                bucket = "open"                      # a FAIL stays a FAIL
            cur[1], cur[2] = bucket, owner or {"open": "toolkit", "untestable": "customer"}.get(bucket, "person")
            cur[3] = text or cur[3]
            items = [i for i in items if i[0] != rung] + [(rung, bucket, cur[2], text or cur[3])]
        elif rung == "-":
            items.append(("-", bucket, owner or "person", text))
        else:
            sys.exit("grade.py: note names rung %r, which is not graded in this summary" % rung)
    count = {b: 0 for b in BUCKETS}
    for r in graded:
        count[res[r][1]] += 1
        v, b, o, t = res[r]
        if b not in ("proven", "accepted") and not any(i[0] == r for i in items):
            items.append((r, b, o, t))
    done = count["proven"] + count["accepted"]
    pct = int(round(100.0 * done / len(graded)))
    extra = [(r, rows[r][0]) for r in OPTIONAL if r in rows and rows[r][0] not in ("PASS", "PASS*", "NOT RUN")]
    return dict(overall=overall, run=run, graded=graded, res=res, count=count, done=done, pct=pct, items=items, extra=extra)


def line(g):
    c = g["count"]
    return "GRADE %d%% (%d of %d required rungs done): proven %d, accepted %d, waiting on a person %d, not testable here %d, open regression %d | verdict %s" % (
        g["pct"], g["done"], len(g["graded"]), c["proven"], c["accepted"], c["waiting"], c["untestable"], c["open"], g["overall"])


def short(t, n=110):
    t = re.sub(r"\(earlier run [^)]*\) ?", "", t).strip()
    return t if len(t) <= n else t[: n - 3] + "..."


def report(g):
    out = [line(g)]
    for b in BUCKETS:
        rs = [r for r in g["graded"] if g["res"][r][1] == b]
        if rs:
            out.append("  %-20s %s" % (LABEL[b], ", ".join(rs)))
    if g["extra"]:
        out.append("  not graded (optional): " + ", ".join("%s %s" % x for x in g["extra"]))
    if g["items"]:
        out.append("  open and pending work:")
        for r, b, o, t in g["items"]:
            out.append("    [%s] %s: %s (%s)" % (o or "person", r, short(t), LABEL[b]))
    return "\n".join(out)


def stamp(summary, g):
    """Insert or replace one `Grade:` line right after the `Overall:` line (never changes a verdict)."""
    ls = open(summary, encoding="utf-8").read().split("\n")
    ls = [x for x in ls if not x.startswith("Grade: ")]
    for i, x in enumerate(ls):
        if x.startswith("Overall: "):
            ls.insert(i + 1, "Grade: " + line(g)[len("GRADE "):])
            break
    open(summary, "w", encoding="utf-8").write("\n".join(ls))


COLS = ["date", "run id", "app", "Mendix path", "toolkit commit", "duration", "gate verdict", "grade",
        "regressions found/fixed", "kept modules", "open items", "lesson prefix"]
HEADER = "# Upgrade run history\n\nOne row per upgrade run, metadata only (no app content, screenshots or logs). `bin/grade.py --history` adds or\nupdates the row of a run id. Grade = done rungs of the 9 required (see READING-THE-VERDICT.md section 6); it sits\nnext to the verdict word and never replaces it.\n\n"


def cell(s):
    return re.sub(r"\s+", " ", str(s)).replace("|", "/").strip() or "?"


def history(path, fields):
    lines = open(path, encoding="utf-8").read().split("\n") if os.path.isfile(path) else (HEADER + "| " + " | ".join(COLS) + " |\n|" + "---|" * len(COLS)).split("\n")
    hdr = next((i for i, x in enumerate(lines) if x.startswith("| date |")), None)
    if hdr is None:
        sys.exit("grade.py: %s has no history table header" % path)
    end = hdr + 2
    while end < len(lines) and lines[end].startswith("|"):
        end += 1
    rid = fields["run id"]
    for i in range(hdr + 2, end):
        cs = [x.strip() for x in lines[i].strip().strip("|").split(" | ")]
        if len(cs) == len(COLS) and cs[1] == rid:
            for k, c in zip(COLS, cs):
                if k not in fields or fields[k] in (None, ""):
                    fields[k] = c
            lines[i] = "| " + " | ".join(cell(fields[k]) for k in COLS) + " |"
            break
    else:
        fields["date"] = fields.get("date") or datetime.date.today().isoformat()
        fields["toolkit commit"] = fields.get("toolkit commit") or toolkit_commit()
        lines.insert(end, "| " + " | ".join(cell(fields.get(k) or "?") for k in COLS) + " |")
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    open(path, "w", encoding="utf-8").write("\n".join(lines))


def toolkit_commit():
    try:
        d = os.path.dirname(os.path.abspath(__file__))
        return subprocess.check_output(["git", "-C", d, "rev-parse", "--short=7", "HEAD"], stderr=subprocess.DEVNULL, text=True).strip()
    except Exception:
        return ""


def duration(since):
    try:
        t = datetime.datetime.strptime(since, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
        s = int((datetime.datetime.now(datetime.timezone.utc) - t).total_seconds())
        return "%dh%02d" % (s // 3600, s % 3600 // 60)
    except Exception:
        return ""


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("summary")
    ap.add_argument("--notes")
    ap.add_argument("--stamp", action="store_true", help="write a Grade: line into the summary")
    ap.add_argument("--history", nargs="?", const="", metavar="HISTORY.md", help="add or update the run's row (default runs/HISTORY.md of this toolkit)")
    for k in ("run", "date", "app", "path", "toolkit", "duration", "since", "regressions", "kept", "open", "lesson", "grade-note"):
        ap.add_argument("--" + k)
    a = ap.parse_args()
    if not os.path.isfile(a.summary):
        sys.exit("grade.py: no such summary: %s" % a.summary)
    notes = a.notes or os.path.join(os.path.dirname(os.path.abspath(a.summary)), "grade-notes.tsv")
    g = grade(a.summary, notes)
    print(report(g))
    if a.stamp:
        stamp(a.summary, g)
    if a.history is not None:
        hp = a.history or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "runs", "HISTORY.md")
        rid = a.run or g["run"]
        if not rid:
            sys.exit("grade.py --history: give --run ID (the summary names none)")
        gt = "%d%% (%d/%d)" % (g["pct"], g["done"], len(g["graded"])) + ("; " + a.grade_note if a.grade_note else "")
        auto = ", ".join("%s (%s)" % (r, o or "person") for r, b, o, t in g["items"]) or "none"
        history(hp, {"date": a.date, "run id": rid, "app": a.app, "Mendix path": a.path,
                     "toolkit commit": a.toolkit, "duration": a.duration or (duration(a.since) if a.since else ""),
                     "gate verdict": g["overall"], "grade": gt, "regressions found/fixed": a.regressions, "kept modules": a.kept,
                     "open items": a.open or auto, "lesson prefix": a.lesson})
        print("history: row %s written to %s" % (rid, os.path.normpath(hp)))


if __name__ == "__main__":
    main()
