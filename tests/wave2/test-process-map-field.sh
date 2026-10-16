#!/bin/bash
# test-process-map-field.sh: pin the field-run fixes of process-map.js (2026-10-16): anchors migration,
# the carried-over report of anchor, long processes, BRD discovery in an existing app's layout,
# PAGE-MAP.tsv page resolution, and the one-line cause summary of validate. Neutral names only.
set -u
TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
PM="$TOOLKIT/project-bin/process-map.js"
FIX="$TOOLKIT/tests/wave2/fixtures/process-map"
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
python3 - "$P/design/process-model.json" <<'PY'
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
python3 - "$L" <<'PY'
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
BRDID=$(python3 -c "import json,glob;print(json.load(open(glob.glob('$E/analysis/knowledge-base/brd/*.json')[0]))['id'])")
UC=$(python3 -c "import json,glob;print(json.load(open(glob.glob('$E/analysis/knowledge-base/brd/*.json')[0]))['useCases'][0]['id'])")
cat > "$E/design/wireframes/order-list-v2.html" <<'H'
<html><body><h1>Orders</h1></body></html>
H
cat > "$E/design/wireframes/index.html" <<'H'
<html><body><h1>Index</h1></body></html>
H
printf 'Order_Overview\torder-list-v2.html\n' > "$E/design/wireframes/PAGE-MAP.tsv"
STAND=$(python3 -c "import json,glob;d=json.load(open(glob.glob('$E/analysis/knowledge-base/brd/*.json')[0]));print(json.dumps([{'useCase':'%s:%s'%(d['id'],u['id']),'reason':'n/a'} for u in d['useCases'][1:]]))")
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
python3 - "$TMP/nobrd/design/process-model.json" <<'PY'
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

printf '\n%s: %d ok, %d FAIL\n' "$(basename "$0")" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
