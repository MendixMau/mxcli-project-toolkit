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
# Gap checks (found measuring a five-app lab project, 18 of 20 journey files were named by app and
# role, 12 of 20 held no qualified name): the unmapped-journey count is printed (A, F), a journey
# that names a transitive CALLER is selected (A, B; --no-model does not), and a data subject
# prints a "data NOT MEASURED" row (G, I) so an enumeration used in another module is never
# silently owed nothing. MXTK_AFFECTED_DEPTH sets the default depth (A3).
#
# Positive control: against master (no affected-tests.sh) the negative guards hold and the rest
# fail. With names_for_unit's caller rows removed, A2 and the --depth 2 case fail; with grep -w
# dropped, A's look-alike guard fails; with the caller names dropped from jnames, the caller
# journey case fails.
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

P="$WORK/proj"; BASE_PM="$WORK/base-PROJECT.md"
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
# Unit tests are off unless the project says yes: the baseline project says yes, section L varies it.
printf '# Project\n\nUnit tests default: yes\n' > "$BASE_PM"; cp "$BASE_PM" "$P/PROJECT.md"
echo '{"id":"J-1","steps":[]}' > "$P/journeys/Shop.journey.json"
echo '{"id":"J-2","steps":[]}' > "$P/journeys/Admin.journey.json"
echo '{"id":"J-3","note":"opens Shop.Order_Edit","steps":[]}' > "$P/tests/e2e/edit.clerk.journey.json"
echo '{"id":"J-6","steps":[]}' > "$P/journeys/Shop.admin.journey.json"   # in journeys/, not <Module>.journey.json, names nothing
echo '{"id":"J-4","steps":[]}' > "$P/tests/e2e/home.clerk.journey.json"
echo '{"id":"J-5","note":"starts on Shop.Order_Overview","steps":[]}' > "$P/tests/e2e/overview.clerk.journey.json"

# Stub mxcli: one call = one -c query; prints the captured block of each statement, in order.
cat > "$P/mxcli" <<'MXCLI'
#!/usr/bin/env bash
D="$(cd "$(dirname "$0")" && pwd)"
printf '%s\n' "$*" >> "$D/.stub-log"
[ "${STUB_NOPROJ:-}" = 1 ] && { cat "$FX/noproj.out"; cat "$FX/noproj.err" >&2; exit "$(cat "$FX/noproj.exit")"; }
q=""; while [ $# -gt 0 ]; do [ "$1" = -c ] && q="$2"; shift; done
case "$q" in "SHOW MICROFLOWS IN"*)   # synthetic listing, the real table shape
  [ -n "${STUB_BADMOD:-}" ] && case "$q" in *"IN $STUB_BADMOD"*) echo "Error: module not found: $STUB_BADMOD" >&2; exit 1 ;; esac
  echo "| Qualified Name | Module | Name | Excluded |"; echo "|---|---|---|---|"
  for n in ${STUB_MF:-Shop.SUB_Order_Total Shop.VAL_Order Shop.ACT_Order_Submit Admin.ACT_Reset}; do echo "| $n | ${n%%.*} | ${n#*.} | false |"; done; exit 0 ;; esac
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
chmod +x "$P/mxcli"; cp "$P/mxcli" "$WORK/mxcli.orig"
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

echo "== A: one microflow change, defaults (project says Unit tests default: yes) =="
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
has A "journey	tests/e2e/overview.clerk.journey.json	names Shop.Order_Overview" && ok "a journey that names a transitive CALLER is selected" || bad "A caller journey" "$(grep ^journey "$WORK/out.A")"
has A "journeys	unmapped	2 of 6 journey file(s)" && ok "unmapped count: home.clerk AND journeys/Shop.admin.journey.json (a file in journeys/ is mapped only when named <Module>.journey.json)" || bad "A unmapped" "$(grep ^journeys "$WORK/out.A")"
lacks A "data	NOT MEASURED" && ok "no data row for a microflow change" || bad "A data row"
has A "run	./bin/test-scratch.sh -- tests/unit/Total.test.mdl tests/unit/Validate.test.mdl --local" && ok "run row: test-scratch on the selection" || bad "A run unit" "$(grep ^run "$WORK/out.A")"
has A "run	node tests/e2e/journey-runner.js journeys/Shop.journey.json" && ok "run row: journey runner" || bad "A run journey"

echo "== A2: --depth 2 adds the depth-2 caller's test =="
run A2 --depth 2 "$TOTAL" >/dev/null
has A2 "unit	tests/unit/Submit.test.mdl	names Shop.ACT_Order_Submit" && ok "Submit selected at depth 2" || bad "A2 depth 2" "$(grep ^unit "$WORK/out.A2")"

echo "== A3: MXTK_AFFECTED_DEPTH sets the default depth, --depth wins =="
MXTK_AFFECTED_DEPTH=2 run A3 "$TOTAL" >/dev/null
has A3 "unit	tests/unit/Submit.test.mdl" && ok "env depth 2 selects Submit" || bad "A3 env" "$(grep ^unit "$WORK/out.A3")"
MXTK_AFFECTED_DEPTH=2 run A4 --depth 1 "$TOTAL" >/dev/null
lacks A4 "Submit.test.mdl" && ok "--depth 1 beats the env" || bad "A4 flag vs env"

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
lacks C "overview.clerk" && ok "no callers, so no caller-named journey" || bad "C caller journey"
has C "Total.test.mdl" && lacks C "Validate.test.mdl" && ok "selection is the subjects alone" || bad "C selection" "$(grep ^unit "$WORK/out.C")"

echo "== D: mxcli cannot open the project (captured exit 1) =="
RC=$(STUB_NOPROJ=1 run D "$TOTAL")
[ "$RC" -eq 0 ] && ok "still exit 0 (advisory)" || bad "D rc=$RC"
has D "callers	NOT MEASURED (mxcli exit 1, 0 of 1 caller blocks: Error: failed to connect: mpr file not found" && ok "names the exit and mxcli's error" || bad "D callers" "$(grep ^callers "$WORK/out.D")"
has D "Total.test.mdl" && ok "falls back to the subjects" || bad "D fallback"

echo "== E: the project's strategy row wins =="
cat > "$P/PROJECT.md" <<'EOF'
# Project

Unit tests default: yes

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
printf 'Unit tests default: yes\n## Test strategy\n| Every change | sometimes | affected | ASSUMED |\n' > "$P/PROJECT.md"
run E2 "$TOTAL" >/dev/null
has E2 "unit scope 'sometimes' unknown, default used" && has E2 "unit=affected" && ok "an unknown scope falls back and says so" || bad "E2" "$(head -1 "$WORK/out.E2")"
cp "$BASE_PM" "$P/PROJECT.md"

echo "== F: deploy-ready default is the full suite =="
run F --moment deploy "$TOTAL" >/dev/null
has F "unit=full journeys=full" && [ "$(grep -c '^unit	' "$WORK/out.F")" = 5 ] && [ "$(grep -c '^journey	' "$WORK/out.F")" = 6 ] \
  && ok "all 5 test files, all 6 journey files" || bad "F full" "$(grep -e ^unit -e ^journey "$WORK/out.F")"
[ "$(calls)" = 0 ] && ok "no mxcli call at deploy-ready" || bad "F called mxcli"
run F2 --moment module --module Admin >/dev/null
has F2 "Other.test.mdl	names module Admin" && has F2 "journeys/Admin.journey.json" && ok "module close of a named module, no script needed" || bad "F2" "$(cat "$WORK/out.F2")"

echo "== G: an entity change selects its module's tests, no caller query =="
run G "$ENTITY" >/dev/null
has G "subject	entity	Shop.Order" && ok "entity subject" || bad "G subject" "$(grep ^subject "$WORK/out.G")"
has G "data	NOT MEASURED	entity Shop.Order	(cross-module use not measured; selected by owning module Shop only)" && ok "data NOT MEASURED row for the entity" || bad "G data row" "$(grep ^data "$WORK/out.G")"
has G "callers	not needed" && [ "$(calls)" = 0 ] && ok "no caller query for an entity" || bad "G callers" "$(grep ^callers "$WORK/out.G")"
has G "Total.test.mdl	names module Shop (data or access change)" && has G "Lookalike.test.mdl" && lacks G "Other.test.mdl" \
  && ok "every Shop test, not Admin's" || bad "G unit" "$(grep ^unit "$WORK/out.G")"

echo "== I: an enumeration change, and a mixed script =="
printf "create or modify enumeration Shop.OrderStatus (\n  Draft 'Draft',\n  Done 'Done'\n);\n" > "$WORK/enum.mdl"
run I "$WORK/enum.mdl" >/dev/null
has I "subject	enumeration	Shop.OrderStatus" && has I "data	NOT MEASURED	enumeration Shop.OrderStatus" && ok "enumeration: subject and NOT MEASURED row" || bad "I enum" "$(grep -e ^subject -e ^data "$WORK/out.I")"
has I "unit	tests/unit/Total.test.mdl	names module Shop (data or access change)" && ok "still selected by owning module" || bad "I unit" "$(grep ^unit "$WORK/out.I")"
cat "$WORK/enum.mdl" "$TOTAL" > "$WORK/mixed.mdl"
run I2 "$WORK/mixed.mdl" >/dev/null
[ "$(grep -c '^data	NOT MEASURED' "$WORK/out.I2")" = 1 ] && has I2 "callers	measured" && ok "mixed: one data row, callers still measured for the microflow" || bad "I2 mixed" "$(grep -e ^data -e ^callers "$WORK/out.I2")"

echo "== J: role, user role and constant subjects print data NOT MEASURED =="
cat > "$WORK/roles.mdl" <<'EOF'
create module role Shop.Manager;
create user role Admin (Shop.Manager);
create or modify constant Shop.MaxItems type Integer default 5;
EOF
run J "$WORK/roles.mdl" >/dev/null
has J "subject	role	Shop.Manager" && has J "subject	userrole	Admin" && has J "subject	constant	Shop.MaxItems" && ok "three subjects, none unmapped" || bad "J subjects" "$(grep ^subject "$WORK/out.J")"
has J "data	NOT MEASURED	role Shop.Manager	(cross-module use not measured" && ok "module role row" || bad "J role" "$(grep ^data "$WORK/out.J")"
has J "data	NOT MEASURED	constant Shop.MaxItems	(cross-module use not measured" && ok "constant row" || bad "J constant" "$(grep ^data "$WORK/out.J")"
has J "data	NOT MEASURED	userrole Admin	(access change" && ok "user role row" || bad "J userrole" "$(grep ^data "$WORK/out.J")"
lacks J "module Admin" && lacks J "Other.test.mdl" && ok "a user role name is never read as a module" || bad "J userrole as module" "$(cat "$WORK/out.J")"
printf 'alter user role Admin add module roles (Shop.Manager);\ndrop user role Old;\n' > "$WORK/roles2.mdl"
run J2 "$WORK/roles2.mdl" >/dev/null
[ "$(grep -c '^subject	userrole	' "$WORK/out.J2")" = 2 ] && ok "ALTER and DROP USER ROLE are subjects too" || bad "J2" "$(grep ^subject "$WORK/out.J2")"

echo "== K: a caller added by an exec shows up on the next call (no stale cache) =="
# The real catalog: on mxcli v0.26.0 a scratch copy had 4 transitive callers of a microflow;
# after `exec` created a microflow calling it, the next SHOW CALLERS rebuilt the catalog
# ("Catalog cached to .mxcli/catalog.db", the .mpr had changed) and listed 5, the new one at
# depth 1 (fixtures/affected-tests/CAPTURE-FRESHNESS.txt). The script keeps no state of its own,
# so it must pass that through. The stub below behaves like that capture: output follows the .mpr.
cat > "$P/mxcli" <<'MXCLI'
#!/usr/bin/env bash
D="$(cd "$(dirname "$0")" && pwd)"
echo "Callers of Shop.SUB_Order_Total (transitive)"
echo "| Caller | Depth |"
echo "|---|---|"
echo "| Shop.VAL_Order | 1 |"
grep -q ADDED "$D/Fixture.mpr" && echo "| Shop.ZZ_New_Caller | 1 |"
exit 0
MXCLI
printf 'not a real model\n' > "$P/Fixture.mpr"
run K1 "$TOTAL" >/dev/null
lacks K1 "Shop.ZZ_New_Caller" && ok "before the exec: the new caller is not there" || bad "K1"
printf 'not a real model\nADDED\n' > "$P/Fixture.mpr"      # what an exec does to the model
run K2 "$TOTAL" >/dev/null
has K2 "caller	Shop.ZZ_New_Caller	depth 1" && has K2 "callers	measured" && ok "after the exec: the new caller is listed, callers measured" || bad "K2 stale" "$(grep -e ^caller "$WORK/out.K2")"
[ ! -e "$P/.mxcli" ] && [ ! -e "$P/.affected-cache" ] && ok "the script keeps no cache of its own" || bad "K cache file"

echo "== L: unit tests are off by default, a module flips them on, a grant on the changed object is not an access change =="
GRANT="$WORK/flow-grant.mdl"; { cat "$TOTAL"; echo "grant execute on microflow Shop.SUB_Order_Total to Shop.User;"; } > "$GRANT"
EGRANT="$WORK/entity-grant.mdl"; echo "grant Shop.User on Shop.Order (create, read);" > "$EGRANT"
BRIEF_DIR="$P/architecture/modules"
# L1: line absent
printf '# Project\n' > "$P/PROJECT.md"
run L1 "$TOTAL" >/dev/null
has L1 "unit=none" && has L1 "unit	off	(PROJECT.md has no 'Unit tests default:' line, treated as no; flip a module:" && lacks L1 "unit	tests/" && lacks L1 ".test.mdl" \
  && ok "L1 default line absent: unit off, no test file, no run row" || bad "L1 absent" "$(cat "$WORK/out.L1")"
has L1 "journey	journeys/Shop.journey.json" && ok "journeys unaffected by the unit gate" || bad "L1 journeys"
# L2: explicit no
printf '# Project\n\n**Unit tests default: no**\n' > "$P/PROJECT.md"
run L2 "$TOTAL" >/dev/null
has L2 "unit	off	(PROJECT.md Unit tests default: no; flip a module:" && lacks L2 ".test.mdl" && ok "L2 default no: unit off, never a .test.mdl run row" || bad "L2 no" "$(cat "$WORK/out.L2")"
run L2b "$ENTITY" >/dev/null; lacks L2b ".test.mdl" && ok "L2b default no: an entity change selects no unit test either" || bad "L2b" "$(cat "$WORK/out.L2b")"
run L2c --moment deploy >/dev/null; [ "$(grep -c '^unit	tests/' "$WORK/out.L2c")" = 5 ] && ok "L2c default no: build complete still runs every existing unit test" || bad "L2c" "$(cat "$WORK/out.L2c")"
run L2d --moment all >/dev/null; [ "$(grep -c '^unit	tests/' "$WORK/out.L2d")" = 5 ] && has L2d "strategy	deploy" && ok "L2d --moment all = everything" || bad "L2d" "$(cat "$WORK/out.L2d")"
# L3: yes
printf '# Project\n\nUnit tests default: yes\n' > "$P/PROJECT.md"
run L3 "$TOTAL" >/dev/null
has L3 "unit	tests/unit/Total.test.mdl	names Shop.SUB_Order_Total" && has L3 "run	./bin/test-scratch.sh -- tests/unit/Total.test.mdl" && ok "L3 default yes: today's behaviour" || bad "L3 yes" "$(cat "$WORK/out.L3")"
# L4: module flipped, default no
printf '# Project\n\nUnit tests default: no\n' > "$P/PROJECT.md"
mkdir -p "$BRIEF_DIR/Shop"; printf '# Brief\n\nUnit tests: yes\n' > "$BRIEF_DIR/Shop/module-brief.md"
run L4 "$ENTITY" >/dev/null
has L4 "unit	tests/unit/Total.test.mdl	names module Shop" && lacks L4 "Other.test.mdl" && has L4 "run	./bin/test-scratch.sh" && ok "L4 Shop flipped by a brief line: Shop's tests are selected" || bad "L4 flip" "$(cat "$WORK/out.L4")"
printf '# Admin\n| Part | This module | Why |\n|---|---|---|\n| Unit (`.test.mdl`) | **yes** | Java action |\n' > "$BRIEF_DIR/Admin-brief.md"
rm -rf "$BRIEF_DIR/Shop"
run L4b "$TOTAL" >/dev/null
lacks L4b "Total.test.mdl" && lacks L4b "Validate.test.mdl" && ok "L4b only Admin flipped (table row, flat brief): a Shop change selects no Shop test" || bad "L4b" "$(cat "$WORK/out.L4b")"
printf '# Admin\n| Unit (`.test.mdl`) | **no** (default) / yes | x |\n' > "$BRIEF_DIR/Admin-brief.md"
run L4c "$ENTITY" >/dev/null; has L4c "unit	off" && ok "L4c the unfilled brief template ('no (default) / yes') is not a flip" || bad "L4c" "$(cat "$WORK/out.L4c")"
rm -rf "$P/architecture"
printf '# Project\n\nUnit tests default: no\nUnit modules: Admin, Other\n' > "$P/PROJECT.md"
run L4d "$TOTAL" >/dev/null; lacks L4d "Total.test.mdl" && ok "L4d PROJECT.md 'Unit modules: Admin, Other': a Shop change selects no unit test" || bad "L4d" "$(cat "$WORK/out.L4d")"
run L4e "$ENTITY" >/dev/null; printf '# Project\n\nUnit tests default: no\nUnit modules: Shop\n' > "$P/PROJECT.md"; run L4f "$ENTITY" >/dev/null
has L4f "unit	tests/unit/Total.test.mdl	names module Shop" && lacks L4f "Other.test.mdl" && ok "L4f 'Unit modules: Shop' flips Shop only" || bad "L4f" "$(cat "$WORK/out.L4f")"
# L5 (P8): the Offer's recorded defaults are a scope, never a switch: default no, Admin flipped, Shop change = no Shop unit
printf 'Unit tests default: no\nUnit modules: Admin\n## Test strategy\n| Moment | Unit tests | Journeys | Status |\n|---|---|---|---|\n| Every change | affected | affected | CONFIRMED |\n| Module done | module | module | CONFIRMED |\n' > "$P/PROJECT.md"
run L5 "$TOTAL" >/dev/null
lacks L5 "Total.test.mdl" && lacks L5 "Validate.test.mdl" && ok "L5 row 'affected' + Admin flipped: a Shop change runs no Shop unit" || bad "L5" "$(cat "$WORK/out.L5")"
run L5b --moment module --module Shop >/dev/null
lacks L5b "Total.test.mdl" && ok "L5b module moment: Shop unit still off" || bad "L5b" "$(cat "$WORK/out.L5b")"
# L5c (P9): row none + module turned on = that module's unit runs
printf 'Unit tests default: no\nUnit modules: Shop\n## Test strategy\n| Every change | none | affected | CONFIRMED |\n| Module done | none | module | CONFIRMED |\n' > "$P/PROJECT.md"
run L5c "$TOTAL" >/dev/null
has L5c "unit	tests/unit/Total.test.mdl" && ok "L5c row none + Unit modules: Shop: Shop's unit runs" || bad "L5c" "$(cat "$WORK/out.L5c")"
run L5d --moment module --module Shop >/dev/null
has L5d "Total.test.mdl" && ok "L5d same at the module moment" || bad "L5d" "$(cat "$WORK/out.L5d")"
# L8: Unit modules parsing
um() { printf 'Unit tests default: no\n%s\n' "$1" > "$P/PROJECT.md"; }
um 'Unit modules: shop , ADMIN'; run L8a "$ENTITY" >/dev/null 2>&1
has L8a "Total.test.mdl" && ok "L8a names are case-insensitive" || bad "L8a" "$(cat "$WORK/out.L8a")"
um 'Unit modules: Shop # decided at CAC-5'; run L8b "$ENTITY" >/dev/null 2>&1
has L8b "Total.test.mdl" && ok "L8b a # comment is stripped" || bad "L8b" "$(cat "$WORK/out.L8b")"
um 'Unit modules: Shop (decided at CAC-5)'; run L8c "$ENTITY" >/dev/null 2>&1
has L8c "Total.test.mdl" && lacks L8c "Other.test.mdl" && ok "L8c a (...) comment is stripped" || bad "L8c" "$(cat "$WORK/out.L8c")"
um '- Unit modules: Shop'; run L8d "$ENTITY" >/dev/null 2>&1
has L8d "Total.test.mdl" && ok "L8d a bullet line is read" || bad "L8d" "$(cat "$WORK/out.L8d")"
um 'Unit modules: none'; run L8e "$ENTITY" >/dev/null 2>&1
has L8e "unit	off" && lacks L8e "unit on only for" && [ ! -s "$WORK/err.L8e" ] && ok "L8e none = no modules, no warning" || bad "L8e" "$(cat "$WORK/out.L8e" "$WORK/err.L8e")"
um 'Unit modules: Shop, Nowhere'; run L8f "$ENTITY" >/dev/null 2>&1
grep -q "'Nowhere'" "$WORK/err.L8f" && ! grep -q "'Shop'" "$WORK/err.L8f" && ok "L8f an unknown module warns on stderr, a known one does not" || bad "L8f" "$(cat "$WORK/err.L8f")"
# L9: the Offer table copied verbatim, edited cells must be read
OFFER='| Moment | Unit tests | Journeys | Status |
|---|---|---|---|
| Every change (build and feedback) | UC | JC | CONFIRMED |
| Module done | module, modules on only | module | CONFIRMED |
| Build complete, and before every later deploy | full | full | CONFIRMED |'
pm() { printf 'Unit tests default: yes\n\n## Test strategy\n%s\n' "$(printf '%s\n' "$OFFER" | sed "s/UC/$1/; s/JC/$2/")" > "$P/PROJECT.md"; }
pm none none; run L9a "$TOTAL" >/dev/null 2>&1
has L9a "unit=none journeys=none" && has L9a "unit	none	scope none" && lacks L9a ".test.mdl" && ok "L9a Offer label 'Every change (build and feedback)' with Unit none: no unit tests" || bad "L9a" "$(cat "$WORK/out.L9a")"
pm 'affected, modules on only' affected; run L9b "$TOTAL" >/dev/null 2>"$WORK/err.L9b"
has L9b "unit=affected journeys=affected" && has L9b "Total.test.mdl" && ! grep -qi "unknown" "$WORK/out.L9b" && [ ! -s "$WORK/err.L9b" ] && ok "L9b the Offer cell 'affected, modules on only' reads as affected, no message" || bad "L9b" "$(cat "$WORK/out.L9b" "$WORK/err.L9b")"
run L9c --moment module --module Shop >/dev/null 2>&1; has L9c "unit=module" && ok "L9c 'module, modules on only' reads as module" || bad "L9c" "$(head -1 "$WORK/out.L9c")"
run L9d --moment deploy >/dev/null 2>&1; has L9d "unit=full journeys=full" && has L9d "row 'Build complete" && ok "L9d 'Build complete, and before every later deploy' maps to build complete" || bad "L9d" "$(head -1 "$WORK/out.L9d")"
printf 'Unit tests default: yes\n## Test strategy\n| Every chnage | none | none | CONFIRMED |\n' > "$P/PROJECT.md"; run L9e "$TOTAL" >/dev/null 2>&1
grep -q 'row label "Every chnage"' "$WORK/err.L9e" && ok "L9e an unmappable row label warns on stderr" || bad "L9e" "$(cat "$WORK/err.L9e")"

pm 'none (decided CAC-5)' none; run L9f "$TOTAL" >/dev/null 2>"$WORK/err.L9f"
has L9f "unit=none" && lacks L9f ".test.mdl" && ! grep -qi "unknown" "$WORK/out.L9f" && ok "L9f a cell 'none (decided CAC-5)' reads as none: no unit tests" || bad "L9f" "$(cat "$WORK/out.L9f")"
printf 'Unit tests default: yes\n## Test strategy\n| Every change | none | none | CONFIRMED |\n| Modul done | none | none | CONFIRMED |\n' > "$P/PROJECT.md"; run L9g "$TOTAL" >/dev/null 2>"$WORK/err.L9g"
has L9g "unit=none" && grep -q 'row label "Modul done"' "$WORK/err.L9g" && ok "L9g an unknown label AFTER a matched row still warns" || bad "L9g" "$(cat "$WORK/err.L9g")"

# L6/L7: grants (unit on, so a module-wide selection would show)
cp "$BASE_PM" "$P/PROJECT.md"
run L6 "$GRANT" >/dev/null
has L6 "subject	microflow	Shop.SUB_Order_Total" && has L6 "part of that subject" && lacks L6 "names module Shop" && lacks L6 "Lookalike.test.mdl" && lacks L6 "data	NOT MEASURED	access" \
  && ok "L6 describe-style microflow plus its trailing grant: no module-wide unit selection" || bad "L6" "$(cat "$WORK/out.L6")"
has L6 "unit	tests/unit/Total.test.mdl	names Shop.SUB_Order_Total" && ok "L6 the microflow's own test is still selected" || bad "L6 own test"
run L7 "$EGRANT" >/dev/null
has L7 "data	NOT MEASURED	access Shop.User" && has L7 "names module Shop (data or access change)" && ok "L7 a standalone entity grant, unit yes: selected by module" || bad "L7" "$(cat "$WORK/out.L7")"

echo "== H: usage =="
RC=$(run H --moment later "$TOTAL"); [ "$RC" -eq 2 ] && ok "bad --moment exits 2" || bad "H rc=$RC"
RC=$(run H2 "$WORK/no-such.mdl"); [ "$RC" -eq 2 ] && ok "missing script exits 2" || bad "H2 rc=$RC"
RC=$(run H3); [ "$RC" -eq 2 ] && ok "a change with no script exits 2" || bad "H3 rc=$RC"
# L10: per-flow unit tests (Unit flows: in the module brief)
echo "== L10: Unit flows: per-flow selection =="
cp "$WORK/mxcli.orig" "$P/mxcli"; chmod +x "$P/mxcli"   # section K swaps the stub
printf '# Project\n\nUnit tests default: no\n' > "$P/PROJECT.md"
fl() { mkdir -p "$BRIEF_DIR/Shop"; printf '# Brief\n\n%b\n' "$1" > "$BRIEF_DIR/Shop/module-brief.md"; }
fl 'Unit flows:\n- SUB_Order_Total: money calculation\n- ACT_Order_Submit: REST call'
run L10a "$TOTAL" >/dev/null 2>&1
has L10a "unit	tests/unit/Total.test.mdl	names listed flow Shop.SUB_Order_Total (money calculation)" && ok "L10a listed and touched: its test is selected, with the reason" || bad "L10a" "$(cat "$WORK/out.L10a")"
lacks L10a "Submit.test.mdl" && ok "L10b listed but untouched (depth-2 caller): skipped" || bad "L10b" "$(cat "$WORK/out.L10a")"
lacks L10a "Validate.test.mdl" && ok "L10c unlisted but touched (depth-1 caller): skipped" || bad "L10c" "$(cat "$WORK/out.L10a")"
lacks L10a "Lookalike.test.mdl" && ok "L10d a look-alike flow name is not the listed flow" || bad "L10d"
[ ! -s "$WORK/err.L10a" ] && ok "L10e a clean list, known flows: no warning" || bad "L10e" "$(cat "$WORK/err.L10a")"
run L10f --depth 2 "$TOTAL" >/dev/null 2>&1
has L10f "Submit.test.mdl" && ok "L10f listed flow reached as a caller within --depth: selected" || bad "L10f" "$(cat "$WORK/out.L10f")"
run L10g "$ENTITY" >/dev/null 2>&1
has L10g "Total.test.mdl" && has L10g "Submit.test.mdl" && lacks L10g "Validate.test.mdl" && ok "L10g a data change in the module owes every listed flow, not the unlisted ones" || bad "L10g" "$(cat "$WORK/out.L10g")"
run L10h --moment module --module Shop >/dev/null 2>&1
has L10h "Total.test.mdl" && has L10h "Submit.test.mdl" && lacks L10h "Validate.test.mdl" && lacks L10h "Other.test.mdl" && ok "L10h module done: all listed flows' tests, nothing unlisted" || bad "L10h" "$(cat "$WORK/out.L10h")"
run L10i --moment deploy >/dev/null 2>&1
for t in Total Validate Submit Lookalike Other; do has L10i "$t.test.mdl" || bad "L10i full run lacks $t.test.mdl"; done; has L10i "unit	tests/unit/Other.test.mdl	full suite" && ok "L10i full run includes every test, listed or not" || bad "L10i"
fl 'Unit flows:\n- Shop.SUB_Order_Total: money calculation'
run L10j "$TOTAL" >/dev/null 2>&1
has L10j "Total.test.mdl" && ok "L10j a qualified name in the list is read" || bad "L10j" "$(cat "$WORK/out.L10j")"
fl 'Unit tests: yes'
run L10k "$TOTAL" >/dev/null 2>&1
has L10k "Total.test.mdl" && has L10k "Validate.test.mdl" && ok "L10k 'Unit tests: yes' without a list keeps the module-level selection" || bad "L10k" "$(cat "$WORK/out.L10k")"
fl 'Unit tests: yes\n\nUnit flows:\n- SUB_Order_Total: money calculation'
run L10l "$TOTAL" >/dev/null 2>&1
has L10l "Total.test.mdl" && lacks L10l "Validate.test.mdl" && ok "L10l a list beats 'Unit tests: yes' in the same brief" || bad "L10l" "$(cat "$WORK/out.L10l")"
fl 'Unit flows:\n- SUB_Order_Total\n- ACT_Order_Submit:   '
run L10m "$TOTAL" >/dev/null 2>&1
grep -q "Shop.SUB_Order_Total without a reason" "$WORK/err.L10m" && grep -q "Shop.ACT_Order_Submit without a reason" "$WORK/err.L10m" && has L10m "Total.test.mdl" && ok "L10m a flow listed without a reason warns (and is still selected)" || bad "L10m" "$(cat "$WORK/err.L10m")"
fl 'Unit flows:\n- SUB_Order_Total: money calculation\n- NoSuchFlow: invented'
run L10n "$TOTAL" >/dev/null 2>&1
grep -q "'Shop.NoSuchFlow'" "$WORK/err.L10n" && ! grep -q "'Shop.SUB_Order_Total'" "$WORK/err.L10n" && ok "L10n an unknown flow name warns, a known one does not" || bad "L10n" "$(cat "$WORK/err.L10n")"
run L10o --no-model "$TOTAL" >/dev/null 2>&1
! grep -q "NoSuchFlow" "$WORK/err.L10o" && ok "L10o --no-model skips the existence check" || bad "L10o"
fl 'Unit flows:\n- <ACT_Order_CalculateTotal>: <money calculation>'
run L10p "$TOTAL" >/dev/null 2>&1
lacks L10p "Total.test.mdl" && lacks L10p "Validate.test.mdl" && [ ! -s "$WORK/err.L10p" ] && ok "L10p the unfilled template placeholder lists nothing and warns nothing" || bad "L10p" "$(cat "$WORK/out.L10p" "$WORK/err.L10p")"
printf '# Project\n\nUnit tests default: no\n## Test strategy\n| Moment | Unit tests | Journeys | Status |\n|---|---|---|---|\n| Every change | none | affected | CONFIRMED |\n' > "$P/PROJECT.md"
fl 'Unit flows:\n- SUB_Order_Total: money calculation'
run L10q "$TOTAL" >/dev/null 2>&1
has L10q "Total.test.mdl" && ok "L10q row none + a Unit flows list: the listed flow's test runs (like L5c)" || bad "L10q" "$(cat "$WORK/out.L10q")"
# L10r..x: review fixes (module scope, parser forms, default yes, owed tests, casing, missing module)
am() { mkdir -p "$BRIEF_DIR/Admin"; printf '# Brief\n\n%b\n' "$1" > "$BRIEF_DIR/Admin/module-brief.md"; }
fl 'Unit flows:\n- SUB_Order_Total: money calculation'; am 'Unit flows:\n- ACT_Reset: reset logic'
run L10r --moment module --module Shop >/dev/null 2>&1
has L10r "Total.test.mdl" && lacks L10r "Other.test.mdl" && ok "L10r --moment module --module Shop: Shop's listed flows only, not Admin's" || bad "L10r" "$(cat "$WORK/out.L10r")"
run L10r2 --moment module --module Shop --module Admin >/dev/null 2>&1
has L10r2 "Total.test.mdl" && has L10r2 "Other.test.mdl" && ok "L10r2 both modules named: both lists run" || bad "L10r2" "$(cat "$WORK/out.L10r2")"
rm -rf "$BRIEF_DIR/Admin"
fl 'Unit flows:\n- SUB_Order_Total: money calculation\n\n- ACT_Order_Submit: REST call\n\n\n- VAL_Order: rule'
run L10s --moment module --module Shop >/dev/null 2>&1
has L10s "Total.test.mdl" && has L10s "Submit.test.mdl" && has L10s "Validate.test.mdl" && ok "L10s blank lines between bullets do not end the list" || bad "L10s" "$(cat "$WORK/out.L10s")"
fl 'Unit flows:\n- SUB_Order_Total (money): calculation\n- Shop.ACT_Order_Submit: REST call\n\n## Next heading\n- VAL_Order: not part of the list'
run L10t --moment module --module Shop >/dev/null 2>&1
has L10t "Total.test.mdl" && has L10t "Submit.test.mdl" && lacks L10t "Validate.test.mdl" && [ ! -s "$WORK/err.L10t" ] && ok "L10t 'ACT (note): reason' and 'Module.ACT: reason' are read; a heading ends the list" || bad "L10t" "$(cat "$WORK/out.L10t" "$WORK/err.L10t")"
fl 'Unit flows: SUB_Order_Total, ACT_Order_Submit'
run L10u --moment module --module Shop >/dev/null 2>&1
has L10u "Total.test.mdl" && has L10u "Submit.test.mdl" && grep -q "Shop.SUB_Order_Total without a reason" "$WORK/err.L10u" && grep -q "Shop.ACT_Order_Submit without a reason" "$WORK/err.L10u" && ok "L10u inline 'Unit flows: A, B' is read; items without a reason warn" || bad "L10u" "$(cat "$WORK/out.L10u" "$WORK/err.L10u")"
fl 'Unit flows:\n- SUB_Order_Total: ok\n- some words, not a flow\n- ACT_Order_Submit ?? why'
run L10v --moment module --module Shop >/dev/null 2>&1
grep -q 'cannot read "some words, not a flow"' "$WORK/err.L10v" && grep -q 'cannot read "ACT_Order_Submit ?? why"' "$WORK/err.L10v" && has L10v "Total.test.mdl" && ok "L10v an unreadable line warns with its text and does not drop the rest" || bad "L10v" "$(cat "$WORK/out.L10v" "$WORK/err.L10v")"
printf '# Project\n\nUnit tests default: yes\n' > "$P/PROJECT.md"
fl 'Unit flows:\n- SUB_Order_Total: money calculation'; am 'Unit tests: yes'
run L10w --moment module --module Shop --module Admin >/dev/null 2>&1
has L10w "Total.test.mdl" && lacks L10w "Validate.test.mdl" && lacks L10w "Submit.test.mdl" && has L10w "Other.test.mdl" && ok "L10w default yes: Shop narrowed to its list, Admin (no list) stays on" || bad "L10w" "$(cat "$WORK/out.L10w")"
run L10w2 "$TOTAL" >/dev/null 2>&1
has L10w2 "Total.test.mdl" && lacks L10w2 "Validate.test.mdl" && ok "L10w2 default yes, change moment: the unlisted touched caller's test is skipped" || bad "L10w2" "$(cat "$WORK/out.L10w2")"
rm -rf "$BRIEF_DIR/Admin"
printf '# Project\n\nUnit tests default: no\n' > "$P/PROJECT.md"
fl 'Unit flows:\n- SUB_Order_Total: money\n- NoTestYet: owed'
run L10x --moment module --module Shop >/dev/null 2>&1
grep -q "Shop.NoTestYet, which no .test.mdl names" "$WORK/err.L10x" && ! grep -q "SUB_Order_Total, which no" "$WORK/err.L10x" && has L10x "Total.test.mdl" && ok "L10x a listed flow with no test warns (owed), a tested one does not" || bad "L10x" "$(cat "$WORK/err.L10x")"
fl 'Unit flows:\n- sub_order_total: money'
run L10y --moment module --module Shop >/dev/null 2>&1
has L10y "Total.test.mdl" && grep -q "model has 'Shop.SUB_Order_Total' (casing differs)" "$WORK/err.L10y" && ok "L10y list casing differs: test still found (case-insensitive), casing warned" || bad "L10y" "$(cat "$WORK/out.L10y" "$WORK/err.L10y")"
fl 'Unit flows:\n- SUB_Order_Total: money\n- Nope.ACT_X: invented'
STUB_BADMOD=Nope run L10z --moment module --module Shop >/dev/null 2>&1
grep -q "module Nope not found in the model" "$WORK/err.L10z" && ! grep -q "Unit modules names" "$WORK/err.L10z" && has L10z "Total.test.mdl" && ok "L10z a listed module the model lacks warns 'not found in the model', non-fatal" || bad "L10z" "$(cat "$WORK/out.L10z" "$WORK/err.L10z")"
# L10aa..: review r2 (parser forms, mixed-module tests, CRLF)
printf '# Project\n\nUnit tests default: no\n' > "$P/PROJECT.md"
for _f in 'Unit flows:\n1. SUB_Order_Total: money\n2) ACT_Order_Submit: REST' 'Unit flows:\n+ SUB_Order_Total: money\n+ ACT_Order_Submit: REST' '## Unit flows\n\n- SUB_Order_Total: money\n- ACT_Order_Submit: REST' '### Unit flows:\n- SUB_Order_Total: money\n- ACT_Order_Submit: REST' 'Unit flows: SUB_Order_Total: money, ACT_Order_Submit: REST'; do
  fl "$_f"; run L10aa --moment module --module Shop >/dev/null 2>&1
  has L10aa "Total.test.mdl" && has L10aa "Submit.test.mdl" && lacks L10aa "Validate.test.mdl" && [ ! -s "$WORK/err.L10aa" ] && ok "L10aa list form read, both flows: $(printf '%s' "$_f" | head -c 28)" || bad "L10aa $_f" "$(cat "$WORK/out.L10aa" "$WORK/err.L10aa")"
done
fl '## Unit flows\n\nTBD, to be decided\n\n## Other'
run L10ab --moment module --module Shop >/dev/null 2>&1
grep -q "looks like a Unit flows block but lists no flow" "$WORK/err.L10ab" && ok "L10ab a Unit flows block that yields no flow warns" || bad "L10ab" "$(cat "$WORK/err.L10ab")"
printf '# Brief\r\n\r\nUnit flows:\r\n- SUB_Order_Total: money\r\n\r\n- ACT_Order_Submit: REST\r\n' > "$BRIEF_DIR/Shop/module-brief.md"
run L10ac --moment module --module Shop >/dev/null 2>&1
has L10ac "Total.test.mdl" && has L10ac "Submit.test.mdl" && [ ! -s "$WORK/err.L10ac" ] && ok "L10ac CRLF brief: flows read, no 'cannot read' warning" || bad "L10ac" "$(cat "$WORK/out.L10ac" "$WORK/err.L10ac")"
# L10af..: review r3 (rule-based block parser)
printf '# Project\n\nUnit tests default: no\n' > "$P/PROJECT.md"
fl 'Unit flows:\n- SUB_Order_Total: money, rounded\n  to cents per line\n- ACT_Order_Submit: REST'
run L10af --moment module --module Shop >/dev/null 2>&1
has L10af "Total.test.mdl" && has L10af "Submit.test.mdl" && [ ! -s "$WORK/err.L10af" ] && ok "L10af wrapped reason line then another bullet: both flows kept" || bad "L10af" "$(cat "$WORK/out.L10af" "$WORK/err.L10af")"
for _f in '## Unit flows (logic only)\n- SUB_Order_Total: money\n- ACT_Order_Submit: REST' 'Unit flows (logic only):\n- SUB_Order_Total: money\n- ACT_Order_Submit: REST' 'Unit flows (logic only): SUB_Order_Total: money, ACT_Order_Submit: REST'; do
  fl "$_f"; run L10ag --moment module --module Shop >/dev/null 2>&1
  has L10ag "Total.test.mdl" && has L10ag "Submit.test.mdl" && [ ! -s "$WORK/err.L10ag" ] && ok "L10ag header with (note) read: $(printf '%s' "$_f" | head -c 30)" || bad "L10ag $_f" "$(cat "$WORK/out.L10ag" "$WORK/err.L10ag")"
done
fl 'Unit flows:\n- SUB_Order_Total: money\n\nJourneys:\n- ACT_Order_Submit: REST'
run L10ah --moment module --module Shop >/dev/null 2>&1
has L10ah "Total.test.mdl" && lacks L10ah "Submit.test.mdl" && [ ! -s "$WORK/err.L10ah" ] && ok "L10ah a following 'Journeys:' field ends the block, silently" || bad "L10ah" "$(cat "$WORK/out.L10ah" "$WORK/err.L10ah")"
fl 'Unit flows:\n- SUB_Order_Total: money\nstray prose here\n- ACT_Order_Submit: REST'
run L10ai --moment module --module Shop >/dev/null 2>&1
has L10ai "Submit.test.mdl" && grep -q 'cannot read "stray prose here"' "$WORK/err.L10ai" && ok "L10ai other unindented line warns with its text, block continues" || bad "L10ai" "$(cat "$WORK/out.L10ai" "$WORK/err.L10ai")"
# mixed-module test: Admin has no list, so it is on
printf '/**\n * @test Mixed\n */\ncall microflow Admin.ACT_Reset();\ncall microflow Shop.VAL_Order();\n/\n' > "$P/tests/unit/Mixed.test.mdl"
fl 'Unit flows:\n- SUB_Order_Total: money'
printf '# Project\n\nUnit tests default: yes\n' > "$P/PROJECT.md"
run L10ad "$TOTAL" >/dev/null 2>&1
has L10ad "Mixed.test.mdl" && lacks L10ad "Validate.test.mdl" && has L10ad "Total.test.mdl" && ok "L10ad default yes: a test naming a listed AND an unlisted module is kept; a Shop-only unlisted test is dropped" || bad "L10ad" "$(cat "$WORK/out.L10ad")"
printf '# Project\n\nUnit tests default: no\n' > "$P/PROJECT.md"; am 'Unit tests: yes'
run L10ae "$TOTAL" >/dev/null 2>&1
has L10ae "Mixed.test.mdl" && lacks L10ae "Validate.test.mdl" && ok "L10ae default no, Admin flipped: the same mixed test is selected via Admin" || bad "L10ae" "$(cat "$WORK/out.L10ae")"
rm -f "$P/tests/unit/Mixed.test.mdl"; rm -rf "$BRIEF_DIR/Admin"
rm -rf "$P/architecture"
printf '# Project\n\nUnit tests default: no\n' > "$P/PROJECT.md"
[ ! -e "$P/.mxcli" ] && ok "wrote nothing into the project" || bad "project written"

echo "== wiring =="
grep -q 'affected-tests.sh' "$TOOLKIT/bin/lib/install-manifest.sh" && ok "named in install-manifest.sh" || bad "not in install-manifest.sh"
grep -q 'affected tests: ./bin/affected-tests.sh' "$TOOLKIT/project-bin/exec.sh" && ok "exec.sh points at it" || bad "exec.sh hint missing"

echo; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
