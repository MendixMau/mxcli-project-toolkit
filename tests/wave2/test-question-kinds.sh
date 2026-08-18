#!/bin/bash
# test-question-kinds.sh — pin the gap/conflict/choice routing and the shared BRD discovery.
#
# The load-bearing assertions here are the two failure directions:
#
#   1. AN UNCLASSIFIED QUESTION GOES TO THE HUMAN. If it defaulted to `gap` an agent would
#      silently absorb work nobody triaged, which is the "the agent didn't interview, it just
#      continued" complaint this toolkit exists to answer. A mistake must resolve toward
#      being asked too much.
#
#   2. EVERY KNOWLEDGE BASE IS READ. facts-lock.sh shipped reading only the first, reported
#      "0 contested" over 10% of a corpus, and the fix is now shared in lib/discover-brds.sh.
#      A second consumer means a second chance to get it wrong, so it is pinned here too, with
#      the decoy KB sorting FIRST alphabetically so a first-match bug cannot pass by luck.

set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Portability: the test suite must run on the platforms the toolkit targets, or the fix for
# a Windows bug can never be verified on Windows. Resolve Python by executing candidates.
# shellcheck disable=SC1091
. "$ROOT/bin/lib/portable.sh"
require_py
QK="$ROOT/bin/question-kinds.sh"
PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected '$3', got '$2'"; fi; }
has()  { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "missing '$3'" ;; esac; }

jqf() { printf '%s' "$1" | "$PY" -c "import json,sys; print(json.load(sys.stdin)['$2'])"; }

mkbrd() { # mkbrd <dir> <file> <json-array-body>
  mkdir -p "$1"; printf '{"openQuestions":%s}' "$3" > "$1/$2"
}

echo "== the three kinds =="

P="$TMP/p"; KB="$P/analysis/src/knowledge-base/brd"
mkbrd "$KB" F001.brd.json '[
 {"id":"Q1","kind":"gap","question":"name length"},
 {"id":"Q2","kind":"conflict","question":"two owners disagree"},
 {"id":"Q3","kind":"choice","question":"tenancy shape"}]'
J=$("$QK" "$P" --json)
check "gap counted"      "$(jqf "$J" gap)" "1"
check "conflict counted" "$(jqf "$J" conflict)" "1"
check "choice counted"   "$(jqf "$J" choice)" "1"
check "conflict + choice go to the human" "$(jqf "$J" human)" "2"
check "a gap does not" "$(jqf "$J" total)" "3"

echo "== failure direction: unclassified is routed to the human =="

mkbrd "$KB" F002.brd.json '[{"id":"Q4","question":"nobody triaged this"}]'
J=$("$QK" "$P" --json)
check "unclassified is counted as such" "$(jqf "$J" unclassified)" "1"
check "  and lands in the human bucket" "$(jqf "$J" human)" "3"
check "  and never in the agent bucket" "$(jqf "$J" gap)" "1"

mkbrd "$KB" F003.brd.json '[{"id":"Q5","kind":"nonsense","question":"typo in the kind"}]'
J=$("$QK" "$P" --json)
check "an unrecognised kind is unclassified, not silently a gap" "$(jqf "$J" unclassified)" "2"
check "  so a typo resolves toward being asked" "$(jqf "$J" human)" "4"

OUT=$("$QK" "$P" 2>&1)
has "the untriaged count is surfaced, not hidden in 'choice'" "$OUT" "have no 'kind'"

mkbrd "$KB" F004.brd.json '[{"id":"Q6","kind":"GAP","question":"shouty"},
 {"id":"Q7","kind":"Choice","question":"titlecase"}]'
J=$("$QK" "$P" --json)
check "kind is case-insensitive (gap)"    "$(jqf "$J" gap)" "2"
check "kind is case-insensitive (choice)" "$(jqf "$J" choice)" "2"

echo "== every knowledge base is read =="

# The decoy sorts first. A first-match bug reads 1 question and reports a tidy, wrong answer.
M="$TMP/multi"
mkbrd "$M/analysis/aaa-decoy/knowledge-base/brd" D.brd.json '[{"id":"D1","kind":"gap","question":"decoy"}]'
mkbrd "$M/analysis/zzz-real/knowledge-base/brd"  R.brd.json '[
 {"id":"R1","kind":"conflict","question":"real 1"},
 {"id":"R2","kind":"choice","question":"real 2"}]'
J=$("$M" 2>/dev/null; "$QK" "$M" --json)
check "both knowledge bases are counted" "$(jqf "$J" brdCount)" "2"
check "  and every question is read"     "$(jqf "$J" total)" "3"
check "  so the human bucket is right"   "$(jqf "$J" human)" "2"

# Legacy layouts must not be dropped now that discovery is shared.
L="$TMP/legacy"; mkbrd "$L/knowledge-base/brd" L.brd.json '[{"id":"L1","kind":"gap","question":"legacy"}]'
J=$("$QK" "$L" --json)
check "a root-level knowledge-base still resolves" "$(jqf "$J" brdCount)" "1"

S="$TMP/single"; mkbrd "$S/analysis/knowledge-base/brd" S.brd.json '[{"id":"S1","kind":"gap","question":"single"}]'
J=$("$QK" "$S" --json)
check "analysis/knowledge-base still resolves" "$(jqf "$J" brdCount)" "1"

echo "== nothing examined is not a clean result =="

E="$TMP/empty"; mkdir -p "$E/analysis"
OUT=$("$QK" "$E" 2>&1); RC=$?
check "no BRDs exits 3, not 0" "$RC" "3"
has "  and says where it looked" "$OUT" "knowledge-base/brd"

# A BRD that exists but declares no questions is a REPORTING failure on a thin source, and the
# tool has to say so rather than print a reassuring zero.
Z="$TMP/zero"; mkbrd "$Z/analysis/s/knowledge-base/brd" Z.brd.json '[]'
OUT=$("$QK" "$Z" 2>&1); RC=$?
check "zero questions still exits 0 (BRDs were read)" "$RC" "0"
has "  but a zero over a thin source is flagged" "$OUT" "reporting"
has "  and the count carries its denominator" "$OUT" "across 1 BRD(s)"

echo "== strict =="

"$QK" "$P" --strict >/dev/null 2>&1; check "--strict fails while a human is owed answers" "$?" "1"
G="$TMP/gapsonly"; mkbrd "$G/analysis/s/knowledge-base/brd" G.brd.json '[{"id":"G1","kind":"gap","question":"g"}]'
"$QK" "$G" --strict >/dev/null 2>&1; check "--strict passes when only gaps remain" "$?" "0"

"$QK" "$TMP/nope" >/dev/null 2>&1; check "a missing directory is a usage error" "$?" "2"
"$QK" >/dev/null 2>&1; check "no arguments is a usage error" "$?" "2"

echo
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
