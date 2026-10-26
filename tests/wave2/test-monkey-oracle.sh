#!/usr/bin/env bash
# Usage: bash test-monkey-oracle.sh [path-to-monkey.js]
#
# Fixture for project-tests/e2e/monkey.js's crash bucket: what it may count as crash-class.
# No browser, no app: the exported functions run against stand-in elements and pages, so the
# fixture runs wherever node does.
#
#   #544  typeSafely() cuts a payload to the box's maxLength, as a user's typing does. A script
#         write skipped maxlength: 5000 characters into a String(200) box gave HTTP 560 on every
#         capped box, filed crash-class, though no user can reach it.

set -uo pipefail

SUT="${1:-}"
[ -z "$SUT" ] && SUT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/project-tests/e2e/monkey.js"
if [ ! -f "$SUT" ]; then
  echo "SKIP: subject not found at $SUT"
  echo "SCORE: 0/0 — nothing to test"
  exit 0
fi
command -v node >/dev/null 2>&1 || { echo "SKIP: node not installed"; exit 0; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
E2E="$(cd "$(dirname "$SUT")" && pwd)"
CFG="$E2E/project.config.template.js"
[ -f "$CFG" ] || CFG="$HERE/../../project-tests/e2e/project.config.template.js"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ -n "${2:-}" ] && echo "         got: $2"; }

# monkey.js resolves a project at require time: an .mpr two levels up and an asserted port.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/monkey-oracle.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/tests/e2e"; : > "$WORK/Fixture.mpr"
cp "$SUT" "$E2E/helpers.js" "$E2E/otel.js" "$E2E/config.js" "$WORK/tests/e2e/"
cp "$CFG" "$WORK/tests/e2e/project.config.js"

IFS= read -r -d '' JS <<'JSEOF' || true
const M = require('./monkey.js');
const out = (k, v) => console.log(`${k} ${JSON.stringify(v)}`);
(async () => {
  // #544 — a stand-in input: maxLength as the DOM reports it (-1 when the attribute is absent).
  class Input { constructor(max) { this.maxLength = max; this.v = ''; this.ev = []; }
                get value() { return this.v; } set value(x) { this.v = x; }
                dispatchEvent(e) { this.ev.push(e.type); } }
  const handle = el => ({ evaluate: (fn, arg) => Promise.resolve(fn(el, arg)) });
  if (typeof M.typeSafely !== 'function') out('TS', 'NOFN');
  else {
    const capped = new Input(200), free = new Input(-1), cjk = new Input(5), short = new Input(10);
    const c1 = await M.typeSafely(null, handle(capped), 'A'.repeat(5000));
    const c2 = await M.typeSafely(null, handle(free), 'A'.repeat(5000));
    const c3 = await M.typeSafely(null, handle(cjk), '倉庫管理システ');
    const c4 = await M.typeSafely(null, handle(short), 'abc');
    out('TS', { c1, l1: capped.v.length, ev: capped.ev, c2, l2: free.v.length, c3, v3: cjk.v, c4, v4: short.v });
  }
  process.exit(0);
})();
JSEOF
OUT="$(cd "$WORK/tests/e2e" && printf '%s' "$JS" | APP_PORT=1 timeout 60 node - 2>&1)"
get() { printf '%s\n' "$OUT" | sed -n "s/^$1 //p"; }
j() { printf '%s' "$(get "$1")" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const o=JSON.parse(s);console.log(String(eval("o."+process.argv[1])))}catch(e){console.log("ERR")}})' "$2"; }

if [ -z "$(get TS)" ] || [ "$(get TS)" = '"NOFN"' ]; then
  bad "monkey.js exports no typeSafely (#544)" "$(printf '%s\n' "$OUT" | tail -3)"
else
  [ "$(j TS c1)" = 200 ] && [ "$(j TS l1)" = 200 ] && ok "#544 a 5000-char payload into a maxlength=200 box is cut to 200, and the cap is returned" \
    || bad "#544 payload not cut to maxLength — a capped box yields an unreachable HTTP 560" "$(get TS)"
  [ "$(j TS 'ev.join()')" = "input,change" ] && ok "#544 the input and change events still fire" || bad "#544 events lost" "$(get TS)"
  [ "$(j TS c2)" = 0 ] && [ "$(j TS l2)" = 5000 ] && ok "#544 a box with no maxlength still gets the whole payload (the case a user can reach)" \
    || bad "#544 an uncapped box was cut" "$(get TS)"
  [ "$(j TS c3)" = 5 ] && [ "$(j TS v3)" = "倉庫管理シ" ] && ok "#544 the cut counts UTF-16 code units, like maxlength and the server" \
    || bad "#544 CJK cut wrong" "$(get TS)"
  [ "$(j TS c4)" = 0 ] && [ "$(j TS v4)" = abc ] && ok "#544 a payload under the cap is untouched and reports no cut" || bad "#544 short payload altered" "$(get TS)"
fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
