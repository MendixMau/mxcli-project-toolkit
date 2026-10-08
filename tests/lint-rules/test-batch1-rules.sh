#!/usr/bin/env bash
# test-batch1-rules.sh -- unit tests for lint-rules/err001_error_swallowed.star and
# lint-rules/loop001_expensive_action_in_loop.star, run under the real Go Starlark
# interpreter with the mxcli builtins mocked from JSON (tests/lint-rules/starrun).
#
# IMPORTANT: every fixture in tests/lint-rules/fixtures/ is a HAND-WRITTEN unit fixture that
# encodes the catalog projection AS READ FROM THE MXCLI SOURCE (error_handling_type values
# from sdk/microflows/error_handling.go, loop_depth / retrieve_source from the 0.25.0
# catalog builder). It is not captured tool output. These tests prove the rule logic and the
# self-checks; they do NOT prove the vocabulary matches a real model. That is what the field
# probe in each rule's header is for.
#
# Needs `go` on PATH. A missing toolchain is a FAILURE (exit 1), never a quiet skip.
# Keep bash-3.2 compatible.
# Usage: tests/lint-rules/test-batch1-rules.sh      Exit 0 only if every assertion holds.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TK="$(cd "$HERE/../.." && pwd)"
FX="$HERE/fixtures"
R1="$TK/lint-rules/err001_error_swallowed.star"
R2="$TK/lint-rules/loop001_expensive_action_in_loop.star"

if ! command -v go >/dev/null 2>&1; then
  echo "FAIL go toolchain not found; these tests cannot run (NOT a pass)."
  echo "     Install Go (https://go.dev/dl/, or: brew install go / apt install golang) and re-run."
  exit 1
fi
# shellcheck source=../../bin/lib/portable.sh
. "$TK/bin/lib/portable.sh"
require_py   # sets $PY or exits 2 with an actionable message

W=$(mktemp -d "${TMPDIR:-/tmp}/b1rules.XXXXXX")
trap 'rm -rf "$W"' EXIT
PASS=0; FAILED=0
ok(){ printf '  PASS %s\n' "$1"; PASS=$((PASS+1)); }
no(){ printf '  FAIL %s\n' "$1"; FAILED=$((FAILED+1)); }

cd "$TK" || exit 1
OUT="$W/out.json"; ERR="$W/err.txt"; RC=0

BIN="$W/starrun"
if ! (cd "$HERE/starrun" && GOFLAGS=-mod=mod go build -o "$BIN" . 2>"$ERR"); then
  echo "FAIL could not build tests/lint-rules/starrun: $(head -c 400 "$ERR")"; exit 1
fi

# run RULE FIXTURE [STRIP]  -> OUT holds stdout, RC the exit code
run(){
  local rule="$1" fix="$2" strip="${3:-}"
  if [ -n "$strip" ]; then
    "$BIN" -rule "$rule" -fixture "$FX/$fix.json" -strip-fields "$strip" >"$OUT" 2>"$ERR"
  else
    "$BIN" -rule "$rule" -fixture "$FX/$fix.json" >"$OUT" 2>"$ERR"
  fi
  RC=$?
}

# check LABEL PY-EXPR : v is the parsed violation list; the expression must be truthy.
check(){
  local label="$1" expr="$2"
  if [ "$RC" -ne 0 ]; then no "$label (harness exit $RC: $(head -c 300 "$ERR"))"; return; fi
  if "$PY" - "$OUT" "$expr" <<'PY'
import json, sys
v = json.load(open(sys.argv[1]))
sys.exit(0 if eval(sys.argv[2]) else 1)
PY
  then ok "$label"; else no "$label (got: $(head -c 400 "$OUT"))"; fi
}

echo "== ERR001 =="
run "$R1" err001-a-continue-nolog
check "a Continue, no log -> 1 finding naming the activity" 'len(v)==1 and "1 activity (" in v[0]["message"] and "Delete order" in v[0]["message"] and "swallowed" in v[0]["message"]'
run "$R1" err001-b-continue-log
check "b Continue + Log message -> 0 findings" 'len(v)==0'
run "$R1" err001-c-custom-raise
check "c Custom + error end event -> 0 findings" 'len(v)==0'
run "$R1" err001-d-handler-call
check "d CustomWithoutRollBack + call to SUB_LogError -> 0 findings" 'len(v)==0'
run "$R1" err001-e-rollback-abort
check "e Rollback / Abort / unset only -> 0 findings" 'len(v)==0'
run "$R1" err001-f-system
check "f System + Administration swallow -> 0 findings, no self-check" 'len(v)==0'
run "$R1" err001-g-rule-type
check "g RULE-type flow swallows -> 0 findings" 'len(v)==0'
run "$R1" err001-a-continue-nolog "error_handling_type"
check "h stripped error_handling_type -> 1 _rule finding mentioning 0.25.0" 'len(v)==1 and v[0]["module"]=="_rule" and "0.25.0" in v[0]["message"]'
run "$R1" err001-i-no-activities
check "i 2 flows, no activities -> 1 _rule finding 'not one activity'" 'len(v)==1 and v[0]["module"]=="_rule" and "not one activity" in v[0]["message"]'
run "$R1" err001-j-twenty-empty
check "j 20 activities, all handling empty -> 1 _rule finding 'none carries'" 'len(v)==1 and v[0]["module"]=="_rule" and "none carries" in v[0]["message"]'
run "$R1" err001-k-nested
check "k Continue inside a loop: logged -> clean, unlogged -> 1 finding at the flow" 'len(v)==1 and v[0]["document_name"]=="Sales.ACT_LoopSwallow" and v[0]["document_type"]=="Microflow" and v[0]["module"]=="Sales"'
run "$R1" err001-l-two-swallowing
check "l nanoflow, Continue + CustomWithoutRollBack -> '2 activities' naming both" 'len(v)==1 and "2 activities" in v[0]["message"] and "Commit" in v[0]["message"] and "Call sync" in v[0]["message"]'
run "$R1" err001-m-handler-name-mismatch
check "m call to SUB_Logistics is not a handler -> 1 finding" 'len(v)==1 and v[0]["document_name"]=="Sales.ACT_Sync"'
run "$R1" err001-n-self-ref-handler
check "n a handler-named flow calling itself does not vouch for itself -> 1 finding" 'len(v)==1'

echo "== LOOP001 =="
run "$R2" loop001-a-db-retrieve
check "a database retrieve at depth 1 -> 1 finding '(database retrieve)'" 'len(v)==1 and "1 per-row call inside" in v[0]["message"] and "Find customer" in v[0]["message"] and "(database retrieve)" in v[0]["message"]'
run "$R2" loop001-b-assoc-retrieve
check "b association retrieve in loop -> 0 findings" 'len(v)==0'
run "$R2" loop001-c-delete-depth2
check "c delete two loops down -> 1 finding '(delete)'" 'len(v)==1 and "(delete)" in v[0]["message"]'
run "$R2" loop001-d-top-level-retrieve
check "d database retrieve before the loop -> 0 findings" 'len(v)==0'
run "$R2" loop001-e-rest-java-external
check "e REST + Java + external in loop -> '3 per-row calls' with all three labels" 'len(v)==1 and "3 per-row calls" in v[0]["message"] and "(REST call)" in v[0]["message"] and "(Java action)" in v[0]["message"] and "(external call)" in v[0]["message"]'
run "$R2" loop001-f-cheap-in-loop
check "f microflow call / commit / create / change / split in loop -> 0 findings" 'len(v)==0'
run "$R2" loop001-g-loops-no-body
check "g 2 loops, no body rows -> 1 _rule finding 'not one activity inside'" 'len(v)==1 and v[0]["module"]=="_rule" and "not one activity inside" in v[0]["message"]'
run "$R2" loop001-a-db-retrieve "loop_depth"
check "h stripped loop_depth -> 1 _rule finding mentioning 0.25.0" 'len(v)==1 and v[0]["module"]=="_rule" and "0.25.0" in v[0]["message"]'
run "$R2" loop001-i-no-loops
check "i expensive actions but no loop -> 0 findings, no self-check" 'len(v)==0'
run "$R2" loop001-j-system
check "j System module + RULE-type loops -> 0 findings" 'len(v)==0'
run "$R2" loop001-k-unknown-source
check "k retrieve with unknown source in loop -> 0 findings (not guessed)" 'len(v)==0'
run "$R2" loop001-l-locations
check "l findings located at each offending flow, clean flow skipped" '
len(v)==2 and sorted((x["module"],x["document_name"],x["document_type"]) for x in v)==[
 ("Billing","Billing.NF_Post","Microflow"),("Sales","Sales.ACT_Import","Microflow")]'
run "$R2" loop001-m-five-offenders
check "m 5 deletes in one loop -> one finding, first 4 named then '...'" 'len(v)==1 and "5 per-row calls" in v[0]["message"] and "D5" in v[0]["message"] and "D6" not in v[0]["message"] and ", ..." in v[0]["message"]'

echo "== performance (synthetic, 3000 flows / 20000 widgets) =="
PF="$W/perf.json"
"$PY" "$HERE/gen-perf-fixture.py" "$PF" >/dev/null || { no "perf fixture generation"; }
TIMEFORMAT='%R'
for pair in "ERR001:$R1" "LOOP001:$R2"; do
  nm="${pair%%:*}"; rule="${pair#*:}"
  { time "$BIN" -rule "$rule" -fixture "$PF" >"$W/perf-out.json" 2>"$W/perf-err.txt"; } 2>"$W/time.txt"
  rc=$?
  secs=$(tail -n 1 "$W/time.txt")
  if [ "$rc" -eq 0 ] && awk -v t="$secs" 'BEGIN{exit !(t+0 < 60)}'; then
    ok "$nm perf run exit 0 in ${secs}s (limit 60s)"
  else
    no "$nm perf run rc=$rc in ${secs}s (limit 60s): $(head -c 300 "$W/perf-err.txt")"
  fi
done

echo
echo "passed: $PASS  failed: $FAILED"
[ "$FAILED" -eq 0 ]
