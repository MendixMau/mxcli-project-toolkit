#!/bin/bash
# test-facts-lock.sh — the shared facts layer that parallel BRD agents bind to.
#
# The two failure modes are opposite:
#   - too quiet: it reports "0 contested" over a corpus that disagrees with itself, and the
#     disagreement reaches the user as an open question. This ALREADY HAPPENED twice while the
#     script was being written — once by reading only the first knowledge-base dir (2 BRDs of
#     20), once by only harvesting keyed identifiers (missing a 149-occurrence conflict whose
#     two spellings never appeared under the same key). Both are pinned below.
#   - too loud: it flags `genealogy` against `Genealogy` — a SQL table and an entity — and the
#     ten real findings drown in sixteen conventions.
#
# Usage: bash test-facts-lock.sh [path-to-facts-lock.sh]

TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUBJECT="${1:-$TOOLKIT/bin/facts-lock.sh}"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/flock.XXXXXX") || exit 2
trap 'rm -rf "$WORK"' EXIT
echo "== subject: $SUBJECT"

P="$WORK/proj"
mkdir -p "$P/analysis/source/knowledge-base/brd" "$P/analysis/usi-source/knowledge-base/brd"

# A decoy corpus that sorts FIRST alphabetically. If the tool reads only one knowledge-base,
# it reads this one, finds nothing, and reports all-clear over the real corpus next door.
cat > "$P/analysis/source/knowledge-base/brd/F000-decoy.brd.json" <<'JSON'
{ "id":"F000","title":"Decoy","operations":[{"operationId":"ListThings"}] }
JSON

# The real corpus. Two spellings of one operation, deliberately never under the same key:
# one under `operationId`, the other buried in a prose note and a path.
cat > "$P/analysis/usi-source/knowledge-base/brd/F001-a.brd.json" <<'JSON'
{ "id":"F001","title":"A",
  "integrations":[{"operationId":"QueryAISafeWIPSummary","path":"/ai/summary"}],
  "domainEntities":[{"entity":"WIPStatus"},{"entity":"genealogy"}] }
JSON
cat > "$P/analysis/usi-source/knowledge-base/brd/F002-b.brd.json" <<'JSON'
{ "id":"F002","title":"B",
  "notes":["calls QueryAiSafeWipSummary then refreshes"],
  "domainEntities":[{"entity":"WipStatus"},{"entity":"Genealogy"}],
  "codes":["C05_MAP_TYPE_CODE_SET"] }
JSON

# --- discovery -------------------------------------------------------------------------------
OUT=$(bash "$SUBJECT" "$P" show 2>&1)
case "$OUT" in
  *"3 BRD(s)"*) ok "reads ALL knowledge-base dirs, not the first one alphabetically" ;;
  *) bad "did not read all 3 BRDs — a lock built over a partial corpus looks authoritative and is not"; echo "        $OUT" | head -2 ;;
esac

# --- the conflict that motivated the tool -------------------------------------------------------
case "$OUT" in
  *QueryAISafeWIPSummary*QueryAiSafeWipSummary*|*QueryAiSafeWipSummary*QueryAISafeWIPSummary*)
    ok "finds a conflict whose spellings never share a key (prose + operationId)" ;;
  *) bad "missed the cross-key conflict — this is the exact defect the tool exists for" ;;
esac
case "$OUT" in
  *WIPStatus*WipStatus*|*WipStatus*WIPStatus*) ok "finds the WIP/Wip acronym conflict" ;;
  *) bad "missed an acronym-casing conflict between two BRDs" ;;
esac

# --- precision ------------------------------------------------------------------------------------
case "$OUT" in
  *"entities/genealogy"*) bad "flagged genealogy vs Genealogy — a table and an entity are not a disagreement" ;;
  *) ok "does not flag an all-lower spelling against a mixed-case one (convention, not conflict)" ;;
esac

# --- freezing ---------------------------------------------------------------------------------------
bash "$SUBJECT" "$P" build >/dev/null 2>&1
LOCK="$P/analysis/facts.lock.json"
[ -f "$LOCK" ] && ok "build writes one project-wide lock" || bad "build wrote no lock file"
grep -q 'C05_MAP_TYPE_CODE_SET' "$LOCK" 2>/dev/null \
  && ok "freezes an unanimous fact (the code set)" \
  || bad "an uncontested identifier was not frozen"
grep -q '"conflicts"' "$LOCK" 2>/dev/null && grep -q 'QueryA' "$LOCK" 2>/dev/null \
  && ok "records the contested ones in the lock rather than silently picking" \
  || bad "conflicts absent from the lock — nothing to resolve against"
python3 -c "import json,sys; json.load(open('$LOCK'))" 2>/dev/null \
  && ok "the lock is valid JSON" || bad "the lock is not parseable"

bash "$SUBJECT" "$P" build >/dev/null 2>&1
[ "$?" -ne 0 ] && ok "build exits non-zero while conflicts are unresolved" \
               || bad "build exited 0 with contested facts — a gate would pass on a broken corpus"

# --- the lock wins ------------------------------------------------------------------------------------
# Resolve the WIP conflict by hand, the way an agent would, then prove deviations are caught.
python3 - "$LOCK" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["facts"].setdefault("entities", {})["wipstatus"] = {"canonical": "WIPStatus", "sources": []}
json.dump(d, open(p, "w"), indent=2, sort_keys=True)
PY
CHK=$(bash "$SUBJECT" "$P" check 2>&1)
case "$CHK" in
  *DEVIATION*WipStatus*) ok "check names the BRD that deviates and the spelling it should use" ;;
  *) bad "a frozen fact was contradicted and check did not say so"; echo "        $CHK" | head -3 ;;
esac
bash "$SUBJECT" "$P" check >/dev/null 2>&1
[ "$?" -ne 0 ] && ok "check exits non-zero on deviation" || bad "check exited 0 while a BRD contradicts the lock"

# --- honest about what it cannot read ---------------------------------------------------------------
echo '{ broken' > "$P/analysis/usi-source/knowledge-base/brd/F003-bad.brd.json"
OUT=$(bash "$SUBJECT" "$P" show 2>&1)
case "$OUT" in
  *UNREADABLE*F003*) ok "names a BRD it could not parse instead of skipping it silently" ;;
  *) bad "an unparseable BRD vanished — its facts are missing and nothing said so" ;;
esac
bash "$SUBJECT" "$P" show >/dev/null 2>&1
[ "$?" -ne 0 ] && ok "an unreadable BRD makes the run non-zero" || bad "exited 0 despite not reading a BRD"

# --- usage --------------------------------------------------------------------------------------------
bash "$SUBJECT" 2>/dev/null; [ "$?" -eq 2 ] && ok "no argument exits 2" || bad "no argument did not exit 2"
bash "$SUBJECT" "$P" nonsense 2>/dev/null; [ "$?" -eq 2 ] && ok "unknown subcommand exits 2" || bad "unknown subcommand accepted"
EMPTY="$WORK/empty"; mkdir -p "$EMPTY"
bash "$SUBJECT" "$EMPTY" show 2>/dev/null; [ "$?" -eq 2 ] \
  && ok "a project with no BRDs exits 2, not a clean 0" \
  || bad "no-BRD project looked clean — the false-green this suite exists to catch"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
