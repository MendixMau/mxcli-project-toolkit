#!/usr/bin/env bash
# Fixture for wave-2 #4: gate-check.sh must not key its stage results on bash INDEXED ARRAYS.
#
# bash evaluates an array subscript as an arithmetic expression. RESULTS[$stage] with a
# non-integer id is therefore a syntax error, and that error aborts the enclosing compound
# command — including the `exit 1` inside it — dropping the script through to its final
# `exit 0`. A forged PASS on a project with no artifacts at all.
#
# The hazard is LATENT on the shipped script: the stage whitelist rejects 0.5 before any
# subscript is evaluated. So the end-to-end exit code cannot discriminate, and this fixture
# tests the ACCESSOR DIRECTLY instead — extracted from the script under test, never copied,
# so it cannot drift away from what actually ships. T2 is the positive control: it builds the
# forged pass out of a real indexed array, proves it forges, then proves the accessor doesn't.
#
#   tests/wave2/test-bug04-subscripts.sh /path/to/gate-check.sh
#
# Against the PRE-fix script: T1/T2/T3/T5 fail (the functions do not exist / the array forges);
# T4 passes on both, because Patch A is behaviour-identical on every whitelisted stage and that
# is precisely the claim T4 exists to check.
#
# NOTE: gate-check.sh derives TOOLKIT_DIR from BASH_SOURCE, so a copy under /tmp silently
# changes every protocol-freshness verdict. Keep the script under test under the toolkit's bin/.
set -uo pipefail

GATE="${1:?usage: test-bug04-subscripts.sh /path/to/gate-check.sh}"
WORK="$(mktemp -d /tmp/bug04.XXXXXX)"
PASS=0; FAIL=0

ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

# ── Extract tbl_add/tbl_get FROM THE SCRIPT UNDER TEST ────────────────────────
# sed range from the tbl_add definition to the close of tbl_get. Testing a hand-copied
# duplicate would prove only that the duplicate works.
ACC="$WORK/accessor.sh"
sed -n '/^tbl_add() {/,/^}/p;/^tbl_get() {/,/^}/p' "$GATE" > "$ACC"

echo "== T1: the accessor exists and is a table, not an array =="
if grep -q '^tbl_get() {' "$ACC" && grep -q '^tbl_add() {' "$ACC"; then
  ok "tbl_add/tbl_get extracted from the script under test"
else
  bad "no tbl_add/tbl_get in $GATE — still on indexed arrays?"
  echo ""; echo "PASS=$PASS FAIL=$FAIL   ($WORK)"; exit 1
fi
if grep -nE '(RESULTS|NOTES|STAGE_TITLES)\[' "$GATE" | grep -vE '^[0-9]+:[[:space:]]*#' | grep -q .; then
  bad "an arithmetic subscript on RESULTS/NOTES/STAGE_TITLES still remains:"
  grep -nE '(RESULTS|NOTES|STAGE_TITLES)\[' "$GATE" | grep -vE '^[0-9]+:[[:space:]]*#' | sed 's/^/       /'
else
  ok "no RESULTS/NOTES/STAGE_TITLES subscript outside comments"
fi

echo "== T2: POSITIVE CONTROL — an indexed array forges a pass, the accessor does not =="
# 2a. Reproduce the bug in isolation, so the test proves the hazard is real rather than
#     assuming it. If this stops forging, bash changed and the rest of the file needs a rethink.
cat > "$WORK/forge.sh" <<'EOF'
set -uo pipefail
declare -a R; R[0]=FAIL
REQ="0.5"
if [ -n "$REQ" ]; then
  v="${R[$REQ]:-}"
  exit 1                       # unconditional failure — and it is SKIPPED
fi
exit 0
EOF
/bin/bash "$WORK/forge.sh" >/dev/null 2>&1
[ $? -eq 0 ] && ok "control: indexed array forges exit 0 (the bug is real on this bash)" \
             || bad "control did not forge — bash behaviour changed, re-derive this fixture"

# 2b. The same shape, using the REAL accessor. Must reach its exit 1.
{ cat "$ACC"; cat <<'EOF'
set -uo pipefail
RESULTS_TBL=""
tbl_add RESULTS_TBL 0 FAIL
REQ="0.5"
if [ -n "$REQ" ]; then
  if tbl_get "$REQ" "$RESULTS_TBL"; then v="$TBL_VALUE"; else v=""; fi
  exit 1
fi
exit 0
EOF
} > "$WORK/noforge.sh"
/bin/bash "$WORK/noforge.sh" >/dev/null 2>&1
[ $? -eq 1 ] && ok "accessor: 0.5 reaches the exit 1 — no forged pass even if the whitelist admitted it" \
             || bad "accessor still forged a pass on 0.5"

echo "== T3: the accessor is EXACT-MATCH, not arithmetic =="
# Every one of these aliased onto a real stage under the indexed array: 05 -> stage 5 (octal),
# 0x0 -> stage 0 (hex), 1+1 -> stage 2, a bare name -> stage 0 (unset -> 0).
{ cat "$ACC"; cat <<'EOF'
set -uo pipefail
T=""
tbl_add T 0 "zero"
tbl_add T 5 "five"
tbl_add T 7 "seven with | a pipe and 'quotes' and  spaces"
tbl_add T build-ready "br"
Stage3=0
for k in 0 5 7 build-ready 05 0x0 1+1 " 5" Stage3 "" 0.5; do
  if tbl_get "$k" "$T"; then echo "[$k]=$TBL_VALUE"; else echo "[$k]=ABSENT"; fi
done
EOF
} > "$WORK/exact.sh"
OUT="$(/bin/bash "$WORK/exact.sh" 2>&1)"
expect() {
  if printf '%s\n' "$OUT" | grep -qxF "$1"; then ok "accessor $1"; else
    bad "accessor expected '$1', got: $(printf '%s\n' "$OUT" | grep -F "[${1%%=*}" | head -1)"
  fi
}
expect "[0]=zero"
expect "[5]=five"
expect "[7]=seven with | a pipe and 'quotes' and  spaces"
expect "[build-ready]=br"
expect "[05]=ABSENT"
expect "[0x0]=ABSENT"
expect "[1+1]=ABSENT"
expect "[ 5]=ABSENT"
expect "[Stage3]=ABSENT"
expect "[]=ABSENT"
expect "[0.5]=ABSENT"

echo "== T4: end-to-end behaviour is IDENTICAL on every whitelisted stage =="
# Patch A's whole claim. A bare project plus the ack line, so every stage FAILs or is MANUAL.
P="$WORK/proj"; mkdir -p "$P"
TK="$(cd "$(dirname "$GATE")/.." && pwd)"
printf 'Toolkit commit: %s\n' "$(git -C "$TK" rev-parse --short HEAD)" > "$P/PROJECT.md"
rc() { "$GATE" --no-html "$P" $1 >/dev/null 2>&1; echo "$?"; }
chk() {
  local got; got="$(rc "$1")"
  [ "$got" = "$2" ] && ok "stage '$1' -> exit $2" || bad "stage '$1' expected exit $2, got $got"
}
chk 0 1            # FAIL
chk 3 1            # FAIL
chk 7 1            # FAIL
chk 5 2            # MANUAL is not a pass
chk P 1            # no intake.md
chk 05 2           # whitelist still rejects the aliases (defence in depth)
chk 1+1 2
chk xyz 2
chk 0.5 2          # still rejected by the untouched whitelist, end to end
chk "" 0           # informational run never blocks
# The PASS path must still be reachable — a table that returned "" for everything would
# satisfy every FAIL assertion above and look green.
printf '## Sign-off\n\nConfirmed by: A Tester on 2026-08-12\n' > "$P/triage.md"
chk 0 0
: > "$P/triage.md"
chk 0 1

echo "== T5: a non-integer stage id does not truncate the evaluation loop =="
# Under the indexed array, a 0.5 in STAGE_NAMES killed the whole `for` loop, so index.html was
# regenerated with every later stage missing — silently, at exit 0.
{ cat "$ACC"; cat <<'EOF'
set -uo pipefail
R=""
for s in 0 0.5 1 2; do tbl_add R "$s" PASS; done
n=0
for s in 0 0.5 1 2; do tbl_get "$s" "$R" && n=$((n+1)); done
echo "resolved=$n"
EOF
} > "$WORK/loop.sh"
/bin/bash "$WORK/loop.sh" 2>&1 | grep -qx 'resolved=4' \
  && ok "all 4 stages survived a fractional id in the loop" \
  || bad "loop truncated by a fractional stage id"

echo ""
echo "PASS=$PASS FAIL=$FAIL   ($WORK)"
[ "$FAIL" -eq 0 ]
