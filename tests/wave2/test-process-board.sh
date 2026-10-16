#!/bin/bash
# test-process-board.sh: pin what process-board.js validates, how it anchors questions, what
# `build` writes, and the Stage-3 gate rule that a process board must not be older than its model.
#
# Golden input: tests/wave2/fixtures/process-board/, a synthetic order approval app (one BRD with
# five use cases and four open questions, four wireframes, a PROJECT.md decisions table with two
# ASSUMED rows, a process model and two judged anchors). Its shapes follow the BRD contract
# (useCases, openQuestions, pages) and the wireframe contract (data-mx-page, data-route) the real
# Stage-2 and Stage-3 producers write. Each defect case copies the fixture and changes one thing,
# so a pass means that one defect was seen.
#
# Usage: bash test-process-board.sh [path-to-process-board.js]

set -u

TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
SUT="${1:-$TOOLKIT/project-bin/process-board.js}"
SUT="$(cd "$(dirname "$SUT")" && pwd)/$(basename "$SUT")"
GATE="$TOOLKIT/bin/gate-check.sh"
FIX="$TOOLKIT/tests/wave2/fixtures/process-board"
export MXTK_NO_FETCH=1

PASS=0; FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected '$3', got '$2'"; fi; }
has()  { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "missing '$3' in: $(printf '%s' "$2" | head -c 400)" ;; esac; }
hasnt(){ case "$2" in *"$3"*) bad "$1" "unexpected '$3'" ;; *) ok "$1" ;; esac; }

command -v node >/dev/null 2>&1 || { echo "SKIP: node not on PATH"; exit 0; }

# fresh copy of the golden fixture
fresh() { rm -rf "$TMP/$1"; cp -R "$FIX" "$TMP/$1"; echo "$TMP/$1"; }
# edit a JSON file in place with a JavaScript expression over `j`
jedit() { node -e 'const fs=require("fs");const f=process.argv[1];const j=JSON.parse(fs.readFileSync(f,"utf8"));'"$2"';fs.writeFileSync(f,JSON.stringify(j,null,2));' "$1"; }
run() { node "$SUT" "$@" 2>&1; }

echo "== T1: the golden fixture validates clean =="
P="$(fresh golden)"
OUT="$(run validate --project "$P")"; RC=$?
check "exit 0" "$RC" "0"
has "summary line" "$OUT" "1 process(es), 8 step(s), 5 use case(s) (1 standalone), 4 wireframe(s), 0 error(s), 1 warning(s)"
has "a wireframe on no step is a warning, not an error" "$OUT" "WARN  1 wireframe(s) on no process step: Orders.Settings_Edit"

echo "== T2: anchor derives four, keeps two judged, leaves none unanchored =="
OUT="$(run anchor --project "$P")"; RC=$?
check "exit 0" "$RC" "0"
has "stat line" "$OUT" "anchors: 6 item(s), 4 derived, 2 judged, 2 global, 0 unanchored"
A="$(cat "$P/design/question-anchors.json")"
has "use case lists the question: Q01 on the submit step" "$A" '"basis": "F001:Q01 -> F001:UC001 -> P1-01"'
has "cited source lines overlap: Q02 on the approve screen step" "$A" '"basis": "F001:Q02 cites the lines of F001:UC002 -> P1-03"'
has "named screen: Q03 on the order list step" "$A" '"basis": "names screen Order_Overview -> P1-08"'
has "ASSUMED register row becomes a decision item" "$A" '"id": "D3-01"'
has "judged global anchor survives a re-run" "$A" '"bucket": "Money"'
hasnt "CONFIRMED decisions are not pinned" "$A" "Module structure"

echo "== T3: build writes a self-contained, deterministic board =="
OUT="$(run build --project "$P")"; RC=$?
check "exit 0" "$RC" "0"
B="$P/design/process-board.html"
[ -s "$B" ] && ok "design/process-board.html written" || bad "design/process-board.html written" "no file"
H="$(cat "$B" 2>/dev/null)"
has "app name in the page" "$H" "Order desk"
has "process title embedded" "$H" "Order approval: submit, approve or reject, notify"
has "wireframe embedded for thumbnails" "$H" "Approve order"
hasnt "wireframe scripts are stripped" "$H" "stripped from thumbnails"
hasnt "no external script" "$H" '<script src='
hasnt "no external stylesheet" "$H" 'rel="stylesheet" href="http'
hasnt "placeholder replaced" "$H" '"__DATA__"'
S1="$(shasum "$B" | cut -d' ' -f1)"
run build --project "$P" >/dev/null
S2="$(shasum "$B" | cut -d' ' -f1)"
check "same input, same bytes" "$S2" "$S1"

echo "== T4: each model defect is an error with exit 1 =="
defect() { # $1 label, $2 js edit of the model, $3 expected message
  local d; d="$(fresh "d$RANDOM")"
  jedit "$d/design/process-model.json" "$2"
  local o rc; o="$(run validate --project "$d")"; rc=$?
  check "$1: exit 1" "$rc" "1"
  has "$1: message" "$o" "$3"
}
defect "page without wireframe" 'j.processes[0].steps[2].page="Order_Missing"' 'P1-03: page "Order_Missing" has no wireframe'
defect "task step without page" 'delete j.processes[0].steps[7].page; j.processes[0].steps[7].kind="task"' 'P1-08: a task step needs a page'
defect "unknown use case" 'j.processes[0].steps[0].useCases=["F001:UC099"]' 'P1-01: use case F001:UC099 is not in any BRD'
defect "use case on no process" 'j.standalone=[]' 'use case F001:UC005 (Nightly cleanup of abandoned drafts) is on no process and not listed as standalone'
defect "standalone without reason" 'j.standalone[0].reason=""' 'standalone use case F001:UC005 has no reason'
defect "decision with one outcome" 'j.processes[0].steps[3].next=[{to:"P1-05",label:"Approve"}]' 'P1-04: a decision needs at least two outcomes'
defect "next to a missing step" 'j.processes[0].steps[0].next=["P1-99"]' 'P1-01: next "P1-99" is not a step id'
defect "undeclared lane" 'j.processes[0].steps[0].lane="ghost"' 'P1-01: lane "ghost" is not declared'
defect "two steps in one cell" 'j.processes[0].steps[1].col=0; j.processes[0].steps[1].lane="requester"' 'shares lane requester column 0'
defect "duplicate step id" 'j.processes[0].steps[1].id="P1-01"' 'step id P1-01 is used twice'

echo "== T5: a missing wireframe with a reason is a warning =="
P="$(fresh wfmissing)"
jedit "$P/design/process-model.json" 'j.processes[0].steps[2].page="Order_Missing"; j.processes[0].steps[2].wireframeMissing="built with defaults"'
OUT="$(run validate --project "$P")"; RC=$?
check "exit 0" "$RC" "0"
has "warning names the reason" "$OUT" "P1-03: page Order_Missing has no wireframe (built with defaults)"

echo "== T6: unanchored items fail --strict; a changed item drops its judged anchor =="
P="$(fresh strict)"
jedit "$P/design/question-anchors.json" 'j.anchors=j.anchors.filter(a=>a.id!=="F001:Q04")'
OUT="$(run validate --strict --project "$P")"; RC=$?
check "strict exit 1 with one unanchored" "$RC" "1"
has "unanchored counted" "$OUT" "1 unanchored"
OUT="$(run validate --project "$P")"; RC=$?
check "without --strict, unanchored is reported, not failed" "$RC" "0"
P="$(fresh stale)"
jedit "$P/design/question-anchors.json" 'j.anchors.find(a=>a.id==="F001:Q04").fingerprint="Which currency did amounts use before?"'
OUT="$(run anchor --project "$P")"
has "stale judged anchor dropped with a warning" "$OUT" "judged anchor F001:Q04 dropped"
has "and the item is unanchored again" "$OUT" "1 unanchored"
P="$(fresh badjudged)"
jedit "$P/design/question-anchors.json" 'j.anchors[0].targets=[{type:"step",step:"P9-99"}]'
OUT="$(run validate --project "$P")"; RC=$?
check "judged anchor to a missing step: exit 1" "$RC" "1"

echo "== T6b: ignorePages silences the wireframe-on-no-step warning; anchor --json keeps stdout pure =="
P="$(fresh ignore)"
jedit "$P/design/process-model.json" 'j.ignorePages=["Orders.Settings_Edit"]'
OUT="$(run validate --project "$P")"; RC=$?
check "exit 0" "$RC" "0"
hasnt "ignored page gives no warning" "$OUT" "wireframe(s) on no process step"
has "summary shows 0 warnings" "$OUT" "0 error(s), 0 warning(s)"
jedit "$P/design/process-model.json" 'j.ignorePages=["Orders.Nope"]'
OUT="$(run validate --project "$P")"
has "an ignorePages entry that matches nothing warns" "$OUT" 'ignorePages: "Orders.Nope" matches no wireframe'
P="$(fresh jsonout)"
jedit "$P/design/question-anchors.json" 'j.anchors=j.anchors.filter(a=>a.id!=="F001:Q04")'
JOUT="$(node "$SUT" anchor --json --project "$P" 2>/dev/null)"; RC=$?
check "anchor --json exits 1 while items remain" "$RC" "1"
check "stdout is pure JSON" "$(printf '%s' "$JOUT" | node -e 'try{const j=JSON.parse(require("fs").readFileSync(0,"utf8"));console.log(Array.isArray(j)?j.length:"notarray")}catch(e){console.log("bad")}')" "1"

echo "== T7: build refuses on errors =="
P="$(fresh refuse)"
jedit "$P/design/process-model.json" 'j.processes[0].steps[0].useCases=["F001:UC099"]'
OUT="$(run build --project "$P")"; RC=$?
check "exit 1" "$RC" "1"
[ -e "$P/design/process-board.html" ] && bad "no board written" "file exists" || ok "no board written"

echo "== T8: usage errors exit 2 =="
OUT="$(run frobnicate --project "$FIX")"; RC=$?
check "unknown command" "$RC" "2"
OUT="$(run validate --project "$TMP/nowhere")"; RC=$?
check "no model" "$RC" "2"

echo "== T9: Stage-3 gate fails a missing or stale process board =="
gatefix() { # a full Stage-3 PASS scaffold plus the process board fixture
  local d; d="$(fresh "$1")"
  mkdir -p "$d/architecture"
  printf '# fit-gap\nrow\n' > "$d/architecture/fit-gap.md"
  printf '# bp\nx\n' > "$d/architecture/blueprint.md"
  printf '<html>\n' > "$d/design/design-system.html"
  touch -t 202601010000 "$d/architecture/fit-gap.md" "$d/architecture/blueprint.md" "$d/design/process-model.json" "$d/design/question-anchors.json"
  printf '<html>\n' > "$d/architecture/blueprint.html"
  touch -t 202601010100 "$d/architecture/blueprint.html"
  echo "$d"
}
P="$(gatefix gate-missing)"
V="$("$GATE" --no-html "$P" 3 2>&1)"
has "model without board fails" "$V" "design/process-model.json exists but design/process-board.html does not"
P="$(gatefix gate-fresh)"
node "$SUT" build --project "$P" >/dev/null 2>&1
touch -t 202601010200 "$P/design/process-board.html"
V="$("$GATE" --no-html "$P" 3 2>&1)"
hasnt "current board passes the process board check" "$V" "process-board.html is older"
has "and the stage passes" "$V" "PASS"
touch -t 202601010300 "$P/design/process-model.json"
V="$("$GATE" --no-html "$P" 3 2>&1)"
has "model newer than board fails" "$V" "design/process-board.html is older than process-model.json"
P="$(gatefix gate-none)"
rm "$P/design/process-model.json"
V="$("$GATE" --no-html "$P" 3 2>&1)"
hasnt "no model: no process board FAIL" "$V" "design/process-model.json exists but"
hasnt "no model: no staleness FAIL" "$V" "process-board.html is older"

printf '\n%s: %d ok, %d FAIL\n' "$(basename "$0")" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
