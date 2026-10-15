#!/usr/bin/env bash
# test-authoring-audit.sh — golden check for the advisory routing audit (CLAUDE.md rule 8).
#
# Runs `routing` on the committed phrasings and the real bin/lib/skill-routing.tsv. Calibrated on
# master 484e7ff at top-3 46/55; the floor is 44 so wording churn in one or two trigger rows does
# not go red, while a scorer regression (tokeniser, BM25 maths, column read) does. Also proves the
# exit contract: 0 without --strict even with misses, 1 under --strict when a must_hit row misses.
#
# Usage: bash tests/wave2/test-authoring-audit.sh [path-to-authoring-audit.py]

set -u
TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
SUT="${1:-$TOOLKIT/tests/advisory/authoring-audit.py}"
[ -r "$SUT" ] || { echo "test-authoring-audit: no script at $SUT"; exit 2; }
. "$TOOLKIT/bin/lib/portable.sh"; require_py
FLOOR=44
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/authoring-audit.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT

out="$("$PY" "$SUT" --root "$TOOLKIT" routing 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "routing exits 0 (advisory)" || bad "routing exits 0" "rc=$rc"
hit=$(printf '%s\n' "$out" | sed -nE 's/.*top-3 ([0-9]+)\/([0-9]+).*/\1/p' | head -1)
tot=$(printf '%s\n' "$out" | sed -nE 's/.*top-3 ([0-9]+)\/([0-9]+).*/\2/p' | head -1)
if [ -n "$hit" ] && [ "$tot" -ge 55 ] && [ "$hit" -ge "$FLOOR" ]; then ok "top-3 $hit/$tot >= $FLOOR"
else bad "top-3 >= $FLOOR of >= 55 phrasings" "$(printf '%s\n' "$out" | head -1)"; fi
# Miss listing on a synthetic file (one sure hit, one sure miss), so it keeps testing after the
# real triggers improve and the committed phrasings stop missing.
printf 'doctor.sh shows red on mxbuild\tskills/doctor-triage.md\t-\t-\nzz synthetic miss probe\tskills/no-such-skill.md\t-\t-\n' > "$TMP/m.tsv"
mout="$("$PY" "$SUT" --root "$TOOLKIT" routing --phrasings "$TMP/m.tsv" 2>&1)"
if printf '%s\n' "$mout" | grep -q 'top-3 1/2' && [ "$(printf '%s\n' "$mout" | grep -c '^  MISS')" -eq 1 ] \
   && printf '%s\n' "$mout" | grep -q 'MISS: "zz synthetic miss probe"'; then ok "the one miss is listed, the hit is not"
else bad "the one miss is listed, the hit is not" "$(printf '%s\n' "$mout" | head -3)"; fi

printf 'should this be a script or a skill\tskills/no-such-skill.md\t-\tmust_hit\n' > "$TMP/p.tsv"
"$PY" "$SUT" --root "$TOOLKIT" routing --phrasings "$TMP/p.tsv" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "must_hit miss without --strict exits 0" || bad "must_hit miss without --strict exits 0" "rc=$rc"
"$PY" "$SUT" --root "$TOOLKIT" routing --phrasings "$TMP/p.tsv" --strict >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && ok "must_hit miss under --strict exits 1" || bad "must_hit miss under --strict exits 1" "rc=$rc"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
