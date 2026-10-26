#!/bin/bash
# test-brd-report-process-map.sh: pin the fused Stage 2 report (2026-10-16): the process map at the
# top of analysis/brd-report.html, the requirements and open questions listed under it with the
# step each is about, and open-questions.html retired.
#
# What is worth pinning: (1) the map is IN the report, drawn by process-map.js, not a copy;
# (2) a step's id in the map is the same id the list rows carry, so a click lands on the rows that
# are about it; (3) what belongs to no step is still listed ("whole app"), never dropped; (4) no
# open-questions.html is produced any more, and an old one in a project is never an error.
# Golden input is the process-map fixture, copied into the BRD location the report discovers,
# without wireframes (pass 1: the report is a Stage 2 surface and needs no screens).
#
# Usage: bash test-brd-report-process-map.sh [path-to-brd-report.sh]

set -u

TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
BR="${1:-$TOOLKIT/bin/brd-report.sh}"
GATE="$TOOLKIT/bin/gate-check.sh"
FIX="$TOOLKIT/tests/wave2/fixtures/process-map"
export MXTK_NO_FETCH=1 MXTK_STRICT_PROTOCOL=0
# shellcheck disable=SC1091
. "$TOOLKIT/bin/lib/portable.sh"
require_py
command -v node >/dev/null 2>&1 || { echo "SKIP: node not on PATH"; exit 0; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }

PASS=0; FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected '$3', got '$2'"; fi; }
has()  { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "missing '$3'" ;; esac; }
hasnt(){ case "$2" in *"$3"*) bad "$1" "unexpected '$3'" ;; *) ok "$1" ;; esac; }

# project <name> [with-wireframes]: the fixture as a Stage 2 project
project() {
  local d="$TMP/$1"
  mkdir -p "$d/analysis/a/knowledge-base/brd" "$d/analysis/a/knowledge-base/reports" "$d/design"
  cp "$FIX"/brd/*.json "$d/analysis/a/knowledge-base/brd/"
  cp "$FIX"/design/process-model.json "$FIX"/design/question-anchors.json "$FIX"/design/ds.css "$d/design/"
  cp "$FIX"/PROJECT.md "$d/PROJECT.md"
  jq '.brdDirs=["analysis/a/knowledge-base/brd"]' "$d/design/process-model.json" > "$d/pm.tmp" && mv "$d/pm.tmp" "$d/design/process-model.json"
  [ "${2:-}" = "with-wireframes" ] && cp -R "$FIX/design/wireframes" "$d/design/wireframes"
  printf '# validation\n\n## Stop condition\n\nClean\n' > "$d/analysis/a/knowledge-base/reports/validation-report.md"
  echo "$d"
}
# the step ids the map draws (data-step="..." inside the framed page) and the ids the rows carry
map_steps() { "$PY" - "$1" <<'PY'
import html, re, sys
d = open(sys.argv[1]).read()
m = re.search(r'<iframe id="pm-frame"[^>]*srcdoc="([^"]*)"', d)
inner = html.unescape(m.group(1)) if m else ''
# the map's data is JSON inside the framed page; its step ids are the ones the cards get
ids = sorted(set(re.findall(r'"id":"(P\d+-\d+)"', inner)))
print(' '.join(ids))
PY
}
row_steps() { "$PY" - "$1" <<'PY'
import re, sys
d = open(sys.argv[1]).read()
ids = set()
for m in re.finditer(r'class="pmrow[^"]*"[^>]*data-steps="([^"]*)"', d):
    ids.update(m.group(1).split())
print(' '.join(sorted(ids)))
PY
}

echo "== T1: the report opens with the process map =="
P="$(project fused)"
OUT="$(bash "$BR" "$P" --quiet 2>&1)"; RC=$?
check "exit 0" "$RC" "0"
R="$P/analysis/brd-report.html"
[ -s "$R" ] && ok "analysis/brd-report.html written" || bad "analysis/brd-report.html written" "no file"
H="$(cat "$R")"
has "a process map section" "$H" 'id="pm-map"'
has "the map is the framed process-map page" "$H" '<iframe id="pm-frame"'
has "the map's process title is in it" "$H" "Order approval: submit, approve or reject, notify"
hasnt "no wireframes needed: pass 1" "$(ls "$P/design")" "wireframes"
# the map comes before the stat grid and the per-BRD sections
"$PY" - "$R" <<'PY' && ok "map first, then the list, then the BRD sections" || bad "order" "map, list, stats, verdicts, per-BRD expected"
import sys
d = open(sys.argv[1]).read()
a, b, c, e = d.index('id="pm-map"'), d.index('id="pm-list"'), d.index('class="stat-grid"'), d.index('<h2>Per BRD</h2>')
sys.exit(0 if a < b < c < e else 1)
PY

echo "== T2: a step's id in the map is the id the rows carry =="
MS="$(map_steps "$R")"
RS="$(row_steps "$R")"
has "the map has the steps" "$MS" "P1-01"
# every step that has a requirement or a question in the model must have rows in the list
for s in P1-01 P1-03 P1-07 P1-08; do
  case " $MS " in *" $s "*) ok "map step $s exists" ;; *) bad "map step $s exists" "map ids: $MS" ;; esac
  case " $RS " in *" $s "*) ok "rows carry step id $s" ;; *) bad "rows carry step id $s" "row ids: $RS" ;; esac
done
# no row names a step the map does not draw
BAD=""; for s in $RS; do case " $MS " in *" $s "*) ;; *) BAD="$BAD $s" ;; esac; done
check "no row names a step the map lacks" "${BAD:-none}" "none"
has "requirement anchor for the submit use case" "$H" 'id="req-F001-UC001" data-kind="req" data-steps="P1-01"'
has "question anchor for Q01 (on the submit step)" "$H" 'id="q-F001-Q01" data-kind="q" data-steps="P1-01"'
has "question anchor for Q02 (on the approve step)" "$H" 'id="q-F001-Q02" data-kind="q" data-steps="P1-03"'
has "the ASSUMED register row is listed as an assumption" "$H" 'id="a-D3-01"'
has "a step chip links to the step" "$H" 'data-step="P1-01"'
has "a click on a step is wired (message to the page)" "$H" "pm:&#x27;step&#x27;"
has "the page filters on the message" "$H" "d.pm === 'step'"
has "the filter reads a #step= link" "$H" "#step="

echo "== T3: what no step is about is listed, not dropped =="
"$PY" - "$R" <<'PY' && ok "unplaced rows sit in the whole-app section" || bad "unplaced rows sit in the whole-app section" "see below"
import re, sys
d = open(sys.argv[1]).read()
whole = d[d.index('id="pm-whole"'):]
whole = whole[:whole.index('<div class="stat-grid"')] if '<div class="stat-grid"' in whole else whole
ids = re.findall(r'class="pmrow[^"]*" id="([^"]+)"[^>]*data-steps=""', whole)
need = {'req-F001-UC005', 'q-F001-Q04'}
missing = need - set(ids)
if missing:
    print('missing from whole app:', sorted(missing), 'found:', ids)
    sys.exit(1)
PY
has "the standalone use case says why" "$H" "Not part of a process:"
# every use case and every question appears exactly once in the list
N_REQ="$(printf '%s' "$H" | grep -o 'data-kind="req"' | wc -l | tr -d ' ')"
check "all five use cases are listed" "$N_REQ" "5"
N_Q="$(printf '%s' "$H" | grep -o 'id="q-F001-Q0[1-4]"' | wc -l | tr -d ' ')"
check "all four BRD questions are listed" "$N_Q" "4"
has "the blocking banner (same content as the retired page)" "$H" "have never been put to the user"
has "a drafting position is shown" "$H" "Drafting position"

echo "== T4: no model, a broken model, no node-free fallback =="
P="$(project nomodel)"; rm "$P/design/process-model.json"
bash "$BR" "$P" --quiet >/dev/null 2>&1; RC=$?
check "no model: still renders" "$RC" "0"
H2="$(cat "$P/analysis/brd-report.html")"
has "no model: says no map yet" "$H2" "No process map yet"
hasnt "no model: no frame" "$H2" '<iframe id="pm-frame"'
has "no model: requirements still listed" "$H2" 'id="req-F001-UC001"'
has "no model: questions still listed" "$H2" 'id="q-F001-Q01"'
P="$(project badmodel)"; jq '.processes[0].steps[0].lane="ghost"' "$P/design/process-model.json" > "$P/m" && mv "$P/m" "$P/design/process-model.json"
bash "$BR" "$P" --quiet >/dev/null 2>&1; RC=$?
check "broken model: still renders" "$RC" "0"
has "broken model: says why" "$(cat "$P/analysis/brd-report.html")" "did not build"

echo "== T5: open-questions.html is retired =="
P="$(project gate-q)"
mkdir -p "$P/analysis/a/knowledge-base/brd"
jq '.openQuestions=[{"id":"Q01","question":"Is the engine in scope?","status":"Open"}]' "$P/analysis/a/knowledge-base/brd/F001-orders.brd.json" > "$P/q" && mv "$P/q" "$P/analysis/a/knowledge-base/brd/F001-orders.brd.json"
OUT="$("$GATE" "$P" 2 2>&1)"; RC=$?
check "the stage 2 gate still blocks on an unraised question" "$RC" "1"
has "the gate points at the BRD report" "$OUT" "analysis/brd-report.html"
[ -f "$P/analysis/brd-report.html" ] && ok "the gate wrote the BRD report" || bad "the gate wrote the BRD report" "missing"
[ ! -e "$P/docs/open-questions.html" ] && ok "no docs/open-questions.html produced" || bad "no docs/open-questions.html produced" "exists"
[ ! -e "$TOOLKIT/bin/questions-report.sh" ] && ok "bin/questions-report.sh is gone" || bad "bin/questions-report.sh is gone" "exists"
find "$P" -name 'open-questions.html' | grep -q . && bad "no open-questions.html anywhere" "$(find "$P" -name open-questions.html)" || ok "no open-questions.html anywhere"
has "the questions are in the report" "$(cat "$P/analysis/brd-report.html")" "Is the engine in scope?"
# an old project: the retired file is there, nothing fails because of it, and it is pointed away from
mkdir -p "$P/docs"; echo '<html>old</html>' > "$P/docs/open-questions.html"
OUT2="$("$GATE" "$P" 2 2>&1)"; RC2=$?
check "an old open-questions.html changes no verdict" "$RC2" "$RC"
has "the gate says the old page is retired" "$OUT2" "docs/open-questions.html is the retired page"
has "and where the content is now" "$OUT2" "analysis/brd-report.html"
# an old project whose questions are all answered: the old file must not turn a pass into a fail
P="$(project gate-ok)"
jq '.openQuestions=[]' "$P/analysis/a/knowledge-base/brd/F001-orders.brd.json" > "$P/q" && mv "$P/q" "$P/analysis/a/knowledge-base/brd/F001-orders.brd.json"
"$GATE" --no-html "$P" 2 >/dev/null 2>&1; RC3=$?
mkdir -p "$P/docs"; echo '<html>old</html>' > "$P/docs/open-questions.html"
"$GATE" --no-html "$P" 2 >/dev/null 2>&1; RC4=$?
check "old file present: same verdict as without it" "$RC4" "$RC3"

echo "== T6: the filter works in a browser (when Chrome is here) =="
CHROME=""
MAC_CHROME=""; [ "$(uname)" = Darwin ] && MAC_CHROME="/Applic""ations/Google Chrome.app/Contents/MacOS/Google Chrome"   # macOS only; elsewhere the browser check uses PATH or is skipped
for c in "$MAC_CHROME" google-chrome chromium chromium-browser; do
  if { [ -n "$c" ] && [ -x "$c" ]; } || command -v "$c" >/dev/null 2>&1; then CHROME="$c"; break; fi
done
if [ -n "$CHROME" ]; then
  P="$(project browser)"; bash "$BR" "$P" --quiet >/dev/null 2>&1
  DOM="$("$CHROME" --headless=new --disable-gpu --virtual-time-budget=5000 --dump-dom "file://$P/analysis/brd-report.html#step=P1-03" 2>/dev/null)"
  VIS="$(printf '%s' "$DOM" | "$PY" -c '
import re, sys
d = sys.stdin.read()
rows = re.findall(r"<div class=\"pmrow[^>]*>", d)
print(sum(1 for r in rows if " hidden" not in r.replace("data-", "")), len(rows))')"
  VISIBLE="${VIS% *}"; TOTAL="${VIS#* }"
  [ "$TOTAL" -gt "$VISIBLE" ] && [ "$VISIBLE" -ge 1 ] && ok "#step=P1-03 shows only that step's rows ($VISIBLE of $TOTAL)" || bad "#step=P1-03 shows only that step's rows" "visible=$VISIBLE total=$TOTAL"
  has "the filter bar is shown" "$DOM" 'id="pm-bar"'
else
  echo "  skip no Chrome found"
fi

echo "== T7: Stage 3: the map and the wireframes link both ways =="
P="$(project stage3 with-wireframes)"
node "$TOOLKIT/project-bin/assemble-prototype.js" "$P/design" >/dev/null 2>&1
PROTO="$(cat "$P/design/prototype.html")"
has "the prototype links to the map" "$PROTO" 'id="proto-map" href="process-map.html"'
node "$TOOLKIT/project-bin/process-map.js" build --project "$P" >/dev/null 2>&1
MAP="$(cat "$P/design/process-map.html")"
has "the map links to the prototype" "$MAP" '"protoHref":"prototype.html"'
has "the map has the wireframes button" "$MAP" 'id="protolink"'
P2="$(project nomap-proto with-wireframes)"; rm "$P2/design/process-model.json"
node "$TOOLKIT/project-bin/assemble-prototype.js" "$P2/design" >/dev/null 2>&1
hasnt "no model: no map link in the prototype" "$(cat "$P2/design/prototype.html")" 'id="proto-map"'
# the Stage 2 report is the same page at Stage 3: with screens the map shows them
bash "$BR" "$P" --quiet >/dev/null 2>&1
has "stage 3 report still builds with wireframes" "$(cat "$P/analysis/brd-report.html")" '<iframe id="pm-frame"'

echo "== T8: the map renderer is not copied =="
check "brd-report.sh draws no swimlane itself" "$(grep -c 'laneband\|renderProcess' "$BR")" "0"
has "it calls process-map.js build --embed" "$(cat "$BR")" "'build', '--embed'"

echo "== T9: review fixes: questions-only report, --stage, whole-app collapse, fit =="
# a Stage 0/1 gate blocked by sme-questions.md only (no BRDs) still writes a report
Q="$TMP/smeonly"; mkdir -p "$Q/analysis/a/knowledge-base"
echo "<html>x</html>" > "$Q/analysis/a/knowledge-base/extraction-report.html"   # Stage 1 passes on its own evidence, so the gate reaches the question check
cat > "$Q/analysis/sme-questions.md" <<'M'
# SME questions

| # | Question | Evidence | Options |
|---|---|---|---|
| F1 | What is the approval limit for an order? | source | (a) 1000 (b) none |
| F2 | Who signs off on refunds? | source | (a) lead (b) finance |
M
printf '# Demo\n' > "$Q/PROJECT.md"
GOUT="$("$GATE" "$Q" 1 2>&1)"
has "the gate is blocked by the unraised questions" "$GOUT" "Gate BLOCKED"
has "and gives the path of the report" "$GOUT" "brd-report.html"
[ -f "$Q/analysis/brd-report.html" ] && ok "gate stage 1 with only sme-questions.md writes a report" || bad "gate stage 1 with only sme-questions.md writes a report"
QR="$(cat "$Q/analysis/brd-report.html" 2>/dev/null)"
has "the questions-only page lists the unraised question" "$QR" "What is the approval limit for an order?"
has "the page says it is a stage view" "$QR" "Open questions, stage 1 view"
has "the page header shows the stage filter" "$QR" "Questions shown: up to stage 1."
hasnt "no process map frame without a model" "$QR" '<iframe id="pm-frame"'
mkdir -p "$TMP/nothing-here"; bash "$BR" "$TMP/nothing-here" --quiet >/dev/null 2>&1; check "no BRDs and no questions still exits 3" "$?" "3"
# --stage passthrough: the stage the gate asked for reaches the collector
P="$(project stagearg)"
bash "$BR" "$P" --stage 1 --quiet >/dev/null 2>&1
has "--stage N is shown in the lede" "$(cat "$P/analysis/brd-report.html")" "Questions shown: up to stage 1."
bash "$BR" "$P" --quiet >/dev/null 2>&1
hasnt "without --stage there is no stage note" "$(cat "$P/analysis/brd-report.html")" "Questions shown: up to stage"
# the whole-app group is collapsed above 8 items, open below
P="$(project manyq)"
jq '.openQuestions += [range(10) | {"id":("W"+tostring),"question":("Whole app question "+tostring),"assumption":"none","blocking":false,"source":"x"}]' "$P/analysis/a/knowledge-base/brd/F001-orders.brd.json" > "$P/q" && mv "$P/q" "$P/analysis/a/knowledge-base/brd/F001-orders.brd.json"
bash "$BR" "$P" --quiet >/dev/null 2>&1
MQ="$(cat "$P/analysis/brd-report.html")"
has "more than 8 whole-app items are collapsed" "$MQ" '<details class="more"><summary>Show the'
P="$(project fewq)"; bash "$BR" "$P" --quiet >/dev/null 2>&1
hasnt "8 or fewer whole-app items are not collapsed" "$(cat "$P/analysis/brd-report.html")" '<summary>Show the'
# the embedded map is fitted: the iframe starts at a computed height and the host ignores a bogus first post
BRS="$(cat "$BR")"
has "the iframe gets a first-paint height" "$BRS" "pm_h0"
has "the host ignores a collapsed height post" "$BRS" "d.h > 80"
if [ -n "$CHROME" ]; then
  # The embedded map drawn at the width the report gives it (the page is 980px wide, the frame about 970):
  # the last step card must end inside the frame, not be cut off on the right.
  P="$(project fit)"
  "$PY" - "$P/design/process-model.json" <<'PY'
import json, sys
f = sys.argv[1]; m = json.load(open(f)); st = m['processes'][0]['steps']
keep, drop = st[:3], st[3:]
keep[-1]['next'] = []
have = {u for s in keep for u in s.get('useCases', [])}
lost = sorted({u for s in drop for u in s.get('useCases', [])} - have)
m['processes'][0]['steps'] = keep
m.setdefault('standalone', []).extend({'useCase': u, 'reason': 'n/a'} for u in lost)
m['standalone'] = [x for x in m['standalone'] if x['useCase'] not in have]
json.dump(m, open(f, 'w'))
PY
  node "$TOOLKIT/project-bin/process-map.js" build --project "$P" --embed --out "$P/embed.html" --data-out "$P/embed.json" >/dev/null 2>&1
  "$PY" - "$P/embed.html" <<'PY'
import sys
f = sys.argv[1]; s = open(f).read()
js = """<script>setTimeout(function(){var c=document.querySelectorAll('.step');var l=c[c.length-1];var r=l.getBoundingClientRect();
var b=document.querySelector('.board');document.title='FIT:'+(r.right<=window.innerWidth+1?'inside':'clipped')+':'+Math.round(r.right)+'/'+window.innerWidth+':zoom'+(b.style.zoom||1);},2500);</script></body>"""
open(f, 'w').write(s.replace('</body>', js, 1))
PY
cat > "$P/fitprobe.py" <<'PY'
import subprocess, sys, re
chrome, f = sys.argv[1], sys.argv[2]
try:
    out = subprocess.run([chrome, '--headless=new', '--disable-gpu', '--virtual-time-budget=8000',
        '--window-size=970,900', '--dump-dom', 'file://' + f], capture_output=True, text=True, timeout=90).stdout
    m = re.search(r'<title>(FIT:[^<]*)</title>', out)
    print(m.group(1) if m else 'FIT:unreadable')
except Exception as e:
    print('FIT:error ' + str(e))
PY
FITOUT="$("$PY" "$P/fitprobe.py" "$CHROME" "$P/embed.html")"
  case "$FITOUT" in
    FIT:unreadable|FIT:error*) echo "  skip browser fit probe ($FITOUT)";;
    *) has "last step card is inside the frame width ($FITOUT)" "$FITOUT" "FIT:inside";;
  esac
fi


printf '\n%s: %d ok, %d FAIL\n' "$(basename "$0")" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
