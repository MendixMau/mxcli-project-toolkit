#!/usr/bin/env bash
# Usage: bash test-design-audit-css-corpus.sh [path-to-design-audit.js]
#
# Fixture for project-tests/e2e/design-audit.js's defined-class corpus (classesInCss) — the set
# every rung-6/7 class verdict (invented, unmatched, never-promoted) is measured against.
#
# The defect (card-disbursement requirements-driven build, 2026-09-26): the harvester read
# selectors at brace depth 0 only. Atlas emits `spacing-outer-bottom-large` ONLY inside three
# breakpoint @media blocks, so the audit called it "invented" on every page that used it — the
# very class skills/design-spacing.md prescribes for section rhythm. Same blind spot for any
# rule under @supports / @layer.
#
# Golden input is a VERBATIM capture of a real mxbuild theme.compiled.css
# (fixtures/design-audit-css/theme-excerpt.css — header says where from). It carries the real
# traps next to the defect: a url("./fonts/….ttf") in @font-face, @keyframes percent selectors,
# a multi-line depth-0 selector list. The two synthetic cases at the end are marked as such:
# they guard declaration values (quoted dots, a brace inside a string) that the capture lacks.

set -uo pipefail

SUT="${1:-}"
[ -z "$SUT" ] && SUT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/project-tests/e2e/design-audit.js"
if [ ! -f "$SUT" ]; then
  echo "SKIP: subject not found at $SUT"
  echo "SCORE: 0/0 — nothing to test"
  exit 0
fi
command -v node >/dev/null 2>&1 || { echo "SKIP: node not installed"; exit 0; }
GOLDEN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/design-audit-css/theme-excerpt.css"
[ -f "$GOLDEN" ] || { echo "FAIL — golden capture missing: $GOLDEN"; exit 1; }

# design-audit.js runs on load, so lift the two functions out of its text instead of requiring it.
OUT="$(node - "$SUT" "$GOLDEN" <<'EOF'
const fs = require('fs');
const [sut, golden] = process.argv.slice(2);
const js = fs.readFileSync(sut, 'utf8');
const lift = (name) => {
  const i = js.indexOf(`function ${name}(`);
  if (i < 0) { console.log(`LIFT-FAIL ${name}`); process.exit(3); }
  let d = 0, j = js.indexOf('{', i);
  for (; j < js.length; j++) { if (js[j] === '{') d++; else if (js[j] === '}' && --d === 0) break; }
  return js.slice(i, j + 1);
};
const classesInCss = new Function(`${lift('harvest')}\n${lift('classesInCss')}\nreturn classesInCss;`)();
const show = (label, text) => console.log(`${label} ${[...classesInCss(text)].sort().join(' ')}`);
show('GOLDEN', fs.readFileSync(golden, 'utf8'));
// SYNTHETIC — declaration values the golden capture does not carry.
show('SYN-QUOTED', '.real { content: ".not-a-class"; background: url(\'img/x.png\'); }');
show('SYN-BRACE', '.a { content: "{"; } .b { color: red; }');
EOF
)"
rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL — harness could not load classesInCss from $SUT (rc=$rc)"; echo "$OUT"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ -n "${2:-}" ] && echo "         got: $2"; }
line() { printf '%s\n' "$OUT" | sed -n "s/^$1 //p"; }
has()  { printf ' %s ' "$(line "$1")" | grep -q " $2 "; }

G="$(line GOLDEN)"
if has GOLDEN spacing-outer-bottom-large; then ok "class defined only inside @media is in the corpus (the 2026-09-26 false 'invented')"
else bad "@media-only class missing from the corpus" "$G"; fi
if has GOLDEN mx-menubar; then ok "class defined inside @supports is in the corpus"
else bad "@supports class missing" "$G"; fi
if has GOLDEN mx-datagrid-table-resizing; then ok "depth-0 multi-line selector list still harvested"
else bad "depth-0 selector regressed" "$G"; fi
if has GOLDEN ttf || has GOLDEN fonts; then bad "url() fragment in @font-face harvested as a class" "$G"
else ok "url(\"./fonts/….ttf\") in @font-face defines no class"; fi
n=$(printf '%s\n' "$G" | wc -w | tr -d ' ')
[ "$n" -eq 3 ] && ok "golden capture yields exactly 3 classes (no at-rule prelude or keyframe step leaked)" \
  || bad "golden capture yields $n classes, want 3" "$G"

S="$(line SYN-QUOTED)"
[ "$S" = "real" ] && ok "quoted dot and url() in declaration values define nothing (synthetic)" || bad "declaration value leaked" "$S"
S="$(line SYN-BRACE)"
[ "$S" = "a b" ] && ok "a brace inside a string does not open a rule (synthetic)" || bad "string brace mis-parsed" "$S"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
