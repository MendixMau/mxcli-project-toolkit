#!/usr/bin/env bash
# Collect every unresolved question a project has raised with itself, and print it as a
# chat-ready batch the agent can paste at a gate.
#
# The defect this exists for: the pipeline generates questions (BRD `openQuestions`,
# analysis/sme-questions.md) and then answers a good number of them unilaterally, in free text,
# in a file nobody opens. Measured on one real project: 46 question rows, 7 mentions of an
# answer, 23 DISTINCT free-text status strings — no controlled vocabulary, therefore nothing
# could ever count them, therefore nothing ever surfaced them. Several of the self-answers were
# real product decisions (hardcode vs. build a rules engine; is a 20-station approval engine in
# scope) taken without the user ever seeing the question.
#
# The ruling this implements: batch per gate. RAISING IS MANDATORY. ASSUMING IS PERMITTED ONLY
# AFTER RAISING. An assumption the user never saw is the defect — not the assumption itself.
#
# Usage:
#   bin/open-questions.sh <project-dir> [stage]
#   bin/open-questions.sh <project-dir> --stage 2
#   bin/open-questions.sh <project-dir> --json
#   bin/open-questions.sh --mapping-table
#
# Exit codes: 0 = nothing blocks. 1 = blocking questions exist. 2 = usage/environment error.
#             3 = nothing was examined (no BRDs and no sme-questions.md) — NOT a clean result.

set -uo pipefail

# ---------------------------------------------------------------------------
# THE CONTROLLED VOCABULARY
# ---------------------------------------------------------------------------
# Six states. Five are authorable; UNRECOGNISED is only ever an output of the normaliser.
# The set is chosen to distinguish exactly the transitions the ruling cares about and nothing
# more — every additional state is another string nobody will spell the same way twice.
#
#   UNRAISED     Never put in front of the user. This is the DEFAULT for anything the
#                normaliser cannot positively place past it.            **BLOCKS**
#   RAISED       Put to the user in chat at a named gate; awaiting their reply. Does not
#                block: the user has seen it, which is the whole ask. Reported as awaiting.
#   ANSWERED     The user decided. Requires a non-empty answer/decision/resolution.
#   ASSUMED      The agent took a position AND the user consented after seeing it.
#                Requires consentBy + consentAt. An `ASSUMED` without them is NOT this
#                state — it is the defect, and normalises to UNRAISED.
#   MOOT         The question stopped mattering (descoped by another decision). Without
#                this, dead questions force-fit into ANSWERED (a lie about a decision) or
#                block a gate forever. Requires the reason to be in the text.
#   UNRECOGNISED The normaliser could not confidently place it. Counts as NOT done.
#                                                                        **BLOCKS**
#
# Blocking set = UNRAISED + UNRECOGNISED. Both mean "the user has not seen this."

VOCAB_BLOCKING="UNRAISED UNRECOGNISED"

# ---------------------------------------------------------------------------
# Schema additions a BRD openQuestion may carry (all optional, all small):
#   raisedAtGate : "Stage 2 gate, 2026-08-12"  — where it was PUT TO THE USER.
#   consentBy    : "Maurits Visser"            — who said "you decide".
#   consentAt    : "2026-08-12"
#
# NOTE the deliberate name `raisedAtGate`. The existing field `raisedAt` is already in real
# data meaning "the pass during which the agent NOTICED this" ("Stage 2 source re-read") —
# an authoring event, not a user-facing one. Reusing it would have silently promoted every
# self-noticed question to RAISED. It is ignored here, on purpose.
# ---------------------------------------------------------------------------

print_mapping_table() {
  cat <<'TABLE'
NORMALISER MAPPING TABLE — how a free-text status becomes a vocabulary state.
Rules are tried in order; first match wins. Matching is on the LEADING TOKEN of the
lowercased string, never "contains" — "Open — ASSUMED for drafting purposes" contains both
words and is Open.

  # | leading token          | extra condition                  | ->
 ---+------------------------+----------------------------------+---------------
  1 | (empty)                | verdict column exists but blank  | UNRAISED
  2 | resolved | closed      | AND a non-empty answer/decision  | ANSWERED
  3 | resolved | closed      | but NO answer recorded           | UNRECOGNISED
  4 | assumed                | AND consentBy AND consentAt      | ASSUMED
  5 | assumed                | no consent recorded              | UNRAISED  <- the defect
  6 | raised | awaiting      | (any)                            | RAISED
  7 | moot | n/a | not      | (any)                            | MOOT
    | relevant | irrelevant |                                  |
    | does not apply | withdrawn |                              |
  8 | open | carried forward | next clause begins "moot"        | MOOT
  9 | open | carried forward | otherwise                        | UNRAISED
 10 | <no verdict column>    | md table has no Decision/        | UNRAISED
    |                        | Resolution/Status/Answer column  |
 11 | anything else          |                                  | UNRECOGNISED

Markdown-specific: a table column headed "Decision" that is FILLED counts as ANSWERED even
when its text is prose rather than a status word — a filled decision column is a recorded
decision. A column headed Resolution/Status/Answer goes through rules 1-11 above. A table
with none of those columns (question + evidence + options only) is UNRAISED by rule 10.

Everything rule 11 catches is printed individually so a human can audit it. Nothing is ever
bucketed as resolved because it was unparseable.
TABLE
}

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
JSON=0
STAGE=""
PROJECT_DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --mapping-table) print_mapping_table; exit 0 ;;
    --json)          JSON=1 ;;
    --stage)         shift; STAGE="${1:-}" ;;
    --stage=*)       STAGE="${1#--stage=}" ;;
    -h|--help)       sed -n '2,30p' "$0"; exit 0 ;;
    --*)             echo "Error: unknown option '$1'." >&2; exit 2 ;;
    *)               if [ -z "$PROJECT_DIR" ]; then PROJECT_DIR="$1"; else STAGE="$1"; fi ;;
  esac
  shift
done

if [ -z "$PROJECT_DIR" ]; then
  echo "Usage: $0 <project-dir> [stage] [--stage N] [--json]" >&2
  echo "       $0 --mapping-table" >&2
  exit 2
fi
if [ ! -d "$PROJECT_DIR" ]; then
  echo "Error: project directory does not exist: $PROJECT_DIR" >&2
  exit 2
fi
case "$STAGE" in
  ""|P|p|build-ready) STAGE="" ;;
  [0-7]) ;;
  *) echo "Error: stage must be 0-7 (got '$STAGE')." >&2; exit 2 ;;
esac
command -v jq >/dev/null 2>&1 || { echo "Error: jq is required." >&2; exit 2; }

# ---------------------------------------------------------------------------
# Locate the artifacts. Same convention as gate-check.sh: analysis/<name>/knowledge-base/,
# falling back to knowledge-base/ at the project root. ALL matches, not the first.
# ---------------------------------------------------------------------------
BRD_FILES=""
for kb in "$PROJECT_DIR"/analysis/*/knowledge-base "$PROJECT_DIR"/analysis/knowledge-base "$PROJECT_DIR"/knowledge-base; do
  [ -d "$kb/brd" ] || continue
  for f in "$kb"/brd/*.brd.json; do
    [ -f "$f" ] || continue
    BRD_FILES="$BRD_FILES$f
"
  done
done
SME_FILES=""
for smf in "$PROJECT_DIR"/analysis/sme-questions.md "$PROJECT_DIR"/analysis/*/sme-questions.md; do
  [ -f "$smf" ] || continue
  SME_FILES="$SME_FILES$smf
"
done

BRD_COUNT=$(printf '%s' "$BRD_FILES" | grep -c . | tr -d ' ')
SME_COUNT=$(printf '%s' "$SME_FILES" | grep -c . | tr -d ' ')

# ---------------------------------------------------------------------------
# Extract. Records are TAB-separated:
#   rawStatus \t id \t origin \t question \t assumption \t consentBy \t consentAt \t answer \t hint
# `hint` carries the note text, used only for stage attribution and cross-reference dedup.
# Tabs and newlines are stripped from every field at the source.
# ---------------------------------------------------------------------------
RECORDS=""

if [ -n "$BRD_FILES" ]; then
  brd_recs=$(printf '%s' "$BRD_FILES" | while IFS= read -r f; do
    [ -n "$f" ] || continue
    jq -r --arg src "$(basename "$f")" '
      def clean: (. // "") | tostring | gsub("[\t\n\r]"; " ") | gsub("  +"; " ");
      (.openQuestions // [])[] |
      [ (.status | clean),
        (.id | clean),
        $src,
        (.question | clean),
        ((.decision // .assumption // "") | clean),
        ((.consentBy // "") | clean),
        ((.consentAt // "") | clean),
        ((.answer // .resolution // "") | clean),
        (((.note // "") + " " + (.impact // "") + " " + (.source // "") + " " + (.risk // "")) | clean)
      ] | @tsv
    ' "$f" 2>/dev/null
  done)
  RECORDS="$RECORDS$brd_recs
"
fi

# --- sme-questions.md: markdown tables. ------------------------------------
# A row is a question if column 1 is an ID like A1 / W3 / OQ-FOO / F007-OQ2.
# The verdict comes from whichever header column is named Decision/Resolution/Status/Answer.
# A table with NO such column yields UNRAISED for every row — rule 10, and it is the single
# most common real shape (question | evidence | options).
if [ -n "$SME_FILES" ]; then
  sme_recs=$(printf '%s' "$SME_FILES" | while IFS= read -r f; do
    [ -n "$f" ] || continue
    awk -v src="$(basename "$f")" '
      function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
      function strip(s) { gsub(/\*\*/, "", s); gsub(/`/, "", s); return trim(s) }
      # A separator row (|---|---|) means the PREVIOUS line was the header.
      /^\|[ \t]*:?-+/ {
        nhdr = split(prev, H, "|")
        verdictcol = 0; verdictname = ""
        for (i = 1; i <= nhdr; i++) {
          h = tolower(strip(H[i]))
          if (h == "decision" || h ~ /^decision[ (]/ ) { verdictcol = i; verdictname = "decision" }
          else if (h ~ /^resolution/ || h ~ /^status/ || h ~ /^answer/) { verdictcol = i; verdictname = "resolution" }
        }
        intable = 1; prev = $0; next
      }
      /^\|/ {
        if (intable) {
          n = split($0, C, "|")
          id = strip(C[2])
          if (id ~ /^[A-Z][A-Za-z0-9]*(-[A-Za-z0-9]+)*$/ && id ~ /[0-9]/) {
            q = strip(C[3])
            opts = ""
            for (i = 4; i <= n; i++) { hh = tolower(strip(C[i])); if (i != verdictcol) opts = opts " " strip(C[i]) }
            if (verdictcol > 0 && verdictcol <= n) {
              v = strip(C[verdictcol])
              if (v == "") raw = ""
              else if (verdictname == "decision") raw = "RESOLVED (decision column filled)"
              else raw = v
              ans = v
            } else {
              raw = "__NO_VERDICT_COLUMN__"
              ans = ""
            }
            gsub(/\t/, " ", q); gsub(/\t/, " ", ans); gsub(/\t/, " ", opts)
            printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", raw, id, src, q, "", "", "", ans, opts
          }
        }
        prev = $0; next
      }
      { intable = 0; prev = $0 }
    ' "$f"
  done)
  RECORDS="$RECORDS$sme_recs
"
fi

RECORDS=$(printf '%s\n' "$RECORDS" | grep -c . >/dev/null 2>&1; printf '%s' "$RECORDS" | grep .)

# ---------------------------------------------------------------------------
# Normalise + attribute a stage + dedup. One awk pass so the rules live in one place.
# Emits: state \t id \t origin \t stage \t question \t assumption \t reason
# ---------------------------------------------------------------------------
NORMALISED=$(printf '%s\n' "$RECORDS" | awk -F'\t' '
  function lower(s) { return tolower(s) }
  function leading(s,   t) {
    t = tolower(s)
    gsub(/^[ \t*_>-]+/, "", t)
    gsub(/[`"]/, "", t)
    return t
  }
  # first clause after the leading verdict word: split on , . ; — -
  function nextclause(s,   t, i, n, A) {
    t = leading(s)
    sub(/^[a-z\/ ]*/, "", t)          # drop the leading word(s)
    gsub(/^[ \t.,;:\-—()]+/, "", t)
    return t
  }
  NF < 9 { next }
  {
    raw=$1; id=$2; origin=$3; question=$4; assumption=$5
    consentBy=$6; consentAt=$7; answer=$8; hint=$9

    L = leading(raw)
    reason = ""
    state = ""

    if (raw == "__NO_VERDICT_COLUMN__") {
      state = "UNRAISED"; reason = "table has no Decision/Resolution column — options listed, nothing decided (rule 10)"
    }
    else if (L == "") {
      state = "UNRAISED"; reason = "verdict column present but blank (rule 1)"
    }
    # `answered`, `decided` and `confirmed` belong here and were missing until 2026-08-12.
    # ANSWERED is the canonical vocabulary word this toolkit tells authors to write, and the
    # collector classified that literal word UNRECOGNISED — i.e. the one status that is
    # unambiguously correct blocked the gate forever, while "closed" passed. Found by the
    # questions-report fixture. CONFIRMED is the word the runbook uses for a hard-gate decision.
    # (No apostrophes in this comment: the awk program is inside a single-quoted shell string.)
    else if (L ~ /^resolved/ || L ~ /^closed/ || L ~ /^answered/ || L ~ /^decided/ || L ~ /^confirmed/) {
      if (answer != "" || assumption != "") { state = "ANSWERED"; reason = "resolved with a recorded answer (rule 2)" }
      else { state = "UNRECOGNISED"; reason = "claims resolved but records no answer/decision/resolution (rule 3)" }
    }
    else if (L ~ /^assumed/) {
      if (consentBy != "" && consentAt != "") {
        state = "ASSUMED"; reason = "assumed with consent from " consentBy " on " consentAt " (rule 4)"
      } else {
        state = "UNRAISED"; reason = "ASSUMED with no consentBy/consentAt — a position taken the user never saw (rule 5)"
      }
    }
    else if (L ~ /^unraised/) {
      # The canonical vocabulary word for "never put to the user", and the DEFAULT the
      # header of this file tells authors to write. It was falling through to rule 11 and
      # reporting UNRECOGNISED — the identical defect fixed for ANSWERED on 2026-08-12,
      # two rules above. Both block, so a gate never wrongly opened; what broke is the
      # feedback to the author (a correctly authored status read as unparseable) and the
      # counts (UNRAISED=0 beside a genuinely unraised question). Found 2026-08-31 on a
      # hand-authored BRD in a migration project. (No apostrophes here: single-quoted awk.)
      state = "UNRAISED"; reason = "explicitly unraised — never put to the user (rule 5b)"
    }
    else if (L ~ /^raised/ || L ~ /^awaiting/) {
      state = "RAISED"; reason = "raised, awaiting the user (rule 6)"
    }
    else if (L ~ /^moot/ || L ~ /^n\/a/ || L ~ /^not applicable/ || L ~ /^not relevant/ ||
             L ~ /^irrelevant/ || L ~ /^does not apply/ || L ~ /^withdrawn/) {
      state = "MOOT"
      # A bare trigger word with no clause after it is still accepted (a non-answer here would
      # defeat the point of recognising the phrase at all) but flagged distinctly, so an
      # auditor can tell "not relevant, here is why" from "not relevant." with nothing behind it.
      NC = nextclause(raw)
      if (NC == "") reason = "moot, no reason given (rule 7)"
      else reason = "moot — marked not relevant (rule 7)"
    }
    else if (L ~ /^open/ || L ~ /^carried forward/) {
      NC = nextclause(raw)
      if (NC ~ /^moot/) { state = "MOOT"; reason = "open but explicitly moot (rule 8)" }
      else { state = "UNRAISED"; reason = "open — never put to the user (rule 9)" }
    }
    else {
      state = "UNRECOGNISED"; reason = "no rule matched leading token (rule 11)"
    }

    # ---- drafting position -------------------------------------------------
    # Real BRDs almost never fill a `decision`/`assumption` field; the position the agent
    # took is buried in the free-text status ("ASSUMED drafting position (a), hardcode —
    # taken to keep this BRD buildable"). Surface it, because the entire point of the batch
    # is that the user can confirm or overturn a position rather than answer cold.
    # Matched on the UPPERCASE token only: the lowercase word appears in prose that is
    # explicitly disclaiming an assumption ("flagged as a trade-off rather than assumed"),
    # and an earlier draft that matched case-blind printed that disclaimer AS the assumption.
    if (assumption == "" && match(raw, /ASSUMED/)) {
      pos = substr(raw, RSTART + 7)
      sub(/^[ \t]*[-—:,.]?[ \t]*/, "", pos)
      if (pos != "") assumption = pos
    }

    # ---- stage attribution -------------------------------------------------
    # Origin decides the floor: sme-questions.md is Stage 1 discovery, a BRD is Stage 2.
    # An explicit "Stage N" in the text may push a question LATER (deferred to Stage 3) but
    # never earlier — real notes cite earlier stages in passing ("per the Stage 0 decision
    # A5"), and letting that pull a BRD question back to Stage 0 would make the Stage 0 gate
    # block on work that had not been done yet.
    blob = tolower(raw " " question " " hint " " assumption)
    stage = (origin ~ /sme-questions/) ? 1 : 2
    if (match(blob, /stage [0-7]/)) {
      cand = substr(blob, RSTART+6, 1) + 0
      if (cand > stage) stage = cand
    }

    # ---- dedup inputs ------------------------------------------------------
    # Two independent signals, resolved in the next pass (which is the only place that
    # knows the full sme-questions id index):
    #   qprefix   — normalised question text, so two rows sharing an id but asking
    #               DIFFERENT things are never silently merged. Hiding a question is the
    #               exact failure this tool exists to stop, so id alone is not enough.
    #   xreftarget— an EXPLICIT "routed to sme-questions.md F1" claim by the author. That is a
    #               statement of duplication by someone who read both, and it overrides the
    #               text check: the BRD row and the sme row deliberately word it differently.
    qk = tolower(question); gsub(/[^a-z0-9]/, "", qk)
    qprefix = substr(qk, 1, 60)
    xreftarget = ""
    tmp = raw " " hint
    if (tmp ~ /sme-questions\.md/) {
      if (match(tmp, /sme-questions\.md[ ]*[A-Z][0-9]+/)) {
        xreftarget = substr(tmp, RSTART, RLENGTH)
        sub(/^sme-questions\.md[ ]*/, "", xreftarget)
      }
    }
    printf "%s\t%s\t%s\t%d\t%s\t%s\t%s\t%s\t%s\t%s\n", state, id, origin, stage, question, assumption, reason, qprefix, raw, xreftarget
  }
')

# Dedup: a cross-referenced pair collapses onto the row that is CLOSEST TO THE USER — i.e. the
# sme-questions.md row, which is the surface a human actually reads. Rank states so the pair
# never resolves to the less-safe verdict: if either copy blocks, the survivor blocks.
DEDUPED=$(printf '%s\n' "$NORMALISED" | awk -F'\t' '
  # Safety rank: when two rows collapse, the SURVIVOR TAKES THE WORSE VERDICT. A pair where
  # one copy is answered and the other was never raised is not answered — merging toward the
  # rosier state is how a question disappears.
  function rank(s) {
    if (s == "UNRECOGNISED") return 6
    if (s == "UNRAISED")     return 5
    if (s == "RAISED")       return 4
    if (s == "MOOT")         return 3
    if (s == "ASSUMED")      return 2
    if (s == "ANSWERED")     return 1
    return 0
  }
  NF < 9 { next }
  # Pass 1: buffer, and index the ids sme-questions.md actually carries. The xref resolution
  # below needs that index, and awk cannot know it until the input is fully read.
  { n++; LINE[n] = $0; if ($3 ~ /sme-questions/) SMEQ[$2] = $8 }
  END {
    for (i = 1; i <= n; i++) {
      split(LINE[i], F, "\t")
      base = F[2]; qp = F[8]
      # An explicit "routed to sme-questions.md <id>" wins, but ONLY if that id really exists
      # in the sme file. A dangling reference must not merge a live question into nothing.
      if (F[10] != "" && (F[10] in SMEQ)) { base = F[10]; qp = SMEQ[F[10]] }
      k = base "|" qp
      if (!(k in seen)) { seen[k] = LINE[i]; cnt[k] = 1; continue }
      cnt[k]++
      split(seen[k], P, "\t")
      # Citation prefers the sme-questions.md origin — it is the surface a human reads —
      # and names both files so the merge is visible rather than a disappearance.
      orig = P[3]
      if (P[3] !~ /sme-questions/ && F[3] ~ /sme-questions/) orig = F[3] " + " P[3]
      else if (P[3] ~ /sme-questions/ && F[3] !~ /sme-questions/) orig = P[3] " + " F[3]
      if (rank(F[1]) > rank(P[1])) W = F[1]; else W = P[1]
      # Prefer whichever copy actually recorded a drafting position / a reason.
      asum = (P[6] != "") ? P[6] : F[6]
      qtext = (P[3] ~ /sme-questions/) ? P[5] : F[5]
      idout = (P[3] ~ /sme-questions/) ? P[2] : F[2]
      rawout = (rank(F[1]) > rank(P[1])) ? F[9] : P[9]
      rsn = (rank(F[1]) > rank(P[1])) ? F[7] : P[7]
      stg = (P[4]+0 < F[4]+0) ? P[4] : F[4]
      seen[k] = W "\t" idout "\t" orig "\t" stg "\t" qtext "\t" asum "\t" rsn "\t" qp "\t" rawout "\t"
    }
    for (k in seen) { split(seen[k], O, "\t"); printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%d\n", O[1],O[2],O[3],O[4],O[5],O[6],O[7],k,O[9],cnt[k] }
  }
' | sort -t"$(printf '\t')" -k4,4n -k2,2)

DUPES_COLLAPSED=$(printf '%s\n' "$DEDUPED" | awk -F'\t' 'NF>=10 && $10>1 {n+=$10-1} END{print n+0}')

# Stage filter: a gate must not pass on debt from an EARLIER stage either, so <= N.
if [ -n "$STAGE" ]; then
  FILTERED=$(printf '%s\n' "$DEDUPED" | awk -F'\t' -v s="$STAGE" 'NF>=9 && $4+0 <= s+0')
else
  FILTERED="$DEDUPED"
fi
FILTERED=$(printf '%s' "$FILTERED" | grep .)

count_state() { printf '%s\n' "$FILTERED" | awk -F'\t' -v w="$1" 'NF>=9 && $1==w{n++} END{print n+0}'; }
N_UNRAISED=$(count_state UNRAISED)
N_RAISED=$(count_state RAISED)
N_ANSWERED=$(count_state ANSWERED)
N_ASSUMED=$(count_state ASSUMED)
N_MOOT=$(count_state MOOT)
N_UNRECOGNISED=$(count_state UNRECOGNISED)
N_TOTAL=$(printf '%s\n' "$FILTERED" | awk -F'\t' 'NF>=9{n++} END{print n+0}')
N_BLOCKING=$((N_UNRAISED + N_UNRECOGNISED))

# ---------------------------------------------------------------------------
# Nothing examined is NOT clean. This is its own exit code so no caller can read a
# zero-question scan as a passing one.
# ---------------------------------------------------------------------------
NOTHING_EXAMINED=0
if [ "$BRD_COUNT" -eq 0 ] && [ "$SME_COUNT" -eq 0 ]; then NOTHING_EXAMINED=1; fi

# ---------------------------------------------------------------------------
# RE-CHECK: a new source arrived after these questions were answered.
#
# Post-mortem 2026-09-02, fix 5: "re-running every open question against each newly-read
# source, as standing procedure rather than when someone remembers." A question closed as
# ANSWERED or ASSUMED against the corpus-as-it-was is not closed against the corpus-as-it-is,
# and a negative answer ("no source describes the classification matrix") is the one most
# likely to be overturned by the file that just landed. The inventory
# (analysis/source-sufficiency.json) stamps `addedAt` on every row `init --refresh` appended;
# a row with `addedAt` and no disposition yet is a source nobody has read against anything.
# Advisory — the ledger blocks on the missing disposition; this names the questions to re-open.
# ---------------------------------------------------------------------------
RECHECK_SOURCES=""
RUBRIC_PATH=""
for cand in "$PROJECT_DIR/analysis/source-sufficiency.json"; do [ -f "$cand" ] && RUBRIC_PATH="$cand"; done
if [ -n "$RUBRIC_PATH" ] && command -v jq >/dev/null 2>&1; then
  RECHECK_SOURCES="$(jq -r '
    (.dispositions // []) as $d
    | [ (.inventory // [])[]
        | select(.addedAt != null)
        | . as $r
        | select( ([$d[] | (.path // .pattern)] | index($r.rel)) == null )
        | "\(.rel) (added \(.addedAt))" ]
    | .[]' "$RUBRIC_PATH" 2>/dev/null)"
fi
N_RECHECK_SOURCES=0
[ -n "$RECHECK_SOURCES" ] && N_RECHECK_SOURCES=$(printf '%s\n' "$RECHECK_SOURCES" | grep -c .)

if [ "$JSON" = "1" ]; then
  printf '%s\n' "$FILTERED" | awk -F'\t' 'NF>=9' | jq -R -s --argjson brds "$BRD_COUNT" \
    --argjson smes "$SME_COUNT" --argjson nothing "$NOTHING_EXAMINED" \
    --argjson dupes "${DUPES_COLLAPSED:-0}" --arg stage "$STAGE" --arg newsrc "$RECHECK_SOURCES" '
    split("\n") | map(select(length>0) | split("\t")) |
    map({state:.[0], id:.[1], origin:.[2], stage:(.[3]|tonumber), question:.[4],
         assumption:.[5], reason:.[6], rawStatus:.[8]}) as $qs |
    { examined: { brdFiles: $brds, smeQuestionFiles: $smes, nothingExamined: ($nothing==1),
                  stageFilter: (if $stage=="" then null else ($stage|tonumber) end),
                  duplicatesCollapsed: $dupes },
      counts: { total: ($qs|length),
                UNRAISED:     ($qs|map(select(.state=="UNRAISED"))|length),
                RAISED:       ($qs|map(select(.state=="RAISED"))|length),
                ANSWERED:     ($qs|map(select(.state=="ANSWERED"))|length),
                ASSUMED:      ($qs|map(select(.state=="ASSUMED"))|length),
                MOOT:         ($qs|map(select(.state=="MOOT"))|length),
                UNRECOGNISED: ($qs|map(select(.state=="UNRECOGNISED"))|length) },
      blocking: ($qs|map(select(.state=="UNRAISED" or .state=="UNRECOGNISED"))|length),
      recheck: { newSources: ($newsrc | split("\n") | map(select(length>0))),
                 questionsToRecheck: (if ($newsrc|length) > 0 then ($qs|map(select(.state=="ANSWERED" or .state=="ASSUMED" or .state=="RAISED"))|length) else 0 end) },
      questions: $qs }'
else
  echo "OPEN QUESTIONS — $PROJECT_DIR${STAGE:+ (stage <= $STAGE)}"
  echo "Examined: $BRD_COUNT BRD file(s), $SME_COUNT sme-questions file(s); ${DUPES_COLLAPSED:-0} duplicate(s) collapsed."
  if [ "$NOTHING_EXAMINED" = "1" ]; then
    echo ""
    echo "NOTHING EXAMINED — no *.brd.json and no analysis/sme-questions.md exist under this"
    echo "project. This is not a clean result; it is an absence of evidence. Zero questions"
    echo "found because zero sources were read."
    echo "(BRDs are discovered at <kb>/brd/*.brd.json, where <kb> is analysis/*/knowledge-base,"
    echo " analysis/knowledge-base, or knowledge-base. A BRD anywhere else is not read.)"
    exit 3
  fi
  echo "Counts: UNRAISED=$N_UNRAISED  RAISED=$N_RAISED  ANSWERED=$N_ANSWERED  ASSUMED=$N_ASSUMED  MOOT=$N_MOOT  UNRECOGNISED=$N_UNRECOGNISED  (total $N_TOTAL)"
  echo "Blocking (UNRAISED + UNRECOGNISED): $N_BLOCKING"
  if [ "$N_RECHECK_SOURCES" -gt 0 ]; then
    N_RC_Q=$(( N_ANSWERED + N_ASSUMED + N_RAISED ))
    echo ""
    echo "RE-CHECK: $N_RECHECK_SOURCES source file(s) arrived after these questions were answered and have"
    echo "  no disposition yet. Every ANSWERED/ASSUMED/RAISED question ($N_RC_Q) is open against them —"
    echo "  negative answers first (\"no source describes X\"). Read, then bin/source-ledger.sh mark:"
    printf '%s\n' "$RECHECK_SOURCES" | sed 's/^/    /'
  fi
  echo ""
  if [ "$N_BLOCKING" -eq 0 ]; then
    echo "Nothing to raise. Every question here has been put to the user."
    exit 0
  fi
  cat <<'HDR'
─────────────────────────────────────────────────────────────────────────────
PASTE THIS BATCH INTO THE CHAT. Then end the turn and wait.
Where a drafting position is shown, the user only has to confirm or overturn it.
─────────────────────────────────────────────────────────────────────────────
HDR
  echo ""
  echo "I have $N_BLOCKING open question(s) that have never been put to you. Several already"
  echo "have a drafting position I took to keep going — those are NOT settled decisions, and"
  echo "I need you to either confirm them or overturn them."
  echo ""
  printf '%s\n' "$FILTERED" | awk -F'\t' -v blk="$VOCAB_BLOCKING" '
    NF>=9 && ($1=="UNRAISED" || $1=="UNRECOGNISED") {
      n++
      printf "%d. %s\n", n, $5
      printf "   source: %s (%s, stage %s)\n", $3, $2, $4
      if ($6 != "") printf "   I ASSUMED (confirm or overturn): %s\n", substr($6,1,200)
      if ($1 == "UNRECOGNISED") printf "   ⚠ UNRECOGNISED status \"%s\" — %s\n", $9, $7
      else if ($9 != "__NO_VERDICT_COLUMN__" && $9 != "") printf "   recorded as: \"%s\"\n", substr($9,1,140)
      print ""
    }'
  cat <<'FTR'
Answer any subset. For anything you would rather I decide, say so explicitly — that
records as ASSUMED with your consent, which is a different thing from me deciding quietly.
FTR
fi

# Exit 3 must fire in BOTH output modes. It used to live only inside the human-output branch,
# so `--json` on a project with no BRDs and no sme-questions.md returned 0 — the exact
# false-green the code above says the exit code exists to prevent, available to every machine
# caller and unavailable to none of them. Found 2026-08-12 by the questions-report fixture,
# which trusted rc=3 and happily rendered an all-clear report for an empty directory.
[ "$NOTHING_EXAMINED" = "1" ] && exit 3
[ "$N_BLOCKING" -gt 0 ] && exit 1
exit 0
