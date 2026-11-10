#!/usr/bin/env bash
# Fixture for project-bin/persona-preflight.sh: fail a journey batch before it starts when a persona
# the journeys log in as is not a demo user (speed-night B: 11 runs x ~104 s lost to a login that could
# never succeed, nothing flagged it).
#
# usage: bash tests/wave2/test-persona-preflight.sh [/path/to/persona-preflight.sh]
#
# Golden input is captured (fixtures/persona-preflight/CAPTURE.txt): `show demo users` / `show user roles`
# from mxcli v0.28.0 and the real run-3 journeys. Positive control: with the demo-user lookup removed
# (every persona treated as present) cases B, C and F fail.
set -uo pipefail
TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
SUBJECT="${1:-$TOOLKIT/project-bin/persona-preflight.sh}"
case "$SUBJECT" in /*) ;; *) SUBJECT="$PWD/$SUBJECT" ;; esac
FX="$TOOLKIT/tests/wave2/fixtures/persona-preflight"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/persona-t.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"; cp "$TOOLKIT/project-bin/_common.sh" "$SUBJECT" "$WORK/bin/"; SUT="$WORK/bin/$(basename "$SUBJECT")"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; return 0; }
echo "== subject: $SUBJECT"
run() { bash "$SUT" --demo-users "$FX/demo-users.txt" --user-roles "$FX/user-roles.txt" "$@" 2>&1; }

# A. the real journeys: requester + approver exist, roles asserted by the persona-named role
out="$(run "$FX/journeys")"; rc=$?
[ $rc -eq 0 ] && ok "A real run-3 journeys: exit 0" || bad "A exit $rc" "$out"
echo "$out" | grep -q '2 persona(s) from 3 journey(s): 2 exist, 2 role(s) asserted, 0 problem' && ok "A denominator line is exact" || bad "A denominator" "$out"

# B. the experiment-B failure: persona requester_test_user -> one named line, exit 1
mkdir -p "$WORK/b"; sed 's/"persona": "requester"/"persona": "requester_test_user"/' "$FX/journeys/J-REQ-01.journey.json" > "$WORK/b/J-REQ-01.journey.json"
out="$(run "$WORK/b/J-REQ-01.journey.json")"; rc=$?
[ $rc -eq 1 ] && ok "B missing persona: exit 1" || bad "B exit $rc" "$out"
[ "$(echo "$out" | grep -c '^PERSONA MISSING')" -eq 1 ] && echo "$out" | grep -q 'PERSONA MISSING: "requester_test_user" (J-REQ-01)' && ok "B exactly one named line, with the journey id" || bad "B line" "$out"

# C. two missing personas -> two lines
cp "$FX/journeys/J-APP-01.journey.json" "$WORK/b/"; sed -i 's/"persona": "approver"/"persona": "approver_x"/' "$WORK/b/J-APP-01.journey.json"
out="$(run "$WORK/b")"; rc=$?
[ "$(echo "$out" | grep -c '^PERSONA MISSING')" -eq 2 ] && [ $rc -eq 1 ] && ok "C one line per missing persona (2)" || bad "C" "$out"

# D. case-sensitive name gets a hint
mkdir -p "$WORK/d"; sed 's/"persona": "requester"/"persona": "Requester"/' "$FX/journeys/J-REQ-01.journey.json" > "$WORK/d/J.journey.json"
out="$(run "$WORK/d")"; echo "$out" | grep -q '"requester" exists; names are case-sensitive' && ok "D case mismatch is named" || bad "D" "$out"

# E. declared personaRole that the demo user lacks
mkdir -p "$WORK/e"; sed 's/"persona": "requester",/"persona": "requester", "personaRole": "Approver",/' "$FX/journeys/J-REQ-01.journey.json" > "$WORK/e/J.journey.json"
out="$(run "$WORK/e")"; rc=$?
[ $rc -eq 1 ] && echo "$out" | grep -q 'PERSONA ROLE: demo user "requester" (J-REQ-01) holds role Requester, expected Approver' && ok "E wrong role named, exit 1" || bad "E" "$out"

# F. no persona anywhere: TEST_USER is who signs in
mkdir -p "$WORK/f"; sed '/"persona":/d' "$FX/journeys/J-REQ-01.journey.json" > "$WORK/f/J.journey.json"
out="$(TEST_USER=MxAdmin run "$WORK/f")"; rc=$?
[ $rc -eq 0 ] && echo "$out" | grep -q 'NOTE: 1 journey(s) name no persona and sign in as TEST_USER "MxAdmin"' && ! echo "$out" | grep -q 'PERSONA MISSING' && ok "F an MxAdmin-only project (no persona, TEST_USER not a demo user) is an advisory note, exit 0" || bad "F" "$out (rc $rc)"
head -n "$(grep -n -m1 '^|[-| ]*|$' "$FX/demo-users.txt" | cut -d: -f1)" "$FX/demo-users.txt" > "$WORK/du-empty.txt"
out="$(TEST_USER=MxAdmin bash "$SUT" --demo-users "$WORK/du-empty.txt" "$WORK/f" 2>&1)"; rc=$?
[ $rc -eq 0 ] && echo "$out" | grep -q 'NOTE:' && ok "F2 a demo-user table with a header and zero rows is no FAULT for an undeclared persona" || bad "F2b" "$out (rc $rc)"
out="$(env -u TEST_USER bash "$SUT" --demo-users "$FX/demo-users.txt" "$WORK/f" 2>&1)"; rc=$?
[ $rc -eq 0 ] && echo "$out" | grep -q '0 persona(s)' && ok "F no persona and no TEST_USER: denominator says 0 personas" || bad "F2" "$out"

# G. existence only when the model has no role named like the persona: said out loud
mkdir -p "$WORK/g"; sed 's/"persona": "requester"/"persona": "demo_user"/' "$FX/journeys/J-REQ-01.journey.json" > "$WORK/g/J.journey.json"
out="$(run "$WORK/g")"; rc=$?
[ $rc -eq 1 ] && echo "$out" | grep -q 'holds role User, expected' || { [ $rc -eq 0 ] && echo "$out" | grep -q 'role NOT asserted for: demo_user'; } && ok "G demo_user: role not silently green (asserted or named unasserted)" || bad "G" "$out"

# H. cannot measure -> exit 2, never a pass
printf 'garbage\n' > "$WORK/h.txt"
bash "$SUT" --demo-users "$WORK/h.txt" "$FX/journeys" >/dev/null 2>&1; [ $? -eq 2 ] && ok "H no demo-user table -> exit 2" || bad "H"
printf '{not json' > "$WORK/bad.journey.json"; run "$WORK/bad.journey.json" >/dev/null 2>&1; [ $? -eq 2 ] && ok "H unreadable journey -> exit 2" || bad "H2"
run "$WORK/nope" >/dev/null 2>&1; [ $? -eq 2 ] && ok "H missing path -> exit 2" || bad "H3"

echo "== $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
