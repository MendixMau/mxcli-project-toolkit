#!/bin/bash
# test-process-map-field.sh: pin the field-run fixes of process-map.js (2026-10-16): anchors migration,
# the carried-over report of anchor, long processes, BRD discovery in an existing app's layout,
# PAGE-MAP.tsv page resolution, and the one-line cause summary of validate. Neutral names only.
set -u
TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
PM="$TOOLKIT/project-bin/process-map.js"
FIX="$TOOLKIT/tests/wave2/fixtures/process-map"
# shellcheck disable=SC1091
. "$TOOLKIT/bin/lib/portable.sh"
require_py
command -v node >/dev/null 2>&1 || { echo "SKIP: node not on PATH"; exit 0; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1 :: ${2:-}"; }
has()   { case "$2" in *"$3"*) ok "$1";; *) bad "$1" "missing: $3";; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1" "unexpected: $3";; *) ok "$1";; esac; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fresh() { rm -rf "$TMP/$1"; mkdir -p "$TMP/$1"; cp -R "$FIX/." "$TMP/$1/"; echo "$TMP/$1"; }
ls "$FIX" >/dev/null 2>&1 || { echo "no fixture"; exit 1; }

echo "== migrate: an old anchors path moves to design/question-anchors.json =="
P=$(fresh mig)
node "$PM" anchor --project "$P" >/dev/null 2>&1
mkdir -p "$P/design/prototype"
cp "$P/design/question-anchors.json" "$P/design/prototype/anchors-old.json"
rm "$P/design/question-anchors.json"
"$PY" - "$P/design/process-model.json" <<'PY'
import json,sys
p=sys.argv[1]; m=json.load(open(p)); m['anchors']='design/prototype/anchors-old.json'; json.dump(m,open(p,'w'),indent=2)
PY
V=$(node "$PM" validate --project "$P" 2>&1)
has "validate warns about the missing anchors file and names migrate" "$V" "migrate"
OUT=$(node "$PM" migrate --project "$P" 2>&1)
has "migrate prints what was carried over" "$OUT" "migrate: carried over"
[ -f "$P/design/question-anchors.json" ] && ok "new anchors file written" || bad "new anchors file written"
[ -f "$P/design/prototype/anchors-old.json.bak" ] && ok "old file kept as .bak" || bad "old file kept as .bak"
[ ! -f "$P/design/prototype/anchors-old.json" ] && ok "old file moved away" || bad "old file moved away"
has "model key rewritten" "$(cat "$P/design/process-model.json")" '"anchors": "design/question-anchors.json"'
has "second migrate has nothing to do" "$(node "$PM" migrate --project "$P" 2>&1)" "nothing to do"

echo "== anchor: carried-over judged entries are reported =="
P=$(fresh car)
OUT=$(node "$PM" anchor --project "$P" 2>&1)
has "anchor reports carried-over judged entries" "$OUT" "carried over: 2 judged from design/question-anchors.json"
P=$(fresh car0); rm -f "$P/design/question-anchors.json"
has "anchor says when there was no previous file" "$(node "$PM" anchor --project "$P" 2>&1)" "carried over: 0 judged"

echo "== long process: warning above 12 steps, canvas holds the loop-back edge =="
L="$TMP/long"; mkdir -p "$L/design" "$L/brd"
"$PY" - "$L" <<'PY'
import json,sys
L=sys.argv[1]
steps=[]
for i in range(1,15):
    s={'id':'L-%02d'%i,'title':'Step %d'%i,'lane':'a' if i%2 else 'b'}
    if i<14: s['next']=['L-%02d'%(i+1)]
    else: s['next']=[{'to':'L-03','label':'Rework'}]
    steps.append(s)
json.dump({'schema':'process-model/1','app':'Demo','lanes':[{'id':'a','label':'A','kind':'role'},{'id':'b','label':'B','kind':'system'}],
 'processes':[{'id':'P1','title':'Long','steps':steps}],'standalone':[]},open(L+'/design/process-model.json','w'))
json.dump({'id':'F001','title':'Demo','useCases':[],'openQuestions':[]},open(L+'/brd/F001.brd.json','w'))
PY
V=$(node "$PM" validate --project "$L" 2>&1)
has "validate warns above 12 steps" "$V" "14 steps; above 12"
node "$PM" build --project "$L" >/dev/null 2>&1
has "long processes get compact cards" "$(cat "$L/design/process-map.html")" "p.steps.length>12"
has "a long process is scaled to fit its box" "$(cat "$L/design/process-map.html")" "function fit()"
has "board keeps room for the loop-back" "$(cat "$L/design/process-map.html")" "padding:30px 40px 16px 0"

echo "== existing-app layout: BRD in analysis/knowledge-base/brd, PAGE-MAP.tsv, no data-mx-page =="
E="$TMP/exist"; rm -rf "$E"; mkdir -p "$E/analysis/knowledge-base/brd" "$E/design/wireframes"
cp "$FIX"/brd/*.brd.json "$E/analysis/knowledge-base/brd/" 2>/dev/null || cp "$FIX"/*/brd/*.brd.json "$E/analysis/knowledge-base/brd/" 2>/dev/null || cp "$(find "$FIX" -name '*.brd.json' | head -1)" "$E/analysis/knowledge-base/brd/"
BRDID=$("$PY" -c "import json,glob;print(json.load(open(glob.glob('$E/analysis/knowledge-base/brd/*.json')[0]))['id'])")
UC=$("$PY" -c "import json,glob;print(json.load(open(glob.glob('$E/analysis/knowledge-base/brd/*.json')[0]))['useCases'][0]['id'])")
cat > "$E/design/wireframes/order-list-v2.html" <<'H'
<html><body><h1>Orders</h1></body></html>
H
cat > "$E/design/wireframes/index.html" <<'H'
<html><body><h1>Index</h1></body></html>
H
printf 'Order_Overview\torder-list-v2.html\n' > "$E/design/wireframes/PAGE-MAP.tsv"
STAND=$("$PY" -c "import json,glob;d=json.load(open(glob.glob('$E/analysis/knowledge-base/brd/*.json')[0]));print(json.dumps([{'useCase':'%s:%s'%(d['id'],u['id']),'reason':'n/a'} for u in d['useCases'][1:]]))")
cat > "$E/design/process-model.json" <<J
{"schema":"process-model/1","app":"Demo","lanes":[{"id":"r","label":"R","kind":"role"}],
 "ignorePages":["index"],
 "processes":[{"id":"P1","title":"Orders","steps":[{"id":"P1-01","title":"Look at orders","lane":"r","page":"Order_Overview","useCases":["$BRDID:$UC"]}]}],
 "standalone":$STAND}
J
V=$(node "$PM" validate --project "$E" 2>&1)
hasnt "BRD found in analysis/knowledge-base/brd" "$V" "is not in any BRD"
hasnt "page resolved through PAGE-MAP.tsv" "$V" "has no wireframe in"
echo "$V" | grep -q "0 error" && ok "validate has 0 errors" || bad "validate has 0 errors" "$(echo "$V" | grep ERROR | head -3)"
rm "$E/design/wireframes/PAGE-MAP.tsv"
V=$(node "$PM" validate --project "$E" 2>&1)
has "error names what it tried" "$V" "tried data-mx-page"
has "error mentions the missing PAGE-MAP.tsv" "$V" "PAGE-MAP.tsv"
sed -i.bak 's/"useCases":\["[^"]*"\]/"useCases":["ZZ99:UC001"]/' "$E/design/process-model.json"
V=$(node "$PM" validate --project "$E" 2>&1)
has "missing use case names the BRD found" "$V" "found $BRDID"
has "and points to brdDirs" "$V" "brdDirs"
mkdir -p "$TMP/nobrd/design"; cp "$E/design/process-model.json" "$TMP/nobrd/design/"
V=$(node "$PM" validate --project "$TMP/nobrd" 2>&1)
has "no BRD at all lists the folders searched" "$V" "analysis/knowledge-base/brd"

echo "== validate: one cause line when most errors share it =="
"$PY" - "$TMP/nobrd/design/process-model.json" <<'PY'
import json,sys
p=sys.argv[1]; m=json.load(open(p))
st=m['processes'][0]['steps']
for i in range(2,6):
    st.append({'id':'P1-0%d'%i,'title':'S%d'%i,'lane':'r','page':'x','useCases':['ZZ99:UC00%d'%i]})
json.dump(m,open(p,'w'))
PY
V=$(node "$PM" validate --project "$TMP/nobrd" 2>&1)
has "CAUSE line printed" "$V" "CAUSE"
FIRST=$(echo "$V" | grep -n "CAUSE" | head -1 | cut -d: -f1); FE=$(echo "$V" | grep -n "^ERROR" | head -1 | cut -d: -f1)
[ "$FIRST" -lt "$FE" ] && ok "CAUSE comes before the error list" || bad "CAUSE comes before the error list" "$FIRST vs $FE"
has "CAUSE gives the fix" "$V" 'set "brdDirs"'

echo "== migrate: old shape converts to targets, empty entries are left out =="
setanch() { "$PY" - "$1/design/process-model.json" "$2" <<'PY'
import json,sys
p=sys.argv[1]; m=json.load(open(p)); m['anchors']=sys.argv[2]; json.dump(m,open(p,'w'),indent=2)
PY
}
P=$(fresh old1); rm -f "$P/design/question-anchors.json"; mkdir -p "$P/design/old"
cat > "$P/design/old/a.json" <<'J'
{"anchors":[{"id":"F001:Q01","step":"P1-02","basis":"b1"},{"id":"F001:Q02","bucket":"Money"},{"id":"F001:Q03"},{"step":"P1-01"},{"id":"F001:Q05","target":"P1-03"},{"id":"F001:Q06","page":"Order_Overview"}]}
J
echo old-bak > "$P/design/old/a.json.bak"
setanch "$P" design/old/a.json
OUT=$(node "$PM" migrate --project "$P" 2>&1)
has "migrate counts the carried entries" "$OUT" "carried over 4 entries (4 judged)"
has "an entry with no target is reported by id" "$OUT" "F001:Q03"
has "an entry with no id is counted" "$OUT" "1 old entry had no id"
NEW=$(cat "$P/design/question-anchors.json")
has "step key became a step target" "$NEW" '"type": "step"'
has "bucket key became a global target" "$NEW" '"bucket": "Money"'
has "page key became a page target" "$NEW" '"type": "page"'
has "judged is kept" "$NEW" '"anchoredBy": "judged"'
hasnt "the empty entry is not in the new file" "$NEW" "F001:Q03"
NT=$("$PY" -c "
import json;a=json.load(open('$P/design/question-anchors.json'))['anchors']
d={e['id']:e['targets'] for e in a}
print(d['F001:Q01']==[{'type':'step','step':'P1-02'}], d['F001:Q05']==[{'type':'step','step':'P1-03'}], all(isinstance(t,dict) for e in a for t in e['targets']))")
[ "$NT" = "True True True" ] && ok "targets equal the old placements, all objects" || bad "targets equal the old placements" "$NT"
[ -f "$P/design/old/a.json.bak.1" ] && [ "$(cat "$P/design/old/a.json.bak")" = "old-bak" ] && ok "an existing .bak is kept, the new one is .bak.1" || bad "existing .bak kept"
H1=$(cksum "$P/design/question-anchors.json" "$P/design/process-model.json")
OUT2=$(node "$PM" migrate --project "$P" 2>&1)
H2=$(cksum "$P/design/question-anchors.json" "$P/design/process-model.json")
has "second migrate has nothing to do" "$OUT2" "nothing to do"
[ "$H1" = "$H2" ] && ok "second migrate leaves both files byte-identical" || bad "second migrate byte-identical"
A=$(node "$PM" anchor --project "$P" 2>&1)
hasnt "anchor does not count an emptied entry as anchored" "$A" "F001:Q03	"

echo "== migrate: a judged old entry beats a derived current one =="
P=$(fresh coll); mkdir -p "$P/design/old"
node "$PM" anchor --project "$P" >/dev/null 2>&1
DID=$("$PY" -c "
import json;a=json.load(open('$P/design/question-anchors.json'))['anchors']
print([e['id'] for e in a if e['anchoredBy']=='derived'][0])")
cat > "$P/design/old/a.json" <<J
{"anchors":[{"id":"$DID","step":"P1-07","basis":"hand judged"}]}
J
setanch "$P" design/old/a.json
OUT=$(node "$PM" migrate --project "$P" 2>&1)
has "collision is printed" "$OUT" "$DID: the old judged placement replaced the current derived one"
R=$("$PY" -c "
import json;a=json.load(open('$P/design/question-anchors.json'))['anchors']
e=[x for x in a if x['id']=='$DID'][0]
print(e['anchoredBy'], e['targets'][0].get('step'))")
[ "$R" = "judged P1-07" ] && ok "the judged placement won" || bad "the judged placement won" "$R"
P=$(fresh coll2); mkdir -p "$P/design/old"
JID=$("$PY" -c "
import json;print(json.load(open('$P/design/question-anchors.json'))['anchors'][0]['id'])")
cat > "$P/design/old/a.json" <<J
{"anchors":[{"id":"$JID","step":"P1-07"}]}
J
setanch "$P" design/old/a.json; rm "$P/design/question-anchors.json.bak" 2>/dev/null
cp "$FIX/design/question-anchors.json" "$P/design/question-anchors.json"
OUT=$(node "$PM" migrate --project "$P" 2>&1)
has "two judged placements: the current one is kept and the loss is printed" "$OUT" "the current placement is kept"

echo "== migrate: the top-level key is patched, a nested look-alike is not =="
P=$(fresh nest); mkdir -p "$P/design/old"
node "$PM" anchor --project "$P" >/dev/null 2>&1
cp "$P/design/question-anchors.json" "$P/design/old/a.json"; rm "$P/design/question-anchors.json"
"$PY" - "$P/design/process-model.json" <<'PY'
import json,sys
p=sys.argv[1]; m=json.load(open(p)); d={'meta':{'anchors':'notes.txt'}}; d.update(m); d['anchors']='design/old/a.json'; json.dump(d,open(p,'w'),indent=2)
PY
OUT=$(node "$PM" migrate --project "$P" 2>&1)
R=$("$PY" -c "
import json;m=json.load(open('$P/design/process-model.json'))
print(m['anchors'], m['meta']['anchors'])")
[ "$R" = "design/question-anchors.json notes.txt" ] && ok "top-level key changed, nested one untouched" || bad "top-level key changed" "$R"
hasnt "output does not claim only that key changed" "$OUT" "only that key was changed"
has "output says the model was re-written" "$OUT" "re-written with that key set"
P=$(fresh plain); mkdir -p "$P/design/old"
node "$PM" anchor --project "$P" >/dev/null 2>&1
cp "$P/design/question-anchors.json" "$P/design/old/a.json"; rm "$P/design/question-anchors.json"
setanch "$P" design/old/a.json
has "a plain model still claims only the key changed" "$(node "$PM" migrate --project "$P" 2>&1)" "only that key was changed"

echo "== migrate: a string target in an old file is a one-item list =="
P=$(fresh strt); mkdir -p "$P/design/old"; rm -f "$P/design/question-anchors.json"
cat > "$P/design/old/a.json" <<'J'
{"anchors":[{"id":"F001:Q01","targets":"P1-02"}]}
J
setanch "$P" design/old/a.json
OUT=$(node "$PM" migrate --project "$P" 2>&1); RC=$?
[ "$RC" -eq 0 ] && ok "string targets do not crash migrate" || bad "string targets crash migrate" "$OUT"
R=$("$PY" -c "
import json;e=json.load(open('$P/design/question-anchors.json'))['anchors'][0]
print(e['targets'])")
[ "$R" = "[{'type': 'step', 'step': 'P1-02'}]" ] && ok "string target became one step target" || bad "string target became one step target" "$R"

echo "== migrate: unfilled entries in the current file are listed =="
P=$(fresh cur0); mkdir -p "$P/design/old"
node "$PM" anchor --project "$P" >/dev/null 2>&1
"$PY" - "$P/design/question-anchors.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d['anchors'].append({'id':'F001:Q77','kind':'question','targets':[]}); json.dump(d,open(p,'w'))
PY
cat > "$P/design/old/a.json" <<'J'
{"anchors":[{"id":"F001:Q78","step":"P1-02"}]}
J
setanch "$P" design/old/a.json
OUT=$(node "$PM" migrate --project "$P" 2>&1)
has "current-file entry with no targets is named" "$OUT" "in the current anchors file placed nothing and was left out: F001:Q77"

echo "== anchor: a judged entry with empty targets is unanchored, not global =="
P=$(fresh emp)
"$PY" - "$P/design/question-anchors.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d['anchors'].append({'id':'F001:Q04','kind':'question','anchoredBy':'judged','targets':[]}); json.dump(d,open(p,'w'))
PY
A=$(node "$PM" anchor --project "$P" 2>&1)
has "warns that the entry places nothing" "$A" "has no targets"
hasnt "and does not count it as judged" "$A" "3 judged"

echo "== PAGE-MAP.tsv beats the filename stem; a row naming a missing file warns =="
E2="$TMP/pm2"; rm -rf "$E2"; cp -R "$E" "$E2"
sed -i.bak "s/\"useCases\":\[\"[^\"]*\"\]/\"useCases\":[\"$BRDID:$UC\"]/" "$E2/design/process-model.json"
cp "$E2/design/wireframes/order-list-v2.html" "$E2/design/wireframes/Order_Overview.html"
cat > "$E2/design/wireframes/order-list-v2.html" <<'H'
<html><body><h1>Mapped</h1></body></html>
H
printf 'Order_Overview\torder-list-v2.html\nGhost_Page\tnot-there.html\n' > "$E2/design/wireframes/PAGE-MAP.tsv"
node "$PM" build --project "$E2" >"$E2/build.log" 2>&1
has "the PAGE-MAP file wins over a stale stem match" "$(grep -o 'file":"wireframes/[^"]*' "$E2/design/process-map.html" 2>/dev/null | tr '\n' ' ')$(tail -2 "$E2/build.log")" "order-list-v2.html"
hasnt "the stale stem file is not used" "$(grep -o 'file":"wireframes/[^"]*' "$E2/design/process-map.html" 2>/dev/null)" "Order_Overview.html"
V=$(node "$PM" validate --project "$E2" 2>&1)
has "a PAGE-MAP row naming a missing file warns" "$V" 'PAGE-MAP.tsv row "Ghost_Page" names not-there.html'

echo "== CAUSE line for the page-names cause =="
E3="$TMP/pm3"; rm -rf "$E3"; cp -R "$E" "$E3"; rm -f "$E3/design/wireframes/PAGE-MAP.tsv"
"$PY" - "$E3/design/process-model.json" <<'PY'
import json,sys
p=sys.argv[1]; m=json.load(open(p)); st=m['processes'][0]['steps']
for i in range(2,6): st.append({'id':'P1-0%d'%i,'title':'S%d'%i,'lane':'r','page':'Nope_%d'%i})
json.dump(m,open(p,'w'))
PY
V=$(node "$PM" validate --project "$E3" 2>&1)
has "CAUSE line names the page cause" "$V" "CAUSE"
has "and points at PAGE-MAP.tsv or data-mx-page" "$(echo "$V" | grep CAUSE)" "PAGE-MAP"

echo "== template: fit for every overflowing board, hint text, resize =="
T="$(cat "$TOOLKIT/project-bin/process-map.template.html")"
has "embed fits every overflowing board" "$T" "EMBED"
has "the hint says scaled" "$T" "The map is scaled to fit the page."
has "the hint says split above 12" "$T" "split it in two."
has "sideways is only for the zoom floor" "$T" "Scroll sideways to follow the process."
has "fit re-runs when the wrap resizes" "$T" "ro.observe(wrap)"

printf '\n%s: %d ok, %d FAIL\n' "$(basename "$0")" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
