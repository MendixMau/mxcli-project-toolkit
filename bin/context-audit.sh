#!/usr/bin/env bash
# context-audit.sh — WHAT fills the context window, read from the Claude Code transcripts on
# this machine: which files are loaded or read, how often, what each costs, how full a session
# is before it does any work, and what was read before a session ran out of room.
#
#   bin/context-audit.sh                       # every session on this machine
#   bin/context-audit.sh --project <dir>       # only records whose cwd is at or under <dir>
#   bin/context-audit.sh --top 40              # longer tables (default 25)
#   bin/context-audit.sh --names               # print real project folder names (local use only)
#
# WHY. token-burn.sh says HOW MANY tokens a project burned; it cannot say WHICH file burned
# them. Deciding what to split, trim or stop routing needs the second number, per file, from
# real runs — not an estimate from `wc` on the skill files.
#
# SAFE TO PASTE. By default no project name leaves this machine: project folders print as
# project-1, project-2 …, and project file paths keep only generic parts (PROJECT.md,
# architecture/, mdlsource/ …) — every other path part becomes `*`, keeping the extension, so
# `architecture/modules/Billing-brief.md` prints as `architecture/modules/*.md` and the rows
# aggregate. Toolkit files print as `toolkit:<path>`. `--names` turns masking off.
#
# PRODUCER. The Claude Code harness writes one JSONL transcript per session under
# `$CLAUDE_CONFIG_DIR/projects/<slug>/<session>.jsonl` (default `~/.claude/projects`), and
# `<slug>/<session>/subagents/agent-*.jsonl` per Agent-tool worker. Nothing else produces it;
# claude.ai chat, Cowork, Copilot, Cursor and Windsurf leave none → NOT AVAILABLE, exit 0.
#
# WHAT IS MEASURED (sizes are characters / 4, printed as "≈tok"; exact counts are per model):
#   - start context: the first assistant call's input + cache write + cache read tokens — the
#     real, billed size of everything loaded before the session did anything.
#   - auto-loaded instruction files (CLAUDE.md, CLAUDE.local.md …): `instructions` attachments.
#   - file reads: the Read tool (exact path) and shell reads — cat/head/tail/sed/less/`git show
#     REV:path` naming ONE file. Shell reads are attributed best-effort; everything else a shell
#     prints lands in "shell output (other)".
#   - re-reads: the same file read again later in the same session.
#   - compactions: `compact_boundary` records, with the context size when they fired and the
#     files read in that session before the first one.
# Format facts, from a real transcript (2026-09-30): tool results are `tool_result` blocks in
# `user` records, content a string or a list of `{type:text}` blocks; usage repeats once per
# streamed block under one `message.id`, so the start context is read once per message.
#
# Exit 0 always — this reads, it never gates. Bash 3.2 + Python 3 via lib/portable.sh.
set -u
TOOLKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/portable.sh
. "$TOOLKIT_ROOT/bin/lib/portable.sh"

PROJECT_DIR=""; TOP=25; NAMES=0
while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT_DIR="${2:-}"; shift ;;
    --top) TOP="${2:-25}"; shift ;;
    --names) NAMES=1 ;;
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1 (see --help)" >&2; exit 1 ;;
  esac
  shift
done
case "$TOP" in ''|*[!0-9]*) echo "--top needs a number" >&2; exit 1 ;; esac
if [ -n "$PROJECT_DIR" ]; then
  PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd)" || { echo "not a directory: $PROJECT_DIR" >&2; exit 1; }
fi

TRANSCRIPTS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
if [ ! -d "$TRANSCRIPTS" ]; then
  echo "NOT AVAILABLE — no Claude Code transcript tree at $TRANSCRIPTS (claude.ai chat, Cowork, Copilot and Cursor sessions leave none)"
  exit 0
fi

require_py
"$PY" - "$TRANSCRIPTS" "$PROJECT_DIR" "$TOP" "$NAMES" "$TOOLKIT_ROOT" <<'PYEOF'
import json, os, re, shlex, sys
from collections import defaultdict

root, project, top, names, toolkit = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4] == "1", sys.argv[5]
toolkit = toolkit.rstrip("/")

GENERIC = {
    "PROJECT.md", "CLAUDE.md", "CLAUDE.local.md", "AGENTS.md", "intake.md", "index.html",
    "README.md", "build-plan.md", "build-plan.json", "blueprint.md", "ds.css", "design-system.html",
    "BUILD-LOG.md", "page-scope.json", "stack.env", "config.json", "package.json",
    "architecture", "design", "wireframes", "mdlsource", "analysis", "knowledge-base", "brd",
    "reports", "extracted", "docs", "modules", ".claude", "agents", "loop", "bin", "project-bin",
    "project-tests", "tests", "e2e", "gallery", "ui-reviews", "app", "sources", "theme",
    "themesource", "javascriptsource", "javasource", "resources", "widgets",
}

def under(path, base):
    return bool(base) and (path == base or path.startswith(base + "/") or path.startswith(base + "\\"))

TK_MARK = "/mxcli-project-toolkit/"

def toolkit_rel(p):
    if under(p, toolkit):
        return p[len(toolkit) + 1:]
    i = p.find(TK_MARK)
    return p[i + len(TK_MARK):] if i >= 0 else None

proj_label = {}
def label(cwd):
    if names:
        return cwd
    if cwd not in proj_label:
        proj_label[cwd] = "project-%d" % (len(proj_label) + 1)
    return proj_label[cwd]

def mask_rel(rel):
    parts = [x for x in re.split(r"[\\/]", rel) if x]
    out = []
    for i, x in enumerate(parts):
        if x in GENERIC:
            out.append(x)
        elif i == len(parts) - 1:
            ext = os.path.splitext(x)[1]
            out.append("*" + ext if ext else "*")
        else:
            out.append("*")
    return "/".join(out)

def show(path, cwd):
    """How a file path prints: toolkit:<rel>, <project>/<masked rel>, or other/<masked>."""
    if path.startswith("?/"):
        return "unknown-dir/" + (path[2:] if names else mask_rel(path[2:]))
    tk = toolkit_rel(path)
    if tk is not None:
        return "toolkit:" + tk
    if cwd and under(path, cwd):
        rel = path[len(cwd) + 1:]
        return label(cwd) + "/" + (rel if names else mask_rel(rel))
    if not os.path.isabs(path):
        return (label(cwd) + "/" if cwd else "") + (path if names else mask_rel(path))
    home = os.path.expanduser("~")
    if under(path, home):
        return "~/" + (path[len(home) + 1:] if names else mask_rel(path[len(home) + 1:]))
    return path if names else "other/" + mask_rel(os.path.basename(path))

def slug(p):
    return re.sub(r"[^A-Za-z0-9]", "-", p)

def transcripts():
    for d in sorted(os.listdir(root)):
        full = os.path.join(root, d)
        if not os.path.isdir(full):
            continue
        if project:
            ps = slug(project)
            if not (d == ps or ps.startswith(d + "-") or d.startswith(ps + "-")):
                continue
        for e in sorted(os.listdir(full)):
            p = os.path.join(full, e)
            if e.endswith(".jsonl") and os.path.isfile(p):
                yield p, False
            elif os.path.isdir(p):
                sub = os.path.join(p, "subagents")
                if os.path.isdir(sub):
                    for s in sorted(os.listdir(sub)):
                        if s.endswith(".jsonl"):
                            yield os.path.join(sub, s), True

def tok(n):
    return (n + 3) // 4

def text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "".join(b.get("text", "") for b in content if isinstance(b, dict))
    return ""

READERS = ("cat", "head", "tail", "sed", "less", "more", "bat", "nl")
PATHISH = re.compile(r"\.(md|sh|json|tsv|csv|html|js|ts|py|mdl|txt|css|yml|yaml|xml|java|star)$")

def shell_file(cmd, cwd):
    """The one file a simple read command prints, or None. Walks the `&&`/`;`/`|` segments in
    order, tracking `NAME=value` assignments and `cd <dir>`, and keeps the last segment that
    starts with a reader and names exactly one file-looking argument. A path still holding an
    unexpanded `$VAR` is reported by its file name only (the directory is unknown)."""
    env, base, found = {}, cwd or "", None
    def expand(w):
        return re.sub(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?", lambda m: env.get(m.group(1), m.group(0)), w)
    def resolve(f):
        f = expand(f)
        if "$" in f:
            return "?/" + os.path.basename(f)
        return f if os.path.isabs(f) else os.path.join(base, f)
    for seg in re.split(r"&&|\|\||;|\||\n", cmd):
        try:
            words = shlex.split(seg)
        except ValueError:
            continue
        while words and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", words[0]):
            n, v = words.pop(0).split("=", 1)
            env[n] = expand(v)
        if not words:
            continue
        w0 = os.path.basename(words[0])
        if w0 == "cd" and len(words) == 2:
            d = expand(words[1])
            if "$" not in d:
                base = d if os.path.isabs(d) else os.path.normpath(os.path.join(base, d))
            continue
        if w0 == "git" and len(words) >= 3 and "show" in words[1:4]:
            refs = [w for w in words if ":" in w and not w.startswith("-") and PATHISH.search(w)]
            if len(refs) == 1:
                found = resolve(refs[0].split(":", 1)[1])
            continue
        if w0 in READERS:
            fs = [w for w in words[1:] if not w.startswith("-") and PATHISH.search(w)]
            if len(fs) == 1:
                found = resolve(fs[0])
    return found

# ---------------------------------------------------------------------------------------------
files = defaultdict(lambda: {"reads": 0, "chars": 0, "sessions": set(), "rereads": 0})
instr = defaultdict(lambda: {"sessions": set(), "chars": 0})
buckets = defaultdict(lambda: [0, 0])      # tool bucket -> [calls, chars]
skills = defaultdict(int)
start_main, start_sub = [], []
compactions = []                            # (preTokens, trigger)
before_compact = defaultdict(lambda: [0, 0])  # file -> [sessions, chars]
n_main = n_sub = 0
days = set()

for path, is_sub in transcripts():
    pending = {}            # tool_use_id -> (kind, key, cwd)
    seen_files = set()
    reads_before = defaultdict(int)
    compacted = False
    first_usage = None
    sess_id = path
    touched = False
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            try:
                r = json.loads(line)
            except ValueError:
                continue
            cwd = (r.get("cwd") or "").rstrip("/\\")
            if project and cwd and not under(cwd, project):
                continue
            ts = r.get("timestamp") or ""
            if ts:
                days.add(ts[:10])
            t = r.get("type")
            if t == "attachment":
                a = r.get("attachment") or {}
                if a.get("type") == "instructions":
                    for f in a.get("files") or []:
                        k = show(f.get("path") or "?", cwd)
                        instr[k]["sessions"].add(sess_id)
                        instr[k]["chars"] = max(instr[k]["chars"], len(f.get("content") or ""))
                continue
            if t == "system" and r.get("subtype") == "compact_boundary":
                m = r.get("compactMetadata") or {}
                compactions.append((m.get("preTokens") or 0, m.get("trigger") or "?"))
                if not compacted:
                    for k, c in reads_before.items():
                        before_compact[k][0] += 1
                        before_compact[k][1] += c
                compacted = True
                continue
            msg = r.get("message") if isinstance(r.get("message"), dict) else {}
            content = msg.get("content")
            if t == "assistant":
                touched = True
                u = msg.get("usage") or {}
                if first_usage is None and u and msg.get("model") != "<synthetic>":
                    first_usage = sum(u.get(k) or 0 for k in ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"))
                for b in content if isinstance(content, list) else []:
                    if not isinstance(b, dict) or b.get("type") != "tool_use":
                        continue
                    name, inp = b.get("name") or "?", b.get("input") or {}
                    if name == "Read" and inp.get("file_path"):
                        # a paged read (offset/limit) of the next part is not a re-read; the same part again is
                        pending[b.get("id")] = ("file", show(inp["file_path"], cwd),
                                                "%s@%s+%s" % (inp["file_path"], max((inp.get("offset") or 1) - 1, 0),
                                                              inp.get("limit") or 2000))  # the Read tool's defaults
                    elif name == "Bash":
                        f = shell_file(inp.get("command") or "", cwd)
                        pending[b.get("id")] = ("file", show(f, cwd), "sh:" + f) if f else ("bucket", "shell output (other)", None)
                    elif name == "Skill":
                        skills[inp.get("skill") or "?"] += 1
                        pending[b.get("id")] = ("bucket", "Skill loads", None)
                    elif name.startswith("mcp__"):
                        pending[b.get("id")] = ("bucket", "MCP: " + name.split("__")[1], None)
                    else:
                        pending[b.get("id")] = ("bucket", name, None)
            elif t == "user" and isinstance(content, list):
                for b in content:
                    if not isinstance(b, dict) or b.get("type") != "tool_result":
                        continue
                    kind, key, real = pending.pop(b.get("tool_use_id"), ("bucket", "unmatched", None))
                    n = len(text_of(b.get("content")))
                    if kind == "file":
                        f = files[key]
                        f["reads"] += 1
                        f["chars"] += n
                        f["sessions"].add(sess_id)
                        # re-reads are judged on the REAL path: masked keys merge distinct files
                        real = (real or key)[3:] if (real or "").startswith("sh:") else (real or key)
                        if real in seen_files:
                            f["rereads"] += 1
                        seen_files.add(real)
                        if not compacted:
                            reads_before[key] += n
                    else:
                        buckets[key][0] += 1
                        buckets[key][1] += n
    if not touched:
        continue
    if is_sub:
        n_sub += 1
        if first_usage:
            start_sub.append(first_usage)
    else:
        n_main += 1
        if first_usage:
            start_main.append(first_usage)

# ---------------------------------------------------------------------------------------------
def pct(xs, p):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(round(p * (len(xs) - 1))))] if xs else 0

def table(rows, heads):
    w = [max(len(str(h)), *(len(str(r[i])) for r in rows)) if rows else len(h) for i, h in enumerate(heads)]
    print("  " + "  ".join(str(h).ljust(w[i]) if i == 0 else str(h).rjust(w[i]) for i, h in enumerate(heads)))
    for r in rows:
        print("  " + "  ".join(str(c).ljust(w[i]) if i == 0 else str(c).rjust(w[i]) for i, c in enumerate(r)))

def k(n):
    return "{:,}".format(n)

if not n_main and not n_sub:
    print("No sessions found%s." % (" for " + project if project else ""))
    sys.exit(0)

span = "%s .. %s" % (min(days), max(days)) if days else "?"
print("Context audit — %d session(s), %d subagent run(s), %s%s" % (n_main, n_sub, span, "" if names else "  (names masked; --names to show)"))
print("Sizes marked ≈tok are characters/4. 'Start' is the billed size of the first call.\n")

print("1. Context before any work (first call: input + cache write + cache read)")
table([[lbl, len(xs), k(pct(xs, .5)), k(pct(xs, .9)), k(max(xs) if xs else 0)]
       for lbl, xs in (("sessions", start_main), ("subagent runs", start_sub)) if xs],
      ["", "runs", "median", "p90", "max"])
print()

print("2. Loaded automatically every session (instruction files)")
rows = sorted(([p, len(v["sessions"]), k(tok(v["chars"]))] for p, v in instr.items()), key=lambda r: -int(r[2].replace(",", "")))
table(rows[:top], ["file", "runs", "≈tok each"]) if rows else print("  (none recorded)")
print()

print("3. Files read, by total context spent (Read tool + simple shell reads)")
rows = sorted(files.items(), key=lambda kv: -kv[1]["chars"])
table([[p, v["reads"], len(v["sessions"]), k(tok(v["chars"])), k(tok(v["chars"] // max(v["reads"], 1))), v["rereads"]]
       for p, v in rows[:top]], ["file", "reads", "sessions", "≈tok total", "≈tok/read", "re-reads"]) if rows else print("  (none)")
tk_total = sum(v["chars"] for p, v in files.items() if p.startswith("toolkit:"))
all_total = sum(v["chars"] for v in files.values())
rr = sum(v["rereads"] * (v["chars"] // max(v["reads"], 1)) for v in files.values())
if all_total:
    print("  toolkit files: ≈%s tok of ≈%s tok read (%d%%); re-reads cost ≈%s tok"
          % (k(tok(tk_total)), k(tok(all_total)), 100 * tk_total // all_total, k(tok(rr))))
print()

print("4. Other tool output, by context spent")
rows = sorted(buckets.items(), key=lambda kv: -kv[1][1])
table([[b, v[0], k(tok(v[1]))] for b, v in rows[:top]], ["tool", "calls", "≈tok total"]) if rows else print("  (none)")
if skills:
    print("  skills invoked: " + ", ".join("%s ×%d" % (s, n) for s, n in sorted(skills.items(), key=lambda x: -x[1])[:top]))
print()

print("5. Compactions (the session ran out of room)")
if compactions:
    pre = [p for p, _ in compactions if p]
    auto = sum(1 for _, t in compactions if t == "auto")
    print("  %d compaction(s), %d automatic; context when it fired: median %s, max %s tokens"
          % (len(compactions), auto, k(pct(pre, .5)), k(max(pre) if pre else 0)))
    rows = sorted(before_compact.items(), key=lambda kv: -kv[1][1])
    if rows:
        print("  read before the first compaction, most context first:")
        table([[p, v[0], k(tok(v[1]))] for p, v in rows[:min(top, 15)]], ["file", "sessions", "≈tok"])
else:
    print("  none")
PYEOF
