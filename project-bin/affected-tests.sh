#!/usr/bin/env bash
# affected-tests.sh: which unit tests and journeys a change owes, per the project's test strategy.
#
#   ./bin/affected-tests.sh [--moment change|module|deploy] [--module <M>]... [--depth N]
#                           [--no-model] <script.mdl>...
#
# Prints, one row per line, tab-separated:
#   strategy  <moment>  unit=<scope> journeys=<scope>  (<where the scope came from>)
#   subject   <kind>    <Module.Name>   line N of <script>
#   caller    <Module.Name>  depth N     (SHOW CALLERS OF ... TRANSITIVE)
#   callers   measured | NOT MEASURED (<reason>)
#   data      NOT MEASURED  <kind> <Module.Name>  (entity/association/enumeration/access/module/role/userrole/constant subject)
#   unit      <file.test.mdl>  <why>   |   unit  off  (<why unit is off>)
#   journey   <file.journey.json>  <why>
#   journeys  unmapped  N of M journey file(s) cannot be selected by name
#   run       <the command to run that selection>
# Exit: 0 printed (an empty selection is printed as "none", never as silence) · 2 usage.
#
# WHY (2026-10-16). testing-shape.md §3 defined the per-change "subject set" (changed microflows
# plus their callers, the pages the change reaches) in prose only; exec.sh printed a lane and
# nothing computed the set. Measured in a five-app lab project (Mendix 11.15, mxcli v0.26.0):
# one exec 28-41 s, a full mxcli test about 6 min, conformance 645 s, coverage 377 s. A change
# that owes three tests was paying for the whole suite whenever an agent chose "to be safe".
# The maintainer's decision: per change, gate + affected tests only; the full e2e and the full
# unit suite run at deploy-ready, and each project picks its strategy with the developer (CAC-5).
#
# THE STRATEGY. PROJECT.md "## Test strategy" (skills/checkpoints/checkpoint-build.md writes it):
#   | Moment | Unit tests | Journeys | Status |
#   | Every change | affected | affected | CONFIRMED |
#   | Module done | module | module | CONFIRMED |
#   | Build complete | full | full | CONFIRMED |
# Scopes: none | affected | module | full. No section, or no row for the moment: these defaults,
# and the strategy row says "default". --moment picks the row (change is the default):
#   change = every change (build and feedback) · module = module done · deploy = build complete and
#   before every later deploy · all = "run everything", any time (same as deploy).
# Old row names "Module close" and "Deploy-ready" still read. A label is matched by its first words,
# case-insensitively: "Every change (build and feedback)" and "Build complete, and before every later
# deploy" (the Offer's own wording) map to their moment; a cell reads up to its first comma or
# parenthesis ("affected, modules on only" = affected, "none (decided CAC-5)" = none). An unknown row label warns on stderr.
#
# UNIT TESTS ARE OFF BY DEFAULT (field test of the RC, 2026-10-16: nothing read the knob, so a
# unit test was offered after every change). Precedence for the UNIT scope, highest first:
#   1. The '## Test strategy' Unit cell is a SCOPE only (none|affected|module|full). It never
#      turns unit on: at the change and module moments the switches in 2 and 3 always filter it.
#      Gate open (default yes): the cell is used as written. Gate closed: flipped modules only, with
#      the moment's built-in scope when the cell says none.
#   2. A module flipped to yes: that module's tests only, at the change and module moments (deploy
#      and all run every existing unit test). A flip is any of: a PROJECT.md line
#      `Unit modules: Shop, Admin` (decided at CAC-5); in the module brief
#      (architecture/modules/<M>/module-brief.md or architecture/modules/<M>-brief.md) a line
#      `Unit tests: yes` or the Declared-shape table row `| Unit (...) | yes | ...`.
#   3. PROJECT.md `Unit tests default:`. `yes` keeps the built-in scope for the moment; `no`, or the
#      line ABSENT, means unit is OFF for every module not flipped in 2. When off the script prints
#      one `unit off` line and NEVER a `run ... .test.mdl` row. `Unit modules:` takes names split
#      by comma or space; `#` and `( ... )` comments, a leading `- ` bullet, any case and `none`
#      are read; a name that matches no module warns on stderr.
#   4. PER FLOW (2026-10-16, after #417). A module brief may list the flows that get unit tests:
#        Unit flows:
#        - ACT_Order_CalculateTotal: money calculation
#      (a bullet per flow, `Name: reason`, `Name (note): reason` or inline `Unit flows: A, B`; blank
#      lines between bullets are fine, a heading or any other line ends the list; `Name` may be
#      qualified `Module.Name`; a `<placeholder>` is ignored; a line that cannot be read warns).
#      A module with a list is flipped by it and selected per flow: at the change moment (scope
#      affected) only the tests naming a LISTED flow the change touched (the flow itself, or a caller
#      within --depth; a data change in the module touches every listed flow); at the module moment
#      only for the --module/subject modules; at deploy every test runs. A test is mapped to its flow
#      as every selection here is: the test file names `Module.Flow` (grep -i -w -F). A flow listed
#      without a reason warns; a listed flow no test names warns (the test is owed); a name
#      `SHOW MICROFLOWS IN <M>` does not list, a different casing, or a module the model lacks warns
#      (best effort: skipped under --no-model or when mxcli cannot run). `Unit tests: yes` or
#      `Unit modules:` with NO list keeps the module-level selection. Under `Unit tests default: yes`
#      a module with a list is narrowed to it, but a test is dropped only when EVERY module it names has a list that excludes it; a test naming any module without a list stays (that module is on).
# Journeys are not affected by any of this.
#
# HOW THE SELECTION IS MADE (judgement-free facts only; skills-over-scripts.md):
#   1. Subjects: `bin/exec.sh --subjects <script>` (the same statement lexer as the change class).
#   2. Callers: ONE batched `mxcli -p <app>.mpr -c "SHOW CALLERS OF X TRANSITIVE; ..."` for every
#      microflow, nanoflow, page, snippet and layout subject. Golden input: a verbatim v0.26.0
#      capture (tests/wave2/fixtures/affected-tests/CAPTURE.txt). Transitive callers include pages
#      (a button's CALL MICROFLOW, a SHOW PAGE) on v0.26.0. The first call builds mxcli's catalog
#      (~19 s on a 275-flow app), later ones ~3 s. mxcli rebuilds the catalog when the .mpr
#      changed, so a call after an exec sees the callers that exec created (measured on v0.26.0). --no-model, no project mxcli, no .mpr, or output
#      that does not parse: "callers NOT MEASURED", and the selection is the subjects alone.
#   3. affected unit: *.test.mdl files that name a subject, or a caller at depth <= --depth
#      (default 1: "the tests of its callers"; MXTK_AFFECTED_DEPTH sets the default, --depth wins). Module, entity, association, enumeration and
#      access subjects select every test file that names their module (testing-shape.md §3 table).
#   4. affected journeys: journeys/<M>.journey.json for every module M owning a subject or ANY
#      transitive caller (a page reached at depth 4 is still a page the change reaches), plus any
#      journey file (journeys/ or tests/e2e/) that names a subject OR a transitive caller literally.
#      A journey file that is not named <Module>.journey.json and holds no qualified Module.Name
#      cannot be selected by name at all; the "journeys unmapped" row counts them, so an empty
#      selection is never read as "nothing owed". Journeys name what they walk by WIDGET and by
#      menu caption far more often than by Module.Name, so the affected scope also reads the
#      widget names of every changed page/snippet and of every caller that is a page (DESCRIBE
#      PAGE, one cheap mxcli call) and selects each journey whose JSON holds one of them
#      ("widgets measured" row). A navigation or layout change selects EVERY journey (each walks
#      the menu). When the widgets or the callers cannot be measured ("widgets NOT MEASURED"),
#      the selection is EVERY journey: unsure means include. (speed experiment E2: 067 changed
#      a page J-REQ-01 walks and 090 changed navigation; both selected 0 journeys.)
#   5. module: every test file naming the module, journeys/<M>.journey.json; the modules are the
#      subjects' modules plus every --module. full: every test file, every journey file.
#   6. A grant/revoke whose object (microflow, page, ...) the SAME script creates or modifies is
#      part of that subject (describe output ends in one): it selects nothing by module. A grant
#      with no such object in the script (entity, module role, other object) is an access change
#      and is selected by owning module as in 7.
#   7. data subjects (entity, association, enumeration, access, module, module role, user role,
#      constant): selected by the owning module only (a user role has no module and selects
#      nothing). Their use in another module's rule, page or microflow is not measured, and a
#      "data NOT MEASURED" row says so for each one.
# What it does NOT do: run anything. `mxcli test` writes to the model, so the run rows go through
# bin/test-scratch.sh (a scratch copy) and the journey runner; the caller runs them.
#
# Producer: exec.sh prints "affected tests: ./bin/affected-tests.sh <script>" on every MDL run.
# Overrides: JOURNEY_DIR (default journeys/), MXCLI (default the project's ./mxcli), MPR_FILE.
# Bash 3.2 / BSD awk / Git Bash.
set -uo pipefail
. "$(dirname "$0")/_common.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"

MOMENT="change"; DEPTH="${MXTK_AFFECTED_DEPTH:-1}"; NO_MODEL=0; MODULES=""; SCRIPTS=""
usage() { sed -n '2,15p' "$0" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --moment) MOMENT="${2:-}"; shift 2 ;;
    --module) MODULES="$MODULES ${2:-}"; shift 2 ;;
    --depth)  DEPTH="${2:-}"; shift 2 ;;
    --no-model) NO_MODEL=1; shift ;;
    -h|--help) usage ;;
    --*) echo "✗ unknown option $1" >&2; usage ;;
    *) [ -f "$1" ] || { echo "✗ no such script: $1" >&2; exit 2; }
       SCRIPTS="$SCRIPTS
$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"; shift ;;
  esac
done
[ "$MOMENT" = all ] && MOMENT=deploy
case "$MOMENT" in change|module|deploy) ;; *) echo "✗ --moment takes change, module, deploy or all" >&2; exit 2 ;; esac
case "$DEPTH" in ''|*[!0-9]*) echo "✗ --depth takes a number" >&2; exit 2 ;; esac
SCRIPTS="$(printf '%s\n' "$SCRIPTS" | sed '/^$/d')"
[ -n "$SCRIPTS" ] || [ "$MOMENT" != change ] || { echo "✗ a change needs at least one script" >&2; usage; }

cd "$PROJECT_ROOT" || exit 2
JDIR="${JOURNEY_DIR:-journeys}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/affected.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
out() { printf '%s\n' "$*"; }

# ── Strategy row ─────────────────────────────────────────────────────────────
case "$MOMENT" in change) ROW="Every change"; ALT="Every change"; DU=affected; DJ=affected ;;
                  module) ROW="Module done"; ALT="Module close"; DU=module; DJ=module ;;
                  deploy) ROW="Build complete"; ALT="Deploy-ready"; DU=full; DJ=full ;; esac
U="$DU"; J="$DJ"; FROM="default: PROJECT.md has no '## Test strategy' row '$ROW' (CAC-5 records it)"
if [ -f PROJECT.md ]; then
  _row="$(awk -v r="$ROW" -v r2="$ALT" '
    /^## /{ on = ($0 ~ /^## Test strategy/) ; next }
    on && /^\|/ { split($0, c, "|"); x = tolower(c[2]); sub(/[(,].*/, "", x); gsub(/^[ \t*`]+|[ \t*`]+$/, "", x)
                  if (x == "moment" || x ~ /^[-: ]*$/) next
                  if (x !~ /^(every change|module done|module close|build complete|deploy-ready)$/) { y = c[2]; gsub(/^[ \t]+|[ \t]+$/, "", y); print "warning: ## Test strategy row label \"" y "\" is not a known moment, ignored" > "/dev/stderr"; next }
                  if (!done && (x == tolower(r) || x == tolower(r2))) { done = 1; u = c[3]; j = c[4]; s = c[5]
                    sub(/[(,].*/, "", u); sub(/[(,].*/, "", j)
                    gsub(/[ \t`*]/, "", u); gsub(/[ \t`*]/, "", j); gsub(/^[ \t]+|[ \t]+$/, "", s)
                    out = tolower(u) "\t" tolower(j) "\t" s } }
    END { if (done) print out }' PROJECT.md)"
  if [ -n "$_row" ]; then
    _u="$(printf '%s' "$_row" | cut -f1)"; _j="$(printf '%s' "$_row" | cut -f2)"; _s="$(printf '%s' "$_row" | cut -f3)"
    case "$_u" in none|affected|module|full) U="$_u" ;; *) FROM="row '$ROW' unit scope '$_u' unknown, default used; " ;; esac
    case "$_j" in none|affected|module|full) J="$_j" ;; *) FROM="${FROM}row '$ROW' journey scope '$_j' unknown, default used; " ;; esac
    case "$FROM" in default:*) FROM="PROJECT.md ## Test strategy, row '$ROW'${_s:+, $_s}" ;; *) FROM="${FROM}PROJECT.md ## Test strategy" ;; esac
  fi
fi

# ── Unit gate: off unless the project default is yes, the row says so, or a module is flipped ──
UNIT_DEFAULT="$(awk '/^[ \t*]*Unit tests default:/ { v = $0; sub(/^[^:]*:/, "", v); gsub(/[ \t*`]/, "", v); print tolower(v); exit }' PROJECT.md 2>/dev/null)"
[ -d "$WORK" ] && : > "$WORK/unitflows"
FLIPPED="$(awk 'tolower($0) ~ /^[ \t*>-]*unit modules:/ { v = $0; sub(/^[^:]*:/, "", v); sub(/#.*/, "", v); gsub(/\([^)]*\)/, "", v)
  gsub(/[ \t*`,]+/, " ", v); n = split(v, a, " "); o = ""
  for (i = 1; i <= n; i++) if (tolower(a[i]) != "none") o = o " " a[i]
  print o; exit }' PROJECT.md 2>/dev/null)"
for _b in architecture/modules/*/module-brief.md architecture/modules/*-brief.md; do
  [ -f "$_b" ] || continue
  case "$_b" in */module-brief.md) _m="$(basename "$(dirname "$_b")")" ;; *) _m="$(basename "$_b" -brief.md)" ;; esac
  if awk '
      tolower($0) ~ /^[ \t*-]*unit tests:[ \t*]*yes([^a-z]|$)/ { f = 1 }
      /^\|/ { split($0, c, "|"); k = tolower(c[2]); v = tolower(c[3]); gsub(/[ \t*`]/, "", v)
              if (k ~ /^[ \t]*unit[ \t]*\(/ && v ~ /^yes/) f = 1 }
      END { exit !f }' "$_b"; then FLIPPED="$FLIPPED $_m"; fi
  # Unit flows: a bullet list `- [Module.]Flow[ (note)][: reason]` under a `Unit flows:` line, or inline
  # `Unit flows: A, B` (comma-split, each may carry `: reason`), `-`/`*`/`+`/numbered bullets, or a `## Unit flows`
  # heading, optionally `(note)`. Blank lines are skipped; an indented non-bullet line continues the previous
  # reason; the block ends at the next heading or an unindented `Word words:` field; any other line warns.
  # A line in the block that cannot be read warns with its text, never dropped silently.
  awk -v m="$_m" -v b="$_b" '
    function trim(t) { gsub(/^[ \t]+|[ \t]+$/, "", t); return t }
    function warn(t) { print "warning: Unit flows in " b ": cannot read \"" t "\"; write `- ACT_Name: reason`" > "/dev/stderr" }
    function item(l,   nm, rest, par, r, i) {
      gsub(/`|\*\*/, "", l); l = trim(l)
      if (l == "") return
      if (substr(l, 1, 1) == "<") { seen++; return }
      if (!match(l, /^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)?/)) { warn(l); return }
      nm = substr(l, 1, RLENGTH); rest = trim(substr(l, RLENGTH + 1)); par = ""
      if (substr(rest, 1, 1) == "(") { i = index(rest, ")"); if (i) { par = substr(rest, 2, i - 2); rest = trim(substr(rest, i + 1)) } }
      if (rest == "") r = par
      else if (substr(rest, 1, 1) == ":") { r = trim(substr(rest, 2)); if (r == "") r = par }
      else if (rest ~ /^-[ \t]/) r = trim(substr(rest, 2))
      else { warn(l); return }
      seen++; print (index(nm, ".") ? nm : m "." nm) "\t" r
    }
    function flush() { if (pend != "") item(pend); pend = "" }
    { sub(/\r$/, "") }
    # header: `Unit flows` (any heading level or plain), optional `(note)`, optional `:` and inline items
    tolower($0) ~ /^[ \t*>#-]*unit flows[ \t*]*(\([^)]*\))?[ \t*]*(:.*)?$/ {
      flush(); on = 1; hdr = 1; v = $0; sub(/^[^:]*(\([^)]*\))?[^:]*:?/, "", v)
      if (index($0, ":") == 0 || $0 ~ /^[^:]*\([^)]*:/) v = ""
      gsub(/`|\*\*/, "", v); v = trim(v)
      if (v != "") { k = split(v, a, ","); for (j = 1; j <= k; j++) item(a[j]) }
      next }
    !on { next }
    /^[ \t]*$/ { next }
    /^[ \t]*([-*+]|[0-9]+[.)])[ \t]/ { flush(); l = $0; sub(/^[ \t]*([-*+]|[0-9]+[.)])[ \t]+/, "", l); pend = l; next }
    /^[ \t]+[^ \t]/ && !/^[ \t]*#/ { if (pend != "") pend = pend " " trim($0); next }
    /^[ \t]*#/ { flush(); on = 0; next }
    /^[A-Za-z][A-Za-z]*([ \t]+[A-Za-z]+)*[ \t]*:/ { flush(); on = 0; next }
    { flush(); warn(trim($0)); next }
    END { flush(); if (hdr && !seen) print "warning: Unit flows in " b " looks like a Unit flows block but lists no flow; write `- ACT_Name: reason` lines under `Unit flows:`" > "/dev/stderr" }' "$_b" >> "$WORK/unitflows"
done
# a module with a Unit flows list is flipped by it
for _lm in $(cut -f1 "$WORK/unitflows" | sed 's/\..*//' | sort -u); do FLIPPED="$FLIPPED $_lm"; done
UNIT_GATED=0; UNIT_OFF_WHY=""
if [ "$MOMENT" != deploy ] && [ "${UNIT_DEFAULT#yes}" = "$UNIT_DEFAULT" ]; then
  if [ -n "$UNIT_DEFAULT" ]; then _dw="PROJECT.md Unit tests default: $UNIT_DEFAULT"
  else _dw="PROJECT.md has no 'Unit tests default:' line, treated as no"; fi
  if [ -n "$FLIPPED" ]; then UNIT_GATED=1; [ "$U" = none ] && U="$DU"
  else U=none; UNIT_OFF_WHY="($_dw; flip a module: PROJECT.md 'Unit modules: <M>', or 'Unit tests: yes' or a 'Unit flows:' list in its brief)"; fi
  FROM="$FROM; unit: $_dw"
fi
out "strategy	$MOMENT	unit=$U journeys=$J	($FROM)"

# ── Subjects ─────────────────────────────────────────────────────────────────
: > "$WORK/subjects"
if [ -n "$SCRIPTS" ]; then
  printf '%s\n' "$SCRIPTS" | while IFS= read -r s; do
    bash "$HERE/exec.sh" --subjects "$s" 2>/dev/null | while IFS='	' read -r k n l; do
      printf '%s\t%s\t%s of %s\n' "$k" "$n" "$l" "$(basename "$s")"
    done
  done > "$WORK/subjects"
fi
# A grant/revoke on an object this same script creates or modifies belongs to that subject.
awk -F'\t' '
  function scr(w,   a) { split(w, a, " of "); return a[2] }
  NR == FNR { if ($1 != "access" && $1 != "unmapped") own[$2 "\t" scr($3)] = 1; next }
  $1 == "access" && (($2 "\t" scr($3)) in own) { print $1 "\t" $2 "\t" $3 "\tPART" ; next }
  { print $0 "\t" }' "$WORK/subjects" "$WORK/subjects" > "$WORK/subjects.tag"
: > "$WORK/subjects.sel"
while IFS='	' read -r k n w tag; do
  if [ "$tag" = PART ]; then out "subject	$k	$n	$w	(grant on an object this script changes: part of that subject, selects nothing by module)"
  else out "subject	$k	$n	$w"; printf '%s\t%s\t%s\n' "$k" "$n" "$w" >> "$WORK/subjects.sel"; fi
done < "$WORK/subjects.tag"
mv "$WORK/subjects.sel" "$WORK/subjects"
[ -n "$SCRIPTS" ] && [ ! -s "$WORK/subjects" ] && out "subject	none	-	no model-writing statement in the script(s)"
mod_of() { printf '%s\n' "${1%%.*}"; }
awk -F'\t' '$2 != "-" && $1 != "userrole" { split($2, a, "."); print a[1] }' "$WORK/subjects" > "$WORK/modules"
for m in $MODULES; do echo "$m" >> "$WORK/modules"; done
sort -u "$WORK/modules" -o "$WORK/modules"

# ── Callers (one batched mxcli call) ─────────────────────────────────────────
: > "$WORK/callers"
awk -F'\t' '$1 ~ /^(microflow|nanoflow|page|snippet|layout)$/ { print $2 }' "$WORK/subjects" | sort -u > "$WORK/flowish"
CALLERS="NOT MEASURED"
if [ "$U" != affected ] && [ "$J" != affected ]; then
  CALLERS="not needed (no affected scope at this moment)"
elif [ ! -s "$WORK/flowish" ]; then
  CALLERS="not needed (no microflow, nanoflow, page, snippet or layout subject)"
elif [ "$NO_MODEL" = 1 ]; then
  CALLERS="NOT MEASURED (--no-model)"
else
  MX="${MXCLI:-$(find_project_mxcli 2>/dev/null || true)}"
  MPR="$(find_mpr 2>/dev/null || true)"
  if [ -z "$MX" ] || [ ! -x "$MX" ]; then CALLERS="NOT MEASURED (no project mxcli; set MXCLI)"
  elif [ -z "$MPR" ]; then CALLERS="NOT MEASURED (no .mpr found)"
  else
    Q="$(sed 's/.*/SHOW CALLERS OF & TRANSITIVE/' "$WORK/flowish" | awk '{ printf "%s%s", (NR > 1 ? "; " : ""), $0 }')"
    "$MX" -p "$MPR" -c "$Q" > "$WORK/mx.out" 2> "$WORK/mx.err"; RC=$?
    _blocks="$(grep -c '^Callers of ' "$WORK/mx.out" 2>/dev/null)" || _blocks=0
    if [ "$RC" -ne 0 ] || [ "$_blocks" -ne "$(wc -l < "$WORK/flowish" | tr -d ' ')" ]; then
      _why="$(grep -v -e '^✓' -e '^WARNING: This is a' -e '^[[:space:]]*$' "$WORK/mx.err" | head -1)"
      CALLERS="NOT MEASURED (mxcli exit $RC, $_blocks of $(wc -l < "$WORK/flowish" | tr -d ' ') caller blocks${_why:+: $_why})"
    else
      CALLERS="measured (SHOW CALLERS OF ... TRANSITIVE, $_blocks subject(s))"
      awk '/^\| *[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]* *\| *[0-9]+ *\|$/ {
             split($0, c, "|"); n = c[2]; d = c[3]; gsub(/ /, "", n); gsub(/ /, "", d)
             if (!(n in best) || d + 0 < best[n]) best[n] = d + 0 }
           END { for (n in best) print n "\t" best[n] }' "$WORK/mx.out" | sort -t '	' -k2,2n -k1,1 > "$WORK/callers"
    fi
  fi
fi
while IFS='	' read -r n d; do out "caller	$n	depth $d"; done < "$WORK/callers"
out "callers	$CALLERS"
awk -F'\t' '$1 ~ /^(entity|association|enumeration|access|module|role|userrole|constant)$/ && $2 != "-" { print $1 "\t" $2 }' "$WORK/subjects" | sort -u |
  while IFS='	' read -r k n; do
    if [ "$k" = userrole ]; then out "data	NOT MEASURED	$k $n	(access change; a user role has no owning module, so no test or journey is selected by it)"
    else out "data	NOT MEASURED	$k $n	(cross-module use not measured; selected by owning module $(mod_of "$n") only)"; fi
  done

# ── Candidate files ──────────────────────────────────────────────────────────
find . \( -name .git -o -name .mpr-snapshots -o -name node_modules -o -name deployment \) -prune -o \
  -type f -name '*.test.mdl' -print 2>/dev/null | sed 's|^\./||' | sort > "$WORK/tests"
for _d in "$JDIR" tests/e2e; do [ -d "$_d" ] && find "$_d" -type f -name '*.journey.json' 2>/dev/null; done | sed 's|^\./||' | sort -u > "$WORK/journeys"

# names: the strings a test or journey must contain to be selected
names_for_unit() {
  awk -F'\t' '$2 != "-" && $1 !~ /^(entity|association|enumeration|access|module|userrole)$/ { print $2 }' "$WORK/subjects"
  awk -F'\t' -v d="$DEPTH" '$2 + 0 <= d { print $1 }' "$WORK/callers"
}
modules_for_unit() { awk -F'\t' '$2 != "-" && $1 ~ /^(entity|association|enumeration|access|module)$/ { split($2, a, "."); print a[1] }' "$WORK/subjects" | sort -u; }

select_unit() {  # $1 = scope; prints "<file>\t<why>"
  case "$1" in
    none) ;;
    full) sed 's/$/	full suite/' "$WORK/tests" ;;
    module)
      while IFS= read -r m; do [ -n "$m" ] || continue
        while IFS= read -r f; do grep -qE "(^|[^A-Za-z0-9_])$m\." "$f" 2>/dev/null && echo "$f	names module $m"; done < "$WORK/tests"
      done < "$WORK/modules" ;;
    affected)
      names_for_unit | sort -u > "$WORK/unames"
      [ -s "$WORK/unames" ] && while IFS= read -r f; do
        _hit="$(grep -o -w -F -f "$WORK/unames" "$f" 2>/dev/null | head -1)"
        [ -n "$_hit" ] && echo "$f	names $_hit"
      done < "$WORK/tests"
      modules_for_unit | while IFS= read -r m; do
        while IFS= read -r f; do grep -qE "(^|[^A-Za-z0-9_])$m\." "$f" 2>/dev/null && echo "$f	names module $m (data or access change)"; done < "$WORK/tests"
      done ;;
  esac | awk -F'\t' '!seen[$1]++'
}

# ── Widgets (which journeys walk a changed page) ─────────────────────────────
# Journeys are written against widget names and menu captions, not Module.Name, so name matching
# alone selects nothing for a page change. ALLWHY non-empty = select every journey (navigation or
# layout change, or the measurement failed: unsure means include).
: > "$WORK/widgets"; : > "$WORK/widget-pages"
WIDGETS="not needed"; ALLWHY=""
if [ "$J" = affected ] && [ -n "$SCRIPTS" ]; then
  if printf '%s\n' "$SCRIPTS" | while IFS= read -r _s; do cat "$_s"; done |
       grep -qiE '^[[:space:]]*(create|alter|drop|move)[[:space:]]([^;]*[[:space:]])?navigation([[:space:]]|$)'; then
    ALLWHY="navigation change: every journey walks the menu"; WIDGETS="not needed ($ALLWHY)"
  elif awk -F'\t' '$1 == "layout" { f = 1 } END { exit !f }' "$WORK/subjects"; then
    ALLWHY="layout change: every page, so every journey, uses it"; WIDGETS="not needed ($ALLWHY)"
  elif [ -s "$WORK/flowish" ]; then
    if [ "$NO_MODEL" = 1 ]; then WIDGETS="NOT MEASURED (--no-model)"
    elif case "$CALLERS" in "NOT MEASURED"*) true ;; *) false ;; esac; then WIDGETS="NOT MEASURED (callers $CALLERS)"
    else
      _MX="${MXCLI:-$(find_project_mxcli 2>/dev/null || true)}"; _MPR="$(find_mpr 2>/dev/null || true)"
      if [ -z "$_MX" ] || [ ! -x "$_MX" ] || [ -z "$_MPR" ]; then WIDGETS="NOT MEASURED (no project mxcli or .mpr)"
      else
        "$_MX" -p "$_MPR" -c "SHOW PAGES; SHOW SNIPPETS" > "$WORK/pg.out" 2> "$WORK/pg.err"; _rc=$?
        # the Qualified Name column of the two tables
        awk -F'|' '$2 ~ /^ *[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]* *$/ { n = $2; gsub(/ /, "", n); print n }' "$WORK/pg.out" | sort -u > "$WORK/allpages"
        { cat "$WORK/flowish"; cut -f1 "$WORK/callers"; } | sort -u > "$WORK/cand"
        comm -12 "$WORK/allpages" "$WORK/cand" > "$WORK/widget-pages"
        if [ "$_rc" -ne 0 ] || [ ! -s "$WORK/allpages" ]; then WIDGETS="NOT MEASURED (SHOW PAGES exit $_rc, $(wc -l < "$WORK/allpages" | tr -d ' ') page(s) listed)"
        elif [ ! -s "$WORK/widget-pages" ]; then WIDGETS="measured (0 of $(wc -l < "$WORK/cand" | tr -d ' ') changed or calling element(s) is a page or snippet)"
        else
          # second table in the output = SHOW SNIPPETS (its header has no Title column)
          _snip="$(awk '/^\| Qualified Name/ { h++ } h >= 2 && /^\| *[A-Za-z_]/ { split($0, c, "|"); n = c[2]; gsub(/ /, "", n); print n }' "$WORK/pg.out")"
          _q=""; while IFS= read -r _p; do
            if printf '%s\n' "$_snip" | grep -qxF "$_p"; then _q="${_q:+$_q; }DESCRIBE SNIPPET $_p"; else _q="${_q:+$_q; }DESCRIBE PAGE $_p"; fi
          done < "$WORK/widget-pages"
          "$_MX" -p "$_MPR" -c "$_q" > "$WORK/desc.out" 2> "$WORK/desc.err"; _rc=$?
          # widget heads: "<widgettype> <name> (" or "{" at the start of a line
          awk '/^[ \t]*[a-z][a-z0-9]*[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*[({]/ && $1 != "create" && $1 != "alter" { print $2 }' "$WORK/desc.out" |
            sed 's/[({].*//' | sort -u > "$WORK/widgets"
          if [ "$_rc" -ne 0 ] || [ ! -s "$WORK/widgets" ]; then WIDGETS="NOT MEASURED (DESCRIBE exit $_rc, $(wc -l < "$WORK/widgets" | tr -d ' ') widget name(s) read)"
          else WIDGETS="measured ($(wc -l < "$WORK/widgets" | tr -d ' ') widget name(s) in $(wc -l < "$WORK/widget-pages" | tr -d ' ') page/snippet(s))"; fi
        fi
      fi
    fi
    case "$WIDGETS" in "NOT MEASURED"*) ALLWHY="unsure, so every journey ($WIDGETS)" ;; esac
  fi
fi

select_journeys() {  # $1 = scope; prints "<file>\t<why>"
  case "$1" in
    none) ;;
    full) sed 's/$/	full suite/' "$WORK/journeys" ;;
    module|affected)
      { cat "$WORK/modules"; [ "$1" = affected ] && cut -f1 "$WORK/callers" | sed 's/\..*//'; } | sort -u |
        while IFS= read -r m; do
          [ -n "$m" ] && [ -f "$JDIR/$m.journey.json" ] && echo "$JDIR/$m.journey.json	module $m"
        done
      if [ "$1" = affected ]; then
        { awk -F'\t' '$2 ~ /\./ { print $2 }' "$WORK/subjects"; cut -f1 "$WORK/callers"; } | sort -u > "$WORK/jnames"
        [ -s "$WORK/jnames" ] && while IFS= read -r f; do
          _hit="$(grep -o -w -F -f "$WORK/jnames" "$f" 2>/dev/null | head -1)"
          [ -n "$_hit" ] && echo "$f	names $_hit"
        done < "$WORK/journeys"
        if [ -n "$ALLWHY" ]; then awk -v w="$ALLWHY" '{ print $0 "\t" w }' "$WORK/journeys"
        elif [ -s "$WORK/widgets" ]; then
          while IFS= read -r f; do
            _hit="$(grep -o -w -F -f "$WORK/widgets" "$f" 2>/dev/null | head -1)"
            [ -n "$_hit" ] && echo "$f	walks widget $_hit of a changed or calling page"
          done < "$WORK/journeys"
        fi
      fi ;;
  esac | awk -F'\t' '!seen[$1]++'
}

# Module names as typed in PROJECT.md or a brief: match case-insensitively, warn on strangers.
if [ -n "$FLIPPED" ]; then
  { cat "$WORK/modules"; for _b in architecture/modules/*/module-brief.md architecture/modules/*-brief.md; do
      [ -f "$_b" ] || continue
      case "$_b" in */module-brief.md) basename "$(dirname "$_b")" ;; *) basename "$_b" -brief.md ;; esac
    done
    [ -s "$WORK/tests" ] && xargs grep -ohE '(^|[^A-Za-z0-9_.])[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_]' < "$WORK/tests" 2>/dev/null | sed -E 's/^[^A-Za-z_]//; s/\..*//'
  } | sort -u > "$WORK/known"
  _canon=""
  for m in $FLIPPED; do
    _k="$(awk -v m="$m" 'tolower($0) == tolower(m) { print; exit }' "$WORK/known")"
    if [ -n "$_k" ]; then _canon="$_canon $_k"
    else _canon="$_canon $m"   # a module named only by a Unit flows list is checked against the model below
      awk -F'\t' -v m="$m" 'tolower(substr($1, 1, index($1, ".") - 1)) == tolower(m) { c = 1 } END { exit !c }' "$WORK/unitflows" ||
        echo "warning: Unit modules names '$m', which matches no module in the tests, briefs or this change" >&2; fi
  done
  FLIPPED="$_canon"
fi
select_unit "$U" > "$WORK/unit.sel"
canon_mod() { awk -v m="$1" 'tolower($0) == tolower(m) { print; f = 1; exit } END { if (!f) print m }' "$WORK/known" 2>/dev/null || echo "$1"; }
# list_sel <module>: the tests of that module's listed flows at the current scope; warns on an owed test
list_sel() {
  case "$U" in none) return ;; module) grep -qixF "$1" "$WORK/modules" || return ;; esac
  awk -F'\t' -v m="$1" 'tolower(substr($1, 1, index($1, ".") - 1)) == tolower(m) { print $1 "\t" $2 }' "$WORK/unitflows" |
  while IFS='	' read -r _fl _why; do
    if [ "$U" = affected ]; then grep -qixF "$_fl" "$WORK/touched" || grep -qixF "$1" "$WORK/datamods" || continue; fi
    _hit=0
    while IFS= read -r f; do
      grep -q -i -w -F "$_fl" "$f" 2>/dev/null && { _hit=1; printf '%s\tnames listed flow %s%s\n' "$f" "$_fl" "${_why:+ ($_why)}"; }
    done < "$WORK/tests"
    [ "$_hit" = 1 ] || echo "warning: Unit flows lists $_fl, which no .test.mdl names; its unit test is owed" >&2
  done
}
names_for_unit | sort -u > "$WORK/touched"
modules_for_unit > "$WORK/datamods"
LISTMODS=""
if [ -s "$WORK/unitflows" ] && [ "$MOMENT" != deploy ]; then
  for m in $(cut -f1 "$WORK/unitflows" | sed 's/\..*//' | sort -u); do LISTMODS="$LISTMODS
$(canon_mod "$m")"; done
  LISTMODS="$(printf '%s\n' "$LISTMODS" | sed '/^$/d' | sort -u | tr '\n' ' ' | sed 's/ $//')"
  awk -F'\t' '$2 == "" { print "warning: Unit flows lists " $1 " without a reason; one line why it needs a unit test (logic or integration)" > "/dev/stderr" }' "$WORK/unitflows"
  # unknown flow names: best effort, SHOW MICROFLOWS IN <M> (skipped without a model)
  if [ "$NO_MODEL" != 1 ]; then
    _mx="${MXCLI:-$(find_project_mxcli 2>/dev/null || true)}"; _mpr="$(find_mpr 2>/dev/null || true)"
    if [ -n "$_mx" ] && [ -x "$_mx" ] && [ -n "$_mpr" ]; then
      _lm="$(cut -f1 "$WORK/unitflows" | sed 's/\..*//' | sort -u)"
      _q="$(printf '%s\n' "$_lm" | sed 's/.*/SHOW MICROFLOWS IN &/' | awk '{ printf "%s%s", (NR > 1 ? "; " : ""), $0 }')"
      : > "$WORK/mf.missing"
      if ! "$_mx" -p "$_mpr" -c "$_q" > "$WORK/mf.out" 2>/dev/null; then
        # one call per module: missing = its error says so, or it fails while another module answers
        : > "$WORK/mf.out"; : > "$WORK/mf.fail"; _okn=0
        for _m in $_lm; do
          if "$_mx" -p "$_mpr" -c "SHOW MICROFLOWS IN $_m" >> "$WORK/mf.out" 2> "$WORK/mf.one"; then _okn=$((_okn+1))
          elif grep -qiE 'not found|does not exist|no such module|unknown module' "$WORK/mf.one"; then echo "$_m" >> "$WORK/mf.missing"
          else echo "$_m" >> "$WORK/mf.fail"; fi
        done
        [ "$_okn" -gt 0 ] && cat "$WORK/mf.fail" >> "$WORK/mf.missing"
        while IFS= read -r _m; do echo "warning: module $_m not found in the model (Unit flows lists it)" >&2; done < "$WORK/mf.missing"
      fi
      if grep -q '^| ' "$WORK/mf.out"; then
        awk -F'|' '/^\| *[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]* *\|/ { n = $2; gsub(/ /, "", n); print n }' "$WORK/mf.out" | sort -u > "$WORK/mf.names"
        cut -f1 "$WORK/unitflows" | sort -u | while IFS= read -r _f; do
          grep -qixF "${_f%%.*}" "$WORK/mf.missing" && continue
          grep -qxF "$_f" "$WORK/mf.names" && continue
          _real="$(grep -ixF "$_f" "$WORK/mf.names" | head -1)"
          if [ -n "$_real" ]; then echo "warning: Unit flows lists '$_f' but the model has '$_real' (casing differs)" >&2
          else echo "warning: Unit flows names '$_f', which is not a microflow in the model" >&2; fi
        done
      fi
    fi
  fi
fi
if [ "$UNIT_GATED" = 1 ]; then   # default no, some modules flipped: only those modules' tests
  : > "$WORK/unit.gated"
  for m in $FLIPPED; do
    case " $LISTMODS " in
    *" $m "*) list_sel "$m" >> "$WORK/unit.gated" ;;   # per flow: the listed flows' tests only
    *)
      while IFS='	' read -r f w; do grep -qE "(^|[^A-Za-z0-9_])$m\." "$f" 2>/dev/null && printf '%s\t%s\n' "$f" "$w"; done < "$WORK/unit.sel" >> "$WORK/unit.gated" ;;
    esac
  done
  awk -F'\t' '!seen[$1]++' "$WORK/unit.gated" > "$WORK/unit.sel"
elif [ -n "$LISTMODS" ]; then   # default yes: a module with a list is narrowed to it, the rest stay on
  : > "$WORK/unit.ls"; for m in $LISTMODS; do list_sel "$m" >> "$WORK/unit.ls"; done
  while IFS='	' read -r f w; do
    # governed by a list only when EVERY module the test names is a listed module; any other module is on, keep the test
    _gov="$(awk -v lm="$LISTMODS" 'BEGIN { n = split(tolower(lm), L, " "); for (i = 1; i <= n; i++) isl[L[i]] = 1 }
      { s = $0; while (match(s, /(^|[^A-Za-z0-9_.$])[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_]/)) {
          q = substr(s, RSTART, RLENGTH); sub(/^[^A-Za-z_]/, "", q); sub(/\..*/, "", q); q = tolower(q)
          if (q in isl) hl = 1; else if (q != "system") ho = 1
          s = substr(s, RSTART + RLENGTH) } }
      END { print (hl && !ho) ? 1 : 0 }' "$f" 2>/dev/null)"
    [ "$_gov" = 1 ] || printf '%s\t%s\n' "$f" "$w"
  done < "$WORK/unit.sel" > "$WORK/unit.new"
  cat "$WORK/unit.ls" >> "$WORK/unit.new"
  awk -F'\t' '!seen[$1]++' "$WORK/unit.new" > "$WORK/unit.sel"
fi
select_journeys "$J" > "$WORK/journey.sel"
if [ -n "$UNIT_OFF_WHY" ]; then out "unit	off	$UNIT_OFF_WHY"
elif [ -s "$WORK/unit.sel" ]; then sed 's/^/unit	/' "$WORK/unit.sel"
else out "unit	none	scope $U: $( [ "$U" = none ] && echo 'strategy says none' || echo "0 of $(wc -l < "$WORK/tests" | tr -d ' ') .test.mdl file(s) match${FLIPPED:+ (unit on only for:$FLIPPED${LISTMODS:+; per listed flow in:$LISTMODS})}")"; fi
[ "$J" = affected ] && [ -n "$SCRIPTS" ] && out "widgets	$WIDGETS"
if [ -s "$WORK/journey.sel" ]; then sed 's/^/journey	/' "$WORK/journey.sel"
else out "journey	none	scope $J: $( [ "$J" = none ] && echo 'strategy says none' || echo "0 of $(wc -l < "$WORK/journeys" | tr -d ' ') journey file(s) in $JDIR/ and tests/e2e/ match")"; fi

# Journeys that name-based selection can never reach: not <JDIR>/<Module>.journey.json and no
# qualified Module.Name inside (they navigate by menu caption). Printed whenever a name-based
# scope is in play, so "journey none" cannot read as "nothing owed".
if [ "$J" = affected ] || [ "$J" = module ]; then
  _tot="$(wc -l < "$WORK/journeys" | tr -d ' ')"; _un=0
  while IFS= read -r f; do [ -n "$f" ] || continue
    # mapped by name only when the stem is ONE identifier: <JDIR>/<Module>.journey.json
    case "$f" in "$JDIR"/*.journey.json)
      _stem="${f##*/}"; _stem="${_stem%.journey.json}"
      case "$_stem" in ''|*[!A-Za-z0-9_]*) ;; *) continue ;; esac ;; esac
    grep -qE '(^|[^A-Za-z0-9_.])[A-Z][A-Za-z0-9_]*\.[A-Z][A-Za-z0-9_]*' "$f" 2>/dev/null || _un=$((_un+1))
  done < "$WORK/journeys"
  [ "$_tot" -gt 0 ] && out "journeys	unmapped	$_un of $_tot journey file(s) are not named <Module>.journey.json and hold no qualified Module.Name: selection by name cannot reach them; read them before saying nothing is owed"
fi

# ── Run rows ─────────────────────────────────────────────────────────────────
_uf="$(cut -f1 "$WORK/unit.sel" | tr '\n' ' ' | sed 's/ $//')"
_jf="$(cut -f1 "$WORK/journey.sel" | tr '\n' ' ' | sed 's/ $//')"
[ -n "$_uf" ] && out "run	./bin/test-scratch.sh -- $_uf --local"
[ -n "$_jf" ] && out "run	node tests/e2e/journey-runner.js $_jf"
exit 0
