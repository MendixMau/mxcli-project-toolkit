#!/usr/bin/env python3
"""runlog.py: append one row per upgrade run to FIELD-RUNS.md (the permanent, append-only run log).

    runlog.py --work DIR [--run-id ID] [--app CODE] [--type TEXT] [--log FIELD-RUNS.md] [--dry-run]
    runlog.py --backfill ROOT [--match TEXT] [--app CODE] [--type TEXT] [--run-id ID] [--log FILE] [--write]
    runlog.py --explain ROOT [--log FILE]      per run-looking folder: LOGGED / WOULD-ADD / SKIPPED <reason>
    runlog.py --summary [--log FILE]           (re)write the "Per app (latest run)" section of the log
    runlog.py --stamp-time --work DIR          write the `Time:` line into DIR/gate-summary.md (replaces an earlier one)
    runlog.py --time-line --work DIR           print that line (or `not recorded`)
    --require-app (with --work): a row without an app code name is refused (exit 2) instead of written `not recorded`
    --verdict-from SCORECARD (with --work/--backfill/--explain): no gate-summary.md? take the verdict from SCORECARD.md
    --verbose: print which file each version came from (versions.txt, gate.conf/env.sh, SCORECARD/JOURNAL title, build or
    mx check log, the .mpr ProductVersion via mxversion.py; first hit wins per field)

Reads a run folder ($WORK of steps/*.md): gate-summary.md (verdict, the `Progress:` line, the rung table, the run id and
date from the `Work:` line), versions.txt and build-<version>.log (from -> highest reached), journeys line(s) (`journeys:
N PASS ...`, `actions ... coverage`), history-row.md (app name, regressions found/fixed), DECISIONS.md, HANDWORK.md.
A value the folder does not hold is written `not recorded`, never guessed.

Step timing: the pipeline appends one row per attempt of a step to state/timing.tsv (step, start UTC, end UTC, exit code).
"run time (machine)" is the sum of the rows. "person wait" is the gap after a row that stopped for a person (exit 10 to 15,
every NEEDS-JUDGMENT stop) until the pipeline next ran; a stop nobody has resumed yet is not counted. A run without
state/timing.tsv writes `not recorded` in both. The log has 14 columns since these two were added at the END of the row;
rows of 12 columns stay as they are (never rewritten), are read as before, and the table header is widened on the next
append.

Refuses (and says what to pass): a run id already in the log (prints the existing row, exit 3); a row that contains a
name from the private names list (bin/private_names.sh, outside the repo; exit 4): pass --app and
--type with code names (and --run-id when the id came from a folder name). Without --write, --backfill only prints the
rows it would add. Python standard library only; run as `python3 -I bin/runlog.py ...`.
Exit: 0 ok (backfill: also when some folders were skipped), 2 usage or unreadable input, 3 duplicate run id, 4 customer name.
"""
import argparse, datetime, os, re, sys

NR = "not recorded"
COLS_OLD = ["run id", "app (code name)", "app type", "from → highest reached", "builds 0 errors", "starts",
        "progress / gate verdict", "regressions open", "journeys (old-app pass/fail, coverage)",
        "fixed in this run", "still open / needs a person", "date"]
COLS = COLS_OLD + ["run time (machine)", "person wait"]
STOP_RC = (10, 11, 12, 13, 14, 15)   # exit codes that end a run for a person (NEEDS-JUDGMENT.md)
HERE = os.path.dirname(os.path.abspath(__file__))
HEADER = """# Field runs

Append-only log of upgrade runs: one row per run, code names only (no customer or app names), written at the end of every
run by `bin/runlog.py` from the run folder and committed through a toolkit PR. A value the run folder did not hold
says `not recorded`; it is never guessed. Never edit or delete a row: a wrong row is fixed by a new row whose run id ends `-fix`.
Reading a row: `progress / gate verdict` is the gate's own `Progress:` line and verdict word (a run is never "failed":
checks closed of checks owed, owner sign-off last); `journeys` is the old-app pass/fail count and the coverage line.
`run time (machine)` and `person wait` come from the run's step timing (`state/timing.tsv`; see SETUP.md): machine = steps running,
wait = from a stop for a person until the pipeline ran again. They were added at the end of the row; rows written before that have 12
columns and stay as they are, and a run without timing says `not recorded`.

"""
ROW = re.compile(r"^\| *(\d+) *\| *(\w+) *\| *([^|]+?) *\| *([^|]*?) *\| *(.*?) *\|$")
VER = r"\d+\.\d+\.\d+(?:\.\d+)?"


def vkey(v):
    return tuple(int(x) for x in v.split("."))


def read(path):
    try:
        return open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return None


def _ts(s):
    return datetime.datetime.strptime(s.strip(), "%Y-%m-%dT%H:%M:%SZ")


def timing(work):
    """state/timing.tsv -> {"steps": [(step, seconds)], "machine": s, "wait": s} or None (absent, or no readable row)."""
    t = read(os.path.join(work, "state", "timing.tsv"))
    if t is None:
        return None
    rows = []
    for ln in t.split("\n"):
        c = ln.rstrip("\r").split("\t")
        if len(c) != 4 or c[0] == "step":
            continue
        try:
            rows.append((c[0], _ts(c[1]), _ts(c[2]), int(c[3])))
        except ValueError:
            continue
    if not rows:
        return None
    per, machine, wait = {}, 0, 0
    for i, (st, a, b, rc) in enumerate(rows):
        d = max(0, int((b - a).total_seconds()))
        per[st] = per.get(st, 0) + d
        machine += d
        if rc in STOP_RC and i + 1 < len(rows):
            wait += max(0, int((rows[i + 1][1] - b).total_seconds()))
    return {"steps": list(per.items()), "machine": machine, "wait": wait}


def dur(s):
    if s < 60:
        return "%ds" % s if s else "0m"
    m = int(s / 60.0 + 0.5)
    return "%dm" % m if m < 60 else ("%dh" % (m // 60) + ("%dm" % (m % 60) if m % 60 else ""))


def time_line(work):
    tm = timing(work)
    if not tm:
        return None
    return "Time: %s; machine %s; person wait %s" % (
        ", ".join("%s %s" % (s, dur(d)) for s, d in tm["steps"]), dur(tm["machine"]), dur(tm["wait"]))


def stamp_time(work):
    """Put the Time: line into gate-summary.md after the header lines (Work: ...); replaces an earlier Time: line."""
    path = os.path.join(work, "gate-summary.md")
    text, line = read(path), time_line(work)
    if text is None or line is None:
        return False
    ls = [x for x in text.split("\n") if not x.startswith("Time: ")]
    at = 1
    for i, x in enumerate(ls[:14]):
        if re.match(r"(Overall|Grade|Progress|Changes|Change ledger|Work): ", x):
            at = i + 1
    ls.insert(at, line)
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(ls))
    return True


def cell(s):
    s = re.sub(r"\s+", " ", str(s)).replace("|", "/").strip()
    return s or NR


def denylist():
    """The private names list (bin/private_names.sh: UPG_PRIVATE_NAMES, default ~/.config/upgrade-toolkit/private-names.txt,
    one extended regex per line). No list: nothing to refuse (said once on stderr)."""
    f = os.environ.get("UPG_PRIVATE_NAMES") or os.path.expanduser("~/.config/upgrade-toolkit/private-names.txt")
    lines = [l.strip() for l in (read(f) or "").splitlines() if l.strip() and not l.strip().startswith("#")]
    if not lines:
        print("runlog.py: no private names list (%s): rows are not checked for customer names" % f, file=sys.stderr)
        return re.compile(r"(?!x)x")
    # the list is POSIX ERE for grep; \b and the rest mean the same in Python
    return re.compile("|".join(lines))


def parse_summary(text):
    d = {"rungs": {}, "optional": set()}
    if text is None:
        return d
    m = re.search(r"^Overall: \*\*(.+?)\*\* \(exit (\d+)\)", text, re.M)
    if m:
        d["overall"], d["rc"] = m.group(1), m.group(2)
    m = re.search(r"^(Progress: .*)$", text, re.M)
    if m:
        d["progress"] = m.group(1)
    m = re.search(r", run (\S+?)\. (\d{4}-\d\d-\d\d)T\d\d:\d\dZ\s*$", text, re.M)
    if m:
        d["run"], d["date"] = m.group(1), m.group(2)
    for ln in text.split("\n"):
        r = ROW.match(ln.rstrip())
        if r:
            name = r.group(2)
            d["rungs"][name] = (r.group(3).strip(), r.group(5))
            if "(optional rung)" in r.group(5):
                d["optional"].add(name)
    if re.search(r"^proposal not signed", text, re.M):
        d["unsigned"] = True
    return d


def history_row(work):
    t = read(os.path.join(work, "history-row.md"))
    if not t:
        return {}
    cols = None
    for ln in t.split("\n"):
        if ln.startswith("| date |"):
            cols = [c.strip() for c in ln.strip().strip("|").split("|")]
        elif cols and ln.startswith("| ") and not ln.startswith("|---"):
            cs = [c.strip() for c in ln.strip().strip("|").split(" | ")]
            if len(cs) == len(cols):
                return dict(zip(cols, cs))
    return {}


def builds(work):
    """Highest version with a successful build log (build-<ver>.log: BUILD SUCCEEDED and no 'ERROR at' line)."""
    best = None
    for base, dirs, files in os.walk(work):
        if base[len(work):].count(os.sep) > 1:
            dirs[:] = []
            continue
        dirs[:] = [x for x in dirs if x not in (".git", "node_modules", "app", "tools", "dl")]
        for f in files:
            m = re.match(r"^build-(%s)\.log$" % VER, f)
            if not m:
                continue
            t = read(os.path.join(base, f)) or ""
            if "BUILD SUCCEEDED" in t and not re.search(r"^ERROR at", t, re.M):
                if best is None or vkey(m.group(1)) > vkey(best):
                    best = m.group(1)
    return best


def vers_in(t):
    return re.findall(VER, t or "")


def chain(t):
    """First line holding `X.Y.Z -> ... -> X.Y.Z` (arrow or `to`): (first, highest) of the versions on that line."""
    for ln in (t or "").split("\n")[:40]:
        if re.search(VER + r" *(?:→|->|\bto\b) *" + VER, ln):
            v = vers_in(ln)
            return v[0], max(v, key=vkey)
    return None


def conf_vers(work):
    for f in ("gate.conf", "env.sh"):
        t = read(os.path.join(work, f))
        if t is None:
            continue
        g = lambda k: (re.search(r"^(?:export +)?%s=[\"']?(%s)" % (k, VER), t, re.M) or [None, None])[1]
        s, tg = g("SOURCE"), [x for x in (g("TARGET"), g("TARGET2")) if x]
        if s or tg:
            return f, s, (max(tg, key=vkey) if tg else None)
    return None


def walk2(work, skip):
    for base, dirs, files in os.walk(work):
        if base[len(work):].count(os.sep) > 1:
            dirs[:] = []
            continue
        dirs[:] = [x for x in dirs if x not in skip]
        yield base, files


def detect_versions(work):
    """(source, highest reached, notes). Each field takes the first source (in order) that holds it."""
    say = []
    st = {"src": None, "top": None}

    def got(name, s, t):
        if (s and not st["src"]) or (t and not st["top"]):
            say.append("%s: %s → %s" % (name, (s if not st["src"] else None) or "-", (t if not st["top"] else None) or "-"))
        st["src"], st["top"] = st["src"] or s, st["top"] or t

    m = re.search(r"^app: (%s)" % VER, read(os.path.join(work, "versions.txt")) or "", re.M)
    got("versions.txt", m and m.group(1), None)
    c = conf_vers(work)
    if c:
        got(*c)
    for f in ("SCORECARD.md", "JOURNAL.md"):
        ch = chain(read(os.path.join(work, f)))
        if ch:
            got(f + " title", *ch)
    got("build-<version>.log", None, builds(work))
    if not (st["src"] and st["top"]):
        for base, files in walk2(work, (".git", "node_modules", "app", "tools", "dl")):
            hit = None
            for f in sorted(files):
                if re.search(r"(?:mx-?check|build).*\.(?:log|txt|out)$", f):
                    m = re.search(r"Mendix(?: version| Runtime| Studio Pro)?:? +v?(%s)" % VER, read(os.path.join(base, f)) or "", re.I)
                    if m:
                        hit = (f, m.group(1))
                        break
            if hit:
                got(hit[0], *((None, hit[1]) if st["src"] else (hit[1], None)))
                break
    if not (st["src"] and st["top"]):
        try:
            sys.path.insert(0, HERE)
            import mxversion
            for base, files in walk2(work, (".git", "node_modules", "tools", "dl")):
                mp = [f for f in files if f.endswith(".mpr")]
                if mp:
                    v = str(mxversion.version(os.path.join(base, mp[0])) or "")
                    if re.match(VER, v):
                        got(mp[0] + " ProductVersion", *((None, v) if st["src"] else (v, None)))
                    break
        except Exception:
            pass
    return st["src"], st["top"], say


def journeys(work, summ):
    texts = []
    j = summ["rungs"].get("journeys")
    if j:
        texts.append(j[1])
    texts.append(read(os.path.join(work, "journeys-after.out")) or "")
    for t in texts:
        m = re.search(r"actions (\d+) found .*? (\d+) pass on baseline \((\d+) defect\).*? (\d+) regression.*?coverage (\d+)/(\d+) \((\d+)%\)", t)
        if m:
            return "old app %s pass / %s fail; %s regression(s); coverage %s/%s (%s%%)" % (
                m.group(2), m.group(3), m.group(4), m.group(5), m.group(6), m.group(7)), int(m.group(4))
    for t in texts:
        m = re.search(r"^journeys: (\d+) PASS, (\d+) FAIL", t, re.M)
        if m:
            return "new app %s PASS, %s FAIL (no old-app count or coverage line)" % (m.group(1), m.group(2)), None
    return NR, None


def count(path, rx):
    t = read(path)
    if t is None:
        return None
    return sum(1 for ln in t.split("\n") if re.match(rx, ln))


def verdict_word(summ, rung, yes):
    r = summ["rungs"].get(rung)
    if not r:
        return NR
    s = r[0]
    if s in ("PASS", "PASS*"):
        return yes
    return "no (%s)" % s if s == "FAIL" else s.lower()


def scorecard_verdict(work):
    t = read(os.path.join(work, "SCORECARD.md"))
    m = re.search(r"verdict[^:\n]*:\**\s*\**(PASS\*?|FAIL|INVALID|EXCEPT|REVIEW)\b(?: \(exit (\d+)\))?", t or "", re.I)
    return (m.group(1).upper() + (" (exit %s)" % m.group(2) if m.group(2) else "")) if m else None


def build_row(work, a):
    summ = parse_summary(read(os.path.join(work, "gate-summary.md")))
    hist = history_row(work)
    p = lambda k: (hist.get(k) or "").strip()
    known = lambda v: v and v not in ("?", "-", "unnamed app")
    run = a.run_id or summ.get("run") or NR
    if "date" not in summ and a.verdict_from:
        m = re.search(r"\d{4}-\d\d-\d\d", read(os.path.join(work, "SCORECARD.md")) or "")
        if m:
            summ["date"] = m.group(0)
    app = a.app or (p("app") if known(p("app")) else NR)
    src, top, notes = detect_versions(work)
    src, top = src or NR, top or NR
    if src == NR and known(p("Mendix path")):
        src = re.split(r"\s*>\s*", p("Mendix path"))[0].strip() or NR
    if a.verbose:
        for n in notes:
            print("   version source %s" % n, file=sys.stderr)
    path = "%s → %s" % (src, top) if (src != NR or top != NR) else NR
    if "overall" in summ:
        word = "%s (exit %s)" % (summ["overall"], summ["rc"])
        prog = summ.get("progress")
        if prog:
            m = re.match(r"Progress: (\d+ of \d+) checks closed \((\d+)%\)", prog)
            prog = "%s (%s%%)" % (m.group(1), m.group(2)) if m else prog
        gate = "%s · %s" % (prog or "progress not recorded", word)
    else:
        gate = NR
        sv = scorecard_verdict(work) if a.verdict_from else None
        if sv:
            gate = "progress not recorded · %s (from SCORECARD.md)" % sv
    jtxt, jreg = journeys(work, summ)
    reg = NR
    m = re.search(r"(\d+) with REGRESSIONS to fix", summ.get("progress", ""))
    if m:
        reg = m.group(1)
    elif jreg is not None:
        reg = "%d (journeys)" % jreg
    fixed = []
    if known(p("regressions found/fixed")):
        fixed.append("regressions found/fixed " + p("regressions found/fixed"))
    nh = count(os.path.join(work, "HANDWORK.md"), r"^\| *\d+ *\|")
    nd = count(os.path.join(work, "DECISIONS.md"), r"^(?:##\s+|-\s+)[A-Z]{1,2}\d+[a-z]?\b")
    if nh is not None:
        fixed.append("%d hand steps logged (HANDWORK.md)" % nh)
    if nd is not None:
        fixed.append("%d decisions logged (DECISIONS.md)" % nd)
    openl = []
    for name, (s, line) in summ["rungs"].items():
        if s in ("PASS", "PASS*") or name in summ["optional"]:
            continue
        openl.append("%s %s" % (name, s))
    if "overall" in summ:
        if summ.get("unsigned"):
            openl.append("proposal not signed")
        if "owner sign-off pending" in summ.get("progress", ""):
            openl.append("owner sign-off pending")
    row = [run, app, a.type or NR, path, verdict_word(summ, "build", "yes"), verdict_word(summ, "logdiff", "yes"),
           gate, reg, jtxt, "; ".join(fixed) or NR, "; ".join(openl) if "overall" in summ else NR,
           summ.get("date") or NR]
    tm = timing(work)
    row += [dur(tm["machine"]), dur(tm["wait"])] if tm else [NR, NR]
    return [cell(x) for x in row]


def fmt(row):
    return "| " + " | ".join(row) + " |"


def log_rows(text):
    rows = []
    for ln in (text or "").split("\n"):
        if ln.startswith("| ") and not ln.startswith("| run id |"):
            cs = [c.strip() for c in ln.strip().strip("|").split(" | ")]
            if len(cs) in (len(COLS_OLD), len(COLS)):
                rows.append((cs[0], ln))
    return rows


def check_names(row, deny):
    hits = sorted({m.group(0) for m in deny.finditer(fmt(row))})
    return hits


def append(log, row, write=True):
    text = read(log)
    if text is None:
        text = HEADER + "| " + " | ".join(COLS) + " |\n|" + "---|" * len(COLS) + "\n"
        if write:
            os.makedirs(os.path.dirname(os.path.abspath(log)), exist_ok=True)
            with open(log, "w", encoding="utf-8") as f:
                f.write(text)
    elif "| run id |" not in text:
        sys.exit("runlog.py: %s has no `| run id |` table header: refusing to append" % log)
    elif write and re.search(r"^\| run id .*\| date \|$", text, re.M):
        # a log started with 12 columns: widen the header and its separator line only; the rows are never touched
        new = re.sub(r"^(\| run id .*\| date \|)\n\|(?:---\|){%d}$" % len(COLS_OLD),
                     lambda m: "| " + " | ".join(COLS) + " |\n|" + "---|" * len(COLS), text, count=1, flags=re.M)
        if new != text:
            with open(log, "w", encoding="utf-8") as f:
                f.write(new)
            text = new
    if write and not text.endswith("\n"):
        with open(log, "a", encoding="utf-8") as f:
            f.write("\n")
    if write:
        with open(log, "a", encoding="utf-8") as f:
            f.write(fmt(row) + "\n")


def one(work, a, deny, seen, write):
    """Return (status, message): status ok | dup | name | skip."""
    row = build_row(work, a)
    if row[0] == NR:
        return "skip", "no run id in %s: pass --run-id" % work
    hit = check_names(row, deny)
    if hit:
        return "name", ("refused: the row for %s contains a customer name (%s). Pass --app and --type with code names "
                        "(and --run-id) and run again." % (work, ", ".join(hit)))
    if row[0] in seen:
        return "dup", "run id %s is already in the log: not appended. Existing row:\n%s" % (row[0], seen[row[0]])
    if write:
        append(a.log, row, True)
    seen[row[0]] = fmt(row)
    return "ok", fmt(row)


BEGIN = "<!-- per-app:begin (generated by runlog.py --summary; do not edit by hand) -->"
END = "<!-- per-app:end -->"


def summary(log):
    """(Re)write the generated per-app section above the run table. Idempotent."""
    text = read(log)
    if text is None or "| run id |" not in text:
        return False
    apps = {}
    for _, ln in log_rows(text):
        c = [x.strip() for x in ln.strip().strip("|").split(" | ")]
        apps.setdefault(c[1], []).append(c)
    lines = []
    for app in sorted(apps):
        rs = apps[app]
        latest = max(enumerate(rs), key=lambda e: (e[1][11] if re.match(r"\d{4}-", e[1][11]) else "", e[0]))[1]
        vs = [v for r in rs for v in vers_in(r[3])]
        lines.append("- **%s** (%s): latest run %s; highest version reached %s; latest %s; %d run%s" % (
            app, latest[2], latest[11], max(vs, key=vkey) if vs else NR, latest[6], len(rs), "" if len(rs) == 1 else "s"))
    block = "%s\n## Per app (latest run)\n\n%s\n%s" % (BEGIN, "\n".join(lines), END)
    if BEGIN in text and END in text:
        new = text[:text.index(BEGIN)] + block + text[text.index(END) + len(END):]
    else:
        k = text.index("| run id |")
        new = text[:k] + block + "\n\n## All runs (history)\n\n" + text[k:]
    if new != text:
        with open(log, "w", encoding="utf-8") as f:
            f.write(new)
    return True


MARKERS = ("gate-summary.md", "SCORECARD.md", "JOURNAL.md", "TOOLKIT-FEEDBACK.md")


def explain(root, a, deny, seen):
    n = 0
    for base, dirs, files in os.walk(root):
        dirs[:] = sorted(x for x in dirs if x not in (".git", "node_modules"))
        if not (set(MARKERS) & set(files) or {"state", "logs"} & set(dirs)) or base == root:
            continue
        n += 1
        rel = os.path.relpath(base, root)
        row = build_row(base, a)
        has_sum = "gate-summary.md" in files
        if not has_sum and not (a.verdict_from and scorecard_verdict(base)):
            why = "no gate-summary.md and no SCORECARD verdict"
            if scorecard_verdict(base):
                why = "no gate-summary.md; SCORECARD.md has a verdict: pass --verdict-from SCORECARD --run-id ID"
            st = "SKIPPED " + why
        elif row[0] == NR:
            st = "SKIPPED no run id: pass --run-id"
        elif check_names(row, deny):
            st = "SKIPPED customer name, pass --app/--type"
        elif row[0] in seen:
            st = "LOGGED"
        else:
            st = "WOULD-ADD" + ("" if row[1] != NR else " (app not recorded: pass --app/--type)")
        print("%s: %s" % (rel, st))
    print("runlog: %d run-looking folders under %s" % (n, root))
    return 0


def main():
    ap = argparse.ArgumentParser(description="append one run row to FIELD-RUNS.md")
    ap.add_argument("--work")
    ap.add_argument("--stamp-time", action="store_true", help="write the Time: line into DIR/gate-summary.md")
    ap.add_argument("--time-line", action="store_true", help="print the Time: line of --work")
    ap.add_argument("--require-app", action="store_true", help="--work: refuse a row without an app code name (exit 2)")
    ap.add_argument("--explain", metavar="ROOT")
    ap.add_argument("--summary", action="store_true")
    ap.add_argument("--verdict-from", choices=["SCORECARD"])
    ap.add_argument("--verbose", action="store_true")
    ap.add_argument("--backfill", metavar="ROOT")
    ap.add_argument("--run-id")
    ap.add_argument("--app")
    ap.add_argument("--type")
    ap.add_argument("--log", default=os.path.join(HERE, "..", "FIELD-RUNS.md"))
    ap.add_argument("--match", help="backfill: only run folders whose path contains this text")
    ap.add_argument("--write", action="store_true", help="backfill: append (default is a dry run)")
    ap.add_argument("--dry-run", action="store_true", help="--work: print the row, append nothing")
    a = ap.parse_args()
    if sum(map(bool, (a.work, a.backfill, a.explain, a.summary))) != 1:
        ap.error("give exactly one of --work DIR, --backfill ROOT, --explain ROOT or --summary")
    a.log = os.path.abspath(a.log)
    if a.summary:
        if not summary(a.log):
            print("runlog.py: %s missing or has no run table" % a.log, file=sys.stderr)
            return 2
        print("runlog: per-app summary written to %s" % a.log)
        return 0
    deny = denylist()
    seen = dict(log_rows(read(a.log)))
    if a.explain:
        if not os.path.isdir(a.explain):
            print("runlog.py: no such folder: %s" % a.explain, file=sys.stderr)
            return 2
        return explain(os.path.abspath(a.explain), a, deny, seen)
    if a.work:
        if not os.path.isdir(a.work):
            print("runlog.py: no such folder: %s" % a.work, file=sys.stderr)
            return 2
        if a.time_line or a.stamp_time:
            line = time_line(os.path.abspath(a.work))
            if a.time_line:
                print(line or "Time: " + NR)
            if a.stamp_time:
                print("runlog: Time line %s" % ("stamped into gate-summary.md" if stamp_time(os.path.abspath(a.work)) else "not stamped (no timing.tsv or no gate-summary.md)"))
            return 0
        if a.require_app and not a.app and build_row(os.path.abspath(a.work), a)[1] == NR:
            print("runlog.py: no app code name for %s: pass --app CODE (the pipeline reads UPG_APP_CODE); nothing appended" % a.work, file=sys.stderr)
            return 2
        st, msg = one(os.path.abspath(a.work), a, deny, seen, not a.dry_run)
        print(msg, file=sys.stderr if st != "ok" else sys.stdout)
        if st == "ok" and not a.dry_run:
            summary(a.log)
        if st == "ok":
            print("runlog: %s %s" % ("would append to" if a.dry_run else "appended to", a.log), file=sys.stderr)
        return {"ok": 0, "dup": 3, "name": 4, "skip": 2}[st]
    root = os.path.abspath(a.backfill)
    if not os.path.isdir(root):
        print("runlog.py: no such folder: %s" % root, file=sys.stderr)
        return 2
    found = []
    for base, dirs, files in os.walk(root):
        dirs[:] = sorted(x for x in dirs if x not in (".git", "node_modules"))
        if ("gate-summary.md" in files or (a.verdict_from and "SCORECARD.md" in files)) and (not a.match or a.match in base):
            found.append(base)
    n = {"ok": 0, "dup": 0, "name": 0, "skip": 0}
    for w in found:
        st, msg = one(w, a, deny, seen, a.write)
        n[st] += 1
        rel = os.path.relpath(w, root)
        print("%s %s" % ({"ok": "ADD    " if not a.write else "ADDED  ", "dup": "DUP    ", "name": "REFUSED", "skip": "SKIP   "}[st], rel))
        print("   " + msg.replace("\n", "\n   "))
    if a.write and n["ok"]:
        summary(a.log)
    print("runlog: %d run folders under %s: %d %s, %d duplicate, %d refused (customer name), %d without a run id. %s"
          % (len(found), root, n["ok"], "added" if a.write else "to add", n["dup"], n["name"], n["skip"],
             "" if a.write else "Dry run: nothing written; add --write to append."))
    return 0


if __name__ == "__main__":
    sys.exit(main())
