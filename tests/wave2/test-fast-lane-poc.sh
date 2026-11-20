#!/usr/bin/env bash
# test-fast-lane-poc.sh — a POC build owes no build-ready, Stage 5 reads MANUAL, `Entry mode: poc`
# is a declared mode (#819 options 1 and 3).
#
# usage: bash tests/wave2/test-fast-lane-poc.sh [toolkit-root]
#   toolkit-root defaults to the checkout this fixture sits in; pass a master worktree to see the
#   cases fail there (the subject is gate-check.sh + project-bin/_position.sh + the kick-off brief).
#
# Field basis: simulated unattended POC build, 2026-11-20 (claude -p, stubbed Mendix tools): the
# agent wrote a module brief and fabricated analysis/sme-questions.md only to get build-ready to
# exit 0, read three scripts looking for an Entry mode a POC could declare, and ended with Stage 5
# FAIL where skills/poc-build.md promises MANUAL.
#
#   P1  Build type: poc + Interview mode: auto on a real init-project.sh scaffold: build-ready
#       exits 0, says N/A (Build type: poc), never escalates open questions, writes no
#       .build-ready-pass stamp; the same scaffold as a full build still FAILs (control)
#   P2  Entry mode: poc (no Build type line): tokeniser emits poc; mxtk_pos_read sets
#       POS_BUILD=poc and the project is not "undeclared"; gate-check prints no "No entry mode
#       declared" banner and reads Stage 1 "not owed (mode: Build type: poc)"
#   P3  Stage 5 under poc, with an unseen built page in docs/progress/look-summary.tsv: MANUAL and
#       the page still named; the full build FAILs on the same summary (control)
#   P4  the kick-off brief (CONVERSION-RUNBOOK.md) no longer demands build-ready of a POC
set -uo pipefail

TK="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
TK="$(cd "$TK" && pwd)"
WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/fast-lane-poc.XXXXXX")" && pwd -P)" || exit 2
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL - $1${2:+: $2}"; }
echo "== toolkit: $TK"

# One real scaffold (init-project.sh), copied per case.
printf 'zz-no-client-name-zz\n' > "$WORK/deny"
MXTK_NO_GUIDE=1 MXTK_LEAKGUARD_DENYFILE="$WORK/deny" bash "$TK/bin/init-project.sh" "$WORK/seed" >/dev/null 2>&1 </dev/null
[ -f "$WORK/seed/PROJECT.md" ] && [ -f "$WORK/seed/intake.md" ] || { echo "init-project.sh produced no scaffold"; exit 2; }

# poc-build.md "Who asks": Q16 answered, Q1-Q15 the verbatim Unverified marker.
mark_poc_intake() {
  awk '
    /^## 16\./ { print; print ""; print "Answered (CONFIRMED): POC build"; next }
    /^## [0-9]+\./ { print; print ""; print "Unverified — how to verify: not asked, POC build (Build type: poc, skills/poc-build.md); ask it if the build continues as a full build"; next }
    { print }' "$1/intake.md" > "$1/intake.tmp" && mv "$1/intake.tmp" "$1/intake.md"
}
N=0
mkp() { N=$((N+1)); P="$WORK/p$N"; cp -R "$WORK/seed" "$P"; mark_poc_intake "$P"; }
setline() { # setline <file> <key> <value|""> — replace or drop "<key>: ..." (drop when value empty)
  awk -v k="$2" -v v="$3" 'index($0, k ": ") == 1 { if (v != "") print k ": " v; done = 1; next } { print }
    END { if (!done && v != "") print k ": " v }' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}
gc() { out="$(bash "$TK/bin/gate-check.sh" --no-html "$@" 2>&1)"; rc=$?; }

echo "-- P1: Build type: poc, auto: build-ready is N/A, exit 0"
mkp; setline "$P/PROJECT.md" "Build type" poc; setline "$P/PROJECT.md" "Interview mode" auto
gc "$P" build-ready
[ "$rc" = 0 ] && ok "P1 build-ready exits 0 under Build type: poc" || bad "P1 build-ready exits 0" "rc=$rc"
case "$out" in *"BUILD-READY: N/A (Build type: poc)"*) ok "P1 verdict line says N/A (Build type: poc)" ;; *) bad "P1 verdict line says N/A" "$(printf '%s\n' "$out" | grep BUILD-READY)" ;; esac
case "$out" in *"NOT EVALUATED for open questions"*|*"Gate BLOCKED"*) bad "P1 no open-questions escalation" ;; *) ok "P1 no open-questions escalation (no sme-questions.md needed)" ;; esac
[ ! -f "$P/.mpr-snapshots/.build-ready-pass" ] && ok "P1 no build-ready stamp written for a POC" || bad "P1 no build-ready stamp written"
case "$out" in *"agent(s) still have unfilled"*) ok "P1 the checklist still prints (informational)" ;; *) bad "P1 the checklist still prints" ;; esac
mkp; setline "$P/PROJECT.md" "Build type" full; setline "$P/PROJECT.md" "Interview mode" auto
gc "$P" build-ready
[ "$rc" != 0 ] && case "$out" in *"BUILD-READY: FAIL"*) true ;; *) false ;; esac \
  && ok "P1 control: the same scaffold as a full build still FAILs build-ready" || bad "P1 control: full build FAILs" "rc=$rc"

echo "-- P2: Entry mode: poc"
. "$TK/project-bin/_position.sh"
[ "$(entry_mode_token "poc" 2>/dev/null)" = poc ] && [ "$(entry_mode_token "**POC** build (demo)" 2>/dev/null)" = poc ] \
  && ok "P2 tokeniser: poc and '**POC** build (demo)' read as poc" || bad "P2 tokeniser emits poc" "$(entry_mode_token poc 2>&1)"
[ "$(entry_mode_token "proof of concept" 2>/dev/null)" = "" ] && ok "P2 tokeniser: other words unchanged ('proof of concept' is not a token)" || bad "P2 tokeniser over-matches"
mkp; setline "$P/PROJECT.md" "Build type" ""; setline "$P/PROJECT.md" "Entry mode" poc
mxtk_pos_read "$P"
[ "$POS_BUILD" = poc ] && ! mxtk_pos_undeclared && ok "P2 mxtk_pos_read: POS_BUILD=poc, position declared" || bad "P2 mxtk_pos_read" "build=$POS_BUILD entry=$POS_ENTRY"
gc "$P"
case "$out" in *"No entry mode declared"*) bad "P2 no 'No entry mode declared' banner" ;; *) ok "P2 no 'No entry mode declared' banner" ;; esac
grep -q '^Stage 1 (Analysis): WAIVED.* not owed (mode: Build type: poc)' <<<"$out" \
  && ok "P2 Stage 1 reads not owed (mode: Build type: poc)" || bad "P2 Stage 1 not owed" "$(printf '%s\n' "$out" | grep '^Stage 1')"
gc "$P" build-ready
[ "$rc" = 0 ] && ok "P2 build-ready N/A under Entry mode: poc too" || bad "P2 build-ready N/A under Entry mode: poc" "rc=$rc"

echo "-- P3: Stage 5 under poc reads MANUAL, the unseen page still named"
look_summary() {
  mkdir -p "$1/docs/progress"
  printf 'as-of\t2026-11-20T10:00:00Z\nmodule\tRooms\t2\t1\nunseen\tRooms.Booking_Overview\t1763632800\n' > "$1/docs/progress/look-summary.tsv"
}
mkp; setline "$P/PROJECT.md" "Build type" poc; look_summary "$P"
gc "$P"
grep -q '^Stage 5 (Build): MANUAL.* look (Build type: poc.*Rooms.Booking_Overview' <<<"$out" \
  && ok "P3 Stage 5 MANUAL under poc, page named" || bad "P3 Stage 5 MANUAL under poc" "$(printf '%s\n' "$out" | grep '^Stage 5')"
mkp; setline "$P/PROJECT.md" "Build type" full; look_summary "$P"
gc "$P"
grep -q '^Stage 5 (Build): FAIL.* look: 1 of' <<<"$out" \
  && ok "P3 control: full build FAILs Stage 5 on the same summary" || bad "P3 control: full build FAILs" "$(printf '%s\n' "$out" | grep '^Stage 5')"

echo "-- P4: kick-off brief"
brief="$(awk '/^```text/{f=1;next} /^```/{f=0} f' "$TK/CONVERSION-RUNBOOK.md")"
grep -q 'Build type: poc: follow skills/poc-build.md instead (no build-ready' <<<"$brief" \
  && ok "P4 the kick-off brief exempts a POC from build-ready" || bad "P4 the kick-off brief exempts a POC" "$(printf '%s\n' "$brief" | grep -n 'build-ready')"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
