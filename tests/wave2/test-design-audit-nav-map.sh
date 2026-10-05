#!/usr/bin/env bash
# Usage: bash test-design-audit-nav-map.sh [path-to-design-audit.js]
#
# Fixture for project-tests/e2e/design-audit.js's navigation map (parseNavigation) — the route
# table rung 7 (a11y, overflow, structure) uses to reach each page in the running app. A page
# with no route is a FAULT row "this check never ran", so a parser that misses items silently
# turns the whole runtime rung into faults.
#
# The defect (card-disbursement requirements-driven build, 2026-09-26): the item regex required
# `;` straight after the page name. Real `describe navigation` output puts `icon <ref>` there
# (and `icon <ref>` before the `(` of a group), so 0 of 4 menu pages were routed and rung 7 ran
# on none of 7 in-scope pages.
#
# Golden input is a VERBATIM capture (fixtures/design-audit-nav/). The last case is SYNTHETIC and
# marked: an icon-less item and a microflow item, the shapes the capture lacks.
#
# mxcli v0.25.0 (2026-10-05) changed the shape: `menu 'G' ( Icon: I ) { … }` and
# `menu item 'X' ( OnClick: show page M.P, Icon: I )`, under `--mdl 0` too. The old regexes routed
# 0 pages from it. A second verbatim capture (…-v025.txt, mxcli's public test app) pins the new
# shape; both must keep parsing, since projects run either mxcli. page-audit.js carries the same
# function (navMapFromModel), so every case runs against both files.

set -uo pipefail

SUT="${1:-}"
[ -z "$SUT" ] && SUT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/project-tests/e2e/design-audit.js"
if [ ! -f "$SUT" ]; then
  echo "SKIP: subject not found at $SUT"
  echo "SCORE: 0/0 — nothing to test"
  exit 0
fi
command -v node >/dev/null 2>&1 || { echo "SKIP: node not installed"; exit 0; }
FIX="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/design-audit-nav"
GOLDEN="$FIX/describe-navigation-responsive.txt"
GOLDEN25="$FIX/describe-navigation-responsive-v025.txt"
for g in "$GOLDEN" "$GOLDEN25"; do [ -f "$g" ] || { echo "FAIL — golden capture missing: $g"; exit 1; }; done

# design-audit.js runs on load, so lift the function out of its text instead of requiring it.
IFS= read -r -d '' JS <<'JS' || true
const fs = require('fs');
const [sut, golden, golden25] = process.argv.slice(2);
const js = fs.readFileSync(sut, 'utf8');
const i = js.indexOf('function parseNavigation(');
if (i < 0) { console.log('LIFT-FAIL parseNavigation'); process.exit(3); }
let d = 0, j = js.indexOf('{', i);
for (; j < js.length; j++) { if (js[j] === '{') d++; else if (js[j] === '}' && --d === 0) break; }
const parse = new Function(`${js.slice(i, j + 1)}\nreturn parseNavigation;`)();
const show = (label, txt) => {
  const m = parse(txt);
  console.log(`${label} n=${m.size} ` + [...m].map(([k, v]) => `${k}=${v.group}>${v.item}`).join(' | '));
};
show('GOLDEN', fs.readFileSync(golden, 'utf8'));
// SYNTHETIC — shapes the capture does not carry.
show('SYN', "  menu 'Ops' (\n    menu item 'Plain' page Mod.Plain_Page;\n    menu item 'Run' microflow Mod.ACT_Run icon Atlas_Core.Atlas.play;\n  );\n");
show('GOLDEN25', fs.readFileSync(golden25, 'utf8'));
// SYNTHETIC — v0.25 shapes the capture does not carry: a page item inside a group, a property-less
// nested group (`menu 'Sub' {`), and an item after the nested group closes.
show('SYN25', "{\n  menu 'Ops' ( Icon: Atlas_Core.Atlas.cog ) {\n    menu item 'Plain' ( OnClick: show page Mod.Plain_Page )\n    menu 'Sub' {\n      menu item 'Deep' ( OnClick: show page Mod.Deep_Page with (DisabledDuringExecution: false), Icon: glyph 57377 )\n    }\n    menu item 'Run' ( OnClick: call microflow Mod.ACT_Run, Icon: Atlas_Core.Atlas.play )\n  }\n};\n");
JS
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ -n "${2:-}" ] && echo "         got: $2"; }

TWIN="$(dirname "$SUT")/page-audit.js"
for F in "$SUT" "$TWIN"; do
[ -f "$F" ] || { echo "  skip — $(basename "$F") not beside the subject"; continue; }
echo "-- $(basename "$F")"
OUT="$(printf '%s' "$JS" | node - "$F" "$GOLDEN" "$GOLDEN25")"
rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL — harness could not load parseNavigation from $F (rc=$rc)"; echo "$OUT"; exit 1; }
G="$(printf '%s\n' "$OUT" | sed -n 's/^GOLDEN //p')"
S="$(printf '%s\n' "$OUT" | sed -n 's/^SYN //p')"
G25="$(printf '%s\n' "$OUT" | sed -n 's/^GOLDEN25 //p')"
S25="$(printf '%s\n' "$OUT" | sed -n 's/^SYN25 //p')"

case "$G" in n=4\ *) ok "golden capture routes all 4 menu pages (the 2026-09-26 zero)";; *) bad "golden capture: want n=4" "$G";; esac
case "$G" in *"Disbursement.Case_Overview=Work>Cases"*) ok "quoted icon ref (\"list-bullets\") does not break the item";; *) bad "Case_Overview route wrong" "$G";; esac
case "$G" in *"MockServices.MockConsole_Overview=Configure>Mock console"*) ok "group caption read past its icon clause";; *) bad "group with icon not read" "$G";; esac
case "$G" in *"MyFirstModule.Home_Web=Work>Home"*) ok "item routed under its own group, not the previous one";; *) bad "Home_Web route wrong" "$G";; esac
case "$S" in *"Mod.Plain_Page=Ops>Plain"*) ok "icon-less item still parses (synthetic)";; *) bad "icon-less item regressed" "$S";; esac
case "$S" in *"microflow:Mod.ACT_Run=Ops>Run"*) ok "microflow item with icon parses (synthetic)";; *) bad "microflow item missed" "$S";; esac
case "$G25" in n=3\ *) ok "v0.25 capture: 2 pages + 1 microflow routed (old regexes: 0)";; *) bad "v0.25 capture: want n=3" "$G25";; esac
case "$G25" in *"Pages.EditableLIstView=null>Editable listview"*) ok "v0.25 icon-less show-page item parses";; *) bad "EditableLIstView route wrong" "$G25";; esac
case "$G25" in *"MyFirstModule.Home_Web=null>Item 2"*) ok "v0.25 '}' closes group 'Item 0' (the next item is top-level again)";; *) bad "group not closed by '}'" "$G25";; esac
case "$G25" in *"microflow:MyFirstModule.MyFirstLogic=null>Item 3"*) ok "v0.25 call-microflow item parses";; *) bad "call microflow item missed" "$G25";; esac
case "$S25" in *"Mod.Plain_Page=Ops>Plain"*) ok "v0.25 item routed under its group (synthetic)";; *) bad "v0.25 grouped item wrong" "$S25";; esac
case "$S25" in *"Mod.Deep_Page=Sub>Deep"*) ok "v0.25 nested property-less group + 'with (…)' action (synthetic)";; *) bad "v0.25 nested group wrong" "$S25";; esac
case "$S25" in *"microflow:Mod.ACT_Run=Ops>Run"*) ok "v0.25 after nested '}' the outer group is current again (synthetic)";; *) bad "v0.25 group stack wrong" "$S25";; esac
done

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
