#!/usr/bin/env bash
# Fixture for #686 speed cuts 1, 2 and 3 as PROJECT.md `Pipeline mode: high-speed | balanced |
# high-quality` (no line = balanced): what runs per build row, and what waits for module close.
#
# usage: bash tests/wave2/test-module-close-cadence.sh [toolkit-root]
#
# Run against a worktree of master ee12a615, 50 of the 66 cases fail; the 16 that pass there are
# guards that master's behaviour survives where it should (high-quality = master per row, the
# 2026-09-19 line, MXTK_PREPUSH_BUILD=always, a refused push on a failing build, the table last,
# no stamp without a full build, no sync note when the line is set, no page check without a page, two-tree no-change stays check, no first-page LOOK on a second page row or in high-speed). Against the previous head 89969a24 every run-2 tweak case fails (W2, W3 first row, W4 x3, M3).
#   E1-E7  exec.sh per-row lane (the real exec.sh, run on a stub project; it prints the lane and
#          then refuses an uncommitted model, writing nothing), per mode. balanced (no line): one
#          1280 LOOK, no journeys, the plain-words note; logic = the exec gate only, unless
#          `## Test strategy` row `Every change` names a scope (unit and journeys columns each, E3/E8).
#          high-speed: no LOOK per row.
#          high-quality: master's per-row journeys + 390/1280 LOOK + per-row unit tests.
#   I1     init-project.sh's generated CLAUDE.local.md: one viewport per page script, both at module
#          review, and the 2026-09-19 fidelity-is-not-a-LOOK line kept.
#   P1-P11 the pre-push hook (install-project-hooks.sh): under `Gate mode: check`, the full build runs
#          once per module (balanced, high-speed), every push under high-quality or
#          MXTK_PREPUSH_BUILD=always; builds on: no build recorded yet, an unreadable _common.sh,
#          N deferred pushes, a Java fingerprint change; a v1
#          hook is replaced in place and fails --check (so sync-project.sh refreshes it).
#   S1     sync-project.sh prints one line when PROJECT.md has no Pipeline mode line.
#   W2-W4  run-2 tweaks: balanced runs the journeys that reach a changed page once per row (W2);
#          a 390 LOOK at a module's first page row, not in high-speed (W3, a real exec on stubs);
#          the --watch restart line after every full build: exec, pre-push, module-close (W4);
#          high-speed polish 75% / 3 rounds (M3).
#   T1-T3  two-tree checkout: the hook and exec.sh share mxtk_model_java_fp (no Java change =
#          deferred; a change under app/javasource = full build, in the hook and in exec.sh).
#   M4     module-close.sh records a full build for the pre-push hook.
#   M5     its report carries a `Polish: n of cap` row per page (countable cap; template only).
#   E9     a page script with a co-located GRANT (logic) still gets its mode's per-row page check.
#   M1-M3  module-close.sh's report carries the bounded polish loop: 85% / 3 rounds with no line,
#          75/2 high-speed, 90/5 high-quality; PROJECT.md `UI polish:` overrides both numbers.
# Golden MDL input is the toolkit's own shipped scripts (as test-exec-change-class.sh uses).
set -uo pipefail
TK="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mc-cadence.XXXXXX")"
export MXTK_LEAKGUARD_DENYFILE="$WORK/denylist"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; return 0; }
echo "== subject: $TK"
# Match on the captured output without a pipe: `printf | grep -q` under pipefail fails when grep
# exits on its first match while printf is still writing (SIGPIPE).
has_out() { case "$out" in *"$1"*) return 0 ;; esac; return 1; }

UI_MDL="$TK/tests/wave2/fixtures/page-fidelity-mocks/bind-contract-alter.mdl"   # ALTER PAGE → ui-only
LOGIC_MDL="$TK/skills/agents-examples/tool-write.example.mdl"                   # microflow → logic
GRANT_MDL="$TK/examples/stylegallery/mdlsource/gallery/90-gallery-home.mdl"     # CREATE PAGE + its GRANT → logic, with a page
NOTE="Screens are polished and checked at module close; mid-module pages may look rough, that's expected."

echo "-- E: exec.sh per-row lane"
E="$WORK/exec"; mkdir -p "$E/bin"; cp "$TK/project-bin/exec.sh" "$TK/project-bin/_common.sh" "$E/bin/"
printf 'x' > "$E/App.mpr"; ( cd "$E" && git init -q )
lane() {  # $1 script, $2 PROJECT.md body
  printf '%s\n' "$2" > "$E/PROJECT.md"
  ( cd "$E" && MXTK_ROOT="$TK" timeout 120 bash bin/exec.sh "$1" 2>&1 ) | sed -n '1,6p'
}
out=$(lane "$UI_MDL" "# P")
case "$out" in *"Pipeline mode: balanced"*"per row: one quick LOOK at 1280 of the page you just changed; no .test.mdl."*) ok "E1 no line = balanced; ui-only: one 1280 LOOK per row" ;; *) bad "E1 ui-only lane" "$out" ;; esac
case "$out" in *"390/1280 LOOK and the full journey set run once at module close"*) ok "E1 ui-only: full journey set + 390/1280 LOOK at module close" ;; *) bad "E1 module close" "$out" ;; esac
case "$out" in *"(embedders of a changed snippet/layout) run once per row (~1 min)"*"journeys that reach it: ./bin/affected-tests.sh"*) ok "W2 balanced page row: one run of the journeys that reach the page (run-2 tweak)" ;; *) bad "W2 balanced per-row journeys" "$out" ;; esac
case "$out" in *"$NOTE"*) ok "E1 the plain-words note prints with the lane" ;; *) bad "E1 note missing" "$out" ;; esac
case "$out" in *"affected tests: ./bin/affected-tests.sh"*) bad "E1 still points at per-row affected tests" "$out" ;; *) ok "E1 no per-row affected-tests pointer" ;; esac
out=$(lane "$LOGIC_MDL" "# P")
case "$out" in *"per row: the exec gate only."*"run once at module close"*"tests owed at module close"*) ok "E2 balanced logic, no strategy row: exec gate only, unit tests at module close" ;; *) bad "E2 logic lane" "$out" ;; esac
TS='## Test strategy
| Moment | Unit tests | Journeys | Status |
|---|---|---|---|'
out=$(lane "$LOGIC_MDL" "Unit tests default: yes
$TS
| Every change (build and feedback) | affected, modules on only | affected | CONFIRMED |")
case "$out" in *"unit tests whose subject this change touched + the changed pages' journeys"*"opts in"*"affected tests: ./bin/affected-tests.sh"*) ok "E3 'Every change' row affected | affected: per-row unit tests AND journeys (both columns honoured)" ;; *) bad "E3 opt-in" "$out" ;; esac
out=$(lane "$LOGIC_MDL" "Unit tests default: yes
$TS
| Every change (build and feedback) | none (exec gate only) | none | CONFIRMED |")
case "$out" in *"per row: the exec gate only."*) ok "E4 'Every change' row none: exec gate only" ;; *) bad "E4 none row" "$out" ;; esac
ROWJ="Unit tests default: no
$TS
| Every change | none | affected | CONFIRMED |"
out=$(lane "$UI_MDL" "$ROWJ")
case "$out" in *"Pipeline mode: balanced"*"(embedders of a changed snippet/layout) re-run once per row (PROJECT.md ## Test strategy 'Every change' journeys column)"*"affected tests: ./bin/affected-tests.sh"*) ok "E8 a CONFIRMED journeys column keeps per-row journeys in balanced (ui-only)" ;; *) bad "E8 journeys column ui" "$out" ;; esac
out=$(lane "$LOGIC_MDL" "$ROWJ")
case "$out" in *"per row: the changed pages' journeys (PROJECT.md ## Test strategy 'Every change' opts in)"*) ok "E8 ... and in the logic lane, without per-row unit tests" ;; *) bad "E8 journeys column logic" "$out" ;; esac
# A page script with its co-located GRANT classifies as logic; it still owes the mode's per-row look
# (PR #700 mode experiment: 8 of 10 page scripts got no per-row LOOK under balanced).
out=$(lane "$GRANT_MDL" "# P")
case "$out" in *"Change class: logic"*"per row: the exec gate only."*"Pages it writes: one quick LOOK at 1280 of each page/snippet it changed + one run of the journeys that reach it"*) ok "E9 balanced, page + GRANT (logic): the 1280 LOOK per row AND the logic lane" ;; *) bad "E9 balanced page+grant" "$out" ;; esac
out=$(lane "$GRANT_MDL" "Pipeline mode: high-quality")
case "$out" in *"re-run only the tests whose subject"*"Pages it writes: the journeys of every page the change reaches + a LOOK at 390 and 1280"*"affected tests:"*) ok "E9 high-quality, page + GRANT: journeys + the 390/1280 LOOK per row, plus per-row tests" ;; *) bad "E9 high-quality page+grant" "$out" ;; esac
out=$(lane "$GRANT_MDL" "Pipeline mode: high-speed")
case "$out" in *"Pages it writes: no per-row LOOK"*) ok "E9 high-speed, page + GRANT: no per-row LOOK, said so" ;; *) bad "E9 high-speed page+grant" "$out" ;; esac
out=$(lane "$LOGIC_MDL" "# P")
case "$out" in *"Pages it writes"*) bad "E9 a script with no page statement got a page check" "$out" ;; *) ok "E9 no page statement: no per-row page check" ;; esac
out=$(lane "$UI_MDL" "**Pipeline mode:** high-speed")
case "$out" in *"Pipeline mode: high-speed"*"per row: the exec gate only; no journeys, no LOOK"*"390/1280 LOOK run once at module close"*"$NOTE"*) ok "E5 high-speed ui-only: no LOOK per row, everything at module close" ;; *) bad "E5 high-speed" "$out" ;; esac
out=$(lane "$UI_MDL" "Pipeline mode: high-quality")
case "$out" in *"Pipeline mode: high-quality"*"(embedders of a changed snippet/layout) re-run once, + a LOOK at 390 and 1280"*) ok "E6 high-quality ui-only: journeys + LOOK at 390 and 1280 per row (master)" ;; *) bad "E6 high-quality ui" "$out" ;; esac
case "$out" in *"$NOTE"*) bad "E6 high-quality prints the rough-pages note" ;; *) ok "E6 high-quality: no rough-pages note" ;; esac
out=$(lane "$LOGIC_MDL" "Pipeline mode: high-quality")
case "$out" in *"re-run only the tests whose subject this change touched"*"affected tests: ./bin/affected-tests.sh"*) ok "E7 high-quality logic: unit tests per row (master)" ;; *) bad "E7 high-quality logic" "$out" ;; esac
out=$(lane "$LOGIC_MDL" "Pipeline mode: turbo")
case "$out" in *"Pipeline mode: balanced"*"per row: the exec gate only."*) ok "E7 an unknown value reads as balanced" ;; *) bad "E7 unknown value" "$out" ;; esac

echo "-- I: init-project.sh generated CLAUDE.local.md"
mkdir -p "$WORK/fakebin"; for s in open xdg-open; do printf '#!/bin/sh\nexit 0\n' > "$WORK/fakebin/$s"; chmod +x "$WORK/fakebin/$s"; done
IP="$WORK/initproj"; mkdir -p "$IP"
PATH="$WORK/fakebin:$PATH" bash "$TK/bin/init-project.sh" "$IP" >/dev/null 2>&1
CL="$IP/CLAUDE.local.md"
if [ -f "$CL" ]; then
  flat=$(tr '\n' ' ' < "$CL" | tr -s ' ')
  case "$flat" in *"look at the page at one viewport (1280px; 390px too on a module's first page), run the journeys that reach it once"*) ok "I1 one viewport per page script (+390 on a module's first page), its journeys once" ;; *) bad "I1 per-script viewport" "$(grep -n -A3 'Before any page MDL' "$CL")" ;; esac
  case "$flat" in *"Both 1280px and 390px on every page, the full journey set and the polish loop run once at module review"*) ok "I1 both viewports, all journeys, polish at module review" ;; *) bad "I1 module review" ;; esac
  case "$flat" in *"1280px and 390px and write what you saw"*) bad "I1 still asks for both viewports per page script" ;; *) ok "I1 no dual-viewport per page script" ;; esac
  case "$flat" in *"a 100% fidelity score once matched under half its wireframe (2026-09-19)"*) ok "I1 protected 2026-09-19 line kept" ;; *) bad "I1 2026-09-19 line lost" ;; esac
else bad "I1 init-project.sh wrote no CLAUDE.local.md"; fi

IN="$IP/intake.md"
if [ -f "$IN" ]; then
  flat=$(tr '\n' ' ' < "$IN")
  case "$flat" in *"Pipeline mode: \`high-speed\`, \`balanced\` (default) or \`high-quality\`?"*"high-speed**: fastest"*"balanced**: each changed page gets one quick look and one run of the journeys that reach it"*"high-quality**: checks every page after every change; slowest"*) ok "I2 intake asks the pipeline mode, three options with trade-offs" ;; *) bad "I2 intake question" ;; esac
else bad "I2 init-project.sh wrote no intake.md"; fi
grep -q '^Pipeline mode: balanced$' "$IP/PROJECT.md" 2>/dev/null && ok "I3 a new PROJECT.md says Pipeline mode: balanced" || bad "I3 PROJECT.md line"
[ "$(grep -ciE '^[*_ >-]*Pipeline mode:' "$IP/PROJECT.md")" = 1 ] && ok "I3 exactly one line reads as the setting (no comment line looks like one)" || bad "I3 extra setting-like lines" "$(grep -niE '^[*_ >-]*Pipeline mode:' "$IP/PROJECT.md")"

echo "-- P: pre-push full build once per module"
S="$WORK/hooks"; mkdir -p "$S/bin" "$S/.claude/loop"
cp "$TK/project-bin/model-stamp.sh" "$TK/project-bin/_common.sh" "$TK/project-bin/install-project-hooks.sh" "$S/bin/"
printf '#!/usr/bin/env bash\necho ran > .claude/full-ran; exit "${FAKE_VM_RC:-0}"\n' > "$S/bin/verify-model.sh"; chmod +x "$S/bin/"*.sh
( cd "$S" && git init -q && git config user.email t@t && git config user.name t && printf 'm' > App.mpr \
  && mkdir mprcontents && echo u > mprcontents/u && git add -A && git commit -qm i ) >/dev/null 2>&1
st() { ( cd "$S" && PROJECT_ROOT="$S" "$@" ) >/dev/null 2>&1; }
# A v1 hook from an earlier toolkit: --check must fail on it, and the install must replace it, not chain it.
printf '#!/usr/bin/env bash\n# mxtk-pre-push full-build hook v1 — old\nexit 0\n' > "$S/.git/hooks/pre-push"; chmod +x "$S/.git/hooks/pre-push"
st bash bin/install-project-hooks.sh
chk=$( cd "$S" && PROJECT_ROOT="$S" bash bin/install-project-hooks.sh --check 2>&1 )
printf '%s\n' "$chk" | grep -q 'pre-push full-build hook installed' \
  && ok "P1 v1 hook replaced by v2; --check passes" || bad "P1 --check after install"
[ ! -e "$S/.git/hooks/pre-push.pre-mxtk" ] && ok "P1 the old v1 hook was replaced in place, not chained" || bad "P1 v1 hook chained as pre-push.pre-mxtk"
cp "$S/.git/hooks/pre-push" "$WORK/pp-v2"
printf '#!/usr/bin/env bash\n# mxtk-pre-push full-build hook v1 — old\nexit 0\n' > "$S/.git/hooks/pre-push"
( cd "$S" && PROJECT_ROOT="$S" bash bin/install-project-hooks.sh --check ) >/dev/null 2>&1 && bad "P1 --check passed on a v1 hook" || ok "P1 --check fails on a v1 hook (sync-project.sh refreshes it)"
cp "$WORK/pp-v2" "$S/.git/hooks/pre-push"
PPH="$S/.git/hooks/pre-push"
echo "checks 1" > "$S/.claude/loop/gate-kind.state"
st env MXTK_STAMP_KIND=check MXTK_STAMP_ERRORS=0 bash bin/model-stamp.sh write pass "exec.sh x (mx check)"
Z=0000000000000000000000000000000000000000
pp() {  # $1 = stdin line; rest = env; sets rc and out
  local line="$1"; shift
  rm -f "$S/.claude/full-ran"
  out=$( cd "$S" && printf '%s\n' "$line" | env "$@" "$PPH" origin x 2>&1 ); rc=$?
}
HEAD0=$(cd "$S" && git rev-parse HEAD)
pp "refs/heads/m $HEAD0 refs/heads/m $Z"
{ [ "$rc" = 0 ] && [ -e "$S/.claude/full-ran" ] && [ -e "$S/.claude/loop/prepush-build.last" ] && has_out 'no full build recorded'; } \
  && ok "P2 first push with no full build recorded here: builds once, stamp written" || bad "P2 first rc=$rc" "$out"
pp "refs/heads/m $HEAD0 refs/heads/m $Z"
{ [ "$rc" = 0 ] && [ ! -e "$S/.claude/full-ran" ] && has_out 'deferred to module close'; } \
  && ok "P2 no Pipeline mode line (balanced), mid-module push: no full build, says it is deferred" || bad "P2 rc=$rc" "$out"
pp "refs/heads/m $HEAD0 refs/heads/m $Z" MXTK_PREPUSH_BUILD=always
{ [ "$rc" = 0 ] && [ -e "$S/.claude/full-ran" ]; } && ok "P3 MXTK_PREPUSH_BUILD=always: full build on every push" || bad "P3 rc=$rc" "$out"
printf 'Pipeline mode: high-quality\n' > "$S/PROJECT.md"
pp "refs/heads/m $HEAD0 refs/heads/m $Z"
{ [ "$rc" = 0 ] && [ -e "$S/.claude/full-ran" ]; } && ok "P3 Pipeline mode: high-quality: full build on every push" || bad "P3 hq rc=$rc" "$out"
printf 'Pipeline mode: high-speed\n' > "$S/PROJECT.md"
pp "refs/heads/m $HEAD0 refs/heads/m $Z"
{ [ "$rc" = 0 ] && [ ! -e "$S/.claude/full-ran" ] && has_out 'Pipeline mode: high-speed'; } && ok "P3 Pipeline mode: high-speed: deferred to module close" || bad "P3 hs rc=$rc" "$out"
printf 'Pipeline mode: balanced\n' > "$S/PROJECT.md"
pp "refs/heads/m $HEAD0 refs/heads/m $Z"
{ [ "$rc" = 0 ] && [ ! -e "$S/.claude/full-ran" ]; } && ok "P3 Pipeline mode: balanced: deferred to module close" || bad "P3 bal rc=$rc" "$out"
rm -f "$S/PROJECT.md"
# A project whose bin/_common.sh predates mxtk_pipeline_mode (master's copy): the mode cannot be read.
cp "$S/bin/_common.sh" "$S/bin/_common.sh.new"
( cd "$TK" && git show ee12a615:project-bin/_common.sh ) > "$S/bin/_common.sh" 2>/dev/null
pp "refs/heads/m $HEAD0 refs/heads/m $Z"
{ [ "$rc" = 0 ] && [ -e "$S/.claude/full-ran" ] && has_out 'could not be read'; } && ok "P9 mode unreadable (an older _common.sh): builds (the safe side)" || bad "P9 rc=$rc" "$out"
mv "$S/bin/_common.sh.new" "$S/bin/_common.sh"
rm -f "$S/.claude/loop/prepush-deferred"
pp "refs/heads/m $HEAD0 refs/heads/m $Z" MXTK_PREPUSH_MAX_DEFERRED=2; r1=$rc; f1=$([ -e "$S/.claude/full-ran" ] && echo y)
pp "refs/heads/m $HEAD0 refs/heads/m $Z" MXTK_PREPUSH_MAX_DEFERRED=2; f2=$([ -e "$S/.claude/full-ran" ] && echo y)
pp "refs/heads/m $HEAD0 refs/heads/m $Z" MXTK_PREPUSH_MAX_DEFERRED=2
{ [ -z "$f1" ] && [ -z "$f2" ] && [ -e "$S/.claude/full-ran" ] && has_out 'pushes in a row deferred'; } \
  && ok "P10 no module close for N pushes (N=2): the third push builds" || bad "P10 f1=$f1 f2=$f2 rc=$rc" "$out"
pp "refs/heads/m $HEAD0 refs/heads/m $Z" MXTK_PREPUSH_MAX_DEFERRED=2
{ [ "$rc" = 0 ] && [ ! -e "$S/.claude/full-ran" ]; } && ok "P10 the build reset the count: next push deferred again" || bad "P10 reset rc=$rc" "$out"
printf 'checks 1\njava 0000\n' > "$S/.claude/loop/gate-kind.state"
pp "refs/heads/m $HEAD0 refs/heads/m $Z"
{ [ "$rc" = 0 ] && [ -e "$S/.claude/full-ran" ] && has_out 'Java/JavaScript/theme files changed'; } && ok "P11 Java fingerprint differs from the last full build's: builds" || bad "P11 rc=$rc" "$out"
echo "checks 1" > "$S/.claude/loop/gate-kind.state"
rm -f "$S/.claude/loop/prepush-build.last"
mkdir -p "$S/docs/progress/module-close"; echo "# Module close: Shop" > "$S/docs/progress/module-close/Shop.md"
pp "refs/heads/m $HEAD0 refs/heads/m $Z" FAKE_VM_RC=1
{ [ "$rc" = 1 ] && [ -e "$S/.claude/full-ran" ] && [ ! -e "$S/.claude/loop/prepush-build.last" ]; } \
  && ok "P4 module-close report, build fails: push refused, no marker written" || bad "P4 rc=$rc" "$out"
pp "refs/heads/m $HEAD0 refs/heads/m $Z"
{ [ "$rc" = 0 ] && [ -e "$S/.claude/full-ran" ] && [ -e "$S/.claude/loop/prepush-build.last" ]; } \
  && ok "P5 module-close report newer than the last build: full build runs, marker written" || bad "P5 rc=$rc" "$out"
has_out 'full build done: if the app runs with --watch, run `mxcli run restart` before the next LOOK' \
  && ok "W4 pre-push: the --watch restart line after its full build" || bad "W4 pre-push watch line" "$out"
pp "refs/heads/m $HEAD0 refs/heads/m $Z"
{ [ "$rc" = 0 ] && [ ! -e "$S/.claude/full-ran" ]; } && ok "P6 next push in the same module: no full build" || bad "P6 rc=$rc" "$out"
( cd "$S" && git add docs && git commit -qm "module close Shop" ) >/dev/null 2>&1; HEAD1=$(cd "$S" && git rev-parse HEAD)
touch -t 200001010000 "$S/docs/progress/module-close/Shop.md"
pp "refs/heads/m $HEAD1 refs/heads/m $HEAD0"
{ [ "$rc" = 0 ] && [ -e "$S/.claude/full-ran" ] && has_out 'module-close commit'; } \
  && ok "P7 a pushed module-close commit: full build runs" || bad "P7 rc=$rc" "$out"
st env MXTK_STAMP_ERRORS=0 bash bin/model-stamp.sh write pass "verify-model.sh"
pp "refs/heads/m $HEAD1 refs/heads/m $HEAD0" MXTK_PREPUSH_BUILD=always
{ [ "$rc" = 0 ] && [ ! -e "$S/.claude/full-ran" ]; } && ok "P8 full stamp: no build, whatever the mode" || bad "P8 rc=$rc" "$out"

echo "-- T: two-tree checkout (.mpr under app/): one Java fingerprint for exec.sh and the hook"
T="$WORK/twotree"; mkdir -p "$T/bin" "$T/.claude/loop" "$T/app/javasource/Mod/actions"
cp "$TK/project-bin/model-stamp.sh" "$TK/project-bin/_common.sh" "$TK/project-bin/install-project-hooks.sh" "$T/bin/"
printf '#!/usr/bin/env bash\necho ran > .claude/full-ran; exit 0\n' > "$T/bin/verify-model.sh"; chmod +x "$T/bin/"*.sh
( cd "$T" && git init -q && git config user.email t@t && git config user.name t && printf 'm' > app/App.mpr \
  && mkdir app/mprcontents && echo u > app/mprcontents/u && echo 'class A {}' > app/javasource/Mod/actions/A.java \
  && git add -A && git commit -qm i ) >/dev/null 2>&1
( cd "$T" && PROJECT_ROOT="$T" bash bin/install-project-hooks.sh ) >/dev/null 2>&1
( cd "$T" && PROJECT_ROOT="$T" MXTK_STAMP_KIND=check MXTK_STAMP_ERRORS=0 bash bin/model-stamp.sh write pass "exec.sh x (mx check)" ) >/dev/null 2>&1
# exec.sh's own recorder: gate_kind_decide's _gk_java_fp, extracted as test-exec-gate-kind.sh does.
sed -n '/^_GK_STATE=/,/^}/p' "$TK/project-bin/exec.sh" > "$WORK/gk.sh"
gkfp() { ( cd "$T" && . "$TK/project-bin/_common.sh" && PROJECT_ROOT="$T" SCRIPT=/dev/null PATCH_MODE=0 MXBUILD=/nonexistent && . "$WORK/gk.sh" && gate_kind_decide >/dev/null 2>&1; _gk_java_fp ) 2>/dev/null; }
printf 'checks 1\njava %s\n' "$(gkfp)" > "$T/.claude/loop/gate-kind.state"; touch "$T/.claude/loop/prepush-build.last"
TH=$(cd "$T" && git rev-parse HEAD)
tpp() { rm -f "$T/.claude/full-ran"; out=$( cd "$T" && printf 'refs/heads/m %s refs/heads/m %s\n' "$TH" "$Z" | "$T/.git/hooks/pre-push" origin x 2>&1 ); rc=$?; }
tpp
{ [ "$rc" = 0 ] && [ ! -e "$T/.claude/full-ran" ] && has_out deferred; } \
  && ok "T1 two-tree, no Java change: the hook's fingerprint matches exec.sh's, push deferred" || bad "T1 rc=$rc" "$out"
echo 'class A { int x; }' > "$T/app/javasource/Mod/actions/A.java"
tpp
{ [ "$rc" = 0 ] && [ -e "$T/.claude/full-ran" ] && has_out 'Java/JavaScript/theme files changed'; } \
  && ok "T2 two-tree, Java under app/javasource changed: full build" || bad "T2 rc=$rc" "$out"
printf '# P\n\nGate mode: check\n' > "$T/PROJECT.md"
mkdir -p "$T/tools"; for x in mxbuild mx; do printf '#!/bin/sh\nexit 0\n' > "$T/tools/$x"; chmod +x "$T/tools/$x"; done
printf 'alter page Mod.P set title = '"'"'x'"'"';\n' > "$WORK/tt.mdl"
tgk() { ( cd "$T" && . "$TK/project-bin/_common.sh" && PROJECT_ROOT="$T" SCRIPT="$WORK/tt.mdl" PATCH_MODE=0 MXBUILD="$T/tools/mxbuild" MXBUILD_PATH="$T/tools/mxbuild" && . "$WORK/gk.sh" && gate_kind_decide && echo "$GATE_KIND|$GATE_KIND_WHY" ) 2>/dev/null; }
gk=$(tgk)
case "$gk" in "full|Java/JavaScript"*) ok "T3 two-tree, exec.sh on a Java change: full build" ;; *) bad "T3 exec gate kind" "$gk" ;; esac
printf 'checks 1\njava %s\n' "$(gkfp)" > "$T/.claude/loop/gate-kind.state"
gk=$(tgk)
case "$gk" in check\|*) ok "T3 two-tree, fingerprint re-recorded, no change: exec.sh stays check-only" ;; *) bad "T3 no-change gate kind" "$gk" ;; esac

echo "-- M: module-close.sh polish loop"
M="$WORK/mc"; mkdir -p "$M/bin"
cp "$TK/project-bin/module-close.sh" "$TK/project-bin/_common.sh" "$M/bin/"; : > "$M/App.mpr"
printf '#!/bin/sh\ncase "$1" in docker) echo "Build succeeded" ;; esac\n' > "$M/mxcli"
for f in metrics-ledger verify-module look-ledger; do printf '#!/bin/sh\nexit 0\n' > "$M/bin/$f.sh"; done
chmod +x "$M/mxcli" "$M/bin/"*.sh
( cd "$M" && bash bin/module-close.sh Shop >/dev/null 2>&1 ); R="$M/docs/progress/module-close/Shop.md"
flat=$(tr '\n' ' ' < "$R" 2>/dev/null)
case "$flat" in *"LOOK every page at 390 and 1280"*"up to 3 rounds"*"fidelity ≥ 85% AND a written LOOK with no blocking issue"*"a score alone never passes"*"UNMEASURED: the LOOK decides"*"design/ui-reviews/"*"does not block the module"*)
  ok "M1 no line (balanced) polish loop: 390 + 1280, 85% / 3 rounds, score alone never passes, gap logged, not blocking" ;; *) bad "M1 report" "$(cat "$R" 2>/dev/null)" ;; esac
case "$flat" in *"affected-tests.sh --moment module --module Shop"*) ok "M1 journeys + unit tests owed at module close" ;; *) bad "M1 tests pointer" ;; esac
grep -q '^| Shop.<Page> | Polish: 0 of 3 |' "$R" && ok "M5 a countable 'Polish: n of cap' row per page (template)" || bad "M5 polish row" "$(grep -n Polish "$R")"
grep -q '^| Page | Role |' "$R" && [ "$(tail -2 "$R" | head -1 | cut -c1-7)" = "| Page " ] && ok "M1 the Page | Role table stays last (row-groups.sh reads it)" || bad "M1 table moved" "$(tail -3 "$R")"
printf '# P\n\n**UI polish:** 90%% / 2 rounds\n' > "$M/PROJECT.md"
( cd "$M" && bash bin/module-close.sh Shop >/dev/null 2>&1 ); flat=$(tr '\n' ' ' < "$R")
case "$flat" in *"up to 2 rounds"*"fidelity ≥ 90%"*) ok "M2 PROJECT.md 'UI polish: 90% / 2 rounds' overrides both" ;; *) bad "M2 override" "$(grep -n polish -i "$R")" ;; esac
for mv in "high-speed 3 75" "high-quality 5 90"; do set -- $mv
  printf 'Pipeline mode: %s\n' "$1" > "$M/PROJECT.md"
  ( cd "$M" && bash bin/module-close.sh Shop >/dev/null 2>&1 ); flat=$(tr '\n' ' ' < "$R")
  case "$flat" in *"Pipeline mode: $1), up to $2 rounds"*"fidelity ≥ $3%"*) ok "M3 $1: $3% / $2 rounds" ;; *) bad "M3 $1" "$(grep -n -i polish "$R")" ;; esac
done
printf 'Pipeline mode: high-quality\nUI polish: 80%% / 4 rounds\n' > "$M/PROJECT.md"
( cd "$M" && bash bin/module-close.sh Shop >/dev/null 2>&1 ); flat=$(tr '\n' ' ' < "$R")
case "$flat" in *"up to 4 rounds"*"fidelity ≥ 80%"*) ok "M3 UI polish overrides a mode's numbers" ;; *) bad "M3 override" "$(grep -n -i polish "$R")" ;; esac

printf '#!/bin/sh\nexit 0\n' > "$M/bin/model-stamp.sh"; chmod +x "$M/bin/model-stamp.sh"; rm -f "$M/.claude/loop/prepush-build.last"
( cd "$M" && bash bin/module-close.sh Shop >/dev/null 2>&1 )
{ [ -e "$M/.claude/loop/prepush-build.last" ] && [ -z "$(find "$M/docs/progress/module-close" -name '*.md' -newer "$M/.claude/loop/prepush-build.last")" ]; } \
  && ok "M4 module-close with a full stamp records the build for the pre-push hook, not older than its report" || bad "M4 stamp" "$(ls -la --time-style=full-iso "$M/.claude/loop" "$R" 2>&1)"
printf '#!/bin/sh\nexit 1\n' > "$M/bin/model-stamp.sh"; rm -f "$M/.claude/loop/prepush-build.last"
( cd "$M" && bash bin/module-close.sh Shop >/dev/null 2>&1 )
[ ! -e "$M/.claude/loop/prepush-build.last" ] && ok "M4 no full stamp: nothing recorded" || bad "M4 recorded without a full build"

# module-close.sh's own full build (Gate mode: check, stamp kind check) prints the --watch line.
mkdir -p "$M/.claude/loop"; echo "checks 1" > "$M/.claude/loop/gate-kind.state"; printf 'kind: check\n' > "$M/.claude/.model-verified"
printf '#!/bin/sh\nexit 1\n' > "$M/bin/model-stamp.sh"; printf '#!/bin/sh\necho "✓ mxbuild: 0 errors"\n' > "$M/bin/verify-model.sh"; chmod +x "$M/bin/"*.sh
out=$( cd "$M" && bash bin/module-close.sh Shop 2>&1 )
case "$out" in *'full build done: if the app runs with --watch, run `mxcli run restart` before the next LOOK'*) ok "W4 module-close: the --watch restart line after its full build" ;; *) bad "W4 module-close watch line" "$out" ;; esac

echo "-- X: a successful exec (stub mxcli/mxbuild): first page row of a module, --watch line"
X="$WORK/xproj"; mkdir -p "$X/bin" "$X/.claude" "$X/mprcontents/84/77" "$X/mdlsource" "$WORK/xjdk/bin"
printf 'not a real model\n' > "$X/Fixture.mpr"; printf 'bson\n' > "$X/mprcontents/84/77/84776610-13b2-48cb-a265-d5e984d63129.mxunit"
cp "$TK"/project-bin/* "$X/bin/" 2>/dev/null; chmod +x "$X/bin/"*
XLINT="$TK/tests/wave2/fixtures/lint-conv020-v028/lint-conv020-v0.28.0.out"
printf '#!/usr/bin/env bash\ncase "$1" in\n  exec) printf "x\\n" >> mprcontents/84/77/84776610-13b2-48cb-a265-d5e984d63129.mxunit ;;\n  lint) cat "%s" ;;\nesac\nexit 0\n' "$XLINT" > "$X/mxcli"
printf '#!/usr/bin/env bash\nfor a in "$@"; do case "$a" in --write-errors=*) printf "{\\"problems\\":[]}" > "${a#--write-errors=}" ;; esac; done\nexit 0\n' > "$WORK/xmxbuild"
printf '#!/bin/sh\nexit 0\n' > "$WORK/xjdk/bin/java"; chmod +x "$X/mxcli" "$WORK/xmxbuild" "$WORK/xjdk/bin/java"
cp "$UI_MDL" "$X/mdlsource/01-page.mdl"; cp "$UI_MDL" "$X/mdlsource/02-page.mdl"
( cd "$X" && ./bin/lint-gate.sh --update-baseline ) >/dev/null 2>&1
( cd "$X" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm fixture ) >/dev/null 2>&1
xexec() { ( cd "$X" && MXTK_ROOT="$TK" SP_RESTART=0 MXTK_NO_INSTALL=1 SKIP_DOCTOR=1 MXTK_SYNC_REFRESH=1 MXBUILD_PATH="$WORK/xmxbuild" JAVA_HOME="$WORK/xjdk" timeout 300 bash bin/exec.sh "$@" 2>&1 ); }
xcommit() { ( cd "$X" && git add -A && git -c user.email=t@t -c user.name=t commit -qm step ) >/dev/null 2>&1; }
out=$(xexec mdlsource/01-page.mdl)
case "$out" in *"✓ Script applied"*"first page row of Demo: also a LOOK at 390"*) ok "W3 balanced, the module's first page row: also a LOOK at 390" ;; *) bad "W3 first page row" "$(printf '%s' "$out" | tail -15)" ;; esac
# #686: the gate now builds a copy (.mxtk/build/), so the served folder is untouched and exec says
# that instead of asking for a restart (tests/wave2/test-build-tree.sh has the in-place fallback).
case "$out" in *"full build ran in .mxtk/build/ — the running app's deployment/ was not touched"*) ok "W4 exec.sh: after a full gate, says the build left the app's deployment/ alone" ;; *) bad "W4 exec watch line" "$(printf '%s' "$out" | tail -8)" ;; esac
case "$out" in *'full build done: if the app runs with --watch'*) bad "W4 exec.sh still asks for a restart after a build in the copy" ;; *) ok "W4 exec.sh: no restart line after a build in the copy" ;; esac
xcommit; out=$(xexec mdlsource/02-page.mdl)
case "$out" in *"✓ Script applied"*) case "$out" in *"first page row of"*) bad "W3 second page row of Demo still says first" ;; *) ok "W3 the module's second page row: no extra 390 LOOK" ;; esac ;; *) bad "W3 second exec did not apply" "$(printf '%s' "$out" | tail -10)" ;; esac
xcommit; rm -rf "$X/.claude/loop/look"; printf 'Pipeline mode: high-speed\n' > "$X/PROJECT.md"; xcommit
out=$(xexec mdlsource/01-page.mdl)
case "$out" in *"✓ Script applied"*) case "$out" in *"first page row of"*) bad "W3 high-speed got the first-page 390 LOOK" ;; *) ok "W3 high-speed: no first-page 390 LOOK" ;; esac ;; *) bad "W3 high-speed exec did not apply" "$(printf '%s' "$out" | tail -10)" ;; esac

echo "-- S: sync-project.sh names a missing Pipeline mode"
sed -i.bak '/^Pipeline mode:/d' "$IP/PROJECT.md"; rm -f "$IP/PROJECT.md.bak"
out=$(bash "$TK/bin/sync-project.sh" "$IP" --dry-run 2>&1)
case "$out" in *"Pipeline mode not set → balanced: journeys, the 390+1280 LOOK and the full build now run at module close. Set \`Pipeline mode: high-quality\`"*) ok "S1 no line: sync says balanced, and how to keep the old cadence" ;; *) bad "S1 sync note" "$(printf '%s' "$out" | tail -5)" ;; esac
printf 'Pipeline mode: high-quality\n' >> "$IP/PROJECT.md"
out=$(bash "$TK/bin/sync-project.sh" "$IP" --dry-run 2>&1)
case "$out" in *"Pipeline mode not set"*) bad "S1 note printed although the line is set" ;; *) ok "S1 line set: no note" ;; esac

echo
echo "module-close cadence: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
