#!/usr/bin/env bash
# token-burn.sh — how many tokens this project has burned, by model, by day and (best effort)
# by stage, read from the Claude Code transcripts on this machine.
#
#   bin/token-burn.sh <project-root>              # the screen: per model, per day, per stage
#   bin/token-burn.sh <project-root> --brief      # one line: "Tokens this stage: …" (status.sh)
#   bin/token-burn.sh <project-root> --scan-all   # look in every transcript dir, not only the
#                                                 # project's own and its ancestors/descendants
#   bin/token-burn.sh <project-root> --json       # the same numbers as one JSON object
#
# PRODUCER. The Claude Code harness (CLI, desktop app, IDE extension) writes one JSONL
# transcript per session under `$CLAUDE_CONFIG_DIR/projects/<slug>/<session>.jsonl` (default
# `~/.claude/projects`), plus `<slug>/<session>/subagents/agent-*.jsonl` for Agent-tool
# workers. `<slug>` is the launch directory with every non-alphanumeric character replaced by
# `-`. Nothing else produces that tree: a claude.ai chat, Cowork, Copilot, Cursor and Windsurf
# sessions leave no transcript here, and for them this instrument prints NOT AVAILABLE and
# exits 0 — an absent number, never a zero that reads as "free".
#
# WHAT IS COUNTED. Every `assistant` record's `message.usage`: input_tokens,
# cache_creation_input_tokens (cache write), cache_read_input_tokens, output_tokens, grouped
# by `message.model`. Three facts about the format, each learned from a real transcript
# (2026-09-18, a 17,000-line toolkit session) and each one a silent miscount if ignored:
#   1. The harness writes ONE RECORD PER STREAMED CONTENT BLOCK, all carrying the same
#      `message.id` and the same usage — that session had 4,336 assistant records for 1,989
#      messages. Summing records overcounts ~2×. Usage is summed ONCE per `message.id`.
#   2. `message.model` is `<synthetic>` on harness-generated records (aborts, errors). Skipped.
#   3. `cwd` is per RECORD, not per session, and a session launched in `~` can spend most of its
#      tokens inside `~/proj`. So records are attributed to the project by their own `cwd`
#      being at or under the project root (the `app/` two-tree layout is under the root, so it
#      needs nothing special), never by which slug directory they sit in. By default the slug
#      directories of the project itself, its ancestors and its descendants are read;
#      `--scan-all` reads every directory, for a project that moved or was symlinked.
#
# THE HEADLINE NUMBER is input + cache write + output. Cache READS are shown separately: they
# are the bulk of the count on any long session and are billed at a fraction of input, so
# folding them in makes every number meaningless. No currency is printed — pricing is per
# model, per plan and per month, and a number that is wrong next quarter is worse than none.
#
# STAGE ATTRIBUTION is by date, from the dated rows of the Decisions table in PROJECT.md
# (`| <stage> | … | CONFIRMED 2026-07-21 | …`): a day is attributed to the highest stage whose
# dated row is on or before it; days before the first dated row, and every day when there is
# no PROJECT.md, land in UNMAPPED. It is a step function over register dates, not a record of
# which stage a session was actually working — the caveat is printed with the table. Dispatch
# lines (runbook §1c) will sharpen it once they carry a stage and a date.
#
# Exit 0 always — this is read, never gated on. Bash 3.2 + Python 3 via lib/portable.sh.
set -u
TOOLKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/portable.sh
. "$TOOLKIT_ROOT/bin/lib/portable.sh"

PROJECT_DIR=""; MODE=screen; SCAN_ALL=0
for a in "$@"; do
  case "$a" in
    --brief) MODE=brief ;;
    --json) MODE=json ;;
    --scan-all) SCAN_ALL=1 ;;
    -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --*) echo "unknown option: $a" >&2; exit 1 ;;
    *) PROJECT_DIR="$a" ;;
  esac
done
[ -n "$PROJECT_DIR" ] || { echo "usage: bin/token-burn.sh <project-root> [--brief|--json] [--scan-all]" >&2; exit 1; }
PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd)" || { echo "not a directory: $1" >&2; exit 1; }

TRANSCRIPTS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
if [ ! -d "$TRANSCRIPTS" ]; then
  case "$MODE" in
    brief) echo "Tokens this stage: NOT AVAILABLE (no Claude Code transcript tree at $TRANSCRIPTS — claude.ai chat, Cowork, Copilot and Cursor sessions leave none)" ;;
    json)  printf '{"available": false, "reason": "no transcript tree at %s"}\n' "$TRANSCRIPTS" ;;
    *)     echo "NOT AVAILABLE — no Claude Code transcript tree at $TRANSCRIPTS (claude.ai chat, Cowork, Copilot and Cursor sessions leave none)" ;;
  esac
  exit 0
fi

require_py
"$PY" - "$PROJECT_DIR" "$TRANSCRIPTS" "$MODE" "$SCAN_ALL" <<'PYEOF'
import json, os, re, sys
from collections import defaultdict

project, root, mode, scan_all = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == "1"

def slug(path):
    return re.sub(r"[^A-Za-z0-9]", "-", path)

proj_slug = slug(project)

# --- which slug directories to read -------------------------------------------------------
dirs = []
for name in sorted(os.listdir(root)):
    full = os.path.join(root, name)
    if not os.path.isdir(full):
        continue
    if scan_all or name == proj_slug or proj_slug.startswith(name + "-") or name.startswith(proj_slug + "-"):
        dirs.append(full)

def jsonl_files(d):
    for entry in sorted(os.listdir(d)):
        p = os.path.join(d, entry)
        if entry.endswith(".jsonl") and os.path.isfile(p):
            yield p
        elif os.path.isdir(p):
            sub = os.path.join(p, "subagents")
            if os.path.isdir(sub):
                for e in sorted(os.listdir(sub)):
                    if e.endswith(".jsonl"):
                        yield os.path.join(sub, e)

def under_project(cwd):
    if not cwd:
        return False
    cwd = cwd.rstrip("/\\")
    return cwd == project or cwd.startswith(project + "/") or cwd.startswith(project + "\\")

# --- read ---------------------------------------------------------------------------------
KEYS = ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens")
seen = set()
by_model = defaultdict(lambda: [0, 0, 0, 0, 0])   # + message count
by_day = defaultdict(lambda: [0, 0, 0, 0, 0])
day_model = defaultdict(lambda: defaultdict(int)) # day -> model -> headline
sidechain = [0, 0]                                 # headline tokens: main, subagent
n_files = n_records = n_synthetic = 0

for d in dirs:
    for f in jsonl_files(d):
        n_files += 1
        with open(f, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                try:
                    rec = json.loads(line)
                except ValueError:
                    continue
                if rec.get("type") != "assistant":
                    continue
                msg = rec.get("message") or {}
                model = msg.get("model") or "?"
                if model == "<synthetic>":
                    n_synthetic += 1
                    continue
                if not under_project(rec.get("cwd")):
                    continue
                n_records += 1
                mid = msg.get("id") or rec.get("uuid") or (f + str(n_records))
                if mid in seen:
                    continue
                seen.add(mid)
                u = msg.get("usage") or {}
                vals = [int(u.get(k) or 0) for k in KEYS]
                day = (rec.get("timestamp") or "")[:10] or "????-??-??"
                for i, v in enumerate(vals):
                    by_model[model][i] += v
                    by_day[day][i] += v
                by_model[model][4] += 1
                by_day[day][4] += 1
                head = vals[0] + vals[1] + vals[3]
                day_model[day][model] += head
                sidechain[1 if rec.get("isSidechain") else 0] += head

def headline(v):
    return v[0] + v[1] + v[3]

# --- stage attribution from PROJECT.md ----------------------------------------------------
reg = os.path.join(project, "PROJECT.md")
stage_rows = []   # (date, stage_rank, stage_label)
def rank(s):
    return -1 if s == "P" else int(s)
if os.path.isfile(reg):
    with open(reg, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            m = re.match(r"^\|\s*(P|\d{1,2})\s*\|", line)
            if not m:
                continue
            for dt in re.findall(r"\b(\d{4}-\d{2}-\d{2})\b", line):
                stage_rows.append((dt, rank(m.group(1)), m.group(1)))
stage_rows.sort()

def stage_for(day):
    best = None
    for dt, r, label in stage_rows:
        if dt <= day and (best is None or r > best[0]):
            best = (r, label)
    return best[1] if best else "UNMAPPED"

current = None
if os.path.isfile(reg):
    with open(reg, encoding="utf-8", errors="replace") as fh:
        txt = fh.read()
    m = re.search(r"^## Current stage.*?\n\s*\*\*Stage\s+(P|\d{1,2})", txt, re.S | re.M)
    if m:
        current = m.group(1)

by_stage = defaultdict(lambda: [0, 0, 0, 0, 0])
stage_days = defaultdict(int)
stage_model = defaultdict(lambda: defaultdict(int))
for day, v in by_day.items():
    s = stage_for(day)
    for i in range(5):
        by_stage[s][i] += v[i]
    stage_days[s] += 1
    for mdl, h in day_model[day].items():
        stage_model[s][mdl] += h

def k(n):
    return "%dk" % round(n / 1000.0) if n >= 1000 else str(n)

def short(model):
    return re.sub(r"^claude-", "", model)

def split(mm):
    tot = sum(mm.values()) or 1
    parts = sorted(mm.items(), key=lambda kv: -kv[1])
    return " · ".join("%s %d%%" % (short(m), round(100.0 * h / tot)) for m, h in parts[:4])

total = [0, 0, 0, 0, 0]
for v in by_model.values():
    for i in range(5):
        total[i] += v[i]

caveat = ("stage = highest stage whose dated PROJECT.md row is on or before that day (UTC); "
          "UNMAPPED = before the first dated row" if stage_rows else
          "no dated stage rows in PROJECT.md — every day is UNMAPPED")

# --- output -------------------------------------------------------------------------------
if mode == "json":
    out = {
        "available": True, "project": project, "transcript_root": root, "dirs": dirs,
        "files": n_files, "records": n_records, "messages": len(seen), "synthetic_skipped": n_synthetic,
        "keys": list(KEYS) + ["messages"],
        "by_model": {m: v for m, v in by_model.items()},
        "by_day": {d: {"stage": stage_for(d), "usage": v} for d, v in sorted(by_day.items())},
        "by_stage": {s: {"days": stage_days[s], "usage": v, "models": dict(stage_model[s])} for s, v in by_stage.items()},
        "headline": {"main": sidechain[0], "subagents": sidechain[1]},
        "current_stage": current, "caveat": caveat,
    }
    print(json.dumps(out, indent=1, sort_keys=True))
    sys.exit(0)

if not seen:
    if mode == "brief":
        print("Tokens this stage: NOT AVAILABLE (no Claude Code transcript records with cwd under %s in %d dir(s) — try --scan-all)" % (project, len(dirs)))
    else:
        print("NOT AVAILABLE — %d transcript dir(s) read under %s, no assistant records with cwd under %s (try --scan-all)" % (len(dirs), root, project))
    sys.exit(0)

if mode == "brief":
    if current is None:
        s, note = "UNMAPPED", "no Current stage line in PROJECT.md"
    elif current in by_stage:
        s, note = current, "stage " + current
    else:
        s, note = None, "no day attributed to stage " + current
    if s:
        v = by_stage[s]
        print("Tokens this stage: %s (%s · %s cache-read · %d days · %s)" % (
            k(headline(v)), split(stage_model[s]), k(v[2]), stage_days[s], note))
    else:
        print("Tokens this stage: 0 (%s; project total %s · %s cache-read)" % (note, k(headline(total)), k(total[2])))
    sys.exit(0)

print("token-burn — %s" % os.path.basename(project))
print("  %d transcript file(s) in %d dir(s) under %s · %d messages (from %d records; %d synthetic skipped)" % (
    n_files, len(dirs), root, len(seen), n_records, n_synthetic))
print("  headline = input + cache-write + output · cache-read shown apart · no currency (see header)")
print()
fmt = "%-22s %9s %11s %11s %9s %9s %8s"
print(fmt % ("MODEL", "INPUT", "CACHE-WRITE", "CACHE-READ", "OUTPUT", "HEADLINE", "MSGS"))
for m, v in sorted(by_model.items(), key=lambda kv: -headline(kv[1])):
    print(fmt % (short(m), k(v[0]), k(v[1]), k(v[2]), k(v[3]), k(headline(v)), v[4]))
print(fmt % ("TOTAL", k(total[0]), k(total[1]), k(total[2]), k(total[3]), k(headline(total)), total[4]))
if sidechain[0] + sidechain[1]:
    print("  subagents (Agent tool): %s of headline (%d%%)" % (
        k(sidechain[1]), round(100.0 * sidechain[1] / (sidechain[0] + sidechain[1]))))
print()
fmt2 = "%-12s %-9s %9s %11s %6s  %s"
print(fmt2 % ("DAY (UTC)", "STAGE", "HEADLINE", "CACHE-READ", "MSGS", "MODEL SPLIT"))
for d, v in sorted(by_day.items()):
    print(fmt2 % (d, stage_for(d), k(headline(v)), k(v[2]), v[4], split(day_model[d])))
print()
fmt3 = "%-9s %5s %9s %11s %6s  %s"
print(fmt3 % ("STAGE", "DAYS", "HEADLINE", "CACHE-READ", "MSGS", "MODEL SPLIT"))
def stage_sort(s):
    return (99, "") if s == "UNMAPPED" else (rank(s), s)
for s in sorted(by_stage, key=stage_sort):
    v = by_stage[s]
    print(fmt3 % (s, stage_days[s], k(headline(v)), k(v[2]), v[4], split(stage_model[s])))
print("  caveat: %s" % caveat)
if current:
    print("  register says current stage %s%s" % (current, "" if current in by_stage else " — no day attributed to it yet"))
PYEOF
