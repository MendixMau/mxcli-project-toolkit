#!/usr/bin/env bash
# Usage: bash tests/wave2/test-obligation-quality-floor.sh /path/to/bin/gate-check.sh
#   (bin/lib/obligation-check.sh is derived from its directory)
#
# The quality floor: no per-module obligation reads PASS by absence. Two field runs (2026-11,
# unattended, requirements-driven, several Mendix apps in one repo under apps/<App>/) skipped
# stages 1-4, so no module brief and no build plan existed; about 78 pages were built and 0
# reviewed, and gate-check printed
#     Obligation look  PASS — no module has been opened for work yet; nothing owed
# for look, fidelity, sweep and journeys. With no planned scope, the built scope is now owed.
#
# Layout: apps/<App>/<App>.mpr + apps/<App>/mdlsource/*.mdl, no architecture/, no build plan —
# the shape of field run 1. The page scripts are the repo's captured page scripts
# (fixtures/page-fidelity-mocks/demo-*.mdl) under the apps' module names.
#
# Positive control: against master's obligation-check.sh, T1 (look PASS by absence) and T5 fail.
set -uo pipefail
GATE="${1:?usage: test-obligation-quality-floor.sh /path/to/bin/gate-check.sh}"
GATE="$(cd "$(dirname "$GATE")" && pwd)/$(basename "$GATE")"
OBCHECK="$(dirname "$GATE")/lib/obligation-check.sh"
[ -r "$OBCHECK" ] || { echo "no obligation-check.sh at $OBCHECK"; exit 2; }
HERE="$(cd "$(dirname "$0")" && pwd)"
CAP="$HERE/fixtures/page-fidelity-mocks"
[ -r "$CAP/demo-list.mdl" ] && [ -r "$CAP/demo-overview.mdl" ] || { echo "captured page scripts missing under $CAP"; exit 2; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ob-floor.XXXXXX")"
trap '[ -n "${KEEP:-}" ] || rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

register() { printf 'Toolkit commit: none\n\n| Stage | Decision | Status | Notes |\n|---|---|---|---|\n' > "$1/PROJECT.md"; }
# A captured page script, re-homed into module <Mod> as page <Page>.
page_script() { sed "s/Demo\.Demo_List/$1.$2/; s/Demo\.Demo_Overview/$1.$2/; s/Demo\.App_Default/$1.Layout/" "$CAP/$3"; }

P="$WORK/multi"; mkdir -p "$P/apps/Portal/mdlsource" "$P/apps/Backoffice/mdlsource"
register "$P"
: > "$P/apps/Portal/Portal.mpr"; : > "$P/apps/Backoffice/Backoffice.mpr"
page_script Dashboard Home demo-overview.mdl   > "$P/apps/Portal/mdlsource/10-dashboard.mdl"
page_script Dashboard Status demo-list.mdl    >> "$P/apps/Portal/mdlsource/10-dashboard.mdl"
page_script Requests Request_List demo-list.mdl > "$P/apps/Portal/mdlsource/20-requests.mdl"
page_script Cases Case_Overview demo-overview.mdl > "$P/apps/Backoffice/mdlsource/10-cases.mdl"
# A commented-out page and a dropped page are not built.
printf -- '-- CREATE PAGE Cases.Old_Page\nDROP PAGE IF EXISTS Cases.Case_Overview;\n' > "$P/apps/Backoffice/mdlsource/50-drop.mdl"
page_script Cases Case_Overview demo-overview.mdl > "$P/apps/Backoffice/mdlsource/98-cases-again.mdl"
# Test scripts are not build scripts.
page_script Testing Ignored demo-list.mdl > "$P/apps/Portal/mdlsource/x.test.mdl"

row() { MXTK_ROWS_UPTO=5 "$OBCHECK" "$1" 2>&1 | grep -E "^Obligation $2 " ; }

echo "== T1: no briefs, page scripts in apps/<App>/ — look is owed by the built modules =="
l="$(row "$P" look | head -1)"
case "$l" in *PENDING*"0 of 3 discharged"*) ok "look PENDING, 0 of 3 modules: $l" ;; *) bad "expected look PENDING 0 of 3, got: $l" ;; esac
case "$l" in *Cases*Dashboard*Requests*) ok "names every built module" ;; *) bad "modules not named: $l" ;; esac
case "$l" in *Testing*) bad "a *.test.mdl page was counted" ;; *) ok "*.test.mdl not counted" ;; esac
d="$(row "$P" look | grep 'OWED BY WHAT WAS BUILT')"
case "$d" in *"4 page(s) built in 3 module(s) (Cases 1, Dashboard 2, Requests 1)"*"0 of 3 module(s) discharged"*"*.mdl"*) ok "denominator line: $d" ;;
             *) bad "denominator line wrong: $d" ;; esac

echo "== T2: the same floor reaches sweep, journeys, fidelity and must-haves =="
for ob in sweep journeys fidelity must-haves; do
  l="$(row "$P" "$ob" | head -1)"
  case "$l" in *PENDING*"of 3 discharged"*) ok "$ob owed by built modules" ;; *) bad "$ob: $l" ;; esac
done
case "$(MXTK_ROWS_UPTO=5 "$OBCHECK" "$P" 2>&1)" in *"nothing owed"*) bad "a module row still says nothing owed" ;; *) ok "no module row reads PASS by absence" ;; esac

echo "== T3: the look ledger wins over scripts when present =="
mkdir -p "$P/.claude/loop/look"
printf '1700000000\t2026-11-01T00:00:00Z\tLedger.Only_Page\tmdlsource/x.mdl\n' > "$P/.claude/loop/look/owed.tsv"
d="$(row "$P" look | grep 'OWED BY WHAT WAS BUILT')"
case "$d" in *"1 page(s) built in 1 module(s) (Ledger 1)"*owed.tsv*) ok "ledger source: $d" ;; *) bad "ledger not used: $d" ;; esac
rm -f "$P/.claude/loop/look/owed.tsv"

echo "== T4: the model's page-scope.json is the last source =="
M="$WORK/model"; mkdir -p "$M/.claude/loop"; register "$M"; : > "$M/App.mpr"
cp "$HERE/fixtures/verify-446/page-scope.json" "$M/.claude/loop/page-scope.json"
d="$(row "$M" look | grep 'OWED BY WHAT WAS BUILT')"
case "$d" in *"1 page(s) built in 1 module(s) (MyFirstModule 1)"*page-scope.json*) ok "page-scope source: $d" ;; *) bad "page-scope not used: $d" ;; esac

echo "== T5: a model with no countable pages is FAULT, counted once — never 0 pages =="
U="$WORK/uncounted"; mkdir -p "$U/app"; register "$U"; : > "$U/app/App.mpr"
out="$(MXTK_ROWS_UPTO=5 "$OBCHECK" "$U" 2>&1)"
case "$(printf '%s\n' "$out" | grep '^Obligation look ')" in *FAULT*"could not be counted"*page-scope.sh*) ok "look FAULT with the remedy" ;;
  *) bad "expected FAULT: $(printf '%s\n' "$out" | grep '^Obligation look ')" ;; esac
n="$( . "$OBCHECK"; mxtk_obligations_report "$U" >/dev/null; echo "$MXTK_OB_N_FAULT")"
[ "$n" = 1 ] && ok "one fault for all module rows" || bad "expected 1 fault, got $n"

echo "== T6: nothing built and no model — the PASS says what was read =="
E="$WORK/empty"; mkdir -p "$E"; register "$E"
l="$(row "$E" look | head -1)"
case "$l" in *PASS*"no page built"*) ok "$l" ;; *) bad "expected measured PASS, got: $l" ;; esac

echo "== T7: a project WITH briefs keeps today's verdicts (no floor, no extra modules) =="
B="$WORK/briefed"; mkdir -p "$B/architecture/modules/Orders" "$B/mdlsource"; register "$B"
page_script Other Unbriefed_Page demo-list.mdl > "$B/mdlsource/10.mdl"
l="$(row "$B" look | head -1)"
case "$l" in *PENDING*"0 of 1 discharged"*Orders*) ok "briefed scope unchanged: $l" ;; *) bad "briefed scope changed: $l" ;; esac
case "$(row "$B" look)" in *"OWED BY WHAT WAS BUILT"*|*Other*) bad "floor applied to a briefed project" ;; *) ok "no floor line, unbriefed module not added" ;; esac
mkdir -p "$B/.claude/loop/sweep/Orders"
printf 'Orders · 4 of 4 interactive elements swept across 2 of 2 pages\n' > "$B/.claude/loop/sweep/Orders/sweep.md"
mkdir -p "$B/docs/progress/must-haves"
printf 'Orders · 13 of 13 rows ticked or NOT DONE with a reason · pages 2 of 2\n' > "$B/docs/progress/must-haves/Orders.md"
case "$(row "$B" sweep | head -1)" in *PASS*"1 of 1"*) ok "a real sweep still discharges" ;; *) bad "sweep: $(row "$B" sweep)" ;; esac
case "$(row "$B" must-haves | head -1)" in *PASS*"1 of 1"*) ok "a ticked must-have list discharges" ;; *) bad "must-haves: $(row "$B" must-haves)" ;; esac
printf 'Orders · all rows ticked\n' > "$B/docs/progress/must-haves/Orders.md"
case "$(row "$B" must-haves | head -1)" in *FAULT*"NO DENOMINATOR"*) ok "a must-have list with no denominator is FAULT" ;; *) bad "must-haves no-denom: $(row "$B" must-haves)" ;; esac

echo "== T8: gate-check Stage 5 on the multi-app copy shows the floor =="
out="$("$GATE" --no-html "$P" 5 2>&1)"
case "$out" in *"Obligation look"*PENDING*) ok "gate-check prints look PENDING" ;; *) bad "gate-check: $(printf '%s\n' "$out" | grep -m1 'Obligation look')" ;; esac

echo "== T9: entry-mode column — a mode a row does not list reads N/A, never PASS; unknown mode owes =="
Q="$WORK/mode"; mkdir -p "$Q/architecture/modules/Orders"
awk -F'\t' 'BEGIN{OFS="\t"} !/^#/ && NF==10 && $1=="look"{$10="migration"} {print}' "$(dirname "$OBCHECK")/obligations.tsv" > "$WORK/ob-mode.tsv"
mrow() { OBLIGATIONS_TSV="$WORK/ob-mode.tsv" MXTK_ROWS_UPTO=5 "$OBCHECK" "$Q" 2>/dev/null | grep '^Obligation look ' | head -1; }
printf 'Entry mode: greenfield\n' > "$Q/PROJECT.md"
case "$(mrow)" in *"N/A — not owed (entry mode greenfield"*) ok "greenfield not owed a migration-only row" ;; *) bad "greenfield: $(mrow)" ;; esac
printf 'Entry mode: migration\n' > "$Q/PROJECT.md"
case "$(mrow)" in *PENDING*) ok "migration still owes it" ;; *) bad "migration: $(mrow)" ;; esac
printf 'Toolkit commit: none\n' > "$Q/PROJECT.md"
case "$(mrow)" in *PENDING*) ok "no Entry mode line owes it" ;; *) bad "no mode: $(mrow)" ;; esac
printf 'Entry mode: greenfield\n' > "$Q/PROJECT.md"
case "$(MXTK_ROWS_UPTO=5 "$OBCHECK" "$Q" 2>/dev/null | grep '^Obligation look ')" in *PENDING*) ok "shipped table: greenfield owes look" ;; *) bad "shipped table changed a verdict" ;; esac
# requirements-driven is translated to the table's `requirements` token by the SAME reader
# artifact-check.sh uses (_art_entry_mode), not by a second copy of the mapping.
printf 'Entry mode: requirements-driven\n' > "$Q/PROJECT.md"
case "$(mrow)" in *"N/A — not owed (entry mode requirements"*) ok "requirements-driven, row omits requirements: not owed" ;; *) bad "rd omit: $(mrow)" ;; esac
awk -F'\t' 'BEGIN{OFS="\t"} !/^#/ && NF==10 && $1=="look"{$10="migration,requirements"} {print}' "$(dirname "$OBCHECK")/obligations.tsv" > "$WORK/ob-mode.tsv"
case "$(mrow)" in *PENDING*) ok "requirements-driven, row lists requirements: owed" ;; *) bad "rd list: $(mrow)" ;; esac

echo "pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
