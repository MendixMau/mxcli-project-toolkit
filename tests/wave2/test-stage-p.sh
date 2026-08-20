#!/usr/bin/env bash
# Fixture for wave-2 Stage P: the merged check_stage_P() from four competing patches
# (bug01 stale-Q9 / bug02 resolver split-brain / bug03 anchored matching / the older
# gate-check-intake-patch.md).
#
# Run it against the PRE-fix script too — that is the positive control. A suite that has
# only ever seen the fix cannot show that it discriminates. Expected on the pre-fix script:
# T2, T3, T5a, T5b, T6a, T8 and T10 fail.
#
#   tests/wave2/test-stage-p.sh /path/to/gate-check.sh
#
# NOTE: gate-check.sh derives TOOLKIT_DIR from BASH_SOURCE, so a copy under /tmp silently
# changes every protocol-freshness verdict. Keep both scripts under the toolkit's bin/.
set -uo pipefail

GATE="${1:?usage: test-stage-p.sh /path/to/gate-check.sh}"
WORK="$(mktemp -d /tmp/stagep.XXXXXX)"
PASS=0; FAIL=0

ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

# A project with a nested analysis/<name>/ workstream, so ANALYSIS_BASE != PROJECT_DIR and
# the split-brain branch is reachable. $2 selects where intake.md is written: root|nested|both.
mkproj() {
  d="$WORK/$1"; mkdir -p "$d/analysis/Live/knowledge-base"
  printf 'Toolkit commit: none\n' > "$d/PROJECT.md"
  echo "$d"
}

# Echo the Stage P verdict line for a project dir.
stagep() { "$GATE" "$1" P 2>&1 | grep '^Stage P' | head -1; }

section() { printf '\n## %s\n\n%s\n' "$1" "$2"; }

echo "== T1: 'Answered (CONFIRMED):' is accepted (the regression that must never return) =="
# bug03's FIRST draft required ^answered: and turned PROJECT-A and PROJECT-E red,
# because both write this parenthetical-qualifier form. It is a real workspace convention.
P="$(mkproj t1)"
{ section '1. How many sites?' 'Answered (CONFIRMED): three — Rotterdam, Genk, Tilburg.'
  section '2. Which ERP?' 'Answered (ASSUMED): SAP S/4HANA.'
} > "$P/intake.md"
V="$(stagep "$P")"
case "$V" in *PASS*) ok "qualifier form accepted" ;; *) bad "qualifier form rejected: $V" ;; esac

echo "== T2: lowercase 'answered:' is accepted =="
P="$(mkproj t2)"
section '1. Where is the source?' 'answered: yes, it is src/.' > "$P/intake.md"
V="$(stagep "$P")"
case "$V" in *PASS*) ok "lowercase marker accepted" ;; *) bad "lowercase marker rejected: $V" ;; esac

echo "== T3: '- Status: Not Answered' must NOT pass =="
# The headline false-green: the literal text saying the question is unanswered contains the
# substring 'Answered', so the old unanchored match graded it as an answer.
P="$(mkproj t3)"
section '1. How many sites?' '- Status: Not Answered' > "$P/intake.md"
V="$(stagep "$P")"
case "$V" in
  *FAIL*) case "$V" in *'1. How many sites?'*) ok "negated form fails, and names the section" ;;
                       *) bad "fails but does not name the section: $V" ;; esac ;;
  *)      bad "'Not Answered' PASSED: $V" ;;
esac

echo "== T4: a real prose answer with no marker — known non-fix, but must be diagnosable =="
# A file-format gate cannot tell a prose answer from a prose restatement of the question, and
# guessing reintroduces the false-green being closed. So this still FAILs; what changed is that
# the message names the offending section AND the accepted markers, so the fix is a 2s edit.
P="$(mkproj t4)"
section '1. How many sites?' 'Three: Rotterdam, Genk, Tilburg. Confirmed with the client 2026-08-04.' > "$P/intake.md"
V="$(stagep "$P")"
if printf '%s' "$V" | grep -q 'FAIL' \
   && printf '%s' "$V" | grep -q '1. How many sites?' \
   && printf '%s' "$V" | grep -q "Answered (CONFIRMED)"; then
  ok "unmarked prose fails, naming the section and the accepted markers"
else
  bad "unmarked prose failure is not diagnosable: $V"
fi

echo "== T5a: stale pre-12828e4 Q9 fails AND is offered the repair =="
P="$(mkproj t5a)"
{ section '1. How many sites?' 'Answered: three.'
  printf '\n## 9. Interview mode: attended (default) or unattended?\n\n'
  printf 'Attended unless the user explicitly says otherwise. Attended = every gate question is asked\n'
  printf 'in chat and the agent waits for the answer. Unattended (opt-in only) = recommended options\n'
  printf 'are applied as ASSUMED and questions are logged in PROJECT.md for later reconciliation.\n'
} > "$P/intake.md"
V="$(stagep "$P")"
if printf '%s' "$V" | grep -q 'FAIL' && printf '%s' "$V" | grep -q -- '--repair-intake'; then
  ok "stale Q9 fails and names the repair path"
else
  bad "stale Q9 not detected / no repair offered: $V"
fi

echo "== T5b: an EDITED Q9 is NOT offered the repair =="
# The repair rewrites only byte-identical boilerplate. Offering it over text a human has
# touched would advertise a command that either does nothing or destroys a real answer.
P="$(mkproj t5b)"
{ section '1. How many sites?' 'Answered: three.'
  printf '\n## 9. Interview mode: attended (default) or unattended?\n\n'
  printf 'Attended unless the user explicitly says otherwise, and for THIS project we agreed\n'
  printf 'unattended for the nightly regeneration run only.\n'
} > "$P/intake.md"
V="$(stagep "$P")"
if printf '%s' "$V" | grep -q 'FAIL' && ! printf '%s' "$V" | grep -q -- '--repair-intake'; then
  ok "edited Q9 fails without offering a destructive repair"
else
  bad "edited Q9 was offered the boilerplate repair: $V"
fi

echo "== T6a: split brain — two DIFFERING intake.md files are refused, both named =="
P="$(mkproj t6a)"
section '1. How many sites?' 'Answered: three.'      > "$P/analysis/Live/intake.md"
section '1. How many sites?' '- Status: Not Answered' > "$P/intake.md"
V="$(stagep "$P")"
if printf '%s' "$V" | grep -q 'FAIL' \
   && printf '%s' "$V" | grep -q "$P/intake.md" \
   && printf '%s' "$V" | grep -q "$P/analysis/Live/intake.md"; then
  ok "two differing intakes refused, both paths named"
else
  bad "split brain not refused / not named: $V"
fi

echo "== T6b: byte-identical copies are NOT ambiguous =="
P="$(mkproj t6b)"
section '1. How many sites?' 'Answered: three.' > "$P/intake.md"
cp "$P/intake.md" "$P/analysis/Live/intake.md"
V="$(stagep "$P")"
case "$V" in *PASS*) ok "identical duplicate graded, not refused" ;; *) bad "identical duplicate refused: $V" ;; esac

echo "== T7: offer, not force — a gate run never rewrites intake.md, and a stage query writes nothing =="
P="$(mkproj t7)"
{ section '1. How many sites?' 'Answered: three.'
  printf '\n## 9. Interview mode: attended (default) or unattended?\n\n'
  printf 'Attended unless the user explicitly says otherwise. Attended = every gate question is asked\n'
  printf 'in chat and the agent waits for the answer. Unattended (opt-in only) = recommended options\n'
  printf 'are applied as ASSUMED and questions are logged in PROJECT.md for later reconciliation.\n'
} > "$P/intake.md"
BEFORE="$(cat "$P/intake.md")"
"$GATE" "$P" P >/dev/null 2>&1
"$GATE" "$P"   >/dev/null 2>&1     # full informational run too
[ "$BEFORE" = "$(cat "$P/intake.md")" ] \
  && ok "intake.md byte-unchanged by both a stage query and a full run" \
  || bad "gate-check REWROTE intake.md"
rm -f "$P/index.html"
"$GATE" "$P" P >/dev/null 2>&1
[ ! -f "$P/index.html" ] && ok "stage query left no board" || bad "stage query wrote a board"

echo "== T8: a bare 'Unverified.' without a how-to-verify clause must NOT pass =="
# The old FAIL message promised an "'Unverified — how to verify' line" while the match
# accepted the bare word — the gate's own error text described a rule it did not enforce.
P="$(mkproj t8)"
{ section '1. How many sites?' 'Unverified.'
  section '2. Which ERP?'      'Unverified — how to verify: ask the IT lead for the ERP contract.'
} > "$P/intake.md"
V="$(stagep "$P")"
if printf '%s' "$V" | grep -q 'FAIL' && printf '%s' "$V" | grep -q '1. How many sites?' \
   && ! printf '%s' "$V" | grep -q '2. Which ERP?'; then
  ok "bare Unverified fails; the qualified one still passes"
else
  bad "bare Unverified mis-graded: $V"
fi

echo "== T9: an intake with no '## ' sections fails, and the verdict names the file =="
P="$(mkproj t9)"
printf 'Some notes, no questions.\n' > "$P/intake.md"
V="$(stagep "$P")"
if printf '%s' "$V" | grep -q 'FAIL' && printf '%s' "$V" | grep -q "$P/intake.md"; then
  ok "no-sections file fails and is named"
else
  bad "no-sections case wrong: $V"
fi

echo "== T10: a nested-only intake.md is found (root has none) =="
P="$(mkproj t10)"
section '1. How many sites?' 'Answered: three.' > "$P/analysis/Live/intake.md"
V="$(stagep "$P")"
case "$V" in
  *PASS*) printf '%s' "$V" | grep -q "$P/analysis/Live/intake.md" \
            && ok "nested intake resolved and named" \
            || bad "passed but did not name the graded file: $V" ;;
  *)      bad "nested-only intake not found: $V" ;;
esac

echo "== T11: a missing intake.md does not pass, and says where it looked =="
# PENDING since 2026-08-20 rather than FAIL — absent is not wrong, and an intake that was never
# scaffolded is the ordinary state of a project on day one. What must not change is that it
# does NOT pass and that it names both search paths; assert those, not the word.
P="$(mkproj t11)"
V="$(stagep "$P")"
if ! printf '%s' "$V" | grep -q 'PASS' && printf '%s' "$V" | grep -q 'PENDING' \
   && printf '%s' "$V" | grep -q 'looked in'; then
  ok "missing intake reports PENDING and names both search paths"
else
  bad "missing intake message unhelpful: $V"
fi

echo ""
echo "PASS=$PASS FAIL=$FAIL   ($WORK)"
[ "$FAIL" -eq 0 ]
