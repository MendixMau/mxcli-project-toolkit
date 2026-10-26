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
#   #562  a spinner still up after 8 s goes in `slow`, not crash-class: it is none of the four
#         crash signals monkey-test.md defines. A ~10 s batch job that then succeeded failed a run.
#   #563  land() reports a target whose menu item navTo cannot find as not reached. It swallowed
#         the throw and asked only "is some .mx-page visible?" — the previous target's page always
#         was, so a target not in the app was fuzzed on another page, findings under its name.

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
    const c3 = await M.typeSafely(null, handle(cjk), '\u5009\u5eab\u7ba1\u7406\u30b7\u30b9\u30c6');
    const c4 = await M.typeSafely(null, handle(short), 'abc');
    out('TS', { c1, l1: capped.v.length, ev: capped.ev, c2, l2: free.v.length, c3,
                v3: cjk.v === '\u5009\u5eab\u7ba1\u7406\u30b7', c4, v4: short.v });
  }
  // #562 — a stand-in page: which selectors are visible, and no real waiting. No Jaeger: the
  // OTel arm returns no spans (the traceRan flag reports that, as in a real run).
  require('./otel.js').capture = async () => [];
  const page = vis => ({ locator: sel => ({ first: () => ({ isVisible: async () => !!vis[sel] }) }),
                         waitForTimeout: async () => {} });
  const B = (js = [], h = []) => ({ jsErrors: js, http5xx: h });
  if (typeof M.oracle !== 'function') out('OR', 'NOFN');
  else {
    const P = '.mx-page, .mx-navigationtree', S = '.mx-progress, .mx-dialog-progress';
    const spin = await M.oracle(page({ [P]: true, [S]: true }), 0, B());
    const spin5 = await M.oracle(page({ [P]: true, [S]: true }), 0, B([], ['560 http://x/xas/']));
    const clean = await M.oracle(page({ [P]: true }), 0, B());
    const blank = await M.oracle(page({}), 0, B());
    out('OR', { spinHits: spin.hits, spinSlow: spin.slow, s5Hits: spin5.hits.length, s5Slow: spin5.slow.length,
                cleanHits: clean.hits.length, cleanSlow: (clean.slow || []).length, blankHits: blank.hits });
  }
  // #563 — navTo throws for an absent menu item (helpers.js, #412); the previous page stays open.
  if (typeof M.land !== 'function') out('LD', 'NOFN');
  else {
    const H = require('./helpers.js');
    const open = { url: () => 'http://localhost:1/p/real', goto: async () => {}, waitForTimeout: async () => {},
                   locator: () => ({ first: () => ({ isVisible: async () => true }) }) };
    H.navTo = async () => { throw new Error('navigation item "Ghost" not found for demo_user; visible: Real\n  at navTo'); };
    const ghost = await M.land(open, 'Group', 'Ghost');
    H.navTo = async () => {};
    const real = await M.land(open, null, 'Real');
    const gone = await M.land({ ...open, locator: () => ({ first: () => ({ isVisible: async () => false }) }) }, null, 'Real');
    out('LD', { ghost, real, gone });
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
  [ "$(j TS c3)" = 5 ] && [ "$(j TS v3)" = true ] && ok "#544 the cut counts UTF-16 code units, like maxlength and the server" \
    || bad "#544 CJK cut wrong" "$(get TS)"
  [ "$(j TS c4)" = 0 ] && [ "$(j TS v4)" = abc ] && ok "#544 a payload under the cap is untouched and reports no cut" || bad "#544 short payload altered" "$(get TS)"
fi

if [ -z "$(get OR)" ] || [ "$(get OR)" = '"NOFN"' ]; then
  bad "monkey.js exports no oracle (#562)" "$(printf '%s\n' "$OUT" | tail -3)"
else
  [ "$(j OR 'spinHits.length')" = 0 ] && [ "$(j OR 'spinSlow.join()')" = "spinner still up after 8s" ] \
    && ok "#562 a spinner still up after 8 s is slow, not crash-class" || bad "#562 a long spinner is still a crash" "$(get OR)"
  [ "$(j OR s5Hits)" = 1 ] && ok "#562 a 5xx in the same round is still crash-class" || bad "#562 5xx lost" "$(get OR)"
  [ "$(j OR cleanHits)" = 0 ] && [ "$(j OR cleanSlow)" = 0 ] && ok "#562 a clean page gives neither" || bad "#562 clean page flagged" "$(get OR)"
  [ "$(j OR 'blankHits.join()')" = "blank page — no .mx-page or nav tree" ] && ok "#562 a blank page stays crash-class (unchanged)" \
    || bad "#562 blank page handling changed" "$(get OR)"
fi
grep -q "finding('slow'" "$SUT" && awk '/process\.exit\(crashes\.length/ {f=1} END{exit !f}' "$SUT" \
  && ok "#562 round() files slow as its own severity; the exit code counts crash-class only" \
  || bad "#562 round() does not file slow, or the exit code changed"

if [ -z "$(get LD)" ] || [ "$(get LD)" = '"NOFN"' ]; then
  bad "monkey.js exports no land (#563)" "$(printf '%s\n' "$OUT" | tail -3)"
else
  [ "$(j LD ghost)" = 'navigation item "Ghost" not found for demo_user; visible: Real' ] \
    && ok "#563 a target navTo cannot find is not reached, with navTo's reason (first line), though another page is open" \
    || bad "#563 a missing menu item counts as reached — fuzzed on the previous target's page" "$(get LD)"
  [ "$(j LD real)" = "" ] && ok "#563 a target that lands returns no reason" || bad "#563 a landed target reads as missed" "$(get LD)"
  [ "$(j LD gone)" = "no .mx-page visible after navigation" ] && ok "#563 no page after a clean navTo is still not reached" || bad "#563 no-page case" "$(get LD)"
fi
grep -q 'const miss = await land(' "$SUT" && grep -q '&& (await land(page, group, item))) {' "$SUT" && grep -q 'reached ${targets.length - unreached.length} of ${targets.length}' "$SUT" \
  && ok "#563 main and the re-land read land()'s reason; the summary prints reached r of t" \
  || bad "#563 a caller still reads land() as a boolean, or the summary has no reached count"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
