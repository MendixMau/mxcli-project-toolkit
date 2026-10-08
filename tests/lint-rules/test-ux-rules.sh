#!/usr/bin/env bash
# test-ux-rules.sh -- unit tests for lint-rules/ux001_confirm_before_destructive.star and
# lint-rules/ux002_decisions_captioned.star, run under the real Go Starlark interpreter with
# the mxcli builtins mocked from JSON (tests/lint-rules/starrun).
#
# IMPORTANT: every fixture in tests/lint-rules/fixtures/ is a HAND-WRITTEN unit fixture that
# encodes the catalog projection AS READ FROM THE MXCLI SOURCE. It is not captured tool
# output. These tests prove the rule logic and the self-checks; they do NOT prove the
# vocabulary (action_type strings, activity_type strings) matches a real model. That is
# what the field probe in each rule's header is for.
#
# Needs `go` on PATH. A missing toolchain is a FAILURE (exit 1), never a quiet skip: a rule
# test that did not run must not read as a rule test that passed.
#
# Keep bash-3.2 compatible.
# Usage: tests/lint-rules/test-ux-rules.sh      Exit 0 only if every assertion holds.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TK="$(cd "$HERE/../.." && pwd)"
FX="$HERE/fixtures"
R1="$TK/lint-rules/ux001_confirm_before_destructive.star"
R2="$TK/lint-rules/ux002_decisions_captioned.star"

if ! command -v go >/dev/null 2>&1; then
  echo "FAIL go toolchain not found; these tests cannot run (NOT a pass)."
  echo "     Install Go (https://go.dev/dl/, or: brew install go / apt install golang) and re-run."
  exit 1
fi
command -v python3 >/dev/null 2>&1 || { echo "FAIL python3 not found"; exit 1; }

W=$(mktemp -d "${TMPDIR:-/tmp}/uxrules.XXXXXX")
trap 'rm -rf "$W"' EXIT
PASS=0; FAILED=0
ok(){ printf '  PASS %s\n' "$1"; PASS=$((PASS+1)); }
no(){ printf '  FAIL %s\n' "$1"; FAILED=$((FAILED+1)); }

cd "$TK" || exit 1
OUT="$W/out.json"; ERR="$W/err.txt"; RC=0

# Build the harness once (its go.mod lives in its own directory, so `go run ./tests/...`
# from the repo root does not resolve). One build also keeps compile time out of the
# perf numbers below.
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
  if python3 - "$OUT" "$expr" <<'PY'
import json, sys
v = json.load(open(sys.argv[1]))
sys.exit(0 if eval(sys.argv[2]) else 1)
PY
  then ok "$label"; else no "$label (got: $(head -c 400 "$OUT"))"; fi
}

echo "== UX001 =="
run "$R1" ux001-a-direct-delete
check "a direct delete button -> 1 finding 'deletes directly'" 'len(v)==1 and "deletes directly" in v[0]["message"]'
run "$R1" ux001-b-confirmed
check "b confirmed flow button -> 0 findings" 'len(v)==0'
run "$R1" ux001-c-flow-deletes
check "c unconfirmed, flow deletes -> 1 finding 'deletes objects'" 'len(v)==1 and "deletes objects" in v[0]["message"]'
run "$R1" ux001-d-depth2
check "d delete reached at call depth 2 -> 1 finding" 'len(v)==1'
run "$R1" ux001-e-depth4
check "e delete only at depth 4 (MAX_CALL_DEPTH=3) -> 0 findings" 'len(v)==0'
run "$R1" ux001-f-name-irreversible
check "f ACT_Order_Approve -> 1 finding 'irreversible'" 'len(v)==1 and "irreversible" in v[0]["message"]'
run "$R1" ux001-g-name-camelcase
check "g ACT_ShowApprovedOrders -> 0 findings" 'len(v)==0'
run "$R1" ux001-h-nanoflow
check "h nanoflow button to ACT_Reject -> 1 finding" 'len(v)==1'
run "$R1" ux001-i-system-module
check "i System-module delete (plus one Sales show-page button) -> 0 findings" 'len(v)==0'
run "$R1" ux001-i2-system-only
check "i2 System-only widgets -> only the 'no widgets' self-check" 'len(v)==1 and v[0]["module"]=="_rule" and "no widgets" in v[0]["message"]'
run "$R1" ux001-j-no-flow-actions
check "j show-page button + action-less widget -> 0 findings" 'len(v)==0'
run "$R1" ux001-k-snippet
check "k button on SNIPPET -> document_type Snippet" 'len(v)==1 and v[0]["document_type"]=="Snippet"'
run "$R1" ux001-l-cycle
check "l call cycle A->B->A terminates, 0 findings" 'len(v)==0'
run "$R1" ux001-m-strip "action_type,has_confirmation"
check "m stripped projection -> 1 _rule finding mentioning 0.25.0" 'len(v)==1 and v[0]["module"]=="_rule" and "0.25.0" in v[0]["message"]'
run "$R1" ux001-n-empty
check "n empty widgets -> 1 _rule finding 'no widgets'" 'len(v)==1 and v[0]["module"]=="_rule" and "no widgets" in v[0]["message"]'
run "$R1" ux001-o-no-action-types
check "o every action_type empty -> 1 _rule finding" 'len(v)==1 and v[0]["module"]=="_rule" and "not one reports an action type" in v[0]["message"]'
run "$R1" ux001-p-locations
check "p findings located at the widget's module and container" '
len(v)==3 and sorted((x["module"],x["document_name"],x["document_type"]) for x in v)==[
 ("Billing","Billing.Invoice_Edit","Page"),("Orders","Orders.Order_Overview","Page"),("Sales","Sales.Quote_View","Page")]'

echo "== UX002 =="
run "$R2" ux002-a-two-bare
check "a two auto-captioned decisions -> 1 finding '2 decision(s)'" 'len(v)==1 and "2 decision(s)" in v[0]["message"]'
run "$R2" ux002-b-captioned
check "b caption 'Already approved?' -> 0 findings" 'len(v)==0'
run "$R2" ux002-c-blank-caption
check "c blank caption -> 1 finding" 'len(v)==1'
run "$R2" ux002-d-eight
check "d 8 activities, no annotation/description -> '8 top-level activities'" 'len(v)==1 and "8 top-level activities" in v[0]["message"]'
run "$R2" ux002-e-seven
check "e 7 activities -> 0 findings" 'len(v)==0'
run "$R2" ux002-f-eight-annotated
check "f 8 activities incl. Annotation -> 0 findings" 'len(v)==0'
run "$R2" ux002-g-eight-described
check "g 8 activities + description -> 0 findings" 'len(v)==0'
run "$R2" ux002-h-rule
check "h RULE with bare decisions -> 0 findings" 'len(v)==0'
run "$R2" ux002-i-administration
check "i Administration flow -> 0 findings" 'len(v)==0'
run "$R2" ux002-j-both-legs
check "j 9 activities + 3 bare decisions -> 2 findings at the flow" '
len(v)==2 and all(x["document_name"]=="Sales.ACT_Big" and x["document_type"]=="Microflow" for x in v)'
run "$R2" ux002-k-strip "auto_generate_caption"
check "k stripped projection -> 1 _rule finding mentioning 0.25.0" 'len(v)==1 and v[0]["module"]=="_rule" and "0.25.0" in v[0]["message"]'
run "$R2" ux002-l-no-activities
check "l 3 flows, no activities -> 1 _rule finding 'checked NOTHING'" 'len(v)==1 and v[0]["module"]=="_rule" and "checked NOTHING" in v[0]["message"]'
run "$R2" ux002-m-no-microflows
check "m zero microflows -> 0 findings" 'len(v)==0'
run "$R2" ux002-n-events-counted
check "n 8 activities between StartEvent and EndEvent -> 1 finding saying 8, not 10" 'len(v)==1 and "has 8 top-level" in v[0]["message"]'
run "$R2" ux002-o-events-not-counted
check "o 7 activities + start/end events -> 0 findings (events are not activities)" 'len(v)==0'
run "$R2" ux002-p-strip-no-decision auto_generate_caption
check "p stripped projection, flow with no decision -> still 1 _rule finding" 'len(v)==1 and v[0]["module"]=="_rule" and "0.25.0" in v[0]["message"]'

echo "== performance (synthetic, 3000 flows / 20000 widgets) =="
PF="$W/perf.json"
python3 "$HERE/gen-perf-fixture.py" "$PF" >/dev/null || { no "perf fixture generation"; }
TIMEFORMAT='%R'
for pair in "UX001:$R1" "UX002:$R2"; do
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
