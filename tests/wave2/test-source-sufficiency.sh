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
#
# Carries a FILLED inventory row. The inventory is pass 1 of the two-pass rubric and it blocks
# scoring, so a fixture without one exercises the legacy-rubric path rather than the current
# instrument — and the legacy warning on stderr would corrupt the `--json 2>&1` assertion
# below. The single row claims every dimension so the "graded but claimed by no source"
# warning stays quiet here; the tests that want those states build their own.
rubric() {
  d=$1; r=$2; c=${3:-[]}; l=${4:-[]}
  mkdir -p "$d/analysis"
  {
    printf '{"assessedAt":"2026-01-01","sources":["s.md"],'
    printf '"inventory":[{"path":"s.md","bytes":10,"kind":"docs","answers":['
    printf '"actors","domain","processes","rules","ui","integrations","nfr","tenancy",'
    printf '"security_model","data_migration"],"statedScope":"","components":[]}],'
    printf '"dimensions":{'
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

echo "== pass 1: the inventory =="
#
# The failure these pin: a live Stage 0 run (2026-08-19) graded a four-file documents-only
# corpus without the OpenAPI contract, because init's scan was documents-only, and asked the
# user closed rubric-shaped questions because nothing produced a source map. Both halves.

P7="$TMP/p7"; mkdir -p "$P7/analysis/source"
: > "$P7/analysis/source/spec.md"
: > "$P7/analysis/source/openapi.yaml"
: > "$P7/analysis/source/schema.sql"
: > "$P7/analysis/source/config.json"
mkdir -p "$P7/analysis/source/node_modules/junk"; : > "$P7/analysis/source/node_modules/junk/a.json"
OUT=$("$SS" init "$P7" --sources "$P7/analysis/source" 2>&1)
has "machine-readable sources are in the corpus" "$OUT" "4 file(s)"
grep -q 'openapi.yaml' "$P7/analysis/source-sufficiency.json" \
  && ok "  the .yaml contract is listed, not silently skipped" \
  || bad "  the .yaml contract is listed, not silently skipped"
grep -q 'schema.sql' "$P7/analysis/source-sufficiency.json" \
  && ok "  so is the .sql schema" || bad "  so is the .sql schema"
grep -q 'node_modules' "$P7/analysis/source-sufficiency.json" \
  && bad "  node_modules is pruned" || ok "  node_modules is pruned"

# An unopened file blocks the grade, and blocks it BEFORE the dimension check — otherwise the
# first thing a reader is told is to grade a corpus nobody has identified.
OUT=$("$SS" report "$P7" 2>&1); RC=$?
check "an unfilled inventory refuses to score" "$RC" "3"
has "  and names an unopened file" "$OUT" "openapi.yaml"
has "  and says which pass comes first" "$OUT" "Pass 1 before pass 2"

# A dimension rated from outside the corpus is called out rather than quietly scored.
P8="$TMP/p8"; mkdir -p "$P8/analysis"
"$PY" - "$P8/analysis/source-sufficiency.json" <<'PY'
import json, sys
keys = ["actors","domain","processes","rules","ui","integrations","nfr","tenancy",
        "security_model","data_migration"]
doc = {
    "assessedAt": "2026-01-01", "sources": ["s.md"],
    # claims everything EXCEPT security_model, which is nonetheless graded `specified` below
    "inventory": [{"path": "s.md", "bytes": 10, "kind": "docs",
                   "answers": [k for k in keys if k != "security_model"],
                   "statedScope": "covers ordering only, not billing",
                   "components": ["Orders", "Catalog"]}],
    "dimensions": {k: {"demands": "d", "rating": "specified", "evidence": "e",
                       "consequence": "c"} for k in keys},
    "conflicts": [], "landmines": [],
}
json.dump(doc, open(sys.argv[1], "w"))
PY
OUT=$("$SS" report "$P8" 2>&1)
has "the overview prints before the grade" "$OUT" "Source overview:"
has "  it surfaces a source's own stated scope" "$OUT" "covers ordering only"
has "  it lists the components the sources define" "$OUT" "Orders"
has "  an uncovered dimension is named" "$OUT" "security_model"
has "  grading it anyway is called out" "$OUT" "claimed by NO source"

# Ordering is load-bearing: the overview suggests open questions, the grade suggests closed
# ones. An agent that reads the grade first asks the wrong question, which is the reported bug.
case "$OUT" in
  *"Source overview:"*"Source sufficiency:"*) ok "  overview precedes the verdict" ;;
  *) bad "  overview precedes the verdict" ;;
esac

# In-flight projects hold pre-inventory rubrics. Those must still score, and must say so.
P9="$TMP/p9"; rubric "$P9" specified
"$PY" - "$P9/analysis/source-sufficiency.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d.pop("inventory", None); json.dump(d, open(p, "w"))
PY
OUT=$("$SS" report "$P9" 2>&1); RC=$?
check "a pre-inventory rubric still scores" "$RC" "0"
has "  but says its grade is not backed by a characterised corpus" "$OUT" "predates the inventory pass"

echo
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
