#!/bin/bash
# test-app-report.sh — pin the app-analysis instrument's parser and the dossier renderer.
#
# Runs with no mxcli and no .mpr: the parser is exercised through `app-facts.sh --parse-only`
# on captured MDL under fixtures/app-analysis/facts/mdl, and the renderer on the captured
# facts plus a deliberately imperfect dossier. What is worth pinning:
#
#   1. POSITIVE CONTROLS. A loop body with a database retrieve, a commit, a delete, a REST call,
#      a microflow call and a nested loop must produce every one of those facts, with line
#      numbers that point into the MDL. A parser that finds nothing on this file is blind.
#   2. NEGATIVE CONTROL. A loop that only changes objects in memory, with a retrieve BEFORE it
#      and a commit AFTER it, must produce an empty in_loop. Otherwise every loop is a finding
#      and the section gets switched off, which is how lint died once already.
#   3. MISMATCH DIRECTION. parsed > catalog is normal (the catalog holds top-level activities
#      only, verified 2026-09-15); parsed < catalog is the only mismatch worth listing.
#   4. SCHEDULED REACHABILITY travels into the record.
#   5. RENDERER VERDICTS: instrument fault beats a dossier pass; a missing dossier section is
#      fault; no dossier at all is manual; no manifest is exit 2.
#   6. TRANSACTION CONTROL inside a loop is recorded even though it is a Java call.
#
# Usage: bash test-app-report.sh [path-to-app-report.sh]

set -u

TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
AR="${1:-$TOOLKIT/bin/app-report.sh}"
AF="$TOOLKIT/project-bin/app-facts.sh"
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
# Path segments are "/"-separated (not "."): several fixture keys (qualified microflow names)
# contain literal dots, so "." cannot double as both a path separator and part of a key.
jq_()  { "$PY" -c 'import json,sys; d=json.load(open(sys.argv[1]))
for k in sys.argv[2].split("/"):
    d = d[int(k)] if isinstance(d, list) else d.get(k, "MISSING")
    if d == "MISSING": break
print(json.dumps(d) if isinstance(d,(dict,list)) else d)' "$1" "$2"; }

echo "== parser (app-facts.sh --parse-only) =="
cp -R "$FIX/facts" "$TMP/facts"
bash "$AF" --parse-only "$TMP/facts" >/dev/null 2>"$TMP/parse.err"; RC=$?
check "parse-only exits 0" "$RC" "0"
L="$TMP/facts/loops.json"
[ -f "$L" ] && ok "loops.json written" || { bad "loops.json written" "$(cat "$TMP/parse.err")"; exit 1; }
check "five MDL files parsed" "$(jq_ "$L" _meta/parsed)" "5"
check "parsed > catalog counted as catalog undercount, not mismatch" "$(jq_ "$L" _meta/catalog_undercount)" "1"

W="microflows/Orders.SUB_DrainQueue"
check "while loop: counted as a loop"                "$(jq_ "$L" "$W/loops_parsed")" "1"
check "while loop: RETRIEVE_DB inside counted"       "$(jq_ "$L" "$W/in_loop/RETRIEVE_DB")" "1"
check "while loop: change ... commit inside counted" "$(jq_ "$L" "$W/in_loop/COMMIT")" "1"
check "while loop: microflow call inside counted"    "$(jq_ "$L" "$W/in_loop/MICROFLOW_CALL")" "1"
check "while loop: not a parse mismatch"             "$("$PY" -c 'import json;print(sum(1 for m in json.load(open("'"$L"'"))["_meta"]["parse_mismatch"] if m["microflow"]=="Orders.SUB_DrainQueue"))')" "0"

S="microflows/Orders.SUB_SyncOrderLines"
check "positive: RETRIEVE_DB in loop"      "$(jq_ "$L" "$S/in_loop/RETRIEVE_DB")" "1"
check "positive: RETRIEVE_ASSOC in loop"   "$(jq_ "$L" "$S/in_loop/RETRIEVE_ASSOC")" "1"
check "positive: REST_CALL in loop"        "$(jq_ "$L" "$S/in_loop/REST_CALL")" "1"
check "positive: COMMIT in loop"           "$(jq_ "$L" "$S/in_loop/COMMIT")" "1"
check "positive: DELETE in loop"           "$(jq_ "$L" "$S/in_loop/DELETE")" "1"
check "positive: MICROFLOW_CALL in loop"   "$(jq_ "$L" "$S/in_loop/MICROFLOW_CALL")" "1"
check "positive: nested loop recorded"     "$(jq_ "$L" "$S/nested_loop_lines")" "[20]"
check "positive: RETRIEVE_DB line points into the MDL" "$(jq_ "$L" "$S/in_loop_lines/RETRIEVE_DB")" "[13]"
check "positive: two loops parsed, catalog one, NOT a mismatch" "$(jq_ "$L" "$S/loops_parsed")" "2"
check "positive: scheduled reachability travels" "$(jq_ "$L" "$S/reachable_from_scheduled_events")" '["Orders.SE_NightlySync"]'
check "scheduled: enabled list carried"  "$(jq_ "$L" "$S/reachable_from_scheduled_events_enabled")" '["Orders.SE_NightlySync"]'
check "scheduled: disabled-only reach is separated" "$(jq_ "$L" "microflows/Orders.SUB_TxPerItem/reachable_from_scheduled_events_enabled")" '[]'
check "scheduled: disabled-only reach still listed"  "$(jq_ "$L" "microflows/Orders.SUB_TxPerItem/reachable_from_scheduled_events_disabled")" '["Orders.SE_NightlySync"]'
check "the commit AFTER the loop is not counted (exactly one COMMIT)" "$(jq_ "$L" "$S/in_loop/COMMIT")" "1"

N="microflows/Orders.SUB_MarkSent"
check "negative: in-memory-only loop has empty in_loop" "$(jq_ "$L" "$N/in_loop")" "{}"
check "negative: retrieve before the loop not counted"  "$(jq_ "$L" "$N/in_loop/RETRIEVE_DB")" "MISSING"

check "mismatch listed only when parsed < catalog" "$(jq_ "$L" _meta/parse_mismatch/0/microflow)" "Orders.SUB_Truncated"
check "exactly one mismatch (nested loop is not one)" "$("$PY" -c 'import json;print(len(json.load(open("'"$L"'"))["_meta"]["parse_mismatch"]))')" "1"

T="microflows/Orders.SUB_TxPerItem"
check "transaction Java actions in a loop are recorded" "$(jq_ "$L" "$T/transaction_action_lines")" "[7, 9]"
check "change ... commit inside loop counts as COMMIT"  "$(jq_ "$L" "$T/in_loop/COMMIT")" "1"
check "Java calls in loop counted"                      "$(jq_ "$L" "$T/in_loop/JAVA_CALL")" "2"

echo "== renderer (app-report.sh) =="
OUT="$TMP/report.json"
bash "$AR" --facts "$TMP/facts" --dossier "$FIX/app-dossier.md" --json > "$OUT" 2>"$TMP/r.err"; RC=$?
check "renders with dossier, exit 0" "$RC" "0"
check "dossier fail carries through"               "$(jq_ "$OUT" 'verdicts/Dependency shape')" "fail"
check "instrument fault beats a dossier pass"      "$(jq_ "$OUT" 'verdicts/Security posture')" "fault"
check "dossier pass on a collected section passes" "$(jq_ "$OUT" 'verdicts/Flow risk patterns')" "pass"
check "missing dossier section is fault"           "$(jq_ "$OUT" 'verdicts/Dead elements')" "fault"
check "skipped stays skipped"                      "$(jq_ "$OUT" 'verdicts/Lint baseline')" "skipped"
check "dispositions present -> manual"             "$(jq_ "$OUT" 'verdicts/Dispositions')" "manual"
check "loop shape counts REST calls from facts"    "$(jq_ "$OUT" loop_shape/with_rest_call)" "1"
check "loop shape counts scheduled-reachable"      "$(jq_ "$OUT" loop_shape/scheduled_reachable)" "2"
check "loop shape counts enabled-reachable separately" "$(jq_ "$OUT" loop_shape/scheduled_reachable_enabled)" "1"
check "loop shape: microflow-call-only excludes DB work and Java" "$(jq_ "$OUT" loop_shape/with_microflow_call_only)" "0"
check "loop shape carries catalog undercount"      "$(jq_ "$OUT" loop_shape/catalog_undercount)" "1"
check "numbered, bold verdict cell (2. Inventory / **pass**) is read" "$(jq_ "$OUT" 'verdicts/Inventory')" "pass"

bash "$AR" --facts "$TMP/facts" --dossier "$TMP/none.md" --json > "$OUT" 2>/dev/null; RC=$?
check "no dossier: exit 0" "$RC" "0"
check "no dossier: sections are manual, not pass"  "$(jq_ "$OUT" 'verdicts/Dependency shape')" "manual"
check "no dossier: instrument fault still fault"   "$(jq_ "$OUT" 'verdicts/Security posture')" "fault"

bash "$AR" --facts "$TMP/facts" --dossier "$FIX/app-dossier.md" -o "$TMP/r.html" >/dev/null 2>&1; RC=$?
check "HTML render exits 0" "$RC" "0"
H="$(cat "$TMP/r.html" 2>/dev/null)"
case "$H" in *"Orders.SUB_SyncOrderLines"*) ok "HTML lists the loop microflow" ;; *) bad "HTML lists the loop microflow" ;; esac
case "$H" in *"DEP-TANGLE-01"*) ok "HTML carries dossier text" ;; *) bad "HTML carries dossier text" ;; esac
case "$H" in *'has no "Dead elements" section'*) ok "HTML says the missing section is missing" ;; *) bad "HTML says the missing section is missing" ;; esac

mkdir -p "$TMP/empty"
bash "$AR" --facts "$TMP/empty" --json >/dev/null 2>&1; RC=$?
check "no manifest: exit 2, never a page" "$RC" "2"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
