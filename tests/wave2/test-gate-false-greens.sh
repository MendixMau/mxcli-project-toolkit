#!/usr/bin/env bash
# test-gate-false-greens.sh — gate verdicts that read green (or red) against what the files say:
#   G1 #638  Stage 1 reads extraction-quality*.json: below threshold / self-graded / unparseable FAIL
#   G2 #640  brd-report on the java-angular pipeline's own BRDs: enumerations and a backend-only
#            source's empty pages/useCases are not FAULTs; a remaining FAULT is named at Stage 2
#   G3 #641  coverage-check: a buildable wildcard over a whole multi-element section is SECTION-WIDE
#   G4 #642  the split ledger form (modules/<M>/coverage-ledger/<BRD>.md) discharges the artifact row
#   G5 #635  no inventory at all is PENDING, not FAIL — and still blocks Stage 1
#   G6 #636  an auto-mode triage sign-off: PASS only under Interview mode: auto (listed, Stage 6
#            FAILs until confirmed — the #624 rule); FAIL in any other mode
#
# GOLDEN INPUT (G2, G3): tests/wave2/fixtures/java-angular-backend-only/ is captured, not written.
# pipelines/java-angular `node run.js 2 && node run.js 3` over the public openwms-java-microservices
# repos (7 Spring Boot sources, no Angular), 2026-11-05: 16 BRDs, 0 screens. barcode.brd.json
# (1 enumeration, 1 entity, 3 microflows) and api.brd.json (4 enumerations only) are two of the 16,
# re-serialised with `jq -c` (content unchanged); screens.json is that run's, verbatim.
#
# Positive control: run against origin/master's gate-check.sh — G1a/G1c/G1d/G1f/G1g, G2a-G2c, G3a,
# G4, G5a and G6a/G6b fail there.
#
# usage: bash tests/wave2/test-gate-false-greens.sh /path/to/bin/gate-check.sh
set -uo pipefail

GATE="${1:?usage: test-gate-false-greens.sh /path/to/gate-check.sh}"
TK="$(cd "$(dirname "$GATE")/.." && pwd)"
GOLD="$(cd "$(dirname "$0")" && pwd)/fixtures/java-angular-backend-only"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/false-greens.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n       %s\n' "$1" "${2:-}"; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "missing '$3' in: $2" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1" "unexpected '$3' in: $2" ;; *) ok "$1" ;; esac; }

# analysis/src/knowledge-base with the two captured BRDs, a clean validation report, a report page.
mkproj() {
  local d="$WORK/$1" k="$WORK/$1/analysis/src/knowledge-base"
  mkdir -p "$k/brd" "$k/reports"
  printf '| Stage | Decision | Status | Notes |\n|---|---|---|---|\n' > "$d/PROJECT.md"
  cp "$GOLD/barcode.brd.json" "$GOLD/api.brd.json" "$k/brd/"
  cp "$GOLD/screens.json" "$k/screens.json"
  printf '# Validation\n\n## Stop condition\n\nClean\n' > "$k/reports/validation-report.md"
  printf '<html>report</html>\n' > "$k/extraction-report.html"
  echo "$d"
}
line() { "$GATE" --no-html "$1" "$2" 2>&1 | grep "^${3:-Stage $2 }" | head -1; }
q() { printf '{"project":"src","overallScore":%s,"threshold":95,"passed":%s%s,"dimensions":{"endpoints":{"score":%s,"found":44,"expected":70,"gaps":[]}}}\n' "$1" "$2" "${3:-}" "$1"; }

echo "== G1 #638: Stage 1 reads the validator's score file =="
P="$(mkproj g1)"
V="$(line "$P" 1)"
has "G1  no score file: PASS says quality was NOT scored" "$V" "extraction quality NOT scored"
has "G1  no 'Extraction scope:' decision is named, not implied" "$V" "no 'Extraction scope:' decision"
q 62.5 false > "$P/analysis/src/extraction-quality.json"
V="$(line "$P" 1)"
has "G1a 62.5 / passed=false: FAIL with the file's numbers" "$V" "FAIL"
has "G1a   and quotes them" "$V" "scores 62.5 / threshold 95"
RC=0; "$GATE" --no-html "$P" 1 >/dev/null 2>&1 || RC=$?
[ "$RC" = 0 ] && ok "G1  Stage 1 stays advisory at the exit code (0)" || bad "G1  exit code" "rc=$RC"
printf '\nWaived artifact extraction-quality: client accepts the endpoint gap for slice 1\n' >> "$P/PROJECT.md"
V="$(line "$P" 1)"
has "G1b a recorded waiver PASSes and carries the reason" "$V" "below its gate but waived — client accepts"
P="$(mkproj g1c)"; q 99 true ',"selfGraded":true' > "$P/analysis/src/extraction-quality.json"
V="$(line "$P" 1)"
has "G1c a self-graded pass is PENDING (the skill: the verdict stays open)" "$V" "Stage 1 (Analysis): PENDING"
has "G1c   and says why" "$V" "self-graded pass"
P="$(mkproj g1d)"; printf '{"overallScore": 9' > "$P/analysis/src/extraction-quality.json"
has "G1d an unparseable score file FAILs" "$(line "$P" 1)" "will not parse"
P="$(mkproj g1f)"
printf '{"overallScore":97,"threshold":95,"passed":true,"dimensions":{"endpoints":{"score":100,"found":70,"expected":70},"timers":{"score":100,"found":0,"expected":0}}}\n' > "$P/analysis/src/extraction-quality.json"
V="$(line "$P" 1)"
has "G1f passed=true 97 with an unconfirmed 0/0 dimension FAILs" "$V" "0 found / 0 expected on timers"
printf '{"overallScore":97,"threshold":95,"passed":true,"dimensions":{"endpoints":{"score":100,"found":70,"expected":70},"timers":{"score":100,"found":0,"expected":0}},"confirmedZeros":[{"dimension":"timers","methods":["grep","parser"]}]}\n' > "$P/analysis/src/extraction-quality.json"
case "$(line "$P" 1)" in *PASS*) ok "G1f   the same zero in confirmedZeros PASSes" ;; *) bad "G1f confirmed zero" "$(line "$P" 1)" ;; esac
printf '{"overallScore":97,"threshold":95,"passed":true}\n' > "$P/analysis/src/extraction-quality.json"
has "G1g no dimensions object FAILs" "$(line "$P" 1)" "has no \`dimensions\` object"
P="$(mkproj g1e)"; q 97 true > "$P/analysis/src/knowledge-base/extraction-quality.json"
printf '| 1 | Extraction scope: tms and common only | CONFIRMED | chat |\n' >> "$P/PROJECT.md"
V="$(line "$P" 1)"
has "G1e 97 / passed=true inside the KB: PASS with the score" "$V" "extraction quality analysis/src/knowledge-base/extraction-quality.json 97 / threshold 95"
hasnt "G1e   and no scope note once the decision exists" "$V" "Extraction scope:' decision"

echo "== G2 #640: the pipeline's own BRDs (captured) =="
P="$(mkproj g2)"
OUT="$(bash "$TK/bin/brd-report.sh" "$P" --html "$WORK/g2.html" 2>&1)"
has "G2a enumerations are not read as entities missing attributes" "$OUT" "unreadable keys: 0"
has "G2b 0 screens in the whole source: pages are 'none in this source'" "$(cat "$WORK/g2.html")" "none in this source"
hasnt "G2b   and no pages FAULT" "$OUT" "FAULT  pages"
hasnt "G2b   and no useCases FAULT" "$OUT" "FAULT  useCases"
has "G2  an enum-only capability's empty microflows stays a FAULT, worded 'empty'" "$OUT" "FAULT  microflows: empty"
V="$(line "$P" 2)"
has "G2c Stage 2 PASS names the remaining FAULT instead of hiding it" "$V" "brd-report FAULT: 1 owed section(s) left empty, e.g. api.brd.json: microflows"
printf '[{"name":"Login","type":"screen"}]\n' > "$P/analysis/src/knowledge-base/screens.json"
OUT="$(bash "$TK/bin/brd-report.sh" "$P" --html "$WORK/g2.html" 2>&1)"
has "G2  a source WITH screens keeps the pages FAULT" "$OUT" "FAULT  pages: empty"

echo "== G3 #641: section-wide buildable wildcard =="
B="$WORK/g2/analysis/src/knowledge-base/brd/barcode.brd.json"
cnt() { jq -r 'paths as $p | select(getpath($p) | type | IN("object","array") | not) | "/" + ($p | map(tostring) | join("/"))' "$B" | grep -c "^$1"; }
ledger() { # ledger <buildable pointer cells...>; every other leaf goes NON-BUILDABLE
  printf '| pointer | type | title | slice | writeMode | acceptance | status |\n|---|---|---|---|---|---|---|\n'
  for c in "$@"; do printf '| `%s` | build | r | 1 | create | r | todo |\n' "$c"; done
  printf '\n| pointer | category | reason |\n|---|---|---|\n'
  for k in modules appType summary; do printf '| `/%s/*` (%s) | provenance | metadata |\n' "$k" "$(cnt "/$k/")"; done
  printf '| `/generatedAt` | provenance | metadata |\n| `/confidence` | provenance | metadata |\n'
}
ledger "/domainEntities/* ($(cnt /domainEntities/))" "/microflows/* ($(cnt /microflows/))" > "$WORK/wide.md"
OUT="$(bash "$TK/bin/coverage-check.sh" "$B" "$WORK/wide.md" 2>&1)"; RC=$?
has "G3a /microflows/* over 3 microflows is SECTION-WIDE" "$OUT" "/microflows/* (3 elements in one claim)"
has "G3a   and so is /domainEntities/* over 2" "$OUT" "SECTION-WIDE:  2"
[ "$RC" = 1 ] && ok "G3a   exit 1" || bad "G3a exit" "rc=$RC"
ledger "/domainEntities/0/* ($(cnt /domainEntities/0/))" "/domainEntities/1/* ($(cnt /domainEntities/1/))" \
  "/microflows/0/* ($(cnt /microflows/0/))" "/microflows/1/* ($(cnt /microflows/1/))" "/microflows/2/* ($(cnt /microflows/2/))" > "$WORK/elem.md"
OUT="$(bash "$TK/bin/coverage-check.sh" "$B" "$WORK/elem.md" 2>&1)"; RC=$?
[ "$RC" = 0 ] && ok "G3b one element per row: clean (exit 0)" || bad "G3b element claims" "$OUT"

echo "== G4 #642: split ledger form discharges the artifact row =="
P="$(mkproj g4)"; mkdir -p "$P/architecture/modules/Barcode/coverage-ledger"
cp "$WORK/elem.md" "$P/architecture/modules/Barcode/coverage-ledger/barcode.md"
V="$("$GATE" --no-html "$P" 4 2>&1 | grep -m1 '^Artifact coverage-ledger')"
has "G4  Artifact coverage-ledger PRESENT for modules/<M>/coverage-ledger/<BRD>.md" "$V" "PRESENT"

echo "== G5 #635: files on disk, no inventory =="
P="$(mkproj g5)"; mkdir -p "$P/sources"; printf 'spec\n' > "$P/sources/req.md"
V="$(line "$P" 0 'Source ledger')"
has "G5a no inventory yet: ledger PENDING, not FAIL" "$V" "Source ledger (every file consumed?): PENDING"
has "G5a no rubric yet: sufficiency PENDING, not FAIL" "$(line "$P" 0 'Source sufficiency')" "Source sufficiency (assessed?): PENDING"
RC=0; "$GATE" --no-html "$P" 1 >/dev/null 2>&1 || RC=$?
[ "$RC" = 1 ] && ok "G5b and it still BLOCKS Stage 1 (exit 1)" || bad "G5b Stage 1 block" "rc=$RC"

echo "== G6 #636: an auto-mode Stage 0 sign-off follows the #624 rule =="
P="$(mkproj g6)"
printf '# Triage\n\n## Sign-off\n\nConfirmed by: auto-mode (unattended field run) on 2026-11-05T22:00Z — ASSUMED, no human saw this\n' > "$P/triage.md"
# Stage 6 is waived so its own check reads PASS-equivalent; #624: a waiver does not excuse it.
printf '\nInterview mode: auto\n\nWaived stage 6: fixture — the release check is what is under test\n' >> "$P/PROJECT.md"
O="$("$GATE" --no-html "$P" 2>&1)"
has "G6a auto mode: Stage 0 PASSes and says ASSUMED" "$(printf '%s\n' "$O" | grep -m1 '^Stage 0 ')" "ASSUMED; a human confirms it before release"
has "G6a   listed in the confirm-before-release line" "$O" "triage.md (Stage 0 sign-off)"
has "G6a   and Stage 6 FAILs until a person confirms" "$(printf '%s\n' "$O" | grep -m1 '^Stage 6 ')" "FAIL"
sed -i.bak 's/^Interview mode: auto$/Interview mode: steering/' "$P/PROJECT.md"; rm -f "$P/PROJECT.md.bak"
has "G6b any other mode: the same sign-off FAILs Stage 0" "$(line "$P" 0)" "passes only under Interview mode: auto"

echo ""
echo "test-gate-false-greens.sh: $PASS ok, $FAIL FAIL"
[ "$FAIL" -eq 0 ]
