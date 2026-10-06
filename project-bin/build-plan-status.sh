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
#   build-plan-status.sh [project-dir] [--html] [--json] [--quiet] [--refresh]
#     --html    also write architecture/build-plan.html (self-contained, no external deps): the
#               plan itself (phases, rows, claims from build-plan.md, see "P." below) followed
#               by views A and B
#     --refresh the unattended form of --html, for exec.sh and gate-check.sh: quiet, writes only
#               when build-plan.md exists, never over a build-plan.html this script did not
#               write, and leaves the file untouched when nothing but the timestamp would change
#     --json    also write architecture/build-plan.json, parsed from architecture/build-plan.md's
#               Step-5 Phase headings, row tables and claims: blocks (see "C." below)
#     --quiet   suppress the stdout table (useful when only --html/--json output is wanted)
#
# Exit: always 0. This is a status view, not a gate — skills-over-scripts.md: a script reports
# facts, a human or a skill (module-review.md, iterative-build-loop.md) judges them.

set -uo pipefail

ROOT="${1:-}"
[ -n "$ROOT" ] && [ "${ROOT#--}" = "$ROOT" ] || ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
shift 2>/dev/null || true

WRITE_HTML=0
WRITE_JSON=0
QUIET=0
REFRESH=0
for a in "$@"; do
  case "$a" in
    --html)  WRITE_HTML=1 ;;
    --refresh) WRITE_HTML=1; REFRESH=1; QUIET=1 ;;
    --json)  WRITE_JSON=1 ;;
    --quiet) QUIET=1 ;;
    *) echo "unknown arg: $a" >&2; exit 2 ;;
  esac
done

cd "$ROOT" || exit 0

MDLSOURCE="$ROOT/mdlsource"
MODULES_DIR="$ROOT/architecture/modules"
REGISTER="$ROOT/docs/improvement-register.md"
BUILD_PLAN="$ROOT/architecture/build-plan.md"
STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ── A. Build-plan phase progress, from mdlsource/<phase>/done- counts ───────
# Phase folders are read as they exist on disk, not matched against build-plan.md's prose Phase
# headers — a fuzzy name-match would be a guess, and skills-over-scripts.md says code carries no
# opinion. If a reader wants the prose name for phase "3b-core-microflows", cross-reference the
# numeric prefix against architecture/build-plan.md by hand; this script does not invent the link.
PHASE_ROWS=""
PHASE_COUNT=0
if [ -d "$MDLSOURCE" ]; then
  for d in "$MDLSOURCE"/*/; do
    [ -d "$d" ] || continue
    phase="$(basename "$d")"
    total=$(find "$d" -maxdepth 1 -type f \( -name '*.mdl' -o -name '*.sql' \) | wc -l | tr -d ' ')
    [ "$total" -eq 0 ] && continue
    done_ct=$(find "$d" -maxdepth 1 -type f \( -name 'done-*.mdl' -o -name 'done-*.sql' \) | wc -l | tr -d ' ')
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
    module="$(basename "$d")"
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
      if grep -q $'\tFAULT\t' "$summary" 2>/dev/null; then
        reviewed="INCOMPLETE (instrument fault)"
      elif grep -q $'\tFINDING\t' "$summary" 2>/dev/null; then
        reviewed="FINDINGS"
      else
        reviewed="CLEAN"
      fi
      age_s=$(( $(date +%s) - $(date -r "$summary" +%s 2>/dev/null || echo 0) ))
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

def classify(state):
    s = state.lower()
    if s.startswith("not built"): return "not built"
    if s.startswith("built"): return "built"
    if s.startswith("pending a person"): return "pending a person"
    return None

def rollup(steps):
    kinds = [classify(s["state"]) for s in steps]
    if not kinds or None in kinds: return "unknown"
    if all(k == "built" for k in kinds): return "built"
    if all(k == "not built" for k in kinds): return "not built"
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
  if [ -f "$(dirname "${BASH_SOURCE[0]}")/_common.sh" ]; then
    # shellcheck disable=SC1091
    . "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
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
  "$PY" - "$PLAN_JSON" "$MDLSOURCE" <<'PYEOF' || echo "<h2>The plan</h2><p class=empty>Could not render the plan section from build-plan.md.</p>"
import fnmatch, html, json, os, re, sys

src, mdl = sys.argv[1], sys.argv[2]
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

def classify(state):  # the parser's rollup reading, per row
    s = (state or "").lower()
    if s.startswith("not built"): return "not built"
    if s.startswith("built"): return "built"
    if s.startswith("pending a person"): return "pending a person"
    return None

CLS = {"built": "st-built", "not built": "st-todo", "pending a person": "st-person",
       "in progress": "st-progress", "unknown": "st-unknown", None: "st-unknown"}

phases = d.get("phases", [])
all_steps = [s for p in phases for s in p["steps"]]
tally = {"built": 0, "not built": 0, "pending a person": 0, None: 0}
for s in all_steps:
    tally[classify(s["state"])] += 1
named_total = named_done = drift_rows = 0
rows_html = []
for p in phases:
    out = []
    for s in p["steps"]:
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
        out.append('<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td class="%s">%s</td><td>%s</td></tr>' % (
            e(s["number"]), e(s["kind"]), ec(s["step"]), ec(s["produces"]),
            e(", ".join(s["dependsOn"])), CLS[k], e(s["state"]), disk))
    rows_html.append(out)

plural = lambda n, w: "%d %s%s" % (n, w, "" if n == 1 else "s")
print("<h2>The plan</h2>")
print("<p class=lede>From <code>architecture/build-plan.md</code>: %s, %s: "
      "<b class=st-built>%d built</b>, <b class=st-todo>%d not built</b>, <b class=st-person>%d pending a person</b>%s.</p>" % (
      plural(len(phases), "phase"), plural(len(all_steps), "row"),
      tally["built"], tally["not built"], tally["pending a person"],
      (", <b class=st-unknown>%d with a State cell this page cannot read</b>" % tally[None]) if tally[None] else ""))
if named_total:
    print("<p class=note>Scripts named in the plan: %d, of which %d are renamed <code>done-</code> under <code>mdlsource/</code>.%s</p>" % (
        named_total, named_done,
        (" <span class=drift>&#9888; %s where the plan and the disk disagree.</span>" % plural(drift_rows, "row")) if drift_rows else ""))
for p, out in zip(phases, rows_html):
    print('<section class=phase><h3>Phase %s &mdash; %s <span class="badge %s">%s</span></h3>' % (
        e(p["id"]), e(p["name"]), CLS.get(p["state"], "st-unknown"), e(p["state"])))
    if p.get("note"):
        print("<p class=note>%s</p>" % e(p["note"]))
    if p["steps"]:
        b = sum(1 for s in p["steps"] if classify(s["state"]) == "built")
        print("<p class=note>%d of %s built</p>" % (b, plural(len(p["steps"]), "row")))
        print("<div class=scroll><table><tr><th>#</th><th>Kind</th><th>Step</th><th>Produces / Proves</th>"
              "<th>Depends on</th><th>State</th><th>Scripts</th></tr>")
        print("\n".join(out))
        print("</table></div>")
    else:
        print("<p class=empty>No row table under this phase.</p>")
    if p.get("claims"):
        print("<details><summary>Claims (%d)</summary><ul class=claims>" % len(p["claims"]))
        for c in p["claims"]:
            extra = (" (%d)" % c["count"] if c.get("count") is not None else "") + (" [%s]" % c["brd"] if c.get("brd") else "")
            print("<li><code>%s</code>%s</li>" % (e(c["pointer"]), e(extra)))
        print("</ul></details>")
    elif p.get("claimsNote"):
        print("<p class=note>Claims: %s</p>" % e(p["claimsNote"]))
    print("</section>")
w = d.get("warnings") or []
if w:
    print("<details class=warn><summary>Parser notes (%d): lines in build-plan.md this page could not read as plan data</summary><ul>" % len(w))
    for x in w:
        print("<li>%s</li>" % e(x))
    print("</ul></details>")
PYEOF
}

if [ "$WRITE_HTML" -eq 1 ]; then
  OUT="$ROOT/architecture/build-plan.html"
  SKIP_HTML=""
  if [ "$REFRESH" -eq 1 ]; then
    # Unattended callers (exec.sh, gate-check.sh) get gate-check.sh's index.html rules: no plan,
    # no page; and never over a page this script did not write (before 2026-08-19 agents wrote
    # this file by hand, and a project may still carry one). Every render from this script names
    # it in the stamp line, so older renders are recognised and adopted.
    if [ ! -f "$BUILD_PLAN" ]; then
      SKIP_HTML="no build-plan.md"
    elif [ -f "$OUT" ] && ! grep -qF 'build-plan-status.sh' "$OUT"; then
      SKIP_HTML="architecture/build-plan.html was not written by this script"
    fi
  fi
  if [ -n "$SKIP_HTML" ]; then
    [ "$QUIET" -eq 0 ] && echo "" && echo "  build-plan.html not written: $SKIP_HTML"
  else
    mkdir -p "$ROOT/architecture"
    OUT_TMP="$OUT.tmp.$$"
    {
      echo '<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
      echo '<!-- generated-by: mxcli-project-toolkit/project-bin/build-plan-status.sh -->'
      echo '<title>Build Plan</title>'
      echo '<style>
:root{--ink:#1c1f24;--muted:#646b75;--line:#e3e6ea;--bg:#fff;--ok:#0a7d2c;--warn:#a66a00;--bad:#b3261e;--person:#6a3fb5}
@media (prefers-color-scheme:dark){:root{--ink:#e6e8eb;--muted:#9aa1ab;--line:#2f343b;--bg:#16181c;--ok:#5cc27a;--warn:#e0a640;--bad:#f07167;--person:#b49af0}}
body{font:14px/1.5 -apple-system,Segoe UI,sans-serif;margin:0;padding:2rem 16px;color:var(--ink);background:var(--bg)}
main{max-width:1200px;margin:0 auto}
h1{font-size:1.35rem;margin:0} h2{font-size:1.1rem;margin-top:2.2rem;border-bottom:1px solid var(--line);padding-bottom:.3rem}
h3{font-size:1rem;margin:1.6rem 0 .2rem}
.scroll{overflow-x:auto}
table{border-collapse:collapse;width:100%;margin-top:.5rem}
th,td{text-align:left;vertical-align:top;padding:.4rem .6rem;border-bottom:1px solid var(--line);font-size:.88rem}
th{color:var(--muted);font-weight:600;white-space:nowrap}
code{font-size:.85em}
.badge{font-size:.75rem;font-weight:600;padding:.1rem .5rem;border:1px solid currentColor;border-radius:999px;margin-left:.4rem;vertical-align:middle}
.st-built,.done,.CLEAN{color:var(--ok)} .st-progress,.in-progress,.INCOMPLETE{color:var(--warn)}
.st-todo,.pending{color:var(--muted)} .st-person{color:var(--person)} .st-unknown{color:var(--muted);font-style:italic}
.FINDINGS,.drift{color:var(--bad)} .drift{font-size:.8rem;margin-top:.15rem}
.note,.empty{color:var(--muted);font-size:.85rem} .lede{font-size:.95rem}
details{margin:.5rem 0} summary{cursor:pointer;color:var(--muted);font-size:.85rem}
.claims{font-size:.82rem} .warn summary{color:var(--warn)}
</style></head><body><main>'
      echo "<h1>Build Plan</h1><p class=note id=stamp>Generated $STAMP by project-bin/build-plan-status.sh from architecture/build-plan.md, mdlsource/ and the module review files. exec.sh and gate-check.sh regenerate it; never hand-edit.</p>"

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
      echo '</main></body></html>'
    } > "$OUT_TMP"
    # Two renders of the same state differ only in the stamp line. A refresh that changed nothing
    # leaves the file alone, or every exec.sh run would dirty the working tree.
    if [ "$REFRESH" -eq 1 ] && [ -f "$OUT" ] \
       && [ "$(grep -v 'id=stamp' "$OUT")" = "$(grep -v 'id=stamp' "$OUT_TMP")" ]; then
      rm -f "${OUT_TMP:?}"
    else
      mv -f "$OUT_TMP" "$OUT"
    fi
    [ "$QUIET" -eq 0 ] && echo "" && echo "  wrote ${OUT#$ROOT/}"
  fi
fi

exit 0
