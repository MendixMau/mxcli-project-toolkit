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
#   build-plan-status.sh [project-dir] [--html] [--json] [--quiet]
#     --html    also write architecture/build-plan.html (self-contained, no external deps)
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
for a in "$@"; do
  case "$a" in
    --html)  WRITE_HTML=1 ;;
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

# ── optional HTML render ─────────────────────────────────────────────────
if [ "$WRITE_HTML" -eq 1 ]; then
  OUT="$ROOT/architecture/build-plan.html"
  mkdir -p "$ROOT/architecture"
  {
    echo '<!doctype html><html><head><meta charset="utf-8">'
    echo '<title>Build Plan Status</title>'
    echo '<style>
body{font:14px/1.5 -apple-system,Segoe UI,sans-serif;margin:2rem;color:#1a1a1a;background:#fff}
h1{font-size:1.3rem} h2{font-size:1.05rem;margin-top:2rem;border-bottom:1px solid #ddd;padding-bottom:.3rem}
table{border-collapse:collapse;width:100%;margin-top:.5rem}
th,td{text-align:left;padding:.4rem .6rem;border-bottom:1px solid #eee;font-size:.9rem}
th{color:#666;font-weight:600}
.done{color:#0a7d2c} .in-progress{color:#a66a00} .pending{color:#888}
.CLEAN{color:#0a7d2c} .FINDINGS{color:#b3261e} .INCOMPLETE{color:#a66a00}
.note{color:#666;font-size:.85rem;margin-top:1rem}
</style></head><body>'
    echo "<h1>Build Plan Status</h1><p class=note>Generated $STAMP by project-bin/build-plan-status.sh — regenerate after any phase status change, never hand-edit.</p>"

    echo "<h2>A. Build-plan phase progress</h2>"
    if [ "$PHASE_COUNT" -eq 0 ]; then
      echo "<p>No phase folders found under <code>mdlsource/</code>.</p>"
    else
      echo "<table><tr><th>Phase</th><th>Done / Total</th><th>%</th><th>Status</th></tr>"
      printf '%s' "$PHASE_ROWS" | while IFS=$'\t' read -r phase ratio pct status; do
        [ -n "$phase" ] || continue
        echo "<tr><td>$phase</td><td>$ratio</td><td>$pct</td><td class=\"$status\">$status</td></tr>"
      done
      echo "</table>"
    fi

    echo "<h2>B. Per-module test/review status</h2>"
    if [ "$MODULE_COUNT" -eq 0 ]; then
      echo "<p>No module directories found under <code>architecture/modules/</code>.</p>"
    else
      echo "<table><tr><th>Module</th><th>Briefed</th><th>Reviewed</th><th>Open findings</th></tr>"
      printf '%s' "$MODULE_ROWS" | while IFS=$'\t' read -r module briefed reviewed findings; do
        [ -n "$module" ] || continue
        cls="pending"
        case "$reviewed" in CLEAN*) cls=CLEAN ;; FINDINGS*) cls=FINDINGS ;; INCOMPLETE*) cls=INCOMPLETE ;; esac
        echo "<tr><td>$module</td><td>$briefed</td><td class=\"$cls\">$reviewed</td><td>$findings</td></tr>"
      done
      echo "</table>"
    fi
    echo "<p class=note>A: built, from mdlsource/ done- prefixes. B: proven, from verify-module.sh + docs/improvement-register.md. A phase at 100% with no reviewed row in B is built, not proven.</p>"
    echo '</body></html>'
  } > "$OUT"
  [ "$QUIET" -eq 0 ] && echo "" && echo "  wrote ${OUT#$ROOT/}"
fi

# ── C. optional JSON render, from build-plan.md itself ───────────────────
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
if [ "$WRITE_JSON" -eq 1 ]; then
  JSON_OUT="$ROOT/architecture/build-plan.json"
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
  if [ ! -f "$BUILD_PLAN" ]; then
    JSON_MSG="no architecture/build-plan.md, so build-plan.json was not written"
  elif [ -z "$PY" ]; then
    JSON_MSG="no working Python 3 found (tried python3, python, py), so build-plan.json was not written"  # portability-ok: names in a diagnostic
  else
    "$PY" - "$BUILD_PLAN" "$JSON_OUT" "$STAMP" <<'PYEOF'
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
    case $? in
      0) JSON_MSG="wrote ${JSON_OUT#$ROOT/}"
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
         fi ;;
      3) JSON_MSG="no Phase headings in architecture/build-plan.md, so build-plan.json was not written" ;;
      *) JSON_MSG="could not parse architecture/build-plan.md, so build-plan.json was not written" ;;
    esac
  fi
  [ "$QUIET" -eq 0 ] && echo "" && echo "  $JSON_MSG"
fi

exit 0
