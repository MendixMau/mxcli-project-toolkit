#!/usr/bin/env bash
# Usage: bash test-design-audit-a11y-evidence.sh [path-to-design-audit.js]
#
# Fixture for #561: design-audit.js rung 7's accessibility row must say WHICH element failed.
# It reported `button-name(critical,x1)` with `evidence: []`, though axe returns each failing
# node's selector and opening tag, so the widget had to be found with a hand probe.
#
# Golden input is CAPTURED: fixtures/design-audit-a11y/axe-run-4.10.2.json is axe-core 4.10.2's
# own result (Playwright chromium) over a page shaped like a Mendix data-grid page — an icon-only
# action button carrying mx-name-actionButton3, an empty Data Grid 2 load-more button with no
# mx-name of its own, an image without alt. The page is synthetic; the axe output is not.

set -uo pipefail

SUT="${1:-}"
[ -z "$SUT" ] && SUT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/project-tests/e2e/design-audit.js"
if [ ! -f "$SUT" ]; then
  echo "SKIP: subject not found at $SUT"
  echo "SCORE: 0/0 — nothing to test"
  exit 0
fi
command -v node >/dev/null 2>&1 || { echo "SKIP: node not installed"; exit 0; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GOLDEN="$HERE/fixtures/design-audit-a11y/axe-run-4.10.2.json"
[ -f "$GOLDEN" ] || { echo "FAIL — golden capture missing: $GOLDEN"; exit 1; }
RENDER="$(dirname "$SUT")/report-render.js"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ -n "${2:-}" ] && echo "         got: $2"; }

# design-audit.js runs on load, so lift the functions out of its text instead of requiring it.
IFS= read -r -d '' JS <<'JSEOF' || true
const fs = require('fs');
const [sut, golden] = process.argv.slice(2);
const js = fs.readFileSync(sut, 'utf8');
const lift = (name) => {
  const i = js.indexOf(`function ${name}(`);
  if (i < 0) return null;
  let d = 0, j = js.indexOf('{', js.indexOf(')', i));
  for (; j < js.length; j++) { if (js[j] === '{') d++; else if (js[j] === '}' && --d === 0) break; }
  return js.slice(i, j + 1);
};
const src = [lift('checkA11y'), lift('a11yEvidence')];
if (!src[0]) { console.log('LIFT-FAIL checkA11y'); process.exit(0); }
if (!src[1]) { console.log('NOFN'); process.exit(0); }
const { checkA11y, a11yEvidence } = new Function(`${src[0].replace(/^function/, 'async function')}\n${src[1]}\nreturn { checkA11y, a11yEvidence };`)();
const cap = JSON.parse(fs.readFileSync(golden, 'utf8'));
let calls = 0;
const page = { evaluate: async () => (++calls === 1 ? undefined : cap) };   // 1: inject axe, 2: axe.run
(async () => {
  const a = await checkA11y(page, '/* axe */');
  const ev = a11yEvidence(a.items);
  console.log('SUM ' + JSON.stringify({ serious: a.seriousOrCritical, tested: a.testedRules }));
  for (const e of ev) console.log('EV ' + JSON.stringify(e));
  console.log('EMPTY ' + JSON.stringify(a11yEvidence([])));
})();
JSEOF
OUT="$(printf '%s' "$JS" | timeout 30 node - "$SUT" "$GOLDEN" 2>&1)"
if printf '%s\n' "$OUT" | grep -q '^LIFT-FAIL'; then bad "checkA11y not found in $SUT" "$OUT"; echo "PASS=$PASS FAIL=$FAIL"; exit 1; fi
if printf '%s\n' "$OUT" | grep -qx NOFN; then
  bad "#561 no a11yEvidence(): the a11y row carries no element evidence"; echo ""; echo "PASS=$PASS FAIL=$FAIL"; exit 1
fi
ev() { printf '%s\n' "$OUT" | grep '^EV ' | sed 's/^EV //'; }
q() { ev | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const r=s.trim().split("\n").map(JSON.parse);console.log(String(eval(process.argv[1])))})' "$1"; }

[ "$(printf '%s\n' "$OUT" | sed -n 's/^SUM //p')" = '{"serious":2,"tested":10}' ] && ok "the captured run reads 2 serious/critical rules over 10 (summary unchanged)" \
  || bad "captured summary changed" "$(printf '%s\n' "$OUT" | sed -n 's/^SUM //p')"
[ "$(q 'r.length')" = 3 ] && ok "one evidence entry per failing node (2 button-name + 1 image-alt)" || bad "wrong evidence count" "$(ev)"
[ "$(q 'r.filter(e=>e.rule==="button-name").map(e=>e.widget).join()')" = "mx-name-actionButton3," ] \
  && ok "the icon-only button's mx-name-actionButton3 is lifted from its tag; the load-more button has none and says so (null)" \
  || bad "mx-name widget not lifted from the captured html" "$(ev)"
[ "$(q 'r.map(e=>e.target).join("|")')" = ".mx-button|.btn-primary|img" ] && ok "axe's selector is carried for every node" || bad "selectors lost" "$(ev)"
[ "$(q 'r.every(e=>e.type==="selector" && e.help && /^https:/.test(e.helpUrl) && e.html.length<=120)')" = true ] \
  && ok "each entry is type selector with help text, help URL and the opening tag cut to 120 chars" || bad "entry shape" "$(ev)"
[ "$(printf '%s\n' "$OUT" | sed -n 's/^EMPTY //p')" = '[]' ] && ok "no violations → no evidence entries" || bad "empty case" "$OUT"
awk '/id: `design-audit\/rung7\/a11y\//{r=1} r&&/evidence: a\.items\.length/{f=1} r&&/a11yEvidence\(a\.items\)/{g=1} END{exit !(f&&g)}' "$SUT" \
  && ok "the rung 7 a11y row uses a11yEvidence() (the tested function is the one that runs)" || bad "the a11y row does not carry a11yEvidence()"
if [ -f "$RENDER" ]; then
  grep -q 'else if (has(e.target))' "$RENDER" && ok "report-render.js shows a selector entry (rule, widget, selector, tag), not 'NO POINTER'" \
    || bad "report-render.js renders a selector entry as NO POINTER"
fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
