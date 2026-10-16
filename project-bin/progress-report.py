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
REPORT_FILE = "progress-report.html"   # the one place the page name lives here (build-plan-status.sh asks for it with --print-name)
IDLE_GAP_S = 600          # a gap longer than this between two events counts as waiting for the user
CACHE_TTL_S = 300         # prompt cache time to live assumed for the cache rewrite observation
ACTIVE_S = 600            # a build counts as active when its last session or exec event is younger than this
# Placeholder list prices in USD per million tokens: glob, input, cache write, cache read, output.
# These are ASSUMED rates, not read from any source. Override with --rates FILE (same 5 columns).
DEFAULT_RATES = [("*opus*", 5.0, 6.25, 0.50, 25.0), ("*sonnet*", 3.0, 3.75, 0.30, 15.0),
                 ("*haiku*", 1.0, 1.25, 0.10, 5.0)]
# Sub-agent description -> stage override (first match wins); otherwise the time window decides.
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
                ("Module done", "Module journeys, plus unit tests when the project has them switched on"),
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
                    if sg in STAGES and (sg not in info["signoff"] or (t and t < info["signoff"][sg][0])): info["signoff"][sg] = (t, c[1][:80])
    m = re.search(r"Entry mode:\s*\**\s*(\w[\w-]*)", md)
    em = (m.group(1).lower() if m else "migration")
    info["entry_mode"] = "requirements" if em.startswith("requirements") else "existing-app-change" if em.startswith("existing") else em
    info["waived"] = set(re.findall(r"Waived artifact\s+([\w-]+)\s*:", md))
    m = re.search(r"^[\s>*_-]*Progress report\s*:\s*\**\s*(off|ask|auto)\b", md, re.M | re.I)
    info["setting"] = m.group(1).lower() if m else "ask"
    info["md_mtime"] = mt
    return info

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
            if clip and ts and not (clip[0] <= ts <= clip[1]): continue
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

DISCOVERY = {}
SCAN_DAYS = 30; SCAN_MAX_FILES = 300; SCAN_MAX_BYTES = 200_000_000; MENTION_MIN = 5; MENTION_PAD_S = 1800
def slug(path):
    """Claude Code's folder name for a launch directory: every non-alphanumeric character becomes a dash."""
    return re.sub(r"[^A-Za-z0-9]", "-", path)

def find_sessions(proj, logs_dir=None):
    """Main-thread session logs that belong to this project on this machine, oldest first.
    Looks in the project's own slug folder, its ancestors' and its descendants'; a session counts when
    at least one record's cwd is at or under the project folder (the folder name alone is not proof)."""
    base = logs_dir or os.path.join(os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(os.path.expanduser("~"), ".claude"), "projects")
    if not os.path.isdir(base): return [], base
    me = slug(os.path.realpath(proj)); out = []
    for name in sorted(os.listdir(base)):
        d = os.path.join(base, name)
        if not (os.path.isdir(d) and (name == me or me.startswith(name + "-") or name.startswith(me + "-"))): continue
        for f in sorted(glob.glob(os.path.join(d, "*.jsonl"))):
            if session_in_project(f, proj): out.append(f)
    # Sessions started elsewhere (another folder's slug): last 30 days, newest first, a capped number of files. A log counts
    # when a record's cwd is the project, or when the project's absolute path appears at least MENTION_MIN times in it
    # (cheap byte count, tool inputs included). Reported on the page as found by path mention.
    DISCOVERY.update({"other_dirs": 0, "other_files": 0, "mention": [], "searched": True})
    have = set(out); cands = []; cutoff = time.time() - SCAN_DAYS * 86400
    for name in os.listdir(base):
        d = os.path.join(base, name)
        if not os.path.isdir(d): continue
        own = (name == me or me.startswith(name + "-") or name.startswith(me + "-"))
        if own: continue
        DISCOVERY["other_dirs"] += 1
        for f in glob.glob(os.path.join(d, "*.jsonl")):
            try:
                st = os.stat(f)
                if st.st_mtime >= cutoff and f not in have: cands.append((st.st_mtime, f, st.st_size))
            except OSError: pass
    cands.sort(reverse=True)
    needles = {os.path.realpath(proj).encode(), os.path.abspath(proj).encode()}
    needle_re = re.compile(b"|".join(re.escape(n) for n in sorted(needles, key=len, reverse=True)))
    for mt, f, size in cands[:SCAN_MAX_FILES]:
        DISCOVERY["other_files"] += 1
        if session_in_project(f, proj): out.append(f); continue
        if size > SCAN_MAX_BYTES: continue
        try: data = open(f, "rb").read()
        except OSError: continue
        if len(needle_re.findall(data)) >= MENTION_MIN:   # one regex, so a path that is a substring of its real path counts once
            # a session that only mentions the project counts for the stretch where it did: first to last mention, padded
            ts = []
            for ln in data.split(b"\n"):
                if any(n in ln for n in needles):
                    mm = re.search(rb'"timestamp"\s*:\s*"([^"]+)"', ln)
                    if mm:
                        e_ = epoch(mm.group(1).decode())
                        if e_: ts.append(e_)
            out.append(f); DISCOVERY["mention"].append(f)
            if ts: DISCOVERY.setdefault("clip", {})[f] = (min(ts) - MENTION_PAD_S, max(ts) + MENTION_PAD_S)
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

def session_in_project(path, proj):
    roots = {os.path.realpath(proj), os.path.abspath(proj)}
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for i, line in enumerate(f):
                if i > 4000: break
                m = re.search(r'"cwd"\s*:\s*"((?:[^"\\]|\\.)*)"', line)
                if m:
                    c = m.group(1)
                    if any(c == r or c.startswith(r.rstrip("/") + "/") for r in roots): return True
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
    # Stage 4 to 5: one source of truth with PROJECT.md. The switch is the earliest evidenced of the Stage 4 sign-off row in
    # PROJECT.md, the first exec.sh build step in the log, and the build skill signal above.
    ev = [t for t in [sig.get("5"), first(lambda e: e["name"] == "Bash" and re.search(r"(^|[\s/])exec\.sh\b", e.get("cmd", "")))] if t]
    so = (info or {}).get("signoff", {}).get("4")
    if so and so[0]: ev.append(so[0])
    if ev: sig["5"] = min(ev)
    return sig

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
                  "step": next((k for k, x in enumerate(hd) if x == "step" or x.startswith("what") or x.startswith("do")), None)}
            while i < len(lines) and lines[i].lstrip().startswith("|"):
                c = _cells(lines[i]); i += 1
                if ci["n"] is None or ci["state"] is None or not c or not re.match(r"^\d+$", c[ci["n"]] if ci["n"] < len(c) else ""): continue
                if cur is None: cur = ("all", "All rows", []); phases.append(cur)
                st = c[ci["state"]] if len(c) == len(hd) else c[-1]
                cur[2].append({"number": c[ci["n"]], "kind": (c[ci["kind"]] if ci["kind"] is not None and ci["kind"] < len(c) else "") or "-",
                               "step": (c[ci["step"]] if ci["step"] is not None and ci["step"] < len(c) and ci["step"] != ci["n"] else "")[:140], "state": st})
            continue
        i += 1
    return [p for p in phases if p[2]]

def finish_plan(phases, proj, generated, source):
    out = []; kinds = collections.Counter(); tot = collections.Counter()
    for pid, name, steps in phases:
        c = collections.Counter(); kd = collections.Counter(); rows = []
        for x in steps:
            cl = classify_state(x.get("state")); c[cl] += 1; kd[x.get("kind") or "-"] += 1
            if cl != "skip": kinds[x.get("kind") or "-"] += 1
            rows.append({"n": x.get("number"), "kind": x.get("kind"), "step": x.get("step"), "state": x.get("state") or "", "cls": cl})
        tot.update(c)
        mods = os.path.join(proj, "architecture", "modules", name)
        out.append({"id": pid, "name": name, "n": len(steps) - c["skip"], "built": c["built"], "partial": c["partial"], "todo": c["todo"], "skip": c["skip"], "kinds": dict(kd),
                    "brief": os.path.isfile(os.path.join(mods, "module-brief.md")), "ledger": os.path.isfile(os.path.join(mods, "coverage-ledger.md")),
                    "def": os.path.isfile(os.path.join(mods, "definition.md")), "steps": rows})
    return {"phases": out, "kinds": dict(kinds), "built": tot["built"], "partial": tot["partial"], "todo": tot["todo"], "skip": tot["skip"],
            "total": sum(tot.values()) - tot["skip"], "generated": generated, "source": source, "note": ""}

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
    for line in tl.splitlines():
        c = [x.strip() for x in line.strip().strip("|").split("|")]
        if line.lstrip().startswith("|") and len(c) >= 5 and c[0].lower() not in ("phase",) and not set(c[0]) <= set("-: "):
            out["phases"].append({"phase": c[0], "start": c[1], "min": _num(c[2]), "min_txt": c[2], "tok": _num(c[3]), "tok_txt": c[3], "runs": c[4]})
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
    bp = finish_plan([(i, n, [{"number": x.get("number"), "kind": x.get("kind"), "step": x.get("step"), "state": x.get("state")} for x in st]) for i, n, st in ph], proj, d.get("generatedAt"), "json")
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

JS = "<script>\n" + 'function openTarget(){var h=location.hash.slice(1);if(!h)return;var e=document.getElementById(h);if(!e)return;\n if(e.tagName===\'DETAILS\')e.open=true;var d=e.closest&&e.closest(\'details\');if(d)d.open=true;}\nwindow.addEventListener(\'hashchange\',openTarget);openTarget();\n(function(){var links=[].slice.call(document.querySelectorAll(\'.snav a[href^="#stage-"]\'));\n if(!(\'IntersectionObserver\' in window))return;var io=new IntersectionObserver(function(es){es.forEach(function(en){if(en.isIntersecting){\n  links.forEach(function(l){l.style.outline=l.getAttribute(\'href\')===\'#\'+en.target.id?\'2px solid var(--accent)\':\'none\'});}})},{rootMargin:\'-60px 0px -70% 0px\'});\n links.forEach(function(l){var t=document.querySelector(l.getAttribute(\'href\'));if(t)io.observe(t)});})();\n' + "</script>"
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
html{scroll-behavior:smooth}[id^=stage-],[id^=agents-],[id^=phase-],#tips{scroll-margin-top:56px}
.snav{position:sticky;top:0;z-index:20;background:var(--bg);border-bottom:1px solid var(--line);padding:8px 16px;display:flex;gap:6px;align-items:center;flex-wrap:wrap}
.snav b{font-size:12px;color:var(--mut);margin-right:4px}.snav a{min-width:34px;text-align:center;padding:4px 10px;border-radius:8px;background:var(--card);border:1px solid var(--line);font-weight:650;font-size:13px;color:var(--ink)}
.snav a.passed{border-color:var(--ok)}.snav a.cur{background:var(--accent);color:#fff;border-color:var(--accent)}.snav a:hover{text-decoration:none;border-color:var(--accent)}
.hd h3 a{color:inherit}.updated{display:inline-block;margin-top:6px;padding:3px 10px;border-radius:8px;background:var(--soft);font-size:13px;font-weight:600}
.layout{display:grid;grid-template-columns:minmax(0,1fr) 340px;gap:16px;align-items:start}.layout.solo{display:block}.content{min-width:0}.side{position:sticky;top:52px;max-height:calc(100vh - 64px);overflow:auto;padding-right:2px}.side h2{margin-top:0}.health{margin-top:8px}.health .hi{font-size:13px;margin-top:3px}.grp{margin-top:8px;border:1px solid var(--line);border-radius:10px;background:var(--card)}.grp>summary{cursor:pointer;padding:9px 12px;font-size:14px}.grp .speed,.grp>.split,.grp>div,.grp .tip{padding:0 12px 10px}.tip{border-top:1px solid var(--line);padding-top:10px}.tip h3{font-size:13px;margin:0 0 4px}.tip p{margin:0 0 4px;font-size:12.5px}.p-info{background:#8793a6;color:#fff}@media(max-width:1000px){.layout{grid-template-columns:minmax(0,1fr)}.side{position:static;max-height:none}}.dot{display:inline-block;width:9px;height:9px;border-radius:50%;margin-right:4px}.p-green{background:#2e9e5b;color:#fff}.p-amber{background:#e0a100;color:#fff}.p-red{background:#d1383d;color:#fff}.pill{padding:1px 9px;margin-left:6px;border-radius:99px;font-size:12px}.speed{margin-top:8px;font-size:13px}.split{display:flex;gap:2px;margin:6px 0}.seg{background:var(--accent);color:#fff;font-size:11px;padding:3px 6px;border-radius:4px;white-space:nowrap;overflow:hidden}.seg:nth-child(2){opacity:.75}.seg:nth-child(3){background:var(--idle);color:var(--ink)}.seg:nth-child(4){opacity:.55}.muted{color:var(--mut);font-size:12px}\n.advl{display:grid;grid-template-columns:repeat(auto-fit,minmax(340px,1fr));gap:10px;margin-top:8px}
.advi{border-left:4px solid var(--warn)}.advi.hi{border-left-color:var(--bad)}.advi .rk{font-size:12px;color:var(--mut)}.advi h3{margin:2px 0 6px}.advi p{margin:4px 0;font-size:13px}.advi .why{color:var(--mut);font-size:12px}
details.ph>summary{list-style:none;cursor:pointer;color:var(--ink)}details.ph>summary::-webkit-details-marker{display:none}
details.ph[open]{grid-column:1/-1}.steps td{font-size:12px;padding:3px 6px}
.note-card{margin-top:14px;border-left:4px solid var(--warn)}
.frag section.phase{margin-top:14px}.frag h2{font-size:16px;margin:24px 0 4px}.frag h3{margin:14px 0 2px}.frag .scroll{overflow-x:auto}
.frag .lede{font-size:14px}.frag .empty{color:var(--mut)}.frag code{font-size:12px}
.frag .st-built,.frag .done,.frag .CLEAN{color:var(--ok)}.frag .st-progress,.frag .in-progress,.frag .INCOMPLETE{color:var(--warn)}
.frag .st-todo,.frag .pending{color:var(--mut)}.frag .st-person{color:#8b5cf6}.frag .st-unknown{color:var(--mut);font-style:italic}
.frag .FINDINGS,.frag .drift{color:var(--bad)}.frag .drift{font-size:12px}.frag .claims{font-size:12px}.frag .warn summary{color:var(--warn)}
.frag .badge{margin-left:6px;border:1px solid currentColor;background:transparent}
footer{margin-top:36px;font-size:13px;color:var(--mut)}footer li{margin:3px 0}
@media(max-width:520px){code,pre,.stage dd,.stage dt{overflow-wrap:anywhere;min-width:0}.stage dl{grid-template-columns:minmax(0,1fr)}.stage dd{text-align:left}.hd .sub{white-space:normal;flex:1 1 100%}.snav{padding:6px 12px;flex-wrap:nowrap;overflow-x:auto;max-width:100%}.snav a{flex:0 0 auto}.snav b{flex:0 0 auto}.updated{max-width:100%;overflow-wrap:anywhere}.advl{grid-template-columns:minmax(0,1fr)}.kpis{grid-template-columns:repeat(2,minmax(0,1fr))}.rail{grid-template-columns:minmax(0,1fr)}main{padding:12px}h1{font-size:20px}.kpi .v{font-size:19px}}
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
        k.append(("Minutes logged", "%s" % fmt_dur(sum(mins) * 60) if mins else "n/a", "TIME-LEDGER.md, finished phases"))
        if toks: k.append(("Sub-agent tokens", fmt_tok(sum(toks)), "TIME-LEDGER.md; lead session not counted"))
    if lg["exec_rows"]: k.append(("Exec rows", "%d" % lg["exec_rows"], "BUILD-LOG.md, %d blocked or not run" % lg["exec_blocked"]))
    if lg["exec_s"] is not None: k.append(("Exec time", fmt_dur(lg["exec_s"]), "metrics-ledger.tsv, %d runs, seconds as measured" % lg.get("exec_n", 0)))
    elif lg["exec_rows"]: k.append(("Active time (est.)", fmt_dur(lg["active_s"]), "gaps under %d min between BUILD-LOG rows" % (IDLE_GAP_S // 60)))
    w("<div class=kpis>" + "".join("<div class='card kpi'><div class=v>%s</div><div class=l>%s<br>%s</div></div>" % (esc(v), esc(l), esc(sm)) for l, v, sm in k) + "</div>")
    if lg["phases"]:
        w("<div class=tw><table><tr><th>Phase</th><th>Start</th><th class=n>Minutes</th><th class=n>Sub-agent tokens</th><th>Exec runs</th></tr>" + "".join(
          "<tr><td>%s</td><td>%s</td><td class=n>%s</td><td class=n>%s</td><td>%s</td></tr>" % (esc(p["phase"]), esc(p["start"]), esc(p["min_txt"] or "-"), esc(p["tok_txt"] or "-"), esc(p["runs"] or "-")) for p in lg["phases"]) + "</table></div>")
    w("</div>")

def render(proj, info, gate, manifest, arts, main, agents, rates, bp, an, adv, tot, peak, args):
    L = args.has_log
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
        if s == "5" and bp and bp["total"] and states[s] not in ("passed", "waived"): owed_txt[s] = "%d of %d plan rows built%s" % (bp["built"], bp["total"], (", %d partial" % bp["partial"]) if bp["partial"] else "")
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
    w("<nav class=snav aria-label='Stage navigation'><b>Stage</b>" + "".join("<a href='#stage-%s' class='%s' title='%s'>%s</a>" % (s_, ("cur " if s_ == info["current"] else "") + ("passed" if states[s_] == "passed" else ""), esc(STAGE_NAME[s_] + ": " + states[s_]), s_) for s_ in STAGES) + "<a href='#build-detail' style='margin-left:auto'>Build</a>" + ("<a href='#tips'>Tips</a>" if L else "") + "</nav><main><div class='layout%s'><div class=content>" % ("" if L else " solo"))
    last_ev = datetime.datetime.fromtimestamp(an["t1"]).strftime("%Y-%m-%d %H:%M") if L else "no session log"
    w("<header><h1>Progress report: %s</h1>" % esc(info["name"]))
    w("<span class=updated id=stamp>Last updated %s %s</span> <span class=sub id=stamp>session log last event %s</span><br>" % (gen, datetime.datetime.now().astimezone().strftime("%Z"), last_ev))
    w("<div class=sub>Stage P to 6 &middot; entry mode %s &middot; <a href='%s'>PROJECT.md</a> &middot; <a href='%s'>gate-check page</a> &middot; replaces the former build-plan.html</div></header>" %
      (esc(info["entry_mode"]), href(os.path.join(proj, "PROJECT.md")), href(os.path.join(proj, "index.html"))))
    if L and DISCOVERY.get("mention") and not args.session_log:
        w("<div class='card note-card'><b>%d session log(s) were found by path mention, not by their folder.</b> Their working folder is not this project, but the project's path appears in them at least %d times, so they are counted. They can include other work: check the list in the footer and pass the right one with <code>--session-log &lt;path&gt;</code> to replace discovery.</div>" % (len(DISCOVERY["mention"]), MENTION_MIN))
    if not L:
        dsc = DISCOVERY
        looked = (" Looked in this project's own log folder and %d other project folders (%d logs from the last %d days)." % (dsc.get("other_dirs", 0), dsc.get("other_files", 0), SCAN_DAYS)) if dsc.get("searched") else ""
        howto = (" To use a log from another place pass it with <code>--session-log &lt;path&gt;</code> (a .jsonl file, or a folder of them, for example <code>~/.claude/projects/&lt;slug&gt;/</code>), then regenerate: <code>project-bin/build-plan-status.sh &lt;project&gt; --html --session-log &lt;path&gt;</code>.") if not args.no_log else ""
        ledgers = (" The time figures below come from the project ledgers (%s), not from a session log." % ", ".join("<code>%s</code>" % esc(x) for x in args.ledgers["sources"])) if args.ledgers else ""
        w("<div class='card note-card'><b>Time, token and cost data from a session log are unavailable.</b> %s%s%s%s Everything else (stages, gates, artifacts, decisions, the plan) is shown as usual.</div>" % (esc(args.log_note), looked, howto, ledgers))
        if args.ledgers: render_ledgers(w, args.ledgers)
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
    kp = [("Gates passed", "%d of 8" % npass, "stages P to 6, from PROJECT.md"), ("Plan rows built", ("%d of %d" % (bp["built"], bp["total"])) if bp and bp["total"] else "none yet", "from architecture/build-plan.md"),
          ("Artifacts present", "%d" % nart, "files found for the eight stages"), ("Decisions", "%d" % ndec, "rows in the PROJECT.md register")] if not L else [("Wall time", fmt_dur(wall), "first to last event in the session"), ("Waiting for you", fmt_dur(idle_s), "gaps over %d min" % (IDLE_GAP_S // 60)),
          ("New tokens", fmt_tok(head(tot)), "input + output + cache write"), ("Cache reads", fmt_tok(tot["cr"]), "billed at a fraction"),
          ("Est. cost", money(cost_all), cost_note), ("Sub-agents", "%d" % nsub, "%d of them in %d workflow run(s)" % (nwf, len({a["wf_id"] for a in agents if a["wf"]}))),
          ("Context avg / peak", "%s / %s" % (fmt_tok(ctx_avg), fmt_tok(peak)), "per main request, " + (("window %s" % fmt_tok(cwin) + (" (%s)" % cnote if cnote else "")) if cwin else "window unknown")), ("Compactions", "%d" % len(main["compacts"]), "automatic context summaries"),
          ("Your prompts", "%d" % main["prompts"], "typed messages, text not read into this page")]
    w("<div class=kpis>" + "".join("<div class='card kpi'><div class=v>%s</div><div class=l>%s</div><div class='l'>%s</div></div>" % (esc(v), esc(l), esc(n)) for l, v, n in kp) + "</div>")
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
    w("<h2>Stage rail: Kickoff (P) to Verify and report (6)</h2><div class=sub>Each card shows gate state, artifact progress%s, decisions and links.%s</div><div class=rail>" % (", wall time, tokens, sub-agents" if L else "", " Time and token splits per stage are approximate (see footer)." if L else ""))
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
        if s == "5" and not L and args.ledgers:
            lg = args.ledgers
            tmin = sum(p["min"] for p in lg["phases"] if p["min"] is not None)
            w("<dt>Build time (ledger)</dt><dd>%s</dd>" % esc((fmt_dur(tmin * 60) + " logged, " if tmin else "") + ("%d exec rows" % lg["exec_rows"] if lg["exec_rows"] else "no exec rows") + (", exec time %s" % fmt_dur(lg["exec_s"]) if lg["exec_s"] is not None else "")))
        if s == "5" and bp: w("<dt>Build progress</dt><dd><a href='#build-detail'>%d of %d rows built%s</a></dd>" % (bp["built"], bp["total"], (", %d partial" % bp["partial"]) if bp["partial"] else ""))
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
            elif row: w("<div class=sub title='%s'>Gate-check page: <b>%s</b> %s</div>" % (esc(row["detail"]), esc(row["status"]), esc(row["detail"][:110] + ("..." if len(row["detail"]) > 110 else ""))))
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
    # build progress (Stage 5): the plan's own phases, stacked built / partial / not built
    w("<h2 id=build-detail>Build progress: Stage 5 plan, scripts and proof</h2>")
    if bp:
        kinds = bp["kinds"]; tr = ""
        cur = next((p for p in bp["phases"] if p["built"] < p["n"] and (p["built"] or p["partial"])), None) or next((p for p in bp["phases"] if p["built"] < p["n"]), None)
        w("<div class=card><div class=hd><b>%d of %d rows built%s</b><a href='#plan-tables'>Jump to the plan tables</a></div><div class='stack3' style='margin:8px 0' title='built, partial, not built'><i class=b style='width:%.1f%%'></i><i class=p style='width:%.1f%%'></i></div>" %
          (bp["built"], bp["total"], (", %d partial" % bp["partial"]) if bp["partial"] else "", pct(bp["built"], bp["total"]), pct(bp["partial"], bp["total"])))
        w("<div class=legend><span><b style='background:var(--ok)'></b>built %d</span><span><b style='background:var(--warn)'></b>partial %d</span><span><b style='background:var(--idle)'></b>not built %d</span>%s</div>" % (bp["built"], bp["partial"], bp["todo"], ("<span>not needed %d (not counted)</span>" % bp["skip"]) if bp["skip"] else ""))
        w("<div class=stack>" + "".join("<i title='%s %d' style='width:%.1f%%;background:%s'></i>" % (k, v, pct(v, bp["total"]), KC.get(k, "#888")) for k, v in kinds.items()) + "</div>")
        w("<div class=legend>" + "".join("<span><b style='background:%s'></b>%s %d</span>" % (KC.get(k, "#888"), k, v) for k, v in kinds.items()) + "</div>")
        lb = (build_log_rows(proj) or [None])[-1]
        if lb: w("<div class=note id=stamp>Last build step: <code>%s</code> (%s), %s at %s.</div>" % (esc(lb[1][:90]), esc(re.sub(r"[^\w .,/()+-]", "", lb[2])[:40].strip() or "no result"), esc(ago(lb[0])), esc(datetime.datetime.fromtimestamp(lb[0]).strftime("%Y-%m-%d %H:%M"))))
        if bp.get("note"): w("<div class='note stale'>%s.</div>" % esc(bp["note"]))
        w("<div class=note id=stamp>Kinds are the plan's own Kind column; row state is the plan's State column read by prefix (built or done = built, partial or in progress = partial, anything else = not built). Plan read %s from %s.</div></div>" % (esc(bp.get("generated") or "unknown"), "architecture/build-plan.md" if bp.get("source") == "md" else "architecture/build-plan.json"))
        w("<div class=phases style='margin-top:10px'>")
        for p in bp["phases"]:
            now = p is cur
            w("<details class='card ph%s' id='phase-%s'><summary><b>Phase %s: %s</b>%s<div class='stack3' style='margin:6px 0'><i class=b style='width:%.0f%%'></i><i class=p style='width:%.0f%%'></i></div><div class=sub>%d of %d rows built%s</div><div class=k>%s</div><div class=k>module files: %s</div><div class=k>Click to show the rows</div></summary>" %
              (" now" if now else "", esc(p["id"]), esc(p["id"]), esc(p["name"]), " <span class=nowtag>building now</span>" if now else "", pct(p["built"], p["n"]), pct(p["partial"], p["n"]), p["built"], p["n"], (", %d partial" % p["partial"]) if p["partial"] else "", esc(" ".join("%s %d" % kv for kv in p["kinds"].items())),
               esc(" ".join(("%s %s" % (n, "yes" if v else "no")) for n, v in (("definition", p["def"]), ("brief", p["brief"]), ("ledger", p["ledger"]))))))
            w("<div class=tw><table class=steps><tr><th>#</th><th>Kind</th><th>Row</th><th>State</th></tr>" + "".join("<tr class='r-%s'><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>" % (x["cls"], esc(x["n"]), esc(x["kind"]), esc(x["step"]), esc(x["state"][:90])) for x in p["steps"]) + "</table></div></details>")
        w("</div>")
    else: w("<div class=card>No plan to summarise yet: %s</div>" % esc(args.plan_msg or "architecture/build-plan.md was not read."))
    w("<div id=plan-tables class=frag>")
    w(args.fragment or "")
    w("</div>")
    # footer
    w("<footer><h2>How these numbers are derived</h2><ul>")
    if L:
        sg = an["sig"]
        w("<li><b>Source.</b> The Claude Code session logs of this project on this machine (%d session file(s), %d sub-agent log(s)). Usage is counted once per message id, taking the maximum of each counter, because the log writes one record per streamed block (same method as the toolkit's token-burn.sh). Synthetic records are skipped. New tokens = input + output + cache write; cache reads are shown apart. Only numbers, timestamps, tool names and sub-agent short descriptions are used; no prompt or message text is copied into this page.</li>" % (args.n_sessions, len(agents)))
        w("<li><b>Cost.</b> Estimate only: tokens times placeholder list prices (see the token table), not an invoice. Cache write and read are priced separately. Set your own rates with a rates file (same format as token-burn.sh --rates) at .claude/progress-report-rates.txt.</li>")
        w("<li><b>Stage windows (approximate).</b> A stage starts at the first matching signal in the main thread: P = toolkit-init skill; 0 = first gate-check run; 1 = gate-check for stage 0 (else the extractor agent); 2 = first write of the BRD contract (else first BRD agent); 3 = gate-check for stage 2 (else a Stage 3 agent); 4 = a Stage 4 or build plan agent; 5 = a build skill. Windows are made monotonic. Detected starts: %s.</li>" %
          esc(", ".join("%s %s" % (s, local_hm(sg[s])) for s in STAGES if sg.get(s)) or "none"))
        w("<li><b>Attribution.</b> Main-thread requests go to the window they start in. Sub-agents go by description first (Stage N, inventory, extractor, BRD) and by start time otherwise, so a Stage 3 agent started during Stage 4 counts to Stage 3, while work done by the main thread in that window counts to Stage 4. Session time before the project existed is shown as Before Stage P.</li>")
        w("<li><b>Time.</b> Wall time is the window length. A gap of more than %d minutes between any two events is waiting for the user, overnight breaks included. A minute is sub-agent time when any sub-agent record span covers it, even if that agent was itself waiting on a tool.</li>" % (IDLE_GAP_S // 60))
    w("<li><b>Gate state.</b> From the PROJECT.md line under Current stage (gates passed list). The generated index.html table supplies titles and details; when it disagrees, PROJECT.md wins and a note appears. Progress for a stage that has not passed is promised artifacts present (toolkit artifact-manifest.tsv, entry mode %s); Stage 5 uses plan rows built.</li>" % esc(info["entry_mode"]))
    w("<li><b>Abbreviations.</b> BRD: business requirements document. This page uses no libraries and no network. Decisions: rows of the PROJECT.md Decisions table by Stage column; CONFIRMED means the user agreed, ASSUMED means the agent proceeded on a stated assumption, RAISED means an open question.</li>")
    w("<li><b>Known gaps.</b> Gate verdicts for Stages 5 and 6 cannot be evaluated before build; interactive time the user spends outside the session is not visible.</li>")
    shown = [esc(x) for x in args.sessions[:6]]
    logs_txt = ("<code>" + "</code>, <code>".join(shown) + "</code>" + (" and %d more" % (len(args.sessions) - 6) if len(args.sessions) > 6 else "")) if args.sessions else ("none found under <code>%s</code>" % esc(args.logs_base) if args.logs_base else "not read")
    how = "chosen with --session-log" if args.session_log else "found by discovery" + (", %d of them by path mention" % len(DISCOVERY["mention"]) if DISCOVERY.get("mention") else "")
    rates_txt = ("<code>%s</code>" % esc(args.rates_used)) if args.rates_used else "built-in placeholder rates (a file at <code>%s</code> or --rates would override them)" % esc(args.rates_default)
    regen = "project-bin/build-plan-status.sh &lt;project&gt; --html" + "".join(" --session-log &lt;path&gt;" for _ in args.session_log[:1])
    direct = "progress-report.py &lt;project&gt; " + (" ".join("--session-log <code>%s</code>" % esc(x) for x in args.session_log) if args.session_log else "--logs-dir &lt;dir&gt;")
    w("<li><b>Inputs.</b> Project folder: <code>%s</code>. Session log(s) (%s): %s. Rates file: %s. To regenerate with the same inputs: <code>%s</code>, or <code>%s</code>.</li>" % (esc(proj), how, logs_txt, rates_txt, regen, direct))
    w("</ul>")
    w("<div class=note id=stamp>Rebuild: project-bin/build-plan-status.sh --html. Setting in PROJECT.md: Progress report: off, ask or auto (now %s). Generated %s.</div></footer></div>%s</div></main>" % (esc(info["setting"]), gen, aside))
    w(JS)
    if args.reload:
        w("<script id=autoreload>(function(){var last=%d;if(Date.now()/1000-last<%d)setTimeout(function(){location.reload()},30000);})();</script>" % (int(args.last_act), ACTIVE_S))
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
    ap.add_argument("--plan-json", help="parsed build plan (build-plan-status.sh --json shape)")
    ap.add_argument("--plan-msg", default="")
    ap.add_argument("--logs-dir", help="folder holding the <slug>/ session log folders (default: <CLAUDE_CONFIG_DIR or ~/.claude>/projects)")
    ap.add_argument("--session-log", action="append", default=[], metavar="PATH", help="session log to use instead of discovery: a .jsonl file or a folder of them; repeatable")
    ap.add_argument("--no-log", action="store_true", help="skip session log discovery")
    a = ap.parse_args()
    proj = os.path.abspath(os.path.expanduser(a.project))
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
    a.fragment = read(a.fragment) if a.fragment else ""; a.plan_msg = a.plan_msg
    if a.session_log and not a.no_log:
        sessions, base = explicit_sessions(a.session_log), ""
    else: sessions, base = ([], "") if a.no_log else find_sessions(proj, a.logs_dir)
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
