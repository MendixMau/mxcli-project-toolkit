#!/bin/bash
# test-cut-score.sh — pin cut-score.sh against a fixture with a KNOWN right answer.
#
# Runs with no mxcli and no .mpr: entirely against fixtures/cut-score/ (captured 2026-10-12 from a
# four-module Mendix 10.24 app built by MDL with a planted structure — see CAPTURE.txt there). The
# planted answer for --cut "Core,Util|Orders|Billing|Reporting" is what is worth pinning:
#
#   1. THE TANGLE IS A BLOCKER. Orders.ACT_Order_Close calls Billing.ACT_Invoice_Create and
#      Billing.ACT_Invoice_Create calls Orders.SUB_Order_GetLines. At partition level that is one
#      bidirectional call pair; both call rows must read class=blocker and BOTH partitions must
#      read verdict=blocked — a tangle has no side.
#   2. THE AGGREGATE IS FOUND FROM THE CATALOG, AND SAID TO BE MISSING WITHOUT IT.
#      Reporting.CAL_Invoice_Totals retrieves Billing.Invoice and runs COUNT and SUM over it.
#      dependencies.json cannot show that; the catalog's activities_data can. With the catalog the
#      Reporting->Billing retrieve row carries aggregate "yes (...)" and Reporting is costly; with
#      --catalog pointing nowhere every row must read "NOT DETECTED" and the gap must be named,
#      never left blank.
#   3. ASSOCIATION-ONLY IS ACCEPTABLE, NOTHING-OUT IS CLEAN. Orders->Core is associate+parameter
#      only (Core owns the data); those rows are class=acceptable. Core+Util has no outgoing
#      crossing edge and must be clean even though four edges point INTO it.
#   4. THE DENOMINATOR IS PRINTED. 7 own edges carrying 12 refs; all 7 cross on this cut. The
#      rows must cover every crossing module edge, and the count must say "7 of 7".
#   5. NOTHING IS INFERRED. MyFirstModule (the scaffold) is an own module the cut does not name:
#      it lands in "_unassigned" and is reported as a gap, never folded into a neighbour. A module
#      named in the cut that does not exist is a gap too.
#   6. THE DEFAULT CUT COMES FROM THE LAYER MAP. With no --cut, levels_by_module of
#      app-layer-map.json gives four partitions L0..L3 and the same blocker; without that file and
#      without --cut the script exits 2 rather than guessing.
#   7. DETERMINISTIC. Two runs on the same inputs are byte-identical bar the timestamp.
#
# Usage: bash test-cut-score.sh [path-to-cut-score.sh]

set -u

TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
CS="${1:-$TOOLKIT/bin/cut-score.sh}"
FIX="$TOOLKIT/tests/wave2/fixtures/cut-score"
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
# rows_() FILE FROM TO KIND FIELD -> the field of that one row
rows_(){ "$PY" -c 'import json,sys; d=json.load(open(sys.argv[1]))
r=[r for r in d["rows"] if r["from"]==sys.argv[2] and r["to"]==sys.argv[3] and r["kind"]==sys.argv[4]]
print(r[0][sys.argv[5]] if len(r)==1 else "ROWS=%d" % len(r))' "$@"; }

CUT="Core,Util|Orders|Billing|Reporting"

echo "== cut-score.sh --json, four-way cut, with catalog =="
bash "$CS" --facts "$FIX/facts" --catalog "$FIX/catalog.db" --cut "$CUT" --json >"$TMP/run1.json" 2>"$TMP/run1.err"; RC=$?
check "exits 0" "$RC" "0"
[ -s "$TMP/run1.json" ] || { bad "produced JSON" "$(cat "$TMP/run1.err")"; echo; echo "$PASS passed, $FAIL failed"; exit 1; }

echo "== 1. the Orders<->Billing call tangle is a blocker on both sides =="
check "one bidirectional partition pair" \
  "$("$PY" -c 'import json;print(len(json.load(open("'"$TMP/run1.json"'"))["bidirectional_partition_pairs"]))')" "1"
check "pair is Billing<->Orders" "$(jq_ "$TMP/run1.json" bidirectional_partition_pairs/0/a)-$(jq_ "$TMP/run1.json" bidirectional_partition_pairs/0/b)" "Billing-Orders"
check "Orders -> Billing call row is class blocker" "$(rows_ "$TMP/run1.json" Orders Billing call class)" "blocker"
check "Billing -> Orders call row is class blocker" "$(rows_ "$TMP/run1.json" Billing Orders call class)" "blocker"
check "Orders verdict blocked"  "$(jq_ "$TMP/run1.json" partitions/Orders/verdict)"  "blocked"
check "Billing verdict blocked" "$(jq_ "$TMP/run1.json" partitions/Billing/verdict)" "blocked"
check "overall verdict blocked" "$(jq_ "$TMP/run1.json" verdict)" "blocked"
check "Orders lists both tangle edges as blockers" \
  "$("$PY" -c 'import json;print(len(json.load(open("'"$TMP/run1.json"'"))["partitions"]["Orders"]["blockers"]))')" "2"

echo "== 2. the Reporting->Billing aggregate is detected from the catalog =="
check "aggregate status DETECTED" "$(jq_ "$TMP/run1.json" aggregate/status)" "DETECTED"
check "one aggregate hit" "$("$PY" -c 'import json;print(len(json.load(open("'"$TMP/run1.json"'"))["aggregate"]["hits"]))')" "1"
check "hit names Reporting.CAL_Invoice_Totals over Billing.Invoice" \
  "$(jq_ "$TMP/run1.json" aggregate/hits/0/microflow)|$(jq_ "$TMP/run1.json" aggregate/hits/0/entity)" \
  "Reporting.CAL_Invoice_Totals|Billing.Invoice"
check "hit counts the two aggregates (COUNT + SUM)" "$(jq_ "$TMP/run1.json" aggregate/hits/0/aggregates)" "2"
case "$(rows_ "$TMP/run1.json" Reporting Billing retrieve aggregate)" in
  "yes ("*) ok "Reporting -> Billing retrieve row carries the aggregate flag" ;;
  *) bad "Reporting -> Billing retrieve row carries the aggregate flag" "$(rows_ "$TMP/run1.json" Reporting Billing retrieve aggregate)" ;;
esac
check "that row is class costly" "$(rows_ "$TMP/run1.json" Reporting Billing retrieve class)" "costly"
check "Reporting verdict costly (aggregate, no blocker)" "$(jq_ "$TMP/run1.json" partitions/Reporting/verdict)" "costly"

echo "== 2b. without a catalog the aggregate column says NOT DETECTED, never blank =="
bash "$CS" --facts "$FIX/facts" --catalog "$TMP/no-such-catalog.db" --cut "$CUT" --json >"$TMP/nocat.json" 2>/dev/null; RC=$?
check "exits 0 without a catalog" "$RC" "0"
check "aggregate status NOT DETECTED" "$(jq_ "$TMP/nocat.json" aggregate/status)" "NOT DETECTED"
case "$(jq_ "$TMP/nocat.json" aggregate/reason)" in
  *"no catalog at"*) ok "reason names the missing catalog" ;;
  *) bad "reason names the missing catalog" "$(jq_ "$TMP/nocat.json" aggregate/reason)" ;;
esac
"$PY" -c 'import json,sys
d=json.load(open(sys.argv[1]))
blank=[r for r in d["rows"] if not str(r.get("aggregate","")).startswith("NOT DETECTED")]
sys.exit(1 if blank else 0)' "$TMP/nocat.json" \
  && ok "every row reads NOT DETECTED (none blank, none n/a)" || bad "every row reads NOT DETECTED" "some rows were not marked"
case "$(jq_ "$TMP/nocat.json" gaps)" in
  *"aggregate detection: NOT DETECTED"*) ok "the gap is listed in gaps" ;;
  *) bad "the gap is listed in gaps" "$(jq_ "$TMP/nocat.json" gaps)" ;;
esac
check "the verdict still finds the blocker without a catalog" "$(jq_ "$TMP/nocat.json" verdict)" "blocked"

echo "== 2c. the build_mode LABEL is not a gate (master #259: mxcli v0.24+ labels a full catalog 'source') =="
# Copies of the captured catalog with ONLY the label changed / ONLY the activity rows removed.
cp "$FIX/catalog.db" "$TMP/source-label.db"
"$PY" -c 'import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); c.execute("update catalog_meta set Value=? where Key=?", ("source","build_mode")); c.commit()' "$TMP/source-label.db"
bash "$CS" --facts "$FIX/facts" --catalog "$TMP/source-label.db" --cut "$CUT" --json >"$TMP/srclabel.json" 2>/dev/null
check "a catalog labelled 'source' still DETECTS the aggregate" "$(jq_ "$TMP/srclabel.json" aggregate/status)" "DETECTED"
check "the label is recorded as found" "$(jq_ "$TMP/srclabel.json" aggregate/build_mode)" "source"
cp "$FIX/catalog.db" "$TMP/empty-acts.db"
"$PY" -c 'import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); c.execute("delete from activities_data"); c.commit()' "$TMP/empty-acts.db"
bash "$CS" --facts "$FIX/facts" --catalog "$TMP/empty-acts.db" --cut "$CUT" --json >"$TMP/emptyacts.json" 2>/dev/null
check "an empty activities_data reads NOT DETECTED" "$(jq_ "$TMP/emptyacts.json" aggregate/status)" "NOT DETECTED"
case "$(jq_ "$TMP/emptyacts.json" aggregate/reason)" in
  *"activities_data is empty"*) ok "the reason names the empty table" ;;
  *) bad "the reason names the empty table" "$(jq_ "$TMP/emptyacts.json" aggregate/reason)" ;;
esac

echo "== 2d. rows carry the actual reason, not always 'no catalog' (review of #341) =="
check "no catalog: rows read NOT DETECTED (no catalog)" "$(rows_ "$TMP/nocat.json" Reporting Billing retrieve aggregate)" "NOT DETECTED (no catalog)"
check "empty activities_data: rows say so" "$(rows_ "$TMP/emptyacts.json" Reporting Billing retrieve aggregate)" "NOT DETECTED (catalog activities_data is empty)"
printf 'not a database\n' >"$TMP/garbage.db"
bash "$CS" --facts "$FIX/facts" --catalog "$TMP/garbage.db" --cut "$CUT" --json >"$TMP/garbage.json" 2>/dev/null; RC=$?
check "an unreadable catalog: exit 0" "$RC" "0"
check "an unreadable catalog: rows say so" "$(rows_ "$TMP/garbage.json" Reporting Billing retrieve aggregate)" "NOT DETECTED (catalog unreadable)"

echo "== 2e. own modules derived from edges never include a missing endpoint (review of #341) =="
mkdir -p "$TMP/noscope"; cp "$FIX/facts/manifest.json" "$TMP/noscope/"
"$PY" -c 'import json,sys
d=json.load(open(sys.argv[1])); d.pop("scope", None); d["edges"][0].pop("from", None)
json.dump(d, open(sys.argv[2], "w"))' "$FIX/facts/dependencies.json" "$TMP/noscope/dependencies.json"
bash "$CS" --facts "$TMP/noscope" --cut "$CUT" --json >"$TMP/noscope.json" 2>"$TMP/noscope.err"; RC=$?
check "no scope + an edge without 'from': exit 0" "$RC" "0"
case "$(jq_ "$TMP/noscope.json" gaps)" in
  *"derived from the edges"*) ok "the derived module set is named as a gap" ;;
  *) bad "the derived module set is named as a gap" "$(cat "$TMP/noscope.err")" ;;
esac

echo "== 3. association-only is acceptable; nothing-out is clean =="
check "Orders -> Core associate is acceptable" "$(rows_ "$TMP/run1.json" Orders Core associate class)" "acceptable"
check "Orders -> Core associate lane is odata-external-entity" "$(rows_ "$TMP/run1.json" Orders Core associate lane)" "odata-external-entity"
check "Orders -> Core parameter is acceptable" "$(rows_ "$TMP/run1.json" Orders Core parameter class)" "acceptable"
check "Core+Util verdict clean" "$(jq_ "$TMP/run1.json" partitions/Core+Util/verdict)" "clean"
check "Core+Util has 4 edges pointing in" "$(jq_ "$TMP/run1.json" partitions/Core+Util/in_edges)" "4"
check "Core+Util has 0 edges going out" "$(jq_ "$TMP/run1.json" partitions/Core+Util/out_edges)" "0"
check "Orders -> Util call is odata-action-or-rest, costly" \
  "$(rows_ "$TMP/run1.json" Orders Util call lane)/$(rows_ "$TMP/run1.json" Orders Util call class)" "odata-action-or-rest/costly"

echo "== 4. the denominator is printed =="
check "own_edges 7" "$(jq_ "$TMP/run1.json" own_edges)" "7"
check "own_edge_weight 12" "$(jq_ "$TMP/run1.json" own_edge_weight)" "12"
check "crossing_edges 7" "$(jq_ "$TMP/run1.json" crossing_edges)" "7"
case "$(jq_ "$TMP/run1.json" denominator)" in
  "7 of 7 own edges"*"12 of 12 refs") ok "denominator sentence reads '7 of 7 ... 12 of 12'" ;;
  *) bad "denominator sentence" "$(jq_ "$TMP/run1.json" denominator)" ;;
esac
check "rows cover every crossing module edge (distinct from/to pairs)" \
  "$("$PY" -c 'import json;d=json.load(open("'"$TMP/run1.json"'"));print(len({(r["from"],r["to"]) for r in d["rows"]}))')" "7"
check "row weights sum to the crossing weight" \
  "$("$PY" -c 'import json;d=json.load(open("'"$TMP/run1.json"'"));print(sum(r["weight"] for r in d["rows"]))')" \
  "$(jq_ "$TMP/run1.json" crossing_weight)"
check "every row has a lane, cost, class and aggregate field" \
  "$("$PY" -c 'import json;d=json.load(open("'"$TMP/run1.json"'"));print(all(r.get(k) for r in d["rows"] for k in ("lane","cost","class","aggregate","why")))')" "True"
check "business events is listed as excluded" "$(jq_ "$TMP/run1.json" lanes_excluded/0)" "business-events (no Event Broker licence)"

echo "== 5. nothing is inferred =="
check "MyFirstModule lands in _unassigned" "$(jq_ "$TMP/run1.json" partitions/_unassigned/modules)" '["MyFirstModule"]'
case "$(jq_ "$TMP/run1.json" gaps)" in
  *"own modules the cut does not place: MyFirstModule"*) ok "the unplaced module is a named gap" ;;
  *) bad "the unplaced module is a named gap" "$(jq_ "$TMP/run1.json" gaps)" ;;
esac
bash "$CS" --facts "$FIX/facts" --catalog "$FIX/catalog.db" --cut "Core,Util,Nonesuch|Orders|Billing|Reporting" --json >"$TMP/typo.json" 2>/dev/null
case "$(jq_ "$TMP/typo.json" gaps)" in
  *"not an own module"*"Nonesuch"*) ok "a cut naming a module that does not exist is a named gap" ;;
  *) bad "a cut naming a module that does not exist is a named gap" "$(jq_ "$TMP/typo.json" gaps)" ;;
esac
bash "$CS" --facts "$FIX/facts" --cut "Core||Orders" --json >/dev/null 2>&1; RC=$?
check "an empty partition in --cut is exit 2" "$RC" "2"

echo "== 6. the default cut comes from the layer map =="
bash "$CS" --facts "$FIX/facts" --catalog "$FIX/catalog.db" --layer-map "$FIX/app-layer-map.json" --json >"$TMP/default.json" 2>"$TMP/default.err"; RC=$?
check "default cut exits 0" "$RC" "0"
check "four level partitions L0..L3" \
  "$("$PY" -c 'import json;print([c["name"] for c in json.load(open("'"$TMP/default.json"'"))["cut"]])')" "['L0', 'L1', 'L2', 'L3']"
check "L0 holds Core, MyFirstModule, Util" "$(jq_ "$TMP/default.json" partitions/L0/modules)" '["Core", "MyFirstModule", "Util"]'
check "default cut finds the same blocker" "$(jq_ "$TMP/default.json" verdict)" "blocked"
bash "$CS" --facts "$FIX/facts" --layer-map "$TMP/no-such-layer-map.json" --json >/dev/null 2>"$TMP/nolm.err"; RC=$?
check "no --cut and no layer map: exit 2" "$RC" "2"
case "$(cat "$TMP/nolm.err")" in
  *"--cut"*) ok "the refusal says how to supply a cut" ;;
  *) bad "the refusal says how to supply a cut" "$(cat "$TMP/nolm.err")" ;;
esac

echo "== 7. deterministic, and the HTML page is written =="
bash "$CS" --facts "$FIX/facts" --catalog "$FIX/catalog.db" --cut "$CUT" --json >"$TMP/run2.json" 2>/dev/null
STRIP='import json,sys
d = json.load(open(sys.argv[1])); d.pop("generated", None); print(json.dumps(d, sort_keys=True))'
"$PY" -c "$STRIP" "$TMP/run1.json" >"$TMP/run1.norm"; "$PY" -c "$STRIP" "$TMP/run2.json" >"$TMP/run2.norm"
if diff -q "$TMP/run1.norm" "$TMP/run2.norm" >/dev/null 2>&1; then
  ok "two runs are byte-identical (generated excluded)"
else
  bad "two runs are byte-identical" "$(diff "$TMP/run1.norm" "$TMP/run2.norm" | head -5)"
fi
bash "$CS" --facts "$FIX/facts" --catalog "$FIX/catalog.db" --cut "$CUT" -o "$TMP/out/cut-score.html" >"$TMP/html.out" 2>&1; RC=$?
check "HTML run exits 0" "$RC" "0"
[ -f "$TMP/out/cut-score.html" ] && ok "HTML written to the -o path" || bad "HTML written to the -o path" "$(cat "$TMP/html.out")"
[ -f "$TMP/out/cut-score.json" ] && ok "JSON sidecar written beside it" || bad "JSON sidecar written beside it"
case "$(cat "$TMP/out/cut-score.html" 2>/dev/null)" in
  *"7 of 7 own edges"*) ok "the page prints the denominator" ;;
  *) bad "the page prints the denominator" ;;
esac
case "$(cat "$TMP/out/cut-score.html" 2>/dev/null)" in
  *"bidirectional call pair between"*) ok "the page names the blocker" ;;
  *) bad "the page names the blocker" ;;
esac
case "$(cat "$TMP/out/cut-score.html" 2>/dev/null)" in
  *"MyFirstModule"*"_unassigned"*) ok "the page shows the unplaced module as a gap" ;;
  *) bad "the page shows the unplaced module as a gap" ;;
esac
case "$(cat "$TMP/html.out")" in
  *"verdict blocked"*"7 of 7"*) ok "stdout summary carries verdict and denominator" ;;
  *) bad "stdout summary carries verdict and denominator" "$(cat "$TMP/html.out")" ;;
esac

echo "== 8. layouts: the catalog is found beside the .mpr, single-tree and two-tree (synthetic trees) =="
for layout in single two; do
  P="$TMP/proj-$layout"; mkdir -p "$P/analysis/app-facts"
  cp "$FIX/facts/"*.json "$P/analysis/app-facts/"
  if [ "$layout" = single ]; then CDIR="$P/.mxcli"; else CDIR="$P/app/.mxcli"; fi
  mkdir -p "$CDIR"; cp "$FIX/catalog.db" "$CDIR/catalog.db"
  bash "$CS" "$P" --cut "$CUT" --json >"$TMP/layout-$layout.json" 2>/dev/null
  check "$layout-tree: catalog auto-found, aggregate DETECTED" "$(jq_ "$TMP/layout-$layout.json" aggregate/status)" "DETECTED"
  bash "$CS" "$P" --cut "$CUT" >/dev/null 2>&1
  [ -f "$P/analysis/cut-score.html" ] && ok "$layout-tree: default -o is <project>/analysis/cut-score.html" \
    || bad "$layout-tree: default -o is <project>/analysis/cut-score.html"
done

echo "== degrades =="
mkdir -p "$TMP/no-deps"
bash "$CS" --facts "$TMP/no-deps" --cut "$CUT" --json >/dev/null 2>&1; RC=$?
check "no dependencies.json: exit 2" "$RC" "2"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
