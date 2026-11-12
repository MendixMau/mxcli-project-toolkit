#!/usr/bin/env python3
"""cockpitpage.py: the upgrade cockpit, one calm page from the files of a run. Nothing about a run is hard-coded.

  cockpitpage.py --work W --out FILE

The model (build_model) reads the run files and lists the decisions that need the owner; the page is the matrix cockpit drawn by
cockpitmatrix.py: top tiles, a readiness strip, one row per upgrade item with four stage columns (Triage, Plan, Upgrade, Test),
a proposed-solution box on every non-green cell, and the decision buttons inside the cell panels. The model also stays in the page
data (phases, items) for the decision tools and the technical folds.

Reads from W (all optional; a missing file only makes that part say "not measured"):
  PROPOSAL.md (versions, section 2 to 6, plan hash), DECISIONS.md (P-n answers), AGENT-DECISIONS.md (here or in the run folder,
  rows with the word "confirm" become items to confirm), gate-summary.md (one row per rung), heal.json (classes, real regressions),
  decisions-open.json (judgment items: id, question, options, recommended), NEEDS-JUDGMENT.md (where the run stopped),
  apimock-inventory.json, findings.json, release-impact.md, state/*.done and state/timing.tsv (time), the app's git log (how each
  change was built), cockpit-items.json (agent-written words per item, see steps/report.md), run-cost.json (optional {"usd": N}), decisions.json (the ledger written by decisions.py).

Effort per item: Large = Complex, Medium, Small = Simple, none = No work.
Every "Needs you" row has a stable id (P-n, signoff, confirm:Dn, regression:<page>, judgment:<id>). The same items are returned by
build_model() for decisions.py, so the page buttons and the chat path share one list.

The page records decisions through the artifact db capability (claude.use("db"), claude.use("user")); with db null it is read only.
Output is page content only (title, style, markup, script), no doctype/html/head/body.
Exit: 0 written, 2 usage.
"""
import argparse, datetime, glob, html, json, os, re, subprocess, sys

PHASES = [("find", "Find", ("fetch", "triage")), ("plan", "Plan", ("propose",)),
          ("upgrade", "Upgrade", ("baseline", "convert", "update", "build")),
          ("test", "Test", ("basewalk", "after", "afterwalk", "journeys", "heal", "diff", "gate")), ("golive", "Go-live", ())]
STEP_ORDER = ["fetch", "triage", "baseline", "basewalk", "propose", "convert", "update", "build", "after", "afterwalk",
              "journeys", "heal", "diff", "gate"]
EFFORT = {"l": "C", "large": "C", "complex": "C", "m": "M", "medium": "M", "s": "S", "small": "S", "simple": "S", "none": "N"}
RUNG_NAMES = {"build": "Build", "idcheck": "Data identity", "const": "Settings", "data": "Data compare", "rest": "REST contract",
              "logdiff": "Log compare", "smoke": "Click through pages", "journeys": "User journeys", "screens": "Screens",
              "release": "Release notes", "apis": "Outside systems", "widgets": "Widgets"}
CLASS_TEXT = {"startup-noise": ("Rewritten on every start", "The old app differs between two of its own starts too. Accepted."),
              "test-setup": ("Test setup", "A test problem, not an app problem. The test is repaired and rerun."),
              "no-click-path": ("No click path", "The test found no way to reach the button. Needs a better test, not an app change."),
              "no-test-data": ("Empty lists", "The test needs rows to click. Add test rows, rerun."),
              "outside-call": ("Outside systems", "These need an outside system. Point them at the mock."),
              "real-regression": ("Real problems", "Worked on the old app, fails on the new one.")}
STEP_HOW = {"step": "Automatic module update (stepupdate), identity check passed", "convert": "Automatic Mendix converter",
            "replay": "Our own earlier edits applied again", "repair": "Repaired", "build": "Rebuilt"}
SIGNED = re.compile(r"^Signed-off:[ \t]+(\S.*?)[ \t]+(\d{4}-\d{2}-\d{2})[ \t]*$")
HASH = re.compile(r"^<!-- proposal inputs-hash: ([0-9a-f]{64}) -->$")


def rd(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return None


def rj(path):
    t = rd(path)
    try:
        return json.loads(t) if t else None
    except ValueError:
        return None


def short(s, n=150):
    s = " ".join(str(s).replace("`", "").replace(" \u2014 ", ", ").replace(" \u2013 ", ", ").split())
    if len(s) <= n:
        return s
    cut = s[:n]
    for sep in (". ", "; ", ", ", " "):
        i = cut.rfind(sep)
        if i > n * 0.5:
            return cut[:i].rstrip(".;,") + "..."
    return cut + "..."


def effort_of(text):
    m = re.search(r"effort[: ]+(none|large|medium|small|[SML])\b", text or "", re.I) or re.search(r"\((none|[SML])\)", text or "")
    return EFFORT.get(m.group(1).lower(), "N") if m else "N"


def mins(a, b):
    try:
        f = "%Y-%m-%dT%H:%M:%SZ"
        return (datetime.datetime.strptime(b, f) - datetime.datetime.strptime(a, f)).total_seconds() / 60
    except ValueError:
        return 0


def pl(n, one, many=None):
    """'1 thing', '5 things': real singular and plural, never '(s)'."""
    return f"{n} {one if n == 1 else (many or one + 's')}"


def dur(m):
    if m is None:
        return ""
    if m < 1:
        return "< 1 min"
    if m < 60:
        return f"{int(round(m))} min"
    h, r = divmod(int(round(m)), 60)
    return f"{h} h {r:02d}" if r else f"{h} h"


# ---- proposal ----
def parse_proposal(text):
    P = {"title": "", "hash": "", "sec2": [], "sec3": [], "sec4": [], "summary": [], "signed": None, "paused": False, "present": bool(text)}
    if not text:
        return P
    sec, cur = "", None
    for ln in text.splitlines():
        m = HASH.match(ln)
        if m:
            P["hash"] = m.group(1)
        if ln.startswith("# "):
            P["title"] = ln[2:].strip()
        if ln.startswith("## "):
            sec = ln[3:4]
            cur = None
            continue
        if sec == "6":
            m = SIGNED.match(ln)
            if m:
                P["signed"] = (m.group(1), m.group(2))
            if ln.startswith("Status: PAUSED"):
                P["paused"] = True
        if sec in ("1", "2", "3", "4") and ln.startswith("- "):
            body = ln[2:].strip()
            if sec == "1":
                P["summary"].append(body)
                continue
            cur = {"text": body, "sub": {}}
            m = re.match(r"^\[(P-\d+)\] (\w+): (.*)$", body)
            if m:
                cur.update(id=m.group(1), kind=m.group(2), name=m.group(3).strip())
            P["sec" + sec].append(cur)
        elif cur is not None and re.match(r"^\s+- ", ln):
            b = ln.strip()[2:]
            k, _, v = b.partition(": ")
            cur["sub"][k if _ else "note"] = v if _ else b
    return P


def parse_decisions_md(text):
    out = {}
    for ln in (text or "").splitlines():
        m = re.match(r"^(P-\d+)\s*\|(.*)$", ln)
        if m:
            f = [x.strip() for x in m.group(2).split("|")]
            out[m.group(1)] = f
    return out


def parse_agent_decisions(text):
    """{base id: {"id","title","choice","why","rows":[...],"confirm":bool,"commits":[...]}} from the markdown table."""
    out = {}
    for ln in (text or "").splitlines():
        if not ln.startswith("|"):
            continue
        c = [x.strip() for x in ln.strip().strip("|").split("|")]
        m = re.match(r"^(D\d+[a-z]?)\b", c[0]) if c else None
        if not m or len(c) < 3:
            continue
        bid = re.match(r"^(D\d+)", m.group(1)).group(1)
        d = out.setdefault(bid, {"id": bid, "title": "", "choice": "", "why": "", "rows": [], "confirm": False, "commits": []})
        row = " ".join(c)
        d["rows"].append(row)
        if not d["title"]:
            d["title"] = re.sub(r"\s*\((agent|OPEN)[^)]*\)\s*", " ", c[1]).strip() if len(c) > 1 else ""
            d["choice"] = c[2] if len(c) > 2 else ""
            d["why"] = c[3] if len(c) > 3 else ""
        if re.search(r"\bconfirm\b", row, re.I) and not re.search(r"\bnot\b.{0,10}\bconfirm", row, re.I):
            d["confirm"] = True
        d["commits"] += re.findall(r"\bcommit(?:ted)? ([0-9a-f]{7,})", row)
    return out


# ---- gate / heal ----
def parse_gate(text):
    rungs = []
    for ln in (text or "").splitlines():
        m = re.match(r"^\| (\d+) \| (\w+) \| (PASS\*?|FAIL|INVALID|NOT RUN|REVIEW|EXCEPT)[^|]*\|[^|]*\|(.*)\|\s*$", ln)
        if m:
            rungs.append({"rung": m.group(2), "verdict": m.group(3), "detail": m.group(4).strip()})
    ov = re.search(r"^Overall: \*\*(\w+)\*\*", text or "", re.M)
    return {"rungs": rungs, "overall": ov.group(1) if ov else ""}


def gate_sentence(r, causes, heal_repairs, nreal):
    """One short sentence for a gate rung: the result in words, then the cause when known. Never the raw gate line."""
    v, rung = r["verdict"], r["rung"]
    d = r["detail"].replace("\\|", "|")
    cause = f" Cause: {', '.join(dict.fromkeys(causes))}." if causes else ""

    def n(pat):
        m = re.search(pat, d)
        return int(m.group(1)) if m else 0
    if rung == "smoke":
        p, f, i = n(r"PASS (\d+)"), n(r"FAIL (\d+)"), n(r"INVALID (\d+)")
        t = p + f + i
        bits = [f"{f} of {pl(t, 'page check')} fail" if f != 1 else f"1 of {pl(t, 'page check')} fails"]
        if i:
            bits.append(f"{i} could not run")
        return ", ".join(bits) + "." + cause
    if rung == "journeys":
        p, f, i = n(r"journeys: (\d+) PASS"), n(r"(\d+) FAIL"), n(r"(\d+) INVALID")
        txt = f"{p} pass, {f} fail, {i} cannot run yet."
        if nreal:
            txt += f" {pl(nreal, 'real problem')}" + (f" ({', '.join(dict.fromkeys(causes))})" if causes else "") + "."
        if heal_repairs:
            txt += " The other failures are test problems that get repaired."
        return txt
    if rung == "screens":
        rv, iv = n(r"(\d+) REVIEW"), n(r"screens: .*?(\d+) INVALID")
        bits = []
        if rv:
            bits.append(f"{pl(rv, 'screen')} changed and {'needs' if rv == 1 else 'need'} a look")
        if iv:
            bits.append(f"{pl(iv, 'screen')} could not be compared")
        return (", ".join(bits) + ".") if bits else "Screens are not measured yet."
    if rung == "apis":
        found, mocked, unk = n(r"apis (\d+) found"), n(r"mocked (\d+)"), n(r"unknown (\d+)")
        txt = f"{pl(found, 'outside call')}: {mocked} can be mocked, {unk} unknown."
        if re.search(r"MOCKED endpoints NOT", d):
            txt += " Mock was not switched on."
        return txt + " Real test needed before go-live."
    bits = []
    for pat, w in ((r"(\d+) FAIL", "fail"), (r"(\d+) REVIEW", "need a look"), (r"(\d+) INVALID", "cannot run yet")):
        c = n(pat)
        if c:
            bits.append(f"{c} {w}")
    if bits:
        return ", ".join(bits) + "." + cause
    return {"FAIL": "Failed.", "REVIEW": "Needs a look.", "INVALID": "Could not be measured yet."}.get(v, "Not measured yet.") + cause


def status_of(v):
    return {"PASS": "ok", "PASS*": "ok", "EXCEPT": "ok", "FAIL": "bad", "REVIEW": "warn", "INVALID": "warn", "NOT RUN": "idle"}.get(v, "idle")


def parse_notes(text):
    """gate-notes.txt: free text with 'Dn: ...' segments. Returns [(id, text)]."""
    out = []
    for ln in (text or "").splitlines():
        ms = list(re.finditer(r"\b(D\d+[a-z]?)\)?: ", ln))
        for k, m in enumerate(ms):
            end = ms[k + 1].start() if k + 1 < len(ms) else len(ln)
            seg = ln[m.end():end]
            seg = re.sub(r"\s+[A-Z ]{6,}\($", "", seg).strip()
            out.append((m.group(1), seg))
    return out


def plain(label):
    """Drop module.page ids, version numbers in brackets and trailing remarks from a label."""
    t = re.split(r"; |\. (?=[A-Z])", label)[0]
    t = re.sub(r"\([^)]*\)", "", t)
    t = re.sub(r"\b(?:from|in|on|at) \S*[._]\S*", "", t)
    t = re.sub(r"\b[A-Z]\w*\.\w+\b", "", t)
    t = " ".join(t.split()).rstrip(",: ")
    return (t[:1].upper() + t[1:]) if t else label


def regression_groups(heal, notes):
    """Group the real regressions by cause. Cause comes from a gate-notes.txt REGRESSION line that names the page's
    module or page stem; else from the evidence (covered click, error page); else by module."""
    causes = [(i, t) for i, t in notes if "REGRESSION" in t]
    g, order = {}, []
    for r in (heal or {}).get("rows", []):
        if r.get("class") != "real-regression":
            continue
        i, ev = r.get("id", ""), r.get("evidence", "")
        page = re.sub(r"^act-", "", i.split(":", 1)[-1])
        page = page.rsplit(".", 1)[0] if "." in page else page
        module = page.split(".")[0]
        stem = re.split(r"[._]", page.split(".")[-1])[0]
        note = next(((ni, nt) for ni, nt in causes if re.search(r"\b" + re.escape(module) + r"(_|\b)", nt) or
                     (len(stem) >= 4 and stem.lower() in nt.lower())), None)
        if note:
            sm = re.match(r"([A-Za-z][\w./]*)", note[1])
            subj = sm.group(1) if sm else module
            key, kind = re.sub(r"\W+", "-", subj), "note"
        elif re.search(r"covered by|overlay|underlay", ev):
            key, kind = "overlay", "overlay"
        elif re.search(r"does NOT say|error|blank", ev):
            key, kind = "page-error", "error"
        else:
            key, kind = "module-" + module, "module"
        e = g.get(key)
        if e is None:
            e = g[key] = {"key": key, "kind": kind, "note": note, "module": module, "pages": [], "ids": [], "ev": []}
            order.append(key)
        if page not in e["pages"]:
            e["pages"].append(page)
        e["ids"].append(i)
        e["ev"].append(ev)
    out = []
    for k in order:
        e = g[k]
        n = len(e["ids"])
        npg = len(e["pages"])
        places = ""
        fix = ""
        if e["kind"] == "note":
            t = e["note"][1]
            sm = re.match(r"([A-Za-z][\w./]*)", t)
            subj = sm.group(1)
            pm = re.search(r"about (\d+) (units|places|pages)", t)
            places = f"about {pm.group(1)} places" if pm else ""
            fm = re.search(r"[Rr]ework needed: (.+?)\s*(?:\(about[^)]*\))?\.?$", t)
            fix = fm.group(1) if fm else ""
            why = re.search(r"\(([^()]*)\)", t)
            e["title"] = ("Replace " if fix.lower().startswith("replace") else "Fix ") + subj
            e["short"] = subj
            e["problem"] = (f"{subj} ({why.group(1)}). " if why else f"{subj}. ") + f"{pl(npg, 'page')} that passed on the old app fail on the new one."
            e["rec_text"] = (fix[:1].upper() + fix[1:] + ".") if fix else "Fix the app: the old version passes it, so a person must see why the new one does not."
            e["effort"] = "C" if pm and int(pm.group(1)) >= 50 else "M"
        elif e["kind"] == "overlay":
            sel = sorted({m.group(1) for ev in e["ev"] for m in [re.search(r"covered by (\S+)", ev)] if m})
            e["title"] = f"Overlay blocks {pl(n, 'click')}"
            e["short"] = f"an overlay blocks {pl(n, 'click')}"
            e["problem"] = "A click lands on a layer that covers its target" + (f" ({', '.join(sel)})" if sel else "") + ". The old app passes the same click."
            e["rec_text"] = "Fix the app: find the layer that stays on top after the page loads."
            e["effort"] = "M"
        elif e["kind"] == "error":
            e["title"] = f"{pl(npg, 'page')} {'shows' if npg == 1 else 'show'} an error"
            e["short"] = "an error on the page"
            e["problem"] = "These pages work on the old app and show an error or stay blank on the new one."
            e["rec_text"] = "Fix the app: the old version passes it, so a person must see why the new one does not."
            e["effort"] = "M"
        else:
            e["title"] = f"Fix the {e['module']} pages"
            e["short"] = f"the {e['module']} pages"
            e["problem"] = short(e["ev"][0], 220) if e["ev"] else "Passes on the old app, fails on the new one."
            e["rec_text"] = "Fix the app: the old version passes it, so a person must see why the new one does not."
            e["effort"] = "M"
        e["meta"] = "Real regression · " + (places + " · " if places else "") + f"{pl(npg, 'page')} {'fails' if npg == 1 else 'fail'}"
        out.append(e)
    return out


# ---- app git log ----
def app_commits(work):
    app = os.path.join(os.path.dirname(work), "app")
    if not os.path.exists(os.path.join(app, ".git")):
        return []
    try:
        o = subprocess.run(["git", "-C", app, "log", "--reverse", "--format=%h|%s"], capture_output=True, text=True, timeout=30).stdout
    except (OSError, subprocess.SubprocessError):
        return []
    return [tuple(x.split("|", 1)) for x in o.splitlines() if "|" in x]


def app_name(work):
    for d in (os.path.join(os.path.dirname(work), "app"), work):
        for p in sorted(glob.glob(os.path.join(d, "*.mpr"))):
            n = os.path.splitext(os.path.basename(p))[0]
            if n != "original":
                return n
    return "App"


# ---- time ----
def run_minutes(work):
    """Minutes per step: timing.tsv rows when present, else the gap between done markers (capped at 6 h per step)."""
    per = {}
    for ln in (rd(os.path.join(work, "state", "timing.tsv")) or "").splitlines()[1:]:
        f = ln.split("\t")
        if len(f) >= 3:
            per[f[0]] = per.get(f[0], 0) + mins(f[1], f[2])
    prev = None
    for s in STEP_ORDER:
        t = rd(os.path.join(work, "state", s + ".done"))
        if not t:
            continue
        t = t.strip()
        if s not in per and prev:
            per[s] = min(mins(prev, t), 360) if mins(prev, t) > 0 else 0
        prev = t
    return per


# ---- the model ----
def build_model(work):
    work = os.path.abspath(work)
    P = parse_proposal(rd(os.path.join(work, "PROPOSAL.md")))
    dm = parse_decisions_md(rd(os.path.join(work, "DECISIONS.md")))
    ad_text = rd(os.path.join(work, "AGENT-DECISIONS.md")) or rd(os.path.join(os.path.dirname(work), "AGENT-DECISIONS.md"))
    import steps as stp   # bin/steps.py: the step records, the only writer of steps.jsonl
    recs, _err = stp.load(work)   # None when work/steps.jsonl is missing or damaged: then AGENT-DECISIONS.md is read as before
    AD = parse_agent_decisions(ad_text) if recs is None else {}   # with step records every agent decision is a step, so it is counted there
    gate = parse_gate(rd(os.path.join(work, "gate-summary.md")))
    heal = rj(os.path.join(work, "heal.json")) or {}
    djo = (rj(os.path.join(work, "decisions-open.json")) or {}).get("items", [])
    inv = (rj(os.path.join(work, "apimock-inventory.json")) or {}).get("endpoints", [])
    finds = (rj(os.path.join(work, "findings.json")) or {}).get("findings", [])
    ledger = rj(os.path.join(work, "decisions.json")) or []
    last = {}
    for r in ledger:
        last[r.get("item")] = r
    nj = rd(os.path.join(work, "NEEDS-JUDGMENT.md")) or ""
    m = re.match(r"# NEEDS JUDGMENT: step (\w+), exit (\d+)", nj)
    stopped = (m.group(1), int(m.group(2))) if m else None
    done = {s: bool(rd(os.path.join(work, "state", s + ".done"))) for s in STEP_ORDER}
    per = run_minutes(work)
    commits = app_commits(work)

    vm = re.search(r"(\d+(?:\.\d+)+)\s*(?:->|to)\s*(\d+(?:\.\d+)+)", P["title"] or "")
    if not vm:
        vm = re.search(r"--source (\S+) --target (\S+)", rd(os.path.join(work, "state", "cmdline.txt")) or "")
    versions = f"{vm.group(1)} → {vm.group(2)}" if vm else ""
    unknown_api = [e for e in inv if e.get("status") == "UNKNOWN"]
    mocked_api = [e for e in inv if e.get("status") == "MOCKED"]
    notes = parse_notes(rd(os.path.join(work, "gate-notes.txt")))
    rgroups = regression_groups(heal, notes)
    regs = [pg for e in rgroups for pg in e["pages"]]   # one entry per page that really regressed
    signed = P["signed"]

    # --- needs-you items ---
    items = []

    def add(it):
        it["decided"] = last.get(it["id"])
        items.append(it)

    for e in rgroups:
        add({"id": f"regression:{e['key']}", "kind": "regression", "dot": "bad", "title": e["title"], "step": "diff",
             "meta": e["meta"], "problem": e["problem"], "tech": e["ids"],
             "rec": "fix", "rec_text": e["rec_text"],
             "options": [{"key": "fix", "label": "Fix the app", "causes": "The row stays open until the new app passes it."},
                         {"key": "accept", "label": "Accept the change as intended", "causes": "Recorded in regression-decisions.txt with your name and reason.",
                          "writes": [{"file": "regression-decisions.txt", "line": f"journey:act-{pg}.* accepted"} for pg in e["pages"]]},
                         {"key": "old-wrong", "label": "The old behaviour was wrong", "causes": "Recorded in regression-decisions.txt with your name and reason.",
                          "writes": [{"file": "regression-decisions.txt", "line": f"journey:act-{pg}.* old-behaviour-wrong"} for pg in e["pages"]]}]})
    for j in djo:
        if regs and j.get("step") in ("journeys", "diff", "gate"):
            continue   # folded into the regression rows above
        wt = j.get("write_to", "")
        if re.match(r"^[\w.-]+\.txt$", wt or "") and os.path.exists(os.path.join(work, wt)):
            continue   # the file the item asks for exists: closed
        opts = []
        for o in j.get("options", []):
            op = {"key": o.get("key"), "label": o.get("label", o.get("key")), "causes": o.get("causes", "")}
            if o.get("writes"):
                op["writes"] = o["writes"]
            elif o.get("key") == "accept" and j.get("pattern") and re.search(r"(approved|allow|shot-accept)", wt or ""):
                f = wt.replace("<rung>", j.get("rung", "journeys")) if "<" in wt else wt
                op["writes"] = [{"file": f, "line": j["pattern"]}]
            opts.append(op)
        rec = j.get("recommended")
        add({"id": f"judgment:{j.get('id')}", "kind": "judgment", "dot": "bad" if j.get("severity") == "blocks" else "warn",
             "title": j.get("question", j.get("id")), "step": j.get("step", ""), "meta": f"Open since step {j.get('step', '?')}, effort {opts[0].get('effort', '') if opts else ''}".replace(", effort ", ""),
             "problem": short(j.get("what", ""), 260) + (" " + short(j.get("why_matters", ""), 160) if j.get("why_matters") else ""),
             "rec": rec, "rec_text": j.get("recommended_why", ""), "options": opts})
    conf = {}   # change id -> {"label","tech","commit"}; from AGENT-DECISIONS rows marked confirm and gate-notes lines that ask for a look
    for bid, d in AD.items():
        if d["confirm"]:
            conf[bid] = {"label": plain(d["title"]) or d["title"], "tech": short(d["title"] + ": " + d["choice"], 200), "commit": d["commits"][0][:7] if d["commits"] else ""}
    for nid, nt in notes:
        base = re.match(r"D\d+", nid).group(0)
        if "REGRESSION" in nt or not re.search(r"confirm|review", nt, re.I):
            continue
        c = conf.setdefault(nid if nid not in AD and base not in AD else base, {"label": "", "tech": "", "commit": ""})
        c["label"] = plain(nt)
        c["tech"] = f"{nid}: " + short(nt, 200)
    ckids = []
    covered = {d for r in (recs or []) for d in (r["proposed"].get("decisions") or [])}   # D rows a step already names
    for bid, c in sorted(conf.items(), key=lambda kv: (int(re.match(r"D(\d+)", kv[0]).group(1)), kv[0])):
        if re.match(r"D\d+", bid).group(0) in covered:
            continue   # the step holds this change, so the legacy "Changes the agent made" row does not repeat it
        ckids.append(f"confirm:{bid}")
        items.append({"id": f"confirm:{bid}", "kind": "confirm", "hidden": True, "dot": "warn", "title": c["label"], "step": "build",
                      "meta": "A change the agent made", "problem": c["tech"], "tech": [c["tech"]] + ([f"commit {c['commit']}"] if c["commit"] else []),
                      "decided": last.get(f"confirm:{bid}"), "rec": "accept", "rec_text": "Accept it if the result looks right; a rejected change goes back into the plan.",
                      "options": [{"key": "accept", "label": "Accept this change", "causes": "Stays as built."},
                                  {"key": "reject", "label": "Reject, put it back in the plan", "causes": "Listed in rejected-changes.txt for the next round.",
                                   "writes": [{"file": "rejected-changes.txt", "line": f"{bid} {short(c['label'], 60)}"}]}]})
    if ckids:
        kids = [i for i in items if i["id"] in ckids]
        nopen = sum(1 for k in kids if not k["decided"])
        items.append({"id": "confirm", "kind": "confirmgroup", "dot": "warn", "title": f"Confirm {pl(len(kids), 'change')} the agent made",
                      "meta": "Listed under Upgrade, marked confirm" if nopen else "All decided, waiting for the pipeline", "step": "build",
                      "problem": "Each change has its commit. Accept or reject one by one; a rejected one goes back into the plan.",
                      "rec": "", "rec_text": "Review them one by one.", "options": [], "children": ckids, "decided": None, "open": nopen})
    # P-n choices: pending in chat; on the page they belong to the sign-off row
    assumed = []
    for it in P["sec3"]:
        pid = it.get("id")
        if not pid:
            continue
        row = dm.get(pid)
        opts_txt = [x.strip() for x in it["sub"].get("options", "").split(" | ") if x.strip()]
        rec_txt = it["sub"].get("recommendation", "")
        opts = [{"key": "rec", "label": short(rec_txt.split(";")[0] if rec_txt else "Take the recommendation", 110), "causes": ""}]
        for n, o in enumerate(opts_txt, 1):
            opts.append({"key": f"o{n}", "label": short(o, 110), "causes": ""})
        for o in opts:
            o["writes"] = [{"decisions_md": {"id": pid, "name": it["name"], "kind": it["kind"], "option": o["label"]}}]
        is_assumed = bool(row and "ASSUMED" in (row[5] if len(row) > 5 else "")) or not row
        if is_assumed and not last.get(pid):
            assumed.append(pid)
        items.append({"id": pid, "kind": "plan-choice", "hidden": True, "dot": "warn", "title": f"{it['name']} ({it['kind']})", "step": "propose",
                      "meta": "Plan choice", "problem": short(it["sub"].get("evidence", ""), 260), "rec": "rec", "rec_text": short(rec_txt, 200),
                      "options": opts, "decided": last.get(pid), "assumed": is_assumed, "effort": effort_of(rec_txt)})
    plan_signed = bool(signed)
    if P["present"] and not plan_signed:
        # Source of the count: every decision the agent recorded in AGENT-DECISIONS.md (len(AD), one per Dn) plus the plan choices
        # in PROPOSAL.md / DECISIONS.md that nobody answered (len(assumed)).
        n = len(AD) + len(assumed) if recs is None else sum(1 for r in recs if (r.get("approval") or {}).get("state") == "assumed")
        add({"id": "signoff", "kind": "signoff", "dot": "warn", "title": "Sign the plan",
             "meta": f"{pl(n, 'choice')} {'was' if n == 1 else 'were'} assumed by the agent" if n else "Nothing goes live without your name",
             "step": "propose", "problem": "Nothing goes live without your name on the plan. Review it under Plan. To change one choice first, say so in chat (decisions.py pending lists them).",
             "rec": "sign", "rec_text": "Read the plan, then sign.", "options": [{"key": "sign", "label": "Sign the plan"}], "plan_hash": P["hash"]})
    visible = [i for i in items if not i.get("hidden")]
    open_visible = [i for i in visible if not (i.get("decided") and i["kind"] != "signoff") and i.get("open", 1)]
    order = {"bad": 0, "warn": 1}
    visible.sort(key=lambda i: order.get(i["dot"], 2))
    items = visible + [i for i in items if i.get("hidden")]

    # --- phases ---
    phases = []

    def phase_time(steps):
        v = [per[s] for s in steps if s in per]
        return dur(sum(v)) if v else ""

    # Find
    rows = []
    sec3 = [i for i in P["sec3"] if i.get("id")]
    rl = len([r for r in (rd(os.path.join(work, "release-impact.md")) or "").splitlines() if re.match(r"^\| \d+ \|", r)])
    mods = [i["text"] for i in P["sec2"] if i["text"].startswith("module update")]
    if mods:
        names = sorted({re.sub(r"^module update (\S+) .*", r"\1", t) for t in mods})
        rows.append([f"{pl(len(names), 'Marketplace module')} to update", short(", ".join(names), 140) + ". The toolkit updates them and keeps our own edits.", "M", "ok"])
    for it in sec3:
        row = dm.get(it["id"])
        st = "ok" if (last.get(it["id"]) or (row and "CONFIRMED" in (row[5] if len(row) > 5 else ""))) else "warn"
        rows.append([f"{it['name']}", short(it["sub"].get("evidence", it["text"]), 140), effort_of(it["sub"].get("recommendation", "")), st])
    sev = {}
    for f in finds:
        sev.setdefault(f.get("severity"), {}).setdefault(f.get("catalog_id"), []).append(f)
    for s, eff in (("blocker", "C"), ("high", "M")):
        for cid, fl in sorted(sev.get(s, {}).items(), key=lambda kv: -len(kv[1])):
            rows.append([f"{len(fl)} × {cid.replace('MX11-', '').replace('-', ' ').lower()}", f"{s.capitalize()} finding in the Mendix 11 catalog: {short(fl[0].get('evidence', {}).get('text', ''), 90)}", eff, "ok"])
    low = sum(len(v) for k, d in sev.items() if k not in ("blocker", "high") for v in d.values())
    if low:
        rows.append([f"{low} low-risk notes", "Listed in the findings, no decision needed.", "S", "ok"])
    if inv:
        rows.append([f"{len(inv)} outside API calls", f"{len(mocked_api)} can be mocked, {len(unknown_api)} get their address from data or are not classified.", "M" if unknown_api else "S", "warn" if unknown_api else "ok"])
    for it in P["sec4"]:
        rows.append([short(it["text"], 70), short(" ".join(it["sub"].values()), 140), "N", "idle"])
    nfind = len(rows)
    phases.append({"id": "find", "n": "Find", "cls": "done" if done["triage"] else "", "time": phase_time(PHASES[0][2]),
                   "s": "What changes in " + (versions.split("→")[-1].strip().split(".")[0] if versions else "the new version") if done["triage"] else "Not started",
                   "title": f"Find: what {versions.split(chr(8594))[-1].strip() if versions else 'the new version'} changes for this app",
                   "intro": "The pipeline read the app and the release notes, and listed everything that breaks or needs a decision.",
                   "facts": [[str(len(finds)), "findings"], [str(rl), "release note rows"], [str(len(inv)), "outside API calls"],
                             [str(sum(1 for r in rows if r[2] == "C")), "complex items"]],
                   "cols": ["Found", "What it means", "Effort", "Status"], "rows": rows})
    # Plan
    rows = []
    for it in sec3:
        row = dm.get(it["id"])
        led = last.get(it["id"])
        opt = next((p for p in items if p["id"] == it["id"]), None)
        if led:
            lab = next((o["label"] for o in opt["options"] if o["key"] == led.get("choice")), led.get("choice"))
            what, st = f"{lab} (by {led.get('by')} via {led.get('source')})", "ok"
        else:
            what = short(row[2] if row and len(row) > 2 else it["sub"].get("recommendation", ""), 150)
            st = "ok" if row and "CONFIRMED" in (row[5] if len(row) > 5 else "") else "warn"
        rows.append([it["name"], what, effort_of(it["sub"].get("recommendation", "")), st])
    rows.append(["Sign-off", f"Signed by {signed[0]} on {signed[1]}." if signed else ("Paused by the owner." if P["paused"] else "Waiting for your name."), "N", "ok" if signed else "warn"])
    cnt = {k: sum(1 for r in rows[:-1] if r[2] == k) for k in "CMSN"}
    pcls = "done" if signed else ("wait" if done["propose"] else "")
    phases.append({"id": "plan", "n": "Plan", "cls": pcls, "time": phase_time(PHASES[1][2]),
                   "s": "Signed" if signed else ("Choices, not signed" if done["propose"] else "Not started"),
                   "title": "Plan: what we decided per topic",
                   "intro": "Every topic got options and one choice. Nothing in the app changes before a person signs.",
                   "facts": [[str(len(sec3)), "topics"], [str(cnt["C"]), "large"], [str(cnt["M"]), "medium"], [str(cnt["S"] + cnt["N"]), "small or none"]],
                   "cols": ["Topic", "Choice", "Effort", "Status"], "rows": rows})
    # Upgrade
    rows, nbuild = [], 0
    eff_by_name = {it["name"]: effort_of(it["sub"].get("recommendation", "")) for it in sec3}
    confirm_ids = {i["id"].split(":")[1]: i for i in items if i["kind"] == "confirm"}
    if done["baseline"]:
        rows.append(["Snapshot old app", "The old app is kept as it was, so every test can compare against it.", "N", "ok"])
    for h, sub in commits:
        pre, _, rest = sub.partition(": ")
        base = pre.split()[0]
        if sub == "original" or base == "build":
            nbuild += (base == "build")
            continue
        did = re.search(r"\b(D\d+)", pre + " " + rest)
        how = STEP_HOW.get(base, "")
        if base == "step":
            item, what = re.sub(r"\s*\(.*$", "", rest), how
        elif base == "convert":
            item, what = sub, how
        else:
            item, what = pre[:1].upper() + pre[1:], short(rest, 140)
        what += f" (commit {h})"
        eff = next((e for n, e in eff_by_name.items() if n and n in sub), "S")
        st = "warn" if did and did.group(1) in confirm_ids and not last.get(f"confirm:{did.group(1)}") else "ok"
        rows.append([short(item, 60), what, eff, st])
    if nbuild:
        rows.append(["Rebuilds", f"{pl(nbuild, 'regenerated build output commit')}, nothing to review.", "N", "ok"])
    nconf = sum(1 for i in confirm_ids.values() if not i["decided"])
    errs = None
    bl = next((r for r in gate["rungs"] if r["rung"] == "build"), None)
    ucls = "done" if done["build"] else ("now" if stopped and stopped[0] in ("convert", "update", "build") else "")
    phases.append({"id": "upgrade", "n": "Upgrade", "cls": ucls, "time": phase_time(PHASES[2][2]),
                   "s": ("Built" + (", 0 errors" if bl and bl["verdict"].startswith("PASS") else "")) if done["build"] else ("Stopped" if ucls == "now" else "Not started"),
                   "title": "Upgrade: how we did it",
                   "intro": "Snapshot the old app, convert, update the modules, then build and repair until there are no errors. Every change has its commit.",
                   "facts": [[str(len(commits) - 1 - nbuild if commits else 0), "changes in the app"], [str(len(mods)), "module steps"],
                             [str(sum(1 for c in commits if c[1].startswith("repair"))), "repairs"], [str(nconf), "to confirm"]],
                   "cols": ["Change", "How we did it", "Effort", "Status"], "rows": rows})
    # Test
    rows = []
    okr = [r for r in gate["rungs"] if status_of(r["verdict"]) == "ok"]
    nrr = [r for r in gate["rungs"] if r["verdict"] == "NOT RUN"]
    cl = {}
    for r in heal.get("rows", []):
        cl.setdefault(r.get("class"), []).append(r)
    note_causes = [e["short"] for e in rgroups if e["kind"] == "note"]
    all_causes = [e["short"] for e in rgroups]
    if okr:
        acc = sum(1 for r in okr if r["verdict"] == "PASS*")
        rows.append([", ".join(RUNG_NAMES.get(r["rung"], r["rung"]) for r in okr)[:70], f"All pass{f', {acc} with accepted differences' if acc else ''}.", "N", "ok"])
    for r in gate["rungs"]:
        v = r["verdict"]
        if status_of(v) == "ok" or v == "NOT RUN":
            continue
        rows.append([RUNG_NAMES.get(r["rung"], r["rung"]), gate_sentence(r, note_causes if r["rung"] == "smoke" else all_causes, bool(cl.get("test-setup") or cl.get("no-click-path")), len(regs)),
                     "C" if v == "FAIL" and regs else "M", status_of(v)])
    if nrr:
        nm = [RUNG_NAMES.get(r["rung"], r["rung"]) for r in nrr]
        rows.append([pl(len(nrr), "check") + " not run", ", ".join([nm[0]] + [x[:1].lower() + x[1:] for x in nm[1:]]) + ": not run in this run.", "M", "idle"])
    unresolved = 0
    for c, rs in sorted(cl.items(), key=lambda kv: (kv[0] == "real-regression", kv[0])):
        acc = sum(1 for r in rs if str(r.get("result", "")).startswith("accepted"))
        lab, txt = CLASS_TEXT.get(c, (c, "Classified by the heal step."))
        if c == "real-regression":
            for e in rgroups:
                rows.append([e["title"], f"Real regression: {pl(len(e['pages']), 'page')} {'fails' if len(e['pages']) == 1 else 'fail'}"
                             + (f", {e['meta'].split(' · ')[1]}" if e["meta"].count(" · ") > 1 else "") + ". " + e["rec_text"], e["effort"], "bad"])
            continue
        st = "ok" if acc == len(rs) else "run"
        unresolved += len(rs) - acc
        rows.append([f"{lab} ({len(rs)})", txt, "S", st])
    notrun = len(nrr)
    gate_done = done["gate"]
    if regs or gate["overall"] in ("FAIL",):
        tcls = "now"
    elif gate["rungs"] and gate["overall"] == "PASS":
        tcls = "done"
    elif gate["rungs"] or any(done[s] for s in ("after", "afterwalk", "journeys", "heal", "diff")):
        tcls = "wait"
    else:
        tcls = ""
    phases.append({"id": "test", "n": "Test", "cls": tcls, "time": phase_time(PHASES[3][2]),
                   "s": (pl(len(regs), "real problem") if regs else ("Passed" if tcls == "done" else ("Open items" if tcls else "Not started"))),
                   "title": "Test: new app against the old app",
                   "intro": "Most failures are test problems, not app problems. Those are repaired by the test side; real problems are listed for you.",
                   "facts": [[str(sum(1 for r in gate["rungs"] if r["verdict"].startswith("PASS"))), "checks pass"], [str(len(regs)), "real problem" if len(regs) == 1 else "real problems"],
                             [str(unresolved), "test rows being fixed"], [str(notrun), "not run yet"]],
                   "cols": ["Check", "Result and why", "Effort", "Status"], "rows": rows})
    # Go-live
    rows = []
    if P["present"] and not signed:
        rows.append(["Sign the plan", "Your name on the choices.", "S", "warn"])
    for e in rgroups:
        rows.append([e["title"], "A real problem the tests found. " + e["meta"].replace("Real regression · ", "").capitalize() + ".", e["effort"], "bad"])
    if nconf:
        rows.append([f"Confirm {pl(nconf, 'change')}", "One by one, under Upgrade.", "S", "warn"])
    if inv and (unknown_api or any(r["rung"] == "apis" and not r["verdict"].startswith("PASS") for r in gate["rungs"])):
        rows.append(["Test real APIs", f"In the test environment{', including the ' + str(len(unknown_api)) + ' unknown calls' if unknown_api else ''}.", "M", "idle"])
    rows.append(["Deploy to test", "Then a user test by the app team.", "M", "idle"])
    phases.append({"id": "golive", "n": "Go-live", "cls": "", "time": "", "s": "Not started", "title": "Go-live: what is left",
                   "intro": "Ready when the plan is signed, the real problems are fixed and the real APIs are tested.",
                   "facts": [[str(len(rows)), "steps left"]], "cols": ["Step", "What", "Effort", "Status"], "rows": rows})

    nb = len(regs)
    nn = len(open_visible)
    if nb:
        state = ("bad", f"Not ready yet. Testing found {pl(nb, 'real problem')}, {pl(nn, 'thing')} {'needs' if nn == 1 else 'need'} you.")
    elif nn:
        state = ("warn", f"Waiting for you. {pl(nn, 'thing')} {'needs' if nn == 1 else 'need'} you.")
    elif gate["overall"] == "PASS":
        state = ("ok", "Ready. Nothing is open.")
    else:
        lastdone = next((s for s in reversed(STEP_ORDER) if done[s]), None)
        state = ("idle", f"In progress. Last finished step: {lastdone}." if lastdone else "Not started.")
    total = sum(per.values())
    cost = (rj(os.path.join(work, "run-cost.json")) or {}).get("usd")
    runname = os.path.basename(os.path.dirname(work)) if os.path.basename(work) == "work" else os.path.basename(work)
    sub = " · ".join(x for x in [versions, runname, dur(total) if total else "", f"${cost:g}" if cost else ""] if x)
    if stopped:
        sub += f" · stopped at {stopped[0]}"
    return {"title": f"{app_name(work)} upgrade", "sub": sub, "state": {"dot": state[0], "text": state[1]}, "planHash": P["hash"],
            "signed": list(signed) if signed else None, "phases": phases, "items": items}


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--work", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--standalone", action="store_true", help="wrap the page content in doctype, html, head and body (a file opened directly, for example on a phone)")
    a = ap.parse_args()
    if not os.path.isdir(a.work):
        print(f"cockpitpage: no work folder {a.work}", file=sys.stderr)
        return 2
    import cockpitmatrix
    model = build_model(a.work)
    matrix = cockpitmatrix.build(a.work, model)
    page = cockpitmatrix.render(model, matrix)
    if a.standalone:
        page = '<!DOCTYPE html>\n<html lang="en"><head><meta charset="utf-8">\n' + page.replace("<style>", "<style>", 1).replace("\n<div class=\"wrap\">", "\n</head><body>\n<div class=\"wrap\">", 1) + "</body></html>\n"
    tmp = a.out + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(page)
    os.replace(tmp, a.out)
    print(f"cockpit: {a.out} ({len(matrix['rows'])} rows, {matrix['tiles']['you']} need you)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
