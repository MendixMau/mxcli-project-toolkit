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
#   unit      <file.test.mdl>  <why>
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
#   | Module close | module | module | CONFIRMED |
#   | Deploy-ready | full | full | CONFIRMED |
# Scopes: none | affected | module | full. No section, or no row for the moment: these defaults,
# and the strategy row says "default". --moment picks the row (change is the default).
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
#      selection is never read as "nothing owed".
#   5. module: every test file naming the module, journeys/<M>.journey.json; the modules are the
#      subjects' modules plus every --module. full: every test file, every journey file.
#   6. data subjects (entity, association, enumeration, access, module, module role, user role,
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
case "$MOMENT" in change|module|deploy) ;; *) echo "✗ --moment takes change, module or deploy" >&2; exit 2 ;; esac
case "$DEPTH" in ''|*[!0-9]*) echo "✗ --depth takes a number" >&2; exit 2 ;; esac
SCRIPTS="$(printf '%s\n' "$SCRIPTS" | sed '/^$/d')"
[ -n "$SCRIPTS" ] || [ "$MOMENT" != change ] || { echo "✗ a change needs at least one script" >&2; usage; }

cd "$PROJECT_ROOT" || exit 2
JDIR="${JOURNEY_DIR:-journeys}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/affected.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
out() { printf '%s\n' "$*"; }

# ── Strategy row ─────────────────────────────────────────────────────────────
case "$MOMENT" in change) ROW="Every change"; DU=affected; DJ=affected ;;
                  module) ROW="Module close"; DU=module;   DJ=module ;;
                  deploy) ROW="Deploy-ready"; DU=full;     DJ=full ;; esac
U="$DU"; J="$DJ"; FROM="default: PROJECT.md has no '## Test strategy' row '$ROW' (CAC-5 records it)"
if [ -f PROJECT.md ]; then
  _row="$(awk -v r="$ROW" '
    /^## /{ on = ($0 ~ /^## Test strategy/) ; next }
    on && /^\|/ { split($0, c, "|"); x = c[2]; gsub(/^[ \t]+|[ \t]+$/, "", x)
                  if (tolower(x) == tolower(r)) { u = c[3]; j = c[4]; s = c[5]
                    gsub(/[ \t`*]/, "", u); gsub(/[ \t`*]/, "", j); gsub(/^[ \t]+|[ \t]+$/, "", s)
                    print tolower(u) "\t" tolower(j) "\t" s; exit } }' PROJECT.md)"
  if [ -n "$_row" ]; then
    _u="$(printf '%s' "$_row" | cut -f1)"; _j="$(printf '%s' "$_row" | cut -f2)"; _s="$(printf '%s' "$_row" | cut -f3)"
    case "$_u" in none|affected|module|full) U="$_u" ;; *) FROM="row '$ROW' unit scope '$_u' unknown, default used; " ;; esac
    case "$_j" in none|affected|module|full) J="$_j" ;; *) FROM="${FROM}row '$ROW' journey scope '$_j' unknown, default used; " ;; esac
    case "$FROM" in default:*) FROM="PROJECT.md ## Test strategy, row '$ROW'${_s:+, $_s}" ;; *) FROM="${FROM}PROJECT.md ## Test strategy" ;; esac
  fi
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
while IFS='	' read -r k n w; do out "subject	$k	$n	$w"; done < "$WORK/subjects"
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
      fi ;;
  esac | awk -F'\t' '!seen[$1]++'
}

select_unit "$U" > "$WORK/unit.sel"
select_journeys "$J" > "$WORK/journey.sel"
if [ -s "$WORK/unit.sel" ]; then sed 's/^/unit	/' "$WORK/unit.sel"
else out "unit	none	scope $U: $( [ "$U" = none ] && echo 'strategy says none' || echo "0 of $(wc -l < "$WORK/tests" | tr -d ' ') .test.mdl file(s) match")"; fi
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
