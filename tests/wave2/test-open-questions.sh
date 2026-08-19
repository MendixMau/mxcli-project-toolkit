#!/usr/bin/env bash
# Fixture for bin/open-questions.sh + its gate-check.sh integration.
#
# Takes the SUBJECT UNDER TEST as $1 (a path to open-questions.sh), matching the other
# wave2 fixtures, so the same suite can be pointed at a `git show HEAD:` baseline.
# gate-check.sh is located next to the subject.
#
# Every case here is a case something is supposed to FAIL on. A guard that has only been
# run against inputs it should pass is not a guard.

set -uo pipefail

SUT="${1:-}"
if [ -z "$SUT" ]; then
  SUT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/bin/open-questions.sh"
fi
if [ ! -f "$SUT" ]; then
  echo "SKIP: subject not found at $SUT (pre-change baseline has no collector)"
  echo "SCORE: 0/0 — nothing to test"
  exit 0
fi
GATE="$(dirname "$SUT")/gate-check.sh"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ -n "${2:-}" ] && echo "         got: $2"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/oqtest.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# Scaffolding: a minimal project with a BRD dir, an sme file, and a decision register.
# ---------------------------------------------------------------------------
mkproj() { # mkproj <name>  -> echoes the project dir
  local d="$TMP/$1"
  mkdir -p "$d/analysis/knowledge-base/brd" "$d/analysis/knowledge-base/reports"
  # Stage 2 must pass on its OWN evidence, or it FAILs before the open-questions check is
  # ever reached — the check deliberately runs last, so a project that is failing for other
  # reasons keeps its own verdict. Without this the gate assertions below test nothing.
  printf '# validation\n\n## Stop condition\n\nClean\n' > "$d/analysis/knowledge-base/reports/validation-report.md"
  cat > "$d/PROJECT.md" <<'EOF'
# Test project
Toolkit commit: deadbeef
## Decisions
| Stage | Decision | Status | Notes |
|---|---|---|---|
| 2 | test | CONFIRMED | - |
EOF
  echo "$d"
}
brd() { # brd <projdir> <file> <json-array-of-openQuestions>
  printf '{"id":"F001","title":"t","openQuestions":%s}\n' "$3" > "$1/analysis/knowledge-base/brd/$2"
}
state_of() { # state_of <projdir> <question-id>
  "$SUT" "$1" --json 2>/dev/null | jq -r --arg i "$2" '.questions[] | select(.id==$i) | .state'
}
blocking_of() { "$SUT" "$1" --json 2>/dev/null | jq -r '.blocking'; }

echo "== bin/open-questions.sh =="

# --- 1. never raised blocks -------------------------------------------------
P="$(mkproj never-raised)"
brd "$P" "F001.brd.json" '[{"id":"Q1","question":"Is the approval engine in scope?","status":"Open"}]'
s="$(state_of "$P" Q1)"
[ "$s" = "UNRAISED" ] && ok "a bare Open question is UNRAISED" || bad "a bare Open question should be UNRAISED" "$s"
[ "$(blocking_of "$P")" = "1" ] && ok "UNRAISED counts as blocking" || bad "UNRAISED must block" "$(blocking_of "$P")"
"$SUT" "$P" >/dev/null 2>&1; [ $? -eq 1 ] && ok "collector exits 1 on blocking questions" || bad "collector must exit 1 on blocking questions"

# --- 2. raised-and-answered does NOT block ---------------------------------
P="$(mkproj answered)"
brd "$P" "F001.brd.json" '[{"id":"Q1","question":"In scope?","status":"Resolved","raisedAtGate":"Stage 2 gate 2026-08-12","answer":"Yes, build it."}]'
s="$(state_of "$P" Q1)"
[ "$s" = "ANSWERED" ] && ok "resolved + answer is ANSWERED" || bad "resolved + answer should be ANSWERED" "$s"
[ "$(blocking_of "$P")" = "0" ] && ok "ANSWERED does not block" || bad "ANSWERED must not block" "$(blocking_of "$P")"

# --- 3. raised-then-assumed-WITH-CONSENT does NOT block --------------------
P="$(mkproj assumed-consent)"
brd "$P" "F001.brd.json" '[{"id":"Q1","question":"Hardcode or engine?","status":"ASSUMED","assumption":"hardcode","raisedAtGate":"Stage 2 gate","consentBy":"Maurits Visser","consentAt":"2026-08-12"}]'
s="$(state_of "$P" Q1)"
[ "$s" = "ASSUMED" ] && ok "ASSUMED + consentBy + consentAt is ASSUMED" || bad "consented assumption should be ASSUMED" "$s"
[ "$(blocking_of "$P")" = "0" ] && ok "ASSUMED-with-consent does not block (the whole ruling)" || bad "consented assumption must not block" "$(blocking_of "$P")"

# --- 4. THE DEFECT: assumed WITHOUT consent blocks -------------------------
P="$(mkproj assumed-no-consent)"
brd "$P" "F001.brd.json" '[{"id":"Q1","question":"Hardcode or engine?","status":"ASSUMED drafting position (a), hardcode — NOT a settled product decision."}]'
s="$(state_of "$P" Q1)"
[ "$s" = "UNRAISED" ] && ok "ASSUMED with no consent recorded is UNRAISED, not ASSUMED" || bad "unconsented assumption must not read as ASSUMED" "$s"
[ "$(blocking_of "$P")" = "1" ] && ok "unconsented assumption blocks" || bad "unconsented assumption must block" "$(blocking_of "$P")"
out="$("$SUT" "$P" 2>/dev/null)"
printf '%s' "$out" | grep -q "I ASSUMED (confirm or overturn): drafting position (a), hardcode" \
  && ok "the drafting position is surfaced so the user can overturn it" || bad "drafting position not surfaced in the batch"

# --- 5. an UNRECOGNISED status blocks rather than passes -------------------
P="$(mkproj unrecognised)"
brd "$P" "F001.brd.json" '[{"id":"Q1","question":"What is GBID?","status":"parked pending vendor call"},{"id":"Q2","question":"Second?","status":"Resolved"}]'
s="$(state_of "$P" Q1)"
[ "$s" = "UNRECOGNISED" ] && ok "an unmapped free-text status is UNRECOGNISED" || bad "unmapped status should be UNRECOGNISED" "$s"
s2="$(state_of "$P" Q2)"
[ "$s2" = "UNRECOGNISED" ] && ok "'Resolved' with NO recorded answer is UNRECOGNISED, not silently resolved" || bad "answerless Resolved should be UNRECOGNISED" "$s2"
[ "$(blocking_of "$P")" = "2" ] && ok "UNRECOGNISED counts as NOT done and blocks" || bad "UNRECOGNISED must block" "$(blocking_of "$P")"

# --- 6. zero BRDs => "nothing examined", not clean -------------------------
P="$TMP/empty"; mkdir -p "$P"
out="$("$SUT" "$P" 2>&1)"; rc=$?
[ "$rc" -eq 3 ] && ok "empty project exits 3 (nothing examined), not 0" || bad "empty project must not exit 0/1" "rc=$rc"
printf '%s' "$out" | grep -q "NOTHING EXAMINED" && ok "empty project says NOTHING EXAMINED in words" || bad "no NOTHING EXAMINED banner"
printf '%s' "$out" | grep -q "not a clean result" && ok "empty project explicitly denies being clean" || bad "empty project reads as clean"
j="$("$SUT" "$P" --json 2>/dev/null)"
[ "$(printf '%s' "$j" | jq -r '.examined.nothingExamined')" = "true" ] && ok "--json flags nothingExamined" || bad "--json must flag nothingExamined"

# --- 7. every report says what it examined ---------------------------------
P="$(mkproj examined-line)"
brd "$P" "F001.brd.json" '[{"id":"Q1","question":"x","status":"Open"}]'
out="$("$SUT" "$P" 2>/dev/null)"
printf '%s' "$out" | grep -qE "^Examined: 1 BRD file\(s\), 0 sme-questions file\(s\)" \
  && ok "the report names what it examined" || bad "report does not state what it examined"

# --- 8. the sme-questions.md / BRD duplicate is counted once ---------------
P="$(mkproj dedup)"
brd "$P" "F001.brd.json" '[{"id":"Q3","question":"Number-circle pairing meaning?","status":"Open — routed to sme-questions.md F1, not duplicated here"}]'
cat > "$P/analysis/sme-questions.md" <<'EOF'
# SME questions

| # | Question | Evidence | Options (not a recommendation) |
|---|---|---|---|
| F1 | What is the business meaning of the 85xxxx/82xxxx pairing? | source | (a) ask (b) model it |
EOF
n="$("$SUT" "$P" --json | jq -r '.questions | length')"
[ "$n" = "1" ] && ok "the cross-referenced pair collapses to one question" || bad "duplicate not collapsed" "count=$n"
d="$("$SUT" "$P" --json | jq -r '.examined.duplicatesCollapsed')"
[ "$d" = "1" ] && ok "the collapse is reported, not silent" || bad "duplicatesCollapsed not reported" "$d"
out="$("$SUT" "$P" 2>/dev/null)"
printf '%s' "$out" | grep -q "sme-questions.md" && ok "the surviving row cites the human-readable source" || bad "survivor does not cite sme-questions.md"

# --- 9. a markdown table with no verdict column is UNRAISED (rule 10) ------
P="$(mkproj md-no-verdict)"
cat > "$P/analysis/sme-questions.md" <<'EOF'
| # | Question | Evidence | Options (not a recommendation) |
|---|---|---|---|
| H2 | Per-station roles or collapse into the 3-tier model? | src | (a) collapse (b) per-station |
EOF
brd "$P" "F001.brd.json" '[]'
s="$(state_of "$P" H2)"
[ "$s" = "UNRAISED" ] && ok "options-only markdown row is UNRAISED" || bad "options-only row should be UNRAISED" "$s"

# --- 10. a markdown Decision column that IS filled reads as ANSWERED -------
P="$(mkproj md-decision)"
cat > "$P/analysis/sme-questions.md" <<'EOF'
| # | Question | Decision | Rationale |
|---|---|---|---|
| A1 | Three fields or fewer? | **Two attributes: Designation + Name** | filter searches one |
| A9 | Something undecided? |  | pending |
EOF
brd "$P" "F001.brd.json" '[]'
[ "$(state_of "$P" A1)" = "ANSWERED" ] && ok "filled Decision column is ANSWERED" || bad "filled Decision should be ANSWERED" "$(state_of "$P" A1)"
[ "$(state_of "$P" A9)" = "UNRAISED" ] && ok "blank Decision column is UNRAISED" || bad "blank Decision should be UNRAISED" "$(state_of "$P" A9)"

# --- 11. MOOT is non-blocking but only when the text says so up front ------
P="$(mkproj moot)"
brd "$P" "F001.brd.json" '[{"id":"Q1","question":"a","status":"Open, moot for this BRD"},{"id":"Q2","question":"b","status":"OPEN. Same as W4 — moot in this scope following W1."}]'
[ "$(state_of "$P" Q1)" = "MOOT" ] && ok "'Open, moot for this BRD' is MOOT" || bad "should be MOOT" "$(state_of "$P" Q1)"
[ "$(state_of "$P" Q2)" = "UNRAISED" ] && ok "'moot' buried mid-sentence does NOT excuse the question" || bad "buried moot must not pass" "$(state_of "$P" Q2)"

# --- 11b. "Not relevant" is a real answer, not UNRECOGNISED -----------------
P="$(mkproj not-relevant)"
brd "$P" "F001.brd.json" '[{"id":"Q1","question":"a","status":"Not relevant — legacy-only, we no longer support that flow."},{"id":"Q2","question":"b","status":"Irrelevant"}]'
[ "$(state_of "$P" Q1)" = "MOOT" ] && ok "'Not relevant — <reason>' is MOOT" || bad "should be MOOT" "$(state_of "$P" Q1)"
[ "$(blocking_of "$P")" = "0" ] && ok "a 'not relevant' answer does not block" || bad "'not relevant' must not block" "$(blocking_of "$P")"
[ "$(state_of "$P" Q2)" = "MOOT" ] && ok "bare 'Irrelevant' is still MOOT (no reason required to pass)" || bad "should be MOOT" "$(state_of "$P" Q2)"

# --- 12. --stage filters, and earlier-stage debt carries forward -----------
P="$(mkproj staged)"
brd "$P" "F001.brd.json" '[{"id":"Q1","question":"a","status":"Open"},{"id":"Q2","question":"b","status":"Open — deferred to Stage 4 architecture"}]'
[ "$("$SUT" "$P" --stage 2 --json | jq -r '.blocking')" = "1" ] && ok "--stage 2 sees only the stage-2 question" || bad "--stage 2 filter wrong"
[ "$("$SUT" "$P" --stage 4 --json | jq -r '.blocking')" = "2" ] && ok "--stage 4 still sees stage-2 debt (carries forward)" || bad "--stage 4 must include earlier debt"
"$SUT" "$P" --stage 9 >/dev/null 2>&1; [ $? -eq 2 ] && ok "a bad stage arg is rejected, not silently ignored" || bad "bad stage arg not rejected"

# --- 13. the mapping table is printable for audit --------------------------
"$SUT" --mapping-table | grep -q "UNRECOGNISED" && ok "--mapping-table prints the audit table" || bad "--mapping-table missing"

# ---------------------------------------------------------------------------
echo ""
echo "== gate-check.sh integration =="
if [ ! -x "$GATE" ]; then
  bad "gate-check.sh not found next to the subject at $GATE"
else
  # A stage with an unraised question must FAIL, naming the count and the command.
  P="$(mkproj gate-block)"
  brd "$P" "F001.brd.json" '[{"id":"Q1","question":"Is the ~20-station engine in scope?","status":"Open"}]'
  out="$(MXTK_STRICT_PROTOCOL=0 "$GATE" --no-html "$P" 2 2>&1)"; rc=$?
  [ "$rc" -ne 0 ] && ok "stage 2 gate exits non-zero with an unraised question" || bad "gate PASSED with an unraised question" "rc=$rc"
  printf '%s' "$out" | grep -q "never been raised" && ok "the failure says the questions were never raised" || bad "failure text does not name the cause"
  printf '%s' "$out" | grep -q "1 question(s)" && ok "the failure names the count" || bad "failure does not name the count"
  printf '%s' "$out" | grep -q "open-questions.sh" && ok "the failure names the command to see them" || bad "failure does not name the command"

  # ASSUMED-with-consent must NOT block the same gate.
  P="$(mkproj gate-consent)"
  brd "$P" "F001.brd.json" '[{"id":"Q1","question":"Is the engine in scope?","status":"ASSUMED","assumption":"out of scope for the POC","raisedAtGate":"Stage 2","consentBy":"Maurits Visser","consentAt":"2026-08-12"}]'
  out="$(MXTK_STRICT_PROTOCOL=0 "$GATE" --no-html "$P" 2 2>&1)"; rc=$?
  printf '%s' "$out" | grep -q "never been raised" \
    && bad "consented assumption blocked the gate — this is the ruling being violated" \
    || ok "consented assumption does not block the gate"
  # And the gate must actually PASS, not merely fail for a different reason — otherwise the
  # assertion above is satisfied by any unrelated failure and proves nothing.
  [ "$rc" -eq 0 ] && ok "that gate genuinely passes (exit 0), so the assertion above is real" \
    || bad "gate did not pass; the consented-assumption assertion is vacuous" "rc=$rc; $(printf '%s' "$out" | tail -2)"

  # UNRECOGNISED must block, not pass.
  P="$(mkproj gate-unrecognised)"
  brd "$P" "F001.brd.json" '[{"id":"Q1","question":"x","status":"parked pending vendor call"}]'
  out="$(MXTK_STRICT_PROTOCOL=0 "$GATE" --no-html "$P" 2 2>&1)"; rc=$?
  [ "$rc" -ne 0 ] && ok "an unrecognised status blocks the gate" || bad "unrecognised status PASSED the gate" "rc=$rc"

  # Nothing examined must not read as a pass.
  P="$TMP/gate-empty"; mkdir -p "$P"; printf '# p\nToolkit commit: x\n' > "$P/PROJECT.md"
  out="$(MXTK_STRICT_PROTOCOL=0 "$GATE" --no-html "$P" 2 2>&1)"; rc=$?
  [ "$rc" -ne 0 ] && ok "a project with nothing examined does not pass its gate" || bad "empty project PASSED" "rc=$rc"
  printf '%s' "$out" | grep -q "NOTHING EXAMINED\|Open questions" && ok "the empty-project report mentions the open-questions check" || bad "no open-questions row in the report"

  # The informational run must always state what it examined.
  P="$(mkproj gate-info)"
  brd "$P" "F001.brd.json" '[{"id":"Q1","question":"x","status":"Open"}]'
  out="$(MXTK_STRICT_PROTOCOL=0 "$GATE" --no-html "$P" 2>&1)"
  printf '%s' "$out" | grep -q "Open questions (raised?):.*examined 1 BRD file" \
    && ok "informational run reports the open-questions row with what it examined" || bad "informational row missing or without an examined count"
fi

echo ""
TOTAL=$((PASS+FAIL))
echo "SCORE: $PASS/$TOTAL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
