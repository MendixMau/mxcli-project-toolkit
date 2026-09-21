#!/bin/bash
# test-app-layer-map.sh — pin app-layer-map.sh's ordering, back-edge reporting and determinism.
#
# Runs with no mxcli and no .mpr: entirely against the captured fixture
# fixtures/app-analysis/facts/dependencies.json (an invented app with a tangle covering ten of
# thirteen own modules, by design — see the fixture's own _fixture_note). What is worth pinning:
#
#   1. THE TANGLE IS FOUND. A tangle of mutually reachable modules is recomputed from the edges
#      and cross-checked against dependencies.json's own counts.largest_tangle; a disagreement
#      must be reported ("mismatch" non-null), never silently reconciled — this fixture's counts
#      agree, so mismatch must be null.
#   2. EVERY BACK EDGE CARRIES ITS WEIGHT AND KINDS. The page's whole value proposition is that
#      forward edges are implied by the order and only backward (wrong-direction) edges are drawn
#      — so every entry in back_edges_list must have a positive weight and a non-empty kinds map,
#      never a bare "there is a backward edge here" with the reference detail dropped.
#   3. DETERMINISTIC ORDER. The sifting pass is a heuristic, not proven minimal, but it must be
#      deterministic: two runs against the same facts must produce the identical module order and
#      the identical back_edges_list, so a page rebuilt from unchanged facts does not reshuffle
#      the reading order out from under a reviewer who bookmarked a position in it.
#   4. DEGRADES. No facts directory, or a facts directory with no dependencies.json, is exit 2 —
#      there is nothing to draw. A facts directory with dependencies.json but no inventory.json
#      or manifest.json still renders, with the gap named on the page rather than silently
#      dropped.
#
# Usage: bash test-app-layer-map.sh [path-to-app-layer-map.sh]

set -u

TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
ALM="${1:-$TOOLKIT/bin/app-layer-map.sh}"
FIX="$TOOLKIT/fixtures/app-analysis"
# shellcheck disable=SC1091
. "$TOOLKIT/bin/lib/portable.sh"
require_py

PASS=0; FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected '$3', got '$2'"; fi; }
jq_()  { "$PY" -c 'import json,sys; d=json.load(open(sys.argv[1]))
for k in sys.argv[2].split("/"):
    d = d[int(k)] if isinstance(d, list) else d.get(k, "MISSING")
    if d == "MISSING": break
print("null" if d is None else (json.dumps(d) if isinstance(d,(dict,list)) else d))' "$1" "$2"; }

echo "== app-layer-map.sh --json (fixture: tangle over 10 of 13 own modules) =="
bash "$ALM" --facts "$FIX/facts" --json >"$TMP/run1.json" 2>"$TMP/run1.err"; RC=$?
check "run 1 exits 0" "$RC" "0"
[ -s "$TMP/run1.json" ] || { bad "run 1 produced JSON" "$(cat "$TMP/run1.err")"; echo; echo "$PASS passed, $FAIL failed"; exit 1; }

check "own_modules matches scope" "$(jq_ "$TMP/run1.json" own_modules)" "13"
check "the recomputed tangle agrees with dependencies.json's own counts (no mismatch)" \
  "$(jq_ "$TMP/run1.json" mismatch)" "null"
check "largest tangle covers 10 of 13 own modules" "$(jq_ "$TMP/run1.json" largest_tangle)" "10"
check "order lists all 13 own modules" \
  "$("$PY" -c 'import json;print(len(json.load(open("'"$TMP/run1.json"'"))["order"]))')" "13"

echo "== every back edge carries a positive weight and a non-empty kinds map =="
"$PY" -c '
import json, sys
d = json.load(open(sys.argv[1]))
edges = d["back_edges_list"]
if not edges:
    print("no back edges in back_edges_list", file=sys.stderr); sys.exit(1)
bad = [e for e in edges if not (isinstance(e.get("weight"), (int, float)) and e["weight"] > 0
                                 and isinstance(e.get("kinds"), dict) and e["kinds"])]
if bad:
    print("back edges missing weight/kinds: %r" % bad, file=sys.stderr); sys.exit(1)
print(len(edges))
' "$TMP/run1.json" >"$TMP/nedges.txt" 2>"$TMP/nedges.err"
if [ $? -eq 0 ]; then
  ok "every back edge in back_edges_list ($(cat "$TMP/nedges.txt") of them) has weight>0 and non-empty kinds"
else
  bad "every back edge in back_edges_list has weight>0 and non-empty kinds" "$(cat "$TMP/nedges.err")"
fi
check "back_edges count matches back_edges_list length" \
  "$(jq_ "$TMP/run1.json" back_edges)" \
  "$("$PY" -c 'import json;print(len(json.load(open("'"$TMP/run1.json"'"))["back_edges_list"]))')"

echo "== stable across two runs on the same facts =="
bash "$ALM" --facts "$FIX/facts" --json >"$TMP/run2.json" 2>"$TMP/run2.err"; RC=$?
check "run 2 exits 0" "$RC" "0"
STRIP='import json,sys
d = json.load(open(sys.argv[1]))
for k in ("generated",):
    d.pop(k, None)
print(json.dumps(d, sort_keys=True))'
"$PY" -c "$STRIP" "$TMP/run1.json" >"$TMP/run1.norm"
"$PY" -c "$STRIP" "$TMP/run2.json" >"$TMP/run2.norm"
if diff -q "$TMP/run1.norm" "$TMP/run2.norm" >/dev/null 2>&1; then
  ok "two runs on the same facts produce byte-identical output (generated timestamp excluded)"
else
  bad "two runs on the same facts produce byte-identical output" "$(diff "$TMP/run1.norm" "$TMP/run2.norm" | head -5)"
fi
check "order is stable across the two runs" \
  "$(jq_ "$TMP/run1.json" order)" "$(jq_ "$TMP/run2.json" order)"

echo "== degrades =="
mkdir -p "$TMP/no-deps"
bash "$ALM" --facts "$TMP/no-deps" --json >/dev/null 2>&1; RC=$?
check "no dependencies.json: exit 2" "$RC" "2"

bash "$ALM" --facts "$TMP/no-such-dir-at-all" --json >/dev/null 2>&1; RC=$?
check "facts directory does not exist: exit 2" "$RC" "2"

mkdir -p "$TMP/deps-only"
cp "$FIX/facts/dependencies.json" "$TMP/deps-only/dependencies.json"
bash "$ALM" --facts "$TMP/deps-only" -o "$TMP/deps-only.html" >/dev/null 2>"$TMP/deps-only.err"; RC=$?
check "dependencies.json alone (no inventory/manifest) still renders" "$RC" "0"
[ -f "$TMP/deps-only.html" ] && ok "HTML page written to the -o path" || bad "HTML page written to the -o path" "$(cat "$TMP/deps-only.err")"
case "$(cat "$TMP/deps-only.html" 2>/dev/null)" in
  *"inventory.json is missing"*) ok "missing inventory.json is named on the page, not swallowed" ;;
  *) bad "missing inventory.json is named on the page, not swallowed" ;;
esac
case "$(cat "$TMP/deps-only.html" 2>/dev/null)" in
  *"manifest.json is missing"*) ok "missing manifest.json is named on the page, not swallowed" ;;
  *) bad "missing manifest.json is named on the page, not swallowed" ;;
esac

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
