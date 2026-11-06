#!/usr/bin/env bash
# Fixture for project-bin/rollback-scan.sh: which effects survive @cleanup rollback in the flows a test calls.
#
# usage: bash tests/wave2/test-rollback-scan.sh [/path/to/rollback-scan.sh]
#
# Golden input is captured, never written: fixtures/rollback-scan/catalog.sql holds rows copied from a real
# `refresh catalog full` of the probe app that measured the six effects (see CAPTURE.txt). The expected
# lines below are the effects that app measured as surviving rollback.
#
# Positive control: with rollback-effects.tsv emptied, the A/B cases fail (no effect lines); with the
# call-edge walk removed, the "intake" case loses its path; with the event branch removed, case C fails.
set -uo pipefail

TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
SUBJECT="${1:-$TOOLKIT/project-bin/rollback-scan.sh}"
case "$SUBJECT" in /*) ;; *) SUBJECT="$PWD/$SUBJECT" ;; esac
FX="$TOOLKIT/tests/wave2/fixtures/rollback-scan"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/rollback-t.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; return 0; }
echo "== subject: $SUBJECT"

command -v sqlite3 >/dev/null 2>&1 || { echo "  skip: sqlite3 CLI needed to build the fixture catalog"; exit 0; }
P="$WORK/proj"; mkdir -p "$P/bin" "$P/tests"
cp "$TOOLKIT/project-bin/_common.sh" "$TOOLKIT/project-bin/rollback-scan.py" "$TOOLKIT/project-bin/rollback-effects.tsv" "$P/bin/"
cp "$SUBJECT" "$P/bin/rollback-scan.sh"; chmod +x "$P/bin/"*.sh
cp "$FX/probes.test.mdl" "$P/tests/"
sqlite3 "$WORK/catalog.db" < "$FX/catalog.sql"
export ROLLBACK_SCAN_CATALOG="$WORK/catalog.db"
cd "$P" || exit 2
scan() { PROJECT_ROOT="$P" bash "$P/bin/rollback-scan.sh" "$@" 2>&1; }

has() { printf '%s\n' "$1" | grep -E "$2" >/dev/null 2>&1; }

# A. the six measured effects, each on its own probe flow
OUT="$(scan tests/probes.test.mdl)"; RC=$?
[ "$RC" = 0 ] && ok "A0 exit 0" || bad "A0 exit $RC" "$OUT"
for want in '^A  REST +MtaProbe\.PRB_Rest ' '^A  FILE-WRITE +MtaProbe\.PRB_File ' '^A  SEP-COMMIT +MtaProbe\.PRB_SeparateCommit ' \
            '^A  QUEUE +MtaProbe\.PRB_Queue ' '^B  AUTONUMBER +MtaProbe\.PRB_Autonumber ' '^B  LOG +MtaProbe\.PRB_Log '; do
  has "$OUT" "$want" && ok "A  $want" || bad "A  missing $want" "$OUT"
done
# the plain-commit control reaches no A line (it does consume the autonumber of its entity: B)
C="$(scan MtaProbe.PRB_Control)"
has "$C" '^A  ' && bad "A7 control has an A line" "$C" || ok "A7 control: no A line"
has "$C" '^B  AUTONUMBER +MtaProbe\.PRB_Control ' && ok "A8 control: autonumber is B" || bad "A8 control autonumber" "$C"
# the queue action says its target is not followed
has "$OUT" 'QUEUE.*not followed' && ok "A9 queue: target not followed is stated" || bad "A9 queue note" "$OUT"

# B. transitive walk and the pure-helper ignore row
OUT="$(scan InvoiceProcessing.SUB_Invoice_CreateFromIntake)"
has "$OUT" 'reached' && has "$OUT" '3 flow\(s\) reached' && ok "B1 three flows reached" || bad "B1 reach count" "$OUT"
has "$OUT" '^A  FILE-WRITE .*Base64DecodeToFile' && ok "B2 file write found" || bad "B2 file write" "$OUT"
has "$OUT" '^A  FILE-DOC ' && ok "B3 file document create found" || bad "B3 filedoc" "$OUT"
has "$OUT" 'getGUID' && bad "B4 getGUID listed as unlisted java" "$OUT" || ok "B4 known-harmless java action not listed"

# C. entity event handler is followed
J="$(scan --json Procurement.ACT_User_Register)"
has "$J" '^\{' && has "$J" '"reached": 5' && has "$J" '"effects": \[\]' && ok "C1 --json prints one object, reached 5 flows, no effect" || bad "C1 json/reach" "$J"
has "$(scan Procurement.ACT_User_Register)" 'reached' && ok "C2 text mode runs" || bad "C2" ""
has "$J" '"reached": 5' && ok "C3 handler reached through the event edge (5 flows, 4 without it)" || bad "C3 event edge not followed" "$J"

# D. never fails, says why
rm -f "$WORK/none.db"
O="$(ROLLBACK_SCAN_CATALOG="$WORK/none.db" scan MtaProbe.PRB_Rest)"; R=$?
[ "$R" = 0 ] && has "$O" 'no catalog' && has "$O" 'refresh catalog full' && ok "D1 missing catalog: exit 0 and the command to build it" || bad "D1 missing catalog" "$O (rc $R)"
O="$(scan Nope.Nothing)"; R=$?
[ "$R" = 0 ] && has "$O" 'not in catalog: Nope.Nothing' && ok "D2 unknown flow named, exit 0" || bad "D2 unknown flow" "$O"
O="$(scan)"; R=$?
[ "$R" = 2 ] && ok "D3 no arguments: usage, exit 2" || bad "D3 usage rc=$R" "$O"
: > "$WORK/empty.db"; O="$(ROLLBACK_SCAN_CATALOG="$WORK/empty.db" scan MtaProbe.PRB_Rest)"; R=$?
[ "$R" = 0 ] && has "$O" 'unreadable|no references' && ok "D4 empty catalog file: message, exit 0" || bad "D4 empty catalog" "$O (rc $R)"

# E. positive control: no effect table, no effect lines
printf '# empty\n' > "$P/bin/rollback-effects.tsv"
O="$(scan tests/probes.test.mdl)"
has "$O" '^[AB]  ' && bad "E1 control: effect lines with an empty table" "$O" || ok "E1 control: empty table prints no effect line"
cp "$TOOLKIT/project-bin/rollback-effects.tsv" "$P/bin/"

# F. speed: query time after the catalog exists (the fixture is small; the 1,250-flow app is in the PR text)
S=$(date +%s); for _ in 1 2 3 4 5; do scan tests/probes.test.mdl >/dev/null; done; E=$(date +%s)
[ $((E - S)) -le 5 ] && ok "F1 five scans in $((E - S)) s" || bad "F1 slow: $((E - S)) s for five scans"

echo "== $PASS ok, $FAIL failed"
[ "$FAIL" = 0 ]
