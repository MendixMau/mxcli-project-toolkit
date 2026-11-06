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

# Portability: the test suite must run on the platforms the toolkit targets, or the fix for
# a Windows bug can never be verified on Windows. Resolve Python by executing candidates.
# shellcheck disable=SC1091
. "$TOOLKIT/bin/lib/portable.sh"
require_py
SUBJECT="${1:-$TOOLKIT/bin/facts-lock.sh}"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/flock.XXXXXX") || exit 2
trap 'rm -rf "$WORK"' EXIT
echo "== subject: $SUBJECT"

P="$WORK/proj"
mkdir -p "$P/analysis/source/knowledge-base/brd" "$P/analysis/alt-source/knowledge-base/brd"

# A decoy corpus that sorts FIRST alphabetically. If the tool reads only one knowledge-base,
# it reads this one, finds nothing, and reports all-clear over the real corpus next door.
cat > "$P/analysis/source/knowledge-base/brd/F000-decoy.brd.json" <<'JSON'
{ "id":"F000","title":"Decoy","operations":[{"operationId":"ListThings"}] }
JSON

# The real corpus. Two spellings of one operation, deliberately never under the same key:
# one under `operationId`, the other buried in a prose note and a path.
cat > "$P/analysis/alt-source/knowledge-base/brd/F001-a.brd.json" <<'JSON'
{ "id":"F001","title":"A",
  "integrations":[{"operationId":"QueryAISafeWIPSummary","path":"/ai/summary"}],
  "domainEntities":[{"entity":"WIPStatus"},{"entity":"genealogy"}] }
JSON
cat > "$P/analysis/alt-source/knowledge-base/brd/F002-b.brd.json" <<'JSON'
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
"$PY" -c "import json,sys; json.load(open('$LOCK'))" 2>/dev/null \
  && ok "the lock is valid JSON" || bad "the lock is not parseable"

bash "$SUBJECT" "$P" build >/dev/null 2>&1
[ "$?" -ne 0 ] && ok "build exits non-zero while conflicts are unresolved" \
               || bad "build exited 0 with contested facts — a gate would pass on a broken corpus"

# --- the lock wins ------------------------------------------------------------------------------------
# Resolve the WIP conflict by hand, the way an agent would, then prove deviations are caught.
"$PY" - "$LOCK" <<'PY'
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
echo '{ broken' > "$P/analysis/alt-source/knowledge-base/brd/F003-bad.brd.json"
OUT=$(bash "$SUBJECT" "$P" show 2>&1)
case "$OUT" in
  *UNREADABLE*F003*) ok "names a BRD it could not parse instead of skipping it silently" ;;
  *) bad "an unparseable BRD vanished — its facts are missing and nothing said so" ;;
esac
bash "$SUBJECT" "$P" show >/dev/null 2>&1
[ "$?" -ne 0 ] && ok "an unreadable BRD makes the run non-zero" || bad "exited 0 despite not reading a BRD"

# --- 0 facts is not agreement (#519) -------------------------------------------------------------------
# The issue's repro: BRDs that carry identifiers only under `name` keys give the harvest nothing.
# check used to print "2 BRD(s) agree with all 0 frozen fact(s)", which reads as a pass over a
# comparison that never happened. Exit codes are unchanged; the line must say PENDING, not agree.
# (Since #621 domainEntities[].name IS read; pages[].name is still WARN-only, so it is the probe.)
Z="$WORK/zero"; mkdir -p "$Z/analysis/x/knowledge-base/brd"
echo '{"id":"F001","pages":[{"name":"PaymentPlan_Overview"}]}' > "$Z/analysis/x/knowledge-base/brd/F001-a.brd.json"
echo '{"id":"F002","pages":[{"name":"PaymentPlan_Overview"}]}' > "$Z/analysis/x/knowledge-base/brd/F002-b.brd.json"
ZC=$(bash "$SUBJECT" "$Z" check 2>&1)
case "$ZC" in
  *"agree with all 0"*) bad "check over 0 harvested facts still reads as agreement"; echo "        $ZC" | head -2 ;;
  *"PENDING facts-lock: 0 identifiers found under any known key in 2 BRD(s)"*) ok "check over 0 harvested facts says PENDING, not agree" ;;
  *) bad "check over 0 harvested facts printed neither agree nor PENDING"; echo "        $ZC" | head -2 ;;
esac
ZB=$(bash "$SUBJECT" "$Z" build 2>&1)
case "$ZB" in
  *"PENDING facts-lock: 0 identifiers found"*) ok "build that freezes 0 facts says the lock is empty" ;;
  *) bad "build froze 0 facts and did not say the lock is empty"; echo "        $ZB" | head -3 ;;
esac
# A lock not yet built over a corpus that does have identifiers: check says build first.
N="$WORK/notbuilt"; mkdir -p "$N/analysis/x/knowledge-base/brd"
echo '{"id":"F001","domainEntities":[{"entity":"PaymentPlan"}]}' > "$N/analysis/x/knowledge-base/brd/F001-a.brd.json"
NC=$(bash "$SUBJECT" "$N" check 2>&1)
case "$NC" in
  *"run build first"*) ok "check with no lock built says run build first, not agree" ;;
  *) bad "check with no lock built did not say run build first"; echo "        $NC" | head -2 ;;
esac

# --- name-keyed identifiers outside the declared shape are read WARN-only (#519) --------------------
# pages[].name respelled across two BRDs: named in a WARN line, never frozen, exit 0 for build and
# check. (The #519 repro was domainEntities[].name; #621 made that a declared fact — next block.)
NK="$WORK/namekeyed"; mkdir -p "$NK/analysis/x/knowledge-base/brd"
echo '{"id":"F001","pages":[{"name":"PaymentPlan_Overview"}]}' > "$NK/analysis/x/knowledge-base/brd/F001-a.brd.json"
echo '{"id":"F002","pages":[{"name":"Paymentplan_Overview"}]}' > "$NK/analysis/x/knowledge-base/brd/F002-b.brd.json"
NB=$(bash "$SUBJECT" "$NK" build 2>&1); NBRC=$?
case "$NB" in
  *"WARN  name-keyed pages/paymentplan_overview"*"PaymentPlan_Overview (F001-a.brd.json)"*"Paymentplan_Overview (F002-b.brd.json)"*)
    ok "a name-keyed respelling is named in a WARN line" ;;
  *) bad "name-keyed respelling not reported"; echo "        $NB" | head -4 ;;
esac
[ "$NBRC" -eq 0 ] && ok "build exit unchanged (0): WARN only" || bad "build exit $NBRC on a name-keyed WARN"
grep -q '"facts": {}' "$NK/analysis/facts.lock.json" && ok "nothing name-keyed is frozen" || bad "name-keyed spelling was frozen"
NCK=$(bash "$SUBJECT" "$NK" check 2>&1); NCKRC=$?
case "$NCK" in *"WARN  name-keyed pages/paymentplan_overview"*) [ "$NCKRC" -eq 0 ] && ok "check names it too, exit 0" || bad "check exit $NCKRC" ;;
  *) bad "check did not report the name-keyed respelling" ;; esac
case "$NCK" in *"agree with all"*) bad "check reads as agreement" ;; *) ok "check still does not read as agreement" ;; esac

# --- a hand-written (Path B) BRD's declared facts are locked (#621) --------------------------------
# Field run: 9 brd-generation.md-shaped BRDs, "2 fact(s) frozen", check PASSed with nothing to
# compare. The shape below is brd-generation.md's own: entities, attributes+types, an
# enumeration's values, use-case and business-rule ids, actors, modules.
PB="$WORK/pathb"; PBB="$PB/analysis/kb/knowledge-base/brd"; mkdir -p "$PBB"
cat > "$PBB/F001-scheduling.brd.json" <<'JSON'
{ "id":"F001","title":"Scheduling","modules":["Scheduling"],"actors":["Planner"],"provenance":"documents",
  "useCases":[{"id":"UC001","title":"Plan a shift","actors":["Planner"],"mainFlow":["1. plan"],"postconditions":["planned"]}],
  "businessRules":[{"id":"BR-01","title":"No double shifts"}],
  "domainEntities":[
    {"name":"Shift","module":"Scheduling","attributes":[{"name":"employeeId","type":"String"},{"name":"shiftType","type":"Enumeration","enumeration":"Scheduling.ShiftType"}]},
    {"name":"ShiftType","module":"Scheduling","mendixType":"Enumeration","values":["Early","Late"]}] }
JSON
cat > "$PBB/F002-leave.brd.json" <<'JSON'
{ "id":"F002","title":"Leave","modules":["Leave"],"actors":["Planner","Employee"],"provenance":"documents",
  "useCases":[{"id":"UC002","title":"Request leave","actors":["Employee"],"mainFlow":["1. ask"],"postconditions":["asked"]}],
  "businessRules":[{"id":"BR-02","title":"Two weeks notice"},"BR-03: a request over 10 days needs a second approver"],
  "domainEntities":[{"name":"LeaveRequest","module":"Leave","attributes":[{"name":"employeeId","type":"String"}]}] }
JSON
cp "$PBB/F001-scheduling.brd.json" "$WORK/f001.keep"; cp "$PBB/F002-leave.brd.json" "$WORK/f002.keep"
BOUT=$(bash "$SUBJECT" "$PB" build 2>&1)
NF=$("$PY" -c "import json,sys; d=json.load(open(sys.argv[1])); print(sum(len(v) for v in d['facts'].values()))" "$PB/analysis/facts.lock.json" 2>/dev/null)
[ "${NF:-0}" -ge 15 ] && ok "Path B: build freezes the declared facts ($NF), not ~0" || { bad "Path B: only ${NF:-0} fact(s) frozen from 2 hand-written BRDs"; echo "        $BOUT" | head -3; }
MISSING=""
for want in '"br-03"' '"shift"' '"shift.employeeid"' '"shifttype.early"' '"uc001"' '"br-01"' '"planner"' '"scheduling"'; do
  grep -q "$want" "$PB/analysis/facts.lock.json" || MISSING="$MISSING $want"
done
[ -z "$MISSING" ] && ok "Path B: entity, attribute, enum value, use-case id, rule id, role and module are each frozen" || bad "Path B: not frozen:$MISSING"
{ grep -q '"type": "String"' "$PB/analysis/facts.lock.json" && grep -q '"module": "Scheduling"' "$PB/analysis/facts.lock.json"; } \
  && ok "Path B: attribute types and entity modules are part of the lock" || bad "Path B: types/modules not locked"
OUT=$(bash "$SUBJECT" "$PB" check 2>&1); rc=$?
case "$OUT" in *"agree with all"*) [ "$rc" -eq 0 ] && ok "Path B: an unchanged corpus agrees (exit 0)" || bad "Path B: rc $rc" ;; *) bad "Path B: unchanged corpus does not agree"; echo "        $OUT" | head -3 ;; esac
# A later change is a visible deviation: a renamed entity, a use case reused in another BRD.
"$PY" - "$PBB/F001-scheduling.brd.json" "$PBB/F002-leave.brd.json" <<'PY'
import json, sys
a = json.load(open(sys.argv[1])); a["domainEntities"][0]["name"] = "WorkShift"; json.dump(a, open(sys.argv[1], "w"))
b = json.load(open(sys.argv[2])); b["useCases"][0]["id"] = "UC001"; json.dump(b, open(sys.argv[2], "w"))
PY
OUT=$(bash "$SUBJECT" "$PB" check 2>&1); rc=$?
{ grep -q "DEVIATION .*entities 'Shift' is frozen but no BRD declares it any more" <<<"$OUT"; } \
  && ok "Path B: a renamed entity is a DEVIATION (frozen, declared by no BRD)" || { bad "Path B: renamed entity not caught"; echo "        $OUT" | head -3; }
grep -q "DEVIATION .*useCases 'UC001' is owned by F001/F002" <<<"$OUT" \
  && ok "Path B: a use-case id that appears in another BRD is a DEVIATION" || { bad "Path B: reused use-case id not caught"; echo "        $OUT" | head -3; }
[ "$rc" -ne 0 ] && ok "Path B: check exits non-zero on a structural deviation" || bad "Path B: check exit 0 on deviations"
cp "$WORK/f001.keep" "$PBB/F001-scheduling.brd.json"; cp "$WORK/f002.keep" "$PBB/F002-leave.brd.json"
# Renaming a BRD file is not a change of owner: owners are BRD ids, not file names.
mv "$PBB/F002-leave.brd.json" "$PBB/F002-leave.brd.json"
OUT=$(bash "$SUBJECT" "$PB" check 2>&1); rc=$?
case "$OUT" in *DEVIATION*) bad "Path B: renaming a BRD file made deviations"; echo "        $OUT" | head -3 ;; *) [ "$rc" -eq 0 ] && ok "Path B: renaming a BRD file is no deviation (owner = BRD id)" || bad "Path B: rename rc $rc" ;; esac
mv "$PBB/F002-leave.brd.json" "$PBB/F002-leave.brd.json"
"$PY" - "$PBB/F001-scheduling.brd.json" <<'PY'
import json, sys
a = json.load(open(sys.argv[1])); a["domainEntities"][0]["attributes"][0]["type"] = "Integer"; json.dump(a, open(sys.argv[1], "w"))
PY
OUT=$(bash "$SUBJECT" "$PB" check 2>&1)
grep -q "DEVIATION  F001-scheduling.brd.json: attributes 'Shift.employeeId' has type 'Integer', lock says 'String'" <<<"$OUT" \
  && ok "Path B: an attribute whose type changed is a DEVIATION naming both types" || { bad "Path B: type change not caught"; echo "        $OUT" | head -3; }
# forget: a deliberate rename is accepted by dropping the frozen fact (and its attributes).
{ bash "$SUBJECT" "$PB" forget entities/Shift >/dev/null 2>&1 && ! grep -q '"shift.employeeid"' "$PB/analysis/facts.lock.json"; } \
  && ok "Path B: forget drops an entity and its attributes from the lock" || bad "Path B: forget did not drop the entity's facts"
# Two BRDs that disagree on one entity's module: contested, nothing frozen for it.
PC="$WORK/pathc"; mkdir -p "$PC/analysis/knowledge-base/brd"
echo '{"id":"F001","modules":["A"],"domainEntities":[{"name":"Employee","module":"A"}]}' > "$PC/analysis/knowledge-base/brd/F001.brd.json"
echo '{"id":"F002","modules":["B"],"domainEntities":[{"name":"Employee","module":"B"}]}' > "$PC/analysis/knowledge-base/brd/F002.brd.json"
OUT=$(bash "$SUBJECT" "$PC" build 2>&1); rc=$?
{ [ "$rc" -ne 0 ] && grep -q "CONFLICT  entities/employee — 2 different module values" <<<"$OUT" \
    && "$PY" -c "import json,sys; sys.exit('employee' in json.load(open(sys.argv[1]))['facts'].get('entities', {}))" "$PC/analysis/facts.lock.json"; } \
  && ok "Path B: one entity owned by two modules is a CONFLICT, not frozen" || { bad "Path B: module disagreement not contested (rc $rc)"; echo "        $OUT" | head -3; }
# An entity name spelt two ways between two hand-written BRDs is a CONFLICT now (it was WARN-only, #519).
PD="$WORK/pathd"; mkdir -p "$PD/analysis/knowledge-base/brd"
echo '{"id":"F001","domainEntities":[{"name":"PaymentPlan"}]}' > "$PD/analysis/knowledge-base/brd/F001.brd.json"
echo '{"id":"F002","domainEntities":[{"name":"Paymentplan"}]}' > "$PD/analysis/knowledge-base/brd/F002.brd.json"
OUT=$(bash "$SUBJECT" "$PD" build 2>&1); rc=$?
{ [ "$rc" -ne 0 ] && grep -q "CONFLICT  entities/paymentplan" <<<"$OUT"; } \
  && ok "Path B: an entity name spelt two ways is a CONFLICT" || { bad "Path B: entity respelling not contested (rc $rc)"; echo "        $OUT" | head -3; }

# --- a near-empty lock is not agreement (#621) ------------------------------------------------------
# A lock built before the BRDs carried (or the harvest could read) their facts: 2 facts over ~20.
NE="$WORK/near"; mkdir -p "$NE/analysis/knowledge-base/brd"
cp "$WORK/f001.keep" "$NE/analysis/knowledge-base/brd/F001-scheduling.brd.json"; cp "$WORK/f002.keep" "$NE/analysis/knowledge-base/brd/F002-leave.brd.json"
printf '{"version":1,"frozenAt":null,"conflicts":[],"facts":{"pages":{"x_overview":{"canonical":"X_Overview","sources":[]},"y_overview":{"canonical":"Y_Overview","sources":[]}}}}\n' > "$NE/analysis/facts.lock.json"
OUT=$(bash "$SUBJECT" "$NE" check 2>&1)
case "$OUT" in
  *"agree with all"*) bad "near-empty: a 2-fact lock over 2 rich BRDs reads as agreement" ;;
  *"NEAR-EMPTY facts-lock: near-empty lock (2 facts)"*) ok "near-empty: a 2-fact lock says 'near-empty lock (2 facts)', not agree" ;;
  *) bad "near-empty: neither agree nor NEAR-EMPTY"; echo "        $OUT" | head -3 ;;
esac

# --- resolve: an explicit majority step, never silent --------------------------------------------
R="$WORK/resolve"; mkdir -p "$R/analysis/knowledge-base/brd"
for i in 1 2; do printf '{ "id":"F00%s","domainEntities":[{"entity":"WIPStatus"},{"entity":"OrderLine"}] }\n' "$i" > "$R/analysis/knowledge-base/brd/F00$i.brd.json"; done
printf '{ "id":"F003","domainEntities":[{"entity":"WipStatus"},{"entity":"Orderline"}] }\n' > "$R/analysis/knowledge-base/brd/F003.brd.json"
printf '{ "id":"F004","domainEntities":[{"entity":"Supplier"}] }\n' > "$R/analysis/knowledge-base/brd/F004.brd.json"
printf '{ "id":"F005","domainEntities":[{"entity":"Orderline"}] }\n' > "$R/analysis/knowledge-base/brd/F005.brd.json"
OUT=$(bash "$SUBJECT" "$R" build 2>&1); rc=$?
{ [ "$rc" -ne 0 ] && ! grep -q '"canonical": "WIPStatus"' "$R/analysis/facts.lock.json"; } \
  && ok "resolve: build alone still picks nothing (exit $rc, no canonical for the casing conflict)" \
  || bad "resolve: build picked a winner on its own" "$OUT"
OUT=$(bash "$SUBJECT" "$R" resolve 2>&1); rc=$?
{ grep -q 'RESOLVED .*WIPStatus.*WIPStatus 2, WipStatus 1' <<<"$OUT" && grep -q '"resolvedBy": "majority: WIPStatus 2, WipStatus 1"' "$R/analysis/facts.lock.json"; } \
  && ok "resolve: the 2-to-1 spelling is frozen and the count is recorded in the lock" || bad "resolve: majority not frozen/recorded" "$OUT"
{ [ "$rc" -ne 0 ] && grep -q 'CONFLICT .*rderline' <<<"$OUT"; } \
  && ok "resolve: a 2-to-2 tie stays contested and resolve exits non-zero" || bad "resolve: tie handled wrong (rc $rc)" "$OUT"
OUT=$(bash "$SUBJECT" "$R" check 2>&1)
grep -q "DEVIATION .*F003.*'WipStatus'.*'WIPStatus'" <<<"$OUT" \
  && ok "resolve: check then names the BRD that uses the minority spelling" || bad "resolve: check did not flag F003" "$OUT"

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
