#!/bin/bash
# triage-report.sh — render a project's triage.md as analysis/triage.html.
#
# WHY THIS EXISTS. skills/conversion-runbook.md's Stage 0 row has promised
# "| **Surface** | `source-sufficiency.html`, `triage.html` |" for months, and nothing in this
# repo generated the second one. A phantom surface is worse than a missing one: a reader takes
# the row as a checklist, cannot find the file, and either hand-rolls an HTML page or quietly
# treats the whole row as aspirational. Meanwhile triage.md itself was unscaffolded, so the one
# project that produced one drifted from the skill (see bin/lib/triage-template.sh's header).
# The scaffold is the fix; this is the presentation layer over it.
#
# WHY IT IS SEPARATE FROM source-sufficiency.sh. They answer different questions and are
# different rows of the routing table: source-sufficiency GRADES THE CORPUS ("what can this
# source support"), triage DECIDES THE PIPELINE ("do we reuse an extractor or build one, and in
# what order do capabilities go"). Merging them also makes the documents-only skip path awkward
# — that path runs the sufficiency report and explicitly does NOT run triage
# (conversion-runbook.md, Stage 0) — and source-sufficiency.sh is already ~650 lines.
#
# WHAT THIS IS NOT — and this is the load-bearing part. It does not validate, grade or judge
# the triage. No "you left a capability out", no "that verdict is not one of the five", no
# check that the reuse-vs-build-new answer is a two-way one. Per skills/skills-over-scripts.md
# this script is code only under row 2 (byte-identical output, no agent present); every
# judgement about a triage belongs in skills/source-triage.md, and the guard against inventing
# a third extraction option lives in the template the author is typing into, not in a parser
# written by the same person who wrote the format. `gate-check.sh <project> 0` is the only
# thing with an opinion here, and its opinion is exactly one line long: is it signed off.
#
# So the markdown subset below is deliberately small and closed: headings, tables, bold, inline
# code, lists, paragraphs, rules, HTML comments. It renders what bin/lib/triage-template.sh
# produces. It is not a markdown parser and must not grow into one.
#
# Usage:
#   triage-report.sh <project-dir> [--html PATH] [--quiet]
#
# Bash 3.2 + any Python 3 (resolved by lib/portable.sh, not assumed to be named `python3`).
# Read-only with respect to triage.md and the Mendix model.

set -u

# Portability: resolve a real Python 3 by EXECUTING candidates, not by looking one up on PATH.
# On Windows `python3` is usually the Microsoft Store alias stub, which `command -v` finds and
# which then opens the Store instead of running. See bin/lib/portable.sh.
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/portable.sh"

usage() {
  cat >&2 <<'USAGE'
usage: triage-report.sh <project-dir> [--html PATH] [--quiet]

  Renders <project>/triage.md (or <analysis-base>/triage.md) to analysis/triage.html.
  Fill triage.md in by following skills/source-triage.md; sign it off, then
  `bin/gate-check.sh <project> 0`. This script renders — it never grades.

exit 0 rendered   2 usage   3 no triage.md   4 two different triage.md files
USAGE
  exit 2
}

PROJECT_DIR="${1:-}"
shift 1 2>/dev/null || true
[ -n "$PROJECT_DIR" ] || usage
case "$PROJECT_DIR" in -*) usage ;; esac
[ -d "$PROJECT_DIR" ] || { echo "triage-report: not a directory: $PROJECT_DIR" >&2; exit 2; }

HTML_OUT=""
QUIET=0
while [ $# -gt 0 ]; do
  case "$1" in
    --html)    HTML_OUT="${2:-}"; shift 2 ;;
    --quiet)   QUIET=1; shift ;;
    -h|--help) usage ;;
    *) echo "triage-report: unknown option: $1" >&2; usage ;;
  esac
done

# --- resolving triage.md ------------------------------------------------------------------
#
# THIS MUST MATCH bin/gate-check.sh:380 (check_stage_0 → resolve_stage_file). Two locations,
# root first, and two DIFFERING copies is a refusal rather than a guess: one of them is stale
# and only a human knows which, so a single rendered page cannot honestly describe both.
# Byte-identical copies are not ambiguous — either one renders the same.
#
# NOT extracted into a shared bin/lib helper, and the reason is worth writing down rather than
# rediscovering. gate-check's version is not a two-line path test: ANALYSIS_BASE is derived
# from its knowledge-base scan, which collects every analysis/*/knowledge-base, REFUSES with
# exit 2 on more than one workstream unless $GATE_WORKSTREAM selects it, and only then takes
# the KB dir's parent. Lifting that out means lifting the multi-workstream refusal and its exit
# codes into a library shared with a renderer that has no business refusing anything. The
# duplicated part here is the small half — the resolution — and it carries this cross-reference
# so the two stay in step. If a third caller ever needs it, extract then, with the refusal.
ANALYSIS_BASE="$PROJECT_DIR"
KB_COUNT=0
for candidate in "$PROJECT_DIR"/analysis/*/knowledge-base; do
  [ -d "$candidate" ] || continue
  KB_COUNT=$((KB_COUNT + 1))
  ANALYSIS_BASE="$(dirname "$candidate")"
done
# More than one workstream: no single analysis base, so only the root copy is well-defined.
# gate-check refuses here; a renderer falls back to the root rather than picking a workstream.
[ "$KB_COUNT" -gt 1 ] && ANALYSIS_BASE="$PROJECT_DIR"

ROOT_F="$PROJECT_DIR/triage.md"
BASE_F="$ANALYSIS_BASE/triage.md"
TRIAGE=""
if [ "$ROOT_F" != "$BASE_F" ] && [ -f "$ROOT_F" ] && [ -f "$BASE_F" ] && ! cmp -s "$ROOT_F" "$BASE_F"; then
  echo "triage-report: two different triage.md files — $ROOT_F and $BASE_F —" >&2
  echo "  a single Stage 0 page cannot describe both; delete or merge the stale one" >&2
  echo "  (the analysis/<name>/ copy is normally the live one) and re-run." >&2
  exit 4
fi
for p in "$ROOT_F" "$BASE_F"; do
  if [ -f "$p" ]; then TRIAGE="$p"; break; fi
done
if [ -z "$TRIAGE" ]; then
  echo "triage-report: no triage.md (looked in $PROJECT_DIR/ and $ANALYSIS_BASE/)" >&2
  echo "  scaffold one with: bin/init-project.sh $PROJECT_DIR" >&2
  echo "  then fill it in per skills/source-triage.md" >&2
  exit 3
fi

[ -n "$HTML_OUT" ] || HTML_OUT="$PROJECT_DIR/analysis/triage.html"

# Was: `command -v python3` — which succeeds on the Windows Store alias stub. require_py probes
# by running the interpreter, so a stub fails here instead of halfway through a stage.
require_py

mkdir -p "$(dirname "$HTML_OUT")" 2>/dev/null || true

TRIAGE="$TRIAGE" HTML_OUT="$HTML_OUT" QUIET="$QUIET" PROJECT_DIR="$PROJECT_DIR" "$PY" <<'PY'
import html as H, os, re, sys, datetime

src      = os.environ['TRIAGE']
html_out = os.environ['HTML_OUT']
quiet    = os.environ['QUIET'] == '1'
project  = os.path.basename(os.path.abspath(os.environ['PROJECT_DIR']))

try:
    with open(src, encoding='utf-8') as f:
        lines = f.read().splitlines()
except Exception as e:
    print(f"triage-report: cannot read {src}: {e}", file=sys.stderr)
    sys.exit(3)

def esc(s):
    return H.escape(str(s or ''))

# --- inline markdown: bold, inline code, and nothing else ----------------------------------
# Escape FIRST, then re-introduce the two tags. Doing it the other way round means a `<` in the
# source becomes a real tag. Deliberately no links, no images, no emphasis-by-underscore: the
# template uses none of them, and every construct added here is one more thing that can render
# a triage wrongly without anyone noticing.
def inline(s):
    s = esc(s)
    s = re.sub(r'`([^`]+)`', r'<code>\1</code>', s)
    s = re.sub(r'\*\*([^*]+)\*\*', r'<strong>\1</strong>', s)
    return s

def split_row(line):
    line = line.strip()
    if line.startswith('|'): line = line[1:]
    if line.endswith('|'):   line = line[:-1]
    return [c.strip() for c in line.split('|')]

IS_TABLE = lambda l: l.strip().startswith('|')
IS_SEP   = lambda l: bool(re.fullmatch(r'\|[\s:|-]+\|?', l.strip()))

out = []          # rendered body chunks
para = []         # pending paragraph lines
list_open = False
in_comment = False
title = None

def flush_para():
    global para
    if para:
        out.append('<p>' + inline(' '.join(para)) + '</p>')
        para = []

def close_list():
    global list_open
    if list_open:
        out.append('</ul>')
        list_open = False

i = 0
while i < len(lines):
    raw = lines[i]
    line = raw.rstrip()

    # HTML comments (the scaffold marker) are structure, not content — drop them whole.
    if in_comment:
        if '-->' in line: in_comment = False
        i += 1; continue
    if line.lstrip().startswith('<!--'):
        if '-->' not in line: in_comment = True
        i += 1; continue

    if not line.strip():
        flush_para(); close_list(); i += 1; continue

    m = re.match(r'^(#{1,4})\s+(.*)$', line.strip())
    if m:
        flush_para(); close_list()
        level, text = len(m.group(1)), m.group(2).strip()
        if level == 1 and title is None:
            title = text
            out.append(f'<h1>{inline(text)}</h1>')
        else:
            out.append(f'<h{level}>{inline(text)}</h{level}>')
        i += 1; continue

    if re.fullmatch(r'-{3,}|\*{3,}|_{3,}', line.strip()):
        flush_para(); close_list()
        out.append('<hr>')
        i += 1; continue

    if IS_TABLE(line):
        flush_para(); close_list()
        block = []
        while i < len(lines) and IS_TABLE(lines[i]):
            block.append(lines[i]); i += 1
        head, body = None, block
        if len(block) >= 2 and IS_SEP(block[1]):
            head, body = block[0], block[2:]
        cells = lambda r, tag: ''.join(f'<{tag}>{inline(c)}</{tag}>' for c in split_row(r))
        thead = f'<thead><tr>{cells(head, "th")}</tr></thead>' if head else ''
        tbody = ''.join(f'<tr>{cells(r, "td")}</tr>' for r in body)
        out.append(f'<div class="scroll"><table>{thead}<tbody>{tbody}</tbody></table></div>')
        continue

    m = re.match(r'^\s*[-*]\s+(.*)$', line)
    if m:
        flush_para()
        if not list_open:
            out.append('<ul>'); list_open = True
        out.append(f'<li>{inline(m.group(1))}</li>')
        i += 1; continue

    # Lazy continuation of the bullet above: an INDENTED non-bullet line inside an open list
    # belongs to the previous item. Without this, every wrapped bullet in the scaffold closed
    # the list and re-opened as a paragraph, so a three-line bullet rendered as one bullet
    # followed by two orphaned sentences. Indentation is the whole test — an unindented line
    # ends the list, as it does in markdown.
    if list_open and raw[:1] in (' ', '\t'):
        out[-1] = out[-1][:-len('</li>')] + ' ' + inline(line.strip()) + '</li>'
        i += 1; continue

    close_list()
    para.append(line.strip())
    i += 1

flush_para(); close_list()
body = '\n  '.join(out)

# Placeholders left in the file are highlighted, not counted and not complained about. Marking
# them is rendering ("here is what is still blank"); saying whether that is acceptable is the
# reader's job and skills/source-triage.md's rule. The gate has the only verdict.
body = re.sub(r'\{\{([^}]*)\}\}',
              lambda m: f'<span class="todo">{m.group(1)}</span>', body)

rendered = datetime.date.today().isoformat()

# The :root token block and base styles are copied from toolkit-guide.html, the shared HTML
# shell for every stage surface (toolkit-guide.html §7). Copying the tokens is NOT opening the
# guide — that is governed by the first-touch sentinel in CLAUDE.md.
page = f"""<title>Source triage — {esc(project)}</title>
<style>
  :root {{
    --bg:#f6f7f9; --panel:#ffffff; --fg:#11141a; --muted:#5b6472; --line:#e0e4ea;
    --accent:#3b5bdb; --todo-bg:#fdf0d5; --todo-fg:#7a4b00; --todo-line:#d9a441;
  }}
  @media (prefers-color-scheme: dark) {{
    :root:not([data-theme="light"]) {{
      --bg:#101319; --panel:#171b22; --fg:#e6e9ef; --muted:#939cab; --line:#272d37;
      --accent:#7b95f0; --todo-bg:#3a2c12; --todo-fg:#e7c07a; --todo-line:#8a6a2a;
    }}
  }}
  :root[data-theme="dark"] {{
    --bg:#101319; --panel:#171b22; --fg:#e6e9ef; --muted:#939cab; --line:#272d37;
    --accent:#7b95f0; --todo-bg:#3a2c12; --todo-fg:#e7c07a; --todo-line:#8a6a2a;
  }}
  * {{ box-sizing:border-box; }}
  body {{ background:var(--bg); color:var(--fg); margin:0; padding:3rem 1.25rem 4rem;
         font:15px/1.6 ui-sans-serif,-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;
         font-variant-numeric:tabular-nums; }}
  main {{ max-width:62rem; margin:0 auto; }}
  .eyebrow {{ font-size:.7rem; text-transform:uppercase; letter-spacing:.14em; font-weight:700;
              color:var(--muted); margin:0 0 .5rem; }}
  h1 {{ font-size:1.75rem; line-height:1.15; letter-spacing:-.02em; margin:0 0 .4rem;
        text-wrap:balance; }}
  h2 {{ font-size:.78rem; text-transform:uppercase; letter-spacing:.12em; font-weight:700;
        margin:2.75rem 0 .75rem; color:var(--muted); }}
  h3 {{ font-size:1rem; margin:1.75rem 0 .5rem; }}
  h4 {{ font-size:.92rem; margin:1.25rem 0 .4rem; color:var(--muted); }}
  p {{ margin:0 0 .9rem; max-width:52rem; }}
  ul {{ margin:0 0 1rem; padding-left:1.15rem; max-width:52rem; }}
  li {{ margin:.25rem 0; }}
  hr {{ border:0; border-top:1px solid var(--line); margin:2.25rem 0; }}
  table {{ width:100%; border-collapse:collapse; font-size:.88rem; margin:0 0 1rem;
           background:var(--panel); }}
  .scroll {{ overflow-x:auto; }}
  th {{ text-align:left; font-size:.68rem; text-transform:uppercase; letter-spacing:.1em;
        font-weight:700; color:var(--muted); border-bottom:1px solid var(--line);
        padding:.5rem .7rem; white-space:nowrap; }}
  td {{ border-bottom:1px solid var(--line); padding:.7rem; vertical-align:top; }}
  code {{ font-size:.85em; background:var(--panel); border:1px solid var(--line);
          border-radius:3px; padding:.05rem .3rem; }}
  .todo {{ background:var(--todo-bg); color:var(--todo-fg); border:1px dashed var(--todo-line);
           border-radius:3px; padding:.05rem .35rem; font-size:.85em; }}
  .banner {{ border-left:3px solid var(--accent); background:var(--panel); border-radius:0 3px 3px 0;
             padding:.9rem 1.1rem; margin:0 0 2rem; color:var(--muted); font-size:.88rem; }}
  .banner p {{ margin:0; }}
  footer {{ margin-top:3rem; padding-top:1.1rem; border-top:1px solid var(--line);
            color:var(--muted); font-size:.8rem; max-width:46rem; }}
</style>
<main>
  <p class="eyebrow">Stage 0 · source triage</p>
  <div class="banner">
    <p>Rendered {esc(rendered)} from <code>{esc(src)}</code>. This page is a view of that file and
       nothing else — it does not check, score or approve anything in it. The verdict on Stage 0
       comes from <code>bin/gate-check.sh {esc(project)} 0</code>, which asks one question: has a
       human signed this off. Dashed boxes are placeholders still in the source.</p>
  </div>
  {body}
  <footer>
    The reasoning behind every section here lives in <code>skills/source-triage.md</code>; the
    fill-in-me source is scaffolded by <code>bin/init-project.sh</code> from
    <code>bin/lib/triage-template.sh</code>. Edit <code>triage.md</code> and re-run
    <code>bin/triage-report.sh</code> — never edit this page.
  </footer>
</main>
"""

with open(html_out, 'w', encoding='utf-8') as f:
    f.write(page)
if not quiet:
    print(f"  triage: {html_out}")
PY

exit $?
