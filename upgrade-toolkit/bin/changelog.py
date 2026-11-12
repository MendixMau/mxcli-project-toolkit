#!/usr/bin/env python3
"""changelog.py: the change ledger of an upgrade run, written as $W/CHANGES.md (trust.md section 3).

  changelog.py --app APP --work W [--since REV] [--accept LABEL=FILE ...] [--decisions FILE] [--out FILE]

Reads the app repo from the run-start marker to HEAD. The marker is the newest commit whose subject is "original" or
starts "original:" / "rung start" (upgrade-pipeline.sh makes them); with none, the root commit; --since REV overrides.
The marker itself is not a change. Every toolkit and agent commit in the app repo carries two trailers:
  Changed-By: toolkit|agent|person        Upgrade-Change: <kind> <rule-id>
(stepupdate.sh, upgrade-pipeline.sh and appcommit.sh write them). A commit without both is "unlabelled": listed, never
assumed to be the toolkit's.

CHANGES.md is the reviewer's document, readable without git: per change when, by, kind, rule, why (the commit subject),
what changed (files; the model's documents counted from the .mpr / mprcontents/ files; the toolkit has no cheap per-document
model diff to call, so a changed model reads "model changed: N unit file(s)"), and the evidence path (the first existing log
for that kind of change). Then the accepted differences (every line of the accept/allow files with its reason), then the
decisions (DECISIONS.md, steps/decide.md).

A commit may also carry `Upgrade-Step: S-n` (appcommit.sh --step, the toolkit's scripts). When the run keeps step records
(<work>/steps.jsonl), each such commit is handed to `steps.py done` (once per commit), and the table says which step each change
belongs to; a commit with no step reads "no step" (the toolkit's own rung-start and build-stubs config commits read "housekeeping" instead), and one that names a step the run does not have reads "unknown step S-n".

Prints one line on stdout, which gate.sh copies into the gate summary:
  Changes: N (toolkit a, agent b, person c, unlabelled d)
Exit: 0 written, 2 input error (APP is not a git repository, no commits, --since not a commit).
Producer: gate.sh runs it when the app repo is known (APP_REPO, else $WORK/app). Consumer: the reviewer, the gate summary."""
import argparse, glob, os, re, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import steps   # the step records (steps.py is the only writer of <work>/steps.jsonl)

SEP_C, SEP_F = "\x1e", "\x1f"
BY = ("toolkit", "agent", "person")


def git(app, *args):
    return subprocess.run(["git", "-C", app, *args], capture_output=True, text=True)


def die(msg):
    print(f"changelog: {msg}", file=sys.stderr)
    sys.exit(2)


def marker(app, since):
    if since:
        r = git(app, "rev-parse", "--verify", "--quiet", since + "^{commit}")
        if r.returncode != 0:
            die(f"--since {since}: not a commit in {app}")
        return r.stdout.strip()
    r = git(app, "log", "-1", "--format=%H", "--extended-regexp", "--grep=^(original|rung start)")
    if r.stdout.strip():
        return r.stdout.strip()
    r = git(app, "rev-list", "--max-parents=0", "HEAD")
    return r.stdout.split()[-1] if r.stdout.split() else ""


def commits(app, base):
    fmt = SEP_C + "%H" + SEP_F + "%aI" + SEP_F + "%s" + SEP_F + "%b"
    r = git(app, "log", "--reverse", "--format=" + fmt, f"{base}..HEAD")
    out = []
    for rec in r.stdout.split(SEP_C)[1:]:
        h, when, subj, body = (rec.split(SEP_F, 3) + [""] * 4)[:4]
        by = kind = rule = step = ""
        for line in body.splitlines():
            m = re.match(r"^Upgrade-Step:\s*(\S+)\s*$", line)
            if m:
                step = m.group(1)
            m = re.match(r"^Changed-By:\s*(\S+)\s*$", line)
            if m:
                by = m.group(1).lower()
            m = re.match(r"^Upgrade-Change:\s*(\S+)\s+(.+?)\s*$", line)
            if m:
                kind, rule = m.group(1), m.group(2)
        label = by if by in BY and kind else "unlabelled"
        out.append({"hash": h, "when": when, "subject": subj, "by": label, "kind": kind or "-", "rule": rule or "-", "step": step})
    return out


HOUSEKEEPING = {("toolkit", "config", "rung-start"), ("toolkit", "config", "build-stubs")}


def link_steps(work, cs):
    """Hand every commit that names a step to steps.py done (a commit once) and set c["step_cell"]. Without <work>/steps.jsonl the
    trailer is shown as written and nothing is recorded."""
    have = os.path.isfile(steps.path_of(work))
    for c in cs:
        ref = c["step"]
        if not ref:
            # the toolkit's own housekeeping commits (the rung start, regenerated stubs) change no behaviour of the app: they are marked,
            # not counted as missing. A config commit by a person or the agent still reads "no step".
            c["step_cell"] = "housekeeping" if (c["by"], c["kind"], c["rule"]) in HOUSEKEEPING else "no step"
            continue
        sid = steps.resolve(work, ref) if have else ref
        if not sid:
            c["step_cell"] = f"unknown step {ref}"
            continue
        c["step_cell"] = sid
        if have:
            say = c["subject"] if steps.plain(c["subject"]) else f"A change of kind {c['kind']} was committed."
            steps.add_commit(work, sid, c["hash"][:7], say, "changelog")


def files_of(app, h):
    r = git(app, "show", "--name-status", "--format=", "--no-renames", h)
    fs = []
    for line in r.stdout.splitlines():
        parts = line.split("\t", 1)
        if len(parts) == 2:
            fs.append((parts[0], parts[1]))
    return fs


def what_changed(fs):
    model = [p for _, p in fs if p.endswith(".mpr") or "/mprcontents/" in "/" + p or p.startswith("mprcontents/")]
    other = [f"{s} {p}" for s, p in fs if p not in model]
    parts = []
    if model:
        units = [p for p in model if p.endswith(".mxunit")]
        parts.append(f"model changed: {len(units)} unit file(s)" if units else "model changed")
    if other:
        shown = other[:6]
        more = f" (+{len(other) - 6} more)" if len(other) > 6 else ""
        parts.append(f"{len(other)} file(s): " + ", ".join(shown) + more)
    return "; ".join(parts) or "no file change"


def evidence(app, work, c):
    subj, kind = c["subject"], c["kind"]
    cands = []
    m = re.match(r"step: (\S+) ", subj)
    if m:
        cands += sorted(glob.glob(os.path.join(app, ".stepupdate", f"step*-{m.group(1)}.log")))
    if subj.startswith("jar:"):
        cands.append(os.path.join(app, ".stepupdate", "jardedupe.log"))
    if kind == "repair":
        cands += sorted(glob.glob(os.path.join(work, "check-*.log")))[-1:]
    if kind == "convert":
        cands += sorted(glob.glob(os.path.join(work, "logs", "convert*.log")) + glob.glob(os.path.join(work, "convert*.log")))[-1:]
    if kind == "replay":
        m = re.match(r"replay: (\S+)", subj)
        if m:
            cands += glob.glob(os.path.join(work, f"replay-{m.group(1)}*.out"))
    for p in cands:
        if os.path.exists(p):
            return p
    return "none recorded"


def read_lines(path):
    try:
        return open(path, encoding="utf-8", errors="replace").read().splitlines()
    except OSError:
        return None


def accepted(specs):
    rows, missing = [], []
    for spec in specs:
        label, _, path = spec.partition("=")
        lines = read_lines(path)
        if lines is None:
            missing.append(spec)
            continue
        for ln in lines:
            t = ln.strip()
            if not t or t.startswith("#"):
                continue
            pat, sep, why = t.partition(" # ")
            if not sep and "#" in t:
                pat, _, why = t.partition("#")
            rows.append((label, pat.strip(), why.strip() or "(no reason written)"))
    return rows, missing


def cell(s):
    return str(s).replace("|", "\\|").replace("\n", " ")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--app", required=True)
    ap.add_argument("--work", required=True)
    ap.add_argument("--since")
    ap.add_argument("--accept", action="append", default=[], metavar="LABEL=FILE")
    ap.add_argument("--decisions")
    ap.add_argument("--out")
    a = ap.parse_args()
    app, work = os.path.abspath(a.app), os.path.abspath(a.work)
    if git(app, "rev-parse", "--git-dir").returncode != 0:
        die(f"{app} is not a git repository")
    if git(app, "rev-parse", "--verify", "--quiet", "HEAD").returncode != 0:
        die(f"{app} has no commit")
    base = marker(app, a.since)
    if not base:
        die("no run-start marker")
    cs = commits(app, base)
    link_steps(work, cs)
    n = {k: sum(1 for c in cs if c["by"] == k) for k in (*BY, "unlabelled")}
    line = f"Changes: {len(cs)} (toolkit {n['toolkit']}, agent {n['agent']}, person {n['person']}, unlabelled {n['unlabelled']})"
    mk = git(app, "log", "-1", "--format=%h %s (%aI)", base).stdout.strip()
    acc, missing = accepted(a.accept)
    dec = read_lines(a.decisions) if a.decisions else None

    o = ["# Changes in the app", "", line, "",
         f"Run start (not a change): `{mk}`. Every change after it in the app repo, oldest first. `by`: toolkit, agent and person are "
         "read from the commit's `Changed-By:` trailer; a commit without both trailers (`Changed-By`, `Upgrade-Change`) is "
         "**unlabelled**: nobody has said who made it or why, so it is never assumed to be the toolkit's.", ""]
    if n["unlabelled"]:
        o += [f"**{n['unlabelled']} unlabelled commit(s) need a decision**: say who made each and why (steps/decide.md), or label it "
              "(`bin/appcommit.sh` for the next one).", ""]
    nostep = sum(1 for c in cs if c["step_cell"] == "no step")
    if os.path.isfile(steps.path_of(work)) and nostep:
        o += [f"**{nostep} commit(s) name no step**: the change does not show up under any step. Pass `--step S-n` to `bin/appcommit.sh` "
              "for the next one (steps/upgrade.md).", ""]
    if cs:
        o += ["| # | when | by | kind | rule | why | what changed | evidence | step |", "|---|---|---|---|---|---|---|---|---|"]
        for i, c in enumerate(cs, 1):
            when = c["when"].replace("T", " ")[:16]
            o.append(f"| {i} | {cell(when)} | {c['by']} | {cell(c['kind'])} | {cell(c['rule'])} | {cell(c['subject'])} (`{c['hash'][:7]}`) | "
                     f"{cell(what_changed(files_of(app, c['hash'])))} | {cell(evidence(app, work, c))} | {cell(c['step_cell'])} |")
    else:
        o.append("No change in the app repo since the run start.")
    o += ["", "## Accepted differences", ""]
    if acc:
        o += ["Each line of the accept and allow files is a difference somebody accepted in writing, with the reason written there.", "",
              "| file | accepted | reason |", "|---|---|---|"]
        o += [f"| {cell(l)} | {cell(p)} | {cell(w)} |" for l, p, w in acc]
    else:
        o.append("None.")
    for m in missing:
        o.append(f"\nNot readable: `{m}`.")
    o += ["", "## Decisions", ""]
    if dec is None:
        o.append("No DECISIONS.md.")
    else:
        rows = [d for d in dec if d.strip() and not d.lstrip().startswith("#") and " | " in d]
        if rows:
            o += ["| id | item | kind | decision | reason | who | status | closes by |", "|---|---|---|---|---|---|---|---|"]
            for d in rows:
                f = [x.strip() for x in d.split(" | ")]
                f = (f + [""] * 8)[:8] if len(f) <= 8 else f[:7] + [" | ".join(f[7:])]
                o.append("| " + " | ".join(cell(x) for x in f) + " |")
        else:
            o.append("No decision recorded.")
    out = a.out or os.path.join(work, "CHANGES.md")
    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    open(out, "w", encoding="utf-8").write("\n".join(o) + "\n")
    print(line)


if __name__ == "__main__":
    main()
