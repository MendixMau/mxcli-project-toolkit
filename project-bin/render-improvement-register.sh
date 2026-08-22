#!/usr/bin/env bash
# render-improvement-register.sh — render docs/improvement-register.md as one HTML page.
#
# WHY THIS EXISTS. skills/improvement-register.md defines the per-project findings register —
# the append-only file whose whole point is the ACROSS-runs view ("is this the same class of
# defect for the fourth time, or four unrelated bugs?"). Every other stage artifact gets an
# HTML surface (the gate board, the enrichment report, module reviews, docs/verification/
# report.html); the register — the stakeholder-visibility story that "we are finding bugs and
# improving" — had none. Named 2026-08-22.
#
# RENDER ONLY, NO VERDICTS. Whether a finding is real, when a disposition may read "fixed",
# and what a recurring class means are judgement, and judgement lives in the skill
# (skills-over-scripts.md). This script counts and displays what the register already says:
#   - the findings table (id, dates, module, source pass, defect class, severity, disposition)
#   - counts by disposition-read and by severity (and defect class, when the column exists)
#   - the one thing the markdown cannot show: opened vs closed over time, derived from the
#     dates the rows themselves carry. Rows without dates get an honest "no trend" line —
#     the page never fakes a timeline.
# The disposition-read (open vs closed) is not a new judgement: it is the skill's own trend
# grep — "group by whether Disposition is 'fixed' or not" — applied verbatim. The raw
# disposition text is always shown next to it, so the read can be checked at a glance.
#
# PARSED DEFENSIVELY. The canonical row shape is the skill's 7-column table
# (Date | Module/Cluster | Source pass | Defect class | Severity | Finding | Disposition),
# but real registers drift — columns are mapped by header NAME, not position, so a register
# with an id column ("#") or "Found at" instead of "Date" still renders. A row the parser
# cannot read is COUNTED and reported on the page ("N rows unparsed"), never silently
# dropped: a page that quietly ate rows would under-report exactly the trend it exists to show.
#
# ABSENCE IS A FAULT, NEVER A PASS. No register file is exit 2 with the fix named — an empty
# green page over a project that never started its register would be the false green this
# toolkit exists to retire.
#
# Input : docs/improvement-register.md   (override: REGISTER_FILE=<path>)
# Output: docs/improvement-register.html (self-contained, no external assets; sits next to
#         the input, or set REGISTER_HTML=<path>)
# Env   : PROJECT_ROOT REGISTER_FILE REGISTER_HTML PYTHON
#
# Exit: 0 page written · 2 fault (no register / unreadable — nothing written)

set -uo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

REG="${REGISTER_FILE:-$PROJECT_ROOT/docs/improvement-register.md}"
if [ ! -f "$REG" ]; then
  echo "FAULT: no register at $REG" >&2
  echo "       No register yet: skills/improvement-register.md defines it — one project-level," >&2
  echo "       append-only docs/improvement-register.md, one row per P1/P2 finding." >&2
  echo "       Absence is not a pass, so no page was written. Set REGISTER_FILE=<path> if the" >&2
  echo "       register lives elsewhere." >&2
  exit 2
fi
OUT="${REGISTER_HTML:-${REG%.md}.html}"

require_py

REG="$REG" OUT="$OUT" "$PY" - <<'PY'
import html, os, re, sys, datetime
from collections import OrderedDict

REG = os.environ["REG"]
OUT = os.environ["OUT"]

try:
    with open(REG, encoding="utf-8") as f:
        raw = f.read()
except OSError as e:
    print(f"FAULT: could not read {REG}: {e}", file=sys.stderr)
    sys.exit(2)

# ── parse ────────────────────────────────────────────────────────────────────────────────────
# Markdown tables, columns mapped by header name. The current header mapping is carried across
# blank lines and prose: real registers (e.g. RoutingMgmt) split one logical table into several
# chunks separated by blank lines, and only the first chunk repeats the header row.
SEP_ROW = re.compile(r"^\s*\|?\s*:?-{2,}")          # |---|---| separator under a header
DATE_RE = re.compile(r"\d{4}-\d{2}-\d{2}")

def cells(line):
    return [c.strip() for c in line.strip().strip("|").split("|")]

def map_header(hdr_cells):
    """Header cell names -> canonical field, by name never by position."""
    m = {}
    for i, name in enumerate(hdr_cells):
        n = name.lower().strip("*` ")
        if n in ("#", "id"):                      m[i] = "id"
        elif "date" in n:                          m[i] = "date"
        elif "module" in n or "cluster" in n:      m[i] = "module"
        elif "source" in n or "found" in n:        m[i] = "source"
        elif "class" in n:                         m[i] = "defect_class"
        elif "severity" in n:                      m[i] = "severity"
        elif "finding" in n or n == "what" or "title" in n: m[i] = "finding"
        elif "disposition" in n or "status" in n:  m[i] = "disposition"
        # unrecognised columns are kept out of the mapping; their cells are ignored, the row
        # itself still parses — an extra column must not eat the whole row
    return m

lines = raw.splitlines()
rows, unparsed = [], []
header_map, header_len = None, 0
in_comment = False
i = 0
while i < len(lines):
    line = lines[i]
    # Commented-out example rows are documentation, not findings (a register may carry one —
    # bin/gate-check.sh handles the same case in decision registers).
    if in_comment:
        if "-->" in line: in_comment = False
        i += 1; continue
    if "<!--" in line and "-->" not in line:
        in_comment = True; i += 1; continue
    if not line.lstrip().startswith("|"):
        i += 1; continue
    if SEP_ROW.match(line):
        i += 1; continue
    cs = cells(line)
    nxt = lines[i + 1] if i + 1 < len(lines) else ""
    if SEP_ROW.match(nxt):                          # header row: next line is |---|---|
        header_map, header_len = map_header(cs), len(cs)
        i += 2; continue
    if header_map is None:
        unparsed.append(line.strip())
        i += 1; continue
    if len(cs) != header_len:
        unparsed.append(line.strip())
        i += 1; continue
    row = {f: "" for f in ("id", "date", "module", "source", "defect_class",
                           "severity", "finding", "disposition")}
    for idx, field in header_map.items():
        if idx < len(cs): row[field] = cs[idx]
    rows.append(row)
    i += 1

if not rows and not unparsed:
    print(f"FAULT: {REG} exists but contains no table rows this parser recognises.", file=sys.stderr)
    print( "       The register format is skills/improvement-register.md's markdown table —", file=sys.stderr)
    print( "       nothing was written; an empty-but-green page is not a pass.", file=sys.stderr)
    sys.exit(2)

# ── derive the facts the page shows ─────────────────────────────────────────────────────────
def esc(s): return html.escape(s, quote=True)

def strip_md(s):
    return re.sub(r"\*\*(.*?)\*\*", r"\1", s).replace("`", "")

# The skill's own trend grep: "group by whether Disposition is 'fixed' or not".
# fixed/resolved reads closed; everything else (deferred, superseded, blockers, blank) reads
# open. Applied to the disposition's LEADING clause only — the verdict word — because real
# dispositions go on to explain themselves ("Deferred — not fixed by silently adding...",
# "Superseded, not closed. Once IR-10 was fixed...") and a whole-text grep reads every such
# explanation as a close. Negations in the leading clause stay open. The raw text is shown
# alongside on the page, so this read is checkable, not authoritative.
def disp_read(disp):
    lead = re.split(r"\s+[—–-]{1,2}\s+|[.;:]\s", strip_md(disp), 1)[0]
    if re.search(r"\b(not|never|un-?fixed|unresolved)\b", lead, re.I):
        return "open"
    return "closed" if re.search(r"\b(fixed|resolved)\b", lead, re.I) else "open"

def sev_norm(sev):
    s = strip_md(sev)
    s = re.split(r"\s*[—(]", s, 1)[0].strip(" -–")
    return s if s else "(none)"

for n, r in enumerate(rows, 1):
    r["_status"] = disp_read(r["disposition"])
    r["_sev"] = sev_norm(r["severity"])
    m = DATE_RE.search(r["date"])
    r["_date"] = m.group(0) if m else ""
    if not r["id"]: r["id"] = str(n)

def count_by(key):
    c = OrderedDict()
    for r in rows:
        v = r[key] or "(none)"
        c[v] = c.get(v, 0) + 1
    return c

status_counts = count_by("_status")
sev_counts    = count_by("_sev")
class_counts  = count_by("defect_class") if any(r["defect_class"] for r in rows) else None

dated = sorted((r["_date"], r["_status"]) for r in rows if r["_date"])
trend = OrderedDict()   # date -> [opened, closed-read]
for d, st in dated:
    trend.setdefault(d, [0, 0])
    trend[d][0] += 1
    if st == "closed": trend[d][1] += 1

gen_at = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
proj = os.path.basename(os.path.dirname(os.path.dirname(os.path.abspath(REG)))) or "project"
reg_rel = os.path.relpath(REG)

# ── render ──────────────────────────────────────────────────────────────────────────────────
# Styling matches the project dashboard bin/gate-check.sh writes (index.html): an embedded
# minimal token set, not the toolkit's toolkit-guide.html :root block — this script runs
# inside consuming projects, where the toolkit path is unknown and the page must be
# self-contained anyway.
parts = []
parts.append(f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<!-- generated-by: mxcli-project-toolkit/project-bin/render-improvement-register.sh -->
<title>{esc(proj)} — Improvement Register</title>
<style>
  *, *::before, *::after {{ box-sizing: border-box; margin: 0; padding: 0; }}
  body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: #f8fafc; color: #1e293b; padding: 32px 40px; }}
  h1 {{ font-size: 22px; margin-bottom: 4px; }}
  h2 {{ font-size: 15px; margin: 28px 0 8px; }}
  .banner {{ background: #fef3c7; color: #92400e; border: 1px solid #fde68a; border-radius: 8px; padding: 10px 14px; font-size: 13px; margin-bottom: 20px; max-width: 1200px; }}
  .subtitle {{ color: #64748b; font-size: 13px; margin-bottom: 16px; }}
  table {{ border-collapse: collapse; width: 100%; max-width: 1200px; background: #fff; border: 1px solid #e2e8f0; border-radius: 8px; overflow: hidden; }}
  th, td {{ text-align: left; padding: 8px 12px; font-size: 13px; border-bottom: 1px solid #e2e8f0; vertical-align: top; }}
  th {{ background: #1e293b; color: #e2e8f0; font-weight: 600; }}
  tr:last-child td {{ border-bottom: none; }}
  .counts {{ display: flex; gap: 24px; flex-wrap: wrap; }}
  .counts table {{ width: auto; min-width: 220px; }}
  .status {{ font-weight: 700; padding: 2px 10px; border-radius: 999px; font-size: 11px; display: inline-block; white-space: nowrap; }}
  .closed {{ background: #dcfce7; color: #166534; }}
  .open   {{ background: #ffedd5; color: #9a3412; }}
  .warn   {{ background: #fee2e2; color: #991b1b; }}
  .bar    {{ display: inline-block; height: 10px; background: #94a3b8; vertical-align: middle; border-radius: 2px; }}
  .bar.c  {{ background: #16a34a; }}
  .muted  {{ color: #64748b; font-size: 12px; }}
  .footer {{ margin-top: 20px; font-size: 11px; color: #94a3b8; max-width: 1200px; }}
  code {{ background: #f1f5f9; padding: 1px 4px; border-radius: 3px; font-size: 12px; }}
</style>
</head>
<body>
<h1>{esc(proj)} — Improvement Register</h1>
<div class="subtitle">The across-runs findings view (skills/improvement-register.md). This page counts and displays; the judgement — what counts as a finding, when one may close, what a recurring class means — stays in the skill.</div>
<div class="banner"><b>Generated from {esc(reg_rel)} — do not edit; regenerate after the register changes.</b> Generated {gen_at} by bin/render-improvement-register.sh.</div>
""")

if unparsed:
    parts.append(f"""<div class="banner" style="background:#fee2e2;color:#991b1b;border-color:#fecaca;">
<b>{len(unparsed)} row(s) unparsed</b> — present in the register but not readable as table rows
(no header in scope, or a cell-count mismatch). They are NOT counted below; the register file
itself remains the authority. First unparsed row: <code>{esc(unparsed[0][:160])}</code></div>
""")

parts.append(f"<h2>Counts — {len(rows)} finding(s) parsed</h2>\n<div class=\"counts\">\n")
parts.append("<table><tr><th>Disposition read</th><th>Count</th></tr>\n")
for k in ("open", "closed"):
    if k in status_counts:
        parts.append(f"<tr><td><span class=\"status {k}\">{k.upper()}</span></td><td>{status_counts[k]}</td></tr>\n")
parts.append("</table>\n")
parts.append("<table><tr><th>Severity</th><th>Count</th></tr>\n")
for k, v in sorted(sev_counts.items(), key=lambda kv: -kv[1]):
    parts.append(f"<tr><td>{esc(k)}</td><td>{v}</td></tr>\n")
parts.append("</table>\n")
if class_counts:
    parts.append("<table><tr><th>Defect class</th><th>Count</th></tr>\n")
    for k, v in sorted(class_counts.items(), key=lambda kv: -kv[1]):
        parts.append(f"<tr><td>{esc(strip_md(k))}</td><td>{v}</td></tr>\n")
    parts.append("</table>\n")
parts.append("</div>\n")
parts.append("<div class=\"muted\" style=\"margin-top:8px;max-width:1200px;\">"
             "“Closed” here is the skill's own trend grep — a disposition containing "
             "<i>fixed</i> or <i>resolved</i> — not a verdict; the raw disposition text is in the "
             "table below. The trend read itself (3+ rows in one defect class is a process "
             "finding) is performed per the skill, not by this page.</div>\n")

# Trend — the thing the markdown cannot show.
parts.append("<h2>Trend — opened vs closed over time</h2>\n")
if trend:
    undated = len(rows) - sum(o for o, _ in trend.values())
    maxn = max(max(o, c) for o, c in trend.values()) or 1
    cum_o = cum_c = 0
    parts.append("<table><tr><th>Date</th><th>Opened</th><th>Closed (read)</th>"
                 "<th>Cumulative open</th><th></th></tr>\n")
    for d, (o, c) in trend.items():
        cum_o += o; cum_c += c
        w_o = int(140 * o / maxn); w_c = int(140 * c / maxn)
        parts.append(f"<tr><td>{esc(d)}</td><td>{o}</td><td>{c}</td><td>{cum_o - cum_c}</td>"
                     f"<td><span class=\"bar\" style=\"width:{max(w_o,2)}px\"></span> "
                     f"<span class=\"bar c\" style=\"width:{max(w_c,2) if c else 0}px\"></span></td></tr>\n")
    parts.append("</table>\n")
    parts.append("<div class=\"muted\" style=\"margin-top:6px;\">A row is counted “closed” on its "
                 "own (opening) date when its disposition already reads fixed/resolved — the register is "
                 "append-only, so a later fix arrives as a new row, which is when the close shows up here.</div>\n")
    if undated:
        parts.append(f"<div class=\"muted\" style=\"margin-top:6px;\"><b>{undated} of {len(rows)} rows carry "
                     f"no parseable date</b> and are not in this trend.</div>\n")
else:
    parts.append("<div class=\"banner\" style=\"background:#f1f5f9;color:#64748b;border-color:#e2e8f0;\">"
                 "No row in this register carries a parseable date (YYYY-MM-DD), so no opened-vs-closed "
                 "trend can be derived — this page will not fake one. The canonical row format in "
                 "skills/improvement-register.md puts the date in the first column; add dates to future "
                 "rows and the trend appears here.</div>\n")

# Findings table.
parts.append(f"<h2>Findings — all {len(rows)} row(s)</h2>\n")
parts.append("<table><tr><th>Id</th><th>Date</th><th>Module/Cluster</th><th>Source pass</th>"
             "<th>Defect class</th><th>Severity</th><th>Finding</th><th>Disposition</th></tr>\n")
for r in rows:
    parts.append(
        f"<tr><td>{esc(r['id'])}</td>"
        f"<td>{esc(r['_date'] or r['date'])}</td>"
        f"<td>{esc(strip_md(r['module']))}</td>"
        f"<td>{esc(strip_md(r['source']))}</td>"
        f"<td>{esc(strip_md(r['defect_class']))}</td>"
        f"<td>{esc(r['_sev'])}</td>"
        f"<td>{esc(strip_md(r['finding']))}</td>"
        f"<td><span class=\"status {r['_status']}\">{r['_status'].upper()}</span> "
        f"<span class=\"muted\">{esc(strip_md(r['disposition']))}</span></td></tr>\n")
parts.append("</table>\n")

parts.append(f"""<div class="footer">
Rendered from <code>{esc(reg_rel)}</code>. The register is append-only and stays the authority —
this page is a disposable render. Regenerate: <code>bin/render-improvement-register.sh</code>.
</div>
</body>
</html>
""")

os.makedirs(os.path.dirname(os.path.abspath(OUT)) or ".", exist_ok=True)
with open(OUT, "w", encoding="utf-8") as f:
    f.write("".join(parts))

print(f"improvement-register → {OUT}")
print(f"  rows      {len(rows)} parsed" + (f", {len(unparsed)} UNPARSED (shown on the page)" if unparsed else ""))
print(f"  status    " + "  ".join(f"{k}={v}" for k, v in status_counts.items()))
print(f"  severity  " + "  ".join(f"{k}={v}" for k, v in sev_counts.items()))
if trend:
    print(f"  trend     {len(trend)} dated day(s)")
else:
    print(f"  trend     NO DATES in any row — the page says so instead of faking one")
PY
