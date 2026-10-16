#!/usr/bin/env bash
# Fixture for project-bin/affected-tests.sh: which unit tests and journeys a change owes,
# per the project's PROJECT.md "## Test strategy" row (defaults when it has none).
#
# usage: bash tests/wave2/test-affected-tests.sh [/path/to/affected-tests.sh]
#
# Golden input is captured, never written: the change scripts are line ranges of
# fixtures/affected-tests/shop.mdl (the MDL that was exec'd to build the captured model), and
# the stub mxcli replays, per statement, the verbatim `SHOW CALLERS OF ... TRANSITIVE` blocks
# mxcli v0.26.0 printed for that model (provenance: fixtures/affected-tests/CAPTURE.txt).
# The .test.mdl and journey files in the stub project are project content, not instrument
# output: they only need to name (or not name) the captured elements.
#
# Positive control: against master (no affected-tests.sh) 10 pass, 34 fail: only the negative
# guards hold. With names_for_unit's caller rows removed, A2 and the --depth 2 case fail; with
# grep -w dropped, A's look-alike guard fails.
set -uo pipefail

TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
SUBJECT="${1:-$TOOLKIT/project-bin/affected-tests.sh}"
case "$SUBJECT" in /*) ;; *) SUBJECT="$PWD/$SUBJECT" ;; esac
FX="$TOOLKIT/tests/wave2/fixtures/affected-tests"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/affected-t.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; return 0; }
echo "== subject: $SUBJECT"

P="$WORK/proj"
mkdir -p "$P/bin" "$P/tests/unit" "$P/journeys" "$P/tests/e2e"
printf 'not a real model\n' > "$P/Fixture.mpr"
cp "$TOOLKIT/project-bin/_common.sh" "$TOOLKIT/project-bin/exec.sh" "$P/bin/"
cp "$SUBJECT" "$P/bin/affected-tests.sh"
chmod +x "$P/bin/"*.sh

# Project content: tests naming the captured elements, one look-alike, one other module.
t() { printf '/**\n * @test %s\n */\ncall microflow %s();\n/\n' "$2" "$2" > "$P/tests/unit/$1.test.mdl"; }
t Total    Shop.SUB_Order_Total
t Validate Shop.VAL_Order
t Submit   Shop.ACT_Order_Submit
t Lookalike Shop.SUB_Order_Total_Legacy
t Other    Admin.ACT_Reset
echo '{"id":"J-1","steps":[]}' > "$P/journeys/Shop.journey.json"
echo '{"id":"J-2","steps":[]}' > "$P/journeys/Admin.journey.json"
echo '{"id":"J-3","note":"opens Shop.Order_Edit","steps":[]}' > "$P/tests/e2e/edit.clerk.journey.json"
echo '{"id":"J-4","steps":[]}' > "$P/tests/e2e/home.clerk.journey.json"

# Stub mxcli: one call = one -c query; prints the captured block of each statement, in order.
cat > "$P/mxcli" <<'MXCLI'
#!/usr/bin/env bash
D="$(cd "$(dirname "$0")" && pwd)"
printf '%s\n' "$*" >> "$D/.stub-log"
[ "${STUB_NOPROJ:-}" = 1 ] && { cat "$FX/noproj.out"; cat "$FX/noproj.err" >&2; exit "$(cat "$FX/noproj.exit")"; }
q=""; while [ $# -gt 0 ]; do [ "$1" = -c ] && q="$2"; shift; done
cat "$FX/callers.err" >&2
first=1
printf '%s\n' "$q" | tr ';' '\n' | sed -n 's/^ *SHOW CALLERS OF \([^ ]*\) TRANSITIVE *$/\1/p' | while IFS= read -r n; do
  blk="$(cat "$FX/callers.out" "$FX/val-order.out" | awk -v n="$n" '
    $0 == "Callers of " n " (transitive)" { on = 1 } on && /^$/ { exit } on { print }')"
  [ -n "$blk" ] || { echo "stub: no captured block for $n" >&2; exit 99; }
  [ "$first" = 1 ] || echo; first=0; printf '%s\n' "$blk"
done || exit 99
exit "$(cat "$FX/callers.exit")"
MXCLI
chmod +x "$P/mxcli"
export FX

lines() { sed -n "$1p" "$FX/shop.mdl" > "$WORK/$2"; echo "$WORK/$2"; }
TOTAL="$(lines 7,10 total.mdl)"           # create or modify microflow Shop.SUB_Order_Total
ENTITY="$(lines 3,6 entity.mdl)"          # create or modify persistent entity Shop.Order
{ sed -n 24,32p "$FX/shop.mdl"; sed -n 33,37p "$FX/shop.mdl"; } > "$WORK/page-and-flow.mdl"
PAGEFLOW="$WORK/page-and-flow.mdl"        # page Shop.Order_Edit + microflow Shop.ACT_Order_New

run() {  # run <label> [args...]; env passes through
  _l="$1"; shift; rm -f "$P/.stub-log"
  ( cd "$P" && ./bin/affected-tests.sh "$@" ) > "$WORK/out.$_l" 2> "$WORK/err.$_l"; echo $?
}
has()   { grep -qF -- "$2" "$WORK/out.$1"; }
lacks() { ! grep -qF -- "$2" "$WORK/out.$1"; }
calls() { if [ -f "$P/.stub-log" ]; then wc -l < "$P/.stub-log" | tr -d ' '; else echo 0; fi; }

echo "== A: one microflow change, defaults (no PROJECT.md) =="
RC=$(run A "$TOTAL")
[ "$RC" -eq 0 ] && ok "exit 0" || bad "A rc=$RC" "$(cat "$WORK/err.A")"
has A "strategy	change	unit=affected journeys=affected	(default:" && ok "strategy row says default affected/affected" || bad "A strategy" "$(head -1 "$WORK/out.A")"
has A "subject	microflow	Shop.SUB_Order_Total	line 1 of total.mdl" && ok "subject from exec.sh --subjects" || bad "A subject" "$(cat "$WORK/out.A")"
[ "$(calls)" = 1 ] && grep -qx -- '-p .*Fixture.mpr -c SHOW CALLERS OF Shop.SUB_Order_Total TRANSITIVE' "$P/.stub-log" \
  && ok "one mxcli call, the transitive callers query" || bad "A mxcli calls" "$(cat "$P/.stub-log" 2>/dev/null)"
has A "caller	Shop.VAL_Order	depth 1" && has A "caller	Shop.Order_Overview	depth 5" && ok "five transitive callers, pages included" || bad "A callers" "$(grep caller "$WORK/out.A")"
has A "callers	measured" && ok "callers measured" || bad "A measured"
has A "unit	tests/unit/Total.test.mdl	names Shop.SUB_Order_Total" && ok "A1 the subject's own test" || bad "A1" "$(grep ^unit "$WORK/out.A")"
has A "unit	tests/unit/Validate.test.mdl	names Shop.VAL_Order" && ok "A2 the depth-1 caller's test" || bad "A2" "$(grep ^unit "$WORK/out.A")"
lacks A "Submit.test.mdl" && ok "A3 a depth-2 caller's test is not owed at --depth 1" || bad "A3 Submit selected at depth 1"
lacks A "Lookalike.test.mdl" && ok "a look-alike name (SUB_Order_Total_Legacy) is not a match" || bad "A look-alike selected"
lacks A "Other.test.mdl" && ok "another module's test not selected" || bad "A Other selected"
has A "journey	journeys/Shop.journey.json	module Shop" && ok "the module journey of the subject and its callers" || bad "A journey" "$(grep ^journey "$WORK/out.A")"
lacks A "Admin.journey.json" && lacks A "home.clerk" && ok "unrelated journeys not selected" || bad "A unrelated journey"
has A "run	./bin/test-scratch.sh -- tests/unit/Total.test.mdl tests/unit/Validate.test.mdl --local" && ok "run row: test-scratch on the selection" || bad "A run unit" "$(grep ^run "$WORK/out.A")"
has A "run	node tests/e2e/journey-runner.js journeys/Shop.journey.json" && ok "run row: journey runner" || bad "A run journey"

echo "== A2: --depth 2 adds the depth-2 caller's test =="
run A2 --depth 2 "$TOTAL" >/dev/null
has A2 "unit	tests/unit/Submit.test.mdl	names Shop.ACT_Order_Submit" && ok "Submit selected at depth 2" || bad "A2 depth 2" "$(grep ^unit "$WORK/out.A2")"

echo "== B: a page and a microflow in one script: ONE batched call =="
run B "$PAGEFLOW" >/dev/null
[ "$(calls)" = 1 ] && grep -qx -- '-p .*Fixture.mpr -c SHOW CALLERS OF Shop.ACT_Order_New TRANSITIVE; SHOW CALLERS OF Shop.Order_Edit TRANSITIVE' "$P/.stub-log" \
  && ok "both subjects in one -c batch" || bad "B batch" "$(cat "$P/.stub-log" 2>/dev/null)"
has B "subject	page	Shop.Order_Edit" && has B "subject	microflow	Shop.ACT_Order_New" && ok "both subjects listed" || bad "B subjects" "$(grep ^subject "$WORK/out.B")"
has B "caller	Shop.Order_Overview	depth 1" && ok "shortest depth kept for a caller reached twice" || bad "B depth" "$(grep ^caller "$WORK/out.B")"
has B "journey	tests/e2e/edit.clerk.journey.json	names Shop.Order_Edit" && ok "a journey that names the changed page" || bad "B named journey" "$(grep ^journey "$WORK/out.B")"
has B "unit	none	scope affected: 0 of 5" && ok "no matching test says so (never silence)" || bad "B unit none" "$(grep ^unit "$WORK/out.B")"

echo "== C: --no-model =="
run C --no-model "$TOTAL" >/dev/null
[ "$(calls)" = 0 ] && ok "mxcli not called" || bad "C called mxcli"
has C "callers	NOT MEASURED (--no-model)" && ok "callers NOT MEASURED, and why" || bad "C callers" "$(grep ^callers "$WORK/out.C")"
has C "Total.test.mdl" && lacks C "Validate.test.mdl" && ok "selection is the subjects alone" || bad "C selection" "$(grep ^unit "$WORK/out.C")"

echo "== D: mxcli cannot open the project (captured exit 1) =="
RC=$(STUB_NOPROJ=1 run D "$TOTAL")
[ "$RC" -eq 0 ] && ok "still exit 0 (advisory)" || bad "D rc=$RC"
has D "callers	NOT MEASURED (mxcli exit 1, 0 of 1 caller blocks: Error: failed to connect: mpr file not found" && ok "names the exit and mxcli's error" || bad "D callers" "$(grep ^callers "$WORK/out.D")"
has D "Total.test.mdl" && ok "falls back to the subjects" || bad "D fallback"

echo "== E: the project's strategy row wins =="
cat > "$P/PROJECT.md" <<'EOF'
# Project

## Test strategy
| Moment | Unit tests | Journeys | Status |
|---|---|---|---|
| Every change | none | module | CONFIRMED |
| Module close | module | module | CONFIRMED |
| Deploy-ready | full | full | ASSUMED |

## Next
| Every change | full | full | not this section |
EOF
run E "$TOTAL" >/dev/null
has E "strategy	change	unit=none journeys=module	(PROJECT.md ## Test strategy, row 'Every change', CONFIRMED)" && ok "row read, status carried" || bad "E strategy" "$(head -1 "$WORK/out.E")"
has E "unit	none	scope none: strategy says none" && ok "unit none per strategy" || bad "E unit" "$(grep ^unit "$WORK/out.E")"
has E "journey	journeys/Shop.journey.json	module Shop" && lacks E "edit.clerk" && ok "journeys at module scope" || bad "E journeys" "$(grep ^journey "$WORK/out.E")"
[ "$(calls)" = 0 ] && ok "no affected scope, so no mxcli call" || bad "E called mxcli"
printf '## Test strategy\n| Every change | sometimes | affected | ASSUMED |\n' > "$P/PROJECT.md"
run E2 "$TOTAL" >/dev/null
has E2 "unit scope 'sometimes' unknown, default used" && has E2 "unit=affected" && ok "an unknown scope falls back and says so" || bad "E2" "$(head -1 "$WORK/out.E2")"
rm -f "$P/PROJECT.md"

echo "== F: deploy-ready default is the full suite =="
run F --moment deploy "$TOTAL" >/dev/null
has F "unit=full journeys=full" && [ "$(grep -c '^unit	' "$WORK/out.F")" = 5 ] && [ "$(grep -c '^journey	' "$WORK/out.F")" = 4 ] \
  && ok "all 5 test files, all 4 journey files" || bad "F full" "$(grep -e ^unit -e ^journey "$WORK/out.F")"
[ "$(calls)" = 0 ] && ok "no mxcli call at deploy-ready" || bad "F called mxcli"
run F2 --moment module --module Admin >/dev/null
has F2 "Other.test.mdl	names module Admin" && has F2 "journeys/Admin.journey.json" && ok "module close of a named module, no script needed" || bad "F2" "$(cat "$WORK/out.F2")"

echo "== G: an entity change selects its module's tests, no caller query =="
run G "$ENTITY" >/dev/null
has G "subject	entity	Shop.Order" && ok "entity subject" || bad "G subject" "$(grep ^subject "$WORK/out.G")"
has G "callers	not needed" && [ "$(calls)" = 0 ] && ok "no caller query for an entity" || bad "G callers" "$(grep ^callers "$WORK/out.G")"
has G "Total.test.mdl	names module Shop (data or access change)" && has G "Lookalike.test.mdl" && lacks G "Other.test.mdl" \
  && ok "every Shop test, not Admin's" || bad "G unit" "$(grep ^unit "$WORK/out.G")"

echo "== H: usage =="
RC=$(run H --moment later "$TOTAL"); [ "$RC" -eq 2 ] && ok "bad --moment exits 2" || bad "H rc=$RC"
RC=$(run H2 "$WORK/no-such.mdl"); [ "$RC" -eq 2 ] && ok "missing script exits 2" || bad "H2 rc=$RC"
RC=$(run H3); [ "$RC" -eq 2 ] && ok "a change with no script exits 2" || bad "H3 rc=$RC"
[ ! -e "$P/.mxcli" ] && ok "wrote nothing into the project" || bad "project written"

echo "== wiring =="
grep -q 'affected-tests.sh' "$TOOLKIT/bin/lib/install-manifest.sh" && ok "named in install-manifest.sh" || bad "not in install-manifest.sh"
grep -q 'affected tests: ./bin/affected-tests.sh' "$TOOLKIT/project-bin/exec.sh" && ok "exec.sh points at it" || bad "exec.sh hint missing"

echo; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
