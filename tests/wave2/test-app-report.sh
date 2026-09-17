#!/bin/bash
# test-app-report.sh — pin the app-analysis instrument's parser and the dossier renderer.
#
# Runs with no mxcli and no .mpr: the parser is exercised through `app-facts.sh --parse-only`
# on captured MDL under fixtures/app-analysis/facts/mdl, and the renderer on the captured
# facts plus a deliberately imperfect dossier. What is worth pinning:
#
#   1. POSITIVE CONTROLS. A loop body with a database retrieve, a commit, a delete, a REST call,
#      a microflow call and a nested loop must produce every one of those facts, with line
#      numbers that point into the MDL. A parser that finds nothing on this file is blind.
#   2. NEGATIVE CONTROL. A loop that only changes objects in memory, with a retrieve BEFORE it
#      and a commit AFTER it, must produce an empty in_loop. Otherwise every loop is a finding
#      and the section gets switched off, which is how lint died once already.
#   3. MISMATCH DIRECTION. parsed > catalog is normal (the catalog holds top-level activities
#      only, verified 2026-09-15); parsed < catalog is the only mismatch worth listing.
#   4. SCHEDULED REACHABILITY travels into the record.
#   5. RENDERER VERDICTS: instrument fault beats a dossier pass; a missing dossier section is
#      fault; no dossier at all is manual; no manifest is exit 2.
#   6. TRANSACTION CONTROL inside a loop is recorded even though it is a Java call.
#   7. HEALTH IS NOT REVIEW PROGRESS. The section verdicts judge the document and go `fail` the
#      moment a finding has no disposition. Health is scored from the facts and must come out
#      the same with a full dossier and with none at all: that is the whole point of splitting
#      them, and it is the check that would have caught the bug this redesign fixed.
#   8. SEVERITY ORDER. A pattern that runs from an ENABLED scheduled event in a widely depended
#      on module must outrank the same pattern in a quiet corner, and the fix-first list must be
#      sorted worst first. A severity model that puts everything in one bucket is the old page.
#   9. MACHINE READABLE. app-report.json lands next to the HTML with the same numbers, and the
#      page carries the same object inline, so the next agent never parses a table.
#  10. LONG TABLES FOLD. Over COLLAPSE_ROWS rows, a table is behind a <details>, including a
#      table that came from the dossier's own markdown.
#
# Usage: bash test-app-report.sh [path-to-app-report.sh]

set -u

TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
AR="${1:-$TOOLKIT/bin/app-report.sh}"
AF="$TOOLKIT/project-bin/app-facts.sh"
FIX="$TOOLKIT/fixtures/app-analysis"
# shellcheck disable=SC1091
. "$TOOLKIT/bin/lib/portable.sh"
require_py

PASS=0; FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected '$3', got '$2'"; fi; }
# Path segments are "/"-separated (not "."): several fixture keys (qualified microflow names)
# contain literal dots, so "." cannot double as both a path separator and part of a key.
jq_()  { "$PY" -c 'import json,sys; d=json.load(open(sys.argv[1]))
for k in sys.argv[2].split("/"):
    d = d[int(k)] if isinstance(d, list) else d.get(k, "MISSING")
    if d == "MISSING": break
print(json.dumps(d) if isinstance(d,(dict,list)) else d)' "$1" "$2"; }

echo "== parser (app-facts.sh --parse-only) =="
cp -R "$FIX/facts" "$TMP/facts"
bash "$AF" --parse-only "$TMP/facts" >/dev/null 2>"$TMP/parse.err"; RC=$?
check "parse-only exits 0" "$RC" "0"
L="$TMP/facts/loops.json"
[ -f "$L" ] && ok "loops.json written" || { bad "loops.json written" "$(cat "$TMP/parse.err")"; exit 1; }
check "six MDL files parsed" "$(jq_ "$L" _meta/parsed)" "6"
check "parsed > catalog counted as catalog undercount, not mismatch" "$(jq_ "$L" _meta/catalog_undercount)" "2"

R="microflows/Catalog.SUB_Reprice"
check "amplifier fixture: three database retrieves in one loop body" "$(jq_ "$L" "$R/in_loop/RETRIEVE_DB")" "3"
check "amplifier fixture: nested loop recorded"                      "$(jq_ "$L" "$R/nested_loop_lines")" "[10]"

W="microflows/Orders.SUB_DrainQueue"
check "while loop: counted as a loop"                "$(jq_ "$L" "$W/loops_parsed")" "1"
check "while loop: RETRIEVE_DB inside counted"       "$(jq_ "$L" "$W/in_loop/RETRIEVE_DB")" "1"
check "while loop: change ... commit inside counted" "$(jq_ "$L" "$W/in_loop/COMMIT")" "1"
check "while loop: microflow call inside counted"    "$(jq_ "$L" "$W/in_loop/MICROFLOW_CALL")" "1"
check "while loop: not a parse mismatch"             "$("$PY" -c 'import json;print(sum(1 for m in json.load(open("'"$L"'"))["_meta"]["parse_mismatch"] if m["microflow"]=="Orders.SUB_DrainQueue"))')" "0"

S="microflows/Orders.SUB_SyncOrderLines"
check "positive: RETRIEVE_DB in loop"      "$(jq_ "$L" "$S/in_loop/RETRIEVE_DB")" "1"
check "positive: RETRIEVE_ASSOC in loop"   "$(jq_ "$L" "$S/in_loop/RETRIEVE_ASSOC")" "1"
check "positive: REST_CALL in loop"        "$(jq_ "$L" "$S/in_loop/REST_CALL")" "1"
check "positive: COMMIT in loop"           "$(jq_ "$L" "$S/in_loop/COMMIT")" "1"
check "positive: DELETE in loop"           "$(jq_ "$L" "$S/in_loop/DELETE")" "1"
check "positive: MICROFLOW_CALL in loop"   "$(jq_ "$L" "$S/in_loop/MICROFLOW_CALL")" "1"
check "positive: nested loop recorded"     "$(jq_ "$L" "$S/nested_loop_lines")" "[20]"
check "positive: RETRIEVE_DB line points into the MDL" "$(jq_ "$L" "$S/in_loop_lines/RETRIEVE_DB")" "[13]"
check "positive: two loops parsed, catalog one, NOT a mismatch" "$(jq_ "$L" "$S/loops_parsed")" "2"
check "positive: scheduled reachability travels" "$(jq_ "$L" "$S/reachable_from_scheduled_events")" '["Orders.SE_NightlySync"]'
check "scheduled: enabled list carried"  "$(jq_ "$L" "$S/reachable_from_scheduled_events_enabled")" '["Orders.SE_NightlySync"]'
check "scheduled: disabled-only reach is separated" "$(jq_ "$L" "microflows/Orders.SUB_TxPerItem/reachable_from_scheduled_events_enabled")" '[]'
check "scheduled: disabled-only reach still listed"  "$(jq_ "$L" "microflows/Orders.SUB_TxPerItem/reachable_from_scheduled_events_disabled")" '["Orders.SE_NightlySync"]'
check "the commit AFTER the loop is not counted (exactly one COMMIT)" "$(jq_ "$L" "$S/in_loop/COMMIT")" "1"

N="microflows/Orders.SUB_MarkSent"
check "negative: in-memory-only loop has empty in_loop" "$(jq_ "$L" "$N/in_loop")" "{}"
check "negative: retrieve before the loop not counted"  "$(jq_ "$L" "$N/in_loop/RETRIEVE_DB")" "MISSING"

check "mismatch listed only when parsed < catalog" "$(jq_ "$L" _meta/parse_mismatch/0/microflow)" "Orders.SUB_Truncated"
check "exactly one mismatch (nested loop is not one)" "$("$PY" -c 'import json;print(len(json.load(open("'"$L"'"))["_meta"]["parse_mismatch"]))')" "1"

T="microflows/Orders.SUB_TxPerItem"
check "transaction Java actions in a loop are recorded" "$(jq_ "$L" "$T/transaction_action_lines")" "[7, 9]"
check "change ... commit inside loop counts as COMMIT"  "$(jq_ "$L" "$T/in_loop/COMMIT")" "1"
check "Java calls in loop counted"                      "$(jq_ "$L" "$T/in_loop/JAVA_CALL")" "2"

echo "== renderer (app-report.sh) =="
OUT="$TMP/report.json"
bash "$AR" --facts "$TMP/facts" --dossier "$FIX/app-dossier.md" --json > "$OUT" 2>"$TMP/r.err"; RC=$?
check "renders with dossier, exit 0" "$RC" "0"
check "dossier fail carries through"               "$(jq_ "$OUT" 'verdicts/Dependency shape')" "fail"
check "instrument fault beats a dossier pass"      "$(jq_ "$OUT" 'verdicts/Security posture')" "fault"
check "dossier pass on a collected section passes" "$(jq_ "$OUT" 'verdicts/Flow risk patterns')" "pass"
check "missing dossier section is fault"           "$(jq_ "$OUT" 'verdicts/Dead elements')" "fault"
check "skipped stays skipped"                      "$(jq_ "$OUT" 'verdicts/Lint baseline')" "skipped"
check "dispositions present -> manual"             "$(jq_ "$OUT" 'verdicts/Dispositions')" "manual"
check "loop shape counts REST calls from facts"    "$(jq_ "$OUT" loop_shape/with_rest_call)" "1"
check "loop shape counts scheduled-reachable"      "$(jq_ "$OUT" loop_shape/scheduled_reachable)" "2"
check "loop shape counts enabled-reachable separately" "$(jq_ "$OUT" loop_shape/scheduled_reachable_enabled)" "1"
check "loop shape: microflow-call-only excludes DB work and Java" "$(jq_ "$OUT" loop_shape/with_microflow_call_only)" "0"
check "loop shape carries catalog undercount"      "$(jq_ "$OUT" loop_shape/catalog_undercount)" "2"
check "loop shape states the denominator: bodies doing nothing scored" "$(jq_ "$OUT" loop_shape/bodies_doing_nothing_scored)" "1"
check "numbered, bold verdict cell (2. Inventory / **pass**) is read" "$(jq_ "$OUT" 'verdicts/Inventory')" "pass"

echo "== health, severity and review progress =="
# Health is scored from facts. The fixture app has a loop with a REST call that a live
# scheduled event reaches: that is the worst thing an app can do per iteration and it must
# come out critical, above the same microflow's other patterns.
check "health state is derived, not a verdict word" "$(jq_ "$OUT" health/state)" "at risk"
check "REST call in a scheduled loop is critical"   "$(jq_ "$OUT" fix_first/0/severity)" "critical"
check "the critical finding is the REST one"        "$(jq_ "$OUT" fix_first/0/pattern)" "REST_IN_LOOP"
check "fix-first is sorted worst first"             "$("$PY" -c 'import json
s=[f["score"] for f in json.load(open("'"$OUT"'"))["fix_first"]]
print(s == sorted(s, reverse=True))')" "True"
check "fix-first names the microflow"               "$(jq_ "$OUT" fix_first/0/target)" "Orders.SUB_SyncOrderLines"
check "every finding carries a recommended fix"     "$("$PY" -c 'import json;print(sum(1 for f in json.load(open("'"$OUT"'"))["findings"] if not f["recommended_fix"]))')" "0"

# ---- PLAIN LANGUAGE ------------------------------------------------------------------------
# The defect that sent this pass back: a reader met LOOP_TQ, LOOP_COMMIT_DEFERRED, DEP_TANGLE
# and catalog_undercount and could not read the page without asking what a loop body was.
# Every code the renderer can print must carry its own sentence, in the page, where it appears.
check "every finding carries a plain-language name" "$("$PY" -c 'import json;print(sum(1 for f in json.load(open("'"$OUT"'"))["findings"] if not f["plain"] or f["plain"]==f["pattern"]))')" "0"
check "every finding carries a sentence saying what the pattern means" "$("$PY" -c 'import json
print(sum(1 for f in json.load(open("'"$OUT"'"))["findings"] if len(f.get("means","")) < 30))')" "0"
check "the glossary defines loop body"              "$("$PY" -c 'import json;print("loop body" in json.load(open("'"$OUT"'"))["glossary"])')" "True"
# Nothing may reach the page as a bare code. This walks every code the renderer CAN emit,
# not only the ones this fixture happens to produce, so a new pattern without a sentence fails.
check "every code the renderer can emit has a glossary entry" "$("$PY" -c '
import json,re,sys
g=json.load(open("'"$OUT"'"))["glossary"]
src=open("'"$AR"'",encoding="utf-8").read()
codes=set()
for block in re.findall(r"PATTERN_W = \{(.*?)\}", src, re.S) + re.findall(r"PLAIN = \{(.*?)\n\}", src, re.S):
    codes |= set(re.findall(r"\"([A-Z_]{4,})\"", block))
codes |= {"RETRIEVE_DB","RETRIEVE_ASSOC","COMMIT","DELETE","ROLLBACK","REST_CALL","MICROFLOW_CALL","JAVA_CALL","JS_CALL"}
codes |= {"catalog_undercount","parse_mismatch","rules_not_describable"}
missing=sorted(c for c in codes if c not in g)
print(missing or "none")')" "none"

# ---- ZERO IS A RESULT ------------------------------------------------------------------------
# The two patterns that take a Mendix runtime down were absent on the real app AND invisible,
# because a zero rendered as an unlabelled tile among fourteen. A zero count must render as a
# stated checked fact with its method, never as a missing row.
check "checks run whether they find anything or not" "$("$PY" -c 'import json;print(len(json.load(open("'"$OUT"'"))["checks"]))')" "8"
check "a zero-count check is still in the list"      "$("$PY" -c 'import json
print(sum(1 for c in json.load(open("'"$OUT"'"))["checks"] if c["count"]==0))')" "1"
check "every check states how it was checked"        "$("$PY" -c 'import json
print(sum(1 for c in json.load(open("'"$OUT"'"))["checks"] if len(c["method"])<20 or len(c["reading"])<20))')" "0"
check "the two runtime-killing patterns are both checked" "$("$PY" -c 'import json
codes={c["code"] for c in json.load(open("'"$OUT"'"))["checks"]}
print(sorted(codes & {"REST_IN_LOOP","END_TRANSACTION"}))')" "['END_TRANSACTION', 'REST_IN_LOOP']"

# ---- THE SEVERITY BAND MUST DISCRIMINATE -----------------------------------------------------
# 187 of 229 findings in one band is a shrug, not a finding. Three fixes, each pinned here.
# 1. Amplifiers alone never reach high. Catalog.SUB_Reprice has all three of them (a nested
#    loop, the same retrieve three times, and a module eleven others reference) and no timer
#    runs it, so it tops out at medium however many amplifiers pile on.
check "amplifiers alone never reach high"           "$("$PY" -c 'import json
f=[x for x in json.load(open("'"$OUT"'"))["findings"] if x["target"]=="Catalog.SUB_Reprice"][0]
print(f["severity"], f["score"])')" "medium 3"
# The ceiling, stated as an invariant over every loop finding rather than one fixture row: a
# switched-off timer is a loaded gun, not a fire, so it cannot buy a high on amplifiers either.
check "no loop finding is high without an enabled timer or a per-item round trip" "$("$PY" -c 'import json
bad=[f["target"] for f in json.load(open("'"$OUT"'"))["findings"]
     if f["kind"]=="loop" and f["severity"] in ("critical","high")
     and "enabled scheduled event" not in f["why"]
     and f["pattern"] not in ("REST_IN_LOOP","END_TRANSACTION")]
print(bad or "none")')" "none"
# 2. Blast radius counts MODULES, not reference edges. Catalog has inbound_edges 96 in the
#    cohesion facts and only eleven distinct inbound modules; the old page would have said
#    "depended on by 96 others" of an app with thirteen own modules.
check "blast radius is stated as modules, within the module count" "$("$PY" -c 'import json,re
d=json.load(open("'"$OUT"'"))
own=d["totals"]["modules_own"]
bad=[x["why"] for x in d["findings"]
     for m in re.findall(r"(\d+) other own modules reference", x["why"]) if int(m) > own]
print(bad or "none")')" "none"
# 3. A nested loop is an amplifier, not a finding. A loop inside a loop with nothing in either
#    body costs nothing, and scoring it as its own row is how the medium band filled up.
check "LOOP_NESTED is never a standalone finding"   "$("$PY" -c 'import json
print(sum(1 for f in json.load(open("'"$OUT"'"))["findings"] if f["pattern"]=="LOOP_NESTED"))')" "0"
check "a nested loop still raises the finding it amplifies" "$("$PY" -c 'import json
f={(x["pattern"],x["target"]):x for x in json.load(open("'"$OUT"'"))["findings"]}
print("multiplies" in f[("LOOP_TQ","Catalog.SUB_Reprice")]["why"])')" "True"
# 4. The structural finding outranks every loop but one. A tangle covering ten of thirteen own
#    modules is a decision about how the app is built, not a row like all the other rows.
check "a tangle covering most of the app is critical" "$("$PY" -c 'import json
f=[x for x in json.load(open("'"$OUT"'"))["findings"] if x["pattern"]=="DEP_TANGLE"][0]
print(f["severity"])')" "critical"
check "the tangle finding states the share of the app it covers" "$("$PY" -c 'import json
f=[x for x in json.load(open("'"$OUT"'"))["findings"] if x["pattern"]=="DEP_TANGLE"][0]
print("%" in f["why"] and "tested" in f["why"])')" "True"
# 5. A bidirectional pair inside the tangle is not reported twice; one outside it still is.
check "a pair outside the tangle is still its own finding" "$("$PY" -c 'import json
print(sorted(x["target"] for x in json.load(open("'"$OUT"'"))["findings"] if x["pattern"]=="DEP_PAIR"))')" "['Tax <-> Users']"
# 6. And the bands must actually spread. One band holding most of the findings is the old page.
check "no single severity band holds most of the findings" "$("$PY" -c 'import json
d=json.load(open("'"$OUT"'"))["health"]["severity"]; t=sum(d.values())
print(max(d.values()) <= 0.6*t, d)' | cut -d" " -f1)" "True"
check "severity uses four words, nothing else"      "$("$PY" -c 'import json;print(sorted({f["severity"] for f in json.load(open("'"$OUT"'"))["findings"]}))')" "['critical', 'high', 'low', 'medium']"
# The same pattern in a quiet module must not score the same as one on the nightly path.
check "scheduled reach outranks the same pattern elsewhere" "$("$PY" -c 'import json
f={(x["pattern"],x["target"]):x["score"] for x in json.load(open("'"$OUT"'"))["findings"]}
print(f[("LOOP_TQ","Orders.SUB_SyncOrderLines")] > f[("LOOP_TQ","Orders.SUB_DrainQueue")])')" "True"
check "a decided disposition line is matched to its finding" "$("$PY" -c 'import json
print([x["decision"] for x in json.load(open("'"$OUT"'"))["findings"] if x["target"]=="Orders.SUB_SyncOrderLines"][0])')" "decided: fix"
check "later plus undecided is not a decision"      "$("$PY" -c 'import json
print([x["decision"] for x in json.load(open("'"$OUT"'"))["findings"] if x["target"]=="Orders.SUB_DrainQueue"][0])')" "later, no decision"
check "review progress counts decided lines"        "$(jq_ "$OUT" review_progress/lines_with_a_decision)" "1"
check "review progress is its own state"            "$(jq_ "$OUT" review_progress/state)" "in progress"
check "sections not collected are named, not implied clean" "$(jq_ "$OUT" health/not_measured)" '["lint_baseline", "security"]'

bash "$AR" --facts "$TMP/facts" --dossier "$TMP/none.md" --json > "$OUT" 2>/dev/null; RC=$?
check "no dossier: exit 0" "$RC" "0"
check "no dossier: sections are manual, not pass"  "$(jq_ "$OUT" 'verdicts/Dependency shape')" "manual"
check "no dossier: instrument fault still fault"   "$(jq_ "$OUT" 'verdicts/Security posture')" "fault"
# THE POINT OF THE SPLIT. With no dossier at all the review has not started, and the app is
# exactly as healthy as it was a line ago. A health number that moves when the document moves
# is the bug this replaced.
check "no dossier: health is unchanged"            "$(jq_ "$OUT" health/state)" "at risk"
check "no dossier: severity counts are unchanged"  "$(jq_ "$OUT" health/severity/critical)" "2"
check "no dossier: findings still scored"          "$(jq_ "$OUT" health/findings_total)" "14"
check "no dossier: the checked-and-absent facts are unchanged" "$("$PY" -c 'import json
print(sum(1 for c in json.load(open("'"$OUT"'"))["checks"] if c["count"]==0))')" "1"
check "no dossier: review progress says not started" "$(jq_ "$OUT" review_progress/state)" "not started"
check "no dossier: nothing carries a decision"     "$(jq_ "$OUT" review_progress/lines_with_a_decision)" "0"

bash "$AR" --facts "$TMP/facts" --dossier "$FIX/app-dossier.md" -o "$TMP/r.html" >/dev/null 2>&1; RC=$?
check "HTML render exits 0" "$RC" "0"
H="$(cat "$TMP/r.html" 2>/dev/null)"
case "$H" in *"Orders.SUB_SyncOrderLines"*) ok "HTML lists the loop microflow" ;; *) bad "HTML lists the loop microflow" ;; esac
case "$H" in *"DEP-TANGLE-01"*) ok "HTML carries dossier text" ;; *) bad "HTML carries dossier text" ;; esac
case "$H" in *'has no "Dead elements" section'*) ok "HTML says the missing section is missing" ;; *) bad "HTML says the missing section is missing" ;; esac
case "$H" in *'Executive summary'*) ok "HTML opens with an executive summary" ;; *) bad "HTML opens with an executive summary" ;; esac
case "$H" in *'Fix first'*) ok "HTML carries a fix-first list" ;; *) bad "HTML carries a fix-first list" ;; esac
case "$H" in *'>critical<'*) ok "HTML shows the severity word, not only a count" ;; *) bad "HTML shows the severity word, not only a count" ;; esac
case "$H" in *'app-report-data'*) ok "HTML embeds the machine-readable block" ;; *) bad "HTML embeds the machine-readable block" ;; esac
# THE BRIEF, IN ONE CHECK. A reader who met this page could not read it and asked what a loop
# body was. The sentence has to be in the page, in the section where the codes appear, not in
# a skill file nobody opens.
case "$H" in *'A loop repeats them once for every item in a list'*) ok "HTML defines a loop body in words" ;; *) bad "HTML defines a loop body in words" ;; esac
case "$H" in *'The words this report uses'*) ok "HTML carries a glossary section" ;; *) bad "HTML carries a glossary section" ;; esac
case "$H" in *'database query inside a loop'*) ok "HTML names LOOP_TQ in plain language, not only as a code" ;; *) bad "HTML names LOOP_TQ in plain language, not only as a code" ;; esac
case "$H" in *'What was checked, including what was not there'*) ok "HTML states zero results as checked facts" ;; *) bad "HTML states zero results as checked facts" ;; esac
case "$H" in *'The structural decision, ahead of every loop'*) ok "HTML gives the tangle its own callout" ;; *) bad "HTML gives the tangle its own callout" ;; esac
case "$H" in *'Where this section is blind'*) ok "HTML names the loop section's blind spots" ;; *) bad "HTML names the loop section's blind spots" ;; esac
# Every code visible in the page body must have its sentence somewhere in the page. This is the
# check that fails the moment a new pattern is added without a reader-facing explanation.
"$PY" -c '
import json,re,sys
h=open(sys.argv[1],encoding="utf-8").read()
g=json.loads(re.search(r"<script type=\"application/json\" id=\"app-report-data\">(.*?)</script>",h,re.S).group(1).replace("<\\/","</"))["glossary"]
import html as H
body=H.unescape(re.sub(r"<script.*?</script>","",h,flags=re.S))
# a code, for this purpose, is an ALL_CAPS token carrying an underscore (so English words in
# caps and bare asset types like ENTITY are not swept in) plus the three lowercase meta names
codes=set(re.findall(r"\b([A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+)\b", body))
codes |= set(re.findall(r"\b(catalog_undercount|parse_mismatch|rules_not_describable)\b", body))
missing=sorted(c for c in codes if c not in g or g[c] not in body)
print("missing explanation in the page for: %s" % missing, file=sys.stderr) if missing else None
sys.exit(1 if missing else 0)' "$TMP/r.html" \
  && ok "every code printed in the page has its sentence in the page" || bad "every code printed in the page has its sentence in the page"
# And a zero renders as a row with a number and a method, never as a silently absent row.
"$PY" -c '
import re,sys
h=open(sys.argv[1],encoding="utf-8").read()
m=re.search(r"What was checked.*?</table>",h,re.S)
sys.exit(0 if m and ">0</b>" in m.group(0) and "mxcli describe" in m.group(0) else 1)' "$TMP/r.html" \
  && ok "a zero count renders as a stated checked fact with its method" || bad "a zero count renders as a stated checked fact with its method"
# The executive summary must come before the section verdict table: a reader who stops after
# one screen has to have read the health picture, not the document's progress bar.
"$PY" -c 'import sys;h=open(sys.argv[1],encoding="utf-8").read()
sys.exit(0 if h.index("Executive summary") < h.index("1. Verdict summary") else 1)' "$TMP/r.html" \
  && ok "executive summary precedes the verdict table" || bad "executive summary precedes the verdict table"
[ -f "$TMP/r.json" ] && ok "app-report.json written next to the page" || bad "app-report.json written next to the page"
check "sidecar JSON carries the same health state" "$(jq_ "$TMP/r.json" health/state)" "at risk"
check "sidecar JSON keeps the section verdicts too" "$(jq_ "$TMP/r.json" 'verdicts/Security posture')" "fault"
# A dossier table of 229 rows inlined into the page is what made the old one unreadable.
"$PY" -c 'import sys,re;h=open(sys.argv[1],encoding="utf-8").read()
big=[t for t in re.findall(r"<table.*?</table>",h,re.S) if t.count("<tr>")>12]
sys.exit(0 if all(h[:h.index(t)].rindex("<details")>h[:h.index(t)].rindex("</details>") if "</details>" in h[:h.index(t)] else "<details" in h[:h.index(t)] for t in big) else 1)' "$TMP/r.html" \
  && ok "every table over 12 rows sits inside a details" || bad "every table over 12 rows sits inside a details"

# A long table written by hand INTO the dossier folds the same way the fact tables do. The
# fixture app is too small to produce one, so build the case rather than assume it.
{ cat "$FIX/app-dossier.md"; printf '\n## 7. Dead elements\n\n| asset | note |\n|---|---|\n'
  i=1; while [ "$i" -le 20 ]; do printf '| Orders.Row%02d | candidate |\n' "$i"; i=$((i+1)); done; } > "$TMP/long.md"
bash "$AR" --facts "$TMP/facts" --dossier "$TMP/long.md" -o "$TMP/long.html" >/dev/null 2>&1
case "$(cat "$TMP/long.html")" in *"table from the dossier"*) ok "a 20-row dossier table folds behind a details" ;; *) bad "a 20-row dossier table folds behind a details" ;; esac
case "$(cat "$TMP/long.html")" in *"Orders.Row20"*) ok "folding hides the rows, never drops them" ;; *) bad "folding hides the rows, never drops them" ;; esac

mkdir -p "$TMP/empty"
bash "$AR" --facts "$TMP/empty" --json >/dev/null 2>&1; RC=$?
check "no manifest: exit 2, never a page" "$RC" "2"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
