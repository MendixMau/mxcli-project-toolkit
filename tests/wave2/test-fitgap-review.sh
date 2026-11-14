#!/usr/bin/env bash
# test-fitgap-review.sh — build-ready item 7: a fit-gap with a Marketplace review must exist
# (bin/lib/marketplace-check.sh mxtk_fitgap_review, bin/lib/marketplace-catalogue.tsv; the
# judgement is skills/marketplace-catalogue.md).
#
# Usage: bash tests/wave2/test-fitgap-review.sh [path-to-gate-check.sh]
#
# Input is a fit-gap markdown table, the format architecture-blueprint.md Step 4 prescribes and
# a person or agent writes by hand; there is no tool output to capture. No mxcli is called.
#
#   F1  no fit-gap                                   -> ✗ Fit-gap naming what to write; rc != 0
#   F2  fit-gap with no Verdict column               -> ✗ no table with a Verdict column
#   F3  a row whose verdict is "TBD"                 -> ✗ naming its line
#   F4  Build row: hand-written LLM call             -> ✗ naming genai-llm and the line
#   F5  F4's row plus "Marketplace: ... because"     -> ✓
#   F6  same capability, Buy `GenAICommons`          -> ✓
#   F7  Build row for plain domain logic             -> ✓ (no catalogue keyword)
#   F8  Build row that names the component           -> ✓ ("Document Generation ... too rigid")
#   F9  --waive artifact/fit-gap --reason            -> ✓ WAIVED, F1's project
#   F10 --adopt 5                                    -> ✓ not owed
#   F11 greenfield, no fit-gap -> ✓ not owed; greenfield WITH a bad fit-gap -> ✗ (a file is read)
#   F12 two-tree layout (app/App.mpr)                -> same verdict as F4
#   F14 Build row with an ACCIDENTAL keyword ("custom chart widget") -> ✗ naming `charts`; the same
#       row with a one-sentence "Marketplace: ... not used because ..." reason -> ✓
#   F14c Build row saying only "Marketplace: not used because ..." (no component) -> ✓
#   F15 `Build type: poc`: no fit-gap -> not owed; with a fit-gap -> still read; `full` -> not exempt
#   Item 7 is ADVISORY (⚠, never counted in the fails total) until a real project has passed it.
#   F13 marketplace line is untouched: the item is printed after "Marketplace:" and Stage 5 is
#       not changed by it (gate-check <p> 5 never prints "Fit-gap:")
# Keep bash-3.2 compatible.
set -uo pipefail

GC="${1:-$(cd "$(dirname "$0")/../.." && pwd)/bin/gate-check.sh}"
GC="$(cd "$(dirname "$GC")" && pwd)/$(basename "$GC")"
[ -r "$(dirname "$GC")/lib/marketplace-catalogue.tsv" ] || { echo "test-fitgap-review: FAIL — no marketplace-catalogue.tsv beside $GC"; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/fitgap.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

# mkproj <name> <layout: root|app> <entry mode|-> [fit-gap lines...]  (no lines = no fit-gap)
mkproj() {
  local d="$WORK/$1" lay="$2" mode="$3" m; shift 3
  mkdir -p "$d/architecture"
  { printf '# PROJECT\n\nToolkit commit: none\n'
    [ "$mode" != - ] && printf 'Entry mode: %s\n' "$mode"
    printf '\n## Current stage\n**Stage P — Kickoff**\n'; } > "$d/PROJECT.md"
  if [ "$#" -gt 0 ]; then
    for r in "$@"; do printf '%s\n' "$r"; done > "$d/architecture/fit-gap.md"
  fi
  m="$d"; [ "$lay" = app ] && m="$d/app"
  mkdir -p "$m"; : > "$m/App.mpr"
  printf '%s\n' "$d"
}
HDR='| Capability | Mendix approach | Verdict | Reason |'
SEP='|---|---|---|---|'
NATIVE='| CRUD grid | Data Grid 2 (native) | **Native** | ships with Atlas |'
LLM='| Triage summary by LLM | Java action calling the chat completions REST endpoint | **Build** | quick to write |'

gc() { env -u MXCLI -u MPR_FILE MXTK_GATE_CACHE_TTL_MIN=0 bash "$GC" --no-html "$@" 2>&1; }
fg_line() { printf '%s\n' "$1" | grep 'Fit-gap:' | head -1; }

echo "== F1: no fit-gap =="
P1="$(mkproj f1 root requirements-driven)"
OUT="$(gc "$P1" build-ready)"; RC=$?
L="$(fg_line "$OUT")"
case "$L" in "  ⚠ Fit-gap: ADVISORY — no architecture/fit-gap.md, so no Marketplace review was made. Write it before Stage 5: one row per capability"*marketplace-catalogue.md*"--waive artifact/fit-gap"*) ok "missing file is a FAIL saying what to write" ;; *) bad "F1: $L" ;; esac
# ADVISORY: item 7 must not raise the fails count. Same project once waived has the same count.
nfail() { printf '%s\n' "$1" | sed -n 's/^BUILD-READY: FAIL — \([0-9][0-9]*\) item.*/\1/p' | head -1; }
N1="$(nfail "$OUT")"; N1="${N1:-0}"
Pw="$(mkproj f1w root requirements-driven)"; gc --waive artifact/fit-gap --reason "advisory comparison" "$Pw" >/dev/null
NW="$(nfail "$(gc "$Pw" build-ready)")"; NW="${NW:-0}"
[ "$N1" = "$NW" ] && ok "missing fit-gap does not change the build-ready fail count ($N1 = $NW with item 7 waived)" || bad "F1: fails $N1 vs waived $NW"
printf '%s\n' "$OUT" | grep -q 'BUILD-READY: FAIL — .*Fit' && bad "F1: summary names the fit-gap" || ok "summary does not count it"

echo "== F2: no verdict column =="
P="$(mkproj f2 root - '| Capability | Mendix approach |' '|---|---|' '| CRUD | Data Grid 2 |')"
L="$(fg_line "$(gc "$P" build-ready)")"
case "$L" in "  ⚠ Fit-gap: ADVISORY — fit-gap.md has no table with a Verdict column"*) ok "no verdict column -> FAIL" ;; *) bad "F2: $L" ;; esac

echo "== F3: unrecognised verdict =="
P="$(mkproj f3 root - "$HDR" "$SEP" "$NATIVE" '| Reporting | tbd | **TBD** | — |')"
L="$(fg_line "$(gc "$P" build-ready)")"
case "$L" in *"no recognised verdict, line 4 (\"tbd\")"*) ok "TBD verdict named with its line" ;; *) bad "F3: $L" ;; esac

echo "== F4: hand-built LLM call =="
P4="$(mkproj f4 root - "$HDR" "$SEP" "$NATIVE" "$LLM")"
L="$(fg_line "$(gc "$P4" build-ready)")"
case "$L" in "  ⚠ Fit-gap: ADVISORY —"*"line 4 (genai-llm: GenAI Commons,"*"Marketplace: <component> not used because"*) ok "catalogued Build without reason -> FAIL naming the component" ;; *) bad "F4: $L" ;; esac

echo "== F5: the same Build with a Marketplace reason =="
P="$(mkproj f5 root - "$HDR" "$SEP" "$NATIVE" '| Triage summary by LLM | Java action | **Build** | Marketplace: GenAI Commons needs Mendix 10.24+, this app is pinned lower |')"
L="$(fg_line "$(gc "$P" build-ready)")"
case "$L" in "  ✓ Fit-gap: 2 row(s) in 1 verdict table(s)"*) ok "$L" ;; *) bad "F5: $L" ;; esac

echo "== F6: Buy the component =="
P="$(mkproj f6 root - "$HDR" "$SEP" "$NATIVE" '| Triage summary by LLM | `GenAICommons` + `MxGenAIConnector` | **Buy** | catalogue genai-llm |')"
L="$(fg_line "$(gc "$P" build-ready)")"
case "$L" in "  ✓ Fit-gap:"*) ok "Buy -> PASS" ;; *) bad "F6: $L" ;; esac

echo "== F7: Build for plain domain logic =="
P="$(mkproj f7 root - "$HDR" "$SEP" "$NATIVE" '| Fee calculation | microflow over Case | **Build (new)** | domain rule |')"
L="$(fg_line "$(gc "$P" build-ready)")"
case "$L" in "  ✓ Fit-gap:"*) ok "uncatalogued Build -> PASS" ;; *) bad "F7: $L" ;; esac

echo "== F8: Build that names the component =="
P="$(mkproj f8 root - "$HDR" "$SEP" '| Monthly statement PDF | HTML page printed by the browser | **Build** | Document Generation needs a headless browser service we cannot host |')"
L="$(fg_line "$(gc "$P" build-ready)")"
case "$L" in "  ✓ Fit-gap:"*) ok "component named -> PASS" ;; *) bad "F8: $L" ;; esac

echo "== F9: waiver =="
gc --waive artifact/fit-gap --reason "architecture lives in the client's own repository" "$P1" >/dev/null
L="$(fg_line "$(gc "$P1" build-ready)")"
case "$L" in "  ✓ Fit-gap: WAIVED — architecture lives"*) ok "waived" ;; *) bad "F9: $L" ;; esac

echo "== F10: adopted above Stage 3 =="
P="$(mkproj f10 root -)"
gc --adopt 5 --reason "joined at the build" "$P" >/dev/null
L="$(fg_line "$(gc "$P" build-ready)")"
case "$L" in "  ✓ Fit-gap: not owed — project joined the toolkit at stage 5") ok "$L" ;; *) bad "F10: $L" ;; esac

echo "== F11: greenfield =="
P="$(mkproj f11a root greenfield)"
L="$(fg_line "$(gc "$P" build-ready)")"
case "$L" in "  ✓ Fit-gap: not owed — greenfield entry mode"*) ok "greenfield, no fit-gap: not owed" ;; *) bad "F11a: $L" ;; esac
P="$(mkproj f11b root greenfield "$HDR" "$SEP" "$LLM")"
L="$(fg_line "$(gc "$P" build-ready)")"
case "$L" in "  ⚠ Fit-gap: ADVISORY —"*genai-llm*) ok "greenfield with a fit-gap: still read" ;; *) bad "F11b: $L" ;; esac

echo "== F12: two-tree layout =="
P="$(mkproj f12 app - "$HDR" "$SEP" "$NATIVE" "$LLM")"
L="$(fg_line "$(gc "$P" build-ready)")"
case "$L" in "  ⚠ Fit-gap: ADVISORY —"*"line 4 (genai-llm"*) ok "app/App.mpr: same verdict" ;; *) bad "F12: $L" ;; esac

echo "== F14c: Build row naming only the word Marketplace (no component) =="
P="$(mkproj f14c root - "$HDR" "$SEP" '| Gauge on the dashboard | custom chart widget | **Build** | Marketplace: not used because it has no dial gauge |')"
L="$(fg_line "$(gc "$P" build-ready)")"
case "$L" in "  ✓ Fit-gap:"*) ok "the word Marketplace alone is the reason" ;; *) bad "F14c: $L" ;; esac

echo "== F15: Build type: poc =="
P="$(mkproj f15 root -)"; printf '\nBuild type: poc\n' >> "$P/PROJECT.md"
L="$(fg_line "$(gc "$P" build-ready)")"
case "$L" in "  ✓ Fit-gap: not owed — Build type: poc"*) ok "poc, no fit-gap: not owed" ;; *) bad "F15a: $L" ;; esac
P="$(mkproj f15b root - "$HDR" "$SEP" "$LLM")"; printf '\nBuild type: poc\n' >> "$P/PROJECT.md"
L="$(fg_line "$(gc "$P" build-ready)")"
case "$L" in "  ⚠ Fit-gap: ADVISORY —"*genai-llm*) ok "poc WITH a fit-gap: still read" ;; *) bad "F15b: $L" ;; esac
P="$(mkproj f15c root -)"; printf '\nBuild type: full\n' >> "$P/PROJECT.md"
L="$(fg_line "$(gc "$P" build-ready)")"
case "$L" in "  ⚠ Fit-gap: ADVISORY — no architecture"*) ok "Build type: full is not exempt" ;; *) bad "F15c: $L" ;; esac

echo "== F13: placement, and no stage verdict changes =="
OUT="$(gc "$P4" build-ready)"
printf '%s\n' "$OUT" | awk '/^  [^ ]+ Marketplace:/{m=NR} /^  [^ ]+ Fit-gap:/{f=NR} END{exit !(m && f && f > m)}' && ok "printed after the Marketplace item" || bad "F13 order: $(printf '%s\n' "$OUT" | grep -nE 'Marketplace:|Fit-gap:')"
OUT="$(gc "$P4" 5)"
printf '%s\n' "$OUT" | grep -q 'Fit-gap:' && bad "F13: stage 5 run printed a Fit-gap line" || ok "stage 5 run does not evaluate it"

echo "== F14: accidental keyword in a Build row =="
P="$(mkproj f14 root - "$HDR" "$SEP" '| Gauge on the dashboard | custom chart widget | **Build** | needs a dial, not a bar |')"
L="$(fg_line "$(gc "$P" build-ready)")"
case "$L" in "  ⚠ Fit-gap: ADVISORY —"*"(charts:"*) ok "short keyword in a Build row asks for the reason (FAIL)" ;; *) bad "F14a: $L" ;; esac
P="$(mkproj f14b root - "$HDR" "$SEP" '| Gauge on the dashboard | custom chart widget | **Build** | Marketplace: Charts not used because it has no dial gauge |')"
L="$(fg_line "$(gc "$P" build-ready)")"
case "$L" in "  ✓ Fit-gap:"*) ok "the same row with a one-sentence reason passes" ;; *) bad "F14b: $L" ;; esac

echo ""
echo "test-fitgap-review: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
