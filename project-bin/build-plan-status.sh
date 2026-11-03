#!/usr/bin/env bash
# build-plan-status.sh — mechanizes the progress tracker brd-to-build-plan.md already specifies
# and iterative-build-loop.md already assumes exists, and adds the per-module test/review status
# next to it. Neither previously had a renderer — see "WHY THIS EXISTS" below.
#
# WHY THIS EXISTS
# brd-to-build-plan.md Step 10 specifies a self-contained `architecture/build-plan.html` progress
# tracker, "regenerated whenever a phase's status changes." iterative-build-loop.md says the
# `build-plan.html` phase status and the `done-` filename prefixes "should agree — when every
# script for a phase is done-, that phase flips to check in the tracker." Neither statement had a
# script behind it (confirmed 2026-08-19: no file in bin/ or project-bin/ writes build-plan.html).
# That is the same shape as `gate-agent` (routed, never invoked, 0/21 sessions) and deep
# verification at "step 10" (specified, scheduled last, never ran) — a mechanism that only exists
# in prose does not exist. This script is the renderer.
#
# It also answers a question the phase view alone cannot: a phase can be 100% done-renamed and
# still not proven — "done" per iterative-build-loop.md means gate-clean AND happy-path verified,
# but only module-review.md's CONFIRM stage (via verify-module.sh) and improvement-register.md
# know whether that verification actually happened and what it found. So this renders TWO views,
# kept honestly separate because they answer different questions:
#
#   A. Build-plan phase progress   — from mdlsource/<phase>/ done- counts.  "How much is BUILT."
#   B. Per-module test/review view — from verify-module.sh summaries + the improvement register.
#                                     "How much is PROVEN, and what's still open."
#
# A phase at 100% in view A with no row in view B is exactly the gap this script exists to make
# visible: built, never proven. DIAGNOSTIC ONLY — reads files, writes nothing but the optional
# --html and --json outputs and never touches the .mpr.
#
# Usage:
#   build-plan-status.sh [project-dir] [--html] [--json] [--quiet] [--refresh] [--open]   (flags and path in any order)
#     --html    also write architecture/progress-report.html (self-contained, no external deps),
#               which replaced architecture/build-plan.html: stages P to 6, time and token data
#               when a Claude Code session log exists (project-bin/progress-report.py), and the
#               plan itself (phases, rows, claims from build-plan.md, see "P." below) followed
#               by views A and B. An existing build-plan.html is left alone.
#     --session-log PATH  use this Claude Code session log (a .jsonl file or a folder of them; repeatable) instead of
#               discovery, for a session started outside the project folder. Passed to progress-report.py.
#     --refresh the unattended form of --html, for exec.sh and gate-check.sh: quiet, writes only
#               when build-plan.md exists, never over a progress-report.html this script did not
#               write, and leaves the file untouched when nothing but the stamp lines would change
#               It also keeps an EXISTING architecture/build-plan.json current (same parser as
#               --json, same no-rewrite-for-a-timestamp rule) and never creates one
#     --open    --html, then show it: on macOS reload the Chrome tab whose URL contains
#               progress-report.html, else open the file once; elsewhere a no-op
#     PROJECT.md `Progress report: off | ask | auto` (default ask): off = never write the page
#     --json    also write architecture/build-plan.json, parsed from architecture/build-plan.md's
#               Step-5 Phase headings, row tables and claims: blocks (see "C." below)
#     --quiet   suppress the stdout table (useful when only --html/--json output is wanted)
#
# Exit: always 0. This is a status view, not a gate — skills-over-scripts.md: a script reports
# facts, a human or a skill (module-review.md, iterative-build-loop.md) judges them.

set -uo pipefail

# One loop for flags AND the path, in any order (2026-10-13, field report via PR #309): the old
# form read $1 as the path, fell back to pwd when $1 was a flag, then `shift`ed unconditionally.
# `--json <root>` therefore dropped --json and refused the real path as "unknown arg" (exit 2), and
# a bare `--json` from inside a project silently ran without it: no build-plan.json, no error.
ROOT=""
WRITE_HTML=0
WRITE_JSON=0
QUIET=0
REFRESH=0
OPEN=0
SESSION_LOGS=()
_want_log=0
for a in "$@"; do
  if [ "$_want_log" -eq 1 ]; then SESSION_LOGS+=("$a"); _want_log=0; continue; fi
  case "$a" in
    --session-log) _want_log=1 ;;
    --html)  WRITE_HTML=1 ;;
    --open)  WRITE_HTML=1; OPEN=1 ;;
    --refresh) WRITE_HTML=1; REFRESH=1; QUIET=1 ;;
    --json)  WRITE_JSON=1 ;;
    --quiet) QUIET=1 ;;
    --*) echo "unknown arg: $a" >&2; exit 2 ;;
    *) if [ -z "$ROOT" ]; then ROOT="$a"; else echo "unexpected second path: $a (first was $ROOT)" >&2; exit 2; fi ;;
  esac
done
[ "$_want_log" -eq 0 ] || { echo "--session-log needs a path" >&2; exit 2; }
[ -n "$ROOT" ] || ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

cd "$ROOT" || exit 0
ROOT="$(pwd)"  # a relative project path must survive the cd (the page is written under $ROOT)

MDLSOURCE="$ROOT/mdlsource"
MODULES_DIR="$ROOT/architecture/modules"
REGISTER="$ROOT/docs/improvement-register.md"
BUILD_PLAN="$ROOT/architecture/build-plan.md"
if [ -n "${EPOCHSECONDS:-}" ]; then TZ=UTC printf -v STAMP '%(%Y-%m-%dT%H:%M:%SZ)T' -1   # bash 5: no date process
else STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; fi

# PROJECT.md `Progress report: off | ask | auto` (default ask). off = this script never writes the
# page; ask and auto only change what the agent does at a stage gate or module close (the skills
# say: ask once, or open it), so the script treats them the same.
report_name() {  # the page name lives in progress-report.py (REPORT_FILE); asked once, here
  REPORT_FILE="$("${PY:-python3}" "${_bpd:-$(dirname "${BASH_SOURCE[0]}")}/progress-report.py" --print-name 2>/dev/null)"  # portability-ok: PY is resolve_py output; python3 only if unset
  [ -n "$REPORT_FILE" ] || REPORT_FILE="progress-report.html"
}
progress_report_setting() {
  _v="$(grep -iE '^[[:space:]>*_-]*Progress report[[:space:]]*:' "$ROOT/PROJECT.md" 2>/dev/null | head -1 \
        | sed -E 's/^[^:]*:[[:space:]*_`]*//' | tr 'A-Z' 'a-z')"
  case "$_v" in
    *"|"*) echo ask ;;   # the option list pasted verbatim is not a choice
    off*) echo off ;;
    auto*) echo auto ;;
    *) echo ask ;;
  esac
}

# ── A. Build-plan phase progress, from mdlsource/<phase>/done- counts ───────
# Phase folders are read as they exist on disk, not matched against build-plan.md's prose Phase
# headers — a fuzzy name-match would be a guess, and skills-over-scripts.md says code carries no
# opinion. If a reader wants the prose name for phase "3b-core-microflows", cross-reference the
# numeric prefix against architecture/build-plan.md by hand; this script does not invent the link.
PHASE_ROWS=""
PHASE_COUNT=0
if [ -d "$MDLSOURCE" ]; then
  # Counted with globs: the find | wc | tr (and basename) per phase folder were five process
  # starts each. dotglob + the symlink test keep find -type f's answer.
  _dg=0; shopt -q dotglob && _dg=1
  for d in "$MDLSOURCE"/*/; do
    [ -d "$d" ] || continue
    _dn="${d%/}"; phase="${_dn##*/}"
    total=0; done_ct=0
    shopt -s dotglob   # only for the file globs: the phase folders themselves stay non-hidden
    for _pf in "$d"*.mdl "$d"*.sql; do
      [ -f "$_pf" ] && [ ! -L "$_pf" ] || continue
      total=$((total + 1))
      case "${_pf##*/}" in done-*) done_ct=$((done_ct + 1)) ;; esac
    done
    [ "$_dg" = 1 ] || shopt -u dotglob
    [ "$total" -eq 0 ] && continue
    pct=$(( total > 0 ? done_ct * 100 / total : 0 ))
    status="pending"
    [ "$done_ct" -gt 0 ] && status="in-progress"
    [ "$done_ct" -eq "$total" ] && status="done"
    PHASE_ROWS="${PHASE_ROWS}${phase}	${done_ct}/${total}	${pct}%	${status}
"
    PHASE_COUNT=$((PHASE_COUNT+1))
  done
fi

# ── B. Per-module test/review status ─────────────────────────────────────────
# "Reviewed" = verify-module.sh has run for this module at least once (a summary.tsv exists).
# Its own verdict is re-derived from that file's rows, never re-run here — this script is a
# reader, not another instrument.
MODULE_ROWS=""
MODULE_COUNT=0
REVIEWED_COUNT=0
if [ -d "$MODULES_DIR" ]; then
  for d in "$MODULES_DIR"/*/; do
    [ -d "$d" ] || continue
    _dn="${d%/}"; module="${_dn##*/}"
    briefed="no"
    if [ -f "$d/module-brief.md" ]; then
      briefed="yes"
    elif [ -f "$BUILD_PLAN" ] \
         && grep -qE "^## +Module brief +(—|-) +$module\b" "$BUILD_PLAN"; then
      # The MERGED form. brd-to-build-plan.md prescribes it for single-module projects —
      # "Single-module projects: merge it. The brief's sections become sections of the build plan
      # under a `## Module brief — <Module>` heading (the form exec.sh's advisory also
      # recognises)… two documents at ~70% overlap is how one of them ends up unwritten."
      #
      # Reading only the per-module file reported `briefed: no` forever on a project that had
      # followed that instruction, with no way to satisfy the column except by writing the
      # duplicate the skill warns against. Found on a real single-module project, 2026-09-08.
      # exec.sh already recognised this shape; this makes the progress board agree with it.
      # Em dash or hyphen, because both get typed — as an ALTERNATION, never a bracket class.
      # `[—-]` looks equivalent and is not: a bracket expression matches one CHARACTER, the em
      # dash is 3 bytes in UTF-8, and under a C/POSIX locale grep compares bytes — so the class
      # cannot match it and the check silently reports "no brief" on a file that has one. Caught
      # on the first real project to run this code, minutes after it shipped; an alternation is
      # matched as a byte sequence and works in either locale.
      briefed="merged"
    fi

    summary="$ROOT/.claude/loop/verify/$module/summary.tsv"
    reviewed="not yet"
    if [ -f "$summary" ]; then
      REVIEWED_COUNT=$((REVIEWED_COUNT+1))
      _sum=""; IFS= read -r -d '' _sum < "$summary" 2>/dev/null || true   # two greps over it, in-shell
      case "$_sum" in
        *$'\tFAULT\t'*) reviewed="INCOMPLETE (instrument fault)" ;;
        *$'\tFINDING\t'*) reviewed="FINDINGS" ;;
        *) reviewed="CLEAN" ;;
      esac
      age_s=$(( ${EPOCHSECONDS:-$(date +%s)} - $(date -r "$summary" +%s 2>/dev/null || echo 0) ))
      age_d=$(( age_s / 86400 ))
      reviewed="$reviewed (${age_d}d ago)"
    fi

    open_findings="-"
    if [ -f "$REGISTER" ]; then
      # Register rows: | Date | Module/Cluster | Source pass | Defect class | Severity | Finding | Disposition |
      # Count rows for this module whose Disposition does not start with "fixed".
      open_findings=$(awk -F'|' -v m="$module" '
        NF >= 8 {
          mod=$3; gsub(/^[ \t]+|[ \t]+$/, "", mod)
          disp=$8; gsub(/^[ \t]+|[ \t]+$/, "", disp)
          if (mod == m && disp !~ /^fixed/) n++
        }
        END { print n+0 }' "$REGISTER")
    fi

    MODULE_ROWS="${MODULE_ROWS}${module}	${briefed}	${reviewed}	${open_findings}
"
    MODULE_COUNT=$((MODULE_COUNT+1))
  done
fi

# ── stdout summary ────────────────────────────────────────────────────────
if [ "$QUIET" -eq 0 ]; then
  echo "══ build-plan status ══  $STAMP"
  echo ""
  echo "── A. Build-plan phase progress (mdlsource/<phase>/, done- prefix) ──"
  if [ "$PHASE_COUNT" -eq 0 ]; then
    echo "  no phase folders found under mdlsource/ — nothing to report"
  else
    printf 'phase\tdone/total\t%%\tstatus\n%s' "$PHASE_ROWS" | (column -t -s "$(printf '\t')" 2>/dev/null || cat) | sed 's/^/  /'
  fi
  echo ""
  echo "── B. Per-module test/review status ──"
  if [ "$MODULE_COUNT" -eq 0 ]; then
    echo "  no module directories found under architecture/modules/ — nothing to report"
  else
    printf 'module\tbriefed\treviewed\topen findings\n%s' "$MODULE_ROWS" | (column -t -s "$(printf '\t')" 2>/dev/null || cat) | sed 's/^/  /'
  fi
  echo ""
  echo "  $REVIEWED_COUNT of $MODULE_COUNT module(s) have ever been through verify-module.sh."
  echo "  A phase at 100% in A with its module never appearing reviewed in B is built, not proven."
  echo "  Staleness backstop for A: project-bin/done-drift-check.sh"
fi

# ── C. the plan itself, parsed from build-plan.md (--json, and --html's plan section) ──
# Views A and B never read the plan's prose, by design (see A's comment). But the prose is
# where the plan actually lives: brd-to-build-plan.md Step 5 writes one `### Phase N <dash> Name`
# heading per phase, a row table (`# | Kind | Step | Produces/Proves | Depends on | Skills |
# State`) and a `claims:` block under each. On a real project (2026-09-16) that file carried
# 7 fully-tabled phases while mdlsource/ was flat, so A and the HTML were honestly empty and
# the plan state existed only as text no program could read. --json writes that text out as
# data so a viewer can build from it. It records what the markdown says and nothing else:
# every field is a cell, a heading part or a claims line; the one derived value is each
# phase's `state`, rolled up from its own rows' State cells and `unknown` when a cell does
# not say built / not built / pending a person. A plan with no Phase headings gets no file.
#
# The encoder is Python's json module, never shell concatenation: one real Produces cell
# contains a double quote, and an invalid file is worse than none, because the viewer shows
# nothing while the file looks present. resolve_py follows exec.sh: sourced from _common.sh
# when present, with a guarded fallback for projects whose _common.sh predates it.
#
# --html reads the same parse (P. below). This is the fix for the empty board: until 2026-10-06
# the HTML was written from views A and B only, so a project whose plan was fully tabled but
# whose build had not yet created mdlsource/<phase>/ folders got "No phase folders found" and
# a column of "Briefed: no" — a page that looked broken at exactly the moment Stage 4 hands it
# to the user. brd-to-build-plan.md Step 10 always said the tracker shows "the phases, their
# numbered scripts, dependency order, and a per-phase/per-script status"; until the 2026-08-19
# renderer the agent wrote that page by hand from the markdown, and the renderer that replaced
# it never read the markdown.
PLAN_JSON=""
PLAN_MSG=""
JSON_MSG=""
TMP_JSON=""
cleanup_tmp() { [ -n "$TMP_JSON" ] && rm -f "${TMP_JSON:?}"; }
trap cleanup_tmp EXIT

parse_plan() {  # $1 = output path. Exit 0 written, 3 no Phase headings, other = parse failure.
  "$PY" - "$BUILD_PLAN" "$1" "$STAMP" <<'PYEOF'
import json, re, sys

src, out, stamp = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(src, encoding="utf-8", errors="replace").read().replace("\r\n", "\n").split("\n")

# `## Phase 1 <dash> Name *(note)*`, any heading level, em dash / en dash / hyphen / colon / middle
# dot between number and name (all five get typed). The id starts with a digit, so "Phase gates"
# and "Phase order at a glance" are prose headings, not phases. The trailing *(...)* is the
# author's annotation.
HEADING = re.compile(r"^#{1,6}\s+Phase\s+(\d[0-9A-Za-z.]*)\s*(?:[\u2014\u2013\u00b7:-]\s*|\s+)(.*?)\s*$")
ANY_HEADING = re.compile(r"^#{1,6}\s")
NOTE = re.compile(r"^(.*?)\s*\*\((.*)\)\*$")
TABLE_SEP = re.compile(r"^\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$")
CLAIMS = re.compile(r"^\s*claims:\s*(.*?)\s*$")
CLAIM = re.compile(r"^\s*(/\S+)(?:\s+\((\d+)\))?\s*(?:\[([^\]]+)\])?\s*$")
POINTER_LINE = re.compile(r"^\s+/")
DASHES = {"-", "\u2014", "\u2013"}

def clean(cell):
    return cell.replace("**", "").strip()

def split_row(line):
    cells = re.split(r"(?<!\\)\|", line.strip())
    if cells and cells[0].strip() == "": cells = cells[1:]
    if cells and cells[-1].strip() == "": cells = cells[:-1]
    return [c.replace("\\|", "|") for c in cells]

def split_list(cell):
    return [t.strip() for t in cell.split(",") if t.strip() and t.strip() not in DASHES]

COLUMNS = (("#", "number"), ("kind", "kind"), ("step", "step"), ("produces", "produces"),
           ("depends", "dependsOn"), ("skill", "skills"), ("state", "state"))

def column_map(headers):
    m = {}
    for i, h in enumerate(headers):
        h = clean(h).strip("`").lower()
        for prefix, key in COLUMNS:
            if key not in m and (h == prefix or (prefix != "#" and h.startswith(prefix))):
                m[key] = i
    return m if "number" in m and "state" in m else None

# Same prefixes as classify_state in progress-report.py, so the phase card, the plan header and
# the phase badge give one count. brd-to-build-plan.md lists `built` / `partial` / `not built` /
# `blocked`; the rest are the spellings the card already counts. `blocked` counts as not built.
# A "not needed" style row is out of the count and out of the rollup. None = cannot be read.
def classify(state):
    s = state.lower().replace("**", "").strip()
    if s.startswith("pending a person"): return "pending a person"
    if s.startswith(("blocked",)): return "blocked"
    if s.startswith(("not built", "not done", "not started", "planned", "to do", "todo", "open", "pending", "failed")): return "not built"
    if s.startswith(("not needed", "n/a", "dropped", "skipped", "waived", "deferred")): return "skipped"
    if s.startswith(("built", "done", "complete", "verified", "proven", "passed")): return "built"
    if s.startswith(("partial", "in progress", "started", "wip")): return "partial"
    return None

def rollup(steps):
    kinds = [classify(s["state"]) for s in steps]
    if None in kinds: return "unknown"
    kinds = [k for k in kinds if k != "skipped"]
    if not kinds: return "unknown"
    if all(k == "built" for k in kinds): return "built"
    if all(k in ("not built", "blocked") for k in kinds): return "not built"
    if all(k in ("built", "pending a person") for k in kinds): return "pending a person"
    return "in progress"

# Cut the file into phases: a Phase heading opens one, the next heading at the same level or
# higher closes it. Deeper sub-headings (per-step `####` sections) stay inside the phase.
phases, warnings = [], []
i = 0
while i < len(lines):
    h = HEADING.match(lines[i])
    if not h:
        i += 1; continue
    level = len(lines[i]) - len(lines[i].lstrip("#"))
    pid, name = h.group(1), h.group(2)
    note = None
    n = NOTE.match(name)
    if n: name, note = n.group(1).strip(), n.group(2).strip()
    label = "Phase " + pid
    body = []
    i += 1
    while i < len(lines):
        a = ANY_HEADING.match(lines[i])
        if a and len(lines[i]) - len(lines[i].lstrip("#")) <= level: break
        body.append(lines[i]); i += 1

    steps, claims, claims_note = [], None, None
    tables_seen = 0
    j = 0
    while j < len(body):
        line = body[j]
        if line.lstrip().startswith("|") and j + 1 < len(body) and TABLE_SEP.match(body[j + 1]):
            headers = split_row(line)
            cmap = column_map(headers)
            tables_seen += 1
            j += 2
            rows = []
            while j < len(body) and body[j].lstrip().startswith("|"):
                rows.append(split_row(body[j])); j += 1
            if cmap is None:
                warnings.append("%s: table header not recognized (%s), its rows are not in steps"
                                % (label, " | ".join(clean(c) for c in headers)))
                continue
            if any(clean(c).lower() == "claims" for c in headers):
                warnings.append("%s: table has an inline Claims column, which is not extracted; "
                                "claims are read from claims: blocks only" % label)
            for cells in rows:
                if len(cells) != len(headers):
                    warnings.append("%s: row starting '%s' has %d cells, header has %d"
                                    % (label, clean(cells[0]) if cells else "", len(cells), len(headers)))
                    cells = (cells + [""] * len(headers))[:len(headers)]
                get = lambda key: clean(cells[cmap[key]]) if key in cmap else None
                steps.append({
                    "number": get("number"), "kind": get("kind"), "step": get("step"),
                    "produces": get("produces"),
                    "dependsOn": split_list(get("dependsOn") or ""),
                    "skills": split_list(get("skills") or ""),
                    "state": get("state"),
                })
            continue
        c = CLAIMS.match(line)
        if c:
            if claims is None: claims = []
            rest = c.group(1)
            candidates = []
            if rest.startswith("(") and rest.endswith(")"):
                claims_note = rest[1:-1].strip()
            elif rest:
                candidates.append(rest)
            j += 1
            if j < len(body) and body[j].strip().startswith("```"):
                j += 1
                while j < len(body) and not body[j].strip().startswith("```"):
                    candidates.append(body[j]); j += 1
                j += 1
            else:
                # Unfenced: ends at the first non-pointer line, as coverage-preflight.sh's
                # extract_claims does. Inside a fence every line is a candidate and a
                # non-pointer line is reported, because the author put it in the block.
                while j < len(body) and POINTER_LINE.match(body[j]):
                    candidates.append(body[j]); j += 1
                if not candidates and j < len(body) and body[j].strip():
                    warnings.append("%s: claims: is followed by a line that is not a pointer: %s"
                                    % (label, body[j].strip()))
            for cand in candidates:
                if not cand.strip(): continue
                m = CLAIM.match(cand)
                if m:
                    claims.append({"pointer": m.group(1),
                                   "count": int(m.group(2)) if m.group(2) else None,
                                   "brd": m.group(3)})
                else:
                    warnings.append("%s: claims line not in 'pointer (count) [BRD]' form: %s"
                                    % (label, cand.strip()))
            continue
        j += 1

    if tables_seen == 0:
        warnings.append("%s: no row table under this heading, steps are empty" % label)
    phases.append({"id": pid, "name": name, "note": note, "state": rollup(steps),
                   "steps": steps, "claims": claims, "claimsNote": claims_note})

if not phases:
    sys.exit(3)
doc = {"schema": 1, "source": "architecture/build-plan.md", "generatedAt": stamp,
       "phases": phases, "warnings": warnings}
with open(out, "w", encoding="utf-8") as f:
    json.dump(doc, f, indent=2, ensure_ascii=False)
    f.write("\n")
PYEOF
}

if [ "$WRITE_JSON" -eq 1 ] || [ "$WRITE_HTML" -eq 1 ]; then
  _bpd="${BASH_SOURCE[0]%/*}"; [ "$_bpd" != "${BASH_SOURCE[0]}" ] || _bpd=.   # dirname without a process
  if [ -f "$_bpd/_common.sh" ]; then
    # shellcheck disable=SC1091
    . "$_bpd/_common.sh"
  fi
  if ! type resolve_py >/dev/null 2>&1; then
    resolve_py() {
      _c=""
      for _c in "${PYTHON:-}" python3 python py; do  # portability-ok: this IS the interpreter probe
        [ -n "$_c" ] || continue
        case "$(command -v "$_c" 2>/dev/null)" in *[Ww]indows[Aa]pps*) continue ;; esac
        if "$_c" -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)' >/dev/null 2>&1; then
          echo "$_c"; return 0
        fi
      done
      return 1
    }
  fi
  PY="$(resolve_py || true)"
  JSON_OUT="$ROOT/architecture/build-plan.json"
  if [ ! -f "$BUILD_PLAN" ]; then
    PLAN_MSG="no architecture/build-plan.md yet"
    JSON_MSG="no architecture/build-plan.md, so build-plan.json was not written"
  elif [ -z "$PY" ]; then
    PLAN_MSG="no working Python 3 found (tried python3, python, py), which reading build-plan.md needs"  # portability-ok: names in a diagnostic
    JSON_MSG="no working Python 3 found (tried python3, python, py), so build-plan.json was not written"  # portability-ok: names in a diagnostic
  else
    if [ "$WRITE_JSON" -eq 1 ]; then
      PLAN_TARGET="$JSON_OUT"
    else
      # --html alone: parse into a scratch file, so an HTML-only run never leaves a JSON behind.
      TMP_JSON="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/build-plan-status.$$.json")"
      PLAN_TARGET="$TMP_JSON"
    fi
    parse_plan "$PLAN_TARGET"
    case $? in
      0) PLAN_JSON="$PLAN_TARGET"
         JSON_MSG="wrote ${JSON_OUT#$ROOT/}"
         if [ "$REFRESH" -eq 1 ] && [ "$WRITE_JSON" -eq 0 ] && [ -f "$JSON_OUT" ]; then
           # --refresh keeps an EXISTING build-plan.json current (never creates one): exec.sh and
           # gate-check.sh run --refresh after every build step, so a json written once at Stage 4
           # would otherwise read 0 built after a day of building. Same parser as --json; the
           # write is skipped when only generatedAt would differ, like the html below.
           if "$PY" -c 'import json,sys
def load(f):
    d=json.load(open(f,encoding="utf-8")); d.pop("generatedAt",None); return d
sys.exit(0 if load(sys.argv[1])==load(sys.argv[2]) else 1)' "$JSON_OUT" "$PLAN_TARGET" >/dev/null 2>&1; then
             JSON_MSG="${JSON_OUT#$ROOT/} already current"
           else
             cp -f "$PLAN_TARGET" "$JSON_OUT" 2>/dev/null && JSON_MSG="refreshed ${JSON_OUT#$ROOT/}"
           fi
         fi
         if [ "$WRITE_JSON" -eq 1 ]; then
           # A producer guarantees its own output is ignored (snapshot-mpr.sh's rule). The JSON
           # is a build product: regenerated on demand in under a second, derived entirely from
           # build-plan.md. Committed, it would churn on most commits and, worse, sit stale in
           # git after the markdown moved on, and a dashboard that is quietly out of date is
           # what makes people stop trusting it. Written here rather than in init-project.sh so
           # it reaches projects that already exist, on their first --json run.
           if [ -d "$ROOT/.git" ] || [ -f "$ROOT/.git" ]; then
             GI="$ROOT/.gitignore"
             if ! { [ -f "$GI" ] && grep -qE '^/?architecture/build-plan\.json$' "$GI"; }; then
               if {
                 if [ -f "$GI" ] && [ -s "$GI" ] && [ -n "$(tail -c 1 "$GI")" ]; then printf '\n'; fi
                 printf '# Build product of project-bin/build-plan-status.sh --json, derived from\n'
                 printf '# architecture/build-plan.md. Regenerate on demand; never commit a stale copy.\n'
                 printf '/architecture/build-plan.json\n'
               } >> "$GI" 2>/dev/null; then
                 JSON_MSG="$JSON_MSG (added /architecture/build-plan.json to .gitignore: a build product, not committed)"
               else
                 JSON_MSG="$JSON_MSG (WARN could not write .gitignore; add /architecture/build-plan.json to it yourself)"
               fi
             fi
           fi
         fi ;;
      3) PLAN_MSG="build-plan.md has no Phase headings (brd-to-build-plan.md Step 5 format), so there is no row list to show"
         JSON_MSG="no Phase headings in architecture/build-plan.md, so build-plan.json was not written" ;;
      *) PLAN_MSG="could not parse architecture/build-plan.md"
         JSON_MSG="could not parse architecture/build-plan.md, so build-plan.json was not written" ;;
    esac
  fi
  [ "$WRITE_JSON" -eq 1 ] && [ "$QUIET" -eq 0 ] && echo "" && echo "  $JSON_MSG"
fi

# ── HTML render ──────────────────────────────────────────────────────────
# Order on the page: the plan (from build-plan.md via C's parse), then A (script folders, built),
# then B (modules, proven). The plan is what a reader opens the page for; A and B sit beside it.
#
# Per plan row, the State cell is what the plan SAYS. The "Scripts" column is what the disk
# SHOWS: every *.mdl / *.sql name written in the row's Step or Produces cell, looked up by file
# name anywhere under mdlsource/ (flat or phase folders), with `…` / `...` inside a name read as
# a wildcard because brd-to-build-plan.md's own examples abbreviate that way. `done-<name>` on
# disk = passed its gate. No name, no lookup: this never guesses which script a prose row means
# (A's rule, kept). When the two disagree (State says built and a named script is not done-, or
# every named script is done- and State says not built) the cell says so: done-drift-check.sh's
# question, asked per row.
render_plan_section() {  # stdout: the plan section's HTML
  if [ -z "$PLAN_JSON" ]; then
    echo "<h2>The plan</h2><p class=empty>Nothing to show yet: ${PLAN_MSG:-build-plan.md was not read}.</p>"
    return 0
  fi
  "$PY" - "$PLAN_JSON" "$MDLSOURCE" "${PHASE_DETAIL:-/dev/null}" "$ROOT" "${_bpd:-$(dirname "${BASH_SOURCE[0]}")}/progress-report.py" <<'PYEOF' || echo "<h2>The plan</h2><p class=empty>Could not render the plan section from build-plan.md.</p>"
import fnmatch, html, json, os, re, sys

src, mdl, detail_out, proj, gen = sys.argv[1:6]
# HARNESS rows are not build rows (MendixMau decision 2026-10-21): they are out of the tally, and a
# HARNESS row that runs verify-module.sh <Module> is not listed here at all, because
# progress-report.py shows it once as that module's sign-off status on the phase card
# (verify_evidence / module_status there). build-plan.json and build-plan.md keep every row.
VERIFY_STEP = re.compile(r"verify-module\.sh`?\s+[`\"']?([A-Za-z_]\w*)")   # same as progress-report.py's
try:
    import importlib.util
    sys.dont_write_bytecode = True   # no bin/__pycache__/ left in the project
    _spec = importlib.util.spec_from_file_location("progress_report", gen)
    _m = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(_m)
    VERIFY_STEP = _m.VERIFY_STEP
except (Exception, SystemExit):  # a broken or old generator: the generator's own run reports it
    pass
d = json.load(open(src, encoding="utf-8"))
e = lambda s: html.escape(s or "", quote=True)
# `code` spans in plan cells render as <code>, not literal backticks
ec = lambda s: re.sub(r"`([^`]+)`", r"<code>\1</code>", e(s))

files = set()
if os.path.isdir(mdl):
    for _r, _ds, fs in os.walk(mdl):
        for f in fs:
            if f.endswith((".mdl", ".sql")):
                files.add(f)

SCRIPT = re.compile(r"[A-Za-z0-9_.\-*…]+\.(?:mdl|sql)\b")

def named_scripts(*cells):
    out = []
    for cell in cells:
        for m in SCRIPT.findall(cell or ""):
            n = m[5:] if m.startswith("done-") else m
            n = n.replace("…", "*").replace("...", "*")
            if n.strip("*.").split(".")[0] and n not in out:
                out.append(n)
    return out

def on_disk(pat):
    if any(fnmatch.fnmatchcase(f, "done-" + pat) for f in files): return "done"
    if any(fnmatch.fnmatchcase(f, pat) for f in files): return "written"
    return "missing"

def classify(state):  # the parser's rollup reading, per row (keep in step with classify in parse_plan)
    s = (state or "").lower().replace("**", "").strip()
    if s.startswith("pending a person"): return "pending a person"
    if s.startswith("blocked"): return "blocked"
    if s.startswith(("not built", "not done", "not started", "planned", "to do", "todo", "open", "pending", "failed")): return "not built"
    if s.startswith(("not needed", "n/a", "dropped", "skipped", "waived", "deferred")): return "skipped"
    if s.startswith(("built", "done", "complete", "verified", "proven", "passed")): return "built"
    if s.startswith(("partial", "in progress", "started", "wip")): return "partial"
    return None

CLS = {"built": "st-built", "not built": "st-todo", "pending a person": "st-person",
       "partial": "st-progress", "blocked": "st-todo", "skipped": "st-todo",
       "in progress": "st-progress", "unknown": "st-unknown", "sign-off only": "st-person", None: "st-unknown"}

phases = d.get("phases", [])
all_steps = [s for p in phases for s in p["steps"]]
tally = {"built": 0, "not built": 0, "pending a person": 0, "partial": 0, "blocked": 0, "skipped": 0, None: 0}
is_harness = lambda s: (s.get("kind") or "").strip().upper() == "HARNESS"
is_signoff = lambda s: is_harness(s) and bool(VERIFY_STEP.search(s.get("step") or ""))
build_steps = [s for s in all_steps if not is_harness(s)]
n_signoff = sum(1 for s in all_steps if is_signoff(s)); n_harness = len(all_steps) - len(build_steps)
signoff_mods = {VERIFY_STEP.search(s["step"] or "").group(1) for s in all_steps if is_signoff(s)}   # modules, as the card's "k of n modules"

def disp_rollup(steps):  # the badge: parse_plan's rollup over the build rows only (build-plan.json keeps its own)
    rows = [s for s in steps if not is_harness(s)]
    if not rows: return "sign-off only" if steps else "unknown"
    kinds = [classify(s["state"]) for s in rows]
    if None in kinds: return "unknown"
    kinds = [k for k in kinds if k != "skipped"]
    if not kinds: return "unknown"
    if all(k == "built" for k in kinds): return "built"
    if all(k in ("not built", "blocked") for k in kinds): return "not built"
    if all(k in ("built", "pending a person") for k in kinds): return "pending a person"
    return "in progress"
for s in build_steps:
    tally[classify(s["state"])] += 1
named_total = named_done = drift_rows = 0
rows_html = []
for p in phases:
    out = []
    for s in p["steps"]:
        if is_signoff(s): continue   # shown once, as the module's sign-off status on the phase card
        names = named_scripts(s["step"], s["produces"])
        k = classify(s["state"])
        disk = ""
        if names:
            states = [on_disk(n) for n in names]
            dn = states.count("done")
            named_total += len(names); named_done += dn
            drift = ""
            if dn == len(names):
                label, dcls = "done-", "st-built"
                if k == "not built":
                    drift = "every script it names is done-, but State still says not built"
            elif dn or "written" in states:
                label, dcls = "%d of %d done-" % (dn, len(names)), "st-progress"
            else:
                label, dcls = "not written yet", "st-todo"
            if k == "built" and dn < len(names):
                drift = "State says built, but not every script it names is done-"
            title = "; ".join("%s: %s" % (n, st) for n, st in zip(names, states))
            disk = '<span class="%s" title="%s">%s</span>' % (dcls, e(title), e(label))
            if drift:
                drift_rows += 1
                disk += '<div class=drift>&#9888; %s</div>' % e(drift)
        st = e(s["state"])
        kind = e(s["kind"]) + (' <span class=mut>(not counted)</span>' if is_harness(s) else "")
        out.append('<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td class="%s">%s</td><td>%s</td></tr>' % (
            e(s["number"]), kind, ec(s["step"]), ec(s["produces"]),
            e(", ".join(s["dependsOn"])), CLS[k], st, disk))
    rows_html.append(out)

plural = lambda n, w: "%d %s%s" % (n, w, "" if n == 1 else "s")
print("<h2>The plan</h2>")
print("<p class=lede>From <code>architecture/build-plan.md</code>: %s, %s: "
      "<b class=st-built>%d built</b>, <b class=st-progress>%d partial</b>, <b class=st-todo>%d not built</b>%s, <b class=st-person>%d pending a person</b>%s%s.</p>" % (
      plural(len(phases), "phase"), plural(len(build_steps), "build row"),
      tally["built"], tally["partial"], tally["not built"] + tally["blocked"],
      (" (%d of them blocked)" % tally["blocked"]) if tally["blocked"] else "",
      tally["pending a person"],
      (", %d not needed" % tally["skipped"]) if tally["skipped"] else "",
      (", <b class=st-unknown>%d with a State cell this page cannot read</b>" % tally[None]) if tally[None] else "")
      + ("<p class=note>Not counted: %s (%s). A module's sign-off shows as its verify status on the phase card, not as a row.</p>" % (
          plural(n_harness, "HARNESS row"), ", ".join(x for x in ((("sign-offs of " + plural(len(signoff_mods), "module")) if n_signoff else ""), (plural(n_harness - n_signoff, "harness pass") if n_harness - n_signoff else "")) if x)) if n_harness else ""))
if named_total:
    print("<p class=note>Scripts named in the plan: %d, of which %d are renamed <code>done-</code> under <code>mdlsource/</code>.%s</p>" % (
        named_total, named_done,
        (" <span class=drift>&#9888; %s where the plan and the disk disagree.</span>" % plural(drift_rows, "row")) if drift_rows else ""))
# One view of the plan: each phase's rows and claims go to the detail file, which progress-report.py
# splices into that phase's card. They are not printed here, or the rows would appear twice.
det = []
for p, out in zip(phases, rows_html):
    h = ['<!--phase:%s-->' % e(p["id"]),
         '<p class=note>Phase state: <span class="badge %s">%s</span></p>' % (CLS.get(disp_rollup(p["steps"]), "st-unknown"), e(disp_rollup(p["steps"])))]
    if p.get("note"):
        h.append("<p class=note>%s</p>" % e(p["note"]))
    if p["steps"]:
        h.append("<div class=tw><table class=steps><tr><th>#</th><th>Kind</th><th>Step</th><th>Produces / Proves</th>"
                 "<th>Depends on</th><th>State</th><th>Scripts</th></tr>")
        h.append("\n".join(out))
        h.append("</table></div>")
    else:
        h.append("<p class=empty>No row table under this phase.</p>")
    if p.get("claims"):
        h.append("<details><summary>Claims (%d)</summary><ul class=claims>" % len(p["claims"]))
        for c in p["claims"]:
            extra = (" (%d)" % c["count"] if c.get("count") is not None else "") + (" [%s]" % c["brd"] if c.get("brd") else "")
            h.append("<li><code>%s</code>%s</li>" % (e(c["pointer"]), e(extra)))
        h.append("</ul></details>")
    elif p.get("claimsNote"):
        h.append("<p class=note>Claims: %s</p>" % e(p["claimsNote"]))
    h.append('<!--/phase-->')
    det.append("\n".join(h))
open(detail_out, "w", encoding="utf-8").write("\n".join(det))
w = d.get("warnings") or []
if w:
    print("<details class=warn><summary>Parser notes (%d): lines in build-plan.md this page could not read as plan data</summary><ul>" % len(w))
    for x in w:
        print("<li>%s</li>" % e(x))
    print("</ul></details>")
PYEOF
}

# ── Progress report page ──────────────────────────────────────────────────
# architecture/progress-report.html replaced build-plan.html. The page is rendered by
# progress-report.py (stages P to 6, session time and token data when a Claude Code log exists);
# this script contributes the part only it can read: the plan tables and views A and B, written
# to a scratch fragment above and embedded as the page's build detail. An older project's
# architecture/build-plan.html is left exactly where it is: not read, not rewritten, not deleted.
if [ "$WRITE_HTML" -eq 1 ]; then
  SKIP_HTML=""
  GEN="${_bpd:-$(dirname "${BASH_SOURCE[0]}")}/progress-report.py"
  report_name
  OUT="$ROOT/architecture/$REPORT_FILE"
  SETTING="$(progress_report_setting)"
  if [ "$SETTING" = "off" ]; then
    SKIP_HTML="PROJECT.md says Progress report: off"
  elif [ "$REFRESH" -eq 1 ] && [ ! -f "$BUILD_PLAN" ]; then
    # Unattended callers (exec.sh, gate-check.sh) get gate-check.sh's index.html rules: no plan,
    # no page; and never over a page this script did not write.
    SKIP_HTML="no build-plan.md"
  elif [ -f "$OUT" ] && ! grep -qF 'build-plan-status.sh' "$OUT"; then
    SKIP_HTML="architecture/$REPORT_FILE was not written by this script"
  elif [ -z "${PY:-}" ]; then
    SKIP_HTML="no working Python 3 found (tried python3, python, py), which the report needs"  # portability-ok: names in a diagnostic
  elif [ ! -f "$GEN" ]; then
    SKIP_HTML="progress-report.py is not next to this script (run bin/sync-project.sh)"
  fi
  if [ -n "$SKIP_HTML" ]; then
    [ "$QUIET" -eq 0 ] && echo "" && echo "  $REPORT_FILE not written: $SKIP_HTML"
  else
    mkdir -p "$ROOT/architecture"
    OUT_TMP="$OUT.tmp.$$"
    FRAG_TMP="$OUT.frag.$$"
    PHASE_DETAIL="$OUT.phases.$$"
    {
      render_plan_section

      echo "<h2>A. Script folders: how much is built</h2>"
      if [ "$PHASE_COUNT" -eq 0 ]; then
        echo "<p class=empty>No phase folders under <code>mdlsource/</code> yet. They appear as the build starts, one folder per phase (brd-to-build-plan.md); until then the plan above is the whole picture.</p>"
      else
        echo "<div class=scroll><table><tr><th>Phase folder</th><th>Done / Total</th><th>%</th><th>Status</th></tr>"
        printf '%s' "$PHASE_ROWS" | while IFS=$'\t' read -r phase ratio pct status; do
          [ -n "$phase" ] || continue
          echo "<tr><td>$phase</td><td>$ratio</td><td>$pct</td><td class=\"$status\">$status</td></tr>"
        done
        echo "</table></div>"
      fi

      echo "<h2>B. Modules: how much is proven</h2>"
      if [ "$MODULE_COUNT" -eq 0 ]; then
        echo "<p class=empty>No module directories under <code>architecture/modules/</code> yet.</p>"
      else
        echo "<p class=note>Briefs are written one module at a time, as that module's build starts (module-brief.md), so \"no\" before then is expected.</p>"
        echo "<div class=scroll><table><tr><th>Module</th><th>Briefed</th><th>Reviewed</th><th>Open findings</th></tr>"
        printf '%s' "$MODULE_ROWS" | while IFS=$'\t' read -r module briefed reviewed findings; do
          [ -n "$module" ] || continue
          cls="pending"
          case "$reviewed" in CLEAN*) cls=CLEAN ;; FINDINGS*) cls=FINDINGS ;; INCOMPLETE*) cls=INCOMPLETE ;; esac
          echo "<tr><td>$module</td><td>$briefed</td><td class=\"$cls\">$reviewed</td><td>$findings</td></tr>"
        done
        echo "</table></div>"
      fi
      echo "<p class=note>The plan: what build-plan.md says. A: built, from mdlsource/ done- prefixes. B: proven, from verify-module.sh + docs/improvement-register.md. A phase at 100% with no reviewed row in B is built, not proven.</p>"
    } > "$FRAG_TMP"
    GEN_ARGS=(--out "$OUT_TMP" --fragment "$FRAG_TMP" --plan-msg "${PLAN_MSG:-}")
    # An older progress-report.py (a `sync-project.sh --only-bin build-plan-status.sh` run, or a hand-edited
    # copy) has no --phase-detail and would exit "unrecognized arguments", writing no page at all. Pass the
    # flag only when the generator knows it; without it the phase cards keep their short row tables.
    grep -q -- '--phase-detail' "$GEN" 2>/dev/null && GEN_ARGS+=(--phase-detail "$PHASE_DETAIL")
    [ -n "$PLAN_JSON" ] && GEN_ARGS+=(--plan-json "$PLAN_JSON")
    for _sl in ${SESSION_LOGS[@]+"${SESSION_LOGS[@]}"}; do GEN_ARGS+=(--session-log "$_sl"); done
    if "$PY" "$GEN" "$ROOT" "${GEN_ARGS[@]}" >/dev/null 2>"$OUT.err.$$"; then
      # Two renders of the same state differ only in the stamp lines. A refresh that changed
      # nothing leaves the file alone, or every exec.sh run would dirty the working tree.
      # Stamp lines carry a data-stamp attribute (one of them also id=stamp); 'id=stamp' is kept in
      # the pattern so a page written before #479, with id=stamp on every such line, still compares.
      if [ "$REFRESH" -eq 1 ] && [ -f "$OUT" ] \
         && [ "$(grep -vE 'id=stamp|data-stamp' "$OUT")" = "$(grep -vE 'id=stamp|data-stamp' "$OUT_TMP")" ]; then
        rm -f "${OUT_TMP:?}"
      else
        mv -f "$OUT_TMP" "$OUT"
      fi
      [ "$QUIET" -eq 0 ] && echo "" && echo "  wrote ${OUT#$ROOT/}"
    else
      rm -f "${OUT_TMP:?}"
      _why="$(tail -n 1 "$OUT.err.$$" 2>/dev/null | head -c 200)"
      if [ "$QUIET" -eq 0 ]; then echo "" && echo "  $REPORT_FILE not written: the generator failed: $(head -c 300 "$OUT.err.$$" 2>/dev/null)"
      else echo "WARN: $REPORT_FILE not updated, progress-report.py failed: ${_why:-no message}" >&2; fi   # unattended callers stay quiet on success, never on a crash
    fi
    rm -f "${FRAG_TMP:?}" "${PHASE_DETAIL:?}" "${OUT}.err.$$"
  fi
fi

# ── --open: show the page ────────────────────────────────────────────────────
# macOS with Chrome running: reload the tab showing this project's report (its exact file:// URL), never a new
# window when a tab exists. Otherwise open the file once. Anywhere else (Linux, Windows, no GUI)
# it does nothing and says so. The setting gates the write above; this only needs the file.
if [ "$OPEN" -eq 1 ]; then report_name; fi
if [ "$OPEN" -eq 1 ] && [ -f "$ROOT/architecture/$REPORT_FILE" ] && [ "$(progress_report_setting)" != "off" ]; then
  if [ "$(uname -s)" = "Darwin" ]; then
    _res="none"
    if pgrep -x "Google Chrome" >/dev/null 2>&1; then  # portability-ok: --open is macOS-only by design (guarded by uname)
      # Match this project's file URL exactly (file:// + absolute path, percent-encoded), never any tab that
      # merely contains the page name: another project's report must not be reloaded in its place.
      _url="file://$("${PY:-python3}" -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$ROOT/architecture/$REPORT_FILE" 2>/dev/null)"  # portability-ok: PY is resolve_py output
      _as='tell application "Google Chrome"
repeat with w in windows
repeat with t in tabs of w
set u to URL of t
if u is "'"$_url"'" or u starts with "'"$_url"'#" or u starts with "'"$_url"'?" then
reload t
return "reloaded"
end if
end repeat
end repeat
end tell
return "none"'
      _res="$(osascript -e "$_as" 2>/dev/null || echo none)"  # portability-ok: --open is macOS-only by design (guarded by uname)
    fi
    if [ "$_res" = "reloaded" ]; then
      [ "$QUIET" -eq 0 ] && echo "  reloaded the open $REPORT_FILE tab"
    else
      open "$ROOT/architecture/$REPORT_FILE" >/dev/null 2>&1 || true  # portability-ok: --open is macOS-only by design (guarded by uname)
      [ "$QUIET" -eq 0 ] && echo "  opened architecture/$REPORT_FILE"
    fi
  else
    [ "$QUIET" -eq 0 ] && echo "  --open does nothing outside macOS; open architecture/$REPORT_FILE yourself"
  fi
fi

exit 0
