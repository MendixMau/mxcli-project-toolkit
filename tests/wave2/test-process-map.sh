#!/bin/bash
# test-process-map.sh: pin what process-map.js validates, how it anchors questions, what
# `build` writes, and the Stage-3 gate rule that a process map must not be older than its model.
#
# Golden input: tests/wave2/fixtures/process-map/, a synthetic order approval app (one BRD with
# five use cases and four open questions, four wireframes, a PROJECT.md decisions table with two
# ASSUMED rows, a process model and two judged anchors). Its shapes follow the BRD contract
# (useCases, openQuestions, pages) and the wireframe contract (data-mx-page, data-route) the real
# Stage-2 and Stage-3 producers write. Each defect case copies the fixture and changes one thing,
# so a pass means that one defect was seen.
#
# Usage: bash test-process-map.sh [path-to-process-map.js]

set -u

TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
SUT="${1:-$TOOLKIT/project-bin/process-map.js}"
SUT="$(cd "$(dirname "$SUT")" && pwd)/$(basename "$SUT")"
GATE="$TOOLKIT/bin/gate-check.sh"
FIX="$TOOLKIT/tests/wave2/fixtures/process-map"
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

echo "== T3: build writes a self-contained, deterministic map =="
OUT="$(run build --project "$P")"; RC=$?
check "exit 0" "$RC" "0"
B="$P/design/process-map.html"
[ -s "$B" ] && ok "design/process-map.html written" || bad "design/process-map.html written" "no file"
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
[ -e "$P/design/process-map.html" ] && bad "no map written" "file exists" || ok "no map written"

echo "== T8: usage errors exit 2 =="
OUT="$(run frobnicate --project "$FIX")"; RC=$?
check "unknown command" "$RC" "2"
OUT="$(run validate --project "$TMP/nowhere")"; RC=$?
check "no model" "$RC" "2"

echo "== T10: pass 1 (Stage 2 close) works with no wireframes at all =="
P="$(fresh pass1)"
rm -rf "$P/design/wireframes"
OUT="$(run validate --project "$P")"; RC=$?
check "steps that name a screen are allowed: exit 0" "$RC" "0"
has "summary: 0 errors, 0 wireframes" "$OUT" "0 wireframe(s), 0 error(s)"
hasnt "no wireframe error" "$OUT" "has no wireframe in"
jedit "$P/design/process-model.json" 'delete j.processes[0].steps[0].page'
OUT="$(run validate --project "$P")"; RC=$?
check "a person step with no screen is allowed: exit 0" "$RC" "0"
hasnt "no task-needs-a-page error" "$OUT" "a task step needs a page"
run anchor --project "$P" >/dev/null
OUT="$(run build --project "$P")"; RC=$?
check "build exits 0" "$RC" "0"
H="$(cat "$P/design/process-map.html" 2>/dev/null)"
K="$(printf '%s' "$H" | node -e 'const h=require("fs").readFileSync(0,"utf8");const m=h.match(/\nvar D = (.*);\n/);if(!m){console.log("nodata");process.exit()}const d=JSON.parse(m[1]);const st=d.processes[0].steps;console.log(st.filter(s=>["P1-01","P1-02","P1-03","P1-08"].includes(s.id)).map(s=>s.id+":"+s.kind+":"+(s.page||"-")+":"+(s.pageMissing?"missing":"")).join(","))')"
check "person steps stay tasks, a named screen is kept as a label, a system step stays system" "$K" "P1-01:task:-:,P1-02:system:-:,P1-03:task:Order_Approve:missing,P1-08:task:Order_Overview:missing"
OUT="$(run validate --strict --project "$P")"; RC=$?
check "pass 1 with every question anchored passes --strict" "$RC" "0"

echo "== T11: answered, consented and open questions are told apart; answers reach the map =="
P="$(fresh answers)"
jedit "$P/brd/F001-orders.brd.json" 'const q=j.openQuestions;
  q[0].status="OPEN"; q[0].options=["A: no maximum","B: cap at 10000"]; q[0].recommendation="A: no maximum";
  q[1].status="ANSWERED"; q[1].answer="No: the approver must be a different person than the requester."; q[1].answeredBy="owner"; q[1].answeredAt="2026-10-17";
  q[2].status="ASSUMED"; q[2].consentBy="owner"; q[2].consentAt="2026-10-17";
  q[3].status="ASSUMED"'
sed -i.bak 's/^| 3 | Hosting: one environment for the demo | ASSUMED | risk: none for the demo |$/| 3 | Hosting: one environment for the demo, shared by every team that needs to look at the build during the review week | ASSUMED | risk: none for the demo |/' "$P/PROJECT.md"
OUT="$(run build --project "$P")"; RC=$?
check "exit 0" "$RC" "0"
H="$(cat "$P/design/process-map.html")"
DJ="$(printf '%s' "$H" | node -e 'const h=require("fs").readFileSync(0,"utf8");const m=h.match(/\nvar D = (.*);\n/);const d=JSON.parse(m[1]);
  const by=s=>d.items.filter(i=>i.state===s).length;
  const it=d.items.find(i=>i.id==="F001:Q02");const dec=d.items.find(i=>/Hosting/.test(i.text));
  console.log([by("open"),by("answered"),by("consented"),by("assumed"),it.answer.slice(0,12),it.answeredBy,it.answeredAt,d.items.find(i=>i.id==="F001:Q03").consentBy,d.items.find(i=>i.id==="F001:Q01").options.length,d.items.find(i=>i.id==="F001:Q01").recommendation,dec.title.slice(-1),dec.text.length>dec.title.length,dec.text.endsWith("review week")].join("|"))')"
# open: Q01 only; answered: Q02 + the CONFIRMED register row; consented: Q03; assumed waiting: Q04 + 2 ASSUMED register rows
check "state counts and fields reach D.items" "$DJ" "1|2|1|3|No: the appr|owner|2026-10-17|owner|2|A: no maximum|…|true|true"
has "the answer text is in the page" "$H" "No: the approver must be a different person than the requester."
has "the CONFIRMED register row is shown as decided" "$H" "Module structure: one module Orders"
has "the page has an Open only filter" "$H" 'id="openOnly"'
has "the page has an answered legend entry" "$H" "Answered or decided"
BRDA="$(run anchor --project "$P")"
has "CONFIRMED rows are not pinned or anchored" "$BRDA" "anchors: 6 item(s)"
hasnt "CONFIRMED rows are not in the anchors file" "$(cat "$P/design/question-anchors.json")" "Module structure"
P2="$(fresh consolidated)"
jedit "$P2/brd/F001-orders.brd.json" 'j.openQuestions[0].status="ANSWERED"; j.openQuestions[0].answer="No maximum."; j.openQuestions[1].status="ANSWERED"; j.openQuestions[1].answer="Different person."; j.openQuestions[2].status="OPEN"'
printf '%s' '{"questions":[{"cid":"C1","title":"Limits","question":"Which limits apply?","sources":[{"brd":"F001","id":"Q01"},{"brd":"F001","id":"Q02"}]},{"cid":"C2","title":"History","question":"What does history show?","sources":[{"brd":"F001","id":"Q01"},{"brd":"F001","id":"Q03"}]}]}' > "$P2/design/questions.json"
jedit "$P2/design/process-model.json" 'j.questions="design/questions.json"'
run anchor --project "$P2" >/dev/null; run build --project "$P2" >/dev/null
CJ="$(node -e 'const h=require("fs").readFileSync(process.argv[1],"utf8");const m=h.match(/\nvar D = (.*);\n/);const d=JSON.parse(m[1]);console.log(["C1","C2"].map(id=>{const i=d.items.find(x=>x.id===id);return i.state+":"+i.answer}).join("|"))' "$P2/design/process-map.html")"
check "consolidated status comes from the referenced BRD questions" "$CJ" "answered:No maximum. | Different person.|open:No maximum."

echo "== T9: Stage-3 gate fails a missing or stale process map =="
gatefix() { # a full Stage-3 PASS scaffold plus the process map fixture
  local d; d="$(fresh "$1")"
  mkdir -p "$d/architecture"
  printf '# fit-gap\nrow\n' > "$d/architecture/fit-gap.md"
  printf '# bp\nx\n' > "$d/architecture/blueprint.md"
  printf '<html>\n' > "$d/design/design-system.html"
  touch -t 202601010000 "$d/architecture/fit-gap.md" "$d/architecture/blueprint.md" "$d/design/process-model.json" "$d/design/question-anchors.json" "$d"/design/wireframes/*.html
  printf '<html>\n' > "$d/architecture/blueprint.html"
  touch -t 202601010100 "$d/architecture/blueprint.html"
  echo "$d"
}
P="$(gatefix gate-missing)"
V="$("$GATE" --no-html "$P" 3 2>&1)"
has "model without map fails" "$V" "design/process-model.json exists but design/process-map.html does not"
P="$(gatefix gate-fresh)"
node "$SUT" build --project "$P" >/dev/null 2>&1
touch -t 202601010200 "$P/design/process-map.html"
V="$("$GATE" --no-html "$P" 3 2>&1)"
hasnt "current map passes the process map check" "$V" "process-map.html is older"
has "and the stage passes" "$V" "PASS"
touch -t 202601010300 "$P/design/process-model.json"
V="$("$GATE" --no-html "$P" 3 2>&1)"
has "model newer than map fails" "$V" "design/process-map.html is older than process-model.json"
P="$(gatefix gate-wf)"
node "$SUT" build --project "$P" >/dev/null 2>&1
touch -t 202601010200 "$P/design/process-map.html"
touch -t 202601010400 "$P/design/wireframes/Order_Approve.html"
V="$("$GATE" --no-html "$P" 3 2>&1)"
has "wireframe newer than map fails" "$V" "design/process-map.html is older than Order_Approve.html"
P="$(gatefix gate-none)"
rm "$P/design/process-model.json"
V="$("$GATE" --no-html "$P" 3 2>&1)"
hasnt "no model: no process map FAIL" "$V" "design/process-model.json exists but"
hasnt "no model: no staleness FAIL" "$V" "process-map.html is older"

printf '\n%s: %d ok, %d FAIL\n' "$(basename "$0")" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
