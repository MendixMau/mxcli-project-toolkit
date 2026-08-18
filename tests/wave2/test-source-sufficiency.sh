#!/bin/bash
# test-source-sufficiency.sh — pin source-sufficiency.sh's behaviour.
#
# The two things worth pinning here are not the happy path.
#
#   1. THE SCALE IS NOT PINNED TO THE FLOOR. An instrument that grades every source SKETCH is
#      exactly as useless as one that passes everything, and much more convincing. So a thick
#      fixture must reach SPECIFICATION and a thin one must not, using the same code path.
#
#   2. UNRATED IS NOT ABSENT. Four false-green bugs were found in this toolkit's instruments in
#      one session, every one of them a clean report over data that was never read. An unfilled
#      rubric must exit 3, and a partially-filled one must refuse to score rather than quietly
#      treat the unread rows as zeroes.

set -u

TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
SS="$TOOLKIT/bin/source-sufficiency.sh"
# Portability: the test suite must run on the platforms the toolkit targets, or a Windows fix
# can never be verified on Windows. Resolve Python by executing candidates, not by name.
# shellcheck disable=SC1091
. "$TOOLKIT/bin/lib/portable.sh"
require_py

PASS=0; FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected '$3', got '$2'"; fi; }
has()  { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "missing '$3'" ;; esac; }
hasnt(){ case "$2" in *"$3"*) bad "$1" "unexpected '$3'" ;; *) ok "$1" ;; esac; }

# rubric <dir> <rating-for-all> [conflicts-json] [landmines-json]
rubric() {
  d=$1; r=$2; c=${3:-[]}; l=${4:-[]}
  mkdir -p "$d/analysis"
  {
    printf '{"assessedAt":"2026-01-01","sources":["s.md"],"dimensions":{'
    first=1
    for k in actors domain processes rules ui integrations nfr tenancy security_model data_migration; do
      [ $first -eq 1 ] || printf ','
      first=0
      printf '"%s":{"demands":"d","rating":"%s","evidence":"e","consequence":"c"}' "$k" "$r"
    done
    printf '},"conflicts":%s,"landmines":%s}' "$c" "$l"
  } > "$d/analysis/source-sufficiency.json"
}

echo "== init =="

P="$TMP/p1"; mkdir -p "$P/analysis/source"
: > "$P/analysis/source/spec.md"; : > "$P/analysis/source/deck.pdf"
OUT=$("$SS" init "$P" --sources "$P/analysis/source" 2>&1)
has "init reports the corpus size" "$OUT" "2 file(s)"
[ -f "$P/analysis/source-sufficiency.json" ] && ok "init writes the rubric" || bad "init writes the rubric"

OUT=$("$SS" init "$P" --sources "$P/analysis/source" 2>&1); RC=$?
check "init refuses to overwrite an assessment" "$RC" "2"
has "  and says why" "$OUT" "refusing to overwrite"

# An empty corpus is a different thing from a thin source, and must not read as one.
P2="$TMP/p2"; mkdir -p "$P2/analysis/empty"
OUT=$("$SS" init "$P2" --sources "$P2/analysis/empty" 2>&1)
has "empty corpus is called out, not treated as thin" "$OUT" "not a thin source; it is no source"

echo "== unread data never scores =="

P3="$TMP/p3"; mkdir -p "$P3"
"$SS" init "$P3" >/dev/null 2>&1
OUT=$("$SS" report "$P3" 2>&1); RC=$?
check "unfilled rubric exits 3" "$RC" "3"
has "  names the unrated count against the total" "$OUT" "10 of 10 dimensions unrated"
hasnt "  and does not print a verdict" "$OUT" "build-ready"

# The dangerous case: nine rated, one silently unread.
rubric "$TMP/p4" specified
"$PY" - "$TMP/p4/analysis/source-sufficiency.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d['dimensions']['tenancy']['rating']=None
json.dump(d,open(p,'w'))
PY
OUT=$("$SS" report "$TMP/p4" 2>&1); RC=$?
check "one unrated row still refuses to score" "$RC" "3"
has "  and names the row" "$OUT" "tenancy"

rubric "$TMP/p5" excellent
OUT=$("$SS" report "$TMP/p5" 2>&1); RC=$?
check "an invented rating is rejected, not coerced" "$RC" "4"
has "  and lists the legal values" "$OUT" "absent/named/specified/verified"

echo '{"dimensions":{}}' > "$TMP/p5/analysis/source-sufficiency.json"
OUT=$("$SS" report "$TMP/p5" 2>&1); RC=$?
check "a rubric with no dimensions is invalid, not empty-clean" "$RC" "4"

echo "== the scale spans its range =="

rubric "$TMP/thick" verified
OUT=$("$SS" report "$TMP/thick" --quiet 2>&1; "$SS" report "$TMP/thick" 2>&1)
has "a fully-specified source reaches SPECIFICATION" "$OUT" "SPECIFICATION"
has "  at 100%" "$OUT" "100% build-ready"
has "  and is described as a conversion" "$OUT" "can reasonably be called a conversion"

rubric "$TMP/thin" absent
OUT=$("$SS" report "$TMP/thin" 2>&1)
has "an empty source is SKETCH" "$OUT" "SKETCH"
has "  at 0%" "$OUT" "0% build-ready"
hasnt "  and is never called a conversion" "$OUT" "can reasonably be called a conversion"

# `named` must be worth nothing. If it scored partial credit, ten vendor name-drops would
# add up to a passing grade, which is the precise failure this instrument exists to catch.
rubric "$TMP/named" named
OUT=$("$SS" report "$TMP/named" 2>&1)
has "a source that names everything and decides nothing scores 0%" "$OUT" "0% build-ready"

echo "== gap vs contradiction routes differently =="

rubric "$TMP/silent" absent '[]' '[]'
OUT=$("$SS" report "$TMP/silent" 2>&1)
has "thin and self-consistent recommends auto" "$OUT" "recommended interview mode: auto"
has "  because asking unanswerable questions is theatre" "$OUT" "theatre"

rubric "$TMP/clash" absent '[{"title":"two owners disagree"}]' '[]'
OUT=$("$SS" report "$TMP/clash" 2>&1)
has "one contradiction forces steering" "$OUT" "recommended interview mode: steering"
has "  and says a contradiction cannot be assumed away" "$OUT" "cannot be assumed"

# A contradiction outranks a landmine: both present must still be steering.
rubric "$TMP/both" absent '[{"title":"x"}]' '[{"title":"y"}]'
OUT=$("$SS" report "$TMP/both" 2>&1)
has "contradiction outranks a shape-changing gap" "$OUT" "recommended interview mode: steering"

rubric "$TMP/shape" absent '[]' '[{"title":"multi-tenancy filed as an NFR"}]'
OUT=$("$SS" report "$TMP/shape" 2>&1)
has "a shape-changing gap alone recommends assist" "$OUT" "recommended interview mode: assist"

# A well-specified source should not be pushed to auto just because it is quiet.
rubric "$TMP/good" specified '[]' '[]'
OUT=$("$SS" report "$TMP/good" 2>&1)
has "a well-specified quiet source recommends assist, not auto" "$OUT" "recommended interview mode: assist"

echo "== output =="

rubric "$TMP/h" specified
"$SS" report "$TMP/h" --html "$TMP/h/out.html" >/dev/null 2>&1
[ -s "$TMP/h/out.html" ] && ok "renders html" || bad "renders html"
grep -q "prefers-color-scheme" "$TMP/h/out.html" && ok "  theme-aware" || bad "  theme-aware"
grep -q "data-theme=\"dark\"" "$TMP/h/out.html" && ok "  honours an explicit theme" || bad "  honours an explicit theme"

# Every printed count must carry what it was counted against.
OUT=$("$SS" report "$TMP/h" 2>&1)
has "the verdict carries its denominator" "$OUT" "of 10 dimensions"
has "  and its corpus size" "$OUT" "source file(s)"

OUT=$("$SS" report "$TMP/h" --json 2>&1)
echo "$OUT" | "$PY" -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d["total"]==10 and "pct" in d else 1)' \
  && ok "--json is machine-readable and carries the total" || bad "--json is machine-readable and carries the total"

OUT=$("$SS" report "$TMP/nonexistent-dir" 2>&1); RC=$?
check "a missing project dir is a usage error" "$RC" "2"

P6="$TMP/p6"; mkdir -p "$P6/analysis"
OUT=$("$SS" report "$P6" 2>&1); RC=$?
check "a missing rubric exits 3, not 0" "$RC" "3"
has "  and says how to make one" "$OUT" "init"

echo
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
