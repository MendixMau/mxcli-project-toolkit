#!/usr/bin/env bash
# test-kickoff.sh — bin/kickoff.sh writes the kickoff declarations in the form the gates parse,
# idempotently, and refuses what it does not know (#821 point 3).
#
# usage: bash tests/wave2/test-kickoff.sh [path-to-kickoff.sh]
#   on master there is no bin/kickoff.sh, so every case fails there.
#
# Field basis: two simulated builds, 2026-11-20 (claude -p, stubbed Mendix tools): both agents wrote
# the 16 intake markers and the register lines with ad-hoc Python heredocs (POC turns 6-18,
# requirements-driven turns 1-11); the POC agent read three scripts looking for a legal Entry mode.
# The scaffold is the real bin/init-project.sh output; the verdicts are the real gate-check.sh's.
#
#   K1  unknown --mode / --build-type / --interview / option: exit 2 naming the accepted values,
#       nothing written; no scaffold: exit 2 naming init-project.sh
#   K2  requirements-driven + auto: Stage P PASS; register lines and Stage-P rows written; the
#       template's defaults ASSUMED (intake + Assumptions); a second run changes no byte
#   K3  --mode poc: Build type: poc and poc-build.md's verbatim markers; Stage P PASS; Stage 1 not owed
#   K4  requirements-driven + steering: the unasked questions are listed and Stage P stays FAIL; an
#       --answers file for them makes it PASS, each answer verbatim; Q1 in --answers is refused
#   K5  a declared mode is never changed by a re-run: exit 3, files byte-identical
#   K7  no --by: nothing is CONFIRMED (rows ASSUMED "no person named", markers say so); a re-run
#       with --by <person> upgrades kickoff's own rows and markers to CONFIRMED, then is idempotent
#   K8  steering with no --build-type: Q16 is left unanswered and listed first, no Build type row
#   K6  --mode change records `Change an existing app`, which the shared tokeniser reads as
#       existing-app-change
set -uo pipefail

TK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
KO="${1:-$TK/bin/kickoff.sh}"
case "$KO" in /*) ;; *) KO="$PWD/$KO" ;; esac
WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/kickoff.XXXXXX")" && pwd -P)" || exit 2
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL - $1${2:+: $2}"; }
echo "== subject: $KO"
[ -f "$KO" ] || { bad "bin/kickoff.sh exists"; echo "PASS=$PASS FAIL=$FAIL"; exit 1; }

printf 'zz-no-client-name-zz\n' > "$WORK/deny"
MXTK_NO_GUIDE=1 MXTK_LEAKGUARD_DENYFILE="$WORK/deny" bash "$TK/bin/init-project.sh" "$WORK/seed" >/dev/null 2>&1 </dev/null
[ -f "$WORK/seed/intake.md" ] || { echo "init-project.sh produced no scaffold"; exit 2; }
N=0
mkp() { N=$((N+1)); P="$WORK/p$N"; cp -R "$WORK/seed" "$P"; }
ko() { out="$(bash "$KO" "$@" 2>&1)"; rc=$?; }
gcP() { bash "$TK/bin/gate-check.sh" --no-html "$1" P >/dev/null 2>&1; }
same() { cmp -s "$1/PROJECT.md" "$2/PROJECT.md" && cmp -s "$1/intake.md" "$2/intake.md"; }
sec() { awk -v n="$2" '$0 ~ "^## " n "\\." { s = 1; next } s && /^## / { exit } s' "$1/intake.md"; }

echo "-- K1: refusals"
mkp; cp -R "$P" "$WORK/k1-before"
ko "$P" --mode greenfield;                  [ "$rc" = 2 ] && case "$out" in *"accepted: poc requirements-driven migration change"*) true ;; *) false ;; esac && ok "K1 unknown --mode: exit 2 with the accepted list" || bad "K1 unknown --mode" "rc=$rc $out"
ko "$P" --mode migration --interview loud;  [ "$rc" = 2 ] && case "$out" in *"accepted: steering assist auto"*) true ;; *) false ;; esac && ok "K1 unknown --interview: exit 2 with the accepted list" || bad "K1 unknown --interview" "rc=$rc $out"
ko "$P" --mode migration --build-type mvp;  [ "$rc" = 2 ] && case "$out" in *"accepted: full poc"*) true ;; *) false ;; esac && ok "K1 unknown --build-type: exit 2 with the accepted list" || bad "K1 unknown --build-type" "rc=$rc $out"
ko "$P" --mode poc --build-type full;       [ "$rc" = 2 ] && ok "K1 --mode poc with --build-type full: exit 2 (contradiction)" || bad "K1 poc + full" "rc=$rc"
ko "$P" --mode migration --fast;            [ "$rc" = 2 ] && case "$out" in *"accepted: --mode"*) true ;; *) false ;; esac && ok "K1 unknown option: exit 2 listing the options" || bad "K1 unknown option" "rc=$rc $out"
ko "$P";                                    [ "$rc" = 2 ] && ok "K1 no --mode: exit 2" || bad "K1 no --mode" "rc=$rc"
same "$P" "$WORK/k1-before" && ok "K1 nothing was written by any refusal" || bad "K1 nothing written"
mkdir -p "$WORK/bare"; ko "$WORK/bare" --mode migration
[ "$rc" = 2 ] && case "$out" in *"init-project.sh"*) true ;; *) false ;; esac && ok "K1 no scaffold: exit 2 naming init-project.sh" || bad "K1 no scaffold" "rc=$rc $out"

echo "-- K2: requirements-driven, auto"
mkp; ko "$P" --mode requirements-driven --interview auto --by "the sponsor"
[ "$rc" = 0 ] && gcP "$P" && ok "K2 exit 0 and Stage P PASS (gate-check.sh P exit 0)" || bad "K2 Stage P PASS" "rc=$rc $(printf '%s\n' "$out" | tail -2)"
grep -q '^Entry mode: requirements-driven$' "$P/PROJECT.md" && grep -q '^Interview mode: auto$' "$P/PROJECT.md" && grep -q '^Build type: full$' "$P/PROJECT.md" \
  && ok "K2 register lines written" || bad "K2 register lines" "$(grep -E '^(Entry mode|Interview mode|Build type):' "$P/PROJECT.md")"
grep -q '^| P | Entry mode: requirements-driven | CONFIRMED | .*consentBy: the sponsor · consentAt: 20' "$P/PROJECT.md" \
  && grep -q '^| P | Build type: full | ASSUMED | .*consentBy: auto-mode' "$P/PROJECT.md" \
  && ok "K2 Stage-P rows: stated values CONFIRMED, the defaulted build type ASSUMED" || bad "K2 decision rows" "$(grep '^| P |' "$P/PROJECT.md")"
grep -q '^Assumed (auto-mode): balanced' <<<"$(sec "$P" 15)" && grep -q '^- Intake Q15: balanced — ASSUMED' "$P/PROJECT.md" \
  && ok "K2 a template default is ASSUMED in intake and listed under Assumptions" || bad "K2 default assumed" "$(sec "$P" 15 | head -3)"
grep -q '^Unverified — how to verify: not asked at kickoff (Interview mode: auto)' <<<"$(sec "$P" 7)" && ok "K2 a question with no default is Unverified, saying how" || bad "K2 no-default question" "$(sec "$P" 7 | head -3)"
cp -R "$P" "$WORK/k2-after1"; ko "$P" --mode requirements-driven --interview auto --by "the sponsor"
[ "$rc" = 0 ] && same "$P" "$WORK/k2-after1" && case "$out" in *"nothing to change"*) true ;; *) false ;; esac \
  && ok "K2 idempotent: the second run changes no byte and says so" || bad "K2 idempotent" "rc=$rc $(diff "$WORK/k2-after1/PROJECT.md" "$P/PROJECT.md"; diff "$WORK/k2-after1/intake.md" "$P/intake.md")"

echo "-- K3: poc"
mkp; ko "$P" --mode poc --interview auto
[ "$rc" = 0 ] && gcP "$P" && ok "K3 Stage P PASS" || bad "K3 Stage P PASS" "rc=$rc"
grep -q '^Build type: poc$' "$P/PROJECT.md" && ok "K3 Build type: poc written" || bad "K3 Build type: poc"
grep -qx 'Unverified — how to verify: not asked, POC build (Build type: poc, skills/poc-build.md); ask it if the build continues as a full build' <<<"$(sec "$P" 4)" \
  && grep -qx 'Answered (kickoff call, no person named): POC build' <<<"$(sec "$P" 16)" && ok "K3 poc-build.md's verbatim markers" || bad "K3 poc markers" "$(sec "$P" 4 | head -3)"
g="$(bash "$TK/bin/gate-check.sh" --no-html "$P" 2>&1)"
grep -q '^Stage 1 (Analysis): WAIVED.* not owed (mode: Build type: poc)' <<<"$g" && ok "K3 Stage 1 not owed (mode: Build type: poc)" || bad "K3 Stage 1 not owed"

echo "-- K4: steering, then --answers"
mkp; ko "$P" --mode requirements-driven --build-type full --interview steering --by "the sponsor"
[ "$rc" = 0 ] && case "$out" in *"Still to ask in chat (Interview mode: steering): Q2 Q3 Q4 Q5 Q6 Q7 Q8 Q10 Q11 Q12 Q13 Q14 Q15"*) true ;; *) false ;; esac \
  && ok "K4 steering: the 13 unasked questions are listed, none invented" || bad "K4 unasked listed" "$(printf '%s\n' "$out" | tail -3)"
gcP "$P" && bad "K4 Stage P must still FAIL with questions unasked" || ok "K4 Stage P stays FAIL until they are answered"
{ echo "# answers given in chat"; for n in 2 3 4 5 6 7 8 10 11 12 13 14 15; do echo "Q$n: answer $n | from chat"; done; } > "$WORK/answers"
ko "$P" --mode requirements-driven --build-type full --interview steering --by "the sponsor" --answers "$WORK/answers"
[ "$rc" = 0 ] && gcP "$P" && ok "K4 --answers: Stage P PASS" || bad "K4 --answers Stage P" "rc=$rc $(printf '%s\n' "$out" | tail -2)"
grep -qx 'Answered (CONFIRMED by the sponsor): answer 12 | from chat' <<<"$(sec "$P" 12)" && ok "K4 each answer written verbatim" || bad "K4 verbatim" "$(sec "$P" 12 | head -3)"
printf 'Q1: migration\n' > "$WORK/bad-answers"; ko "$P" --mode requirements-driven --interview steering --answers "$WORK/bad-answers"
[ "$rc" = 2 ] && ok "K4 Q1 in --answers refused (it is --mode)" || bad "K4 Q1 refused" "rc=$rc"

echo "-- K5: a declared mode is not changed by a re-run"
cp -R "$WORK/k2-after1" "$WORK/k5"; P="$WORK/k5"; cp -R "$P" "$WORK/k5-before"
ko "$P" --mode migration --interview auto
[ "$rc" = 3 ] && same "$P" "$WORK/k5-before" && case "$out" in *"Mode changes are decisions"*) true ;; *) false ;; esac \
  && ok "K5 exit 3, nothing written, the rule named" || bad "K5 refused" "rc=$rc $out"
ko "$P" --mode requirements-driven --interview steering --by "the sponsor"
[ "$rc" = 3 ] && ok "K5 an Interview mode change is refused too" || bad "K5 interview change" "rc=$rc"

echo "-- K7: no --by, then --by"
mkp; ko "$P" --mode requirements-driven --interview auto
[ "$rc" = 0 ] && ! grep -q 'CONFIRMED' <<<"$(grep '^| P |' "$P/PROJECT.md")" \
  && grep -q '^| P | Interview mode: auto | ASSUMED | .*no person named' "$P/PROJECT.md" \
  && grep -qx 'Answered (kickoff call, no person named): auto' <<<"$(sec "$P" 9)" \
  && ok "K7 without --by nothing is CONFIRMED (Interview mode: auto included)" || bad "K7 no CONFIRMED without --by" "$(grep '^| P |' "$P/PROJECT.md")"
ko "$P" --mode requirements-driven --interview auto --by "the sponsor"
[ "$rc" = 0 ] && grep -q '^| P | Interview mode: auto | CONFIRMED | .*consentBy: the sponsor' "$P/PROJECT.md" \
  && [ "$(grep -c '^| P | Interview mode:' "$P/PROJECT.md")" = 1 ] && grep -qx 'Answered (CONFIRMED by the sponsor): auto' <<<"$(sec "$P" 9)" \
  && ok "K7 --by upgrades kickoff's own row (one row, CONFIRMED) and marker" || bad "K7 --by upgrade" "$(grep '^| P |' "$P/PROJECT.md")"
cp -R "$P" "$WORK/k7"; ko "$P" --mode requirements-driven --interview auto --by "the sponsor"
same "$P" "$WORK/k7" && ok "K7 then idempotent" || bad "K7 idempotent after upgrade"

echo "-- K8: steering, build type not stated"
mkp; ko "$P" --mode requirements-driven --interview steering --by "the sponsor"
[ "$rc" = 0 ] && case "$out" in *"Still to ask in chat (Interview mode: steering): Q16 Q2"*) true ;; *) false ;; esac \
  && [ -z "$(sec "$P" 16 | grep -iE '^(answered|assumed|unverified)')" ] && ! grep -q '^| P | Build type' "$P/PROJECT.md" \
  && ok "K8 Q16 unanswered and listed first, no Build type row" || bad "K8 Q16 unanswered" "$(printf '%s\n' "$out" | grep 'Still'; grep '^| P |' "$P/PROJECT.md")"

echo "-- K6: change an existing app"
mkp; ko "$P" --mode change --build-type full --interview assist
. "$TK/bin/lib/entry-mode.sh"
grep -q '^Entry mode: Change an existing app$' "$P/PROJECT.md" && [ "$(entry_mode_token "Change an existing app")" = existing-app-change ] && [ "$rc" = 0 ] \
  && ok "K6 'Change an existing app' recorded verbatim, read as existing-app-change" || bad "K6 change mode" "rc=$rc $(grep '^Entry mode' "$P/PROJECT.md")"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
