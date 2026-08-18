#!/bin/bash
# questions-report.sh — render a project's open questions as a reviewable HTML page.
#
# WHY THIS EXISTS
# ---------------
# bin/open-questions.sh already produces a chat-ready batch. That solves "the agent has the
# questions". It does not solve the two things the user actually reported missing:
#
#   1. There is no surface showing WHAT WAS FOUND — what got examined, what is still open,
#      and which open items are blocking — that a human can read away from the terminal.
#   2. Most questions arrive with no proposed answer. A question with no proposed answer is
#      work handed back to the user. A question with two named options and a recommendation
#      is a decision they can make in five seconds.
#
# This script renders (1), and marks every question that lacks (2) as a defect in the
# generating stage rather than quietly presenting a bare question.
#
# Usage:
#   bin/questions-report.sh <project-dir> [--stage N] [-o <output.html>] [--quiet]
#
# Default output: <project-dir>/docs/open-questions.html
#
# Exit codes: 0 = report written, nothing blocking. 1 = report written, blocking questions
#             exist. 2 = usage/environment error. 3 = nothing was examined (NOT a clean
#             result — same meaning as open-questions.sh).

set -uo pipefail

# Portability: resolve a real Python 3 by EXECUTING candidates, not by looking one up on PATH.
# On Windows `python3` is usually the Microsoft Store alias stub, which `command -v` finds and
# which then opens the Store instead of running. See bin/lib/portable.sh.
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/portable.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECTOR="$SCRIPT_DIR/open-questions.sh"

PROJECT_DIR=""
STAGE_ARGS=()
OUT=""
QUIET=0

while [ $# -gt 0 ]; do
  case "$1" in
    --stage) STAGE_ARGS+=(--stage "${2:-}"); shift 2 ;;
    -o|--output) OUT="${2:-}"; shift 2 ;;
    --quiet) QUIET=1; shift ;;
    -h|--help) sed -n '2,28p' "${BASH_SOURCE[0]}"; exit 0 ;;
    -*) echo "questions-report.sh: unknown option $1" >&2; exit 2 ;;
    *) if [ -z "$PROJECT_DIR" ]; then PROJECT_DIR="$1"; else STAGE_ARGS+=("$1"); fi; shift ;;
  esac
done

[ -n "$PROJECT_DIR" ] || { echo "usage: questions-report.sh <project-dir> [--stage N] [-o out.html]" >&2; exit 2; }
[ -d "$PROJECT_DIR" ] || { echo "questions-report.sh: not a directory: $PROJECT_DIR" >&2; exit 2; }
[ -x "$COLLECTOR" ] || [ -f "$COLLECTOR" ] || { echo "questions-report.sh: collector not found: $COLLECTOR" >&2; exit 2; }

PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
[ -n "$OUT" ] || OUT="$PROJECT_DIR/docs/open-questions.html"

JSON=$(bash "$COLLECTOR" "$PROJECT_DIR" "${STAGE_ARGS[@]+"${STAGE_ARGS[@]}"}" --json 2>/dev/null)
COLLECT_RC=$?

# rc 3 means no BRDs and no sme-questions.md were found. That is not "no open questions";
# it means the instrument found nothing to read, and reporting it as clean is the exact
# class of false-green this toolkit keeps getting bitten by.
# Belt and braces: the flag is read from the payload as well as the exit code. rc=3 was
# unreachable in --json mode until 2026-08-12, and this script trusting it alone is how that
# went unnoticed — it rendered a clean-looking report over an empty directory.
NOTHING=$(printf '%s' "$JSON" | grep -c '"nothingExamined": *true' | head -1)
if [ "$COLLECT_RC" -eq 3 ] || [ "${NOTHING:-0}" -gt 0 ] || [ -z "$JSON" ]; then
  echo "questions-report.sh: nothing was examined (no BRDs, no sme-questions.md) — refusing to" >&2
  echo "  write a report that would read as 'no open questions'. Exit 3." >&2
  exit 3
fi

mkdir -p "$(dirname "$OUT")" || { echo "questions-report.sh: cannot create $(dirname "$OUT")" >&2; exit 2; }

require_py

PROJECT_NAME="$(basename "$PROJECT_DIR")"
GENERATED="$(date '+%Y-%m-%d %H:%M')"

# The collector's JSON goes through a temp FILE, not a pipe. `"$PY" - <<'PYEOF'` takes its
# program from stdin, so a pipe into the same command is swallowed by the heredoc and json.load
# reads an empty string. Costing a temp file is cheaper than an inline-quoted program.
JSON_TMP=$(mktemp "${TMPDIR:-/tmp}/qreport.XXXXXX.json") || exit 2
trap 'rm -f "$JSON_TMP"' EXIT
printf '%s' "$JSON" > "$JSON_TMP"

PROJECT_NAME="$PROJECT_NAME" GENERATED="$GENERATED" JSON_TMP="$JSON_TMP" \
  PROJECT_DIR="$PROJECT_DIR" OUT="$OUT" "$PY" - <<'PYEOF'
import html, json, os, sys

with open(os.environ["JSON_TMP"], encoding="utf-8") as fh:
    d = json.load(fh)
qs = d.get("questions", [])
counts = d.get("counts", {})
ex = d.get("examined", {})
blocking = d.get("blocking", 0)
project = os.environ["PROJECT_NAME"]
generated = os.environ["GENERATED"]
out_path = os.environ["OUT"]

BLOCKING_STATES = {"UNRAISED", "UNRECOGNISED"}

# Order: what needs the user first, then what is merely on record.
ORDER = ["UNRECOGNISED", "UNRAISED", "RAISED", "ASSUMED", "ANSWERED", "MOOT"]
STATE_NOTE = {
    "UNRAISED":     "Never put to you. These block the gate.",
    "UNRECOGNISED": "Status text no rule could map. Treated as unraised — a status nobody can parse is not an answer.",
    "RAISED":       "Put to you, awaiting your reply.",
    "ASSUMED":      "A position was taken AND you consented to it. Recorded, not blocking.",
    "ANSWERED":     "Settled with a recorded answer.",
    "MOOT":         "Descoped — genuinely dead, not silently dropped.",
}

def esc(s):
    return html.escape(str(s or ""))

# A question the user can act on needs a proposed answer. One without is not "a question",
# it is unfinished work by the stage that produced it — so it gets called out as such.
def has_proposal(q):
    return bool((q.get("assumption") or "").strip())

groups = {}
for q in qs:
    groups.setdefault(q.get("state", "UNRECOGNISED"), []).append(q)

actionable = [q for q in qs if q.get("state") in BLOCKING_STATES]
no_proposal = [q for q in actionable if not has_proposal(q)]

rows = []
for st in ORDER:
    n = counts.get(st, 0)
    if n:
        cls = "b" if st in BLOCKING_STATES else ""
        rows.append(f'<tr class="{cls}"><td><code>{st}</code></td><td class="num">{n}</td><td>{esc(STATE_NOTE.get(st,""))}</td></tr>')
tbl = "\n".join(rows)

stage_filter = ex.get("stageFilter")
scope = f"stage &le; {esc(stage_filter)}" if stage_filter else "all stages"

cards = []
for st in ORDER:
    items = groups.get(st, [])
    if not items:
        continue
    badge = "block" if st in BLOCKING_STATES else "ok"
    cards.append(f'<h2>{esc(st)} <span class="count">{len(items)}</span></h2>')
    cards.append(f'<p class="note">{esc(STATE_NOTE.get(st,""))}</p>')
    for q in items:
        prop = (q.get("assumption") or "").strip()
        raw = (q.get("rawStatus") or "").strip()
        reason = (q.get("reason") or "").strip()
        bits = [f'<div class="q {badge}">']
        bits.append(f'<div class="qid">{esc(q.get("id","?"))} <span class="src">{esc(q.get("origin",""))}</span></div>')
        bits.append(f'<div class="qtext">{esc(q.get("question",""))}</div>')
        if prop:
            bits.append(
                '<div class="prop"><span class="lbl">Drafting position — confirm or overturn</span>'
                f'<div>{esc(prop)}</div></div>')
        elif st in BLOCKING_STATES:
            bits.append(
                '<div class="gap"><span class="lbl">No proposed answer</span>'
                '<div>This question was handed over bare. Before putting it to the user, the owning '
                'stage should propose at least two named options and a recommendation — otherwise the '
                'user is being asked to do the analysis the stage was meant to do.</div></div>')
        meta = []
        if raw:
            meta.append(f'recorded as: <code>{esc(raw[:160])}</code>')
        if reason:
            meta.append(esc(reason))
        if q.get("stage") is not None:
            meta.append(f'stage {esc(q.get("stage"))}')
        if meta:
            bits.append('<div class="meta">' + " &middot; ".join(meta) + "</div>")
        bits.append("</div>")
        cards.append("".join(bits))

banner_cls = "fail" if blocking else "pass"
banner_txt = (f"{blocking} question(s) have never been put to the user — this gate is blocked."
              if blocking else
              "No unraised questions. Every question on record has been seen by the user.")

gapline = ""
if no_proposal:
    gapline = (f'<div class="banner warn"><b>{len(no_proposal)} of {len(actionable)} blocking questions '
               f'arrive with no proposed answer.</b> They are listed below and marked. A bare question '
               f'moves the work to the user; a question with two options and a recommendation takes them '
               f'seconds. Fix these in the stage that generated them.</div>')

doc = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Open questions — {esc(project)}</title>
<style>
  /* Shell copied from toolkit-guide.html so every project surface reads as one system. */
  :root {{
    --bg:#f8fafc; --surface:#ffffff; --ink:#1e293b; --ink-soft:#64748b; --ink-faint:#94a3b8;
    --line:#e2e8f0; --accent:#0f4c81;
    --pass-bg:#dcfce7; --pass-ink:#166534;
    --fail-bg:#fee2e2; --fail-ink:#991b1b;
    --warn-bg:#fef3c7; --warn-ink:#92400e;
    --radius:10px;
    --font:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
    --mono:ui-monospace,'SF Mono',Menlo,monospace;
  }}
  * {{ box-sizing:border-box; }}
  body {{ margin:0; background:var(--bg); color:var(--ink); font-family:var(--font); line-height:1.55; }}
  .wrap {{ max-width:980px; margin:0 auto; padding:32px 20px 64px; }}
  h1 {{ font-size:24px; margin:0 0 4px; }}
  h2 {{ font-size:15px; text-transform:uppercase; letter-spacing:.06em; color:var(--ink-soft);
       margin:34px 0 4px; border-bottom:1px solid var(--line); padding-bottom:6px; }}
  .count {{ background:var(--line); color:var(--ink-soft); border-radius:999px;
            padding:1px 9px; font-size:12px; letter-spacing:0; }}
  .sub {{ color:var(--ink-soft); font-size:14px; margin:0 0 20px; }}
  .banner {{ border-radius:var(--radius); padding:13px 16px; margin:16px 0; font-size:14px; }}
  .banner.pass {{ background:var(--pass-bg); color:var(--pass-ink); }}
  .banner.fail {{ background:var(--fail-bg); color:var(--fail-ink); }}
  .banner.warn {{ background:var(--warn-bg); color:var(--warn-ink); }}
  table {{ border-collapse:collapse; width:100%; background:var(--surface);
           border:1px solid var(--line); border-radius:var(--radius); overflow:hidden; font-size:14px; }}
  th,td {{ text-align:left; padding:9px 13px; border-bottom:1px solid var(--line); }}
  th {{ background:#f1f5f9; font-size:12px; text-transform:uppercase; letter-spacing:.05em; color:var(--ink-soft); }}
  tr:last-child td {{ border-bottom:none; }}
  tr.b td {{ background:#fff7f7; }}
  td.num {{ font-family:var(--mono); text-align:right; width:70px; }}
  .note {{ color:var(--ink-faint); font-size:13px; margin:0 0 12px; }}
  .q {{ background:var(--surface); border:1px solid var(--line); border-left:3px solid var(--ink-faint);
        border-radius:var(--radius); padding:14px 16px; margin:10px 0; }}
  .q.block {{ border-left-color:#dc2626; }}
  .q.ok {{ border-left-color:#94a3b8; }}
  .qid {{ font-family:var(--mono); font-size:12px; color:var(--accent); font-weight:600; margin-bottom:5px; }}
  .src {{ color:var(--ink-faint); font-weight:400; }}
  .qtext {{ font-size:15px; }}
  .prop, .gap {{ margin-top:10px; padding:9px 12px; border-radius:8px; font-size:14px; }}
  .prop {{ background:var(--warn-bg); color:var(--warn-ink); }}
  .gap {{ background:#f1f5f9; color:var(--ink-soft); }}
  .lbl {{ display:block; font-size:11px; text-transform:uppercase; letter-spacing:.06em;
          font-weight:700; margin-bottom:3px; opacity:.85; }}
  .meta {{ margin-top:9px; font-size:12px; color:var(--ink-faint); }}
  code {{ font-family:var(--mono); font-size:.9em; background:#f1f5f9; padding:1px 5px; border-radius:4px; }}
  .footer {{ margin-top:44px; padding-top:14px; border-top:1px solid var(--line);
             color:var(--ink-faint); font-size:12px; }}
  @media print {{ body {{ background:#fff; }} .q {{ break-inside:avoid; }} }}
</style></head>
<body><div class="wrap">
  <h1>Open questions — {esc(project)}</h1>
  <p class="sub">Generated {esc(generated)} &middot; scope: {scope} &middot;
     examined {esc(ex.get("brdFiles",0))} BRD file(s) and {esc(ex.get("smeQuestionFiles",0))} SME question file(s),
     {esc(ex.get("duplicatesCollapsed",0))} duplicate(s) collapsed</p>

  <div class="banner {banner_cls}">{esc(banner_txt)}</div>
  {gapline}

  <h2>What was found</h2>
  <table><tr><th>State</th><th class="num">Count</th><th>Meaning</th></tr>
  {tbl}
  </table>

  {"".join(cards)}

  <div class="footer">
    mxcli-project-toolkit &middot; generated by <code>bin/questions-report.sh</code> from
    <code>bin/open-questions.sh --json</code>. Regenerate after answering: rerun the same command.
    An <code>ASSUMED</code> state without recorded consent is normalised to <code>UNRAISED</code> and
    blocks &mdash; a position the user never saw is not an assumption they made.
  </div>
</div></body></html>
"""

with open(out_path, "w") as f:
    f.write(doc)
PYEOF

PY_RC=$?
[ "$PY_RC" -eq 0 ] || { echo "questions-report.sh: render failed (python exit $PY_RC)" >&2; exit 2; }

if [ "$QUIET" -eq 0 ]; then
  echo "Wrote: $OUT"
  # Reads the temp file, not a pipe, and no 2>/dev/null: a summary that silently prints
  # nothing when it breaks is worse than one that says why.
  JSON_TMP="$JSON_TMP" "$PY" - <<'PYSUM'
import json, os
with open(os.environ["JSON_TMP"], encoding="utf-8") as fh:
    d = json.load(fh)
c = d.get("counts", {})
qs = d.get("questions", [])
bare = [q for q in qs
        if q.get("state") in ("UNRAISED", "UNRECOGNISED")
        and not (q.get("assumption") or "").strip()]
print("  blocking: %s   total: %s   without a proposed answer: %s"
      % (d.get("blocking", 0), c.get("total", 0), len(bare)))
PYSUM
fi

[ "$COLLECT_RC" -eq 1 ] && exit 1
exit 0
