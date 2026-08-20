#!/bin/bash
# test-brd-report.sh — pin bin/brd-report.sh, the ONE Stage 2 surface.
#
# What is worth pinning here is not that a page comes out. Three pages came out before this
# script existed — one per pipeline — and every one of them rendered `Module: undefined` and a
# column of zeros on a BRD written by hand per brd-generation.md, because the three copies had
# drifted onto three different key names. So:
#
#   1. BOTH SHAPES RENDER. A hand-written BRD (modules[], attributes[], target) and a
#      scaffolder BRD (module, attributeCount, to) must both produce a populated page. The
#      whole reason there were three renderers is that each only knew one shape.
#
#   2. A DRIFTED KEY IS A FAULT, NOT A ZERO. This is the assertion that matters. An entity
#      whose attribute count lives under a name nobody reads must produce a visible finding.
#      Rendering it as `0` is the exact false green this instrument replaces, and `0` is what
#      the old reports printed.
#
#   3. EVERY KNOWLEDGE BASE IS READ. The discover-brds.sh regression (2026-08-12): a consumer
#      that matched only the FIRST analysis/*/knowledge-base reported a clean result over 10%
#      of the corpus. Any new consumer re-earns that test.
#
#   4. NO BRDs IS NOT A PASS. Exit 3, with the directories it looked in.
#
#   5. PROVENANCE DISCRIMINATES. A requirements BRD with no domainEntities is `skipped` with a
#      reason; a migration BRD with no domainEntities is `fault`. Same renderer, same absence,
#      different verdict — if these two ever collapse, the surface is lying again.
#
# Usage: bash test-brd-report.sh [path-to-brd-report.sh]
#
# The argument is what run-all.sh passes; it defaults to the toolkit's own copy. Declaring it
# in a `# Usage:` line is not cosmetic — run-all.sh reads that line to find each fixture's
# subject, and a fixture without one gets executed an extra time while the runner probes it.

set -u

TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
BR="${1:-$TOOLKIT/bin/brd-report.sh}"
# Portability: the suite must run on the platforms the toolkit targets. Resolve Python by
# executing candidates, not by name.
# shellcheck disable=SC1091
. "$TOOLKIT/bin/lib/portable.sh"
require_py

PASS=0; FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected '$3', got '$2'"; fi; }
has()  { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "missing '$3'" ;; esac; }
hasnt(){ case "$2" in *"$3"*) bad "$1" "unexpected '$3'" ;; *) ok "$1" ;; esac; }

# brd <project-dir> <kb-name> <file-name> <<json
brd() {
  d="$1/analysis/$2/knowledge-base/brd"
  mkdir -p "$d"
  cat > "$d/$3"
}

echo "== both BRD shapes render =="

# The documented shape (brd-generation.md): modules[], attributes[], target, screens[].
P="$TMP/hand"
brd "$P" src F001-orders.brd.json <<'J'
{
  "id": "F001",
  "title": "Order Registration",
  "provenance": "documents",
  "modules": ["ACME_OrderRegist"],
  "actors": ["OrderRegisterUser"],
  "useCases": [{"id": "UC001", "title": "View list", "actors": ["OrderRegisterUser"],
                "preconditions": ["logged in"], "mainFlow": ["1. open the page"],
                "postconditions": ["list shown"], "screens": ["Order_Overview"]}],
  "domainEntities": [{"name": "OrderDetail", "persistent": true,
                      "attributes": [{"name": "OrderCode"}, {"name": "CustomerCode"}],
                      "associations": [{"name": "a1", "target": "OrderHeader"}]}],
  "microflows": [{"name": "ACT_Save", "purpose": "persist a draft", "validations": ["not blank"]}],
  "pages": [{"name": "Order_NewEdit", "purpose": "entry form"}],
  "integrations": [{"name": "PartnerLookup", "type": "REST"}],
  "openQuestions": [{"id": "D1", "question": "approval branching?"}],
  "sourceKB": ["KB_Spec.md"]
}
J
OUT=$("$BR" "$P" 2>&1); RC=$?
check "the documented shape renders" "$RC" "0"
has "  and finds the BRD" "$OUT" "1 BRD(s)"
H="$P/analysis/brd-report.html"
grep -q 'ACME_OrderRegist' "$H" && ok "  modules[] reaches the page" || bad "  modules[] reaches the page"
grep -q 'OrderHeader' "$H" && ok "  association target reaches the page" || bad "  association target reaches the page"
grep -q 'Order_Overview' "$H" && ok "  useCases[].screens reaches the page" || bad "  useCases[].screens reaches the page"
has "  and no key is reported unreadable" "$OUT" "unreadable keys: 0"

# The scaffolder shape as it shipped: module (singular), attributeCount, a.to, u.screen.
# Every one of these was a key one of the three old reports could not read.
P="$TMP/scaffold"
brd "$P" src Orders.brd.json <<'J'
{
  "module": "Orders",
  "generatedAt": "2026-08-01T00:00:00.000Z",
  "appType": "crud",
  "confidence": "low",
  "summary": {"openGapCount": 7},
  "openGaps": ["fk-unresolved:User"],
  "domainEntities": [{"name": "Order", "mendixType": "PersistentEntity", "attributeCount": 9,
                      "associations": [{"name": "a1", "to": "Customer"}]}],
  "microflows": [{"name": "GET_Orders", "purpose": "read", "hiddenRules": [
                    {"rule": "cancelled orders are hidden after 30 days", "risk": "high"}]}],
  "pages": [{"name": "Orders_List", "uiPattern": "list"}],
  "useCases": [{"id": "UC1", "title": "Orders_List", "reviewStatus": "pending",
                "screen": "Orders_List"}]
}
J
OUT=$("$BR" "$P" 2>&1); RC=$?
check "the scaffolder shape renders" "$RC" "0"
H="$P/analysis/brd-report.html"
grep -q '>Orders<' "$H" && ok "  module (singular) still reaches the page" || bad "  module (singular) still reaches the page"
grep -q 'Customer' "$H" && ok "  association a.to still reaches the page" || bad "  association a.to still reaches the page"
grep -q '>9<' "$H" && ok "  attributeCount still reaches the page" || bad "  attributeCount still reaches the page"
grep -q 'cancelled orders are hidden' "$H" && ok "  hidden rules are derived from microflows[]" || bad "  hidden rules are derived from microflows[]"
has "  the legacy keys are named so the transition can finish" "$OUT" "legacy key(s) still in use"

echo "== a drifted key is a FAULT, not a zero =="
#
# The load-bearing test. `attrCount` is not a name any producer uses; it stands for the NEXT
# rename. The renderer must say it cannot read the attribute count, and must not print 0 —
# printing 0 is what made three reports look complete while saying nothing.

P="$TMP/drift"
brd "$P" src Drifted.brd.json <<'J'
{
  "module": "Drifted",
  "generatedAt": "2026-08-01T00:00:00.000Z",
  "appType": "crud",
  "openGaps": [],
  "domainEntities": [{"name": "Thing", "mendixType": "PersistentEntity", "attrCount": 4,
                      "associations": [{"name": "a1", "points_at": "Other"}]}],
  "microflows": [{"name": "ACT_Do", "purpose": "do"}],
  "pages": [{"name": "P"}],
  "useCases": [{"id": "UC1", "title": "T"}]
}
J
OUT=$("$BR" "$P" 2>&1); RC=$?
check "a drifted key still exits 0 — it is a finding, not a crash" "$RC" "0"
has "the drifted attribute key is reported as a fault" "$OUT" "FAULT  unreadable key"
has "  by name" "$OUT" "domainEntities[].attributes"
has "  saying what it was looked for under" "$OUT" "attributes/attributeCount"
has "  and refusing to call it zero" "$OUT" "NOT as zero"
has "  the drifted association target is caught too" "$OUT" "associations[].target"
check "  and the count is carried, not implied" \
  "$(printf '%s\n' "$OUT" | grep -c 'unreadable keys: 2')" "1"

H="$P/analysis/brd-report.html"
grep -q 'class="unknown"' "$H" && ok "  the page renders it as ? not 0" || bad "  the page renders it as ? not 0"
grep -q 'Unreadable keys' "$H" && ok "  and lists it in its own block" || bad "  and lists it in its own block"

# The negative half: an entity that genuinely HAS no attributes is a real zero, not a drift.
# Without this the check above passes trivially by shouting at every BRD.
P="$TMP/realzero"
brd "$P" src Real.brd.json <<'J'
{"id": "F1", "provenance": "documents", "modules": ["M"], "useCases": [{"id": "U", "title": "t"}],
 "domainEntities": [{"name": "Empty", "attributes": []}]}
J
OUT=$("$BR" "$P" 2>&1)
has "an explicitly empty attributes[] is a real zero, not a drift" "$OUT" "unreadable keys: 0"

echo "== every knowledge base is read =="
#
# discover-brds.sh's own regression, re-earned by this consumer. Two source folders, 1 + 2
# BRDs. A reader that globbed the first match would report 1.

P="$TMP/multikb"
brd "$P" source A.brd.json <<'J'
{"id":"A","provenance":"documents","modules":["A"],"useCases":[{"id":"U","title":"t"}]}
J
brd "$P" alt-source B.brd.json <<'J'
{"id":"B","provenance":"documents","modules":["B"],"useCases":[{"id":"U","title":"t"}]}
J
brd "$P" alt-source C.brd.json <<'J'
{"id":"C","provenance":"documents","modules":["C"],"useCases":[{"id":"U","title":"t"}]}
J
OUT=$("$BR" "$P" 2>&1)
has "all three BRDs across two knowledge bases are read" "$OUT" "3 BRD(s) across 2 knowledge-base dir(s)"
has "  and the count carries its denominator" "$OUT" "of 27 = 3 BRD(s) x 9 sections"

echo "== no BRDs is never a pass =="

P="$TMP/empty"; mkdir -p "$P/analysis"
OUT=$("$BR" "$P" 2>&1); RC=$?
check "an empty project exits 3, not 0" "$RC" "3"
has "  and names where it looked" "$OUT" "analysis/*/knowledge-base/brd"
[ -f "$P/analysis/brd-report.html" ] && bad "  and writes no page over no data" || ok "  and writes no page over no data"

OUT=$("$BR" "$TMP/no-such-dir" 2>&1); RC=$?
check "a missing project dir is a usage error" "$RC" "2"

P="$TMP/broken"
brd "$P" src X.brd.json <<'J'
{ this is not json
J
OUT=$("$BR" "$P" 2>&1); RC=$?
check "an unparseable BRD exits 4, not 0" "$RC" "4"
has "  and names the file" "$OUT" "X.brd.json"

echo "== provenance decides what an absence means =="

# Same absence — no domainEntities — must read differently on the two provenances.
P="$TMP/reqs"
brd "$P" src F9.brd.json <<'J'
{"id":"F9","title":"Reqs only","provenance":"interview","modules":["M"],
 "useCases":[{"id":"UC1","title":"Do a thing","mainFlow":["1. do it"]}]}
J
OUT=$("$BR" "$P" 2>&1); RC=$?
check "a requirements BRD with no entities still exits 0" "$RC" "0"
hasnt "  and its missing domainEntities is NOT a fault" "$OUT" "FAULT  domainEntities"
H="$P/analysis/brd-report.html"
grep -q 'v-skipped' "$H" && ok "  it is skipped" || bad "  it is skipped"
grep -q 'optional for a interview BRD' "$H" \
  && ok "  with the reason printed on the page" || bad "  with the reason printed on the page"

P="$TMP/mig"
brd "$P" src Mig.brd.json <<'J'
{"module":"Mig","generatedAt":"2026-08-01T00:00:00.000Z","appType":"crud","openGaps":[],
 "domainEntities":[],"microflows":[],"pages":[],"useCases":[]}
J
OUT=$("$BR" "$P" 2>&1)
has "a migration BRD with no entities IS a fault" "$OUT" "FAULT  domainEntities"
has "  and says which provenance expected it" "$OUT" "a code-extracted BRD is expected to carry it"
has "  the same for microflows" "$OUT" "FAULT  microflows"
hasnt "  but never calls it a zero" "$OUT" "0 domain entities"

# Provenance that cannot be determined is SAID, never guessed. A guess here decides whether a
# missing domain model is a finding or a non-event, and being wrong either way is the bug.
P="$TMP/mystery"
brd "$P" src M.brd.json <<'J'
{"id":"M","title":"Where did this come from","modules":["M"]}
J
OUT=$("$BR" "$P" 2>&1); RC=$?
check "an undetermined provenance still renders" "$RC" "0"
has "  and says so in as many words" "$OUT" "PROVENANCE UNDETERMINED"
has "  naming what it looked for" "$OUT" "no \"provenance\" key, no extractor fingerprint, and no sourceKB"
has "  and refuses a verdict on every section" "$OUT" "9 section(s) cannot be verdicted"
hasnt "  rather than defaulting them to a pass" "$OUT" "No faults."

# A declared provenance nobody recognises must not be silently coerced onto a known one.
P="$TMP/weird"
brd "$P" src W.brd.json <<'J'
{"id":"W","modules":["W"],"provenance":"vibes","useCases":[{"id":"U","title":"t"}]}
J
OUT=$("$BR" "$P" 2>&1)
has "an unrecognised declared provenance is undetermined, not coerced" "$OUT" "PROVENANCE UNDETERMINED"
has "  and quotes what was declared" "$OUT" "vibes"

echo "== brd-validation.md check 5: both signals, together =="

P="$TMP/check5"
brd "$P" src Low.brd.json <<'J'
{"module":"Low","generatedAt":"2026-08-01T00:00:00.000Z","appType":"crud","openGaps":[],
 "confidence":"low","sourceKB":["KB_Spec.md"],
 "domainEntities":[{"name":"E","attributeCount":1}],"microflows":[{"name":"m","purpose":"p"}],
 "pages":[{"name":"p"}],
 "useCases":[{"id":"U","title":"t","status":"doc-confirmed"}]}
J
brd "$P" src Bare.brd.json <<'J'
{"module":"Bare","generatedAt":"2026-08-01T00:00:00.000Z","appType":"crud","openGaps":[],
 "confidence":"low",
 "domainEntities":[{"name":"E","attributeCount":1}],"microflows":[{"name":"m","purpose":"p"}],
 "pages":[{"name":"p"}],"useCases":[{"id":"U","title":"t"}]}
J
# A BRD outside the one pair check 5 actually ranks must be left explicitly unranked, or the
# renderer has invented an ordering the skill declined to make.
brd "$P" src High.brd.json <<'J'
{"module":"High","generatedAt":"2026-08-01T00:00:00.000Z","appType":"crud","openGaps":[],
 "confidence":"high",
 "domainEntities":[{"name":"E","attributeCount":1}],"microflows":[{"name":"m","purpose":"p"}],
 "pages":[{"name":"p"}],"useCases":[{"id":"U","title":"t"}]}
J
"$BR" "$P" --quiet
H="$P/analysis/brd-report.html"
grep -q 'review-ready' "$H" \
  && ok "low confidence WITH doc corroboration is the better review candidate" \
  || bad "low confidence WITH doc corroboration is the better review candidate"
grep -q 'uncorroborated' "$H" \
  && ok "  low confidence with NEITHER signal is called out separately" \
  || bad "  low confidence with NEITHER signal is called out separately"
grep -q 'Code confidence' "$H" && grep -q 'Doc-KB corroboration' "$H" \
  && ok "  both signals appear together, not confidence alone" \
  || bad "  both signals appear together, not confidence alone"
grep -q 'ranks only the low-confidence pair' "$H" \
  && ok "  and the ordering the skill does not make is left unmade" \
  || bad "  and the ordering the skill does not make is left unmade"

echo "== output =="

P="$TMP/out"
brd "$P" src O.brd.json <<'J'
{"id":"O","provenance":"documents","modules":["O"],"useCases":[{"id":"U","title":"t"}]}
J
"$BR" "$P" --html "$TMP/out/custom.html" --quiet
[ -s "$TMP/out/custom.html" ] && ok "--html writes where it is told" || bad "--html writes where it is told"
grep -q 'toolkit-guide.html' "$TMP/out/custom.html" \
  && ok "  and says where its shell tokens come from" || bad "  and says where its shell tokens come from"
grep -q -- '--pass-bg' "$TMP/out/custom.html" \
  && ok "  carrying the shared token block" || bad "  carrying the shared token block"

OUT=$("$BR" "$P" --json 2>&1)
printf '%s' "$OUT" | "$PY" -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d["brdCount"]==1 and d["sectionCells"]==9 and "verdicts" in d else 1)' \
  && ok "--json is machine-readable and carries its denominator" \
  || bad "--json is machine-readable and carries its denominator"

OUT=$("$BR" "$P" --quiet 2>&1)
check "--quiet says nothing" "$OUT" ""

OUT=$("$BR" "$P" --nonsense 2>&1); RC=$?
check "an unknown option is a usage error" "$RC" "2"

echo
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
