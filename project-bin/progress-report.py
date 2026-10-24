#!/usr/bin/env python3
"""Progress report: one self-contained HTML page for a conversion project, stages P to 6.

usage: progress-report.py PROJECT_DIR [--out FILE] [--toolkit DIR] [--rates FILE] [--fragment FILE]
                         [--logs-dir DIR] [--session-log PATH ...] [--no-log]

Called by project-bin/build-plan-status.sh (--html, --refresh, --open), which writes
architecture/progress-report.html. It replaces the older architecture/build-plan.html.

Reads, never writes, the project folder (PROJECT.md, index.html, architecture/build-plan.json),
the toolkit artifact manifest (bin/lib/artifact-manifest.tsv) and, when present, the Claude Code
session logs of this project on this machine (<config>/projects/<slug>/*.jsonl and the
subagents/ folders). Without a session log the project-only sections render and the time and
token sections say they are unavailable. Python 3 standard library only.

Privacy: the logs are read for numbers (token counters, timestamps, tool names) and for sub-agent
short descriptions. No prompt or message text is copied into the page.
Every tunable lives in the CONFIG block below so the page is easy to change.
"""
import sys, os, re, json, glob, html, fnmatch, calendar, collections, datetime, pathlib, argparse, time, urllib.parse

# ----------------------------------------------------------------- CONFIG
STAGES = ["P", "0", "1", "2", "3", "4", "5", "6"]
STAGE_NAME = {"P": "Kickoff", "0": "Triage", "1": "Analysis", "2": "Requirements",
              "3": "Architecture and design", "4": "Build plan", "5": "Build and improve",
              "6": "Verify and report"}
TABS = [("tab-overview", "Overview"), ("tab-build", "Build"), ("tab-changes", "Changes"), ("tab-performance", "Performance"), ("tab-pages", "Pages"), ("tab-notes", "Notes, tips and bugs")]
BUG_REPO = {"mxcli": ("mxcli", "https://github.com/mendixlabs/mxcli"), "toolkit": ("the toolkit", "https://github.com/MendixMau/mxcli-project-toolkit")}
REPORT_FILE = "progress-report.html"   # the one place the page name lives here (build-plan-status.sh asks for it with --print-name)
IDLE_GAP_S = 600          # a gap longer than this between two events counts as waiting for the user
CACHE_TTL_S = 300         # prompt cache time to live assumed for the cache rewrite observation
ACTIVE_S = 600            # a build counts as active when its last session or exec event is younger than this
# Placeholder list prices in USD per million tokens: glob, input, cache write, cache read, output.
# These are ASSUMED rates, not read from any source. Override with --rates FILE (same 5 columns).
DEFAULT_RATES = [("*opus*", 5.0, 6.25, 0.50, 25.0), ("*sonnet*", 3.0, 3.75, 0.30, 15.0),
                 ("*haiku*", 1.0, 1.25, 0.10, 5.0)]
# Sub-agent description -> stage override (first match wins); otherwise the time window decides.
PHASE_LEAD_S = 1800
AGENT_STAGE_RULES = [(r"Stage\s*(\d)", None), (r"inventory", "0"), (r"extractor|Path [AB]\b|extraction", "1"),
                     (r"\bBRD|Validate and fix|Consolidate", "2")]
# Extra artifact globs per stage on top of the toolkit manifest (project relative).
EXTRA_ARTIFACTS = {
    "P": ["intake.md", "PROJECT.md", "docs/BUILD-LOG.md"],
    "0": ["triage.md", "analysis/triage.html", "analysis/source-sufficiency.html", "analysis/source-sufficiency.json",
          "analysis/inventory-batches/*.json"],
    "1": ["knowledge-base/summary.md", "extractor/QUALITY.md",
          "extraction-quality.json", "analysis/facts.lock.json", "analysis/README.md"],
    "2": ["analysis/brd-report.html", "analysis/questions.html", "analysis/stage2-closeout.md",
          "knowledge-base/brd-contract.md", "questions/review-sheet.md",
          "questions/consolidated.json"],
    "3": ["architecture/blueprint.html", "module-design.html", "design/*.html", "design/*.md",
          "architecture/integration-contracts.md", "architecture/fit-gap.md",
          "architecture/blueprint.md", "design/wireframes/*.html", "architecture/modules/*/definition.md"],
    "4": ["architecture/build-plan.md", "architecture/build-plan.json",
          "architecture/modules/*/module-brief.md", "architecture/modules/*/coverage-ledger.md"],
    "5": [], "6": [],
}
# Project pages section: the HTML pages found on disk, grouped by folder. Only these top-level folders are scanned
# ("" = files directly in the project root, never below it); the inventory itself is never listed here, it is read from
# disk on every render. A folder named in PAGE_SKIP_DIRS (or starting with a dot) is never entered, at any depth, and a
# top-level folder that is a symlink or resolves outside the project is skipped. Each folder is here because a producer
# writes HTML into it (paths as in bin/lib/artifact-manifest.tsv):
PAGE_DIRS = ["",                # index.html (bin/gate-check.sh), test-report.html, module-design.html
             "analysis",        # brd-report.sh, app-report.sh, source-ledger.sh, extraction-report.sh, triage pages
             "architecture",    # blueprint.html (architecture-blueprint.md Step 7), module-design.html
             "design",          # design-system.html, process-map.js, wireframes/, ui-reviews/ (review-agent)
             "docs",            # render-improvement-register.sh, verify-module.sh (docs/verification/report.html)
             "reports",         # verify-module.sh's reports/test-report.html shape
             "knowledge-base"]  # extraction-report.sh's knowledge-base/extraction-report.html shape
PAGE_SKIP_DIRS = frozenset("node_modules .mpr-snapshots deployment mprcontents theme theme-cache .git vendor vendorlib "
                           "userlib javascriptsource widgets bower_components __pycache__ site-packages".split())
PAGE_MAX_DEPTH = 6        # folder levels below a scanned top-level folder
PAGE_GROUP_OPEN = 8       # a folder with more pages than this is folded behind a details with its count
PAGE_FOLDER_MAX = 100     # pages linked per folder at most; the rest are counted ("+K more"). Bounds what is listed, not
                          # what is walked: every folder keeps its row
# Project advisory thresholds (each rule says which one fired).
ADV = {"opus_cost_share": 0.40, "ctx_avg_tokens": 180_000, "ctx_peak_frac": 0.98, "compactions": 1,   # context: average under 180k is fine; the window counts as reached only at this share of the real window (or after a compaction). Context is never red
       "hang_amber_s": 600, "hang_red_s": 1800, "repeat_fail_red_n": 3, "min_lost_s": 60,   # red only for a key script failing on every run (at least this many runs) or one hang or stall past hang_red_s; amber from hang_amber_s
       "inherent_scripts": r"^(exec|gate-check|doctor|verify-module|review-module|build[\w-]*|mxbuild|mxcli|stack-up[\w-]*|test-stack-up)\.sh$",   # time in these is how the toolkit works, not a project choice
        "cache_rewrites": 3,
       "stage_outlier_x": 1.5, "agent_short_s": 120, "agent_long_s": 1800, "short_agents_n": 3, "long_agents_n": 2,
       "wait_share": 0.15, "cache_hit_min": 0.85, "max_items": 6,
       # tips from tool calls (numbers and tool or script names only)
       "hang_min_s": 300, "hang_x": 5, "hang_n": 1,          # a call is hanging past both: this many seconds and this many times its tool's median
       "repeat_fail_n": 3,                                    # the same script failing this many times
       "edit_loop_n": 6, "edit_loop_window_s": 1800,          # the same file edited this many times inside this window
       "ci_wait_s": 600,                                      # seconds spent in sleep, watch or monitor calls
       "large_read_chars": 40000, "large_read_n": 3,          # file reads this large, this many times
       "slow_script_s": 60, "slow_script_runs": 3, "slow_script_total_s": 300,   # a script slow on every run
       "serial_agents_n": 3, "serial_agent_s": 60,            # sub-agents run one after another that could overlap
       "full_test_n": 3, "full_test_s": 120,                  # full test suite runs
       "slice_outlier_x": 2.0, "slice_outlier_n": 1,          # exec.sh runs above this multiple of the median
       "fail_share_amber": 0.25}                              # run health: amber from this failure rate (of all calls, or of one key script); red is never rate-based
SCRIPT_FILE_RE = re.compile(r"\.(sh|py|js)$")
REAL_CMDS = frozenset("mxcli mxbuild mx git gh npm npx node python python3 make curl jq docker".split())   # the only non-file commands a tip may name
TRIVIAL_CMDS = frozenset("cd sleep echo true false test [ ls cat pwd export source . printf grep diff".split())   # shell builtins and trivial commands: a non-zero exit is routine, never a repeat-failure tip
INHERENT_TOOLS = frozenset(("AskUserQuestion", "ExitPlanMode"))   # required interview and approval time: waiting on the user, not a slow step or a hang
TOKENS_PER_MIN = 30_000   # assumed exchange rate used only to rank token waste against time waste
KEY_SCRIPTS = (("doctor", r"^doctor\.sh$"), ("gate-check", r"^gate-check\.sh$"), ("exec", r"^exec\.sh$"),
               ("tests", r"^(test-[\w.-]*\.sh|run-all\.sh|run-tests\.sh|verify-module\.sh|pytest)$"))
FULL_TEST_SCRIPTS = ("run-all.sh", "run-tests.sh")
WAITY_RE = re.compile(r"\bsleep\s+\d|gh\s+(run|pr)\s+(watch|checks)|--watch\b|\buntil\b")
SCRIPT_RE = re.compile(r"(?:^|[\s/;&|(])([A-Za-z0-9_.-]+\.(?:sh|py|js))\b")
# Context window per model id (first match wins), read from the session log's model id. Only 200k and 1M exist.
WINDOWS = [(r"\[1m\]|-1m\b", 1_000_000), (r"^claude-", 200_000)]   # regexes on the model id
KNOWN_WINDOWS = (200_000, 1_000_000)   # when an observed context exceeds the assumed window, use the next of these (never an invented size)
def window_for(model, observed=0):
    """Context window for one model id, or None when the model is not in WINDOWS. A context seen above 200k proves the
    larger window is in use, so the result steps up to the next size in KNOWN_WINDOWS."""
    base = next((w_ for g, w_ in WINDOWS if re.search(g, model or "")), None)
    if base is None: return None
    if observed <= base: return base
    return next((k for k in KNOWN_WINDOWS if k >= observed), None)
def ctx_pct(n, window):
    """Share of the window in percent, never above 100. Nothing when the window is unknown."""
    return min(100.0, 100.0 * n / window) if window else None
def ctx_pct_txt(n, window): return "%.0f%%" % ctx_pct(n, window) if window else "n/a"
def context_window(msgs, compacts=(), flag_1m=False):
    """(window, note) for the main thread, read from the log. 1M only when the log says so: a model id with [1m] or a
    context-1m beta/flag (flag_1m). Otherwise 200k. A context above 200k without a 1M marker is NOT proof of 1M: when
    automatic compactions fired, the window is capped at the highest compaction point (labelled inferred); with no compaction
    it steps to the next known size (labelled inferred). (None, note) when the model is not in the table."""
    if not msgs: return None, "no requests"
    model = collections.Counter(m["model"] for m in msgs).most_common(1)[0][0]
    obs = max(m["in"] + m["cr"] + m["cw"] for m in msgs)
    base = window_for(model)
    if base is None: return None, "model %s is not in the WINDOWS table" % model
    if flag_1m and base < 1_000_000: return 1_000_000, "1M read from the log's context flag"
    if base >= 1_000_000: return base, "1M read from the model id"
    pres = [c["pre"] for c in compacts if c.get("pre") and c.get("trig", "auto") == "auto"]
    if obs <= base: return base, ""
    if pres: return max(pres), "inferred: no 1M marker in the log, so the window is capped at the compaction point (%s)" % fmt_tok(max(pres))
    nxt = window_for(model, obs)
    if nxt is None: return None, "a context of %s exceeds every known window" % fmt_tok(obs)
    return nxt, "inferred: the log shows %s and no 1M marker or compaction" % fmt_tok(obs)
TEST_MOMENTS = [("Every change", "Gate check plus only the tests that touch the change"),
                ("Module done", "Module journeys, plus the per-flow unit tests chosen at CAC-5 (listed in the module brief)"),
                ("Build complete", "Everything, once"),
                ("Before every later deploy", "Everything"),
                ("User asks", "Everything")]

# ----------------------------------------------------------------- helpers
def esc(s): return html.escape(str(s), quote=True)
def epoch(ts):
    try:
        t = calendar.timegm(datetime.datetime.strptime(ts[:19], "%Y-%m-%dT%H:%M:%S").timetuple())
        m = re.match(r"\.(\d+)", ts[19:])
        return t + (float("0." + m.group(1)) if m else 0.0)
    except Exception: return None
def fmt_tok(n):
    n = float(n)
    if n >= 1e6: return "%.2fM" % (n / 1e6)
    if n >= 1e3: return "%.1fk" % (n / 1e3)
    return "%d" % n
def fmt_dur(s):
    s = int(round(s)); h, m = divmod(s // 60, 60)
    return "%dh %02dm" % (h, m) if h else "%dm" % m if m else "%ds" % s
TICK_FMT = ["%H:%M"]
def local_hm(t): return datetime.datetime.fromtimestamp(t).strftime(TICK_FMT[0])
def pct(a, b): return 100.0 * a / b if b else 0.0
def read(p):
    try: return open(p, encoding="utf-8", errors="replace").read()
    except Exception: return ""

# ----------------------------------------------------------------- project
def load_project(proj):
    md = read(os.path.join(proj, "PROJECT.md"))
    try: mt = os.path.getmtime(os.path.join(proj, "PROJECT.md"))
    except OSError: mt = None
    info = {"dir": proj, "name": os.path.basename(proj.rstrip("/")), "current_line": None, "current": None, "passed": [], "decisions": [], "signoff": {}, "md_mtime": None,
            "entry_mode": None, "has_md": bool(md)}
    m = re.search(r"^## Current stage\s*\n+\*\*(.+?)\*\*(.*)$", md, re.M)
    if m:
        info["current_line"] = (m.group(1) + m.group(2)).strip()
        s = re.match(r"Stage\s+(\w)", m.group(1)); info["current"] = s.group(1) if s else None
        g = re.search(r"gates passed:\s*([^()\n]+)", m.group(2))
        if g: info["passed"] = [x.strip() for x in re.split(r"[\u00b7|;]", g.group(1))[0].split(",") if x.strip() in STAGES]   # "P, 0, 1, 2, 3, 4 · manual: 5": only the part before the dot is the passed list
    sec = re.search(r"^## Decisions\s*\n(.*?)(?=^## )", md, re.M | re.S)
    if sec:
        for line in sec.group(1).splitlines():
            c = [x.strip() for x in line.strip().strip("|").split("|")]
            if len(c) >= 3 and c[0] in STAGES and c[0] != "Stage":
                st = re.match(r"[A-Za-z]+", c[2]); info["decisions"].append((c[0], c[1], st.group(0).upper() if st else "OTHER"))
                if re.search(r"sign-?off", c[1], re.I) and st and st.group(0).upper() in ("CONFIRMED", "ASSUMED"):   # a stage sign-off row is the evidence the stage passed, and when
                    t = decision_time(" ".join(c[2:]) or c[1]) or decision_time(c[1])
                    sm = re.search(r"Stage\s*(\w)\b", c[1]); sg = c[0] if c[0] in STAGES else (sm.group(1) if sm else None)
                    if sg in STAGES and (sg not in info["signoff"] or (t and t < info["signoff"][sg][0])): info["signoff"][sg] = (t, c[1][:80], bool(re.search(r"20\d\d-\d\d-\d\d[ T]\d\d:\d\d", " ".join(c[2:]) + " " + c[1])))
    info["changes"] = []   # PROJECT.md ## Change log rows (skills/change-intake.md), shown on the Changes tab
    sec = re.search(r"^## Change log\s*\n(.*?)(?=^## |\Z)", md, re.M | re.S)
    if sec:
        for line in sec.group(1).splitlines():
            c = [x.strip().replace("\\|", "|") for x in re.split(r"(?<!\\)\|", line.strip().strip("|"))]
            if len(c) >= 8 and re.match(r"CR-\d+$", c[0]):
                st = re.match(r"[A-Za-z]+", c[7]); info["changes"].append({"cr": c[0], "date": c[1], "ask": c[3], "cls": c[4], "size": c[5],
                    "status": st.group(0).lower() if st else "unknown", "status_txt": c[7], "closed": c[8] if len(c) > 8 else ""})
    m = re.search(r"Entry mode:\s*\**\s*(\w[\w-]*)", md)
    em = (m.group(1).lower() if m else "migration")
    info["entry_mode"] = "requirements" if em.startswith("requirements") else "existing-app-change" if em.startswith("existing") else em
    info["waived"] = set(re.findall(r"Waived artifact\s+([\w-]+)\s*:", md))
    m = re.search(r"^[\s>*_-]*Progress report\s*:\s*\**\s*(off|ask|auto)\b", md, re.M | re.I)
    info["setting"] = m.group(1).lower() if m else "ask"
    info["md_mtime"] = mt
    return info

CR_STATE = {"open": ("waiting", "open"), "refined": ("waiting", "refined"), "agreed": ("waiting", "agreed"), "applied": ("built", "applied"),
            "proven": ("proven", "proven"), "rejected": ("closed", "rejected")}

def render_changes(w, chg, bp):
    """Changes tab: the PROJECT.md Change log as a backlog, with the plan rows that carry each CR tag."""
    w("<section class=tab id=tab-changes><h2 id=changes>Changes: requests logged after the plan</h2><div class=sub>From the PROJECT.md Change log (skills/change-intake.md). "
      "Open, refined and agreed rows are waiting; applied rows are built; proven rows have evidence. Plan rows are the build-plan.md rows whose text names the CR.</div>")
    if not chg:
        w("<div class=card>No change requests logged. A change made with no row is invisible here, so log every ask first.</div></section>"); return
    tagged = collections.defaultdict(lambda: [0, 0])
    for p in (bp or {}).get("phases", []):
        for x in p.get("steps", []):
            for cr in set(re.findall(r"CR-\d+", x.get("step", ""))):
                tagged[cr][1] += 1; tagged[cr][0] += x.get("cls") == "built"
    groups = collections.Counter(CR_STATE.get(c["status"], ("waiting", ""))[0] for c in chg)
    col = {"waiting": "var(--warn)", "built": "var(--accent)", "proven": "var(--ok)", "closed": "var(--idle)"}
    w("<div class=card><div class=hd><b>%d change request(s): %d waiting, %d built, %d proven%s</b></div>" % (len(chg), groups["waiting"], groups["built"], groups["proven"], (", %d rejected" % groups["closed"]) if groups["closed"] else ""))
    w("<div class=stack>" + "".join("<i title='%s %d' style='width:%.1f%%;background:%s'></i>" % (k, groups[k], pct(groups[k], len(chg)), col[k]) for k in col if groups[k]) + "</div>")
    w("<div class=legend>" + "".join("<span><b style='background:%s'></b>%s %d</span>" % (col[k], k, groups[k]) for k in col if groups[k]) + "</div></div>")
    w("<div class='card' style='margin-top:10px'><div class=tw><table class=crs><tr><th>CR</th><th>Ask</th><th>Class</th><th>Size</th><th>Status</th><th class=n>Plan rows built</th><th>Closed by</th></tr>")
    for c in chg:
        g, _ = CR_STATE.get(c["status"], ("waiting", c["status"])); t = tagged.get(c["cr"])
        ask = c["ask"].strip('"'); pm = re.search(r"\(part:\s*([^)]*)\)\s*$", ask)   # one sentence split over several CRs: lead with the part
        if pm: ask = "Part: %s. %s" % (pm.group(1).strip(), ask[:pm.start()].strip().strip('"'))
        w("<tr><td><b>%s</b><div class=sub>%s</div></td><td title='%s'>%s</td><td>%s</td><td>%s</td><td><span class='crst cr-%s' title='%s'>%s</span></td><td class=n>%s</td><td>%s</td></tr>" % (
            esc(c["cr"]), esc(c["date"]), esc(ask), esc(ask[:140] + ("..." if len(ask) > 140 else "")), esc(c["cls"]), esc(c["size"]), g, esc(c["status_txt"]), esc(c["status"]),
            ("%d of %d" % (t[0], t[1])) if t else "<span class=sub>none tagged</span>", esc(c["closed"][:60]) or "<span class=sub>none yet</span>"))
    w("</table></div></div></section>")

def load_bugs(proj, tk):
    """docs/bugs.jsonl (bin/file-bugs.sh) for the Bugs tab. The rows are shown as logged; the file buttons come only from
    file-bugs.py --json, which redacts each bug and refuses without a deny list, so this page never builds a public URL
    itself and never posts anything. The --json run makes no network call."""
    path = os.path.join(proj, "docs", "bugs.jsonl"); out = {"rows": [], "links": {}, "note": "", "path": path, "proj": proj, "cmd": ""}
    for line in read(path).splitlines():
        try: d = json.loads(line)
        except ValueError: continue
        if isinstance(d, dict) and d.get("id"): out["rows"].append(d)
    if not any(r.get("status", "open") == "open" for r in out["rows"]): return out
    dirs = [tk, os.environ.get("MXTK_TOOLKIT_DIR", "")]   # file-bugs.py ships in the toolkit only, never in a project's bin/
    for f in (os.path.join(proj, ".claude", "toolkit.env"), os.path.join(os.path.expanduser("~"), ".mxcli-toolkit.env")):
        m = re.search(r"^\s*(?:export\s+)?(?:MXTK_TOOLKIT_DIR|TOOLKIT_DIR|MXCLI_TOOLKIT)\s*=\s*[\"']?([^\"'\n]+)", read(f), re.M)
        if m: dirs.append(os.path.expanduser(m.group(1).strip()))
    fb = next((x for x in (os.path.join(d, "bin", "lib", "file-bugs.py") for d in dirs if d) if os.path.isfile(x)), "")
    if not fb:
        out["note"] = "File buttons need the toolkit's bin/lib/file-bugs.py. Point to the toolkit clone with MXTK_TOOLKIT_DIR=<path> in ~/.mxcli-toolkit.env or pass --toolkit."; return out
    out["cmd"] = os.path.join(os.path.dirname(os.path.dirname(fb)), "file-bugs.sh")
    try:
        import subprocess
        p = subprocess.run([sys.executable, "-I", fb, "--project", proj, "--json"], capture_output=True, text=True, timeout=30)
        if p.returncode == 0:
            for it in json.loads(p.stdout or "[]"): out["links"][it.get("id")] = it
        else: out["note"] = (p.stderr or p.stdout).strip().replace("file-bugs: ", "")[:400]
    except Exception as e:
        out["note"] = "file-bugs.py --json did not run (%s)." % type(e).__name__
    return out

def render_bugs(w, bugs):
    """Bugs tab: the project's tool bugs (mxcli or toolkit). An open bug gets buttons that copy its file-bugs.sh
    command (one per repo); the person runs it, which files through gh after a y/N."""
    rows = bugs["rows"]
    w("<div id=bugs-part><h2 id=bugs>Encountered bugs or limitations</h2><div class=sub>Problems in mxcli or the toolkit hit in this project, from docs/bugs.jsonl. Add one with "
      "<code>bin/file-bugs.sh --add --target mxcli|toolkit --title T --repro R --expected E --actual A</code>. A button copies the filing command. Run it in your "
      "terminal (or in Claude Code after <code>!</code>): it removes project names, paths and secrets, shows the text and likely duplicates, asks y/N, "
      "then files with <code>gh issue create</code>. Nothing is posted from this page. No GitHub CLI or account (for example on "
      "Team Server only)? Nothing breaks: the bug stays here, open, with its workaround, and <code>--links</code> prints a pre-filled link to "
      "hand to someone who has an account.</div>")
    if not rows:
        w("<div class=card>No bugs logged in this project. When a session hits or works around a bug in mxcli or the toolkit, log it first, then file it from here.</div></div>"); return
    n = collections.Counter(r.get("status", "open") for r in rows)
    w("<div class=card><div class=hd><b>%d bug(s): %d open, %d filed, %d fixed</b></div>" % (len(rows), n["open"], n["filed"], n["fixed"]))
    if bugs["note"]: w("<p class='note stale'>No file buttons: %s</p>" % esc(bugs["note"]))
    w("</div><div class='card' style='margin-top:10px'><div class=tw><table class=crs><tr><th>Bug</th><th>For</th><th>Title</th><th>Status</th><th>Action</th></tr>")
    for r in rows:
        tgt = r.get("target", ""); label = BUG_REPO.get(tgt, (tgt or "unknown", ""))[0]; st = r.get("status", "open"); it = bugs["links"].get(r.get("id"), {})
        if st == "filed" and r.get("issue_url"): act = " ".join("<a href='%s'>%s</a>" % (esc(u), esc(re.sub(r"^https://github\.com/", "", u))) for u in [r["issue_url"]] + list((r.get("also") or {}).values()))
        elif st == "fixed": act = "<span class=sub>fixed</span>"
        elif it.get("refused"): act = "<span class=sub title='%s'>held back: redaction found something that looks private; fix the row</span>" % esc(it.get("note", ""))
        elif it.get("title") and bugs.get("cmd"):   # filing runs gh in the person's terminal: redact, duplicate search, y/N, gh issue create
            home = os.path.expanduser("~"); q = lambda x: "~" + x[len(home):] if x.startswith(home + os.sep) else x
            base = "%s --project %s --file %s" % (q(bugs["cmd"]), q(bugs["proj"]), r.get("id"))
            # a finding that is really both is two submissions, one per repo (skills/upstream-feedback.md section 1)
            cmds = [(base, "File to " + label, "")] + [(base + " --to " + k, "also to " + BUG_REPO[k][0], " alt") for k in BUG_REPO if k != tgt and tgt in BUG_REPO]
            act = "".join("<button type=button class='filebtn%s' data-cmd='%s' title='Copies the command; paste it in your terminal, or in Claude Code after !'>%s</button> " % (c_, esc(cmd), esc(lab_)) for cmd, lab_, c_ in cmds)
            act += "<div class=sub><code>%s</code></div>" % esc(base)
        else: act = "<span class=sub>no button (see note above)</span>"
        w("<tr><td><b>%s</b><div class=sub>%s</div></td><td>%s</td><td>%s</td><td><span class='crst cr-%s'>%s</span></td><td>%s</td></tr>" % (
            esc(r.get("id", "")), esc(r.get("date", "")), esc(label), esc(r.get("title", "")), {"open": "waiting", "filed": "built", "fixed": "proven"}.get(st, "closed"), esc(st), act))
    w("</table></div></div></div>")

def decision_time(txt):
    """Epoch of the first date (and time when given) in a decision row cell; local time; None without a date."""
    m = re.search(r"(20\d\d)-(\d\d)-(\d\d)(?:[ T](\d\d):(\d\d))?", txt or "")
    if not m: return None
    try: return datetime.datetime(int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4) or 0), int(m.group(5) or 0)).timestamp()
    except ValueError: return None

def reconcile_gates(info, gate):
    """One source of truth for which stages passed. PROJECT.md (the stage line and the sign-off rows in its decision
    register) wins over the generated gate-check page when it is the newer file; when the page is the newer file its
    PASS rows are added. The page's own age is recorded so a card can say it is stale."""
    md_t, g_t = info.get("md_mtime"), gate.get("mtime")
    info["passed_md"] = list(info["passed"]); info["gate_stale_s"] = 0
    if not info["has_md"]: return
    gp = [s for s in STAGES if gate["rows"].get(s, {}).get("status") == "PASS"]
    ps = set(info["passed"])
    if info["current"] or ps:
        ps |= {s for s in info["signoff"] if s in STAGES and (info["current"] is None or STAGES.index(s) < STAGES.index(info["current"]) or s in info["passed"])}
    if g_t and md_t and g_t > md_t: ps |= set(gp)
    if g_t and md_t and g_t < md_t - 60: info["gate_stale_s"] = md_t - g_t
    info["passed"] = [s for s in STAGES if s in ps]

def load_gate_index(proj):
    p = os.path.join(proj, "index.html"); out = {"rows": {}, "mtime": None, "extra": {}}
    h = read(p)
    if not h: return out
    out["mtime"] = os.path.getmtime(p)
    for row in re.findall(r"<tr>(.*?)</tr>", h, re.S):
        cells = [re.sub(r"<[^>]+>", "", c).strip() for c in re.findall(r"<td[^>]*>(.*?)</td>", row, re.S)]
        if len(cells) >= 4:
            cells = [html.unescape(c) for c in cells]
            if cells[0] in STAGES: out["rows"][cells[0]] = {"title": cells[1], "status": cells[2], "detail": cells[3]}
            elif "Open questions" in cells[1]:
                m = re.search(r"RAISED=(\d+)", cells[3]); out["extra"]["raised"] = int(m.group(1)) if m else None
    return out

WAIVED = set()
def load_manifest(toolkit, mode):
    rows = []
    txt = read(os.path.join(toolkit, "bin", "lib", "artifact-manifest.tsv")) if toolkit else ""
    for line in txt.splitlines():
        if not line.strip() or line.startswith("#"): continue
        c = line.split("\t")
        if len(c) >= 7 and c[1] in STAGES and mode in c[5].split(",") and c[0] not in WAIVED:
            rows.append({"id": c[0], "stage": c[1], "paths": c[2].split("|"), "absence": c[6].strip()})
    return rows

def resolve(proj, pattern):
    pattern = pattern.replace("${JOURNEY_DIR}", "journeys")
    hits = sorted(glob.glob(os.path.join(proj, pattern)))
    if not hits:
        hits = sorted(glob.glob(os.path.join(proj, "analysis", "*", pattern)))
    return [h for h in hits if os.path.isfile(h)]

SELF_OUT = None   # the page being written: it counts as present, or the first render and the next differ
def collect_artifacts(proj, manifest):
    stages = {s: {"owed": [], "files": collections.OrderedDict()} for s in STAGES}
    for r in manifest:
        found = []
        for pat in r["paths"]: found += resolve(proj, pat)
        if SELF_OUT and not found and any(pat.endswith(REPORT_FILE) for pat in r["paths"]): found = [SELF_OUT]   # counts as present, never listed (see below)
        for f in found:
            if os.path.basename(f) == REPORT_FILE or os.path.relpath(f, proj).startswith(".."): continue   # the report never lists itself, and nothing outside the project folder
            stages[r["stage"]]["files"].setdefault(f, r["id"])
        stages[r["stage"]]["owed"].append({"id": r["id"], "found": len(found), "absence": r["absence"]})
    for s, pats in EXTRA_ARTIFACTS.items():
        for pat in pats:
            for f in resolve(proj, pat): stages[s]["files"].setdefault(f, "extra")
    return stages

def link_kind(path):
    e = os.path.splitext(path)[1].lower()
    return "html" if e == ".html" else "md" if e == ".md" else "data"

def rel_href(f, outdir, pm=os.path):
    """A relative, percent-encoded href from the page's folder to f. pm is the path module (ntpath in tests), so a
    Windows path gives forward slashes too."""
    return urllib.parse.quote(pm.relpath(f, outdir).replace(pm.sep, "/"))

def collect_pages(proj, skip=()):
    """{folder relative to proj ("." for the root): [(path, mtime)]}, every page found, sorted. Walks only PAGE_DIRS,
    never enters PAGE_SKIP_DIRS or dot folders, does not follow links, skips a top-level folder that is a symlink or
    resolves outside the project, and leaves out the paths in skip."""
    skipk = {os.path.normcase(os.path.abspath(s)) for s in skip if s}
    real_proj = os.path.normcase(os.path.realpath(proj))
    found = []
    def take(path):
        if not path.lower().endswith((".html", ".htm")) or os.path.basename(path) == REPORT_FILE: return
        if os.path.normcase(os.path.abspath(path)) in skipk or not os.path.isfile(path): return
        try: found.append((path, os.path.getmtime(path)))
        except OSError: pass
    for top in PAGE_DIRS:
        base = os.path.join(proj, top) if top else proj
        if not os.path.isdir(base): continue
        if not top:
            for n in sorted(os.listdir(base)): take(os.path.join(base, n))
            continue
        rb = os.path.normcase(os.path.realpath(base))
        if top.lower() in PAGE_SKIP_DIRS or os.path.islink(base) or not rb.startswith(real_proj.rstrip(os.sep) + os.sep): continue
        for d, ds, fs in os.walk(base):
            depth = os.path.relpath(d, base).count(os.sep) + (0 if d == base else 1)
            ds[:] = sorted(x for x in ds if not x.startswith(".") and x.lower() not in PAGE_SKIP_DIRS and depth < PAGE_MAX_DEPTH)
            for n in sorted(fs): take(os.path.join(d, n))
    nat = lambda t: [int(x) if x.isdigit() else x for x in re.split(r"(\d+)", t.lower())]   # w2 before w10
    def key(x):
        r = os.path.relpath(x[0], proj).replace(os.sep, "/"); d, _, name = r.rpartition("/")
        return (d != "", [nat(c) for c in d.split("/")] if d else [], nat(name))   # root first; folders part by part, so wireframes/x sits before wireframes-v1/
    found.sort(key=key)
    groups = collections.OrderedDict()
    for f, mt in found:
        groups.setdefault(os.path.relpath(os.path.dirname(f), proj).replace(os.sep, "/"), []).append((f, mt))
    return groups

def render_pages(proj, outdir, skip=()):
    """The Project pages section: one row per folder, indented under the nearest listed parent folder, each page a
    relative link with its modified date. Dates are days, so the section is unchanged on the same day unless a listed
    page changed (added, removed or renamed; an edit only moves its date, on a later day), and a --refresh leaves the page alone."""
    groups = collect_pages(proj, skip)
    n = sum(len(v) for v in groups.values())
    out = ["<h2 id=pages>Project pages: HTML pages found in the project's output folders</h2><div class=sub>Found on disk under %s; "
           "each link opens the page. Dates are when the file last changed. Folders like node_modules, theme and deployment are "
           "not scanned (PAGE_DIRS and PAGE_SKIP_DIRS in the script).</div>" % esc(", ".join((d + "/") if d else "the project root" for d in PAGE_DIRS))]
    if not groups:
        out.append("<div class=card>No HTML pages found yet.</div>"); return "".join(out)
    out.append("<div class='card pages'><div class=sub>%d page%s in %d folder%s</div><div class=tree>" % (n, "" if n == 1 else "s", len(groups), "" if len(groups) == 1 else "s"))
    depth = {}
    day = lambda t: datetime.datetime.fromtimestamp(t).strftime("%Y-%m-%d")
    for gi, (g, files) in enumerate(groups.items()):
        par = max((p for p in depth if p != "." and g.startswith(p + "/")), key=len, default=None)
        depth[g] = depth[par] + 1 if par else 0
        label = "project root" if g == "." else (g[len(par) + 1:] if par else g) + "/"
        items = "".join("<li><a href='%s'>%s</a> <span class=mut>%s</span></li>" % (esc(rel_href(f, outdir)), esc(os.path.basename(f)), day(mt)) for f, mt in files[:PAGE_FOLDER_MAX])
        if len(files) > PAGE_FOLDER_MAX: items += "<li class=mut>+%d more not listed (PAGE_FOLDER_MAX)</li>" % (len(files) - PAGE_FOLDER_MAX)
        if len(files) > PAGE_GROUP_OPEN:
            body = "<details id='pages-%d-%s'><summary>%d pages, newest %s</summary><ul>%s</ul></details>" % (gi, esc(re.sub(r"[^A-Za-z0-9]+", "-", g).strip("-") or "root"), len(files), day(max(mt for _, mt in files)), items)
        else: body = "<ul>%s</ul>" % items
        out.append("<div class=pg style='padding-left:%dpx'><b class=dir title='%s'>%s</b>%s</div>" % (16 * depth[g], esc(g + "/" if g != "." else "./"), esc(label), body))
    out.append("</div></div>")
    return "".join(out)

# ----------------------------------------------------------------- session
def rate_for(model, rates):
    for g, i, cw, cr, o in rates:
        if fnmatch.fnmatch(model or "", g): return (i, cw, cr, o)
    return None
def load_rates(path):
    if not path: return DEFAULT_RATES
    out = []
    for l in read(path).splitlines():
        l = l.split("#")[0].split()
        if len(l) == 5:
            try: out.append((l[0], *map(float, l[1:])))
            except ValueError: pass
    return out or DEFAULT_RATES

def cost_of(u, model, rates):
    r = rate_for(model, rates)
    if not r: return None
    return (u["in"] * r[0] + u["cw"] * r[1] + u["cr"] * r[2] + u["out"] * r[3]) / 1e6

def scan_transcript(path, is_main=False, clip=None):
    """Returns messages (dedup by message.id, max of each counter), event times, compactions, prompts, tool events."""
    flag_1m = False; msgs = {}; times = []; compacts = []; prompts = 0; tools = []; gate = []; calls = {}
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            try: o = json.loads(line)
            except Exception: continue
            t = o.get("type"); ts = epoch(o.get("timestamp", "")) if o.get("timestamp") else None
            if clip and ts and not any(a_ <= ts <= b_ for a_, b_ in clip): continue
            if ts and t in ("user", "assistant"): times.append(ts)
            if not flag_1m:
                bt = (o.get("params") or {}).get("betas") if isinstance(o.get("params"), dict) else None
                if (isinstance(bt, list) and any("context-1m" in str(x) for x in bt)) or re.search(r"\[1m\]", str(o.get("requestedModel") or "")): flag_1m = True
            if "compactMetadata" in o:
                cm = o["compactMetadata"]; compacts.append({"t": ts, "pre": cm.get("preTokens"), "post": cm.get("postTokens"), "trig": cm.get("trigger") or "auto"})
            if t == "user" and is_main and not o.get("isMeta") and not o.get("isCompactSummary"):
                c = o.get("message", {}).get("content")
                if isinstance(c, str) and not c.lstrip().startswith("<"): prompts += 1
                elif isinstance(c, list) and any(b.get("type") == "text" for b in c) and not any(b.get("type") == "tool_result" for b in c): prompts += 1
            if t == "user" and isinstance(o.get("message", {}).get("content"), list):
                for b in o["message"]["content"]:
                    if isinstance(b, dict) and b.get("type") == "tool_result" and b.get("tool_use_id") in calls:
                        c_ = calls[b["tool_use_id"]]; txt = b.get("content")
                        if isinstance(txt, list): txt = "".join(x.get("text", "") for x in txt if isinstance(x, dict))
                        txt = txt if isinstance(txt, str) else ""
                        head_ = txt[:300]; c_["t1"] = ts; c_["rchars"] = len(txt)
                        c_["err"] = bool(b.get("is_error")) or bool(re.match(r"\s*Exit code:?\s*[1-9]", head_))
                        c_["timeout"] = bool(re.search(r"(?i)timed out", head_)) and c_["name"] != "Read"
                        c_["killed"] = bool(re.search(r"\[killed\]|was killed|Terminated", head_)) and c_["name"] != "Read"
            if t != "assistant": continue
            m = o.get("message", {}); u = m.get("usage") or {}; mid = m.get("id") or o.get("uuid")
            if m.get("model") in (None, "<synthetic>"): continue
            if "[1m]" in str(m.get("model")): flag_1m = True
            cur = msgs.setdefault(mid, {"t": ts, "model": m["model"], "in": 0, "out": 0, "cr": 0, "cw": 0})
            for k, uk in (("in", "input_tokens"), ("out", "output_tokens"), ("cr", "cache_read_input_tokens"), ("cw", "cache_creation_input_tokens")):
                cur[k] = max(cur[k], u.get(uk) or 0)
            for b in m.get("content", []):
                if b.get("type") == "tool_use" and b.get("id") and ts:
                    i = b.get("input") or {}; n = b.get("name"); cmd = i.get("command") or "" if n == "Bash" else ""
                    sm = SCRIPT_RE.search(cmd) if cmd else None
                    word = re.match(r"\s*(?:\w+=\S+\s+)*([A-Za-z0-9_.-]{1,30})", cmd.split("&&")[-1] if "&&" in cmd else cmd) if cmd and not sm else None
                    arg = re.search(r"gate-check\.sh\s+\S+\s+(P|[0-6]|build-ready)\b", cmd) if cmd else None
                    f_ = i.get("file_path") or i.get("notebook_path") or ""
                    calls[b["id"]] = {"t0": ts, "t1": None, "name": n, "script": (sm.group(1) if sm else word.group(1) if word else ""),
                                      "variant": arg.group(1) if arg else "", "file": f_ if n in ("Write", "Edit", "MultiEdit", "NotebookEdit") else "",
                                      "bg": bool(i.get("run_in_background")), "waity": bool(WAITY_RE.search(cmd)) or n == "Monitor",
                                      "killed": n in ("TaskStop", "KillShell", "KillBash"), "timeout": False, "err": False, "rchars": 0, "who": "main" if is_main else "agent"}
            if is_main:
                for b in m.get("content", []):
                    if b.get("type") == "tool_use":
                        i = b.get("input", {}); n = b.get("name")
                        ev = {"t": ts, "name": n}
                        if n == "Bash": ev["cmd"] = (i.get("command") or "")[:400]
                        elif n in ("Write", "Edit"): ev["file"] = i.get("file_path", "")
                        elif n in ("Agent", "Task"): ev["desc"] = i.get("description", "")
                        elif n == "Skill": ev["skill"] = i.get("skill", "")
                        tools.append(ev)
    return {"flag_1m": flag_1m, "msgs": list(msgs.values()), "times": times, "compacts": compacts, "prompts": prompts, "tools": tools, "calls": list(calls.values())}

IS_WIN = os.name == "nt"
_MSYS_RE = re.compile(r"^/([A-Za-z])(?:/(.*))?$")
_DRIVE_RE = re.compile(r"^[A-Za-z]:[\\/]")

def fix_msys(p, win=None):
    """Git Bash hands native Windows Python an MSYS path (/c/work/proj), which no Windows API can open.
    On Windows only, turn it into C:/work/proj; every other path, and every other platform, is unchanged."""
    win = IS_WIN if win is None else win
    m = _MSYS_RE.match(p) if win else None
    return "%s:/%s" % (m.group(1).upper(), m.group(2) or "") if m else p

def real_path(p):
    """realpath, except that a Windows drive path is taken as it is when it is not this machine's own (tests)."""
    if _DRIVE_RE.match(p) and os.name != "nt": return p
    return os.path.realpath(p)

def path_key(p, win=None):
    """A comparable form: forward slashes, no trailing slash; on Windows also lower case (the file system ignores case)."""
    win = IS_WIN if win is None else win
    k = p.replace("\\", "/")
    if len(k) > 1: k = k.rstrip("/") or "/"
    return k.lower() if win else k

def unescape_json_str(s):
    """The inside of a JSON string literal as the string it denotes (C:\\\\work\\\\x -> C:\\work\\x); unchanged when not valid."""
    try: return json.loads('"' + s + '"')
    except Exception: return s

def under(c, roots, win=None):
    """Is path c at or under one of the roots, whatever the slash style and (on Windows) the case."""
    ck = path_key(c, win)
    for r in roots:
        rk = path_key(r, win)
        if ck == rk or ck.startswith(rk.rstrip("/") + "/"): return True
    return False

def root_forms(proj, win=None):
    """Every spelling of the project folder a log may carry: realpath and abspath, with / and \\ separators on Windows."""
    win = IS_WIN if win is None else win
    base = {real_path(proj), proj if _DRIVE_RE.match(proj) else os.path.abspath(proj)}
    out = set(base)
    if win:
        for b in base:
            out.add(b.replace("\\", "/")); out.add(b.replace("/", "\\"))
            m = _DRIVE_RE.match(b)
            if m:  # Git Bash spelling (C:/work/proj -> /c/work/proj), as in `cd /c/work/proj && ...`
                out.add("/" + b[0].lower() + b[2:].replace("\\", "/"))
    return sorted(out, key=len, reverse=True)

def needle_for(roots, win=None):
    """Byte pattern over raw log lines. A backslash is doubled in JSON text, so on Windows each root is also matched in that form."""
    win = IS_WIN if win is None else win
    pats = set()
    for n in roots:
        pats.add(n)
        if win: pats.add(n.replace("\\", "\\\\"))
    return re.compile(b"|".join(re.escape(n.encode()) for n in sorted(pats, key=len, reverse=True)), re.I if win else 0)

def touches(name, inp, cwd, roots, win=None):
    """Does this tool call operate on the project: a path under the root in its input, a Bash command that cds into the
    root or names a path under it, or a working directory at or under it. Words in prose never count."""
    win = IS_WIN if win is None else win
    if cwd and under(cwd, roots, win): return True
    for k in ("file_path", "notebook_path", "path"):
        v = inp.get(k)
        if isinstance(v, str) and under(v, roots, win): return True
    if name == "Bash":
        c = inp.get("command") or ""
        for r in roots:
            if re.search(r"(?<![A-Za-z0-9_.\-])" + re.escape(r) + r"(?![A-Za-z0-9_.\-])", c, re.I if win else 0): return True
    return False

TS_RE = re.compile(rb'"timestamp"\s*:\s*"([^"]+)"')
EARLY_CALLS = 200     # stop reading a file that has made this many tool calls and none on the project

def dbg(msg):
    if os.environ.get("PROGRESS_REPORT_DEBUG"): sys.stderr.write("progress-report: %s\n" % msg)

def tool_share(path, roots, needle):
    """Per-session test for a log started in another folder, streamed line by line. Returns None for a session that runs
    progress-report.py itself, else {touch, total, share, spans}: touching calls, all tool calls between the first and last
    touching call, their ratio, and the spans between touching calls with gaps over SPAN_GAP_S cut. Gives up early on a
    file that is clearly not about the project. Lines that do not name the project are only counted, never parsed."""
    dbg("opened %s" % path)
    calls = []; any_touch = False   # (t, touches)
    try: fh = open(path, "rb")
    except OSError: return {"touch": 0, "total": 0, "share": 0.0, "spans": []}
    with fh:
        for ln in fh:
            n = ln.count(b'"type":"tool_use"')
            if not n: continue
            m = TS_RE.search(ln); ts = epoch(m.group(1).decode("ascii", "replace")) if m else None
            if not ts: continue
            if b"progress-report.py" in ln or needle.search(ln):
                try: o = json.loads(ln)
                except Exception: o = None
                if o is not None and o.get("type") == "assistant":
                    for b in (o.get("message") or {}).get("content") or []:
                        if isinstance(b, dict) and b.get("type") == "tool_use":
                            i = b.get("input") or {}
                            if b.get("name") == "Bash" and "progress-report.py" in (i.get("command") or ""): return None
                            x = touches(b.get("name"), i, o.get("cwd"), roots); any_touch = any_touch or x
                            calls.append((ts, x))
                    continue
            calls.extend((ts, False) for _ in range(n))
            if not any_touch and len(calls) >= EARLY_CALLS: return {"touch": 0, "total": 0, "share": 0.0, "spans": []}
    t_ = sorted(t for t, x in calls if x)
    if not t_: return {"touch": 0, "total": 0, "share": 0.0, "spans": []}
    inwin = [1 for t, x in calls if t_[0] <= t <= t_[-1]]
    spans = []; a_ = b_ = t_[0]
    for t in t_[1:]:
        if t - b_ > SPAN_GAP_S: spans.append((a_, b_)); a_ = t
        b_ = t
    spans.append((a_, b_))
    return {"touch": len(t_), "total": len(inwin), "share": len(t_) / max(1, len(inwin)), "spans": spans}

def load_cache(path):
    """Discovery cache: one line per examined session file (verdict, mtime, size, path, details of a used one)."""
    c = {"scanned": 0.0, "entries": {}, "root": None, "rules": None}
    try: lines = open(path, encoding="utf-8").read().splitlines()
    except OSError: return None
    for ln in lines:
        if ln.startswith("# scanned="):
            for part in ln[2:].split("\t"):
                k, _, v = part.partition("=")
                if k == "scanned":
                    try: c["scanned"] = float(v)
                    except ValueError: pass
                elif k in ("root", "rules"): c[k] = v
            continue
        f = ln.split("\t")
        if len(f) >= 4 and f[0] in ("used", "no"):
            try: c["entries"][f[3]] = {"v": f[0], "m": float(f[1]), "s": int(f[2]), "info": json.loads(f[4]) if len(f) > 4 and f[4] else None}
            except ValueError: continue
    return c

def cache_rules():
    """The attribution rule constants a cached verdict depends on; a cache written under other rules is stale."""
    return "share=%g;calls=%d" % (TOOL_SHARE, TOOL_MIN)

def save_cache(path, scanned, entries, root):
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = path + ".tmp.%d" % os.getpid()
        with open(tmp, "w", encoding="utf-8") as fh:
            fh.write("# scanned=%.0f\troot=%s\trules=%s\tprogress-report session cache: verdict, mtime, size, path, details. Safe to delete.\n" % (scanned, root, cache_rules()))
            for f, e in sorted(entries.items()):
                fh.write("%s\t%.6f\t%d\t%s\t%s\n" % (e["v"], e["m"], e["s"], f, json.dumps(e["info"]) if e.get("info") else ""))
        os.replace(tmp, path)
    except OSError: pass

SWITCH = {}
DISCOVERY = {}
TOOL_MIN = 20; TOOL_SHARE = 0.25; SPAN_GAP_S = 1800
SCAN_DAYS = 30; SCAN_MAX_FILES = int(os.environ.get("PROGRESS_REPORT_SCAN_MAX_FILES") or 300); SCAN_MAX_BYTES = 200_000_000; 
def slug(path):
    """Claude Code's folder name for a launch directory: every non-alphanumeric character becomes a dash."""
    return re.sub(r"[^A-Za-z0-9]", "-", path)

def have_own(out): return set(out)

def find_sessions(proj, logs_dir=None, cache_path=None, win=None):
    """Main-thread session logs that belong to this project on this machine, oldest first.
    Looks in the project's own slug folder, its ancestors' and its descendants'; a session counts when
    at least one record's cwd is at or under the project folder (the folder name alone is not proof)."""
    base = logs_dir or os.path.join(os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(os.path.expanduser("~"), ".claude"), "projects")
    if not os.path.isdir(base): return [], base
    win = IS_WIN if win is None else win
    proj = fix_msys(proj, win)
    me = slug(real_path(proj)); out = []
    mel = me.lower() if win else me
    def own_dir(name):
        n = name.lower() if win else name
        return n == mel or mel.startswith(n + "-") or n.startswith(mel + "-")
    for name in sorted(os.listdir(base)):
        d = os.path.join(base, name)
        if not (os.path.isdir(d) and own_dir(name)): continue
        for f in sorted(glob.glob(os.path.join(d, "*.jsonl"))):
            if session_in_project(f, proj, win): out.append(f)
    # Sessions started elsewhere (another folder's slug): last 30 days, newest first, a capped number of files. A log counts
    # when a record's cwd is the project, or when at least TOOL_SHARE of its tool calls (and TOOL_MIN of them) operate on the
    # project path. Text mentions never count. Listed on the page.
    DISCOVERY.update({"other_dirs": 0, "other_files": 0, "mention": [], "searched": True, "used": [], "skipped_report": 0, "cache": "cold"})
    cutoff = time.time() - SCAN_DAYS * 86400; started = time.time()
    roots = root_forms(proj, win)
    needle = needle_for(roots, win)
    cpath = cache_path or os.path.join(proj, ".claude", "progress-report-sessions.txt")
    cache = load_cache(cpath); entries = {}; cands = []
    root_id = real_path(proj)
    # A cache belongs to one project path and one rule set: a copied or moved project, or a toolkit update that changed the
    # thresholds, reads it as cold (its verdicts are about another folder or another rule).
    if cache and (cache["root"] != root_id or cache["rules"] != cache_rules()): cache = None
    if cache:   # warm: known files are stat-ed; only a changed or a new file is read; only directories touched since the last run are listed
        DISCOVERY["cache"] = "warm"
        for f, e in cache["entries"].items():
            if not f.startswith(base.rstrip(os.sep) + os.sep): continue   # another config folder's entry
            try: st = os.stat(f)
            except OSError: continue
            if st.st_mtime < cutoff: continue
            if abs(st.st_mtime - e["m"]) < 1e-3 and st.st_size == e["s"]: entries[f] = e
            else: cands.append((st.st_mtime, f, st.st_size))
        for name in os.listdir(base):
            d = os.path.join(base, name)
            try: dm = os.stat(d).st_mtime
            except OSError: continue
            if not os.path.isdir(d) or own_dir(name) or dm < cache["scanned"] - 2: continue
            DISCOVERY["other_dirs"] += 1
            for f in glob.glob(os.path.join(d, "*.jsonl")):
                if f in entries or f in {c[1] for c in cands}: continue
                try: st = os.stat(f)
                except OSError: continue
                if st.st_mtime >= cutoff: cands.append((st.st_mtime, f, st.st_size))
    else:       # cold: every other folder's logs of the last SCAN_DAYS days (stat only), newest first, capped
        for name in os.listdir(base):
            d = os.path.join(base, name)
            if not os.path.isdir(d) or own_dir(name): continue
            DISCOVERY["other_dirs"] += 1
            for f in glob.glob(os.path.join(d, "*.jsonl")):
                try: st = os.stat(f)
                except OSError: continue
                if st.st_mtime >= cutoff: cands.append((st.st_mtime, f, st.st_size))
        cands.sort(reverse=True)
        # Files past the cap are recorded as "no" (mtime and size), so a warm run never hands them back as candidates.
        for mt, f, size in cands[SCAN_MAX_FILES:]: entries[f] = {"v": "no", "m": mt, "s": size, "info": None}
        cands = cands[:SCAN_MAX_FILES]
    nread = 0
    for mt, f, size in sorted(cands, reverse=True):
        nread += 1
        if size > SCAN_MAX_BYTES: entries[f] = {"v": "no", "m": mt, "s": size, "info": None}; continue
        r = tool_share(f, roots, needle)
        if r is None: DISCOVERY["skipped_report"] += 1; entries[f] = {"v": "no", "m": mt, "s": size, "info": None}; continue
        if r["touch"] >= TOOL_MIN and r["share"] >= TOOL_SHARE:
            entries[f] = {"v": "used", "m": mt, "s": size, "info": {"share": r["share"], "touch": r["touch"], "total": r["total"], "spans": r["spans"]}}
        else: entries[f] = {"v": "no", "m": mt, "s": size, "info": None}
    # the page's "looked in N folders (M logs)" counts must not depend on cold or warm: count them the same way both times
    DISCOVERY["other_dirs"] = sum(1 for n in os.listdir(base) if os.path.isdir(os.path.join(base, n)) and not own_dir(n))
    DISCOVERY["other_files"] = len(entries)
    for f, e in entries.items():
        if e["v"] != "used" or f in have_own(out): continue
        i = e["info"]; sp = [tuple(x) for x in i["spans"]]
        out.append(f); DISCOVERY["mention"].append(f); DISCOVERY.setdefault("clip", {})[f] = sp
        DISCOVERY["used"].append({"id": os.path.splitext(os.path.basename(f))[0][:8], "t": sp[0][0], "share": i["share"], "touch": i["touch"], "total": i["total"], "span_s": sum(b_ - a_ for a_, b_ in sp)})
    save_cache(cpath, started, entries, root_id)
    dbg("discovery %s, %d file(s) read, %.2f s" % (DISCOVERY["cache"], nread, time.time() - started))
    out.sort(key=lambda f: os.path.getmtime(f))
    return out, base

def explicit_sessions(paths):
    """--session-log inputs: a .jsonl file, or a folder of them (not searched below it). Used as given, no cwd test."""
    out = []
    for p_ in paths:
        p_ = os.path.abspath(os.path.expanduser(p_))
        if os.path.isdir(p_): out += sorted(glob.glob(os.path.join(p_, "*.jsonl")), key=os.path.getmtime)
        elif os.path.isfile(p_): out.append(p_)
    seen = set()
    return [f for f in out if not (f in seen or seen.add(f))]

def session_in_project(path, proj, win=None):
    win = IS_WIN if win is None else win
    roots = root_forms(fix_msys(proj, win), win)
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for i, line in enumerate(f):
                if i > 4000: break
                m = re.search(r'"cwd"\s*:\s*"((?:[^"\\]|\\.)*)"', line)
                if m:
                    if under(unescape_json_str(m.group(1)), roots, win): return True
    except Exception: pass
    return False

def load_sessions(paths):
    mains = []; agents = []; extra_calls = []
    for session in paths:
        clip = DISCOVERY.get("clip", {}).get(session)
        mains.append(scan_transcript(session, True, clip))
        sdir = session[:-6]
        for f in sorted(glob.glob(os.path.join(sdir, "subagents", "**", "agent-*.jsonl"), recursive=True)):
            try: meta = json.load(open(f[:-6] + ".meta.json"))
            except Exception: meta = {}
            d = scan_transcript(f, False, clip)
            if not d["times"]: continue
            extra_calls.extend(d["calls"])
            wf = "workflows" in f.split(os.sep)
            model = (d["msgs"][0]["model"] if d["msgs"] else meta.get("model") or "unknown")
            agents.append({"desc": str(meta.get("description") or meta.get("label") or "sub-agent")[:80], "model": model, "wf": wf,
                           "wf_id": os.path.basename(os.path.dirname(f)) if wf else None, "phase": meta.get("phase"),
                           "t0": min(d["times"]), "t1": max(d["times"]), "times": d["times"], "turns": len(d["msgs"]), "msgs": d["msgs"]})
    main = {"msgs": [], "times": [], "compacts": [], "prompts": 0, "tools": [], "calls": [], "flag_1m": any(m["flag_1m"] for m in mains)}
    for m in mains:
        for k in ("msgs", "times", "compacts", "tools", "calls"): main[k] += m[k]
        main["prompts"] += m["prompts"]
    main["calls"] += extra_calls
    main["msgs"].sort(key=lambda m: m["t"] or 0); main["tools"].sort(key=lambda e: e["t"] or 0); main["times"].sort()
    return main, agents

# ----------------------------------------------------------------- stage windows
GATE_RE = re.compile(r"gate-check\.sh\s+(?:\.\s+)?(?:--closeout\s+\.\s*)?([P0-6])?\b")
GENERIC = set("fix fixes patch domain docs phase scaffold app skeleton model models module journey test tests look add the and for of new data".split())

def run_kind(result, gate=""):
    """ok = the script was applied (also applied-unverified); blocked = it never ran; fail = anything else (rolled back, failed)."""
    r = (result or "").lower()
    if re.search(r"blocked|not-run", r) or (gate or "").lower() == "not-run": return "blocked"
    if "applied" in r and not re.search(r"rolled|fail|error", r): return "ok"
    return "fail"

def ledger_runs(proj):
    """Rows of .claude/loop/metrics-ledger.tsv, the log exec.sh writes itself (ts in UTC), oldest first."""
    ml = read(os.path.join(proj, ".claude", "loop", "metrics-ledger.tsv")).splitlines()
    if len(ml) < 2: return []
    h = ml[0].split("\t"); out = []
    for line in ml[1:]:
        c = line.split("\t"); g = lambda k: c[h.index(k)].strip() if k in h and h.index(k) < len(c) else ""
        t = epoch(g("ts"))
        if not t or not g("script"): continue
        try: el = float(g("elapsed_s"))
        except ValueError: el = None
        try: sc = float(g("score"))
        except ValueError: sc = None
        try: rs = int(float(g("restored") or 0)) > 0
        except ValueError: rs = False
        out.append({"t": t, "script": g("script"), "result": g("result"), "kind": run_kind(g("result"), g("gate")), "elapsed": el, "restored": rs, "score": sc})
    out.sort(key=lambda r: r["t"]); return out

def build_runs(proj):
    """(runs, source name): the metrics ledger when it has rows, else docs/BUILD-LOG.md."""
    r = ledger_runs(proj)
    if r: return r, ".claude/loop/metrics-ledger.tsv"
    bl = [{"t": t, "script": sc, "result": res, "kind": run_kind(res), "elapsed": None, "restored": False, "score": None} for t, sc, res in build_log_rows(proj)]
    return bl, "docs/BUILD-LOG.md"

def phase_for_script(script, phases):
    """The plan phase a build script belongs to: its file name in a plan row, else its mdlsource/<phase>/ folder, else the
    script's name matched to phase names (then row texts). None when nothing matches."""
    txt = script or ""
    bn = os.path.basename(txt.strip().split()[-1]).lower() if txt.strip() else ""
    if len(bn) > 4:
        for p in phases:
            if any(bn in (x["step"] or "").lower() for x in p["steps"]): return p
    m = re.search(r"mdlsource/([^/\s]+)/", txt)
    if m:
        f = m.group(1).lower(); fm = re.match(r"(?:phase[-_ ]?)?0*(\d+)(?:[-_ ](.*))?$", f)
        for p in phases:
            pid = str(p["id"]).lower(); nm = re.sub(r"[^a-z0-9]+", "", p["name"].lower()); fr = re.sub(r"[^a-z0-9]+", "", (fm.group(2) if fm and fm.group(2) else ""))
            if f == pid or (fm and fm.group(1) == pid.lstrip("0") and (not fr or fr in nm or nm in fr)) or re.sub(r"[^a-z0-9]+", "", f) == nm: return p
    stem = os.path.splitext(bn)[0]
    nm_ = re.match(r"0*(\d+)", stem)
    if nm_:   # a phase name that states its script numbers ("rows 350 to 399")
        for p in phases:
            r_ = re.search(r"rows?\s+(\d+)\s*(?:to|-)\s*(\d+)", p["name"])
            if r_ and int(r_.group(1)) <= int(nm_.group(1)) <= int(r_.group(2)): return p
    toks = [t for t in re.split(r"[-_\s]+", stem) if t and not t.isdigit() and t not in GENERIC and len(t) > 2]
    best, bs = None, 0
    for p in phases:
        nm = re.findall(r"[a-z0-9]+", p["name"].lower())
        sc = 3 * sum(1 for t in toks if t in nm or any(w_.startswith(t) or t.startswith(w_) for w_ in nm if len(w_) > 3))
        sc += sum(1 for x in p["steps"] for t in toks if t in (x["step"] or "").lower()) * 0.2
        if sc >= 3 and sc >= bs: best, bs = p, sc     # a phase NAME must match; row texts only break ties; the later phase wins a tie
    return best

def script_phases(runs, phases):
    """script -> phase for every script in the runs. Direct matches first; a numbered script with no match takes the phase of
    the nearest lower-numbered script that matched (scripts are numbered in build order). Unnumbered ones stay unmapped."""
    direct = {}; num = {}
    for r in runs:
        sc = r["script"]
        if sc in direct: continue
        direct[sc] = phase_for_script(sc, phases)
        m = re.match(r"0*(\d+)", os.path.splitext(os.path.basename(sc.strip().split()[-1]) if sc.strip() else "")[0])
        num[sc] = int(m.group(1)) if m else None
    # sort on (number, script name) only: two scripts can share a leading number (10-a, 10b-b) and dicts do not compare (#513)
    known = [(n_, pp) for n_, _k, pp in sorted(((num[k], k, direct[k]) for k in direct if direct[k] and num[k] is not None), key=lambda t: (t[0], t[1]))]
    out = {}
    for k, p in direct.items():
        if not p and num[k] is not None:
            lower = [pp for n, pp in known if n <= num[k]]
            p = lower[-1] if lower else None
        out[k] = p
    return out

def now_phase(bp, proj):
    """The phase the last applied build step belongs to (blocked and failed steps build nothing); else the highest phase
    with a built or partial row. Earlier phases with partial rows stay amber only."""
    phases = bp["phases"]
    runs, _ = build_runs(proj)
    ok = [r for r in runs if r["kind"] == "ok"]
    sp = script_phases(runs, phases)
    for r in reversed(ok[-12:]):     # the last applied step that maps to a phase (experiments and patches may not)
        if sp.get(r["script"]): return sp[r["script"]]
    act = [p for p in phases if p["built"] or p["partial"]]
    return act[-1] if act else None

def exec_facts(proj, bp):
    """Stage 5 build facts from the exec log (ledger first): counts, exec seconds, span, per-phase runs, latest score."""
    runs, src = build_runs(proj)
    if not runs: return None
    f = {"src": src, "n": len(runs), "ok": sum(r["kind"] == "ok" for r in runs), "fail": sum(r["kind"] == "fail" for r in runs), "blocked": sum(r["kind"] == "blocked" for r in runs),
         "restored": sum(1 for r in runs if r["restored"]), "first": runs[0]["t"], "last": runs[-1]["t"], "last_run": runs[-1]}
    el = [r["elapsed"] for r in runs if r["elapsed"] is not None]
    f["exec_s"] = sum(el) if el else None
    f["bad_s"] = sum(r["elapsed"] or 0 for r in runs if r["kind"] == "fail" or r["restored"]) if el else None
    sc = [r for r in runs if r["score"] is not None]; f["score"] = sc[-1] if sc else None
    per = {}; order = []; sp = script_phases(runs, bp["phases"]) if bp else {}
    for r in runs:
        p = sp.get(r["script"])
        k = (p["id"], p["name"]) if p else ("", "not mapped to a phase")
        if k not in per: per[k] = {"runs": 0, "ok": 0, "fail": 0, "blocked": 0, "s": 0.0}; order.append(k)
        d = per[k]; d["runs"] += 1; d[r["kind"]] += 1; d["s"] += r["elapsed"] or 0
    if bp: order.sort(key=lambda k: ([str(p["id"]) for p in bp["phases"]].index(str(k[0])) if k[0] != "" and str(k[0]) in [str(p["id"]) for p in bp["phases"]] else 10**6))
    f["phases"] = [(k, per[k]) for k in order]
    return f

def switch_from_runs(proj, day0):
    """First exec-log row on or after the sign-off date: the metrics ledger, else BUILD-LOG. (epoch, source) or None."""
    for rows, src in ((ledger_runs(proj), ".claude/loop/metrics-ledger.tsv"), ([{"t": t} for t, _, _ in build_log_rows(proj)], "docs/BUILD-LOG.md")):
        c = [r["t"] for r in rows if r["t"] >= day0]
        if c: return min(c), src
    return None

def facts_line(f):
    """One short line: runs, passed, failed or blocked, and the share of build time lost to failed or restored runs."""
    bad = f["fail"] + f["blocked"]; ex = f["exec_s"]; sh = ""
    if ex and f["bad_s"] is not None:
        x = f["bad_s"] / ex; words = [(0.25, "a quarter"), (1 / 3.0, "a third"), (0.5, "half"), (2 / 3.0, "two thirds")]
        near = [wd for v, wd in words if abs(x - v) < 0.04]
        sh = " (about %s of build time)" % (near[0] if near else "%d%%" % round(100 * x))
    return "%d build runs, %d passed, %d failed or blocked%s" % (f["n"], f["ok"], bad, sh)

def stage_boundaries(main, agents, info=None):
    """Start time per stage from session signals; honest fallbacks; monotonic."""
    tools = main["tools"]; sig = {}
    def first(pred):
        c = [e["t"] for e in tools if e["t"] and pred(e)]; return min(c) if c else None
    gate_any = lambda e: e["name"] == "Bash" and "gate-check" in e.get("cmd", "")
    gate_arg = lambda n: (lambda e: gate_any(e) and re.search(r"gate-check\.sh\s+(?:\.\s+)?%s\b" % n, e["cmd"]))
    sig["P"] = first(lambda e: e["name"] == "Skill" and "toolkit-init" in e.get("skill", ""))
    sig["0"] = first(gate_any)
    sig["1"] = first(gate_arg("0")) or first(lambda e: e["name"] == "Agent" and re.search(r"extract|Path [AB]", e.get("desc", "")))
    sig["2"] = first(lambda e: ("brd-contract" in e.get("file", "") + e.get("cmd", ""))) or first(lambda e: e["name"] == "Agent" and "BRD" in e.get("desc", ""))
    sig["3"] = first(gate_arg("2")) or first(lambda e: e["name"] == "Agent" and re.search(r"Stage 3", e.get("desc", "")))
    sig["4"] = first(lambda e: e["name"] == "Agent" and re.search(r"Stage 4|build plan", e.get("desc", ""), re.I))
    sig["5"] = first(lambda e: "build" in e.get("skill", "") and "plan" not in e.get("skill", ""))
    sig["6"] = None
    t5, _ = stage_switch(info, tools, sig.get("5"))
    sig["5"] = t5
    return sig

def stage_switch(info, tools, skill_t=None):
    """THE Stage 4 to 5 boundary, used by every per-stage view (windows, sub-agent tables, tokens, chart band) and by the
    no-log page. It is the EARLIEST evidenced build activity: the first row of the exec log (metrics ledger, else BUILD-LOG)
    and the Stage 4 sign-off time when the row has one. Only when there is no exec log row does the session log decide: the
    first exec.sh call, the build skill, the first write under mdlsource/. With ledger rows, session signals are ignored. A sign-off row with a date but no time gives no moment of its
    own: midnight is not evidence, so activity before that date is ignored and the switch is marked inferred. A later
    gate-check run never moves it. Returns (epoch or None, source text)."""
    so = (info or {}).get("signoff", {}).get("4")
    day0 = so[0] if so and so[0] and len(so) > 2 and not so[2] else None
    ok = lambda t: t and (day0 is None or t >= day0)
    exec_p = lambda e: e["name"] == "Bash" and re.search(r"(^|[\s/])exec\.sh\b", e.get("cmd", ""))
    mdl_p = lambda e: e["name"] in ("Write", "Edit") and "/mdlsource/" in e.get("file", "")
    SWITCH.clear(); cands = []
    r = switch_from_runs(info["dir"], day0 or 0) if info and info.get("dir") else None
    if r: cands.append((r[0], r[1]))
    if so and so[0] and day0 is None: cands.append((so[0], "the Stage 4 sign-off row in PROJECT.md"))
    if not r:   # the exec log is the primary source: with rows in it, session-log signals never move the switch
        ex = [e["t"] for e in tools if e["t"] and ok(e["t"]) and exec_p(e)]
        if ex: cands.append((min(ex), "the first exec.sh call in the session log"))
        if skill_t and ok(skill_t): cands.append((skill_t, "the build skill in the session log"))
    if not r:
        md = [e["t"] for e in tools if e["t"] and ok(e["t"]) and mdl_p(e)]
        if md: cands.append((min(md), "the first mdlsource write in the session log"))
    if not cands: return None, ""
    t, src = min(cands)
    if day0: SWITCH.update(inferred=True, t=t, day=day0, src=src)
    else: SWITCH.update(t=t, src=src)
    return t, src

def build_windows(sig, t_start, t_end):
    order = [s for s in STAGES if sig.get(s)]; wins = []
    last = t_start
    if order and sig[order[0]] > t_start: wins.append(("pre", t_start, sig[order[0]])); last = sig[order[0]]
    prev = None
    for s in order:
        st = max(sig[s], last)
        if prev: wins[-1] = (wins[-1][0], wins[-1][1], st)
        wins.append((s, st, t_end)); prev = s; last = st
    return wins
def stage_at(wins, t):
    for s, a, b in wins:
        if a <= t < b: return s
    return wins[-1][0] if wins and t >= wins[-1][1] else (wins[0][0] if wins else "P")

def agent_stage(a, wins):
    w5 = next((x for s_, x, _ in wins if s_ == "5"), None)
    if w5 and re.search(r"\bPhase\s*\d", a["desc"]) and not re.search(r"Stage\s*\d", a["desc"]) and a["t0"] >= w5 - PHASE_LEAD_S: return "5"   # a plan phase starting just before the first build run is build work
    for pat, fixed in AGENT_STAGE_RULES:
        m = re.search(pat, a["desc"])
        if m:
            s = fixed or m.group(1)
            if s in STAGES: return s
    return stage_at(wins, a["t0"])

# ----------------------------------------------------------------- build plan
PHASE_RE = re.compile(r"^#{1,6}\s+(?:Phase|Slice)\s+(\d[0-9A-Za-z.]*)\s*(?:[\u2014\u2013\u00b7:-]\s*|\s+)(.*?)\s*$")
def classify_state(raw):
    """Row status by prefix, 'not built' checked before 'built'. built | partial | todo | skip."""
    l = (raw or "").strip().lower().replace("**", "")
    if l.startswith(("not built", "not done", "not started", "planned", "to do", "todo", "open", "pending", "blocked", "failed")): return "todo"
    if l.startswith(("not needed", "n/a", "dropped", "skipped", "waived", "deferred")): return "skip"
    if l.startswith(("built", "done", "complete", "verified", "proven", "passed")): return "built"
    if l.startswith(("partial", "in progress", "started", "wip")): return "partial"
    return "todo"

# HARNESS rows that run `verify-module.sh <Module>` (the module-close row, brd-to-build-plan.md
# Step 5): Pass = the module's summary is clean AND its LOOK + CONFIRM is done. The agent that ran
# the pass often never edits State (MendixMau review 2026-10-21), so the report reads the evidence
# too. It promotes a row only on the full evidence and otherwise flags, like done-drift:
#   clean  the run reached its `verdict` row (CLEAN), no FAULT, no FINDING, nothing SKIPPED but
#          the look row and N/A rows (a --quick or --skip-* run is not a module close)
#   fresh  newer than every BUILD-LOG row and done- file of the scripts the row depends on
#          (dependsOn, followed back through the plan)
#   LOOK   the newest design/ui-reviews/ui-review-*.html naming the module (the `look`
#          obligation's artifact, bin/lib/obligations.tsv) states "N of N" in its headline and
#          carries N PROOF-OF-LOOK citations of screenshots on disk of 10 KB or more. The git
#          VALID AT staleness that obligation-check.sh adds is not run here: no git calls.
VERIFY_STEP = re.compile(r"verify-module\.sh`?\s+[`\"']?([A-Za-z_]\w*)")
PLAN_SCRIPT = re.compile(r"[A-Za-z0-9_.\-*…]+\.(?:mdl|sql)\b")

def _summary_state(rows):
    """'' when clean, else why not."""
    if not rows or rows[-1][0] != "verdict": return "cut short (no verdict row)"
    for r in rows:
        v = r[1] if len(r) > 1 else ""
        if v in ("FAULT", "FINDING"): return "%s: %s" % (v, r[0])
        if v == "SKIPPED" and not r[0].startswith("look (") and not (len(r) > 4 and r[4].startswith("(N/A")):
            return "SKIPPED: %s" % r[0]
    return "" if rows[-1][1] == "CLEAN" else "verdict %s" % rows[-1][1]

_EV_CACHE = {}
def _reviews(proj):
    """[(filename date, mtime, path, text)] of the LOOK reports, read once per project."""
    if ("rev", proj) not in _EV_CACHE:
        out = []
        for f in glob.glob(os.path.join(proj, "design", "ui-reviews", "ui-review-*.html")):
            try:
                d = re.search(r"\d{4}-\d\d-\d\d", os.path.basename(f))
                out.append((d.group(0) if d else "0000-00-00", os.path.getmtime(f), f, open(f, encoding="utf-8", errors="replace").read()))
            except OSError: pass
        _EV_CACHE[("rev", proj)] = out
    return _EV_CACHE[("rev", proj)]

def look_evidence(proj, mod):
    """(n, m, why): the module's newest LOOK report's headline count; why is '' when it discharges."""
    cands = [c for c in _reviews(proj) if mod in c[3]]
    if not cands: return 0, 0, "no design/ui-reviews/ui-review-*.html names %s" % mod
    _d, _t, f, txt = sorted(cands, reverse=True)[0]
    m = re.search(r"(\d+)\s+of\s+(\d+)", txt[:4000].replace("\r", ""), re.I)
    if not m: return 0, 0, "%s states no 'N of N' denominator" % os.path.basename(f)
    n, tot = int(m.group(1)), int(m.group(2))
    if n < tot or n == 0: return n, tot, "%s reviewed %d of %d" % (os.path.basename(f), n, tot)
    ok = 0
    for shot in re.findall(r"PROOF-OF-LOOK:\s*[^=<]+=\s*([^<>\s]+)", txt):
        p = shot if os.path.isabs(shot) else os.path.join(os.path.dirname(f), shot)
        try: ok += os.path.getsize(p) >= 10240
        except OSError: pass
    if ok < n: return n, tot, "%s: %d of %d PROOF-OF-LOOK screenshots on disk" % (os.path.basename(f), ok, n)
    return n, tot, ""

def _dep_scripts(x, by_n):
    names, todo, seen = set(), list(x.get("dependsOn") or []), set()
    while todo:
        k = str(todo.pop()).strip()
        if k in seen or k not in by_n: continue
        seen.add(k); r = by_n[k]
        for cell in (r.get("step"), r.get("produces")):
            for t in PLAN_SCRIPT.findall(cell or ""):
                names.add((t[5:] if t.startswith("done-") else t).replace("…", "*").replace("...", "*"))
        todo.extend(r.get("dependsOn") or [])
    return names

def verify_evidence(proj, x, by_n=None, log_rows=None, done_files=None):
    """The evidence for a HARNESS row that runs verify-module.sh <Module>, None for any other row:
    {mod, state, cl, form, day, why, since, n, tot}. form: none (no summary), unclean, stale, owed
    (clean and fresh, LOOK not discharged), verified. module_status reads it (the rule #501 put in harness_verify)."""
    m = VERIFY_STEP.search(x.get("step") or "") if (x.get("kind") or "").strip().upper() == "HARNESS" else None
    if not m: return None
    mod, state = m.group(1), x.get("state") or ""
    ev = {"mod": mod, "state": state, "cl": classify_state(state), "form": "none", "day": "", "why": "", "since": 0, "n": 0, "tot": 0}
    f = os.path.join(proj, ".claude", "loop", "verify", mod, "summary.tsv")
    try:
        rows = [l.split("\t") for l in open(f, encoding="utf-8", errors="replace").read().splitlines()[1:] if l.strip()]
        t = os.path.getmtime(f); ev["day"] = datetime.datetime.fromtimestamp(t).strftime("%Y-%m-%d")
    except OSError:
        return ev
    ev["why"] = _summary_state(rows)
    if ev["why"]: ev["form"] = "unclean"; return ev
    names = _dep_scripts(x, by_n or {})
    match = lambda s_: any(fnmatch.fnmatchcase(os.path.basename(s_), n) or fnmatch.fnmatchcase(os.path.basename(s_), "done-" + n) for n in names)
    if log_rows is None: log_rows = build_log_rows(proj)
    if done_files is None:
        if ("done", proj) not in _EV_CACHE:
            _EV_CACHE[("done", proj)] = [os.path.join(r_, n_) for r_, _d, fs in os.walk(os.path.join(proj, "mdlsource")) for n_ in fs if n_.startswith("done-")]
        done_files = _EV_CACHE[("done", proj)]
    since = [r for r in log_rows if r[0] > t and match(r[1])] if names else []
    newer = [d_ for d_ in done_files if names and match(d_) and os.path.getmtime(d_) > t]
    if since or newer: ev["form"] = "stale"; ev["since"] = len(since); return ev
    ev["n"], ev["tot"], ev["why"] = look_evidence(proj, mod)
    ev["form"] = "owed" if ev["why"] else "verified"
    return ev

# A module's sign-off status (MendixMau decision 2026-10-21): the HARNESS verify row is shown once,
# as its module's status on the phase card, never as a build row. Same evidence, nothing measured.
SIGNOFF_CLS = {"verified": "st-built", "owed": "st-progress", "stale": "st-progress", "unclean": "st-todo", "none": "st-todo", "claimed": "drift", "held": "st-person"}
def module_status(ev):
    """(form, label, detail) for the module of a verify_evidence result. detail is the evidence
    or the State disagreement, '' when there is nothing to add."""
    cl, day, st = ev["cl"], ev["day"], ev["state"] or "nothing"
    raw = (ev["state"] or "").strip().lower().replace("**", "")
    if ev["form"] == "none":
        if cl == "built": return "claimed", "built? no verify summary", "State says built, but .claude/loop/verify/%s/summary.tsv does not exist" % ev["mod"]
        return "none", "Verify not run", ""
    if ev["form"] == "unclean":
        return "unclean", "Verify not clean %s (%s)" % (day, ev["why"]), ("State says built, but the summary is not clean" if cl == "built" else "")
    if ev["form"] == "stale":
        lbl = ("Verify stale (%d build%s since)" % (ev["since"], "" if ev["since"] == 1 else "s")) if ev["since"] else "Verify stale (a script was marked done- after it)"
        return "stale", lbl, "summary %s is older than a script this row depends on" % day
    if ev["form"] == "owed":
        return "owed", "Verify owed - LOOK + CONFIRM", "verify clean %s; %s" % (day, ev["why"])
    lbl = "Verified \u2713 %s (LOOK %d/%d)" % (day, ev["n"], ev["tot"])
    if cl == "built": return "verified", lbl, ""
    # #501 never promoted a row a person holds: blocked / pending a person is not a sign-off
    if raw.startswith(("blocked", "pending a person")):
        return "held", "Verify clean %s, LOOK %d/%d - held: State says %s" % (day, ev["n"], ev["tot"], ev["state"]), ""
    return "verified", lbl, "State says %s: update State" % st

def _cells(line):
    c = re.split(r"(?<!\\)\|", line.strip())
    if c and c[0].strip() == "": c = c[1:]
    if c and c[-1].strip() == "": c = c[:-1]
    return [x.replace("\\|", "|").replace("**", "").strip() for x in c]

def parse_plan_md(path):
    """Row state straight from build-plan.md: a Phase heading opens a phase, a table with a # column and a State or
    Status column gives its rows (the last cell when a row is short). Returns [(id, name, [steps])] or []."""
    try: lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    except Exception: return []
    phases = []; cur = None; i = 0
    while i < len(lines):
        h = PHASE_RE.match(lines[i])
        if h: cur = (h.group(1), re.sub(r"\s*\*\(.*\)\*$", "", h.group(2)).strip(), []); phases.append(cur); i += 1; continue
        if lines[i].lstrip().startswith("|") and i + 1 < len(lines) and re.match(r"^\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$", lines[i + 1]):
            hd = [x.strip("`").lower() for x in _cells(lines[i])]; i += 2
            ci = {"n": next((k for k, x in enumerate(hd) if x in ("#", "no", "no.", "step", "row", "number")), None),
                  "state": next((k for k, x in enumerate(hd) if x.startswith(("state", "status"))), None),
                  "kind": next((k for k, x in enumerate(hd) if x.startswith("kind")), None),
                  "step": next((k for k, x in enumerate(hd) if x == "step" or x.startswith("what") or x.startswith("do")), None),
                  "dep": next((k for k, x in enumerate(hd) if x.startswith("depend")), None),
                  "prod": next((k for k, x in enumerate(hd) if x.startswith("produce")), None)}
            while i < len(lines) and lines[i].lstrip().startswith("|"):
                c = _cells(lines[i]); i += 1
                if ci["n"] is None or ci["state"] is None or not c or not re.match(r"^\d+$", c[ci["n"]] if ci["n"] < len(c) else ""): continue
                if cur is None: cur = ("all", "All rows", []); phases.append(cur)
                st = c[ci["state"]] if len(c) == len(hd) else c[-1]
                cell = lambda k: c[ci[k]] if ci[k] is not None and ci[k] < len(c) else ""
                cur[2].append({"number": c[ci["n"]], "kind": cell("kind") or "-",
                               "step": (cell("step") if ci["step"] != ci["n"] else ""), "state": st,
                               "produces": cell("prod"), "dependsOn": [d for d in re.split(r"[,\s]+", cell("dep")) if d.strip("-\u2014")]})
            continue
        i += 1
    return [p for p in phases if p[2]]

def finish_plan(phases, proj, generated, source):
    """Counts per phase and for the plan. HARNESS rows are not build rows (MendixMau decision
    2026-10-21): they are out of every 'x of y built' count, and a verify-module.sh row is shown as
    its module's sign-off status on the phase card instead (the last such row per module)."""
    out = []; kinds = collections.Counter(); tot = collections.Counter()
    by_n = {str(x.get("number")): x for _p, _n, st in phases for x in st}; logs = None
    last = {}
    for pi, (_pid, _name, steps) in enumerate(phases):
        for x in steps:
            m = VERIFY_STEP.search(x.get("step") or "") if (x.get("kind") or "").strip().upper() == "HARNESS" else None
            if m: last[m.group(1)] = (pi, x)
    signoffs = []
    for pi, (pid, name, steps) in enumerate(phases):
        c = collections.Counter(); kd = collections.Counter(); rows = []; mods_here = []; harness = 0
        for x in steps:
            kd[x.get("kind") or "-"] += 1
            if (x.get("kind") or "").strip().upper() == "HARNESS":
                harness += 1
                if logs is None and VERIFY_STEP.search(x.get("step") or ""): logs = build_log_rows(proj)
                ev = verify_evidence(proj, x, by_n, logs) if logs is not None else None
                if ev:
                    if last.get(ev["mod"], (None, None))[1] is x:
                        form, label, detail = module_status(ev)
                        mods_here.append({"mod": ev["mod"], "form": form, "label": label, "detail": detail, "n": x.get("number")})
                    continue   # its module's status says it; not a row of the list
                rows.append({"n": x.get("number"), "kind": x.get("kind"), "step": (x.get("step") or "")[:140], "state": x.get("state") or "", "cls": "harness"})
                continue
            cl = classify_state(x.get("state")); c[cl] += 1
            if cl != "skip": kinds[x.get("kind") or "-"] += 1
            rows.append({"n": x.get("number"), "kind": x.get("kind"), "step": (x.get("step") or "")[:140], "state": x.get("state") or "", "cls": cl})
        tot.update(c); signoffs.extend(mods_here)
        mods = os.path.join(proj, "architecture", "modules", name)
        out.append({"id": pid, "name": name, "n": c["built"] + c["partial"] + c["todo"], "built": c["built"], "partial": c["partial"], "todo": c["todo"], "skip": c["skip"], "kinds": dict(kd),
                    "harness": harness, "signoffs": mods_here,
                    "brief": os.path.isfile(os.path.join(mods, "module-brief.md")), "ledger": os.path.isfile(os.path.join(mods, "coverage-ledger.md")),
                    "def": os.path.isfile(os.path.join(mods, "definition.md")), "steps": rows})
    return {"phases": out, "kinds": dict(kinds), "built": tot["built"], "partial": tot["partial"], "todo": tot["todo"], "skip": tot["skip"],
            "total": sum(tot.values()) - tot["skip"], "harness": sum(p["harness"] for p in out), "signoffs": signoffs,
            "generated": generated, "source": source, "note": ""}

def build_log_rows(proj):
    """[(epoch, script, result)] from docs/BUILD-LOG.md exec rows, oldest first."""
    rows = []
    for line in read(os.path.join(proj, "docs", "BUILD-LOG.md")).splitlines():
        m = re.match(r"^\|\s*(20\d\d-\d\d-\d\dT\d\d:\d\d:\d\d)(Z|[+-]\d\d:?\d\d)?\s*\|\s*(.*?)\s*\|", line)
        if not m: continue
        c = [x.strip() for x in line.strip().strip("|").split("|")]
        try:
            t = datetime.datetime.strptime(m.group(1), "%Y-%m-%dT%H:%M:%S")
            z = m.group(2)
            if z == "Z": t = t.replace(tzinfo=datetime.timezone.utc)
            elif z:
                sg = 1 if z[0] == "+" else -1; zz = z[1:].replace(":", ""); t = t.replace(tzinfo=datetime.timezone(sg * datetime.timedelta(hours=int(zz[:2]), minutes=int(zz[2:]))))
            else: t = t.astimezone()
            rows.append((t.timestamp(), re.sub(r"[`]", "", c[1] if len(c) > 1 else ""), c[3] if len(c) > 3 else ""))
        except Exception: continue
    rows.sort(); return rows

def _num(txt):
    m = re.search(r"([\d.]+)\s*([kKmM]?)", txt or "")
    if not m: return None
    try: v = float(m.group(1))
    except ValueError: return None
    return int(v * {"": 1, "k": 1e3, "m": 1e6}[m.group(2).lower()])

def load_ledgers(proj):
    """Fallback when no session log exists: docs/progress/TIME-LEDGER.md (minutes, sub-agent tokens, exec runs per phase),
    docs/BUILD-LOG.md exec rows, .claude/loop/metrics-ledger.tsv (seconds per exec). None when none of them is there."""
    out = {"phases": [], "exec_rows": 0, "exec_blocked": 0, "active_s": 0, "exec_s": None, "first": None, "last": None, "sources": []}
    tl = read(os.path.join(proj, "docs", "progress", "TIME-LEDGER.md"))
    cols = {"start": 1, "min": 2, "tok": 3, "runs": 4}   # default layout; each table header re-maps it (a second table can differ)
    for line in tl.splitlines():
        c = [x.strip() for x in line.strip().strip("|").split("|")]
        if not line.lstrip().startswith("|") or len(c) < 4: continue
        if c[0].lower() == "phase":
            h = [x.lower() for x in c]
            fi = lambda *k: next((i for i, x in enumerate(h) if any(w in x for w in k)), None)
            cols = {"start": fi("start"), "min": fi("minute"), "tok": fi("token"), "runs": fi("exec", "run", "script")}
            continue
        if set(c[0]) <= set("-: ") or cols["min"] is None or len(c) <= cols["min"]: continue
        g = lambda k: c[cols[k]] if cols.get(k) is not None and len(c) > cols[k] else ""
        out["phases"].append({"phase": c[0], "start": g("start"), "min": _num(g("min")), "min_txt": g("min"), "tok": _num(g("tok")), "tok_txt": g("tok"), "runs": g("runs")})
    if out["phases"]: out["sources"].append("docs/progress/TIME-LEDGER.md")
    rows = build_log_rows(proj)
    if rows:
        out["exec_rows"] = len(rows); out["exec_blocked"] = sum(1 for r in rows if re.search(r"blocked|not-run|\U0001F6AB", r[2]))
        ts = [r[0] for r in rows]; out["first"], out["last"] = ts[0], ts[-1]
        out["active_s"] = sum(b - a for a, b in zip(ts, ts[1:]) if b - a <= IDLE_GAP_S)
        out["sources"].append("docs/BUILD-LOG.md")
    ml = read(os.path.join(proj, ".claude", "loop", "metrics-ledger.tsv")).splitlines()
    if len(ml) > 1:
        h = ml[0].split("\t")
        if "elapsed_s" in h:
            k = h.index("elapsed_s"); v = [float(r.split("\t")[k]) for r in ml[1:] if len(r.split("\t")) > k and re.match(r"^[\d.]+$", r.split("\t")[k])]
            if v: out["exec_s"] = sum(v); out["exec_n"] = len(v); out["sources"].append(".claude/loop/metrics-ledger.tsv")
    return out if out["sources"] else None

def load_build_plan(path, proj=None):
    """The plan counts. build-plan.json is a derived copy of build-plan.md; when it is older than the md or than the
    newest docs/BUILD-LOG.md row, the md is read instead (and the page says so), never a stale JSON with 0 built."""
    proj = proj or os.path.dirname(os.path.dirname(os.path.abspath(path)))
    md = os.path.join(proj, "architecture", "build-plan.md")
    try: d = json.load(open(path)); jt = os.path.getmtime(path)
    except Exception: d = None; jt = None
    mdp = parse_plan_md(md) if os.path.isfile(md) else []
    log_t = (build_log_rows(proj) or [(0,)])[-1][0]
    stale = jt is not None and ((os.path.isfile(md) and os.path.getmtime(md) > jt) or log_t > jt)
    if mdp and (d is None or stale):
        bp = finish_plan(mdp, proj, datetime.datetime.fromtimestamp(os.path.getmtime(md)).strftime("%Y-%m-%d %H:%M"), "md")
        if d is not None: bp["note"] = "plan JSON was stale, counted from build-plan.md" + (" (build-plan.json is older than build-plan.md)" if os.path.getmtime(md) > jt else " (build-plan.json is older than the newest BUILD-LOG.md row)")
        return bp
    if d is None: return None
    ph = [(p["id"], p["name"], p.get("steps", [])) for p in d.get("phases", [])]
    bp = finish_plan([(i, n, [{"number": x.get("number"), "kind": x.get("kind"), "step": x.get("step"), "state": x.get("state"), "produces": x.get("produces"), "dependsOn": x.get("dependsOn") or []} for x in st]) for i, n, st in ph], proj, d.get("generatedAt"), "json")
    if stale: bp["note"] = "plan JSON is older than the newest BUILD-LOG.md row and there is no readable build-plan.md to recount from; built counts may lag"
    return bp

# ----------------------------------------------------------------- analysis
def zero(): return {"in": 0, "out": 0, "cr": 0, "cw": 0, "cost": 0.0, "n": 0}
def add(a, m, rates):
    for k in ("in", "out", "cr", "cw"): a[k] += m[k]
    c = cost_of(m, m["model"], rates); a["n"] += 1
    if c is None: a["unpriced"] = True
    else: a["cost"] += c
def head(a): return a["in"] + a["out"] + a["cw"]

def analyse(proj, info, gate, manifest, arts, main, agents, rates, bp):
    all_t = main["times"] + [x for a in agents for x in (a["t0"], a["t1"])]
    t0, t1 = min(all_t), max(all_t)
    sig = stage_boundaries(main, agents, info); wins = build_windows(sig, t0, t1)
    S = {s: {"main": zero(), "sub": zero(), "wf": zero(), "agents": [], "wf_n": 0, "min": collections.Counter()} for s in ["pre"] + STAGES}
    for s_ in S: S[s_]["ctx"] = []
    mctx = []
    for m in main["msgs"]:
        if m["t"] is not None:
            add(S[stage_at(wins, m["t"])]["main"], m, rates)
            c_ = m["in"] + m["cr"] + m["cw"]; S[stage_at(wins, m["t"])]["ctx"].append(c_); mctx.append((m["t"], c_))
    for a in agents:
        a["stage"] = agent_stage(a, wins); a["tok"] = zero()
        cx = [m["in"] + m["cr"] + m["cw"] for m in a["msgs"]] or [0]
        a["ctx_avg"] = sum(cx) / len(cx); a["ctx_peak"] = max(cx)
        for m in a["msgs"]: add(a["tok"], m, rates)
        st = S[a["stage"]]; st["agents"].append(a)
        add(st["wf" if a["wf"] else "sub"], {**{k: a["tok"][k] for k in ("in", "out", "cr", "cw")}, "model": "__sum__"}, rates) if False else None
        tgt = st["wf" if a["wf"] else "sub"]
        for k in ("in", "out", "cr", "cw", "cost", "n"): tgt[k] += a["tok"][k]
        if a["tok"].get("unpriced"): tgt["unpriced"] = True
    # minute states
    ev = sorted(set(int(x) for x in main["times"]) | set(int(x) for a in agents for x in a["times"])); idle = []
    for x, y in zip(ev, ev[1:]):
        if y - x > IDLE_GAP_S: idle.append((x, y))
    sub_iv = [(a["t0"], a["t1"]) for a in agents]
    minutes = []; m0 = int(t0 // 60)
    for k in range(int((t1 - t0) // 60) + 1):
        a = (m0 + k) * 60; mid = a + 30
        st = "sub" if any(x <= mid <= y for x, y in sub_iv) else "idle" if any(x < mid < y for x, y in idle) else "main"
        minutes.append((a, st)); S[stage_at(wins, a)]["min"][st] += 1
    # token buckets of 10 minutes
    buckets = collections.Counter()
    for m in main["msgs"] + [m for a in agents for m in a["msgs"]]:
        if m["t"] is not None: buckets[int((m["t"] - t0) // 600)] += m["in"] + m["out"] + m["cw"]
    return {"mctx": sorted(mctx), "t0": t0, "t1": t1, "wins": wins, "sig": sig, "S": S, "minutes": minutes, "buckets": buckets, "idle": idle}

# ----------------------------------------------------------------- advice
def advice(info, an, main, agents, rates):
    S = an["S"]; out = []
    tot = zero()
    for s in S.values():
        for part in ("main", "sub", "wf"):
            for k in ("in", "out", "cr", "cw", "cost"): tot[k] += s[part][k]
    htot = head(tot)
    stage_head = {k: head(v["main"]) + head(v["sub"]) + head(v["wf"]) for k, v in S.items()}
    top = max(stage_head, key=stage_head.get)
    if htot:
        lab = "before Stage P" if top == "pre" else "Stage " + top
        out.append(("Where tokens went", "%s used %.0f%% of the new tokens (input + output + cache write): %s of %s." % (lab, pct(stage_head[top], htot), fmt_tok(stage_head[top]), fmt_tok(htot))))
    subs = [a for a in agents]; sub_tok = sum(head(a["tok"]) for a in subs)
    out.append(("Sub-agent share", "%d sub-agents carried %.0f%% of new tokens and %.0f%% of estimated cost; the main thread carried the rest." %
                (len(subs), pct(sub_tok, htot), pct(sum(a["tok"]["cost"] for a in subs), tot["cost"]))))
    opus_a = [a for a in subs if "opus" in a["model"]]
    rule = [d for d in info["decisions"] if "ubagent" in d[1] or "Subagent" in d[1]]
    if opus_a:
        oc = sum(a["tok"]["cost"] for a in opus_a)
        txt = "%d sub-agents ran on Opus (%s, est. $%.0f, %.0f%% of sub-agent cost): %s." % (len(opus_a), ", ".join(esc(a["desc"]) for a in opus_a[:4]), oc, pct(oc, sum(a["tok"]["cost"] for a in subs)), "")
        if rule: txt += " The register says \"%s\"; consider Sonnet for any that are not design or judgment work." % rule[0][1]
        out.append(("Model choice", txt.replace(": .", ".")))
    mc = collections.Counter(); 
    for m in main["msgs"]: mc[m["model"]] += 1
    mm = mc.most_common(1)[0] if mc else None
    if mm and "opus" in mm[0]:
        mcost = sum(S[s]["main"]["cost"] for s in S)
        out.append(("Main thread model", "The main thread ran on %s for %d requests (est. $%.0f, %.0f%% of total). Routine orchestration turns could run on a cheaper model; keep the expensive one for review and judgment." % (mm[0], mm[1], mcost, pct(mcost, tot["cost"]))))
    peak = max([m["in"] + m["cw"] + m["cr"] for m in main["msgs"]] or [0])
    comp = main["compacts"]
    cw_, cn_ = context_window(main["msgs"], main["compacts"], main.get("flag_1m", False))
    ctxt = "Peak main-thread context was %s tokens (%s)." % (fmt_tok(peak), ("%s of the %s window for this model%s" % (ctx_pct_txt(peak, cw_), fmt_tok(cw_), "; " + cn_ if cn_ else "")) if cw_ else "window unknown: " + cn_)
    if comp: ctxt += " Auto-compacted %d times (at %s tokens), each time dropping the context to about %s." % (len(comp), ", ".join(fmt_tok(c["pre"] or 0) for c in comp), fmt_tok(sum(c["post"] or 0 for c in comp) / len(comp)))
    out.append(("Context size", ctxt + (" Hand bulk reading to sub-agents and park or clear at a stage boundary, before the next auto-compaction." if comp else "")))
    inp = tot["in"] + tot["cw"] + tot["cr"]; hit = pct(tot["cr"], inp)
    out.append(("Cache hit ratio", "%.0f%% of all input tokens were served from cache. %s" % (hit, "Healthy." if hit >= 85 else "Low: long idle gaps or changing prompt prefixes are rewriting the cache.")))
    reqs = sorted(main["msgs"], key=lambda m: m["t"] or 0); rew = 0; rewtok = 0
    for a, b in zip(reqs, reqs[1:]):
        if b["t"] and a["t"] and b["t"] - a["t"] > CACHE_TTL_S and b["cw"] > 50_000: rew += 1; rewtok += b["cw"]
    if rew: out.append(("Cache rewrites after waiting", "%d times the main thread resumed after more than %d minutes and rewrote %s tokens of cache. Waiting on the user lets the 5 minute cache expire; batch questions and answer in one go." % (rew, CACHE_TTL_S // 60, fmt_tok(rewtok))))
    idle_s = sum(y - x for x, y in an["idle"]); wall = an["t1"] - an["t0"]
    out.append(("Waiting time", "%s of %s wall time (%.0f%%) was gaps longer than %d minutes, i.e. waiting for the user." % (fmt_dur(idle_s), fmt_dur(wall), pct(idle_s, wall), IDLE_GAP_S // 60)))
    return out, tot, peak

def _union(iv):
    iv = sorted(x for x in iv if x[1] > x[0]); out = []
    for a_, b_ in iv:
        if out and a_ <= out[-1][1]: out[-1][1] = max(out[-1][1], b_)
        else: out.append([a_, b_])
    return out
def _total(iv): return sum(b_ - a_ for a_, b_ in iv)
def _median(v):
    v = sorted(v); return v[len(v) // 2] if v else 0
def stage_label(an, t):
    s_ = stage_at(an["wins"], t)
    return "before Stage P" if s_ == "pre" else "Stage " + s_

def call_stats(info, an, main):
    """Per tool call numbers: health, speed and the raw groups the tips read. Numbers and tool or script names only."""
    calls = [c for c in main.get("calls", []) if c["t0"]]
    done = [c for c in calls if c["t1"]]
    for c in done: c["dur"] = max(0.0, c["t1"] - c["t0"])
    med = {}
    for n in {c["name"] for c in done}: med[n] = _median([c["dur"] for c in done if c["name"] == n])
    inh = lambda c: c["name"] == "Bash" and bool(c["script"]) and bool(re.match(ADV["inherent_scripts"], c["script"]))   # required gates and builds never count as hangs
    failed = [c for c in done if c["err"]]
    killed = [c for c in calls if (c["killed"] or c["timeout"]) and not inh(c)]
    hung = [c for c in done if c["dur"] >= ADV["hang_min_s"] and c["dur"] >= ADV["hang_x"] * max(med.get(c["name"], 0), 1) and not c["waity"] and not c["bg"] and c["name"] not in INHERENT_TOOLS and not inh(c)]
    hung_all = {id(c): c for c in hung + killed}.values()
    keyed = collections.OrderedDict()
    for label, rx in KEY_SCRIPTS:
        rs = [c for c in done if c["name"] == "Bash" and c["script"] and re.match(rx, c["script"])]
        keyed[label] = {"runs": len(rs), "fail": sum(1 for c in rs if c["err"]), "calls": rs}
    # time split of the whole session, approximate
    t0, t1 = an["t0"], an["t1"]; wall = max(t1 - t0, 1)
    idle = _union([list(x) for x in an["idle"]])
    ci = _union([[c["t0"], c["t1"]] for c in done if c["waity"] or c["bg"]])
    ask = [[c["t0"], c["t1"]] for c in done if c["name"] in INHERENT_TOOLS]   # interview time is waiting on the user
    tool = _union([[c["t0"], c["t1"]] for c in done if not (c["waity"] or c["bg"]) and c["name"] not in ("Agent", "Task") and c["name"] not in INHERENT_TOOLS])
    ci_s = _total(ci); tool_s = _total(tool); idle_s = _total(_union(idle + ask))
    think_s = max(0.0, wall - idle_s - ci_s - tool_s)
    # slices: one exec.sh run
    sl = [c for c in done if c["name"] == "Bash" and c["script"] == "exec.sh"]
    sl_med = _median([c["dur"] for c in sl])
    sl_out = [c for c in sl if sl_med and c["dur"] > ADV["slice_outlier_x"] * sl_med]
    slow = sorted([c for c in done if c["name"] not in ("Agent", "Task") and not c["waity"] and not c["bg"] and c["name"] not in INHERENT_TOOLS], key=lambda c: -c["dur"])[:3]
    return {"calls": calls, "done": done, "med": med, "failed": failed, "killed": killed, "hung": list(hung_all), "keyed": keyed,
            "split": {"tool": tool_s, "think": think_s, "user": idle_s, "ci": ci_s, "wall": wall},
            "slices": sl, "slice_med": sl_med, "slice_out": sl_out, "slow": slow}

def callname(c):
    if c["name"] == "Bash" and c["script"]: return c["script"] + ((" " + c["variant"]) if c.get("variant") else "")
    return c["name"] or "tool"

def run_health(cs):
    """Green, amber or red per measure, each with its counts. Red is rare: a key script failing on every run (at least
    repeat_fail_red_n runs) or one hang or stall past hang_red_s. Amber: a failure rate from fail_share_amber, or a hang past hang_amber_s."""
    nd = len(cs["done"]); share = len(cs["failed"]) / nd if nd else 0.0
    items = [("Tool calls failed", "amber" if share >= ADV["fail_share_amber"] else "green", "%d of %d (%.0f%%)" % (len(cs["failed"]), nd, 100 * share))]
    kl = []; worst = "green"; rk = {"green": 0, "amber": 1, "red": 2}
    for label, v in cs["keyed"].items():
        if not v["runs"]: continue
        rate = v["fail"] / v["runs"]
        l_ = "red" if (v["fail"] == v["runs"] and v["runs"] >= ADV["repeat_fail_red_n"]) else "amber" if rate >= ADV["fail_share_amber"] else "green"
        kl.append("%s %d/%d passing" % (label, v["runs"] - v["fail"], v["runs"]))
        if rk[l_] > rk[worst]: worst = l_
    items.append(("Key scripts", worst if kl else "green", "; ".join(kl) or "none ran (doctor, gate-check, exec, tests)"))
    longest = max([c.get("dur", 0.0) for c in cs["hung"]] + [c.get("dur", 0.0) for c in cs["killed"] if c.get("dur") is not None] + [0.0])
    nh = len({id(c) for c in list(cs["hung"]) + list(cs["killed"])})
    items.append(("Hung or killed", "red" if longest > ADV["hang_red_s"] else "amber" if longest > ADV["hang_amber_s"] else "green",
                  "%d command(s)%s" % (nh, ", longest %s" % fmt_dur(longest) if longest else "")))
    overall = max((i[1] for i in items), key=lambda x: rk[x])
    return overall, items

def advisory(info, an, main, agents, rates, tot, peak):
    """Ranked, rule-based tips on tokens, speed and health. Each: impact (minutes-equivalent), ratio over its threshold,
    what was seen, why it matters, one fix, why it fired. Returns (fired, quiet, health, speed)."""
    S = an["S"]; fired = []; quiet = []
    cs = call_stats(info, an, main)
    cost_all = sum(S[s][p]["cost"] for s in S for p in ("main", "sub", "wf")) or 1e-9
    proj = info["dir"]
    def rel(f):
        try: r = os.path.relpath(f, proj)
        except ValueError: r = f
        return os.path.basename(f) if r.startswith("..") else r
    GROUP = {"tokens": "Tokens and cost", "speed": "Speed", "health": "Health"}
    hidden = [0]
    def rule(ratio, kind, title, seen, matters, fix, why, lost_s=0.0, lost_tok=0.0, group=None, sev=None, inherent=False):
        """inherent: the cost comes from how the toolkit or mxcli works (builds, required gates and reviews, the mandated review model, waiting on builds or the user). Never shown."""
        if ratio >= 1 and inherent: hidden[0] += 1; return
        if ratio >= 1 and not lost_tok and 0 < lost_s < ADV["min_lost_s"]: ratio = 0   # a tip that loses under a minute is noise
        d = {"ratio": ratio, "kind": kind, "group": group or GROUP[kind], "sev": sev or ("amber" if ratio >= 2 else "info"), "title": title, "seen": seen, "matters": matters, "fix": fix, "why": why,
             "lost_s": lost_s, "lost_tok": lost_tok, "impact": lost_s / 60.0 + lost_tok / TOKENS_PER_MIN}
        (fired if ratio >= 1 else quiet).append(d)
    lostfmt = lambda ls, lt: " / ".join(x for x in (fmt_dur(ls) if ls else "", fmt_tok(lt) + " tokens" if lt else "") if x)
    # ---- tokens
    opus_main = sum(S[s]["main"]["cost"] for s in S) if any("opus" in m["model"] for m in main["msgs"]) else 0
    oa = [a for a in agents if "opus" in a["model"]]; opus_sub = sum(a["tok"]["cost"] for a in oa)
    share = (opus_main + opus_sub) / cost_all
    rule(share / ADV["opus_cost_share"], "tokens", "Model mix: Opus carries most of the cost",
         "Opus is %.0f%% of estimated cost ($%.0f of $%.0f): main thread $%.0f, %d sub-agents $%.0f (%s)." % (100 * share, opus_main + opus_sub, cost_all, opus_main, len(oa), opus_sub, ", ".join(a["desc"] for a in oa[:3])),
         "The most capable model is the slowest and dearest; routine batches do not need it.",
         "Keep Opus for architecture, build plan and review. Run routine batches (BRD drafting, extraction, validation) on a cheaper model.",
         "Fired when the Opus share of cost is at least %.0f%% (opus_cost_share). Measured %.0f%%." % (100 * ADV["opus_cost_share"], 100 * share),
         lost_tok=sum(head(a["tok"]) for a in oa), inherent=True)
    mc = [m["in"] + m["cr"] + m["cw"] for m in main["msgs"]] or [0]; avg = sum(mc) / len(mc)
    win, wnote = context_window(main["msgs"], main["compacts"], main.get("flag_1m", False)); comp = len(main["compacts"])
    big = [c for c in cs["done"] if c["name"] == "Read" and c["rchars"] >= ADV["large_read_chars"]]
    reached = bool(win) and peak >= ADV["ctx_peak_frac"] * win
    r = max(avg / ADV["ctx_avg_tokens"], 1.0 if reached else 0.0, comp / ADV["compactions"] if ADV["compactions"] else 0, len(big) / ADV["large_read_n"])
    csev = "amber" if (reached or comp or avg >= ADV["ctx_avg_tokens"]) else "info"   # context is never red
    ctitle = ("Context: the window was reached and compacted %d time(s)" % comp if (reached and comp) else "Context: the window was reached" if reached
              else "Context: compacted %d time(s)" % comp if comp else "Context: the main thread runs large" if avg >= ADV["ctx_avg_tokens"] else "Context: large file reads")
    rule(r, "tokens", ctitle,
         "Average context %s, peak %s (%s); %d automatic compaction(s); %d file read(s) over %s characters." %
         (fmt_tok(avg), fmt_tok(peak), ("%s window, %s avg, %s peak" % (fmt_tok(win), ctx_pct_txt(avg, win), ctx_pct_txt(peak, win)) + ("; " + wnote if wnote else "")) if win else "window unknown: " + wnote, comp, len(big), fmt_tok(ADV["large_read_chars"])),
         "Every request re-reads the whole context, so a full window costs more on every later turn, and compaction loses detail.",
         "Hand bulk reading (source files, long logs) to sub-agents so only a summary returns, and park or clear at each stage boundary instead of waiting for auto-compaction.",
         "Fired when average context reaches %s, the peak reaches %.0f%% of the window, compactions reach %d, or %d large reads occur (ctx_avg_tokens, ctx_peak_frac, compactions, large_read_n)." % (fmt_tok(ADV["ctx_avg_tokens"]), 100 * ADV["ctx_peak_frac"], ADV["compactions"], ADV["large_read_n"]),
         lost_tok=sum(c["rchars"] for c in big) / 4.0, group="Context", sev=csev)
    reqs = sorted(main["msgs"], key=lambda m: m["t"] or 0); rew = 0; rewtok = 0; rewcost = 0.0
    for a, b in zip(reqs, reqs[1:]):
        if b["t"] and a["t"] and b["t"] - a["t"] > CACHE_TTL_S and b["cw"] > 50_000:
            rew += 1; rewtok += b["cw"]; rt = rate_for(b["model"], rates); rewcost += b["cw"] * rt[1] / 1e6 if rt else 0
    rule(rew / ADV["cache_rewrites"], "tokens", "Cache rewrites after waiting",
         "%d resumptions after more than %d minutes rewrote %s tokens of cache (about $%.0f at cache write price)." % (rew, CACHE_TTL_S // 60, fmt_tok(rewtok), rewcost),
         "A cache that expired while the session waited is paid for again in full on the next request.",
         "Batch answers: let the agent collect questions and answer them in one sitting, and avoid leaving a long context idle past the 5 minute cache lifetime.",
         "Fired when at least %d such rewrites occur (cache_rewrites). Counted %d." % (ADV["cache_rewrites"], rew), lost_tok=rewtok, inherent=True)
    sc = {s: sum(S[s][p]["cost"] for p in ("main", "sub", "wf")) for s in STAGES if sum(S[s][p]["cost"] for p in ("main", "sub", "wf")) > 0}
    if len(sc) >= 3:
        vals = sorted(sc.values()); med_ = vals[len(vals) // 2]; top = max(sc, key=sc.get); x = sc[top] / med_ if med_ else 0
        stok = {s: sum(head(S[s][p]) for p in ("main", "sub", "wf")) for s in sc}
        rule(x / ADV["stage_outlier_x"], "tokens", "Cost outlier: Stage %s" % top,
             "Stage %s cost $%.0f, %.1fx the median stage ($%.0f)." % (top, sc[top], x, med_),
             "One stage that dwarfs the rest usually hides repeated reading or an over-sized agent.",
             "Check what dominated Stage %s (its card and the sub-agent table). If it was repeated reading, give that work a cheaper model or a smaller context." % top,
             "Fired when a stage costs at least %.1fx the median stage (stage_outlier_x). Measured %.1fx." % (ADV["stage_outlier_x"], x),
             lost_tok=max(0, stok[top] - sorted(stok.values())[len(stok) // 2]), inherent=True)
    # ---- sub-agents
    short = [a for a in agents if a["t1"] - a["t0"] < ADV["agent_short_s"]]; long_ = [a for a in agents if a["t1"] - a["t0"] > ADV["agent_long_s"]]
    tpa = sum(head(a["tok"]) for a in agents) / len(agents) if agents else 0
    r = max(len(short) / ADV["short_agents_n"], len(long_) / ADV["long_agents_n"])
    lg = max(agents, key=lambda a: a["t1"] - a["t0"]) if agents else None
    rule(r, "tokens", "Sub-agent use: many very short or very long agents",
         "%d agents averaging %s new tokens each; %d ran under %d s (spawn overhead dominates); %d ran over %d min (longest: %s, %s)." % (len(agents), fmt_tok(tpa), len(short), ADV["agent_short_s"], len(long_), ADV["agent_long_s"] // 60, lg["desc"] if lg else "none", fmt_dur(lg["t1"] - lg["t0"]) if lg else "0"),
         "Tiny agents pay start-up cost for no gain, and a very long one loses everything if it fails late.",
         "Merge tiny tasks into one agent, and split agents that run past 30 minutes into checkpointed pieces.",
         "Fired when at least %d agents are under %d s or %d agents over %d s." % (ADV["short_agents_n"], ADV["agent_short_s"], ADV["long_agents_n"], ADV["agent_long_s"]),
         lost_s=sum(a["t1"] - a["t0"] for a in short), group="Sub-agents")
    wall = an["t1"] - an["t0"]; idle_s = sum(y - x for x, y in an["idle"]); ws = idle_s / wall if wall else 0
    rule(ws / ADV["wait_share"], "speed", "Waiting on the user",
         "%s of %s wall time (%.0f%%) was gaps longer than %d minutes between turns." % (fmt_dur(idle_s), fmt_dur(wall), 100 * ws, IDLE_GAP_S // 60),
         "Waiting is wall time nobody can speed up, and it also lets the cache expire.",
         "Queue the questions for the next checkpoint and let the agent work on something independent while the answer is pending.",
         "Fired when waiting is at least %.0f%% of wall time (wait_share). Measured %.0f%%." % (100 * ADV["wait_share"], 100 * ws), lost_s=idle_s, inherent=True)
    inp = tot["in"] + tot["cw"] + tot["cr"]; hit = tot["cr"] / inp if inp else 1
    rule((1 - hit) / (1 - ADV["cache_hit_min"]) if hit < 1 else 0, "tokens", "Cache hit ratio is low", "Only %.0f%% of input tokens came from cache." % (100 * hit),
         "Cache reads cost a fraction of fresh input, so every miss is paid in full.",
         "Keep the system prompt and early context stable; avoid editing earlier turns or swapping tools mid-session.",
         "Fired when the cache hit ratio is below %.0f%% (cache_hit_min). Measured %.0f%%." % (100 * ADV["cache_hit_min"], 100 * hit), lost_tok=max(0, inp * (ADV["cache_hit_min"] - hit)), inherent=True)
    # ---- health
    hg = cs["hung"]; med = cs["med"]
    if hg or True:
        names = collections.Counter(callname(c) for c in hg)
        longest = max(hg, key=lambda c: c.get("dur", 0)) if hg else None
        excess = sum(max(0.0, c.get("dur", 0) - med.get(c["name"], 0)) for c in hg)
        stg = sorted({stage_label(an, c["t0"]) for c in hg})
        rule(len(hg) / ADV["hang_n"] if ADV["hang_n"] else 0, "health", "Hanging or killed commands",
             "%d command(s) hung, timed out or were stopped (%s)%s; %s." % (len(hg), ", ".join("%s x%d" % kv for kv in names.most_common(4)) or "none",
                (", longest %s in %s" % (fmt_dur(longest["dur"]), callname(longest))) if longest else "", ", ".join(stg) or "no stage"),
             "A hung command blocks the whole session until it times out, and the time is lost even when the work is then redone.",
             "Give long commands a timeout and run them in the background; if the same one hangs twice, fix or file the tool instead of retrying.",
             "Fired when %d or more calls ran past %d s and %dx their tool's median, timed out, or were stopped (hang_n, hang_min_s, hang_x)." % (ADV["hang_n"], ADV["hang_min_s"], ADV["hang_x"]), lost_s=excess + 60.0 * len([c for c in hg if "dur" not in c]), sev="red" if (longest and longest.get("dur", 0) > ADV["hang_red_s"]) else "amber")
    byfail = collections.defaultdict(list)
    for c in cs["failed"]:
        if c["name"] == "Bash" and c["script"] and c["script"] not in TRIVIAL_CMDS and (SCRIPT_FILE_RE.search(c["script"]) or c["script"] in REAL_CMDS): byfail[(c["script"], c.get("variant", ""))].append(c)   # real scripts and tools only, by name
    worst = max(byfail.items(), key=lambda kv: len(kv[1])) if byfail else None
    if worst:
        (sn, var), fl = worst; nm = sn + ((" " + var) if var else "")
        tot_runs = len([c for c in cs["done"] if c["name"] == "Bash" and c["script"] == sn and c.get("variant", "") == var])
        stg = collections.Counter(stage_label(an, c["t0"]) for c in fl)
        others = ", ".join("%s x%d" % ((k[0] + (" " + k[1] if k[1] else "")), len(v)) for k, v in sorted(byfail.items(), key=lambda kv: -len(kv[1]))[1:4])
        rule(len(fl) / ADV["repeat_fail_n"], "health", "Failing tool on repeat: %s" % nm,
             "%s failed %d of %d runs (%s)%s." % (nm, len(fl), tot_runs, ", ".join("%s x%d" % kv for kv in stg.most_common(3)), ("; also failing: " + others) if others else ""),
             "A tool that fails repeatedly is either broken or being rerun without changing its input, and each rerun costs the call plus the turn that reads its output.",
             "Read the failure once, fix the cause or the script, and file the tool if the failure is not yours. Stop rerunning it unchanged.",
             "Fired when the same script fails %d or more times (repeat_fail_n). Counted %d." % (ADV["repeat_fail_n"], len(fl)),
             lost_s=sum(c.get("dur", 0) for c in fl), sev="red" if (len(fl) == tot_runs and tot_runs >= ADV["repeat_fail_red_n"] and any(re.match(rx, sn) for _, rx in KEY_SCRIPTS)) else "amber")
    else:
        rule(0, "health", "Failing tool on repeat", "no script failed repeatedly", "", "", "Fired when the same script fails %d or more times (repeat_fail_n). Counted 0." % ADV["repeat_fail_n"])
    edits = collections.defaultdict(list)
    for c in cs["calls"]:
        if c["file"]: edits[c["file"]].append(c["t0"])
    best = (0, None, 0.0)
    for f, ts_ in edits.items():
        ts_.sort(); j = 0
        for i in range(len(ts_)):
            while ts_[i] - ts_[j] > ADV["edit_loop_window_s"]: j += 1
            if i - j + 1 > best[0]: best = (i - j + 1, f, ts_[i] - ts_[j])
    rule(best[0] / ADV["edit_loop_n"], "health", "Rework loop: one file edited again and again",
         "%s was edited %d times within %s%s." % (rel(best[1]) if best[1] else "no file", best[0], fmt_dur(best[2]), (" (" + stage_label(an, edits[best[1]][0]) + ")") if best[1] else ""),
         "Many small edits to one file usually mean the target is unclear or each attempt is checked too late.",
         "Write down what the file must do and the check that proves it before the next edit, then edit once and run the check.",
         "Fired when one file is edited %d or more times inside %d minutes (edit_loop_n, edit_loop_window_s). Peak %d." % (ADV["edit_loop_n"], ADV["edit_loop_window_s"] // 60, best[0]),
         lost_s=best[2])
    # ---- speed
    wy = [c for c in cs["done"] if c["waity"] or c["bg"]]; wy_s = _total(_union([[c["t0"], c["t1"]] for c in wy]))
    rule(wy_s / ADV["ci_wait_s"], "speed", "Waiting on CI or background work",
         "%s spent in sleep, watch or monitor calls (%d call(s))." % (fmt_dur(wy_s), len(wy)),
         "Time spent polling is time the session is not building.",
         "Start the next independent step while the check runs, and poll less often.",
         "Fired when waiting calls total at least %d s (ci_wait_s). Measured %d s." % (ADV["ci_wait_s"], wy_s), lost_s=wy_s, inherent=True)
    byscript = collections.defaultdict(list)
    for c in cs["done"]:
        if c["name"] == "Bash" and c["script"] and not c["waity"] and not c["bg"]: byscript[c["script"]].append(c["dur"])
    slow = [(sn, v) for sn, v in byscript.items() if len(v) >= ADV["slow_script_runs"] and _median(v) >= ADV["slow_script_s"] and sum(v) >= ADV["slow_script_total_s"]]
    slow = [(k, v) for k, v in slow if not re.match(ADV["inherent_scripts"], k)]   # exec, gate checks, builds: how the toolkit works
    sw = max(slow, key=lambda kv: sum(kv[1])) if slow else None
    rule((sum(sw[1]) / ADV["slow_script_total_s"]) if sw else 0, "speed", "Slow on every run: %s" % (sw[0] if sw else "no script"),
         "%s ran %d times, median %s, %s in total%s." % (sw[0], len(sw[1]), fmt_dur(_median(sw[1])), fmt_dur(sum(sw[1])), "; also slow: " + ", ".join(k for k, _ in slow if k != sw[0]) if len(slow) > 1 else "") if sw else "no script was slow on every run",
         "A script that is slow each time is paid for in full every time it runs.",
         "Cache what does not change between runs, or run it less often (per module and before deploys, not after every edit).",
         "Fired when a script runs %d or more times, median at least %d s, total at least %d s (slow_script_*)." % (ADV["slow_script_runs"], ADV["slow_script_s"], ADV["slow_script_total_s"]),
         lost_s=(sum(sw[1]) - _median(sw[1])) if sw else 0)
    ag = sorted([c for c in cs["done"] if c["name"] in ("Agent", "Task") and c["dur"] >= ADV["serial_agent_s"]], key=lambda c: c["t0"])
    chain = 0; best_chain = 0; ser_s = 0.0; cur_s = 0.0
    for p_, n_ in zip(ag, ag[1:]):
        if 0 <= n_["t0"] - p_["t1"] < 60:
            chain = chain + 1 if chain else 2; cur_s += min(p_["dur"], n_["dur"])
            if chain > best_chain: best_chain, ser_s = chain, cur_s
        else: chain = 0; cur_s = 0.0
    rule(best_chain / ADV["serial_agents_n"], "speed", "Serial sub-agents that could have overlapped",
         "%d sub-agents of at least %d s ran one after another with no overlap (about %s of overlappable time)." % (best_chain, ADV["serial_agent_s"], fmt_dur(ser_s)),
         "Independent agents started together finish in the time of the slowest one.",
         "Start independent sub-agents in one message so they run in parallel, and keep the serial order only where one needs another's result.",
         "Fired when %d or more sub-agents of %d s or more run back to back (serial_agents_n, serial_agent_s). Counted %d." % (ADV["serial_agents_n"], ADV["serial_agent_s"], best_chain), lost_s=ser_s, group="Sub-agents")
    full = [c for c in cs["done"] if c["name"] == "Bash" and c["script"] in FULL_TEST_SCRIPTS]
    fmed = _median([c["dur"] for c in full])
    rule((len(full) / ADV["full_test_n"]) if fmed >= ADV["full_test_s"] else 0, "speed", "Full test runs where impacted tests would do",
         "The full suite ran %d times, median %s, %s in total." % (len(full), fmt_dur(fmed), fmt_dur(sum(c["dur"] for c in full))),
         "Every full run re-proves code that did not change.",
         "Run only the tests that touch the change after each slice, the whole suite at build complete and before a deploy.",
         "Fired when the full suite runs %d or more times with a median of %d s or more (full_test_n, full_test_s)." % (ADV["full_test_n"], ADV["full_test_s"]),
         lost_s=sum(c["dur"] for c in full) - (fmed if full else 0))
    so = cs["slice_out"]
    rule(len(so) / ADV["slice_outlier_n"] if cs["slice_med"] else 0, "speed", "Slow slices",
         "%d exec.sh run(s) took more than %.0fx the median slice (median %s over %d slices; slowest %s)." % (len(so), ADV["slice_outlier_x"], fmt_dur(cs["slice_med"]), len(cs["slices"]), fmt_dur(max([c["dur"] for c in so] or [0]))),
         "An outlier slice is where the time went; the rest are routine.",
         "Open the outlier's BUILD-LOG row: if it was a gate or build repeating, fix that step; if it was one large script, split it.",
         "Fired when %d or more slices exceed %.1fx the median (slice_outlier_x, slice_outlier_n)." % (ADV["slice_outlier_n"], ADV["slice_outlier_x"]),
         lost_s=sum(c["dur"] - cs["slice_med"] for c in so), inherent=True)
    fired.sort(key=lambda d: (-d["impact"], -d["ratio"]))
    for d in fired + quiet:
        d["lost"] = lostfmt(d["lost_s"], d["lost_tok"])
    health = run_health(cs)
    return fired[:ADV["max_items"]], quiet + fired[ADV["max_items"]:], health, cs, hidden[0]

# tabs: without JavaScript every section shows, one page as before; the chosen tab survives the 30 s reload
TABS_JS = ("(function(){var b=document.body,tabs=[].slice.call(document.querySelectorAll('section.tab')),links=[].slice.call(document.querySelectorAll('.tabbar a[data-tab]'));if(!tabs.length)return;\n"
  "var K='pr-tab:'+location.pathname;function get(){try{return sessionStorage.getItem(K)}catch(e){return null}}\n"
  "function show(id){tabs.forEach(function(t){t.classList.toggle('on',t.id===id)});links.forEach(function(l){l.classList.toggle('on',l.getAttribute('data-tab')===id)});try{sessionStorage.setItem(K,id)}catch(e){}}\n"
  "window.__prShow=show;b.classList.add('tabbed');var s=get();show(s&&document.getElementById(s)?s:tabs[0].id);\n"
  "links.forEach(function(l){l.addEventListener('click',function(e){e.preventDefault();b.classList.remove('all');show(l.getAttribute('data-tab'));window.scrollTo(0,0)})});\n"
  "document.addEventListener('click',function(e){var t=e.target.closest&&e.target.closest('button[data-cmd]');if(!t)return;var c=t.getAttribute('data-cmd'),l=t.textContent;\n"
  " function fb(){try{var x=document.createElement('textarea');x.value=c;document.body.appendChild(x);x.select();var ok=document.execCommand('copy');x.remove();return ok}catch(_){return false}}\n"
  " function done(ok){t.textContent=ok?'Copied: paste in your terminal':'Copy failed: use the command below';setTimeout(function(){t.textContent=l},2000)}\n"
  " if(navigator.clipboard&&navigator.clipboard.writeText)navigator.clipboard.writeText(c).then(function(){done(true)},function(){done(fb())});else done(fb())});\n"
  "var a=document.getElementById('showall');if(a)a.addEventListener('click',function(e){e.preventDefault();b.classList.toggle('all');a.textContent=b.classList.contains('all')?'Tabs':'Show all'});})();\n")
JS = "<script>\n" + TABS_JS + 'function openTarget(){var h=location.hash.slice(1);if(!h)return;var e=document.getElementById(h);if(!e)return;\n var t=e.closest&&e.closest(\'section.tab\');if(t&&window.__prShow){window.__prShow(t.id);if(t!==e)setTimeout(function(){e.scrollIntoView()},0);}\n var ph=null;for(var d=e;d;d=d.parentElement&&d.parentElement.closest(\'details\'))if(d.tagName===\'DETAILS\'){d.open=true;if(!ph&&d.classList&&d.classList.contains(\'ph\'))ph=d}\n if(ph)[].forEach.call(document.querySelectorAll(\'details.ph[open]\'),function(o){if(o!==ph)o.open=false});}\nwindow.addEventListener(\'hashchange\',openTarget);openTarget();\ndocument.addEventListener(\'toggle\',function(ev){var t=ev.target;if(!t.open||!t.classList||!t.classList.contains(\'ph\'))return;[].forEach.call(document.querySelectorAll(\'details.ph[open]\'),function(o){if(o!==t)o.open=false})},true);\n' + "</script>"
# ----------------------------------------------------------------- render
CSS = """
:root{--bg:#f6f7f9;--card:#fff;--ink:#1c2430;--mut:#667085;--line:#e3e7ee;--accent:#2f6fed;--ok:#1f9d63;--warn:#d98a0b;--bad:#c93c3c;--idle:#d9dde5;--main:#2f6fed;--sub:#8b5cf6;--soft:#eef2fb;--shadow:0 1px 2px rgba(20,30,50,.06)}
@media(prefers-color-scheme:dark){:root{--bg:#12161c;--card:#1a2029;--ink:#e6eaf0;--mut:#98a2b3;--line:#2a3340;--accent:#6b9bff;--ok:#3fc283;--warn:#e6a23c;--bad:#ef6b6b;--idle:#2d3542;--main:#6b9bff;--sub:#a78bfa;--soft:#202838;--shadow:none}}
*{box-sizing:border-box}html{-webkit-text-size-adjust:100%}
body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.45 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif}
main{max-width:1280px;margin:0 auto;padding:16px}
h1{font-size:24px;margin:0 0 2px}h2{font-size:18px;margin:32px 0 4px}h3{font-size:15px;margin:0}
.sub{color:var(--mut);font-size:13px}.mut{color:var(--mut)}
a{color:var(--accent);text-decoration:none}a:hover{text-decoration:underline}
.card,.rail>*,.adv>*,.phases>*{min-width:0}.chip,dd,.sub,.adv p{overflow-wrap:anywhere}.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:14px;box-shadow:var(--shadow)}
.kpis{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:10px;margin:14px 0}
.kpi .v{font-size:22px;font-weight:650}.kpi .l{font-size:12px;color:var(--mut)}
.bar{height:8px;border-radius:5px;background:var(--idle);overflow:hidden}.bar>i{display:block;height:100%;background:var(--accent)}
.bar.big{height:14px}.bar.ok>i{background:var(--ok)}
.rail{display:grid;grid-template-columns:repeat(auto-fill,minmax(290px,1fr));gap:12px;margin-top:10px}
.stage{display:flex;flex-direction:column;gap:8px;border-top:4px solid var(--idle)}
.stage.passed{border-top-color:var(--ok)}.stage.progress{border-top-color:var(--accent)}.stage.waived{border-top-color:var(--warn)}.stage.pre{opacity:.85}
.hd{display:flex;flex-wrap:wrap;justify-content:space-between;align-items:flex-start;gap:4px 8px}.hd h3{min-width:0;flex:1 1 220px}.hd .sub{white-space:nowrap;overflow-wrap:normal}
.badge{font-size:11px;padding:2px 8px;border-radius:99px;background:var(--soft);white-space:nowrap;font-weight:600}
.passed .badge{color:var(--ok)}.progress .badge{color:var(--accent)}.waived .badge{color:var(--warn)}
dl{display:grid;grid-template-columns:auto minmax(0,1fr);gap:3px 10px;margin:0;font-size:13px}dt{color:var(--mut)}dd{margin:0;text-align:right}
.chips{display:flex;flex-wrap:wrap;gap:5px}.chip{font-size:12px;padding:2px 8px;border-radius:6px;background:var(--soft);display:inline-block}
.chip.miss{color:var(--mut);border:1px dashed var(--line);background:transparent}
.dec span{font-size:12px;padding:1px 7px;border-radius:5px;margin-right:4px;background:var(--soft)}
.c{color:var(--ok)}.a{color:var(--warn)}.r{color:var(--bad)}
details{margin-top:2px}summary{cursor:pointer;font-size:13px;color:var(--mut)}
table{border-collapse:collapse;width:100%;font-size:13px}th,td{padding:5px 8px;border-bottom:1px solid var(--line);text-align:left;vertical-align:top}
th{font-size:12px;color:var(--mut);font-weight:600}td.n,th.n{text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap}
.tw{overflow-x:auto}
svg text{fill:var(--ink);font-size:11px}svg .m{fill:var(--mut)}
.legend{display:flex;gap:14px;flex-wrap:wrap;font-size:12px;color:var(--mut);margin:6px 0}.legend b{display:inline-block;width:10px;height:10px;border-radius:2px;margin-right:5px;vertical-align:-1px}
.adv{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:10px}.adv .card{padding:12px}.adv h3{font-size:13px;color:var(--accent);margin-bottom:3px}.adv p{margin:0;font-size:13px}
.phases{display:grid;grid-template-columns:repeat(auto-fill,minmax(210px,1fr));gap:10px}
.ph b{font-size:13px}.ph .k{font-size:11px;color:var(--mut);margin-top:4px}
.stack3{display:flex;height:8px;border-radius:5px;overflow:hidden;background:var(--idle)}.stack3>i{display:block;height:100%}.stack3 .b{background:var(--ok)}.stack3 .p{background:var(--warn)}
.ph.now{border-color:var(--accent);box-shadow:0 0 0 1px var(--accent)}.nowtag{font-size:11px;color:var(--accent);font-weight:600;margin-left:4px}
.stale{color:var(--warn)}.r-partial td:last-child{color:var(--warn)}.r-built td:last-child{color:var(--ok)}
.stack{display:flex;height:16px;border-radius:5px;overflow:hidden;background:var(--idle)}.stack>i{display:block;height:100%}
.note{font-size:12px;color:var(--mut);margin:4px 0}
html{scroll-behavior:smooth}[id^=stage-],[id^=agents-],[id^=phase-],#stages,#build-detail,#tips,#pages{scroll-margin-top:56px}
.snav{position:sticky;top:0;z-index:20;background:var(--bg);border-bottom:1px solid var(--line);padding:8px 16px;display:flex;gap:6px;align-items:center;flex-wrap:wrap}
.snav a{min-width:34px;text-align:center;padding:4px 10px;border-radius:8px;background:var(--card);border:1px solid var(--line);font-weight:650;font-size:13px;color:var(--ink)}
.snav a:hover{text-decoration:none;border-color:var(--accent)}
.hd h3 a{color:inherit}.updated{display:inline-block;margin-top:6px;padding:3px 10px;border-radius:8px;background:var(--soft);font-size:13px;font-weight:600}
.tabbar{display:none;margin-left:auto;gap:4px;flex-wrap:wrap}body.tabbed .tabbar{display:flex}body.tabbed .snav>a{display:none}.tabbar a{padding:3px 10px;border-radius:999px;text-decoration:none;color:var(--ink);border:1px solid var(--line)}.tabbar a.on{background:var(--accent);border-color:var(--accent);color:#fff}#showall{color:var(--mut);border-style:dashed}
body.tabbed:not(.all) section.tab:not(.on){display:none}body.all section.tab{border-top:1px solid var(--line);margin-top:24px}section.tab .side{position:static;max-height:none;margin-top:24px}
button.filebtn{font:inherit;font-size:13px;cursor:pointer;border:1px solid var(--accent)}.filebtn{display:inline-block;padding:3px 10px;border-radius:6px;background:var(--accent);color:#fff;text-decoration:none;white-space:nowrap;margin:2px 0}.filebtn.alt{background:transparent;color:var(--accent);border:1px solid var(--accent)}.crs td{vertical-align:top}.crst{display:inline-block;padding:1px 8px;border-radius:999px;font-size:12px;border:1px solid currentColor}.cr-waiting{color:var(--warn)}.cr-built{color:var(--accent)}.cr-proven{color:var(--ok)}.cr-closed{color:var(--mut)}
.layout{display:grid;grid-template-columns:minmax(0,1fr) 340px;gap:16px;align-items:start}.layout.solo{display:block}.content{min-width:0}.side{position:sticky;top:52px;max-height:calc(100vh - 64px);overflow:auto;padding-right:2px}.side h2{margin-top:0}.health{margin-top:8px}.health .hi{font-size:13px;margin-top:3px}.grp{margin-top:8px;border:1px solid var(--line);border-radius:10px;background:var(--card)}.grp>summary{cursor:pointer;padding:9px 12px;font-size:14px}.grp .speed,.grp>.split,.grp>div,.grp .tip{padding:0 12px 10px}.tip{border-top:1px solid var(--line);padding-top:10px}.tip h3{font-size:13px;margin:0 0 4px}.tip p{margin:0 0 4px;font-size:12.5px}.p-info{background:#8793a6;color:#fff}@media(max-width:1000px){.layout{grid-template-columns:minmax(0,1fr)}.side{position:static;max-height:none}}.dot{display:inline-block;width:9px;height:9px;border-radius:50%;margin-right:4px}.p-green{background:#2e9e5b;color:#fff}.p-amber{background:#e0a100;color:#fff}.p-red{background:#d1383d;color:#fff}.pill{padding:1px 9px;margin-left:6px;border-radius:99px;font-size:12px}.speed{margin-top:8px;font-size:13px}.split{display:flex;gap:2px;margin:6px 0}.seg{background:var(--accent);color:#fff;font-size:11px;padding:3px 6px;border-radius:4px;white-space:nowrap;overflow:hidden}.seg:nth-child(2){opacity:.75}.seg:nth-child(3){background:var(--idle);color:var(--ink)}.seg:nth-child(4){opacity:.55}.muted{color:var(--mut);font-size:12px}\n.advl{display:grid;grid-template-columns:repeat(auto-fit,minmax(340px,1fr));gap:10px;margin-top:8px}
.advi{border-left:4px solid var(--warn)}.advi.hi{border-left-color:var(--bad)}.advi .rk{font-size:12px;color:var(--mut)}.advi h3{margin:2px 0 6px}.advi p{margin:4px 0;font-size:13px}.advi .why{color:var(--mut);font-size:12px}
details.ph>summary{list-style:none;cursor:pointer;color:var(--ink)}details.ph>summary::-webkit-details-marker{display:none}
details.ph[open]{grid-column:1/-1;border-color:var(--accent);box-shadow:0 0 0 1px var(--accent);background:var(--soft)}.steps td{font-size:12px;padding:3px 6px}
.nolog{margin:10px 0;font-size:13px}.note-card{margin-top:14px;border-left:4px solid var(--warn)}.live{font-size:12px;color:var(--muted)}.live a{color:inherit}details.how{margin:10px 0;font-size:13px;color:var(--muted)}details.how summary{cursor:pointer}
.frag h2{font-size:16px;margin:24px 0 4px}.frag h3{margin:14px 0 2px}.frag .scroll{overflow-x:auto}
.frag .lede{font-size:14px}.frag .empty{color:var(--mut)}.frag code{font-size:12px}
.frag .st-built,.ph .st-built,.frag .done,.frag .CLEAN{color:var(--ok)}.frag .st-progress,.ph .st-progress,.frag .in-progress,.frag .INCOMPLETE{color:var(--warn)}
.frag .st-todo,.ph .st-todo,.frag .pending{color:var(--mut)}.frag .st-person,.ph .st-person{color:#8b5cf6}.frag .st-unknown,.ph .st-unknown{color:var(--mut);font-style:italic}
.frag .FINDINGS,.frag .drift,.ph .drift{color:var(--bad)}.frag .drift,.ph .drift{font-size:12px}.ph .claims{font-size:12px}.frag .claims{font-size:12px}.frag .warn summary{color:var(--warn)}
.frag .badge,.ph .badge{margin-left:6px;border:1px solid currentColor;background:transparent}
.pages .tree{margin-top:6px;font-size:13px}.pg{display:grid;grid-template-columns:minmax(120px,220px) minmax(0,1fr);gap:2px 12px;padding:5px 0;border-bottom:1px solid var(--line)}.pg:last-child{border-bottom:0}
.pg .dir{font-weight:600;overflow-wrap:anywhere}.pg ul{list-style:none;margin:0;padding:0;display:flex;flex-wrap:wrap;gap:3px 14px}.pg li{overflow-wrap:anywhere}.pg details{margin:0}.pg details ul{margin-top:4px}
footer{margin-top:36px;font-size:13px;color:var(--mut)}footer li{margin:3px 0}
@media(max-width:520px){code,pre,.stage dd,.stage dt{overflow-wrap:anywhere;min-width:0}.stage dl{grid-template-columns:minmax(0,1fr)}.stage dd{text-align:left}.hd .sub{white-space:normal;flex:1 1 100%}.snav{padding:6px 12px;flex-wrap:nowrap;overflow-x:auto;max-width:100%}.snav a{flex:0 0 auto}.updated{max-width:100%;overflow-wrap:anywhere}.advl{grid-template-columns:minmax(0,1fr)}.pg{grid-template-columns:minmax(0,1fr)}.kpis{grid-template-columns:repeat(2,minmax(0,1fr))}.rail{grid-template-columns:minmax(0,1fr)}main{padding:12px}h1{font-size:20px}.kpi .v{font-size:19px}}
"""
KC = {"BRIEF": "#8b5cf6", "BUILD": "#2f6fed", "PROVE": "#1f9d63", "HARNESS": "#d98a0b", "RUN": "#c93c3c"}

def stage_state(s, info, gate):
    g = gate["rows"].get(s, {}).get("status", "")
    if g == "WAIVED": return "waived"
    if info["has_md"] and info["passed"] or info["current"]:
        if s in info["passed"]: return "passed"
        return "progress" if s == info["current"] else "pending"
    return {"PASS": "passed", "PENDING": "pending"}.get(g, "pending")

def ago(t):
    d = time.time() - t
    if d < 0: return "just now"
    return ("%d min ago" % max(1, round(d / 60))) if d < 5400 else ("%.0f h ago" % (d / 3600)) if d < 172800 else ("%d days ago" % round(d / 86400))

def render_ledgers(w, lg):
    w("<div class='card ledgers'><div class=hd><h3>Time and effort from the project ledgers</h3><span class=sub>source: %s; not a session log</span></div>" % ", ".join(esc(x) for x in lg["sources"]))
    k = []
    if lg["phases"]:
        mins = [p["min"] for p in lg["phases"] if p["min"] is not None]; toks = [p["tok"] for p in lg["phases"] if p["tok"]]
        k.append(("Minutes logged", "%s" % fmt_dur(sum(mins) * 60) if mins else "n/a", "TIME-LEDGER.md (optional, hand written), finished phases"))
        if toks: k.append(("Sub-agent tokens", fmt_tok(sum(toks)), "TIME-LEDGER.md; lead session not counted"))
    w("<div class=kpis>" + "".join("<div class='card kpi'><div class=v>%s</div><div class=l>%s<br>%s</div></div>" % (esc(v), esc(l), esc(sm)) for l, v, sm in k) + "</div>")
    if lg["phases"]:
        w("<div class=tw><table><tr><th>Phase</th><th>Start</th><th class=n>Minutes</th><th class=n>Sub-agent tokens</th><th>Exec runs</th></tr>" + "".join(
          "<tr><td>%s</td><td>%s</td><td class=n>%s</td><td class=n>%s</td><td>%s</td></tr>" % (esc(p["phase"]), esc(p["start"]), esc(p["min_txt"] or "-"), esc(p["tok_txt"] or "-"), esc(p["runs"] or "-")) for p in lg["phases"]) + "</table></div>")
    w("</div>")

def signoff_html(p):
    """The phase card's module sign-off line(s): one per module whose last verify row is here."""
    out = []
    for m in p.get("signoffs") or []:
        drift = m["form"] == "claimed" or m["detail"].startswith("State says")
        out.append("<div class='k signoff' data-module='%s'>Module sign-off, %s (row %s): <span class='%s'>%s</span>%s</div>" % (
            esc(m["mod"]), esc(m["mod"]), esc(m["n"]), SIGNOFF_CLS.get(m["form"], "st-todo"), esc(m["label"]),
            ("<div class=drift>&#9888; %s</div>" if drift else " <span class=mut>(%s)</span>") % esc(m["detail"]) if m["detail"] else ""))
    return "".join(out)

def signoff_suffix(bp):
    """', k of n modules signed off' after a build count, '' when the plan has no verify row. Held is not signed off."""
    so = (bp or {}).get("signoffs") or []
    return ", %d of %d module%s signed off" % (sum(1 for m in so if m["form"] == "verified"), len(so), "" if len(so) == 1 else "s") if so else ""

def phase_bar(p, runs):
    """The phase card's bar and count; a phase of HARNESS rows only has no build rows to count."""
    if not p["n"] and p.get("harness"): return "<div class=sub>Sign-off phase: no build rows</div>"
    return "<div class='stack3' style='margin:6px 0'><i class=b style='width:%.0f%%'></i><i class=p style='width:%.0f%%'></i></div><div class=sub>%d of %d rows built%s%s</div>" % (
        pct(p["built"], p["n"]), pct(p["partial"], p["n"]), p["built"], p["n"], (", %d partial" % p["partial"]) if p["partial"] else "", (" &middot; %d runs" % runs) if runs else "")

def signoff_rollup(bp):
    """One line under the plan counts: module sign-offs and other HARNESS rows, never counted as built rows."""
    so = bp.get("signoffs") or []
    other = sum(1 for p in bp["phases"] for x in p["steps"] if x["cls"] == "harness")
    if not so and not other: return ""
    v = sum(1 for m in so if m["form"] == "verified")
    txt = ("Module sign-offs: %d of %d module%s verified, each shown on its phase card." % (v, len(so), "" if len(so) == 1 else "s")) if so else ""
    if other: txt += (" " if txt else "") + "%d other HARNESS row%s listed in %s phase, not counted." % (other, "" if other == 1 else "s", "its" if other == 1 else "their")
    return "<div class=note id=signoffs>%s HARNESS rows are a module's sign-off or a harness pass, not build rows, so the counts above leave them out.</div>" % txt

def render(proj, info, gate, manifest, arts, main, agents, rates, bp, an, adv, tot, peak, args):
    L = args.has_log
    facts = exec_facts(proj, bp)
    if not L: stage_switch(info, [], None)   # no session log: the same function, from the exec log alone
    def href(f): return urllib.parse.quote(os.path.relpath(f, args.outdir).replace(os.sep, "/"))
    S = an["S"]; wall = (an["t1"] - an["t0"]) if L else 0
    if wall > 86400: TICK_FMT[0] = "%d %b %H:%M"
    idle_s = sum(y - x for x, y in an["idle"]) if L else 0
    nsub = len(agents); nwf = sum(1 for a in agents if a["wf"])
    states = {s: stage_state(s, info, gate) for s in STAGES}
    # progress per stage
    prog = {}; owed_txt = {}
    for s in STAGES:
        owed = [o for o in arts[s]["owed"] if o["absence"] != "optin" or o["found"]]
        have = sum(1 for o in owed if o["found"]); n = len(owed)
        if states[s] in ("passed", "waived"): prog[s] = 100.0
        elif s == "5" and bp and bp["total"]: prog[s] = pct(bp["built"], bp["total"])
        elif states[s] == "progress": prog[s] = min(pct(have, n), 95.0) if n else 0.0
        else: prog[s] = 0.0
        owed_txt[s] = "%d of %d promised artifacts present" % (have, n) if n else "no manifest rows"
        if s == "5" and bp and bp["total"] and states[s] not in ("passed", "waived"): owed_txt[s] = "%d of %d plan rows built%s%s" % (bp["built"], bp["total"], (", %d partial" % bp["partial"]) if bp["partial"] else "", signoff_suffix(bp))
    overall = sum(prog.values()) / len(STAGES)
    npass = sum(1 for s in STAGES if states[s] == "passed")
    dec = {s: collections.Counter(d[2] for d in info["decisions"] if d[0] == s) for s in STAGES}
    cost_note = "estimate at placeholder list prices"
    unp = any(S[s][p].get("unpriced") for s in S for p in ("main", "sub", "wf"))
    def money(c): return "n/a" if unp else "$%.0f" % c
    cost_all = sum(S[s][p]["cost"] for s in S for p in ("main", "sub", "wf"))
    H = []; w = H.append
    gen_epoch = time.time()
    gen = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    w("<!doctype html><html lang=en><head><meta charset=utf-8><meta name=viewport content='width=device-width,initial-scale=1'>")
    w("<!-- generated-by: mxcli-project-toolkit/project-bin/build-plan-status.sh (progress-report.py) -->")
    w("<title>Progress report: %s</title><style>%s</style></head><body>" % (esc(info["name"]), CSS))
    # One group of section links (issue #479): the bar without JavaScript. With JavaScript the tab bar replaces them
    # (body.tabbed hides the plain links). The current stage is in the header line below, and the #stage-N card
    # anchors stay for links from other pages; a link into a hidden tab switches to that tab first.
    w("<nav class=snav aria-label='Page sections'><a href='#stages'>Stages</a><a href='#build-detail'>Build</a><a href='#pages'>Pages</a>" + ("<a href='#tips'>Tips</a>" if L else "") + "<span class=tabbar role=tablist>" + "".join("<a href='#%s' data-tab='%s' role=tab>%s</a>" % (t_, t_, n_) for t_, n_ in TABS) + "<a href='#' id=showall title='Every tab on one page, for searching and printing'>Show all</a></span></nav><main><div class='layout solo'><div class=content>")
    last_ev = datetime.datetime.fromtimestamp(an["t1"]).strftime("%Y-%m-%d %H:%M") if L else "no session log"
    w("<header><h1>Progress report: %s</h1>" % esc(info["name"]))
    w("<span class=updated id=stamp data-stamp>Last updated %s %s</span> <span class=sub id=lastevent data-stamp>session log last event %s</span>%s<br>" % (gen, datetime.datetime.now().astimezone().strftime("%Z"), last_ev,
      " <span class=live>&middot; <span id=livetxt>Live &middot; refreshes every 30 s</span> &middot; <a href='#' id=livebtn>Pause</a></span>" if args.reload else ""))
    nowstage = ("<a href='#stage-%s'>Stage %s: %s</a>" % (info["current"], info["current"], esc(STAGE_NAME[info["current"]]))) if info["current"] in STAGE_NAME else "unknown"
    w("<div class=sub><span class=nowstage>Current stage: %s</span> &middot; Stage P to 6 &middot; entry mode %s &middot; <a href='%s'>PROJECT.md</a> &middot; <a href='%s'>gate-check page</a></div></header>" %
      (nowstage, esc(info["entry_mode"]), href(os.path.join(proj, "PROJECT.md")), href(os.path.join(proj, "index.html"))))
    how_parts = []
    if L and DISCOVERY.get("mention") and not args.session_log:
        rows = "".join("<tr><td><code>%s</code></td><td>%s</td><td class=n>%d%%</td></tr>" % (esc(u["id"]), datetime.datetime.fromtimestamp(u["t"]).strftime("%Y-%m-%d"), round(u["share"] * 100)) for u in sorted(DISCOVERY.get("used", []), key=lambda u: u["t"]))
        how_parts.append("<p><b>Sessions from other folders (%d).</b> Counted when at least %d%% of a session's tool calls, and at least %d of them, operate on this project's path; only the time between those calls counts, gaps over %d minutes are cut. Words in text never count. Pass <code>--session-log &lt;path&gt;</code> to replace discovery.</p><div class=tw><table><tr><th>Session</th><th>Date</th><th>Share of tool calls on the project</th></tr>%s</table></div>" % (len(DISCOVERY["mention"]), round(TOOL_SHARE * 100), TOOL_MIN, SPAN_GAP_S // 60, rows))
    if SWITCH.get("inferred"):
        how_parts.append("<p><b>Stage switch inferred.</b> The Stage 4 sign-off row gives a date (%s) without a time, so the switch to Stage 5 is %s, the earliest build activity on or after it (source: %s). Stage 4 time includes that day's planning.</p>" % (datetime.datetime.fromtimestamp(SWITCH["day"]).strftime("%Y-%m-%d"), local_hm(SWITCH["t"]), esc(SWITCH.get("src", "the build activity"))))
    if facts: how_parts.append("<p><b>Build runs</b> come from %s (UTC in the file, shown in local time); a run counts as passed when the script was applied.</p>" % esc(facts["src"]))
    if not L:
        dsc = DISCOVERY
        looked = (" Looked in this project's own log folder and %d other project folders (%d logs from the last %d days)." % (dsc.get("other_dirs", 0), dsc.get("other_files", 0), SCAN_DAYS)) if dsc.get("searched") and not args.no_log else ""
        howto = (" To use a log from another place pass it with <code>--session-log &lt;path&gt;</code> (a .jsonl file, or a folder of them, for example <code>~/.claude/projects/&lt;slug&gt;/</code>), then regenerate: <code>project-bin/build-plan-status.sh &lt;project&gt; --html --session-log &lt;path&gt;</code>.") if not args.no_log else ""
        ledgers = (" Build runs below come from the exec log (%s); tokens and cost need a session log." % ", ".join("<code>%s</code>" % esc(x) for x in args.ledgers["sources"])) if args.ledgers else ""
        how_parts.append("<p><b>No session log.</b> %s%s%s%s</p>" % (esc(args.log_note), looked, howto, ledgers))
    if how_parts: w("<details class=how id=how><summary>How this was measured</summary>%s</details>" % "".join(how_parts))
    if not L:
        w("<p class=nolog>%s Time, token and cost figures are not shown; everything else is (details in How this was measured).</p>" % esc(args.log_note))
    PERF = []
    if not L and args.ledgers and args.ledgers["phases"]: render_ledgers(PERF.append, args.ledgers)
    w("<section class=tab id=tab-overview>")
    w("<div class='card' style='margin-top:14px'><div class=hd><h3><a href='#stage-%s'>%s</a></h3><span class=sub>%d of 8 gates passed%s</span></div>" % (info["current"] or "P", esc(info["current_line"] or "Current stage unknown"), npass, (", %d waived" % sum(1 for s_ in STAGES if states[s_] == "waived")) if "waived" in states.values() else ""))
    w("<div class='bar big ok' style='margin:8px 0' title='mean of the eight stage bars'><i style='width:%.0f%%'></i></div>" % overall)
    w("<div class=sub>Overall progress %.0f%%: mean of the stage bars below (passed or waived stage = 100, current stage = promised artifacts present, Stage 5 = plan rows built).</div></div>" % overall)
    if gate["mtime"] and info["has_md"]:
        gp = [s for s in STAGES if gate["rows"].get(s, {}).get("status") == "PASS"]
        if set(gp) != set(info["passed"]):
            w("<p class='note stale'>Note: the gate-check page (index.html) lists passed stages %s, this page counts %s (PROJECT.md stage line and sign-off rows%s). Re-run gate-check to refresh the page.</p>" % (esc(", ".join(gp) or "none"), esc(", ".join(info["passed"]) or "none"), ", newer than the page" if info.get("gate_stale_s") else ""))
    # KPIs
    allc = [m["in"] + m["cr"] + m["cw"] for m in main["msgs"]] or [0]; ctx_avg = sum(allc) / len(allc)
    cwin, cnote = context_window(main["msgs"], main["compacts"], main.get("flag_1m", False))
    pw = lambda a_: ctx_pct_txt(a_, cwin)
    nart = sum(len(arts[s_]["files"]) for s_ in STAGES); ndec = len(info["decisions"])
    chg = info.get("changes", []); waiting = [c for c in chg if c["status"] in ("open", "refined", "agreed")]
    kp0 = [("Gates passed", "%d of 8" % npass, "stages P to 6, from PROJECT.md"), ("Plan rows built", ("%d of %d" % (bp["built"], bp["total"])) if bp and bp["total"] else "none yet", "from architecture/build-plan.md" + signoff_suffix(bp)),
           ("Changes waiting", ("%d of %d" % (len(waiting), len(chg))) if chg else "none logged", "open, refined or agreed in the Change log"),
           ("Artifacts present", "%d" % nart, "files found for the eight stages"), ("Decisions", "%d" % ndec, "rows in the PROJECT.md register")]
    kp = [] if not L else [("Wall time", fmt_dur(wall), "first to last event in the session"), ("Waiting for you", fmt_dur(idle_s), "gaps over %d min" % (IDLE_GAP_S // 60)),
          ("New tokens", fmt_tok(head(tot)), "input + output + cache write"), ("Cache reads", fmt_tok(tot["cr"]), "billed at a fraction"),
          ("Est. cost", money(cost_all), cost_note), ("Sub-agents", "%d" % nsub, "%d of them in %d workflow run(s)" % (nwf, len({a["wf_id"] for a in agents if a["wf"]}))),
          ("Context avg / peak", "%s / %s" % (fmt_tok(ctx_avg), fmt_tok(peak)), "per main request, " + (("window %s" % fmt_tok(cwin) + (" (%s)" % cnote if cnote else "")) if cwin else "window unknown")), ("Compactions", "%d" % len(main["compacts"]), "automatic context summaries"),
          ("Your prompts", "%d" % main["prompts"], "typed messages, text not read into this page")]
    kpis = lambda k_: "<div class=kpis>" + "".join("<div class='card kpi'><div class=v>%s</div><div class=l>%s</div><div class='l'>%s</div></div>" % (esc(v), esc(l), esc(n)) for l, v, n in k_) + "</div>"
    w(kpis(kp0))
    if kp: PERF.append("<h2>Session totals</h2>" + kpis(kp))
    # tips and tricks: a narrow side column, one collapsed box per theme, calm severity, actionable tips only
    aside = ""
    if L:
        fired, quiet, health, cs, n_inherent = args.adv2
        overall, items = health
        WORD = {"green": "OK", "amber": "Worth a look", "red": "Needs action"}
        sp = cs["split"]; wl = sp["wall"] or 1
        slow = "".join("<li>%s <span class=muted>%s, %s</span></li>" % (esc(callname(c)), fmt_dur(c["dur"]), esc(stage_label(an, c["t0"]))) for c in cs["slow"])
        sls = cs["slices"]; so = ", ".join("%s (%s, %s)" % ("slice " + str(sls.index(c) + 1), fmt_dur(c["dur"]), stage_label(an, c["t0"])) for c in cs["slice_out"][:3])
        speed = ("<div class=split>" + "".join("<span class=seg style='flex:%.3f' title='%s'>%.0f%%</span>" % (max(sp[k] / wl, 0.04), lab, 100 * sp[k] / wl) for k, lab in (("tool", "tool runs"), ("think", "model thinking"), ("user", "waiting on you"), ("ci", "CI and background"))) + "</div>"
                 "<div class=muted>Tool runs, model thinking, waiting on you, CI and background; %s wall time, approximate. Median slice %s over %d slice(s)%s.</div><div><b>Slowest calls</b><ol>%s</ol></div>" % (fmt_dur(wl), fmt_dur(cs["slice_med"]), len(sls), ("; outliers: " + esc(so)) if so else "", slow or "<li>none recorded</li>"))
        ORDER = ["Context", "Tokens and cost", "Speed", "Health", "Sub-agents"]; rank = {"red": 2, "amber": 1, "info": 0}
        parts = ["<aside class=side id=tips aria-label='Tips and tricks'><h2>Tips and tricks</h2><div class=sub>Only patterns with a concrete action in this project, ranked by time or tokens lost. Numbers only, no message text. Thresholds are in the ADV block of the script.</div>"]
        parts.append("<div class='card health'><b>Run health</b> <span class='pill p-%s'>%s</span>%s</div>" % (overall, WORD[overall], "".join("<div class=hi><i class='dot p-%s'></i><b>%s</b> %s</div>" % (lv, esc(n_), esc(v_)) for n_, lv, v_ in items)))
        for g in ORDER:
            tips = [d for d in fired if d["group"] == g]
            if not tips: continue   # an empty group is not shown at all, no count of 0
            worst = max((d["sev"] for d in tips), key=lambda x: rank[x])
            dot = "p-" + {"red": "red", "amber": "amber", "info": "info"}[worst]
            body = (speed if g == "Speed" else "") + "".join(
                "<div class='tip t-%s'><h3>%s</h3><p><b>Seen.</b> %s</p><p><b>Why it matters.</b> %s</p><p><b>Fix.</b> %s</p><p class=why>Lost: about %s. %s</p></div>" % (d["sev"], esc(d["title"]), esc(d["seen"]), esc(d["matters"]), esc(d["fix"]), esc(d["lost"] or "n/a"), esc(d["why"])) for d in tips)
            parts.append("<details class=grp><summary><i class='dot %s'></i><b>%s</b> <span class=muted>%d</span></summary>%s</details>" % (dot, g, len(tips), body))
        if not fired: parts.append("<div class='card muted'>No pattern crossed its threshold in this session.</div>")
        parts.append("<div class=muted>%d check(s) ran without needing action; %d more are inherent to how the toolkit and mxcli work (build time, required gates and reviews, waiting) and are never shown.</div></aside>" % (len(quiet), n_inherent))
        aside = "".join(parts)
    # stage rail
    w("<h2 id=stages>Stage rail: Kickoff (P) to Verify and report (6)</h2><div class=sub>Each card shows gate state, artifact progress%s, decisions and links.%s</div><div class=rail>" % (", wall time, tokens, sub-agents" if L else "", " Time and token splits per stage are approximate (see footer)." if L else ""))
    wins = {s: (a, b) for s, a, b in an["wins"]}
    for s in ["pre"] + STAGES:
        sd = S[s]
        if s == "pre":
            if "pre" not in wins: continue
            st = "pre"; title = "Before Stage P"; badge = "outside project"
        else:
            st = states[s]; title = "Stage %s: %s" % (s, STAGE_NAME[s]); badge = {"passed": "passed", "progress": "in progress", "pending": "pending", "waived": "waived"}[st]
        tm = sd["min"]; mins = sum(tm.values()); act = tm["main"] + tm["sub"]
        tk = zero()
        for p in ("main", "sub", "wf"):
            for k in ("in", "out", "cr", "cw", "cost"): tk[k] += sd[p][k]
        subn = sd["sub"]["n"] and len([a for a in sd["agents"] if not a["wf"]]); wfn = len([a for a in sd["agents"] if a["wf"]])
        subh = sum(head(a["tok"]) for a in sd["agents"])
        w("<div class='card stage %s' id='stage-%s'><div class=hd><h3><a href='%s' title='%s'>%s</a></h3><span class=badge>%s</span></div>" % (st, s, "#agents-" + s if L and sd["agents"] else "#stage-" + s, "Jump to the sub-agents of this stage" if L and sd["agents"] else "This stage", esc(title), esc(badge)))
        if s != "pre":
            w("<div><div class='bar %s' title='%s'><i style='width:%.0f%%'></i></div><div class=sub>%.0f%%: %s</div></div>" % ("ok" if st == "passed" else "", esc(owed_txt[s]), prog[s], prog[s], esc((owed_txt[s] + ("; gate not yet passed, bar capped at 95%" if st == "progress" else "")) if st in ("progress", "pending") else "gate " + st)))
        w("<dl>")
        cl = sd["ctx"]
        if L:
            w("<dt>Wall time</dt><dd>%s (%s active, %s waiting)</dd>" % (fmt_dur(mins * 60) if mins else "none", fmt_dur(act * 60), fmt_dur(tm["idle"] * 60)))
            w("<dt>New tokens</dt><dd>%s &middot; est. %s</dd>" % (fmt_tok(head(tk)) if tk["n"] or head(tk) else "none", money(tk["cost"])))
            w("<dt>Main context</dt><dd>%s</dd>" % ("avg %s, peak %s (%s of %s)" % (fmt_tok(sum(cl) / len(cl)), fmt_tok(max(cl)), pw(max(cl)), fmt_tok(cwin) if cwin else "unknown window") if cl else "no requests"))
            w("<dt>Sub-agents</dt><dd>%d + %d workflow &middot; %s tokens</dd>" % (subn, wfn, fmt_tok(subh) if sd["agents"] else "0"))
        if s == "5" and bp: w("<dt>Build progress</dt><dd><a href='#build-detail'>%d of %d rows built%s%s</a></dd>" % (bp["built"], bp["total"], (", %d partial" % bp["partial"]) if bp["partial"] else "", signoff_suffix(bp)))
        if s != "pre":
            c = dec[s]; w("<dt>Decisions</dt><dd class=dec><span class=c>%d confirmed</span><span class=a>%d assumed</span><span class=r>%d raised</span></dd>" % (c["CONFIRMED"], c["ASSUMED"], c["RAISED"]))
            if s == "2" and gate["extra"].get("raised"): w("<dt>BRD questions</dt><dd>%d raised</dd>" % gate["extra"]["raised"])
        w("</dl>")
        if L: w("<details><summary>Token breakdown</summary><dl><dt>Input</dt><dd>%s</dd><dt>Output</dt><dd>%s</dd><dt>Cache write</dt><dd>%s</dd><dt>Cache read</dt><dd>%s</dd><dt>Main thread</dt><dd>%s</dd><dt>Sub-agents</dt><dd>%s</dd></dl></details>" %
          (fmt_tok(tk["in"]), fmt_tok(tk["out"]), fmt_tok(tk["cw"]), fmt_tok(tk["cr"]), fmt_tok(head(sd["main"])), fmt_tok(subh)))
        if s != "pre":
            row = gate["rows"].get(s)
            if states[s] == "passed" and info.get("gate_stale_s") and (not row or row["status"] != "PASS"):
                age = time.time() - gate["mtime"]
                w("<div class='sub stale' title='PROJECT.md says this stage passed; the generated gate-check page is older than PROJECT.md and does not list it'>Gate-check page is %s old, re-run gate-check</div>" % (("%d days" % round(age / 86400)) if age >= 86400 else ("%d hours" % max(1, round(age / 3600)))))
            elif row:
                # a placeholder FAIL on a stage after the current one is just "not started yet": show it as pending, not as a failure
                rs = row["status"]
                if rs == "FAIL" and states[s] == "pending" and "placeholder" in row["detail"].lower() and info["current"] in STAGES and STAGES.index(s) > STAGES.index(info["current"]): rs = "PENDING"
                w("<div class=sub title='%s'>Gate-check page: <b>%s</b> %s</div>" % (esc(row["detail"]), esc(rs), esc(row["detail"][:110] + ("..." if len(row["detail"]) > 110 else ""))))
            files = list(arts[s]["files"].items()); prim = [(f, i) for f, i in files if link_kind(f) == "html"]; rest = [(f, i) for f, i in files if link_kind(f) != "html"]
            def chip(f, cls=""):
                return "<a class='chip %s' href='%s'>%s</a>" % (cls, href(f), esc(os.path.relpath(f, proj)))
            # collapse big groups of siblings (wireframes etc.)
            groups = collections.defaultdict(list)
            for f, i in prim: groups[os.path.dirname(f)].append(f)
            chips = []
            for d_, fl in groups.items():
                if len(fl) > 4: chips.append("<span class=chip>%s (%d html, see list)</span>" % (esc(os.path.relpath(d_, proj) + "/"), len(fl)))
                else: chips += [chip(f) for f in fl]
            w("<div class=chips>%s</div>" % ("".join(chips) or "<span class='chip miss'>no html artifact yet</span>"))
            miss = [o["id"] for o in arts[s]["owed"] if not o["found"] and o["absence"] != "optin"]
            more = [f for f, i in files if len(groups.get(os.path.dirname(f), [])) > 4 and link_kind(f) == "html"] + [f for f, i in rest]
            if more or miss:
                w("<details><summary>%d more files%s</summary><div class=chips style='margin-top:6px'>%s%s</div></details>" %
                  (len(more), (", %d owed and missing" % len(miss)) if miss else "", "".join(chip(f) for f in more),
                   "".join("<span class='chip miss'>%s</span>" % esc(m) for m in miss)))
        w("</div>")
    w("</div>")
    w("</section>")
    w_main = w; w = PERF.append
    if L:
        # where time went
        w("<h2>Where time went: wall clock by stage, activity and tokens</h2><div class=sub>Top band: stage (approximate). Middle: who was working. Bottom: new tokens per 10 minutes. Hours are local time.</div>")
        W, LH = 1000.0, 1000.0 / max(len(an["minutes"]), 1)
        tick_h = max(1, -(-len(an["minutes"]) // 600))
        svg = ["<div class=card><svg viewBox='0 0 1000 150' width='100%' role=img aria-label='Session timeline'>"]
        cols = {"P": "#7c8aa5", "0": "#6b9bd6", "1": "#4fb0a6", "2": "#7bb661", "3": "#d6a84a", "4": "#d98a5f", "5": "#c06c9a", "6": "#8b6cc0", "pre": "#b5bcc9"}
        for s, a, b in an["wins"]:
            x = (a - an["t0"]) / 60 * LH; ww = (b - a) / 60 * LH
            svg.append("<a href='#stage-%s'><title>%s</title><rect x='%.1f' y='6' width='%.1f' height='22' fill='%s'/><text x='%.1f' y='21' fill='#fff' style='fill:#fff;font-weight:600;cursor:pointer'>%s</text></a>" % (s if s != "pre" else "P", "Stage " + s, x, max(ww, 1), cols[s], x + 4, "" if ww < 14 else ("pre" if s == "pre" else s)))
        sc = {"idle": "var(--idle)", "main": "var(--main)", "sub": "var(--sub)"}
        i = 0; ms = an["minutes"]
        while i < len(ms):
            j = i
            while j + 1 < len(ms) and ms[j + 1][1] == ms[i][1]: j += 1
            svg.append("<rect x='%.1f' y='36' width='%.1f' height='34' fill='%s'/>" % (i * LH, (j - i + 1) * LH, sc[ms[i][1]])); i = j + 1
        bk = an["buckets"]; mx = max(bk.values()) if bk else 1; bw = 10 * LH
        for k, v in bk.items():
            h = 50.0 * v / mx; svg.append("<rect x='%.1f' y='%.1f' width='%.1f' height='%.1f' fill='var(--accent)' opacity='.8'/>" % (k * bw, 124 - h, max(bw - 1, 1), h))
        tt = datetime.datetime.fromtimestamp(an["t0"]).replace(minute=0, second=0, microsecond=0) + datetime.timedelta(hours=1)
        while tt.timestamp() < an["t1"]:
            x = (tt.timestamp() - an["t0"]) / 60 * LH
            svg.append("<line x1='%.1f' x2='%.1f' y1='74' y2='128' stroke='var(--line)'/><text class=m x='%.1f' y='142' text-anchor='middle'>%s</text>" % (x, x, min(x, 975), tt.strftime(TICK_FMT[0])))
            tt += datetime.timedelta(hours=tick_h)
        svg.append("<text class=m x='1000' y='84' text-anchor='end' style='font-size:10px'>tallest bar %s tokens / 10 min</text>" % fmt_tok(mx))
        svg.append("</svg><div class=legend><span><b style='background:var(--main)'></b>main agent only</span><span><b style='background:var(--sub)'></b>one or more sub-agents running</span><span><b style='background:var(--idle)'></b>waiting (gap over %d min)</span><span><b style='background:var(--accent)'></b>tokens per 10 min</span></div>" % (IDLE_GAP_S // 60))
        w("".join(svg))
        w("<div class=tw><table><tr><th>Stage</th><th>Window (local)</th><th class=n>Wall</th><th class=n>Main only</th><th class=n>Sub-agents active</th><th class=n>Waiting</th><th>Share of wall time</th></tr>")
        for s, a, b in an["wins"]:
            tm = S[s]["min"]; n = sum(tm.values()) or 1
            w("<tr><td>%s</td><td>%s to %s</td><td class=n>%s</td><td class=n>%s</td><td class=n>%s</td><td class=n>%s</td><td style='min-width:120px'><div class=stack><i style='width:%.1f%%;background:var(--main)'></i><i style='width:%.1f%%;background:var(--sub)'></i><i style='width:%.1f%%;background:var(--idle)'></i></div></td></tr>" %
              ("Before P" if s == "pre" else "<a href='#stage-%s'>Stage %s</a>" % (s, s), local_hm(a), local_hm(b), fmt_dur(n * 60), fmt_dur(tm["main"] * 60), fmt_dur(tm["sub"] * 60), fmt_dur(tm["idle"] * 60), pct(tm["main"], n), pct(tm["sub"], n), pct(tm["idle"], n)))
        w("</table></div></div>")
        # context over time
        w("<h2>Context size: main-thread context per request, over time</h2><div class=sub>Context = input + cache read + cache write of each main-thread request. Dashed line is the window (%s). Red marks are automatic compactions.</div>" % ((fmt_tok(cwin) + " for this model" + ("; " + cnote if cnote else "")) if cwin else "unknown: " + cnote))
        top = max([c for _, c in an["mctx"]] + ([cwin] if cwin else [1])) * 1.05; CW = 1000.0
        sv = ["<div class=card><svg viewBox='0 0 1000 110' width='100%' role=img aria-label='Main thread context over time'>"]
        pts = " ".join("%.1f,%.1f" % ((t - an["t0"]) / 60 * LH, 95 - 85 * c / top) for t, c in an["mctx"])
        sv.append("<polyline points='%s' fill='none' stroke='var(--accent)' stroke-width='1.5'/>" % pts)
        if cwin: yw = 95 - 85 * cwin / top; sv.append("<line x1='0' x2='1000' y1='%.1f' y2='%.1f' stroke='var(--bad)' stroke-dasharray='4 3' opacity='.7'/><text class=m x='2' y='%.1f' style='font-size:10px'>window %s</text>" % (yw, yw, yw - 3, fmt_tok(cwin)))
        for cp in main["compacts"]:
            if cp["t"]: x = (cp["t"] - an["t0"]) / 60 * LH; sv.append("<line x1='%.1f' x2='%.1f' y1='4' y2='95' stroke='var(--bad)' stroke-width='2'/><text x='%.1f' y='14' style='font-size:10px;fill:var(--bad)'>compact %s to %s</text>" % (x, x, min(x + 3, 800), fmt_tok(cp["pre"] or 0), fmt_tok(cp["post"] or 0)))
        tt = datetime.datetime.fromtimestamp(an["t0"]).replace(minute=0, second=0, microsecond=0) + datetime.timedelta(hours=1)
        while tt.timestamp() < an["t1"]:
            x = (tt.timestamp() - an["t0"]) / 60 * LH; sv.append("<text class=m x='%.1f' y='108' text-anchor='middle'>%s</text>" % (min(x, 975), tt.strftime(TICK_FMT[0]))); tt += datetime.timedelta(hours=tick_h)
        sv.append("</svg>"); w("".join(sv))
        w("<div class=tw><table><tr><th>Stage</th><th class=n>Main requests</th><th class=n>Average context</th><th class=n>Peak context</th><th class=n>Average of window</th><th class=n>Peak of window</th></tr>")
        for s_ in ["pre"] + STAGES:
            cl = S[s_]["ctx"]
            if cl: w("<tr><td>%s</td><td class=n>%d</td><td class=n>%s</td><td class=n>%s</td><td class=n>%s</td><td class=n>%s</td></tr>" % ("Before P" if s_ == "pre" else "<a href='#stage-%s'>Stage %s</a>" % (s_, s_), len(cl), fmt_tok(sum(cl) / len(cl)), fmt_tok(max(cl)), pw(sum(cl) / len(cl)), pw(max(cl))))
        w("<tr><th>All</th><th class=n>%d</th><th class=n>%s</th><th class=n>%s</th><th class=n>%s</th><th class=n>%s</th></tr></table></div>" % (len(allc), fmt_tok(ctx_avg), fmt_tok(peak), pw(ctx_avg), pw(peak)))
        if cnote: w("<div class=note>Window note: %s.</div>" % esc(cnote))
        w("</div>")
        # tokens per stage
        w("<h2>Tokens and estimated cost per stage</h2><div class=sub>Cost is an estimate at placeholder list prices per million tokens (%s). Edit DEFAULT_RATES or pass --rates.</div><div class=card><div class=tw><table><tr><th>Stage</th><th class=n>Input</th><th class=n>Output</th><th class=n>Cache write</th><th class=n>Cache read</th><th class=n>New tokens</th><th class=n>Est. cost</th><th>Share of cost</th></tr>" %
          esc("; ".join("%s %g in, %g write, %g read, %g out" % r for r in rates)))
        for s in ["pre"] + STAGES:
            sd = S[s]; tk = zero()
            for p in ("main", "sub", "wf"):
                for k in ("in", "out", "cr", "cw", "cost"): tk[k] += sd[p][k]
            if not (head(tk) or tk["cr"]): continue
            w("<tr><td>%s</td><td class=n>%s</td><td class=n>%s</td><td class=n>%s</td><td class=n>%s</td><td class=n>%s</td><td class=n>%s</td><td style='min-width:110px'><div class=bar><i style='width:%.0f%%'></i></div></td></tr>" %
              ("Before P" if s == "pre" else "<a href='#stage-%s'>Stage %s</a>" % (s, s), fmt_tok(tk["in"]), fmt_tok(tk["out"]), fmt_tok(tk["cw"]), fmt_tok(tk["cr"]), fmt_tok(head(tk)), money(tk["cost"]), pct(tk["cost"], cost_all)))
        w("<tr><th>Total</th><th class=n>%s</th><th class=n>%s</th><th class=n>%s</th><th class=n>%s</th><th class=n>%s</th><th class=n>%s</th><th></th></tr></table></div></div>" % (fmt_tok(tot["in"]), fmt_tok(tot["out"]), fmt_tok(tot["cw"]), fmt_tok(tot["cr"]), fmt_tok(head(tot)), money(cost_all)))
        # sub-agents
        w("<h2>Sub-agents: who ran, on which model, for how long</h2><div class=sub>Grouped by stage. Workflow runs (parallel inventory batches) are collapsed into one group row. Duration is first to last record of the agent.</div>")
        for s in ["pre"] + STAGES:
            ag = S[s]["agents"]
            if not ag: continue
            singles = sorted([a for a in ag if not a["wf"]], key=lambda a: a["t0"]); wfs = collections.defaultdict(list)
            for a in ag:
                if a["wf"]: wfs[a["wf_id"]].append(a)
            stot = sum(head(a["tok"]) for a in ag)
            w("<details id='agents-%s' %s class=card style='margin-top:8px'><summary><b>%s</b> &middot; %d agents &middot; %s new tokens &middot; est. %s</summary><div class=tw><table style='margin-top:8px'><tr><th>Description</th><th>Model</th><th class=n>Start</th><th class=n>Duration</th><th class=n>Turns</th><th class=n>Context avg / peak</th><th class=n>New tokens</th><th class=n>Est. cost</th></tr>" %
              (s, "open" if s in ("3", "4") else "", "Before P" if s == "pre" else "Stage %s: %s" % (s, STAGE_NAME[s]), len(ag), fmt_tok(stot), money(sum(a["tok"]["cost"] for a in ag))))
            for a in singles:
                w("<tr><td>%s</td><td>%s</td><td class=n>%s</td><td class=n>%s</td><td class=n>%d</td><td class=n>%s / %s (%s)</td><td class=n>%s</td><td class=n>%s</td></tr>" % (esc(a["desc"]), esc(a["model"].replace("claude-", "")), local_hm(a["t0"]), fmt_dur(a["t1"] - a["t0"]), a["turns"], fmt_tok(a["ctx_avg"]), fmt_tok(a["ctx_peak"]), ctx_pct_txt(a["ctx_peak"], window_for(a["model"]) if not cwin or cwin < 1_000_000 else cwin), fmt_tok(head(a["tok"])), money(a["tok"]["cost"])))
            for wid, fl in wfs.items():
                ph = sorted({a["phase"] for a in fl if a["phase"]})
                w("<tr><td><b>Workflow %s</b> (%d parallel agents%s)<br><span class=sub>%s</span></td><td>%s</td><td class=n>%s</td><td class=n>%s</td><td class=n>%d</td><td class=n>%s / %s</td><td class=n>%s</td><td class=n>%s</td></tr>" %
                  (esc(wid), len(fl), ", phase " + esc("/".join(ph)) if ph else "", esc(", ".join(sorted(a["desc"] for a in fl))), esc(", ".join(sorted({a["model"].replace("claude-", "") for a in fl}))),
                   local_hm(min(a["t0"] for a in fl)), fmt_dur(max(a["t1"] for a in fl) - min(a["t0"] for a in fl)), sum(a["turns"] for a in fl), fmt_tok(sum(a["ctx_avg"] for a in fl) / len(fl)), fmt_tok(max(a["ctx_peak"] for a in fl)), fmt_tok(sum(head(a["tok"]) for a in fl)), money(sum(a["tok"]["cost"] for a in fl))))
            w("</table></div></details>")
        # advice
        w("<h2>All observations: token and context facts computed from this session</h2><div class=sub>Plain measurements behind the advisory above.</div><div class=adv>")
        for t, p in adv: w("<div class=card><h3>%s</h3><p>%s</p></div>" % (esc(t), p if "&" in p else esc(p)))
        top5 = sorted(agents, key=lambda a: -a["tok"]["cost"])[:5]
        w("<div class=card><h3>Five most expensive sub-agents</h3><table>" + "".join("<tr><td>%s</td><td class=n>%s</td><td class=n>%s</td></tr>" % (esc(a["desc"]), esc(a["model"].replace("claude-", "")), money(a["tok"]["cost"])) for a in top5) + "</table></div></div>")
    w = w_main
    # build progress (Stage 5): the plan's own phases, stacked built / partial / not built
    w("<section class=tab id=tab-build>")
    w("<h2 id=build-detail>Build progress: Stage 5 plan, scripts and proof</h2>")
    if bp:
        kinds = bp["kinds"]; tr = ""
        runs_by = {str(k_[0]): d["runs"] for k_, d in (facts["phases"] if facts else []) if k_[0] != ""}
        cur = now_phase(bp, proj); phase_detail = args.phase_detail
        w("<div class=card><div class=hd><b>%d of %d rows built%s</b><a href='#plan-tables'>Jump to script folders and module proof</a></div><div class='stack3' style='margin:8px 0' title='built, partial, not built'><i class=b style='width:%.1f%%'></i><i class=p style='width:%.1f%%'></i></div>" %
          (bp["built"], bp["total"], (", %d partial" % bp["partial"]) if bp["partial"] else "", pct(bp["built"], bp["total"]), pct(bp["partial"], bp["total"])))
        w("<div class=legend><span><b style='background:var(--ok)'></b>built %d</span><span><b style='background:var(--warn)'></b>partial %d</span><span><b style='background:var(--idle)'></b>not built %d</span>%s</div>" % (bp["built"], bp["partial"], bp["todo"], ("<span>not needed %d (not counted)</span>" % bp["skip"]) if bp["skip"] else ""))
        w("<div class=stack>" + "".join("<i title='%s %d' style='width:%.1f%%;background:%s'></i>" % (k, v, pct(v, bp["total"]), KC.get(k, "#888")) for k, v in kinds.items()) + "</div>")
        w("<div class=legend>" + "".join("<span><b style='background:%s'></b>%s %d</span>" % (KC.get(k, "#888"), k, v) for k, v in kinds.items()) + "</div>")
        lb = (facts["last_run"]["t"], facts["last_run"]["script"], facts["last_run"]["result"]) if facts else None
        if lb: w("<div class=note id=lastbuild data-stamp>%s. Last build step: <code>%s</code> (%s), %s at %s.</div>" % (esc(facts_line(facts)), esc(lb[1][:90]), esc(re.sub(r"[^\w .,/()+-]", "", lb[2])[:40].strip() or "no result"), esc(ago(lb[0])), esc(datetime.datetime.fromtimestamp(lb[0]).strftime("%Y-%m-%d %H:%M"))))
        if facts and facts["score"]: w("<div class=note id=modelscore data-stamp>Latest model score %.1f (%s).</div>" % (facts["score"]["score"], esc(facts["score"]["script"][:40])))
        if bp.get("note"): w("<div class='note stale'>%s.</div>" % esc(bp["note"]))
        w("<div class=note id=planread data-stamp>Kinds are the plan's own Kind column; row state is the plan's State column read by prefix (built or done = built, partial or in progress = partial, anything else = not built); HARNESS rows are not build rows and are not counted. A HARNESS row running verify-module.sh &lt;Module&gt; is that module's sign-off and shows on its phase card as one status, read from the module's verify summary and LOOK report: verified only when the summary is clean and newer than the scripts it depends on and the LOOK is N of N. The gate's own record of the look is the look obligation, in the obligations table of <code>gate-check.sh &lt;project&gt; 5</code> (index.html). Plan read %s from %s.</div>%s</div>" % (esc(bp.get("generated") or "unknown"), "architecture/build-plan.md" if bp.get("source") == "md" else "architecture/build-plan.json", signoff_rollup(bp)))
        def card(p):
            now = p is cur
            w("<details class='card ph%s' id='phase-%s'%s><summary><b>Phase %s: %s</b>%s%s<div class=k>%s</div><div class=k>module files: %s</div>%s<div class=k>Click to show or hide the rows</div></summary>" %
              (" now" if now else "", esc(p["id"]), " open" if now else "", esc(p["id"]), esc(p["name"]), " <span class=nowtag>building now</span>" if now else "", phase_bar(p, runs_by.get(str(p["id"]))), esc(" ".join("%s %d" % kv for kv in p["kinds"].items())),
               esc(" ".join(("%s %s" % (n, "yes" if v else "no")) for n, v in (("definition", p["def"]), ("brief", p["brief"]), ("ledger", p["ledger"])))), signoff_html(p)))
            if str(p["id"]) in phase_detail: w(phase_detail[str(p["id"])])
            else: w("<div class=tw><table class=steps><tr><th>#</th><th>Kind</th><th>Row</th><th>State</th></tr>" + "".join("<tr class='r-%s'><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>" % (x["cls"], esc(x["n"]), esc(x["kind"]) + (" <span class=mut>(not counted)</span>" if x["cls"] == "harness" else ""), esc(x["step"]), esc(x["state"][:90])) for x in p["steps"]) + "</table></div>" if p["steps"] else "")
            w("</details>")
        # focus: the phase being built plus the three unfinished ones with the latest built date; the rest fold
        last = lambda p: max([m for x in p["steps"] for m in re.findall(r"20\d\d-\d\d-\d\d", x.get("state", ""))] or [""])
        done = [p for p in bp["phases"] if p["n"] and p["built"] == p["n"]]
        left = [p for p in bp["phases"] if p not in done]
        cl = any(p is cur for p in left)
        focus = ([cur] if cl else []) + sorted([p for p in left if p is not cur], key=last, reverse=True)[:4 - cl]
        rest = [p for p in left if not any(p is f for f in focus)]
        def fold(fid, title, sub, ps):
            w("<details class='card grp-ph' id='%s' style='margin-top:10px'><summary><b>%s (%d)</b><div class=sub>%s</div></summary><div class=phases>" % (fid, title, len(ps), sub))
            for p in ps: card(p)
            w("</div></details>")
        if focus:
            w("<h3 style='margin:14px 0 4px'>Building now and next</h3><div class=sub>The phase being built, then the unfinished phases with the most recent built rows.</div><div class=phases style='margin-top:6px'>")
            for p in focus: card(p)
            w("</div>")
        if rest: fold("fold-rest", "Other unfinished phases", "Not started yet, or a few rows left: %s" % esc(", ".join("Phase %s %d of %d" % (p["id"], p["built"], p["n"]) for p in rest)), rest)
        if done: fold("fold-done", "Completed phases", "Every row built: %s" % esc(", ".join("Phase %s" % p["id"] for p in done)), done)
    else: w("<div class=card>No plan to summarise yet: %s</div>" % esc(args.plan_msg or "architecture/build-plan.md was not read."))
    if args.fragment:   # plan tally, views A (script folders) and B (module proof); the per-phase rows live in the cards above
        w("<section id=plan-tables class='card frag'>")
        w(args.fragment)
        w("</section>")
    w("</section>")
    render_changes(w, chg, bp)
    w("<section class=tab id=tab-performance>")
    if not L: w("<h2>Performance</h2><p class=nolog>%s Time, token and cost figures need a Claude Code session log of this project (see How this was measured at the top).</p>" % esc(args.log_note))
    H.extend(PERF)
    w("</section><section class=tab id=tab-pages>")
    w(render_pages(proj, args.outdir, [SELF_OUT]))
    w("</section><section class=tab id=tab-notes>")
    w(aside)   # tips first, then the bugs met here; the method notes below are reference, folded
    render_bugs(w, args.bugs)
    # footer
    w("<footer><details class=card id=derived><summary><b>How these numbers are derived</b><div class=sub>Sources, cost, stage windows, attribution, time, gate state, known gaps and the exact inputs of this page.</div></summary><ul>")
    if L:
        sg = an["sig"]
        w("<li><b>Source.</b> The Claude Code session logs of this project on this machine (%d session file(s), %d sub-agent log(s)). Usage is counted once per message id, taking the maximum of each counter, because the log writes one record per streamed block (same method as the toolkit's token-burn.sh). Synthetic records are skipped. New tokens = input + output + cache write; cache reads are shown apart. Only numbers, timestamps, tool names and sub-agent short descriptions are used; no prompt or message text is copied into this page.</li>" % (args.n_sessions, len(agents)))
        w("<li><b>Cost.</b> Estimate only: tokens times placeholder list prices (see the token table), not an invoice. Cache write and read are priced separately. Set your own rates with a rates file (same format as token-burn.sh --rates) at .claude/progress-report-rates.txt.</li>")
        w("<li><b>Stage windows (approximate).</b> A stage starts at the first matching signal in the main thread: P = toolkit-init skill; 0 = first gate-check run; 1 = gate-check for stage 0 (else the extractor agent); 2 = first write of the BRD contract (else first BRD agent); 3 = gate-check for stage 2 (else a Stage 3 agent); 4 = a Stage 4 or build plan agent; 5 = the first row of the exec log (metrics ledger, else BUILD-LOG) or the timed Stage 4 sign-off, whichever is earlier; only with no exec log rows, the first exec.sh call, a build skill or an mdlsource write in the session log. Windows are made monotonic. Detected starts: %s.</li>" %
          esc(", ".join("%s %s" % (s, local_hm(sg[s])) for s in STAGES if sg.get(s)) or "none"))
        w("<li><b>Attribution.</b> Main-thread requests go to the window they start in. Sub-agents go by description first (Stage N, inventory, extractor, BRD) and by start time otherwise, so a Stage 3 agent started during Stage 4 counts to Stage 3, while work done by the main thread in that window counts to Stage 4. Session time before the project existed is shown as Before Stage P.</li>")
        w("<li><b>Time.</b> Wall time is the window length. A gap of more than %d minutes between any two events is waiting for the user, overnight breaks included. A minute is sub-agent time when any sub-agent record span covers it, even if that agent was itself waiting on a tool.</li>" % (IDLE_GAP_S // 60))
    w("<li><b>Gate state.</b> From the PROJECT.md line under Current stage (gates passed list). The generated index.html table supplies titles and details; when it disagrees, PROJECT.md wins and a note appears. Progress for a stage that has not passed is promised artifacts present (toolkit artifact-manifest.tsv, entry mode %s); Stage 5 uses plan rows built.</li>" % esc(info["entry_mode"]))
    w("<li><b>Abbreviations.</b> BRD: business requirements document. This page uses no libraries and no network. Decisions: rows of the PROJECT.md Decisions table by Stage column; CONFIRMED means the user agreed, ASSUMED means the agent proceeded on a stated assumption, RAISED means an open question.</li>")
    w("<li><b>Known gaps.</b> Gate verdicts for Stages 5 and 6 cannot be evaluated before build; interactive time the user spends outside the session is not visible.</li>")
    shown = [esc(x) for x in args.sessions[:6]]
    logs_txt = ("<code>" + "</code>, <code>".join(shown) + "</code>" + (" and %d more" % (len(args.sessions) - 6) if len(args.sessions) > 6 else "")) if args.sessions else ("none found under <code>%s</code>" % esc(args.logs_base) if args.logs_base else "not read")
    how = "chosen with --session-log" if args.session_log else "found by discovery" + (", %d of them from other folders by tool calls on the project" % len(DISCOVERY["mention"]) if DISCOVERY.get("mention") else "")
    rates_txt = ("<code>%s</code>" % esc(args.rates_used)) if args.rates_used else "built-in placeholder rates (a file at <code>%s</code> or --rates would override them)" % esc(args.rates_default)
    regen = "project-bin/build-plan-status.sh &lt;project&gt; --html" + "".join(" --session-log &lt;path&gt;" for _ in args.session_log[:1])
    direct = "progress-report.py &lt;project&gt; " + (" ".join("--session-log <code>%s</code>" % esc(x) for x in args.session_log) if args.session_log else "--logs-dir &lt;dir&gt;")
    w("<li><b>Inputs.</b> Project folder: <code>%s</code>. Session log(s) (%s): %s. Rates file: %s. To regenerate with the same inputs: <code>%s</code>, or <code>%s</code>.</li>" % (esc(proj), how, logs_txt, rates_txt, regen, direct))
    w("</ul>")
    w("<div class=note id=rebuildnote data-stamp>Rebuild: project-bin/build-plan-status.sh --html. Setting in PROJECT.md: Progress report: off, ask or auto (now %s). Generated %s.</div></details></footer></section></div></div></main>" % (esc(info["setting"]), gen))
    w(JS)
    if args.reload:
        w("<script id=autoreload>%s</script>" % ("(function(){\nvar VK='pr-view:'+location.pathname,PK='pr-paused',IDLE=20000,EVERY=30000,last=%d,active=%d,lastInput=0,de=document.documentElement;\nfunction get(k){try{return sessionStorage.getItem(k)}catch(e){return null}}\nfunction put(k,v){try{if(v===null)sessionStorage.removeItem(k);else sessionStorage.setItem(k,v)}catch(e){}}\ntry{history.scrollRestoration='manual'}catch(e){}\nfunction restore(){try{var st=JSON.parse(get(VK)||'null');if(!st)return;\n var d=st.d||{};for(var id in d){var e=document.getElementById(id);if(e&&e.tagName==='DETAILS')e.open=!!d[id]}\n var sb=de.style.scrollBehavior;de.style.scrollBehavior='auto';window.scrollTo(0,st.y||0);de.style.scrollBehavior=sb;\n }catch(e){}}\nrestore();window.addEventListener('load',function(){restore();put(VK,null)});\nfunction save(){var d={};var all=document.querySelectorAll('details[id]');for(var i=0;i<all.length;i++)d[all[i].id]=all[i].open;put(VK,JSON.stringify({y:window.pageYOffset||de.scrollTop||0,d:d}))}\nfunction reloadNow(){save();location.reload()}\nwindow.__prReload=reloadNow;\n['scroll','click','keydown','wheel','touchstart','mouseup'].forEach(function(n){window.addEventListener(n,function(){lastInput=Date.now()},{passive:true})});\ndocument.addEventListener('selectionchange',function(){lastInput=Date.now()});\nvar live=document.getElementById('live'),btn=document.getElementById('livebtn'),txt=document.getElementById('livetxt');\nfunction paint(){var p=get(PK)==='1';if(txt)txt.textContent=p?'Paused':'Live · refreshes every 30 s';if(btn)btn.textContent=p?'Resume':'Pause'}\nif(btn)btn.addEventListener('click',function(ev){ev.preventDefault();put(PK,get(PK)==='1'?null:'1');paint()});\npaint();\nfunction tick(){if(get(PK)==='1'||Date.now()-lastInput<IDLE){setTimeout(tick,EVERY);return}reloadNow()}\nif(Date.now()/1000-last<active)setTimeout(tick,EVERY);\n})();" % (int(args.last_act), ACTIVE_S)))
    w("</body></html>")
    out = "\n".join(H)
    return out.replace("\u2014", " - ").replace("\u2013", " - ")

def main_():
    if "--print-name" in sys.argv: print(REPORT_FILE); return
    ap = argparse.ArgumentParser(description="Render the progress report page.", formatter_class=argparse.RawDescriptionHelpFormatter, epilog="""Inputs (also printed in the page footer, so a later regenerate need not guess):
  project folder   PROJECT: PROJECT.md, index.html, architecture/build-plan.json; written under PROJECT/architecture/.
  session logs     <logs-dir or CLAUDE_CONFIG_DIR or ~/.claude>/projects/<slug>/*.jsonl and <session>/subagents/;
                   <slug> is the project path with every non-alphanumeric character replaced by '-'.
                   A log counts for the project when a record's cwd is at or under it.
  --session-log    use this log instead of discovery (a .jsonl file, or a folder of them; repeat for several). The sub-agent logs
                   next to each log (<session>/subagents/) are read too. Needed when the session was started outside the project
                   folder and discovery cannot find it. Discovery stays the default.
  rates file       prices per million tokens: --rates FILE, else <project>/.claude/progress-report-rates.txt when present, else
                   the placeholder rates in the script. One line per model: glob input cache-write cache-read output.
  context window   200k unless the log records 1M (a [1m] model id or a context-1m beta/flag). Above 200k with no marker the
                   window is capped at the auto-compaction point and labelled "inferred". Percentages never exceed 100.
  page name        REPORT_FILE in the script (--print-name prints it).""")
    ap.add_argument("project")
    ap.add_argument("--out"); ap.add_argument("--toolkit")
    ap.add_argument("--rates", help="rates file (glob input cache-write cache-read output per line); default <project>/.claude/progress-report-rates.txt if present, else placeholder rates")
    ap.add_argument("--fragment", help="HTML file with the plan tables and views A and B, embedded as the build detail")
    ap.add_argument("--phase-detail", help="HTML file of <!--phase:ID-->...<!--/phase--> blocks (rows with Produces, Depends on, Scripts, and Claims), spliced into each phase card")
    ap.add_argument("--plan-json", help="parsed build plan (build-plan-status.sh --json shape)")
    ap.add_argument("--plan-msg", default="")
    ap.add_argument("--logs-dir", help="folder holding the <slug>/ session log folders (default: <CLAUDE_CONFIG_DIR or ~/.claude>/projects)")
    ap.add_argument("--session-log", action="append", default=[], metavar="PATH", help="session log to use instead of discovery: a .jsonl file or a folder of them; repeatable")
    ap.add_argument("--session-cache", help="discovery cache file (default <project>/.claude/progress-report-sessions.txt)")
    ap.add_argument("--no-log", action="store_true", help="skip session log discovery")
    a = ap.parse_args()
    for _k in ("out", "fragment", "phase_detail", "plan_json", "logs_dir", "session_cache", "toolkit"):
        if getattr(a, _k, None): setattr(a, _k, fix_msys(getattr(a, _k)))
    a.session_log = [fix_msys(x) for x in a.session_log]
    proj = os.path.abspath(os.path.expanduser(fix_msys(a.project)))
    a.outdir = os.path.dirname(os.path.abspath(a.out)) if a.out else os.path.join(proj, "architecture")
    out_path = a.out or os.path.join(a.outdir, REPORT_FILE)
    tk = a.toolkit or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    if not os.path.isfile(os.path.join(tk, "bin", "lib", "artifact-manifest.tsv")):
        tk = ""
        for f in (os.path.join(proj, ".claude", "toolkit.env"), os.path.join(os.path.expanduser("~"), ".mxcli-toolkit.env")):
            m = re.search(r"^\s*(?:export\s+)?(?:MXTK_TOOLKIT_DIR|TOOLKIT_DIR|MXCLI_TOOLKIT)\s*=\s*[\"']?([^\"'\n]+)", read(f), re.M)
            if m and os.path.isfile(os.path.join(os.path.expanduser(m.group(1)), "bin", "lib", "artifact-manifest.tsv")):
                tk = os.path.expanduser(m.group(1)); break
    info = load_project(proj); gate = load_gate_index(proj)
    reconcile_gates(info, gate)
    WAIVED.update(info["waived"])
    global SELF_OUT
    SELF_OUT = re.sub(r"\.tmp\.\d+$", "", out_path)
    manifest = load_manifest(tk, info["entry_mode"]); arts = collect_artifacts(proj, manifest)
    rf = a.rates or os.path.join(proj, ".claude", "progress-report-rates.txt")
    rates = load_rates(rf if os.path.isfile(rf) else None)
    a.rates_used = rf if os.path.isfile(rf) else ""; a.rates_default = rf
    bp = load_build_plan(a.plan_json or os.path.join(proj, "architecture", "build-plan.json"), proj)
    a.fragment = read(a.fragment) if a.fragment else ""; a.phase_detail = {m.group(1): m.group(2) for m in re.finditer(r"<!--phase:(.*?)-->(.*?)<!--/phase-->", read(a.phase_detail) if a.phase_detail else "", re.S)}; a.plan_msg = a.plan_msg
    a.bugs = load_bugs(proj, tk)
    if a.session_log and not a.no_log:
        sessions, base = explicit_sessions(a.session_log), ""
    else: sessions, base = ([], "") if a.no_log else find_sessions(proj, a.logs_dir, a.session_cache)
    a.n_sessions = len(sessions); a.has_log = False; a.log_note = ""; a.sessions = sessions; a.logs_base = base
    main = {"msgs": [], "times": [], "compacts": [], "prompts": 0, "tools": [], "calls": []}; agents = []
    if sessions:
        main, agents = load_sessions(sessions)
        a.has_log = bool(main["times"] or agents)
    a.ledgers = None
    if not a.has_log:
        a.ledgers = load_ledgers(proj)
        a.log_note = "No Claude Code session log was found for this project folder on this machine." if not a.no_log else "Session logs were not read."
    ledger_t = [os.path.getmtime(f) for f in (os.path.join(proj, ".claude", "loop", "metrics-ledger.tsv"), os.path.join(proj, "docs", "BUILD-LOG.md")) if os.path.isfile(f)]
    log_t = max(main["times"] + [x for g in agents for x in g["times"]] or [0])
    a.last_act = max(ledger_t + [log_t] or [0])
    a.reload = (time.time() - a.last_act) < ACTIVE_S if a.last_act else False
    if a.has_log:
        an = analyse(proj, info, gate, manifest, arts, main, agents, rates, bp)
        adv, tot, peak = advice(info, an, main, agents, rates)
        a.adv2 = advisory(info, an, main, agents, rates, tot, peak)
    else:
        an = {"S": {s: {"main": zero(), "sub": zero(), "wf": zero(), "agents": [], "wf_n": 0, "min": collections.Counter(), "ctx": []} for s in ["pre"] + STAGES},
              "wins": [], "sig": {}, "idle": [], "minutes": [], "buckets": {}, "mctx": [], "t0": 0, "t1": 0}
        adv, tot, peak = [], zero(), 0
    out = render(proj, info, gate, manifest, arts, main, agents, rates, bp, an, adv, tot, peak, a)
    tmp = out_path + ".tmp.%d" % os.getpid()
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(tmp, "w", encoding="utf-8") as f: f.write(out)
    os.replace(tmp, out_path)
    print("wrote", out_path, len(out), "bytes")

if __name__ == "__main__":
    main_()
