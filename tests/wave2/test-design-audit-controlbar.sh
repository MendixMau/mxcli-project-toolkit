#!/usr/bin/env bash
# Usage: bash test-design-audit-controlbar.sh [path-to-design-audit.js]
#
# Fixture: design-audit.js's #891 guard names the data grid control bar mxcli actually writes.
#
# The defect (field run 2026-11-20, a real Mendix 11.8 app): readCompleteness() looked for
# `controlbar <name>`, but mxcli writes a DataGrid2 control bar unnamed — `controlbar {`. On a
# grid with New/Edit buttons the guard rightly FAULTed the page (2 buttons unread), yet its
# message said "controlbars: none" while the unread buttons were the control bar's. The verdict
# was right; the explanation pointed away from the cause.
#
# Golden input is CAPTURED: fixtures/design-audit-controlbar/elk-Task_Overview-mx11.8.json is
# `mxcli -p <mpr> describe --format elk page Tasks.Task_Overview` (mxcli v0.32, Mendix 11.8.0)
# from that app, verbatim — the exact command design-audit.js runs.

set -uo pipefail

SUT="${1:-}"
[ -z "$SUT" ] && SUT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/project-tests/e2e/design-audit.js"
[ -f "$SUT" ] || { echo "SKIP: subject not found at $SUT"; exit 0; }
command -v node >/dev/null 2>&1 || { echo "SKIP: node not installed"; exit 0; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GOLDEN="$HERE/fixtures/design-audit-controlbar/elk-Task_Overview-mx11.8.json"
[ -f "$GOLDEN" ] || { echo "FAIL — golden capture missing: $GOLDEN"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ -n "${2:-}" ] && echo "         got: $2"; }

# design-audit.js runs on load, so lift the functions out of its text instead of requiring it.
IFS= read -r -d '' JS <<'JSEOF' || true
const fs = require('fs');
const [sut, golden] = process.argv.slice(1);
const js = fs.readFileSync(sut, 'utf8');
// To the top-level closing `}` line: brace counting is fooled by the `\\{` inside the guard's own regex.
const lift = (name) => {
  const i = js.indexOf(`\nfunction ${name}(`);
  if (i < 0) return null;
  const j = js.indexOf('\n}\n', i);
  return j < 0 ? null : js.slice(i + 1, j + 2);
};
const names = ['walkElk', 'mdlWidgetInstances', 'readCompleteness'];
const src = names.map(lift);
if (src.some((x) => !x)) { console.log('LIFT-FAIL ' + names.filter((n, i) => !src[i]).join(',')); process.exit(0); }
// mdlWidgetInstances reads the file's own MDL_NON_WIDGET_TYPES set; lift that verbatim too.
const ci = js.indexOf('const MDL_NON_WIDGET_TYPES');
const consts = ci < 0 ? 'const MDL_NON_WIDGET_TYPES = new Set();' : js.slice(ci, js.indexOf(']);', ci) + 3);
const { readCompleteness } = new Function(`${consts}\n${src.join('\n')}\nreturn { readCompleteness };`)();
const doc = JSON.parse(fs.readFileSync(golden, 'utf8'));
const r = readCompleteness(doc);
console.log('PARTIAL ' + r.partial);
console.log('UNREAD ' + r.unread.join(','));
console.log('BARS ' + r.controlbars.length + '|' + r.controlbars.join(','));
// A named control bar (older MDL shape) still reports its name.
const named = readCompleteness({ root: doc.root, mdlSource: doc.mdlSource.replace('controlbar {', 'controlbar cbTasks {') });
console.log('NAMED ' + named.controlbars.join(','));
// A page without a control bar reports none; `controlbar` inside another word is not one.
const none = readCompleteness({ root: doc.root, mdlSource: "create page M.P (Title: 'x') {\n  container cnt (Class: 'mycontrolbar') {\n  }\n};" });
console.log('NONE ' + none.controlbars.length);
JSEOF
OUT="$(node -e "$JS" "$SUT" "$GOLDEN" 2>&1)"
line() { printf '%s\n' "$OUT" | sed -n "s/^$1 //p"; }
if printf '%s\n' "$OUT" | grep -q '^LIFT-FAIL'; then bad "could not lift the guard from design-audit.js" "$OUT"; else
  [ "$(line PARTIAL)" = true ] && ok "the captured page is partially read (verdict unchanged)" || bad "partial" "$OUT"
  printf '%s' "$(line UNREAD)" | grep -q 'btnNew' && ok "the unread widgets are the control bar's buttons" || bad "unread" "$(line UNREAD)"
  case "$(line BARS)" in
    1\|*unnamed*) ok "the unnamed \`controlbar {\` mxcli writes is reported: $(line BARS | cut -d'|' -f2)" ;;
    *) bad "the unnamed control bar is not reported (message would say 'controlbars: none')" "$(line BARS)" ;;
  esac
  [ "$(line NAMED)" = cbTasks ] && ok "a named control bar still reports its name" || bad "named control bar" "$(line NAMED)"
  [ "$(line NONE)" = 0 ] && ok "no control bar → none; a class value containing 'controlbar' is not one" || bad "false control bar" "$(line NONE)"
fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
