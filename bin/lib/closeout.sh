#!/usr/bin/env bash
# closeout.sh — the stage close-out / next-stage-open block, printed for the person in the chat.
#
# WHY THIS EXISTS (2026-09-02). At the Stage 2, 3 and 4 transitions the toolkit was strong at
# ASKING (the 2+1 checkpoint questions, the brainstorms, the hard stop) and at PROVING (the
# gate-check paste, the live-checklist repost) — and silent about CLOSING: nobody was told, in
# one message, what the stage produced, what was decided in it, what is still open going into
# the next one, what the next stage will do and how, and which skills govern it. Measured on a
# real register (TFC-TCXGraphPOC): 77 CONFIRMED/ASSUMED rows and no reader-facing recap at any
# gate; an open-questions table mixing ANSWERED, Deferred and PARKED rows so "what is still
# open entering Stage 5" could not be read off it. The checkpoint format's "What we found"
# digest is built to drive the next questions, not to inventory the stage.
#
# WHAT IT IS: an emitter. It reads exactly the records the gates already read — the decision
# register, bin/lib/artifact-manifest.tsv, bin/lib/skill-routing.tsv — and prints one
# chat-ready markdown block. It decides NOTHING: the verdict line is gate-check's own, quoted;
# a decision is whatever the register says it is; an open question is "open" by the same
# controlled-vocabulary stance bin/open-questions.sh takes (a status whose first word is not
# in the closed set is reported as carried forward, with that word shown, so a register that
# spells "done" nine ways gets its nine spellings back instead of a clean sheet).
#
# WHAT IT IS NOT: a second register, a second routing table, or a stakeholder report. The
# audience is the person in the chat (decided 2026-09-02 — a rendered docs/ report was offered
# and declined). Everything it prints has a file it was read from, named in the heading.
#
# Wired from bin/gate-check.sh:
#     bin/gate-check.sh --closeout <project-dir> <stage>
# which runs the full evaluation, keeps its verdict for the "Gate" line, and prints ONLY this
# block — so the agent can paste it as-is (conversion-runbook.md §1b rule 7). Also runnable
# directly, in which case it shells out to gate-check.sh for the verdict line:
#     bin/lib/closeout.sh <project-dir> <stage>
#
# The static per-stage lines (purpose, approach, primary skill groups) are TOOLKIT knowledge —
# one sentence each, citing the owning skill — not a cache of any project's environment
# (CLAUDE.md authoring rule 5). If a stage's purpose changes in conversion-runbook.md §2, the
# line here changes in the same commit.

set -uo pipefail

_CO_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=artifact-check.sh
. "$_CO_LIB_DIR/artifact-check.sh"
ROUTING_TSV="${ROUTING_TSV:-$_CO_LIB_DIR/skill-routing.tsv}"

_co_title() {
  case "$1" in
    P|p) echo "Kickoff" ;;            0) echo "Triage & Scope" ;;
    1) echo "Analysis" ;;             2) echo "Requirements (BRDs)" ;;
    3) echo "Architecture & Design" ;; 4) echo "Build Plan" ;;
    5) echo "Build" ;;                6) echo "Test" ;;
    7) echo "Cutover" ;;              *) echo "?" ;;
  esac
}
# ✋ stages per conversion-runbook.md §2 — the ones whose gate needs a CONFIRMED row.
_co_hard() { case "$1" in 0|3|4|7) printf ' ✋' ;; *) printf '' ;; esac; }
_co_next() { case "$1" in P|p) echo 0 ;; [0-6]) echo $(( $1 + 1 )) ;; *) echo "" ;; esac; }

# One line each: what the stage is for, and how it is worked. Owning skill named so the reader
# can go there; nothing else, because everything else is in that skill.
_co_purpose() {
  case "$1" in
    0) echo "Characterise the source and decide scope IN: extract or not, which capabilities, in what order (\`source-triage.md\`)." ;;
    1) echo "Turn source code, documents and SME answers into a knowledge base — entities, logic, screens — and confirm scope OUT (\`migration-pipeline.md\`, \`kb-generation.md\`)." ;;
    2) echo "Write and validate one BRD per capability (\`F<NNN>.brd.json\`): entities, microflows, pages, use cases, open questions (\`brd-generation.md\`, \`brd-validation.md\`)." ;;
    3) echo "Decide the shape and the look: module boundaries, blueprint with fit-gap (buy / build / stub per item), security model, then the design system plus ONE annotated wireframe per screen (\`modularize-domain.md\`, \`architecture-blueprint.md\`, \`design-artifacts.md\`)." ;;
    4) echo "Turn BRDs + architecture into a numbered, dependency-ordered script plan with grants co-located, a coverage ledger (every requirement claimed by a row or catalogued with a reason) and the first module brief (\`brd-to-build-plan.md\`, \`coverage-ledger.md\`, \`module-brief.md\`)." ;;
    5) echo "Build the model one module at a time from the plan, as mxcli MDL scripts, each module closed by one review pass (\`iterative-build-loop.md\`, \`module-review.md\`)." ;;
    6) echo "Prove the app end to end: golden path + edge cases + DB assertions, the app-wide module review, and the process-coherence pass (\`testing-shape.md\`, \`e2e-harness-base.md\`)." ;;
    7) echo "Legacy-data migration and the cutover decision — recorded even when the decision is to throw the legacy data away (\`checkpoint-cutover.md\`)." ;;
    *) echo "" ;;
  esac
}
_co_approach() {
  case "$1" in
    0) echo "ba-agent runs \`source-sufficiency.sh\` and fills \`triage.md\`; CAC-1 opens with a scope brainstorm, not options; ✋ sign-off on the extraction decision before any BRD." ;;
    1) echo "Path A extractors (migration) / Path B document extraction / Path C SME interview; four extraction quality checks with evidence; CAC-1b diffs what came out against what was scoped in." ;;
    2) echo "Scaffold → enrich from the KB → validation loop to Clean; every \`openQuestions\` entry is raised in chat (\`open-questions.sh --stage 2\` must report 0 blocking); CAC-2 fixes grouping and order, CAC-3 catches hidden business rules before architecture locks." ;;
    3) echo "architect-agent proposes with evidence, you confirm at the ✋ gate — boundaries, buy/build/stub, roles, volumes, integrations, branding each asked. Nothing touches the .mpr. Diagrams: layer + wiring always; workflow / agent-wiring when CAC-3 Q3 flags them; cross-persona journeys when more than one persona. CAC-4 brainstorms the design direction before any design system is generated." ;;
    4) echo "Plan rows carry \`claims:\`; the coverage check is pasted (UNCLAIMED / PHANTOM / DOUBLE-CLAIMED all empty, leaf counts shown); every CONFIRMED decision from Stages 0–3 maps to a row id or a descoped ledger entry; CAC-5 brainstorms scope and order before the plan locks. No MDL is written here." ;;
    5) echo "Per script: snapshot → \`exec.sh\` → mxbuild gate → happy path. Per module: build, gate, prove, LOOK over every page (\`module-review.md\`) with the denominator stated — pages reviewed of pages that exist. Fixtures seeded per \`fixture-seeding.md\`; live checklist in chat throughout, never more than two items silently." ;;
    6) echo "Playwright harness with DB assertions, results reported verbatim; zero open P1 app-wide; journeys proven non-vacuous (\`journey-proof.md\`); the headline states pages and journeys covered of those that exist, and names anything UNMEASURED." ;;
    7) echo "Stage 6 passed first; CAC-6 asks cutover readiness; ✋ CONFIRMED only." ;;
    *) echo "" ;;
  esac
}
# Primary skill groups per stage (skill-routing.tsv column 7), in preference order. The ranking
# below puts these first, then the more stage-specific row, then baseline before ondemand.
_co_groups() {
  case "$1" in
    0) echo "source,requirements" ;; 1) echo "source,requirements" ;; 2) echo "requirements" ;;
    3) echo "architecture,design" ;; 4) echo "requirements,architecture" ;; 5) echo "build,verify" ;;
    6) echo "verify" ;;              7) echo "spine,verify" ;;             *) echo "" ;;
  esac
}
# Checkpoints that fire INSIDE the stage being opened, with when (conversion-runbook.md §2 table).
_co_checkpoints() {
  case "$1" in
    0) echo "\`checkpoint-scope.md\` (CAC-1) at the close — opens with a brainstorm" ;;
    1) echo "\`checkpoint-extraction.md\` (CAC-1b) at the close — scope out" ;;
    2) echo "\`checkpoint-brd.md\` (CAC-2) after the scaffold; \`checkpoint-architecture.md\` (CAC-3) at the close" ;;
    3) echo "\`checkpoint-design.md\` (CAC-4) after the architecture, BEFORE any design system — opens with a brainstorm" ;;
    4) echo "\`checkpoint-build.md\` (CAC-5) at the close — opens with a brainstorm on scope and order" ;;
    5) echo "none — the per-module build loop and its live checklist are the conversation" ;;
    6) echo "\`checkpoint-cutover.md\` (CAC-6) at the close — ✋, CONFIRMED only" ;;
    7) echo "none after CAC-6" ;;
    *) echo "" ;;
  esac
}

_co_trim() { printf '%s' "$1" | sed -E 's/^[ \t]+//; s/[ \t]+$//; s/^\*+//; s/\*+$//; s/^[ \t]+//; s/[ \t]+$//'; }
# Truncate to N chars on a word boundary, with an ellipsis. Cells in a real register run to
# 2,000 characters; the block is a recap, the register is the record.
_co_trunc() {
  local s="$1" n="${2:-110}"
  if [ "${#s}" -le "$n" ]; then printf '%s' "$s"; return; fi
  printf '%s…' "$(printf '%s' "$s" | cut -c1-"$n" | sed -E 's/[[:space:]]+[^[:space:]]*$//')"
}
# Stage cell → bare stage token ("Stage 3" → 3, "P" → P). Empty when it is not a stage.
_co_stage_of() {
  local s; s="$(_co_trim "$1" | sed -E 's/^[Ss]tage[ \t]*//')"
  case "$s" in P|p) echo P ;; [0-7]) echo "$s" ;; *) echo "" ;; esac
}
# First word of a status cell, upper-cased, punctuation stripped — the same "controlled
# vocabulary or it is not closed" stance as bin/open-questions.sh.
_co_status_word() { _co_trim "$1" | awk '{print toupper($1)}' | tr -d '.,;:→*_()' ; }
_co_is_closed() {
  case "$1" in ANSWERED|RESOLVED|CONFIRMED|MOOT|CLOSED|DONE|WITHDRAWN|DECIDED) return 0 ;; *) return 1 ;; esac
}

# _co_table <register> <section heading (lowercase, without ##)> — rows of that section's
# markdown table, header and separator dropped, one row per line, cells tab-separated.
_co_table() {
  awk -v want="$2" '
    /<!--/ { c = 1 } c { if ($0 ~ /-->/) c = 0; next }
    /^## / { h = tolower($0); sub(/^## +/, "", h); insec = (index(h, want) == 1); next }
    insec && /^\|/ {
      line = $0; sub(/^\|/, "", line); sub(/\|[ \t]*$/, "", line)
      n = split(line, f, "|")
      if (f[1] ~ /^[ \t]*-+[ \t]*$/) next
      first = f[1]; gsub(/^[ \t]+|[ \t]+$/, "", first)
      if (tolower(first) == "stage" || first == "#") next
      out = ""
      for (i = 1; i <= n; i++) { g = f[i]; gsub(/^[ \t]+|[ \t]+$/, "", g); out = out (i > 1 ? "\t" : "") g }
      print out
    }' "$1"
}

# ── plain words ─────────────────────────────────────────────────────────────
# What each artifact IS, for a reader who does not know the toolkit. One clause, no file
# names — the file name is on the technical line next to it. Unknown ids fall back to the id.
_co_plain_artifact() {
  case "$1" in
    intake) echo "the kickoff questionnaire (what this project is)" ;;
    register) echo "the decision register" ;;
    triage) echo "the triage sheet (what we take from the source, and how)" ;;
    extraction-report) echo "the report on what extraction found" ;;
    brds) echo "the requirement documents, one per capability" ;;
    brd-validation) echo "the validation report on the requirements" ;;
    brd-surface) echo "the readable requirements overview page" ;;
    module-design) echo "the module-split sign-off page" ;;
    fit-gap) echo "the buy / build / stub list" ;;
    blueprint-md) echo "the architecture blueprint" ;;
    blueprint-html) echo "the rendered architecture page" ;;
    design-system) echo "the design system showcase (colours, components)" ;;
    ds-css) echo "the stylesheet behind the design system" ;;
    wireframes) echo "one wireframe per screen" ;;
    module-definition) echo "one definition document per module" ;;
    build-plan) echo "the numbered build plan" ;;
    build-plan-html) echo "the build progress board" ;;
    module-brief) echo "the first module's brief (what the builder gets)" ;;
    coverage-ledger) echo "the ledger proving every requirement is claimed by a build step" ;;
    ui-reviews) echo "the page review report" ;;
    journeys) echo "the click-through journey definitions" ;;
    page-scope) echo "the list of pages in scope for review" ;;
    improvement-register|improvement-register-html) echo "the findings register" ;;
    report-json|verification-html) echo "the test report" ;;
    workflow-design) echo "the process diagrams (states, and who moves them)" ;;
    swimlanes) echo "swimlane diagrams (who does what, per process)" ;;
    sequence-diagrams) echo "sequence diagrams for integrations and agent calls" ;;
    erd) echo "the entity diagram across modules" ;;
    nfr-sheet) echo "the non-functional requirements table" ;;
    integration-contracts) echo "the integration contracts" ;;
    test-plan) echo "the test plan" ;;
    acceptance-criteria) echo "the acceptance criteria per module" ;;
    demo-script) echo "the demo script" ;;
    *) echo "$1" ;;
  esac
}
# What the gate of a stage NEEDS, in one plain sentence (conversion-runbook.md §2 Gate rows).
_co_plain_gate_needs() {
  case "$1" in
    P) echo "every kickoff question answered, or marked as something we could not verify and how we would" ;;
    0) echo "a signed triage sheet — you agreed what we take from the source and how" ;;
    1) echo "the extraction checked for quality, and you confirmed what came out is what you meant" ;;
    2) echo "every requirement document validated clean, and every question the pipeline raised put to you in chat" ;;
    3) echo "the architecture and the design produced, and you said yes to the module split, the buy/build/stub calls, the roles, and the look" ;;
    4) echo "a build plan you approved, with every requirement claimed by a build step and every earlier decision mapped to one" ;;
    5) echo "every build script through its gates, and every module reviewed with the numbers stated (pages reviewed of pages that exist)" ;;
    6) echo "the end-to-end tests passing, the app-wide review with zero open showstoppers, and the numbers stated" ;;
    7) echo "a recorded cutover decision — even if it is to throw the legacy data away" ;;
    *) echo "" ;;
  esac
}
# mxtk_plain_verdict <stage> <verdict text> <project-dir> [register]
# The "In plain words" paragraph under a gate line: status first, then every reason the
# technical text carries that has a known plain translation, then what is still missing on
# the manifest for this stage. Written for the person in the chat, not the agent.
mxtk_plain_verdict() {
  local st="$1" v="$2" root="$3" reg="${4:-$3/PROJECT.md}" status low
  status="$(printf '%s' "$v" | sed -E 's/^Stage [P0-7]: *//' | awk '{print toupper($1)}' | tr -d ':,;—-')"
  low="$(printf '%s' "$v" | tr '[:upper:]' '[:lower:]')"
  printf '**In plain words:** '
  case "$low" in *blocked*) status="BLOCKED" ;; esac
  case "$status" in
    BLOCKED) printf 'the stage'"'"'s own checks pass, but the gate is held shut by something outside them (below)' ;;
    PASS)    printf 'this stage is done — what the gate looks for is there and signed off' ;;
    PENDING) printf 'nothing is wrong, but this stage has not produced what its gate looks for yet' ;;
    FAIL)    printf 'something is there but it is not acceptable yet, or the sign-off is missing' ;;
    WAIVED)  printf 'you declared this stage out of scope for this project, with a reason, so it does not block' ;;
    MANUAL)  printf 'a script cannot check this gate — a person has to paste the evidence in chat' ;;
    *)       printf 'the gate could not be read (%s)' "${status:-no verdict}" ;;
  esac
  printf '. The gate needs: %s.\n' "$(_co_plain_gate_needs "$st")"
  local said=0
  _co_say() { [ "$said" -eq 0 ] && printf 'Why, specifically:\n'; said=1; printf -- '- %s\n' "$1"; }
  case "$low" in *"older than"*|*"stale render"*)
    _co_say "a rendered page is out of date compared to the document it was made from — regenerate the render; the content itself is not what failed" ;; esac
  case "$low" in *"no stage-"*"confirmed decision"*|*"no confirmed decision"*|*"without an interview"*|*"nobody approved"*)
    _co_say "the sign-off question for this stage was never answered in chat — the files exist, but nobody said yes to them" ;; esac
  case "$low" in *unsynced*)
    _co_say "a decision changed a requirement and the requirements document (BRD or wireframe) has not been updated to match — that has to be brought in line first" ;; esac
  case "$low" in *"not clean"*|*"findings outstanding"*)
    _co_say "the requirements validation still lists problems" ;; esac
  case "$low" in *"blocking question"*|*"never raised"*|*"unraised"*)
    _co_say "questions the pipeline raised were never put to you" ;; esac
  case "$low" in *"placeholder"*|*"[user] on [date]"*)
    _co_say "the sign-off line is still the template placeholder — nobody signed" ;; esac
  case "$low" in *"is empty"*|*"exists but is empty"*)
    _co_say "a file exists but has nothing in it" ;; esac
  case "$low" in *"sufficiency"*)
    _co_say "the source was never rated for whether it holds enough to build from" ;; esac
  case "$low" in *"p1"*|*"module-review"*)
    _co_say "the app-wide page review has not run, or still has open showstoppers" ;; esac
  case "$low" in *"unanswered"*|*"no blanks"*|*"blank"*)
    _co_say "a kickoff question is still blank" ;; esac
  # Missing mandatory artifacts for this stage, in plain names.
  local id stage paths producer consumers modes absence miss=""
  if [ -f "$ARTIFACT_TSV" ]; then
    while IFS=$'\t' read -r id stage paths producer consumers modes absence; do
      case "$id" in ''|'#'*|artifact) continue ;; esac
      [ "$stage" = "$st" ] && [ "$absence" != "optin" ] || continue
      _art_waiver "$reg" "$id" "$stage" >/dev/null 2>&1 && continue
      _art_find "$root" "$paths"
      [ -z "$ART_HIT" ] && miss="$miss${miss:+; }$(_co_plain_artifact "$id")"
    done < "$ARTIFACT_TSV"
  fi
  [ -n "$miss" ] && _co_say "still missing for this stage: $miss"
  case "$status" in
    PASS|WAIVED) [ "$said" -eq 0 ] && printf 'Nothing is holding it.\n' ;;
    *) [ "$said" -eq 0 ] && printf 'The technical line above names the exact file or row; nothing in it has a plainer translation yet — say so and one gets added.\n' ;;
  esac
  return 0
}

# ── the block ───────────────────────────────────────────────────────────────
# mxtk_closeout_report <project-dir> <stage> [register]
mxtk_closeout_report() {
  local root="$1" st="$2" reg="${3:-$1/PROJECT.md}"
  local next title ntitle
  case "$st" in P|p) st=P ;; [0-7]) ;; *) echo "closeout: stage must be P or 0-7 (got '$st')" >&2; return 2 ;; esac
  title="$(_co_title "$st")"; next="$(_co_next "$st")"; ntitle="$(_co_title "$next")"

  printf '## Stage %s close-out — %s%s\n\n' "$st" "$title" "$(_co_hard "$st")"

  # ── Artifacts produced ──────────────────────────────────────────────────
  printf '**Artifacts produced** (rows of `bin/lib/artifact-manifest.tsv` for stage %s; presence only, never quality)\n' "$st"
  local id stage paths producer consumers modes absence reason n_art=0 optin
  if [ -f "$ARTIFACT_TSV" ]; then
    while IFS=$'\t' read -r id stage paths producer consumers modes absence; do
      case "$id" in ''|'#'*|artifact) continue ;; esac
      [ "$stage" = "$st" ] || continue
      optin=""
      if [ "$absence" = "optin" ]; then
        optin="$(_art_field "$reg" "opt-in artifact $id" 2>/dev/null || true)"
        _art_find "$root" "$paths"
        # Offered, never taken up, never produced: not this stage's output — say nothing here;
        # it was listed at the stage OPEN as on offer.
        [ -z "$optin" ] && [ -z "$ART_HIT" ] && continue
      fi
      n_art=$((n_art+1))
      if reason="$(_art_waiver "$reg" "$id" "$stage")"; then
        printf -- '- ⏭ `%s` — WAIVED: %s\n' "$id" "$reason"; continue
      fi
      _art_find "$root" "$paths"
      if [ -n "$ART_HIT" ]; then
        printf -- '- ✅ `%s`%s — `%s`\n' "$id" "$( [ -n "$optin" ] && printf ' (opted in)' )" "${ART_HIT#"$root"/}"
      elif [ -n "$ART_EMPTY" ]; then
        printf -- '- ❌ `%s` — EMPTY file at `%s`; produced-and-empty is not produced (producer: %s)\n' "$id" "${ART_EMPTY#"$root"/}" "$producer"
      else
        printf -- '- ⬜ `%s` — PENDING; produce it: %s\n' "$id" "$producer"
      fi
    done < "$ARTIFACT_TSV"
  fi
  [ "$n_art" -eq 0 ] && printf -- '- (the manifest promises no artifact for stage %s)\n' "$st"
  printf '\n'

  # ── Decisions made this stage ───────────────────────────────────────────
  local rows n_conf=0 n_ass=0 n_oth=0 n_dec=0 s d status notes w
  rows="$( [ -f "$reg" ] && _co_table "$reg" "decisions" || true )"
  local dec_lines="" dec_cap=15
  while IFS=$'\t' read -r s d status notes; do
    [ -n "${s:-}" ] || continue
    [ "$(_co_stage_of "$s")" = "$st" ] || continue
    w="$(_co_status_word "$status")"
    case "$w" in CONFIRMED) n_conf=$((n_conf+1)) ;; ASSUMED) n_ass=$((n_ass+1)) ;; *) n_oth=$((n_oth+1)) ;; esac
    n_dec=$((n_dec+1))
    # A recap, not the register: past the cap, count instead of list (§1b: "group, don't
    # dump"). Non-CONFIRMED rows are never dropped — a PENDING or SUPERSEDED row IS the news.
    if [ "$n_dec" -gt "$dec_cap" ] && [ "$w" = "CONFIRMED" ]; then continue; fi
    dec_lines="$dec_lines$(printf -- '- %s · %s%s' "${w:-?}" "$(_co_trunc "$(_co_trim "$d")" 110)" \
      "$( [ -n "$(_co_trim "${notes:-}")" ] && printf ' — %s' "$(_co_trunc "$(_co_trim "$notes")" 90)" )")"$'\n'
  done <<< "$rows"
  if [ "$n_dec" -gt "$dec_cap" ]; then
    dec_lines="$dec_lines- … and the remaining CONFIRMED rows (first $dec_cap listed, all $n_dec stage-$st rows are in $(basename "$reg"))"$'\n'
  fi
  printf '**Decisions made this stage** (`%s` → Decisions, stage %s: %s CONFIRMED, %s ASSUMED%s)\n' \
    "$(basename "$reg")" "$st" "$n_conf" "$n_ass" "$( [ "$n_oth" -gt 0 ] && printf ', %s with another status word' "$n_oth" )"
  if [ $((n_conf + n_ass + n_oth)) -eq 0 ]; then
    if [ -n "$(_co_hard "$st")" ]; then
      printf -- '- none recorded — this is a ✋ stage: artifacts without a CONFIRMED row do not pass its gate\n'
    else
      printf -- '- none recorded\n'
    fi
  else
    printf '%s' "$dec_lines"
  fi
  printf '\n'

  # ── Carried forward ─────────────────────────────────────────────────────
  printf '**Carried forward into Stage %s** (what is still open; the register is the record, this is the view)\n' "${next:-—}"
  local carried=0 q raised oq_lines="" n_oq=0
  rows="$( [ -f "$reg" ] && _co_table "$reg" "open questions" || true )"
  while IFS=$'\t' read -r id q raised status; do
    [ -n "${id:-}" ] || continue
    w="$(_co_status_word "${status:-}")"
    _co_is_closed "$w" && continue
    n_oq=$((n_oq+1))
    oq_lines="$oq_lines$(printf -- '  - %s (%s) — %s' "$(_co_trim "$id")" "${w:-no status}" "$(_co_trunc "$(_co_trim "$q")" 100)")"$'\n'
  done <<< "$rows"
  if [ "$n_oq" -gt 0 ]; then
    carried=1
    printf -- '- Open questions not closed: %s (status word outside answered / resolved / confirmed / moot / closed / done / withdrawn / decided — fix the word if the question is actually closed)\n%s' "$n_oq" "$oq_lines"
  fi
  local as_lines="" n_as=0
  rows="$( [ -f "$reg" ] && _co_table "$reg" "decisions" || true )"
  while IFS=$'\t' read -r s d status notes; do
    [ -n "${s:-}" ] || continue
    [ "$(_co_status_word "$status")" = "ASSUMED" ] || continue
    n_as=$((n_as+1))
    as_lines="$as_lines$(printf -- '  - stage %s · %s' "$(_co_trim "$s")" "$(_co_trunc "$(_co_trim "$d")" 100)")"$'\n'
  done <<< "$rows"
  if [ "$n_as" -gt 0 ]; then
    carried=1
    printf -- '- Decisions still ASSUMED (any stage; each carries a risk if wrong): %s\n%s' "$n_as" "$as_lines"
  fi
  local n_unsync=0
  [ -f "$reg" ] && n_unsync="$(grep -c 'UNSYNCED' "$reg" 2>/dev/null || true)"; n_unsync="${n_unsync:-0}"
  if [ "${n_unsync:-0}" -gt 0 ]; then
    carried=1
    printf -- '- BRD drift markers still `UNSYNCED`: %s — gate-check blocks every gate until ba-agent flushes them\n' "$n_unsync"
  fi
  [ "$carried" -eq 0 ] && printf -- '- nothing — no open question, no ASSUMED decision, no UNSYNCED marker\n'
  printf '\n'

  # ── Gate ────────────────────────────────────────────────────────────────
  printf '**Gate** (`bin/gate-check.sh %s %s`, verbatim)\n' "$root" "$st"
  local verdict="${MXTK_CLOSEOUT_VERDICT:-}"
  if [ -z "$verdict" ] && [ -x "$_CO_LIB_DIR/../gate-check.sh" ] && [ "$st" != "P" ]; then
    verdict="$(MXTK_NO_FETCH=1 "$_CO_LIB_DIR/../gate-check.sh" --no-html "$root" 2>/dev/null | grep "^Stage $st " | head -1 || true)"
  fi
  printf '%s\n\n' "${verdict:-Stage $st: (no verdict available — run gate-check.sh and paste its line)}"
  mxtk_plain_verdict "$st" "${verdict:-}" "$root" "$reg"
  printf '\n'

  # ── Next stage ──────────────────────────────────────────────────────────
  if [ -z "$next" ]; then
    printf '_No next stage — Stage 7 is the last. Close the loop per `skills/close-the-loop.md`._\n'
    return 0
  fi
  printf '## Next: Stage %s — %s%s\n\n' "$next" "$ntitle" "$(_co_hard "$next")"
  printf '**What it does:** %s\n\n' "$(_co_purpose "$next")"
  printf '**How it is worked:** %s\n\n' "$(_co_approach "$next")"
  printf '**Checkpoints in this stage:** %s.\n\n' "$(_co_checkpoints "$next")"

  printf '**Governing skills and instruments** (top 5 from `bin/lib/skill-routing.tsv` for stage %s, ranked by group then specificity; the full routed set is `README.md` → "When to use which skill" — the always-on baseline set applies on top)\n' "$next"
  if [ -f "$ROUTING_TSV" ]; then
    awk -F'\t' -v st="$next" -v groups="$(_co_groups "$next")" '
      /^#/ || NF < 7 { next }
      $6 == "experimental" { next }
      $1 == "interview-protocol" || $1 == "grill-mode" || $2 ~ /checkpoints\// { next }
      {
        n = split($5, a, ","); hit = 0
        for (i = 1; i <= n; i++) if (a[i] == st) hit = 1
        if (!hit) next
        gp = split(groups, g, ","); rank = 9
        for (i = 1; i <= gp; i++) if ($7 == g[i]) rank = i
        printf "%d\t%d\t%d\t%s\t%s\n", rank, n, ($6 == "baseline" ? 0 : 1), $2, $3
      }' "$ROUTING_TSV" | sort -t$'\t' -n -k1,1 -k2,2 -k3,3 | head -5 \
      | awk -F'\t' '{ t = $5; if (length(t) > 160) t = substr(t, 1, 157) "…"; printf "- `%s` — %s\n", $4, t }'
  else
    printf -- '- (skill-routing.tsv not found at %s — routing cannot be shown)\n' "$ROUTING_TSV"
  fi
  printf '\n'

  printf '**Optional artifacts on offer for Stage %s** (none is owed unless you opt in; opt in with one line in `%s`: `Opt-in artifact <id>: <why>` — the artifact check then tracks it like any other)\n' "$next" "$(basename "$reg")"
  local n_opt=0
  if [ -f "$ARTIFACT_TSV" ]; then
    while IFS=$'\t' read -r id stage paths producer consumers modes absence; do
      case "$id" in ''|'#'*|artifact) continue ;; esac
      [ "$stage" = "$next" ] && [ "$absence" = "optin" ] || continue
      n_opt=$((n_opt+1))
      optin="$(_art_field "$reg" "opt-in artifact $id" 2>/dev/null || true)"
      if [ -n "$optin" ]; then
        printf -- '- ✅ `%s` — opted in (%s) — `%s`\n' "$id" "$(_co_trunc "$optin" 60)" "${paths%%|*}"
      else
        printf -- '- ⬜ `%s` — `%s` — %s\n' "$id" "${paths%%|*}" "$(_co_trunc "$producer" 140)"
      fi
    done < "$ARTIFACT_TSV"
  fi
  [ "$n_opt" -eq 0 ] && printf -- '- (none on the manifest for stage %s — say what you want and it can be added)\n' "$next"
  printf -- '- anything else you want defined before this stage starts — name it\n\n'

  printf '_Generated by `gate-check.sh --closeout`; paste as-is, then run the stage'"'"'s checkpoint or open its live checklist (conversion-runbook.md §1b rule 7)._\n'
  return 0
}

# Direct invocation.
if [ "${BASH_SOURCE[0]:-$0}" = "${0}" ]; then
  [ $# -ge 2 ] || { echo "usage: bin/lib/closeout.sh <project-dir> <stage> [register]" >&2; exit 2; }
  mxtk_closeout_report "$1" "$2" "${3:-}"
fi
