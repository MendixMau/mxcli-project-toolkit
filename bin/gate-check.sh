#!/usr/bin/env bash
# Mechanical stage-gate checker — replaces "remember to self-check" with file-existence/grep checks.
#
# Always evaluates all stages (0-7). On a full informational run it also regenerates index.html in
# the project directory from the real results, so the dashboard can never silently drift from
# actual project state. A stage-specific run answers one question and writes nothing: that is the
# invocation used in agent loops and hooks, and a read-only query must leave no trace.
#
# Usage: bin/gate-check.sh [--html|--no-html] [--ack-protocol [--approved-in-chat]|--force-stale] [--verbose]
#                          [--adopt <stage> --reason "..."]
#                          [--waive <stage|obligation[/module]> --reason "..."]
#                          <project-dir> [stage]
#   - With a stage-number, additionally exits non-zero if that specific stage's check fails.
#   - Without one, evaluates and reports all stages, exits 0 regardless (informational run).
#   - --html forces the dashboard write; --no-html suppresses it. Neither changes any verdict.
#   - --ack-protocol shows what protocol changed, offers the diff, and records the new toolkit
#     commit in the decision register + docs/BUILD-LOG.md. Interactive only (see below).
#   - --strict-protocol (or MXTK_STRICT_PROTOCOL=1) restores BLOCKING on protocol staleness.
#     OFF by default: staleness notifies, it does not stop the run. Opt in for CI.
#   - --force-stale (or MXTK_ACK_STALE=1) proceeds past a --strict-protocol block and writes a
#     PROTOCOL-BYPASS line to docs/BUILD-LOG.md. Meaningless without --strict-protocol, which
#     is the point: with nothing blocking there is nothing to force.
#   - --adopt <stage> --reason "..." records that this project JOINED the toolkit at <stage>.
#     Every earlier stage then reports WAIVED instead of red, and never affects an exit code.
#   - --waive <stage> --reason "..." does the same for one stage — for work a project already
#     did its own way. Both write a line into the decision register and docs/BUILD-LOG.md;
#     --reason is required, because an unexplained skip is the thing gates exist to prevent.
#   - --waive <obligation>[/<module>] --reason "..." waives a PASS rather than a stage — the
#     rows in bin/lib/obligations.tsv (look, sweep, journeys, coherence). `look/Orders` waives
#     one module; bare `look` waives every module. Same flag and same mandatory reason on
#     purpose: a second waiver vocabulary is a second place to look and a second thing to keep
#     in step. A waived pass reports WAIVED with its reason — never PASS.
#
# VERDICT VOCABULARY (four, and the difference between the first two is the whole point):
#   PASS    — checked, and it holds.
#   PENDING — the artifact is not there at all. Nothing is wrong; nothing has been done yet.
#   FAIL    — something IS there and it is wrong, or a ✋ gate has artifacts but no sign-off.
#   WAIVED  — declared out of scope for this project, in writing, with a reason.
#   MANUAL  — not machine-checkable; a human must paste the evidence.
# Exit codes on a stage query: PASS/WAIVED 0, FAIL 1, MANUAL 2, PENDING 3. An informational
# run (no stage argument) still exits 0 regardless — it is a status report, not a verdict.

set -uo pipefail

# Options are collected before positionals so a project path containing spaces survives.
# The obvious `set -- $POSITIONAL` form word-splits the path and was rejected for that reason.
HTML_MODE="auto"
ACK_PROTOCOL=0
APPROVED_IN_CHAT=0
PROTOCOL_VERBOSE=0
FORCE_STALE="${MXTK_ACK_STALE:-0}"
STRICT_PROTOCOL="${MXTK_STRICT_PROTOCOL:-0}"
ADOPT_STAGE=""
WAIVE_STAGE=""
WAIVER_REASON=""
declare -a GC_ARGS
GC_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --html)    HTML_MODE="always" ;;
    --no-html) HTML_MODE="never" ;;
    --ack-protocol)    ACK_PROTOCOL=1 ;;
    --approved-in-chat) APPROVED_IN_CHAT=1 ;;
    --verbose)         PROTOCOL_VERBOSE=1 ;;
    --adopt)           shift; ADOPT_STAGE="${1:-}" ;;
    --waive)           shift; WAIVE_STAGE="${1:-}" ;;
    --reason)          shift; WAIVER_REASON="${1:-}" ;;
    --force-stale)     FORCE_STALE=1 ;;
    --strict-protocol) STRICT_PROTOCOL=1 ;;
    --)        shift; while [ $# -gt 0 ]; do GC_ARGS[${#GC_ARGS[@]}]="$1"; shift; done; break ;;
    --*)       echo "Error: unknown option '$1'." >&2; exit 2 ;;
    *)         GC_ARGS[${#GC_ARGS[@]}]="$1" ;;
  esac
  shift
done
set -- ${GC_ARGS[@]+"${GC_ARGS[@]}"}

if [ $# -lt 1 ]; then
  echo "Usage: $0 [--html|--no-html] <project-dir> [stage-number]" >&2
  exit 1
fi

# --- Escape hatches, for when the gate itself is the thing blocking the room -------------
#
# MXTK_SKIP_GATES=1 — return "no verdict" immediately and do no work at all. Added during a
# training round (2026-08-25) where gate-check took 5-15 minutes per invocation on participant
# machines that could not be reproduced here: on this Mac a full run is 1.9s empty / 7.8s on a
# real project, and the artifact tree walk — the previously known slow path, see the prune
# comment further down — costs 0.30s worst case over a 107k-file project.
#
# Exits 0 DELIBERATELY, including for a stage-specific run that would normally exit non-zero
# on failure. A skipped gate must not read as a failed one, and it must not wedge a caller
# that branches on the exit code. It is loud on stderr for the same reason the WAIVED verdict
# exists: a check nobody performed has to say so, every time, or it becomes green-by-absence.
#
# MXTK_NO_FETCH=1 — keep every gate, drop only the network. The protocol-freshness check runs
# `git fetch` against the toolkit remote on EVERY invocation (see TOOLKIT_REF below) over an
# HTTPS remote with no timeout, so a proxy that swallows packets or a credential prompt nobody
# is there to answer stalls the whole run. The fallback that this forces is already designed
# and already non-blocking: local HEAD, labelled UNVERIFIED. Prefer this over SKIP_GATES —
# it keeps the verdicts and only gives up the "is your toolkit current?" answer.
if [ "${MXTK_SKIP_GATES:-0}" = "1" ]; then
  echo "gate-check: SKIPPED — MXTK_SKIP_GATES=1 is set in this environment." >&2
  echo "  No stage was evaluated and no verdict was produced. This is NOT a pass." >&2
  echo "  Re-enable with: unset MXTK_SKIP_GATES" >&2
  exit 0
fi

PROJECT_DIR="$1"
REQUESTED_STAGE="${2:-}"

# Validate the stage argument BEFORE it is ever used as an array subscript.
# bash evaluates subscripts arithmetically, so RESULTS[Stage3] dereferences a
# variable named Stage3; under `set -u` that aborts the script mid-run, and the
# abort was observed exiting 0 — a typo'd stage silently forged a passing gate.
# A gate you can pass by misspelling is not a gate.
case "$REQUESTED_STAGE" in
  ""|P|p|0|1|2|3|4|5|6|7|build-ready) ;;
  *)
    echo "Error: unknown stage '$REQUESTED_STAGE'." >&2
    echo "Valid: P, 0-7, build-ready, or omit for an informational run." >&2
    exit 2
    ;;
esac

# --waive also accepts an OBLIGATION target (bin/lib/obligations.tsv): `look/Orders` for one
# module, `sweep` for every module. Same flag, same mandatory --reason, same register — a second
# waiver vocabulary would be a second place to look and a second thing to keep in step.
# --adopt stays stage-only: adoption is a statement about where the project joined the pipeline.
_gc_is_obligation() {
  local tsv; tsv="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/obligations.tsv"
  [ -f "$tsv" ] || return 1
  awk -F'\t' -v w="$(printf '%s' "${1%%/*}" | tr '[:upper:]' '[:lower:]')" \
      '!/^#/ && $1==w && $1!="obligation" {found=1} END{exit !found}' "$tsv"
}
for opt_pair in "--adopt:$ADOPT_STAGE" "--waive:$WAIVE_STAGE"; do
  opt_name="${opt_pair%%:*}"; opt_val="${opt_pair#*:}"
  [ -n "$opt_val" ] || continue
  case "$opt_val" in
    P|p|[0-7]) continue ;;
  esac
  if [ "$opt_name" = "--waive" ] && _gc_is_obligation "$opt_val"; then continue; fi
  if [ "$opt_name" = "--waive" ]; then
    echo "Error: --waive takes a stage (P or 0-7) or an obligation target, got '$opt_val'." >&2
    echo "Obligations (bin/lib/obligations.tsv): $(awk -F'\t' '!/^#/ && NF>=9 && $1!="obligation"{printf "%s ", $1}' \
      "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/obligations.tsv" 2>/dev/null)" >&2
    echo "  per module:  --waive look/Orders  --reason \"...\"" >&2
    echo "  every module: --waive look        --reason \"...\"" >&2
    exit 2
  fi
  echo "Error: $opt_name takes a stage (P or 0-7), got '$opt_val'." >&2; exit 2
done
if [ -n "$ADOPT_STAGE" ] && [ -n "$WAIVE_STAGE" ]; then
  echo "Error: --adopt and --waive do different things; run them one at a time." >&2
  exit 2
fi
# A skip with no reason is the failure mode gates exist to prevent, so the reason is not
# optional and there is no default. "Recorded via --adopt" would be a sentence that says nothing
# and would be written by whichever agent found the flag first.
if { [ -n "$ADOPT_STAGE" ] || [ -n "$WAIVE_STAGE" ]; } && [ -z "$WAIVER_REASON" ]; then
  echo "Error: --adopt/--waive require --reason \"why this project does not need it\"." >&2
  echo "It is written into the register and read back by everyone who sees the WAIVED row." >&2
  exit 2
fi

if [ ! -d "$PROJECT_DIR" ]; then
  echo "Error: project directory does not exist: $PROJECT_DIR" >&2
  exit 1
fi

# Resolve the knowledge-base dir the same way this project's artifacts actually live.
# Convention: analysis/<name>/knowledge-base/ under the project dir; fall back to
# knowledge-base/ directly under the project dir if that's how the project is laid out.
#
# All matches are collected, not just the first. The old loop `break`-ed on the
# first analysis/*/knowledge-base hit, so in a repo with two workstreams the one
# that sorts first won — and every stage verdict silently described that
# workstream. Observed in PROJECT-C: a dead 3-BRD workstream sorted ahead of
# the live 18-BRD one, so Stage 1 reported PASS and Stage 2 FAIL, both about the
# wrong project, for days. Worse, the PASS was pointing at a client extraction
# the run-sheet marks "do not open".
#
# With more than one workstream a single verdict is not just wrong, it is
# meaningless — so refuse rather than guess. $GATE_WORKSTREAM selects one.
KB_DIR=""
KB_MATCHES=""
KB_COUNT=0
for candidate in "$PROJECT_DIR"/analysis/*/knowledge-base; do
  [ -d "$candidate" ] || continue
  KB_MATCHES="${KB_MATCHES}  $candidate"$'\n'
  KB_COUNT=$((KB_COUNT + 1))
  KB_DIR="$candidate"
done

if [ "$KB_COUNT" -gt 1 ]; then
  if [ -n "${GATE_WORKSTREAM:-}" ]; then
    KB_DIR="$PROJECT_DIR/analysis/$GATE_WORKSTREAM/knowledge-base"
    if [ ! -d "$KB_DIR" ]; then
      echo "Error: GATE_WORKSTREAM='$GATE_WORKSTREAM' does not resolve to a knowledge-base dir." >&2
      echo "Available:" >&2
      printf '%s' "$KB_MATCHES" >&2
      exit 2
    fi
  else
    echo "Error: $KB_COUNT workstreams found under $PROJECT_DIR/analysis/:" >&2
    printf '%s' "$KB_MATCHES" >&2
    echo "A single gate verdict cannot describe more than one. Re-run with:" >&2
    echo "  GATE_WORKSTREAM=<name> $0 $*" >&2
    exit 2
  fi
fi

if [ -z "$KB_DIR" ]; then
  for candidate in "$PROJECT_DIR/analysis/knowledge-base" "$PROJECT_DIR/knowledge-base"; do
    if [ -d "$candidate" ]; then
      KB_DIR="$candidate"
      break
    fi
  done
fi

# Resolve the analysis base (the dir that holds architecture/, design/, build-plan, etc.).
# Projects using the documented analysis/<name>/ layout keep these UNDER that dir, not at root.
# Per-stage checks must look in both places or they false-FAIL on the toolkit's own default layout.
# ANALYSIS_BASE is the parent of the knowledge-base dir when that's nested (analysis/<name>/),
# else the project root.
ANALYSIS_BASE="$PROJECT_DIR"
if [ -n "$KB_DIR" ]; then
  kb_parent="$(dirname "$KB_DIR")"
  # Only treat it as a nested base if it's actually below the project root (analysis/<name>/).
  case "$kb_parent" in
    "$PROJECT_DIR") ANALYSIS_BASE="$PROJECT_DIR" ;;
    "$PROJECT_DIR"/*) ANALYSIS_BASE="$kb_parent" ;;
  esac
fi

# Return the first existing path among "<root>/<rel>" and "<analysis-base>/<rel>".
# Usage: resolve_artifact "architecture/build-plan.md" -> echoes the path, or empty if neither.
resolve_artifact() {
  local rel="$1" p
  for p in "$PROJECT_DIR/$rel" "$ANALYSIS_BASE/$rel"; do
    if [ -e "$p" ]; then echo "$p"; return 0; fi
  done
  echo ""
  return 1
}

# Resolve a per-stage SOURCE file (intake.md, triage.md) rather than a build artifact.
#
# resolve_artifact() deliberately prefers the ROOT copy — correct for artifacts, where a root
# build-plan.md really is the project's build plan. It is wrong for a stage source file, which
# is a hand-maintained document that gets forked and abandoned: on PROJECT-D the root holds
# a July-era scaffold with one unanswered question while analysis/PROJECT-D/intake.md holds eight
# real answers, and root-first grades the file nobody has touched. So a plain
# `resolve_artifact "intake.md"` is NOT the fix — it lands on exactly the same stale file.
#
# Echoes the resolved path, or the literal AMBIGUOUS when two DIFFERENT copies exist. Two
# differing copies is not a layout a single verdict can describe; one is stale and only a human
# knows which. Byte-identical copies are not ambiguous — either one grades the same. On a flat
# project both candidates are the same path and this is a no-op.
#
# MERGE NOTE: bug02 proposed this as a shared helper; gate-check-intake-patch.md proposed the
# same logic inlined in check_stage_P, arguing it keeps resolve_artifact's semantics from
# spreading. The helper won: check_stage_0 needs byte-identical behaviour, and an inline copy is
# how the two call sites would drift apart again. Wired into check_stage_0 by bug02's patch.
resolve_stage_file() {
  local rel="$1" root_f="$PROJECT_DIR/$1" base_f="$ANALYSIS_BASE/$1"
  if [ "$root_f" != "$base_f" ] && [ -f "$root_f" ] && [ -f "$base_f" ] \
     && ! cmp -s "$root_f" "$base_f"; then
    echo "AMBIGUOUS"
    return 1
  fi
  resolve_artifact "$rel"
}

# --- Decision register (PROJECT.md) --------------------------------------------
# Two BLOCKING checks (protocol freshness, BRD drift-sync), both ✋ decision gates and Stage 7
# read the decision register. They used to hardcode "$PROJECT_DIR/PROJECT.md".
#
# Calling resolve_artifact is NOT the fix: it tries the project root first, so on a project
# whose live register lives at analysis/<name>/PROJECT.md while an abandoned stub survives at
# the root, it lands on exactly the same blank file. Observed on PROJECT-D: root register =
# 7 CONFIRMED rows, ack 11eafdf (16 Jul); live register at analysis/PROJECT-D/PROJECT.md = 42
# CONFIRMED rows, ack 13b5445 (20 Jul). A drift gate that grades the abandoned register is
# worse than no drift gate — the live register's UNSYNCED markers are invisible to it and
# every gate goes green. Measured: the unpatched script exits 0 on `<that project> 4`.
#
# So: when two DIFFERENT candidate registers exist, REFUSE. Same stance, same shape, as the
# multi-workstream refusal above — a single verdict cannot describe two registers.
# Disambiguate persistently with a "Decision register" row in CLAUDE.local.md's ## Wiring
# table, or per-run with $GATE_REGISTER.
#
# MERGE NOTE (bug02 × resolve_stage_file): two reconciliations were needed here.
#   1. STANCE. resolve_stage_file() returns AMBIGUOUS and the owning stage prints one FAIL
#      row; the register refuses hard with exit 2. They differ deliberately: an ambiguous
#      intake.md poisons one stage line, an ambiguous register poisons the two BLOCKING
#      checks that gate EVERY stage plus three verdicts, and those print before any stage
#      row exists to carry the message. There is no row to put a FAIL in, so the run stops.
#   2. IDENTICAL COPIES. bug02's draft refused on count alone. Aligned with
#      resolve_stage_file() instead: byte-identical copies are not ambiguous, either one
#      grades the same, and refusing over them is pure cry-wolf. Only differing copies refuse.
REGISTER=""
REG_MATCHES=""
REG_COUNT=0
REG_FIRST=""
REG_DIFFER=0
# PROJECT-*.md siblings are candidates too (bug65). A project running two tracks against one
# directory keeps a second register next to the first — PROJECT.md + PROJECT-DAFNE.md. Without
# this term the sibling was never a CANDIDATE, so REG_COUNT stayed 1, REG_DIFFER stayed 0, the
# ambiguity path below never fired, and the run graded the primary track in silence. That is
# the failure this whole block exists to prevent, arriving through the one door left open.
# Adding the term needs no new mechanism: the sibling now differs from PROJECT.md, trips
# REG_DIFFER=1, and lands in the existing refusal-to-guess path, which blocks nothing and
# names both candidates and both remedies. $GATE_REGISTER still overrides, as before.
for candidate in "$PROJECT_DIR/PROJECT.md" "$PROJECT_DIR"/PROJECT-*.md "$PROJECT_DIR"/analysis/*/PROJECT.md; do
  [ -f "$candidate" ] || continue
  REG_MATCHES="${REG_MATCHES}  $candidate"$'\n'
  REG_COUNT=$((REG_COUNT + 1))
  if [ -z "$REG_FIRST" ]; then
    REG_FIRST="$candidate"
  elif ! cmp -s "$REG_FIRST" "$candidate"; then
    REG_DIFFER=1
  fi
  REGISTER="$candidate"
done
# With only identical copies, grade the first — deterministic, and every copy says the same.
[ "$REG_DIFFER" = "0" ] && REGISTER="$REG_FIRST"

# Explicit selection wins over any inference.
REG_SEL="${GATE_REGISTER:-}"
if [ -z "$REG_SEL" ] && [ -f "$PROJECT_DIR/CLAUDE.local.md" ]; then
  REG_SEL="$(awk -F'|' '
    /^## Wiring/ { w = 1; next }
    /^## / { w = 0 }
    w && /^\|/ && tolower($2) ~ /decision register/ {
      p = $3
      gsub(/`/, "", p)
      gsub(/^[ \t]+|[ \t]+$/, "", p)
      if (p != "") { print p; exit }
    }' "$PROJECT_DIR/CLAUDE.local.md")"
fi
if [ -n "$REG_SEL" ]; then
  case "$REG_SEL" in
    /*) REGISTER="$REG_SEL" ;;
    *)  REGISTER="$PROJECT_DIR/$REG_SEL" ;;
  esac
  if [ ! -f "$REGISTER" ]; then
    echo "Error: selected decision register does not exist: $REGISTER" >&2
    echo "Fix the 'Decision register' row in CLAUDE.local.md ## Wiring, or \$GATE_REGISTER." >&2
    exit 2
  fi
elif [ "$REG_DIFFER" = "1" ]; then
  # Two differing registers. This used to exit 2 and stop the run. It no longer does: nothing in
  # this script blocks a project over a condition the project's own author can resolve in one
  # line — see the staleness rationale further down. But it cannot GUESS either, because grading
  # the wrong register silently is exactly the defect this resolution was added to close.
  #
  # So it does the third thing: says it cannot evaluate, names both candidates and both remedies,
  # and lets every gate that does NOT depend on the register report normally. REGISTER stays
  # empty, so register-dependent verdicts degrade to a stated "cannot evaluate" rather than a
  # coin flip, and the exit code reflects the requested stage's own merits.
  REGISTER=""
  REG_AMBIGUOUS=1
  echo "⚠ $REG_COUNT differing decision registers (PROJECT.md) found under $PROJECT_DIR:"
  printf '%s' "$REG_MATCHES"
  echo "  Nothing is blocked, but the ✋ decision gates and BRD drift-sync cannot be evaluated"
  echo "  until one is named — whichever were graded would be a coin flip."
  echo "  A) Name it for this run:"
  echo "       GATE_REGISTER=<path-relative-to-project-dir> $0 $*"
  echo "  B) Name it permanently, in CLAUDE.local.md ## Wiring:"
  echo "       | Decision register | analysis/<name>/PROJECT.md | the live one; the other is superseded |"
  echo ""
fi
REG_AMBIGUOUS="${REG_AMBIGUOUS:-0}"

# ── WHERE DID THIS PROJECT JOIN, AND WHAT DOES ITS ENTRY MODE NOT RUN? ──────────────────────
#
# WHY THIS EXISTS (2026-08-20, customer round). gate-check evaluated P–7 against every project
# on earth, so two completely different situations arrived as the same wall of red:
#   1. a project that has not started a stage yet, and
#   2. a project that will never start it — it wired the toolkit in at build phase, or its entry
#      mode does not run that stage at all — so no amount of work will ever clear the row.
# (2) is the corrosive one: a permanent red for an artifact nobody intends to produce teaches
# the reader that the board is noise, and by then (1) and a REAL failure look identical too.
#
# The fix is not inference. "This project looks like it is past Stage 3, stay quiet" was tried
# on 2026-08-20 in its display-layer form and reverted the same day — see the long note above
# the stage loop. Position in the list cannot tell an empty stage from a broken one.
#
# So the toolkit's own rule applies, the one Stage 0 already states for triage rows: N/A IS AN
# ANSWER AND IT IS WRITTEN DOWN. A stage is skipped because the register says so, in a line a
# human put there with a reason attached — never because a script guessed. Two forms, both read
# from the decision register (the one place gate decisions live, per CLAUDE.md):
#
#     Adopted at stage: 5 — build was underway before the toolkit was wired in
#     Waived stage 2: analysis was done in Confluence; BRDs will not be regenerated
#
# plus the entry mode, which the runbook already treats as a recorded Stage-P decision:
#
#     Entry mode: greenfield
#
# Write them with `--adopt` / `--waive`, or by hand; both spellings are read the same way.
#
# WHAT A WAIVER MAY NOT DO — see waiver_applies() below. It may excuse a stage with nothing in
# it, and it may excuse an unsigned ✋ decision (that is the toolkit's own ritual, and a project
# that did the work elsewhere never had a reason to run it). It may NOT hide a stage whose
# artifacts exist and are inconsistent: "NOT clean, 14 findings outstanding" is a fact about the
# project, and no line in a register makes it stop being one.

# Rank orders the pipeline for "earlier than". P sorts before 0 — the numbers alone cannot.
stage_rank() { case "$1" in P|p) echo 0 ;; [0-7]) echo $(( $1 + 1 )) ;; *) echo 99 ;; esac; }

# reg_field <lowercased label> — value of the first "Label: value" line in the register.
# Tolerant of markdown decoration (>, *, -, bold) because these lines get written by hand.
reg_field() {
  [ -n "$REGISTER" ] && [ -f "$REGISTER" ] || return 1
  awk -v want="$1" '
    # Skip HTML comment blocks. A register can carry a commented-out example of exactly these
    # labels — the scaffold nearly shipped one — and a waiver read out of a comment would be
    # invisible to the person who wrote it and permanent for everyone after them.
    /<!--/ { incomment = 1 }
    incomment { if ($0 ~ /-->/) incomment = 0; next }
    { line = $0
      gsub(/^[ \t>*_-]+/, "", line); gsub(/\*/, "", line)
      i = index(line, ":"); if (i == 0) next
      key = tolower(substr(line, 1, i - 1)); gsub(/^[ \t]+|[ \t]+$/, "", key)
      if (key != want) next
      v = substr(line, i + 1); gsub(/^[ \t]+|[ \t]+$/, "", v)
      if (v != "") { print v; exit }
    }' "$REGISTER"
}

ADOPTED_AT=""; ADOPTED_REASON=""; WAIVED_LIST=""; WAIVED_REASON=""; ENTRY_MODE=""

# Dashes are split with parameter expansion, not a bracket expression: an em-dash inside a
# sed/awk character class is a multibyte trap on BSD userland, and these lines are hand-written
# by people who will use whichever dash their editor produces.
strip_lead_dash() { # strip_lead_dash <text> — drop a leading dash/colon and the space after it
  local t="$1"
  case "$t" in
    —*) t="${t#—}" ;; –*) t="${t#–}" ;; -*) t="${t#-}" ;; :*) t="${t#:}" ;;
  esac
  printf '%s' "$t" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}
split_reason() { # split_reason <text> — everything after the first dash separator, or nothing
  local t="$1"
  case "$t" in
    *—*) printf '%s' "${t#*—}" | sed 's/^[[:space:]]*//' ;;
    *–*) printf '%s' "${t#*–}" | sed 's/^[[:space:]]*//' ;;
    *" - "*) printf '%s' "${t#* - }" ;;
    *) printf '' ;;
  esac
}
split_head() { # split_head <text> — everything BEFORE the first dash separator
  local t="$1"
  case "$t" in
    *—*) printf '%s' "${t%%—*}" ;;
    *–*) printf '%s' "${t%%–*}" ;;
    *" - "*) printf '%s' "${t%% - *}" ;;
    *) printf '%s' "$t" ;;
  esac
}

POS_RAW="$(reg_field "adopted at stage" 2>/dev/null || true)"
if [ -n "$POS_RAW" ]; then
  ADOPTED_AT="$(printf '%s' "$POS_RAW" | awk '{print $1}' | tr -d '.,;')"
  ADOPTED_REASON="$(strip_lead_dash "$(printf '%s' "$POS_RAW" | sed 's/^[^ ]*[ ]*//')")"
  case "$ADOPTED_AT" in
    P|p|[0-7]) ;;
    *) echo "⚠ '$POS_RAW' in $REGISTER is not a stage this pipeline has — ignoring the adoption line." >&2
       ADOPTED_AT=""; ADOPTED_REASON="" ;;
  esac
fi

# Waivers, in two spellings. ONE LINE PER STAGE is what --waive writes and what the docs show,
# because a waiver is one stage's reason and a shared reason is a lie the moment a second stage
# is added for a different one (measured: two --waive runs nested "(was: …)" inside each other
# and relabelled the first stage with the second stage's reason):
#
#     Waived stage 6: QA runs in the client's own suite
#
# The aggregate spelling is still read — it is shorter to write by hand for a contiguous block,
# and projects that adopted it before the per-stage form existed must keep working:
#
#     Waived stages: 1, 2 — requirements came from the workshop deck
#
# Per-stage lines win where both name the same stage: they are the more specific statement.
WAIVED_REASONS=""   # newline-separated "STAGE<TAB>reason"
while IFS= read -r wline; do
  [ -n "$wline" ] || continue
  WAIVED_LIST="$WAIVED_LIST${wline%%	*} "
  WAIVED_REASONS="$WAIVED_REASONS$wline
"
done <<WAIVED_EOF
$(awk '
  /<!--/ { incomment = 1 }
  incomment { if ($0 ~ /-->/) incomment = 0; next }
  { line = $0
    gsub(/^[ \t>*_-]+/, "", line); gsub(/\*/, "", line)
    i = index(line, ":"); if (i == 0) next
    key = tolower(substr(line, 1, i - 1)); gsub(/^[ \t]+|[ \t]+$/, "", key)
    if (key !~ /^waived stage[ \t]+[p0-7]$/) next
    st = toupper(substr(key, length(key)))
    v = substr(line, i + 1); gsub(/^[ \t]+|[ \t]+$/, "", v)
    printf "%s\t%s\n", st, v
  }' "${REGISTER:-/dev/null}" 2>/dev/null)
WAIVED_EOF

POS_RAW="$(reg_field "waived stages" 2>/dev/null || true)"
if [ -n "$POS_RAW" ]; then
  WAIVED_REASON="$(split_reason "$POS_RAW")"
  WAIVED_LIST="$WAIVED_LIST$(split_head "$POS_RAW" | tr ',;' '  ' \
                 | awk '{ for (i=1;i<=NF;i++) if ($i ~ /^[Pp0-7]$/) printf "%s ", toupper($i) }')"
fi

waived_reason_for() { # waived_reason_for <STAGE> — the per-stage reason, else the aggregate one
  local st="$1" r
  r="$(printf '%s' "$WAIVED_REASONS" | awk -F'\t' -v s="$st" '$1 == s { print $2; exit }')"
  [ -n "$r" ] && { printf '%s' "$r"; return 0; }
  printf '%s' "$WAIVED_REASON"
}

# Entry mode: the register first (the runbook says it is recorded CONFIRMED there), then the
# intake answer, which is where it is actually decided and the only copy a young project has.
ENTRY_RAW="$(reg_field "entry mode" 2>/dev/null || true)"
if [ -z "$ENTRY_RAW" ]; then
  ENTRY_SRC="$(resolve_stage_file "intake.md")"
  if [ -n "$ENTRY_SRC" ] && [ "$ENTRY_SRC" != "AMBIGUOUS" ] && [ -f "$ENTRY_SRC" ]; then
    ENTRY_RAW="$(awk '
      /^##[ \t]*1\./ && tolower($0) ~ /entry mode/ { insec = 1; next }
      insec && /^##[ \t]/ { exit }
      insec { line = tolower($0); gsub(/^[ \t>*_-]+/, "", line)
              if (line ~ /^(answered|answer|a|decision|assumed)[ \t]*(\([^)]*\))?[ \t]*:/) { print line; exit } }
    ' "$ENTRY_SRC")"
  fi
fi
case "$(printf '%s' "$ENTRY_RAW" | tr '[:upper:]' '[:lower:]')" in
  *greenfield*)    ENTRY_MODE="greenfield" ;;
  *requirement*)   ENTRY_MODE="requirements-driven" ;;
  *migration*)     ENTRY_MODE="migration" ;;
esac

# stage_waiver <stage> — "<scope>|<reason>", or nothing. Most specific source of truth first.
#
# SCOPE MATTERS, and it is not decoration:
#   declared — a human wrote this stage off for this project, by name, with a reason. That is a
#              statement about the artifact, so it can also excuse an unsigned ✋ decision.
#   mode     — the entry mode says the stage does not run. That is a statement about the SHAPE of
#              the project, not about anything in it, so it excuses an EMPTY stage only. A
#              greenfield project that went and wrote a build-plan.md still needs to sign it off:
#              the plan is real, people will build from it, and "greenfield" never said otherwise.
stage_waiver() {
  local st="$1" w
  for w in $WAIVED_LIST; do
    if [ "$w" = "$(printf '%s' "$st" | tr '[:lower:]' '[:upper:]')" ]; then
      local r; r="$(waived_reason_for "$w")"
      printf 'declared|waived in %s%s\n' "$(basename "${REGISTER:-PROJECT.md}")" "${r:+ — $r}"
      return 0
    fi
  done
  # Adoption never waives Stage P. Intake is how the toolkit learns what the project IS, it costs
  # one conversation, and the adoption decision is itself a Stage-P answer. `--waive P` still can.
  if [ -n "$ADOPTED_AT" ] && [ "$st" != "P" ] && [ "$st" != "p" ] \
     && [ "$(stage_rank "$st")" -lt "$(stage_rank "$ADOPTED_AT")" ]; then
    printf 'declared|this project joined the toolkit at stage %s%s — the stage happened (or did not) before that, and is not required here\n' \
      "$ADOPTED_AT" "${ADOPTED_REASON:+: $ADOPTED_REASON}"
    return 0
  fi
  # Entry mode. The runbook's Entry Modes table already says these stages do not run; until now
  # the gate did not know that, so it demanded artifacts the runbook had excused.
  case "$ENTRY_MODE" in
    greenfield)
      case "$st" in
        1|2|3|4) printf 'mode|greenfield entry mode — stages 1–4 collapse into the plan the user already has (conversion-runbook.md → Entry Modes)\n'; return 0 ;;
      esac ;;
    requirements-driven)
      case "$st" in
        7) printf 'mode|requirements-driven entry mode — no legacy system to cut over from; if legacy data turns up, record a Stage-7 decision and this goes back to being checked (conversion-runbook.md → Entry Modes)\n'; return 0 ;;
      esac ;;
  esac
  return 1
}

# waiver_applies <scope> <status> <note> — may a waiver speak for THIS verdict?
#
#   PENDING                    yes, either scope. Nothing is there and nothing needs to be.
#   FAIL with a ✋, declared    yes. That marker is only ever emitted by the decision-row gates —
#                              artifacts present, no CONFIRMED row. It is the toolkit's own
#                              sign-off ritual, and a project that did the work elsewhere never
#                              ran it. KEEP THE ✋ IN THOSE MESSAGES: it is this branch's contract.
#   FAIL with a ✋, mode        no. See the scope note above stage_waiver().
#   FAIL otherwise             no. Something was examined and it was wrong, and no line in a
#                              register makes that stop being true.
#   PASS / MANUAL              no. A pass is better news than a waiver, and MANUAL wants evidence.
waiver_applies() {
  case "$2" in
    PENDING) return 0 ;;
    FAIL)    [ "$1" = "declared" ] || return 1
             case "$3" in *✋*) return 0 ;; esac; return 1 ;;
  esac
  return 1
}

# The pre-12828e4 Q9 body. gate-check NEVER rewrites it — the repair lives in
# sync-project.sh --repair-intake, which rewrites only when the section is byte-identical to
# this text. The hint below is therefore printed only on a byte-identical match, so the command
# it offers is one that will actually succeed and cannot lose an edited answer.
q9_stale_scaffold_text() {
  cat <<'EOF'
## 9. Interview mode: attended (default) or unattended?

Attended unless the user explicitly says otherwise. Attended = every gate question is asked
in chat and the agent waits for the answer. Unattended (opt-in only) = recommended options
are applied as ASSUMED and questions are logged in PROJECT.md for later reconciliation.
EOF
}

# Print the "## 9." section, trailing blank lines stripped.
q9_section() {
  awk '/^## 9\./{insec=1} insec && /^## /&&!/^## 9\./{insec=0} insec{print}' "$1" \
    | awk '{a[NR]=$0} END{last=NR; while(last>0 && a[last]~/^[ \t]*$/) last--; for(i=1;i<=last;i++) print a[i]}'
}

check_stage_P() {
  local f
  f="$(resolve_stage_file "intake.md")"
  if [ "$f" = "AMBIGUOUS" ]; then
    echo "FAIL|two different intake.md files — $PROJECT_DIR/intake.md and $ANALYSIS_BASE/intake.md — a single Stage P verdict cannot describe both; delete or merge the stale one (the analysis/<name>/ copy is normally the live one) and re-run"
    return
  fi
  if [ -z "$f" ] || [ ! -f "$f" ]; then
    echo "PENDING|intake.md not found (looked in $PROJECT_DIR/ and $ANALYSIS_BASE/) — the kickoff interview has not started; bin/init-project.sh scaffolds it"
    return
  fi

  # Every "## " question section must carry an answer MARKER at the start of a line.
  #
  # The old test was an unanchored, case-sensitive substring search for "Answered" or
  # "Unverified" anywhere in the section, and it was wrong in BOTH directions:
  #   - "- Status: Not Answered" PASSED, because it contains "Answered";
  #   - a bare "Unverified." PASSED without the how-to-verify clause the FAIL message promises;
  #   - a lowercase "answered: ..." FAILED;
  #   - a real prose answer with no marker FAILED (see the known limitation below).
  #
  # MERGE NOTE — two anchored matchers were proposed and they disagree:
  #   * gate-check-intake-patch.md: case-SENSITIVE, exactly two words (Answered|Unverified), no
  #     colon required. Its argument, recorded because it is a good one: the accepted vocabulary
  #     is a runbook decision, not a script decision, and should change in the template preamble
  #     and the runbook together. It lost anyway, on two measured facts — case-sensitivity
  #     reproduces the false-FAIL on a lowercase "answered:" (bug01 §"Adjacent finding"), and
  #     accepting a bare "Unverified" keeps the FAIL message a lie.
  #   * bug03: case-insensitive, five markers, an optional parenthetical qualifier, a required
  #     colon, and "Unverified" only counts when the line also says how to verify. Chosen.
  # The qualifier branch is NOT cosmetic: PROJECT-A and PROJECT-E both write
  # "Answered (CONFIRMED):", and bug03's first draft turned both projects red by rejecting it.
  # That form is a real workspace convention and any future tightening must keep accepting it.
  #
  # GATE_INTAKE_LOOSE=1 (an escape hatch in gate-check-intake-patch.md) is deliberately NOT
  # carried over: it restores the substring match, under which "- Status: Not Answered" passes
  # again — the single worst false-green this change exists to close. The merged matcher is far
  # wider than the one that hatch was written to soften, so the migration case it covered is
  # mostly gone; a project that still needs it should widen the marker list here, in the open.
  local bad total
  bad=$(awk '
    function flush(){ if (insec && !ok) { bad = bad sep title; sep = "; " } }
    /^##[ \t]/ { flush(); insec=1; ok=0; title=$0; sub(/^##[ \t]*/,"",title); next }
    insec {
      line=$0
      gsub(/^[ \t>*_-]+/,"",line); gsub(/\*/,"",line)
      l=tolower(line)
      if (l ~ /^(answered|answer|a|decision|assumed)[ \t]*(\([^)]*\))?[ \t]*:/) ok=1
      else if (l ~ /^unverified/ && l ~ /how to verify/) ok=1
    }
    END { flush(); print bad }' "$f")
  total=$(grep -c '^##[ \t]' "$f")

  # Always name the file that was graded. A Stage P line that does not is what let the
  # wrong-file bug survive for weeks: the output was locally coherent and globally wrong.
  local where=" [$f]"

  # If the offending section is the untouched pre-12828e4 Q9 boilerplate, name the repair.
  # Detection is by the gate's OWN criterion (it landed in $bad), so it cannot drift away from
  # what is graded; the byte comparison only decides whether the offered command is safe.
  local hint="" q9_a q9_b
  case "$bad" in
    *9.*)
      q9_a=$(mktemp "${TMPDIR:-/tmp}/q9a.XXXXXX") || q9_a=""
      q9_b=$(mktemp "${TMPDIR:-/tmp}/q9b.XXXXXX") || q9_b=""
      if [ -n "$q9_a" ] && [ -n "$q9_b" ]; then
        q9_section "$f" > "$q9_a"
        q9_stale_scaffold_text > "$q9_b"
        if cmp -s "$q9_a" "$q9_b"; then
          hint=" — Q9 is the untouched pre-12828e4 scaffold text, which can never pass this gate; it is byte-identical to the old template so replacing it loses nothing: bin/sync-project.sh $PROJECT_DIR --repair-intake"
        fi
        rm -f "$q9_a" "$q9_b"
      fi
      ;;
  esac

  if [ "$total" -eq 0 ]; then
    echo "FAIL|intake.md has no '## ' question sections$where"
  elif [ -z "$bad" ]; then
    echo "PASS|all $total intake questions carry an answer marker$where"
  else
    echo "FAIL|unanswered section(s) in $f: $bad — each '## ' section needs a line STARTING with 'Answered:' (Answer:/A:/Decision:/Assumed: also accepted, and a qualifier such as 'Answered (CONFIRMED):' is fine), or 'Unverified — how to verify: …'$hint"
  fi
}

check_stage_0() {
  # MERGE NOTE: bug02 supplies the resolver (root-first resolve_artifact grades the abandoned
  # copy on a nested-layout project), bug03 supplies the anchored sign-off test. They touch
  # different halves of this function and both are applied.
  local f
  f="$(resolve_stage_file "triage.md")"
  if [ "$f" = "AMBIGUOUS" ]; then
    echo "FAIL|two different triage.md files — $PROJECT_DIR/triage.md and $ANALYSIS_BASE/triage.md — a single Stage 0 verdict cannot describe both; delete or merge the stale one (the analysis/<name>/ copy is normally the live one) and re-run"
    return
  fi
  if [ -z "$f" ] || [ ! -f "$f" ]; then
    echo "PENDING|triage.md not found (looked in $PROJECT_DIR/ and $ANALYSIS_BASE/) — Stage 0 has not started"
    return
  fi
  # Two INDEPENDENT greps used to satisfy this: `grep -q "^## Sign-off" && grep -q "Confirmed
  # by:"`. The "Confirmed by:" line did not have to be inside ## Sign-off — or anywhere near
  # it; a quoted email or a code fence sufficed — and its VALUE was never inspected, so the
  # unedited template line "Confirmed by: [user] on [date]" passed a human-sign-off gate.
  # Now the line must live INSIDE the section AND carry a filled-in value.
  local signer
  signer=$(awk '
    /^##[ \t]+Sign-off/ { insec=1; next }
    insec && /^##[ \t]/ { exit }
    insec && tolower($0) ~ /confirmed by:/ {
      v=$0; sub(/^.*[Cc]onfirmed by:[ \t]*/,"",v)
      gsub(/^[ \t]+|[ \t]+$/,"",v); gsub(/\*/,"",v)
      print v; exit
    }' "$f")
  if [ -z "$signer" ]; then
    echo "FAIL|no non-empty 'Confirmed by:' line inside the '## Sign-off' section of $f — anything the user actually said is enough (\"confirmed in chat\", \"agreed, move on\"); it only has to not be the shipped placeholder"
  elif printf '%s' "$signer" | grep -q '\['; then
    echo "FAIL|'Confirmed by:' still holds the shipped placeholder: \"$signer\" — replace it with whatever the user actually said (\"confirmed in chat 2026-08-20\" is fine; a full name is not required) ($f, ## Sign-off)"
  else
    echo "PASS|triage.md signed off by \"$signer\" [$f]"
  fi
}

check_stage_1() {
  if [ -z "$KB_DIR" ]; then
    # An entry-mode-blind message here sent a real requirements-driven session looking for an
    # extractor it was never going to run (2026-08-20). "No knowledge-base directory" is true in
    # every mode; what to DO about it is not, and the KB for a document corpus is built by a
    # skill, not a pipeline. Name both routes rather than assuming the migration one.
    echo "PENDING|no knowledge-base directory yet — migration: run the extraction pipeline; requirements-driven: build the KB from the document corpus per skills/kb-generation.md (Path B). Either way it lands at analysis/<source>/knowledge-base/"
    return
  fi
  local report="$KB_DIR/extraction-report.html"
  if [ ! -f "$report" ]; then
    echo "PENDING|$report not written yet — run bin/extraction-report.sh <project-root>. It renders whatever the knowledge base holds, code-extracted or document, so this is the same command in every entry mode"
    return
  fi
  if [ ! -s "$report" ]; then
    echo "FAIL|$report exists but is empty — an extraction ran and produced nothing readable"
    return
  fi
  local kb_md="$KB_DIR/share/KB.md"
  if [ -f "$kb_md" ] && [ ! -s "$kb_md" ]; then
    echo "FAIL|share/KB.md exists but is empty"
    return
  fi

  # --- Scope-out (CAC-1b) is a SKILL, not a check here. Deliberate; read before re-adding. -----
  #
  # A blocking scope gate lived here for part of 2026-08-20 and was removed the same day. What it
  # tested was whether a `CONFIRMED` row existed in the register — i.e. whether a string was
  # present in a markdown file. An agent can write that string without asking anyone, so the gate
  # could not distinguish "the scope conversation happened" from "the row got typed", which is the
  # only thing it was there to distinguish. skills/skills-over-scripts.md, row 4 of its test table:
  # "check that X is filled in" → write the sentence, stop.
  #
  # The real defect the gate was reaching for is real: extraction on a customer round reached far
  # past the subsystems under discussion, and no later gate notices, because every later gate
  # measures whether the extraction is GOOD, never whether it is the RIGHT one. Validation-clean
  # BRDs for capabilities nobody asked for pass Stage 2, pass coverage-check, and surface during
  # the build.
  #
  # That is fixed upstream of here, by wiring: CAC-1 and CAC-1b are now named in
  # conversion-runbook.md's stage matrix, so a session running any entry mode loads them. Before
  # 2026-08-20 CAC-1 was reachable only from migration-pipeline.md, so requirements-driven and
  # greenfield sessions fired no checkpoint at all and went into extraction with no agreed scope.
  # The wiring is what fixes it; the exit code added nothing on top.
  #
  # Recovery when the conversation was skipped anyway is also a skill, not a gate:
  # skills/checkpoints/checkpoint-extraction.md holds it late, with the extraction report as its
  # input instead of the triage map — better input, since you can see what actually came out.
  echo "PASS|extraction-report.html present and non-empty$( [ -f "$kb_md" ] && echo ", KB.md present and non-empty")"
}

check_stage_2() {
  if [ -z "$KB_DIR" ]; then
    echo "PENDING|no knowledge-base directory yet — Stage 1 has not produced one"
    return
  fi
  local brd_dir="$KB_DIR/brd"
  if [ ! -d "$brd_dir" ] || [ -z "$(find "$brd_dir" -maxdepth 1 -name '*.brd.json' -print -quit 2>/dev/null)" ]; then
    echo "PENDING|no brd/*.brd.json scaffolds yet"
    return
  fi
  local validation="$KB_DIR/reports/validation-report.md"
  if [ ! -f "$validation" ]; then
    echo "PENDING|reports/validation-report.md not written yet — the BRDs have not been validated"
    return
  fi
  # Anchored and section-aware. `grep -A2 … | grep -qi clean` matched "clean" ANYWHERE in the
  # three-line window after the header, case-blind and in any polarity, so a report reading
  # "NOT clean, 14 findings outstanding" PASSED Stage 2 — and the verdict text then asserted
  # "Stop condition is Clean", i.e. the dashboard denied the gap rather than merely missing it.
  # Now: take the FIRST non-empty line of the "## Stop condition" section, strip markdown
  # decoration, and require it to START with "clean". Echo the line back so a failure is
  # diagnosable without opening the file.
  local first
  first=$(awk '
    /^##[ \t]+Stop condition/ { insec=1; next }
    insec && /^##[ \t]/       { exit }
    insec {
      line=$0
      gsub(/^[ \t>*_-]+/,"",line); gsub(/[ \t]+$/,"",line); gsub(/\*/,"",line)
      if (line == "") next
      print line; exit
    }' "$validation")
  if [ -z "$first" ]; then
    echo "FAIL|'## Stop condition' section not found or empty in $validation"
    return
  fi
  case "$(printf '%s' "$first" | tr '[:upper:]' '[:lower:]')" in
    clean|clean[^a-z0-9]*)
      echo "PASS|brd/*.brd.json present, Stop condition reads \"$first\"" ;;
    *)
      echo "FAIL|'## Stop condition' in $validation reads \"$first\" — it must START with \"Clean\"; a report that merely contains the word (\"NOT clean, 14 findings\") is not a clean stop" ;;
  esac
}

# ✋ stages need a CONFIRMED decision row in PROJECT.md's Decisions table
# (| Stage | Decision | Status | Notes |) — artifacts alone don't pass a hard gate.
# Matches a whole table FIELD equal to CONFIRMED, never a substring of the row.
# The old pattern was `.*CONFIRMED`, which UNCONFIRMED and "NOT CONFIRMED" both
# satisfy — a row explicitly marked as not decided passed the ✋ hard gate. The
# gate whose entire purpose is "ASSUMED does not pass" was passable by a row
# that said so in the status column.
# Any field may hold the status (column order varies by project); the field must
# equal CONFIRMED exactly after trimming, so UNCONFIRMED no longer qualifies.
# When two differing registers exist, REGISTER is deliberately empty and this cannot answer.
# Callers must ask reg_unavailable() FIRST and report MANUAL — "no CONFIRMED decision found" would
# be a false negative dressed as a verdict, which is the failure this whole wave is about.
# --- Artifact search, without crawling the whole Mendix project ----------------------------
#
# WHY THIS EXISTS (2026-08-20). Four checks searched for toolkit artifacts with a bare
# `find "$PROJECT_DIR" …  -print -quit`. `-print -quit` bails on the FIRST MATCH — so the cost
# was invisible while developing against a project that had the artifact, and unbounded on one
# that did not. Find only knows there is no match once it has walked every last inode.
#
# The projects that do not have the artifact are, precisely, the ones early in the pipeline. So
# a Stage 0/1 project paid a full recursive crawl of a Mendix app root — deployment/,
# mprcontents/, theme-cache/, javasource/, userlib/, .git/, and sources/, which holds the
# client's entire legacy codebase because that is what sources/ is for. Reported as
# "gate-check was hanging" from a Windows customer round; under Git Bash, where each stat
# crosses a translation layer, "slow" and "hung" are the same observation.
#
# Toolkit artifacts live in a handful of shallow, known places. None of them is ever inside a
# Mendix build directory or the source drop, so pruning costs no coverage. Deliberately NOT
# pruned: `modules` and `resources`, because `*/architecture/modules/*-brief.md` is a real
# search path and a name-prune cannot tell that dir from the Mendix one.
MXTK_PRUNE_DIRS='.git .svn .hg node_modules deployment mprcontents theme-cache themesource
                 javasource javascriptsource mlsource userlib widgets theme .mendix-cache
                 .mendix .vscode sources'

# find_artifact <find-expression...> — same semantics as `find "$PROJECT_DIR" <expr> -print -quit`,
# minus the dead weight. Prints the first match, or nothing.
find_artifact() {
  local prune=() d first=1
  for d in $MXTK_PRUNE_DIRS; do
    if [ "$first" = 1 ]; then prune+=( -name "$d" ); first=0
    else prune+=( -o -name "$d" ); fi
  done
  find "$PROJECT_DIR" \( "${prune[@]}" \) -prune -o \( "$@" \) -print -quit 2>/dev/null
}

# advise <key> <message> — print an advisory the FIRST time this project sees it, then never again.
#
# For things worth saying once and not worth repeating: Stage 0/1 incompleteness, which is
# ordinary on a young project and stops being news immediately. A warning printed on every run
# is indistinguishable from noise by the third run, and the whole point of demoting these from
# blocking gates was to stop the tool nagging people who have decided to move on.
#
# State lives in .claude/, alongside the existing .guide-shown sentinel and gitignored for the
# same reason. Writing it is the one exception to "a stage query must not dirty the working
# tree": the alternative is not remembering, and not remembering is the nagging.
#
# Keys are per-advisory, so signing triage.md later does not resurrect an unrelated advisory,
# and clearing the file (or deleting .claude/.gate-advisories) makes them all show once more.
advise() {
  local key="$1" msg="$2" state="$PROJECT_DIR/.claude/.gate-advisories"
  if [ -f "$state" ] && grep -qxF "$key" "$state" 2>/dev/null; then
    return 0
  fi
  echo "" >&2
  echo "⚠ $msg" >&2
  echo "  Advisory only — Stages 0 and 1 do not block. Shown once; re-run with an empty" >&2
  echo "  $state to see it again." >&2
  mkdir -p "$PROJECT_DIR/.claude" 2>/dev/null || return 0
  printf '%s\n' "$key" >> "$state" 2>/dev/null || true
}

reg_unavailable() {
  [ "$REG_AMBIGUOUS" = "1" ] && return 0
  return 1
}
reg_unavailable_note() {
  echo "MANUAL|cannot evaluate: $REG_COUNT differing decision registers exist and none is named — see the ⚠ notice above; set GATE_REGISTER or add the CLAUDE.local.md ## Wiring row"
}

has_confirmed_decision() {
  local stage="$1"
  local f="$REGISTER"
  [ -n "$f" ] && [ -f "$f" ] || return 1
  awk -F'|' -v want="$stage" '
    /^\|/ {
      s = $2
      gsub(/^[ \t]+|[ \t]+$/, "", s)
      sub(/^[Ss]tage[ \t]*/, "", s)
      if (s != want) next
      for (i = 3; i <= NF; i++) {
        f = toupper($i)
        gsub(/^[ \t]+|[ \t]+$/, "", f)
        # Word-anchored, not string-exact. Projects routinely write the status as
        # "CONFIRMED 2026-07-21" — status plus an inline date in one cell — and the
        # string-exact test reported "no Stage-3/Stage-4 CONFIRMED decision" over a
        # register holding eight of them (TFC-TCXGraphPOC, logged there as TD-07).
        # The project's own response was to treat a real gate FAIL as known-false and
        # stop reading it, which is precisely the habit gates exist to prevent.
        #
        # Still anchored at the START of the FIELD, so what d8117be bought is kept:
        # a Notes cell that merely mentions the word ("groundwork, not confirmed
        # yet") does not qualify, and neither does "NOT CONFIRMED". What this newly
        # admits is a field that BEGINS with CONFIRMED and then continues — which is
        # the convention it exists to accept.
        if (f ~ /^CONFIRMED([ \t]|$)/) found = 1
      }
    }
    END { exit !found }
  ' "$f"
}

check_stage_3() {
  local fit_gap design_system
  fit_gap="$(resolve_artifact "architecture/fit-gap.md")"
  design_system="$(resolve_artifact "design/design-system.html")"
  if [ -z "$fit_gap" ] || [ -z "$design_system" ]; then
    echo "PENDING|not started — missing $( [ -z "$fit_gap" ] && echo "architecture/fit-gap.md ")$( [ -z "$design_system" ] && echo "design/design-system.html")"
    return
  fi
  # Wireframes are load-bearing: ui-preflight-pages.md starts from them and the build
  # loop verifies built pages against them. A design system without wireframes is half
  # the Stage-3 deliverable (design-artifacts.md Step 3, one per screen).
  local wireframes_dir
  wireframes_dir="$(resolve_artifact "design/wireframes")"
  if [ -z "$wireframes_dir" ] || [ -z "$(find "$wireframes_dir" -maxdepth 1 -name '*.html' -print -quit 2>/dev/null)" ]; then
    echo "PENDING|design/wireframes/*.html missing — design system exists but no wireframes (design-artifacts.md Step 3); the mdl-agent's UI pre-flight cannot run without them"
    return
  fi
  # The architecture track must arrive at the ✋ gate as HTML too (architecture-blueprint.md
  # Step 7): blueprint.html is the generated checkpoint render — markdown stays canonical,
  # but a missing or stale render means the gate reviews raw Mermaid or an outdated picture.
  local blueprint_html
  blueprint_html="$(resolve_artifact "architecture/blueprint.html")"
  if [ -z "$blueprint_html" ]; then
    echo "PENDING|architecture/blueprint.html missing — the Stage-3 checkpoint render (architecture-blueprint.md Step 7); regenerate it from blueprint.md"
    return
  fi
  local arch_base
  arch_base="$(dirname "$blueprint_html")"
  local src
  for src in "$arch_base/blueprint.md" "$arch_base/fit-gap.md" "$arch_base/open-issues.md"; do
    if [ -f "$src" ] && [ "$blueprint_html" -ot "$src" ]; then
      echo "FAIL|architecture/blueprint.html is older than $(basename "$src") — stale render at a sign-off gate; regenerate (architecture-blueprint.md Step 7)"
      return
    fi
  done
  if reg_unavailable; then reg_unavailable_note; return; fi
  if has_confirmed_decision 3; then
    echo "PASS|fit-gap, blueprint render, design system, wireframes present and a Stage-3 CONFIRMED decision is in $REGISTER"
  else
    echo "FAIL|artifacts exist but ${REGISTER:-PROJECT.md} has no Stage-3 CONFIRMED decision — ✋ gate: artifacts without an interview don't pass"
  fi
}

check_stage_4() {
  local build_plan
  build_plan="$(resolve_artifact "architecture/build-plan.md")"
  if [ -z "$build_plan" ]; then
    echo "PENDING|architecture/build-plan.md not written yet"
    return
  fi
  if reg_unavailable; then reg_unavailable_note; return; fi
  if has_confirmed_decision 4; then
    echo "PASS|build-plan.md present and a Stage-4 CONFIRMED decision is in $REGISTER"
  else
    echo "FAIL|build-plan.md exists but ${REGISTER:-PROJECT.md} has no Stage-4 CONFIRMED decision — ✋ gate: a plan nobody approved doesn't pass"
  fi
}

check_stage_6() {
  local f test_ok="" review_ok=""
  for f in "$PROJECT_DIR/test-report.html" "$PROJECT_DIR"/reports/test-report.html \
           "$ANALYSIS_BASE/test-report.html" "$ANALYSIS_BASE"/reports/test-report.html; do
    [ -s "$f" ] && test_ok=1
  done
  # The harness's own surface also satisfies the test half: verify-module.sh's final render
  # rung produces docs/verification/report.html from docs/report.json (report-render.js /
  # report-normalize.js). Both halves must be present — the HTML is rendered FROM the JSON,
  # and accepting one without the other would accept a surface whose machine half is gone.
  # Before this, test-report.html was the only accepted name and nothing in the toolkit
  # generated it, so Stage 6 was structurally unpassable (improvement-plan Finding 14 / P9).
  if [ -s "$PROJECT_DIR/docs/verification/report.html" ] && [ -s "$PROJECT_DIR/docs/report.json" ]; then
    test_ok=1
  fi
  # module-review.md report — any non-empty dated report under a ui-reviews/ dir
  if [ -n "$(find_artifact -path '*/ui-reviews/ui-review-*.html' -size +0c)" ]; then
    review_ok=1
  fi
  if [ -z "$test_ok" ]; then
    echo "PENDING|no test surface yet — need test-report.html (project root or reports/), or docs/verification/report.html + docs/report.json (verify-module.sh's render rung)"
    return
  fi
  if [ -z "$review_ok" ]; then
    echo "PENDING|test surface present but no module-review report (ui-review-*.html under a ui-reviews/ dir) — Stage 6 requires the full-app module-review.md pass, zero open P1"
    return
  fi
  echo "PASS|test surface (test-report.html, or docs/verification/report.html + docs/report.json) + module-review report both present"
}

check_stage_7() {
  # MERGE NOTE: bug02 changes WHICH register is read, bug03 changes WHICH ROWS in it count.
  # Orthogonal; both applied.
  if reg_unavailable; then reg_unavailable_note; return; fi
  local f="$REGISTER"
  if [ -z "$f" ] || [ ! -f "$f" ]; then
    echo "PENDING|no decision register (PROJECT.md) under $PROJECT_DIR — nothing to read a cutover decision from"
    return
  fi
  # Field-exact on the STATUS (as has_confirmed_decision already is, since d8117be) and now
  # also column-aware on ROW SELECTION. `tolower($0) ~ /cutover/` scanned the whole row
  # including the free-text Notes cell, so an unrelated CONFIRMED row whose notes said
  # "groundwork for the eventual cutover" passed Stage 7 — the ✋ gate whose stated purpose is
  # "ASSUMED does not pass". A row qualifies only if it IS the cutover decision: stage field
  # (col 2) equal to 7, or the decision field (col 3) naming the cutover. Distinguish "no such
  # row" from "row present but not CONFIRMED" — they need different fixes.
  local verdict rows
  verdict=$(awk -F'|' '
    /^\|/ {
      s=$2; gsub(/^[ \t]+|[ \t]+$/,"",s); sub(/^[Ss]tage[ \t]*/,"",s)
      d=(NF>=3)?tolower($3):""
      if (s != "7" && d !~ /cutover/) next
      rows++
      for (i=2;i<=NF;i++){ v=toupper($i); gsub(/^[ \t]+|[ \t]+$/,"",v); if (v=="CONFIRMED") found=1 }
    }
    END { print (found?"PASS":"FAIL") " " rows+0 }' "$f")
  rows="${verdict#* }"
  if [ "${verdict%% *}" = "PASS" ]; then
    echo "PASS|a Stage-7/cutover decision row in $f has Status exactly CONFIRMED ($rows candidate row(s))"
  elif [ "$rows" = "0" ]; then
    echo "PENDING|no cutover decision row in $f — add a Decisions row whose Stage field is 7 (or whose Decision names the cutover) with Status exactly CONFIRMED"
  else
    echo "FAIL|$rows cutover decision row(s) in $f, none with a field exactly CONFIRMED (✋ gate — UNCONFIRMED/ASSUMED does not pass)"
  fi
}

check_stage_manual() {
  echo "MANUAL|not file-existence-checkable — fill in status manually"
}

# Pre-build readiness: everything that must be wired before Stage 5 build starts.
# Prints a checklist and returns non-zero if ANY item fails (reports all, not first-fail).
check_build_ready() {
  local fails=0 f found
  echo "Build-ready check for: $PROJECT_DIR"
  echo ""

  # 1. Project wired: CLAUDE.local.md with a Wiring block
  if [ -f "$PROJECT_DIR/CLAUDE.local.md" ] && grep -q "## Wiring" "$PROJECT_DIR/CLAUDE.local.md"; then
    echo "  ✓ CLAUDE.local.md present with a ## Wiring block"
  else
    echo "  ✗ no CLAUDE.local.md with a ## Wiring block — run bin/init-project.sh or bin/sync-project.sh"
    fails=$((fails+1))
  fi

  # 2. Baseline routing includes the UI-quality skills (not the pre-audit table)
  # Test ui-preflight-pages, NOT module-review — same fix as bin/sync-project.sh §2c.
  # The Wiring block that init/sync GENERATE contains the literal "module-review.md" in
  # its "UI review reports" row, so grepping for that string made this check satisfied by
  # the installer's own output: a project with zero real baseline routing passed.
  # ui-preflight-pages.md appears only in a genuine Baseline routing table.
  if grep -q "ui-preflight-pages" "$PROJECT_DIR/CLAUDE.local.md" 2>/dev/null; then
    echo "  ✓ baseline routing references the UI-quality skills"
  else
    echo "  ✗ baseline routing missing UI-quality rows (ui-preflight-pages.md, module-review.md) — run bin/sync-project.sh"
    fails=$((fails+1))
  fi

  # 3. All 6 agents present with no unfilled placeholders
  #
  # review-agent was missing from this list until 2026-08-20, and so was every count that
  # said "five". It owns module-review.md stage 4 — the LOOK, the one pass that assesses
  # rendered pages — so a project could pass build-ready with the reviewer an inert stub,
  # then run a module review with no configured owner for the stage that finds the escaped
  # defects. Measured: an end-to-end run that executed journeys, DB/OQL assertions and a
  # monkey pass, reported all three, and never looked at a page. The count is six.
  local agents_dir="$PROJECT_DIR/.claude/agents" missing_agents="" a
  for a in ba-agent architect-agent mdl-agent gate-agent test-agent review-agent; do
    [ -f "$agents_dir/$a.md" ] || missing_agents="$missing_agents $a"
  done
  # {{DOUBLE_BRACE}} is EXCLUDED, and the exclusion is load-bearing. Every agent
  # template carries, on line 11, "If any {{DOUBLE_BRACE}} placeholder remains in
  # this file, refuse to proceed" — the token is prose standing in for "double
  # brace", not an unfilled slot. A bare `grep "{{"` therefore fails build-ready
  # on a CORRECTLY completed project, and the only way to pass is to delete the
  # sentence. That is exactly what happened: all five agents in a real project
  # ended up with zero occurrences of "refuse to proceed", because a false
  # positive made deleting the safety net the cheapest way to get a green gate.
  # A check that punishes the correct state trains people to break it.
  local remaining
  remaining=$(sed 's/{{DOUBLE_BRACE}}//g' "$agents_dir"/*.md 2>/dev/null \
              | grep -o '{{[^}]*}}' | sort -u | tr '\n' ' ')
  if [ -n "$missing_agents" ]; then
    echo "  ✗ missing agent(s):$missing_agents — run bin/init-agents.sh"
    fails=$((fails+1))
  elif [ -n "$remaining" ]; then
    # Name them. "still have placeholders" sends you grepping five files by hand.
    # ${remaining} braced, not bare: $remaining— splices the em-dash's UTF-8
    # bytes into the variable NAME on byte-oriented bash 3.2, and set -u then
    # aborts the whole run. Only the failure branch ever built that string, so
    # a pass-path-only test would have shipped it.
    echo "  ✗ agent(s) still have unfilled placeholders: ${remaining}— complete them (agent-roles.md)"
    fails=$((fails+1))
  else
    echo "  ✓ all 6 agents present, no unfilled placeholders"
  fi

  # 3b. Crash net present. Stage 5 writes to a binary .mpr that Studio Pro holds
  # open; without snapshot/restore a bad exec is recovered from git or not at all.
  # These are installed by init-project.sh — a project missing them predates that,
  # or someone deleted them.
  local missing_net="" s
  for s in _common.sh snapshot-mpr.sh restore-mpr.sh exec.sh; do
    [ -f "$PROJECT_DIR/bin/$s" ] || missing_net="$missing_net $s"
  done
  if [ -n "$missing_net" ]; then
    echo "  ✗ crash net incomplete, missing:$missing_net — run bin/init-project.sh (or bin/sync-project.sh)"
    fails=$((fails+1))
  else
    echo "  ✓ crash net present (snapshot / restore / guarded exec)"
  fi

  # 4. At least one module brief exists (JIT — the first module's brief must be ready)
  if find_artifact -path '*/architecture/modules/*-brief.md' | grep -q .; then
    echo "  ✓ at least one module brief exists (architecture/modules/)"
  else
    echo "  ✗ no module brief (architecture/modules/<Module>/module-brief.md) — ba-agent translation mode (module-brief.md)"
    fails=$((fails+1))
  fi

  # 5. Design assets: wireframes + a design system file
  if find_artifact -path '*/wireframes/*.html' | grep -q .; then
    echo "  ✓ wireframes present"
  else
    echo "  ✗ no wireframes (design/wireframes/*.html) — design-artifacts.md"
    fails=$((fails+1))
  fi
  if find_artifact \( -name 'ds.css' -o -name 'design-system.html' \) | grep -q .; then
    echo "  ✓ design system present (ds.css / design-system.html)"
  else
    echo "  ✗ no design system (ds.css or design-system.html) — design-artifacts.md"
    fails=$((fails+1))
  fi

  echo ""
  if [ "$fails" -eq 0 ]; then
    echo "BUILD-READY: PASS — all wiring checks passed"
    return 0
  fi
  echo "BUILD-READY: FAIL — $fails item(s) above must be resolved before Stage 5 build"
  return 1
}

STAGE_NAMES=(0 1 2 3 4 5 6 7)

# Stage id -> value tables. Deliberately NOT bash indexed arrays.
#
# bash evaluates an array subscript as an ARITHMETIC EXPRESSION, not as a key. So
# RESULTS[$REQUESTED_STAGE] with a non-integer id such as 0.5 is a syntax error — and that
# error aborts the ENCLOSING COMPOUND COMMAND, i.e. the whole `if [ -n "$REQUESTED_STAGE" ]`
# block at the foot of this script INCLUDING its `exit 1`, so control resumes at the final
# `exit 0`. Measured 3/3 against an empty project: a forged PASS. Neither `:-` nor `set -u`
# prevents it (the expansion never completes, and the block's own exits are discarded).
# The same arithmetic also makes `05` mean stage 5, `0x0`/`1-1`/bare identifiers mean stage 0,
# and `a[n=2]` assign to n. And a non-integer in STAGE_NAMES kills the evaluation `for` loop
# mid-way, so index.html renders with the remaining stages silently missing.
#
# The line-46 whitelist currently rejects 0.5 first, so none of this is reachable today — this
# replacement is behaviour-identical on every accepted stage. It exists so that adding a
# fractional stage id later cannot arm the forged pass. bash 3.2 has no associative arrays, so
# these are newline/tab-delimited tables read by an exact-string accessor: no arithmetic, no
# eval, no subshell, arbitrary string keys.
tbl_add() { # tbl_add <table-var-name> <key> <value> — append a record in place.
  # printf -v, NOT "$(tbl_add ...)": command substitution strips trailing newlines and
  # collapses the whole table onto one line, after which `case "$line" in "$key"$'\t'*)`
  # matches the FIRST record as a prefix and returns every later record as its value. That
  # bug produced a fresh forged pass (exit 0 on a FAILing stage) in an earlier draft of this
  # very fix, which is why the fixture asserts on the FAIL and MANUAL paths too.
  printf -v "$1" '%s%s\t%s\n' "${!1}" "$2" "$3"
}
tbl_get() { # tbl_get <key> <table>; sets TBL_VALUE; rc 1 when the key is absent
  local key="$1" table="$2" line
  TBL_VALUE=""
  local IFS=$'\n'
  for line in $table; do
    case "$line" in
      "$key"$'\t'*) TBL_VALUE="${line#*$'\t'}"; return 0 ;;
    esac
  done
  return 1
}

STAGE_TITLES_TBL=""
tbl_add STAGE_TITLES_TBL 0 "Triage"
tbl_add STAGE_TITLES_TBL 1 "Analysis"
tbl_add STAGE_TITLES_TBL 2 "Requirements"
tbl_add STAGE_TITLES_TBL 3 "Architecture & Design"
tbl_add STAGE_TITLES_TBL 4 "Build Plan"
tbl_add STAGE_TITLES_TBL 5 "Build"
tbl_add STAGE_TITLES_TBL 6 "Test"
tbl_add STAGE_TITLES_TBL 7 "Cutover"

RESULTS_TBL=""
NOTES_TBL=""

# Protocol-freshness check: the session must have acknowledged the toolkit version it is
# working from. PROJECT.md records "Toolkit commit: <sha>" (set by the session-start ritual
# in CLAUDE.local.md); if the protocol has moved since that ack, the session is working from a
# stale read — the root cause of every skipped-gate incident so far.
#
# Compared against the REMOTE tip, not local HEAD. Local HEAD only advances when someone runs
# `git pull`, so a session that skips the pull records its stale SHA and the check compares the
# stale clone to itself — always passing, in precisely the case it exists to catch.
#
# Only PROTOCOL_PATHS invalidate an ack. The toolkit's rules live in skills/ and agents/;
# bin/, README and docs can move without a session needing to re-read anything. The strict
# form was tried: landing §1.6 turned PROJECT-C red claiming "the protocol changed" when only
# bin/ had moved. A gate that cries wolf teaches people to rubber-stamp the SHA without opening
# the runbook, which costs more than the bug it closes. See TOOLKIT-UPGRADE-PLAN.md §1.9.
#
# §1.9 softened this once already, from "any change" to "only skills/ and agents/". It was not
# enough, and the reason is structural: that filter asks WHICH FILES CHANGED, never WHETHER THIS
# SESSION DEPENDS ON THEM. Reproduced: a project with a signed-off Stage 0 is blocked because
# someone else pushed a two-word typo fix to a Stage 3 skill, while the board prints
# "Stage 0: PASS" directly above the block. The wrong party is punished — nothing in the blocked
# project changed — and the message can only imply whose fault it is. So the scope is now
# RELEVANCE, not file location: block when the requested gate depends on what moved, warn
# otherwise. Measured over the last 30 toolkit commits: 18/30 blocked before, 5-8/30 after, and
# Stage 5 correctly stays at 18/30 because almost all toolkit churn IS build-stage protocol.
TOOLKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROTOCOL_PATHS="skills agents"

# ── Stage → protocol-file map ─────────────────────────────────────────────────
# WHICH protocol files a given gate actually depends on.
#
# THIS MAP IS NEW SURFACE AND IT CAN ROT. It has no upstream source: the runbook's Stage Matrix
# (§2) names each stage's owning skill in PROSE ("Owner: ba-agent", "per design-artifacts.md's
# full output list") and agent-roles.md maps agents to stage ranges. Both are readable by a
# human, neither by a script. What follows is a hand-derived encoding of those rows, so adding,
# renaming or re-homing a skill WILL silently desynchronise it.
#
# How you would notice, in the order the signals arrive:
#   1. The WARN banner names the changed files. A file you know is load-bearing for the stage
#      you are running, listed as "nothing this gate depends on", is a miss — fix the row.
#   2. A new or renamed skill matches nothing here, so protocol_is_mapped() returns false and
#      protocol_is_relevant() FAILS SAFE — it blocks every stage and the note says "(unmapped)".
#      A stale map therefore makes the gate NOISIER, never quieter: it degrades toward the old
#      always-block behaviour rather than toward silence. That is the deliberate failure
#      direction, and it is also the nag that gets the row added.
#   3. `ls skills/` against the union of these rows is a 10-second audit; anything in the former
#      and not the latter is either intentionally unmapped-and-always-relevant or a gap.
#
# What this gives up, stated plainly: a genuinely dangerous change to a skill filed here under
# the WRONG stage passes as a warning. That is a real regression against blocking on everything,
# bounded by the fail-safe above and by PROTOCOL_ALWAYS below.
#
# PROTOCOL_ALWAYS governs every stage: the runbook is the executable spec for all of them, and
# query-the-model.md gates any question asked before writing anything.
#
# agents/ is ALWAYS relevant too, and deliberately NOT stage-scoped. An agent definition governs
# HOW work is done rather than WHAT a given stage produces, so there is no stage at which a
# stale read of it is safe — you cannot know in advance which stage it will bite at. The cost is
# small and checkable rather than asserted: agents/ churns far less than skills/, and the
# block-rate measurement reports the agents/-only figure separately for exactly that reason.
# ── The runbook's Surface column ─────────────────────────────────────────────────────────
# WHY THIS EXISTS. This script walks the runbook's **Gate** column and, until now, nothing else.
# A gate asks "is the required evidence present and internally consistent" — it cannot ask "is
# the work any good", because that is a human's judgement and it is made by READING the stage's
# Surface artifact. So a stage could pass its gate while the one artifact a human would review
# had never been generated, and the board would show green. That is not hypothetical: on
# PROJECT-B the Stage 2 surface was simply never produced, the gate-required
# validation-report.md was, and "gate PASS" was read as "stage done" by the agent that wrote it.
#
# Reported, never enforced. A missing Surface does NOT fail a gate and does NOT touch the exit
# code — it is a stage nobody can review, which is a different complaint and belongs in a
# different sentence.
#
# PARSED, NOT COPIED. The list lives in exactly one place, skills/conversion-runbook.md §2, and
# is read out of it at runtime. A second copy here is the disease this repo keeps catching
# itself with (see bin/lib/discover-brds.sh's header). The cost of that choice is honest: the
# parser below is hand-tuned against PROSE cells and it WILL rot the day someone rewords one.
# When it does it must say "cannot parse", never fall silent — a surface that cannot be checked
# and a surface that is present must never print the same way.
RUNBOOK_FILE="$TOOLKIT_DIR/skills/conversion-runbook.md"

# "<stage>\t<raw cell>" for every stage that declares a Surface row.
stage_surface_cells() {
  [ -r "$RUNBOOK_FILE" ] || return 1
  awk '
    /^### Stage / { cur=""; if (match($0, /^### Stage (P|[0-7])/)) cur=substr($0, 11, RLENGTH-10); next }
    /^\| \*\*Surface\*\* \|/ && cur!="" {
      cell=$0; sub(/^\| \*\*Surface\*\* \| ?/,"",cell); sub(/ ?\|[[:space:]]*$/,"",cell)
      print cur "\t" cell; cur=""
    }
  ' "$RUNBOOK_FILE"
}

# The artifact patterns for one stage, space-separated. Empty output means either "no Surface
# row" or "a Surface row we could not read"; the caller distinguishes them via stage_surface_cells.
stage_surface_patterns() {
  local want="$1" st cell
  while IFS="$(printf '\t')" read -r st cell; do
    [ "$st" = "$want" ] || continue
    # Order matters. Strip parentheticals FIRST: Stage 3's cell carries an em-dash INSIDE a
    # parenthetical, so cutting at the gloss first would swallow design-system.html and the
    # wireframes with it. Cutting at " — " second is what keeps Stage 2's historical mention of
    # the renamed enrichment-summary.html — the exact file this whole check is about — from
    # being reported as a surface the project still owes.
    cell="$(printf '%s' "$cell" | sed -E 's/\([^)]*\)//g')"
    cell="${cell%% — *}"
    # Backticked tokens that look like artifacts. The no-space filter drops toolkit COMMANDS
    # (`bin/brd-report.sh <project-root>`); ^bin/ is belt-and-braces for the same reason.
    printf '%s' "$cell" \
      | grep -oE '`[^`]+`' | tr -d '`' \
      | grep -E '^[^ ]+\.(html|json|md)$' | grep -v '^bin/' \
      | sed -E 's/<[^>]*>/*/g' \
      | tr '\n' ' '
    return 0
  done <<EOF
$(stage_surface_cells)
EOF
  return 1
}

# "present" | "MISSING: a, b" | "not declared in runbook §2" | "cannot parse"
stage_surface_status() {
  local st="$1" pats missing="" pat base f hit
  if ! stage_surface_cells >/dev/null 2>&1; then
    echo "cannot parse — $RUNBOOK_FILE is unreadable"; return
  fi
  if ! pats="$(stage_surface_patterns "$st")"; then
    # No Surface row at all. §2's intro promises every stage a review surface, so this is a
    # runbook gap rather than a project one, and saying so is how it gets closed.
    echo "not declared in runbook §2"; return
  fi
  if [ -z "$(printf '%s' "$pats" | tr -d ' ')" ]; then
    echo "cannot parse — the Surface row for stage $st yielded no artifact"; return
  fi
  for pat in $pats; do
    hit=0
    for base in "$PROJECT_DIR" "$ANALYSIS_BASE"; do
      # Unmatched globs stay literal with nullglob off, so -e is the whole test.
      # "$base"/$pat, not $base/$pat: the base must be quoted (a project path with a space in
      # it word-splits otherwise and every surface reports MISSING), the pattern must not be
      # (it has to glob). Same idiom as the analysis/*/knowledge-base scan above.
      for f in "$base"/$pat; do [ -e "$f" ] && { hit=1; break 2; }; done
    done
    [ "$hit" = "1" ] || missing="$missing${missing:+, }$pat"
  done
  [ -z "$missing" ] && echo "present" || echo "MISSING: $missing"
}

# The one-line suffix appended to a stage's verdict.
stage_surface_suffix() {
  local s; s="$(stage_surface_status "$1")"
  case "$s" in
    present) printf ' · Surface present' ;;
    *)       printf ' · Surface %s' "$s" ;;
  esac
}

PROTOCOL_ALWAYS="skills/conversion-runbook.md skills/query-the-model.md agents/"
stage_protocol_paths() {
  # The arms below are GENERATED from bin/lib/skill-routing.tsv by bin/render-routing.sh.
  # Do not hand-edit them: add or change the skill's ROW (its `stages` column) and re-render.
  # This map used to be one of six hand-kept copies of the same routing knowledge; a skill
  # added to skills/ and forgotten here trips protocol_is_mapped()'s fail-safe and blocks
  # every stage as "(unmapped)" — noisy by design, but only after someone hits it.
  case "$1" in
# <!-- ROUTING:BEGIN stage-map -->
    P)  echo "skills/interview-protocol.md skills/grill-mode.md skills/agent-roles.md skills/bootstrap-project.md skills/mendix-epics-api.md skills/corpus-extraction-integrity.md" ;;
    0)  echo "skills/interview-protocol.md skills/grill-mode.md skills/checkpoints/checkpoint-template.md skills/checkpoints/checkpoint-scope.md skills/source-triage.md skills/assess-migration.md skills/migration-pipeline.md skills/migrate-general.md skills/migrate-outsystems.md skills/source-os11.md skills/os-xml-schema.md skills/source-node-express-react.md skills/document-discovery.md skills/extractor-quality-loop.md skills/qa-loop-goal-pattern.md skills/mendix-epics-api.md skills/corpus-extraction-integrity.md" ;;
    1)  echo "skills/interview-protocol.md skills/grill-mode.md skills/checkpoints/checkpoint-template.md skills/checkpoints/checkpoint-extraction.md skills/migration-pipeline.md skills/source-os11.md skills/os-xml-schema.md skills/source-node-express-react.md skills/document-discovery.md skills/extractor-quality-loop.md skills/kb-generation.md skills/corpus-extraction-integrity.md" ;;
    2)  echo "skills/interview-protocol.md skills/grill-mode.md skills/checkpoints/checkpoint-template.md skills/checkpoints/checkpoint-brd.md skills/checkpoints/checkpoint-architecture.md skills/kb-generation.md skills/brd-generation.md skills/brd-validation.md" ;;
    3)  echo "skills/interview-protocol.md skills/grill-mode.md skills/checkpoints/checkpoint-template.md skills/checkpoints/checkpoint-design.md skills/architecture-blueprint.md skills/modularize-domain.md skills/design-artifacts.md skills/brd-to-build-plan.md" ;;
    4)  echo "skills/interview-protocol.md skills/grill-mode.md skills/checkpoints/checkpoint-template.md skills/checkpoints/checkpoint-build.md skills/agent-roles.md skills/module-brief.md skills/module-folder-convention.md skills/brd-to-build-plan.md skills/coverage-ledger.md skills/rest-integration-first-time-right.md" ;;
    5|build-ready) echo "skills/interview-protocol.md skills/grill-mode.md skills/agent-roles.md skills/module-brief.md skills/learned-mdl-preflight.md skills/module-folder-convention.md skills/learned-microflow-patterns.md skills/ui-preflight-pages.md skills/design-spacing.md skills/ui-loop.md skills/learned-stylegallery.md skills/learned-mcp-patterns.md skills/module-review.md skills/testing-shape.md skills/iterative-build-loop.md skills/mdl-cookbook-microflows.md skills/build/mdl/oneshot-mdl-method.md skills/learned-page-patterns.md skills/oneshot-page-structure-patterns.md skills/mendix-agents.md skills/mendix-agent-ui.md skills/fixture-seeding.md skills/journey-proof.md skills/monkey-test.md skills/report-schema.md skills/harness-architecture.md skills/process-coherence-pass.md skills/lint-that-actually-runs.md skills/improvement-register.md skills/journey-examples.md skills/wiring-sweep.md skills/learned-workflow-patterns.md skills/rest-integration-first-time-right.md skills/bug-submission-checklist.md skills/empty-widget-triage.md skills/learned-sidebar-collapse-icons.md skills/learned-popup-navigation.md skills/learned-datagrid-customcontent-binding.md skills/learned-popup-feedback-pattern.md" ;;
    6)  echo "skills/interview-protocol.md skills/grill-mode.md skills/checkpoints/checkpoint-template.md skills/checkpoints/checkpoint-cutover.md skills/module-review.md skills/testing-shape.md skills/existing-app-assurance.md skills/qa-loop-goal-pattern.md skills/e2e-harness-base.md skills/learned-db-assertions.md skills/fixture-seeding.md skills/journey-proof.md skills/monkey-test.md skills/learned-skill-ux-audit.md skills/learned-skill-scope-delta.md skills/report-schema.md skills/harness-architecture.md skills/process-coherence-pass.md skills/e2e-evidence-report.md skills/lint-that-actually-runs.md skills/improvement-register.md skills/journey-examples.md skills/wiring-sweep.md skills/bug-submission-checklist.md skills/empty-widget-triage.md skills/anonymize-client-app-for-demo.md" ;;
    7)  echo "skills/interview-protocol.md skills/grill-mode.md skills/checkpoints/checkpoint-template.md skills/checkpoints/checkpoint-cutover.md skills/close-the-loop.md" ;;
    *)  echo "" ;;
# <!-- ROUTING:END -->
  esac
}
# stages_for_protocol_files <file...> — which stages route to these files. Used to turn "eight
# skill files changed" into "this touches stages 3 and 5", which is the form a reader can act on.
stages_for_protocol_files() {
  local st k f out=""
  for st in P 0 1 2 3 4 5 6 7; do
    for f in "$@"; do
      for k in $(stage_protocol_paths "$st"); do
        case "$f" in "$k"*) out="$out$st "; break 2 ;; esac
      done
    done
  done
  printf '%s' "$out" | sed 's/ *$//'
}

# Does this file appear under ANY stage? A "no" is what triggers the fail-safe.
protocol_is_mapped() {
  local f="$1" st k
  for st in P 0 1 2 3 4 5 6 7; do
    for k in $(stage_protocol_paths "$st") $PROTOCOL_ALWAYS; do
      case "$f" in "$k"*) return 0 ;; esac
    done
  done
  return 1
}
# Relevant to the REQUESTED gate? Unmapped files are relevant (fail-safe).
protocol_is_relevant() {
  local f="$1" k
  for k in $PROTOCOL_ALWAYS $(stage_protocol_paths "${REQUESTED_STAGE:-}"); do
    case "$f" in "$k"*) return 0 ;; esac
  done
  protocol_is_mapped "$f" || return 0
  return 1
}

TOOLKIT_HEAD="$(git -C "$TOOLKIT_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")"

# Resolve the reference tip. Fetch failure must not silently degrade to the old self-comparison:
# fall back to local HEAD so offline work isn't stranded, but label the verdict UNVERIFIED so a
# pass that proved nothing cannot read as a pass that did.
SYNC_REF_LABEL="origin"
# The fetch is the only network call in this script and it had no timeout and no opt-out, so a
# slow or captive network turned a local file check into an unbounded wait. Two guards, both of
# which fall through to the existing UNVERIFIED path rather than failing:
#   - MXTK_NO_FETCH=1 skips it outright.
#   - Otherwise it is capped by git's own low-speed abort (~8s). A `timeout`/`gtimeout` wrapper
#     was rejected: macOS ships NEITHER, so it would have silently broken every trainer's Mac.
#     GIT_TERMINAL_PROMPT=0 stops it blocking forever on credentials nobody is there to type.
if [ "${MXTK_NO_FETCH:-0}" = "1" ]; then
  TOOLKIT_REF="$TOOLKIT_HEAD"
  SYNC_REF_LABEL="local HEAD — UNVERIFIED, fetch skipped (MXTK_NO_FETCH=1)"
elif git -C "$TOOLKIT_DIR" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1 \
   && GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o ConnectTimeout=5}" \
      git -C "$TOOLKIT_DIR" -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=8 fetch --quiet 2>/dev/null; then
  TOOLKIT_REF="$(git -C "$TOOLKIT_DIR" rev-parse --short '@{u}' 2>/dev/null || echo "unknown")"
else
  TOOLKIT_REF="$TOOLKIT_HEAD"
  SYNC_REF_LABEL="local HEAD — UNVERIFIED, could not reach origin"
fi

# Verdict vocabulary. Protocol staleness NEVER blocks by default — it NOTIFIES.
#   PASS   — the ack is current (or ahead of origin: unpushed toolkit work).
#   WARN   — the toolkit moved, but nothing the requested gate depends on changed. One quiet
#            line, no banner. Relevance is used here for VOLUME, not for gating.
#   NOTICE — something the reader should act on: protocol the requested gate depends on moved,
#            or freshness cannot be established at all. Gets the full lettered notice.
# Only --strict-protocol turns NOTICE into a block. See the rationale below the verdict.
SYNC_STATUS="NOTICE"
SYNC_NOTE="$REGISTER has no 'Toolkit commit:' line — protocol freshness cannot be established"
SYNC_HEADLINE="$REGISTER records no toolkit commit, so this project's protocol freshness is unknown."
SYNC_DETAIL=""
SYNC_OPT_A="Record the current protocol commit:  $0 $PROJECT_DIR --ack-protocol"
if [ "$REG_AMBIGUOUS" = "1" ]; then
  # Do not say "none found" when the problem is that there are two. Naming the wrong cause sends
  # the reader looking for a missing file that is not missing.
  SYNC_NOTE="cannot evaluate: $REG_COUNT differing decision registers exist and none is named — see the ⚠ notice above"
  SYNC_HEADLINE="$REG_COUNT differing decision registers under $PROJECT_DIR, so protocol freshness cannot be read from either."
elif [ -z "$REGISTER" ] || [ ! -f "$REGISTER" ]; then
  SYNC_NOTE="no decision register (PROJECT.md) found under $PROJECT_DIR — protocol freshness cannot be established"
  SYNC_HEADLINE="No decision register (PROJECT.md) under $PROJECT_DIR, so protocol freshness is unknown."
  SYNC_OPT_A="Scaffold one:  bin/init-project.sh $PROJECT_DIR   (it stamps the current commit)"
fi
# Reads $REGISTER, not "$PROJECT_DIR/PROJECT.md" (bug02): on PROJECT-D the root stub acked
# 11eafdf while the live nested register acked 13b5445, so the freshness verdict described a
# register nobody had touched since 16 July.
if [ -n "$REGISTER" ] && [ -f "$REGISTER" ]; then
  RECORDED="$(grep -o 'Toolkit commit: [a-f0-9]*' "$REGISTER" | head -1 | awk '{print $3}')"
  if [ -n "${RECORDED:-}" ]; then
    if [ "$RECORDED" = "$TOOLKIT_REF" ]; then
      SYNC_STATUS="PASS"
      SYNC_NOTE="session acknowledged toolkit commit $TOOLKIT_REF ($SYNC_REF_LABEL)"
    elif ! git -C "$TOOLKIT_DIR" cat-file -e "${RECORDED}^{commit}" 2>/dev/null; then
      SYNC_NOTE="$REGISTER acknowledges toolkit commit $RECORDED, which does not exist in the toolkit clone"
      SYNC_HEADLINE="$REGISTER acknowledges toolkit commit $RECORDED, which this clone has never seen."
      SYNC_DETAIL="Nothing can be diffed against it, so freshness is unknown rather than stale."
      SYNC_OPT_A="Fetch the toolkit, then re-baseline:  $0 $PROJECT_DIR --ack-protocol"
    elif git -C "$TOOLKIT_DIR" merge-base --is-ancestor "$TOOLKIT_REF" "$RECORDED" 2>/dev/null; then
      SYNC_STATUS="PASS"
      SYNC_NOTE="ack $RECORDED is ahead of $TOOLKIT_REF ($SYNC_REF_LABEL) — unpushed toolkit work, acknowledgement is current"
    else
      # --diff-filter=MDR, i.e. ADDED files are dropped: a protocol file that did not exist when
      # the ack was made cannot invalidate a read that already happened. Empirically safe on this
      # repo — every mass-restructure that added a skill also MODIFIED the file that routes to
      # it, so the restructure is still caught through the M paths. Renames and deletions are
      # kept: a skill you may have read disappearing is real risk.
      # shellcheck disable=SC2086 — PROTOCOL_PATHS is a deliberate multi-pathspec list.
      SYNC_CHANGED="$(git -C "$TOOLKIT_DIR" diff --name-only --diff-filter=MDR "$RECORDED" "$TOOLKIT_REF" -- $PROTOCOL_PATHS 2>/dev/null || true)"
      SYNC_ADDED="$(git -C "$TOOLKIT_DIR" diff --name-only --diff-filter=A "$RECORDED" "$TOOLKIT_REF" -- $PROTOCOL_PATHS 2>/dev/null || true)"
      SYNC_RELEVANT=""
      SYNC_IRRELEVANT=""
      SYNC_UNMAPPED=""
      for f in $SYNC_CHANGED; do
        if protocol_is_relevant "$f"; then
          SYNC_RELEVANT="$SYNC_RELEVANT $f"
          protocol_is_mapped "$f" || SYNC_UNMAPPED="$SYNC_UNMAPPED $f"
        else
          SYNC_IRRELEVANT="$SYNC_IRRELEVANT $f"
        fi
      done
      SYNC_MOVED="$(printf '%s\n%s\n' "$SYNC_CHANGED" "$SYNC_ADDED" | grep -v '^$' | tr '\n' ' ' | sed 's/ *$//')"
      if [ -n "$SYNC_RELEVANT" ]; then
        # Line counts are REPORTED, never used to filter. Measured on this repo, diff size is
        # anti-correlated with importance: the one-line diffs in the window are STOP-rule
        # corrections in learned-mdl-preflight.md, while the largest are anonymization sweeps
        # that changed no rule at all. The count exists to make the notice and the ack record
        # legible — "1 insertion" reads very differently from "636 insertions".
        # shellcheck disable=SC2086 — SYNC_RELEVANT is a deliberate multi-pathspec list.
        SYNC_LINES="$(git -C "$TOOLKIT_DIR" diff --shortstat "$RECORDED" "$TOOLKIT_REF" -- $SYNC_RELEVANT 2>/dev/null | sed 's/^ *//')"
        SYNC_NOTE="protocol that gate '${REQUESTED_STAGE:-all}' depends on changed since the ack ($RECORDED → $TOOLKIT_REF, $SYNC_REF_LABEL) —$SYNC_RELEVANT ($SYNC_LINES)"
        SYNC_HEADLINE="The toolkit moved since this project acknowledged it ($RECORDED → $TOOLKIT_REF, $SYNC_REF_LABEL)."
        SYNC_DETAIL="Changed, and gate '${REQUESTED_STAGE:-all}' depends on it:$SYNC_RELEVANT ($SYNC_LINES)"
        SYNC_OPT_A="Read it and accept:  $0 $PROJECT_DIR --ack-protocol   (shows the diff, then records it)"
        if [ -n "$SYNC_UNMAPPED" ]; then
          SYNC_NOTE="$SYNC_NOTE [unmapped, treated as relevant:$SYNC_UNMAPPED — add it to stage_protocol_paths()]"
          SYNC_DETAIL="$SYNC_DETAIL
    Unmapped, so treated as relevant:$SYNC_UNMAPPED — add it to stage_protocol_paths()."
        fi
      elif [ -n "$SYNC_MOVED" ]; then
        # Relevance decides VOLUME, not gating: this one is a single quiet line, deliberately
        # without the banner. A notice that appears in full on every run for three weeks becomes
        # wallpaper, and wallpaper is how the original gate trained people to rubber-stamp.
        SYNC_STATUS="WARN"
        SYNC_NOTE="toolkit moved ($RECORDED → $TOOLKIT_REF, $SYNC_REF_LABEL); nothing gate '${REQUESTED_STAGE:-all}' depends on changed — $SYNC_MOVED. Ack when convenient: $0 $PROJECT_DIR --ack-protocol"
      else
        SYNC_STATUS="PASS"
        SYNC_NOTE="ack $RECORDED is behind $TOOLKIT_REF ($SYNC_REF_LABEL) but no protocol path (${PROTOCOL_PATHS// /, }) changed — acknowledgement still valid"
      fi
    fi
  fi
fi

# Does this verdict stop the run? Only under --strict-protocol, and only at NOTICE level.
# DEFAULT IS NEVER. The whole history of this check is a gate that blocked the wrong party: the
# project that gets blocked is the one that changed nothing, because someone ELSE pushed to a
# shared repo. §1.9's own conclusion — "a gate that cries wolf trains people to rubber-stamp the
# SHA without opening the runbook, which costs more than the bug it closes" — applies with more
# force to a block than to a warning. So the reader is TOLD, with the options spelled out, and
# the stage verdict below is evaluated and reported on its own merits regardless. Anyone who
# wants the old behaviour in CI opts in with --strict-protocol.
SYNC_BLOCKING=0
[ "$STRICT_PROTOCOL" = "1" ] && [ "$SYNC_STATUS" = "NOTICE" ] && SYNC_BLOCKING=1

# The one-line verdict is jargon by construction — it names commits and paths so a maintainer
# can act on it without a second command. Non-verbose readers get the same verdict in words.
if [ "$PROTOCOL_VERBOSE" = "1" ]; then
  printf "Sync (Protocol freshness): %s — %s\n" "$SYNC_STATUS" "$SYNC_NOTE"
else
  case "$SYNC_STATUS" in
    PASS)   printf "Toolkit updates: up to date.\n" ;;
    WARN)   printf "Toolkit updates: the shared toolkit moved, but nothing this stage uses changed. No action needed.\n" ;;
    NOTICE) printf "Toolkit updates: available, not yet reviewed. Nothing is blocked.\n" ;;
    *)      printf "Toolkit updates: %s\n" "$SYNC_STATUS" ;;
  esac
fi
if [ "$SYNC_STATUS" = "NOTICE" ]; then
  # Lead with the CHOICE, not with the diagnosis. The old message named files, showed no diff,
  # offered no command, and did not say where the value it wanted was written — so the only
  # available response was to go and find the four-step ritual in another file.
  echo ""
  # LAYERED, and plain-language by default (2026-08-26). The old notice was written for someone
  # who already knew what a "protocol commit" was: it led with two abbreviated SHAs, said "ack",
  # and named skill file paths. A TAM running this in an enablement session reads that and can
  # only conclude something is broken. Nothing about the SHAs helps them decide; the decision is
  # "has the shared toolkit changed in a way that affects what I am about to build?" — so ask
  # exactly that, in those words, and put the identifiers behind --verbose for the people who
  # actually diff things.
  if [ "$PROTOCOL_VERBOSE" = "1" ]; then
    echo "  ⚠ $SYNC_HEADLINE"
    [ -n "$SYNC_DETAIL" ] && printf '    %s\n' "$SYNC_DETAIL"
  else
    echo "  ⚠ The shared toolkit has been updated since this project last checked."
    if [ -n "${SYNC_RELEVANT:-}" ]; then
      SYNC_N="$(printf '%s' "$SYNC_RELEVANT" | wc -w | tr -d ' ')"
      echo "    $SYNC_N guidance file(s) that this stage relies on changed. Nothing is broken and"
      echo "    nothing is blocked — this is asking whether you want to take the update."
    fi
  fi
  if [ -n "${SYNC_RELEVANT:-}" ]; then
    # shellcheck disable=SC2086 — SYNC_RELEVANT is a deliberate list.
    SYNC_STAGES="$(stages_for_protocol_files $SYNC_RELEVANT)"
    [ -n "$SYNC_STAGES" ] && echo "    Stages this touches: $SYNC_STAGES"
    if [ "$PROTOCOL_VERBOSE" != "1" ]; then
      echo "    For the file list and commit ids, re-run with --verbose."
    fi
  fi
  echo ""
  if [ "$PROTOCOL_VERBOSE" = "1" ]; then
    echo "    A) $SYNC_OPT_A"
  else
    echo "    If you are an agent: run \"$0 $PROJECT_DIR --ack-protocol --verbose\" to see what"
    echo "    changed, summarise it for the user in plain language, ask whether to take the"
    echo "    update, and only if they say yes re-run with --ack-protocol --approved-in-chat."
    echo "    Do not decide this on the user's behalf and do not ask them to type anything."
    echo ""
    echo "    A) Take the update  — the agent records it for you once you say yes."
  fi
  if [ "$SYNC_BLOCKING" = "1" ]; then
    echo "    B) Proceed anyway:  $0 --force-stale $PROJECT_DIR ${REQUESTED_STAGE:-<stage>}"
    echo "       (--strict-protocol is on, so this run WILL stop; the bypass is logged.)"
  else
    echo "    B) Decide later — nothing is blocked. This notice repeats until you answer."
    echo "    C) Not needed here — if the update asks for work this project already did its own"
    echo "       way, or is past: $0 --waive <stage> --reason \"...\" $PROJECT_DIR"
    echo "       Taking the update (A) never obliges you to produce anything; it records that"
    echo "       you were told."
  fi
  echo ""
fi

# ── The build log: where an ack or a bypass leaves its trace ─────────────────
# Hard-coded to docs/BUILD-LOG.md. Resolving it from CLAUDE.local.md's ## Wiring block would be
# more correct for projects that keep their build log elsewhere, and is the obvious follow-up;
# it is not done here because a missing/renamed log must never be the reason an ack fails.
BUILD_LOG="$PROJECT_DIR/docs/BUILD-LOG.md"
build_log_append() {
  mkdir -p "$(dirname "$BUILD_LOG")" 2>/dev/null || true
  printf '%s  %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >> "$BUILD_LOG"
}

# ── --adopt / --waive: the way a project says "not here, and here is why" ────
#
# Writes ONE line into the resolved register and one into the build log, then exits. It writes
# nothing else and grades nothing — the next ordinary run reads the line back through reg_field()
# and the stage turns WAIVED. That indirection is deliberate: the line in the register is the
# authority, so a human can write, edit or delete it by hand without this script's help, and
# deleting it puts the stage straight back under the gate.
register_set_line() { # register_set_line <Label> <value> — replace the line, or append a section
  local label="$1" value="$2" tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/reg.XXXXXX")" || return 1
  if awk -v lab="$label" -v val="$value" '
       BEGIN { key = tolower(lab) }
       # Same comment guard as reg_field(): never rewrite a label the reader would not have read.
       /<!--/ { incomment = 1 }
       incomment { print; if ($0 ~ /-->/) incomment = 0; next }
       !done {
         line = $0; gsub(/^[ \t>*_-]+/, "", line); gsub(/\*/, "", line)
         i = index(line, ":")
         if (i > 0) {
           k = tolower(substr(line, 1, i - 1)); gsub(/^[ \t]+|[ \t]+$/, "", k)
           if (k == key) { print lab ": " val; done = 1; next }
         }
       }
       { print }
       END { exit !done }
     ' "$REGISTER" > "$tmp"; then
    cat "$tmp" > "$REGISTER"; rm -f "$tmp"; return 0
  fi
  rm -f "$tmp"
  printf '\n## Toolkit position\n\n%s: %s\n' "$label" "$value" >> "$REGISTER"
}

if [ -n "$ADOPT_STAGE" ] || [ -n "$WAIVE_STAGE" ]; then
  if [ -z "$REGISTER" ] || [ ! -f "$REGISTER" ]; then
    echo "No decision register (PROJECT.md) found under $PROJECT_DIR — nothing to record in." >&2
    echo "Scaffold one first:  bin/init-project.sh $PROJECT_DIR" >&2
    exit 1
  fi
  if [ -n "$ADOPT_STAGE" ]; then
    ADOPT_STAGE="$(printf '%s' "$ADOPT_STAGE" | tr '[:lower:]' '[:upper:]')"
    register_set_line "Adopted at stage" "$ADOPT_STAGE — $WAIVER_REASON" \
      || { echo "Could not write to $REGISTER" >&2; exit 1; }
    build_log_append "TOOLKIT-ADOPTED-AT $ADOPT_STAGE reason: $WAIVER_REASON"
    echo "Recorded in $REGISTER:  Adopted at stage: $ADOPT_STAGE — $WAIVER_REASON"
    echo "Every stage before $ADOPT_STAGE now reports WAIVED and exits 0. Stage P is deliberately"
    echo "not covered — the kickoff interview is how the toolkit learns what this project is."
  else
    # An obligation waiver (bin/lib/obligations.tsv) uses the SAME flag and the same reason
    # requirement, because a second waiver vocabulary is a second place to look and a second
    # thing to keep in step. Spelled as a target rather than a stage:
    #     --waive look/Orders --reason "integration module, no pages"   (one module)
    #     --waive sweep       --reason "QA runs in the client's own suite"  (every module)
    # The obligation form is recognised by the target naming a row in obligations.tsv.
    OB_TSV="$TOOLKIT_DIR/bin/lib/obligations.tsv"
    WAIVE_OB="${WAIVE_STAGE%%/*}"
    if [ -f "$OB_TSV" ] && awk -F'\t' -v w="$(printf '%s' "$WAIVE_OB" | tr '[:upper:]' '[:lower:]')" \
         '!/^#/ && $1==w && $1!="obligation" {found=1} END{exit !found}' "$OB_TSV"; then
      register_set_line "Waived obligation $WAIVE_STAGE" "$WAIVER_REASON" \
        || { echo "Could not write to $REGISTER" >&2; exit 1; }
      build_log_append "OBLIGATION-WAIVED $WAIVE_STAGE reason: $WAIVER_REASON"
      echo "Recorded in $REGISTER:  Waived obligation $WAIVE_STAGE: $WAIVER_REASON"
      echo "That pass now reports WAIVED with its reason instead of PENDING. It does NOT report"
      echo "PASS — a waived pass is one nobody performed, and the register says who decided that."
      exit 0
    fi
    WAIVE_STAGE="$(printf '%s' "$WAIVE_STAGE" | tr '[:lower:]' '[:upper:]')"
    # One line per stage, so a second --waive cannot relabel the first stage's reason. Repeating
    # --waive for the same stage overwrites that stage's line and nothing else.
    register_set_line "Waived stage $WAIVE_STAGE" "$WAIVER_REASON" \
      || { echo "Could not write to $REGISTER" >&2; exit 1; }
    build_log_append "STAGE-WAIVED $WAIVE_STAGE reason: $WAIVER_REASON"
    echo "Recorded in $REGISTER:  Waived stage $WAIVE_STAGE: $WAIVER_REASON"
  fi
  echo "A waiver excuses an empty stage and an unsigned ✋ decision. It does NOT hide artifacts"
  echo "that exist and are inconsistent — those keep failing, which is the point."
  exit 0
fi

# Rewrite the "Toolkit commit:" line in the RESOLVED register — not "$PROJECT_DIR/PROJECT.md".
# On a project whose live register is nested, the root stub is exactly the file nobody reads.
# Line-oriented rather than a s/[a-f0-9]+/ substitution, because a freshly scaffolded register
# holds prose there ("(set at session start — see CLAUDE.local.md)"), which no sha pattern matches.
register_stamp_commit() {
  local ref="$1" tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/reg.XXXXXX")" || return 1
  awk -v ref="$ref" '
    !done && /Toolkit commit:/ {
      if (match($0, /Toolkit commit:[ \t]*[0-9a-f]+/)) sub(/Toolkit commit:[ \t]*[0-9a-f]+/, "Toolkit commit: " ref)
      else sub(/Toolkit commit:.*$/, "Toolkit commit: " ref)
      done = 1
    }
    { print }
    END { exit !done }
  ' "$REGISTER" > "$tmp" || { rm -f "$tmp"; return 1; }
  cat "$tmp" > "$REGISTER" && rm -f "$tmp"
}

# ── --ack-protocol: the one-command upgrade path ─────────────────────────────
# Replaces the four-step session-start ritual (pull, read sha, edit PROJECT.md, say so in chat)
# with a single command that shows what moved, offers the diff, and records the answer.
#
# This deliberately makes rubber-stamping EASIER, which is the maintainer's stated fear. The
# trade is legibility rather than impossibility: the log line carries the file list AND the
# changed-line count, so a later reader can tell "1 file changed, 1 insertion" from "22 files
# changed, 636 insertions" acked eleven seconds after the previous line. Today the only artifact
# is a bare sha, and that distinction cannot be made at all.
if [ "$ACK_PROTOCOL" = "1" ]; then
  if [ -z "$REGISTER" ] || [ ! -f "$REGISTER" ]; then
    echo "No decision register (PROJECT.md) found under $PROJECT_DIR — nothing to acknowledge in." >&2
    exit 1
  fi
  if [ "$SYNC_STATUS" = "PASS" ]; then
    echo "Nothing to acknowledge — $REGISTER is already current at $TOOLKIT_REF."
    exit 0
  fi
  if [ "$TOOLKIT_REF" = "unknown" ]; then
    echo "Cannot acknowledge: the toolkit clone at $TOOLKIT_DIR has no resolvable commit." >&2
    exit 1
  fi
  # Non-interactive: the ack still needs a HUMAN, but it no longer needs a TERMINAL.
  #
  # The original rule refused any ack without a TTY, because an ack asserts that a human read
  # the diff and an unattended auto-yes would write a record of a read that never happened —
  # poisoning the one signal that tells reads from rubber-stamps. That reasoning is intact and
  # this code still enforces it. What it got wrong was equating "a human" with "a human at a
  # terminal". The people this now runs in front of — TAMs in an enablement session, consultants
  # in a workshop — are humans who will never open a shell, and refusing them left the notice
  # repeating forever with no reachable answer, which is its own kind of rubber-stamp.
  #
  # So there are two honest ways to ack, and the log records WHICH:
  #   at a terminal   — the human ran this, saw the diffstat, optionally paged the full diff
  #   approved in chat — the agent ran --ack-protocol --verbose, summarised what changed in
  #                      plain language, ASKED, and the human said yes
  # Both are real reads. Neither is an agent deciding alone: --approved-in-chat is a claim the
  # agent makes on the record, in a countable log line, and an agent that sets it without having
  # asked has falsified an audit trail rather than skipped a step. That is the same trust model
  # every other write in this toolkit already runs on.
  #
  # There is still no env-var auto-yes, and --approved-in-chat is deliberately not implied by
  # anything: it must be typed, once, per ack, after the question was actually put.
  if [ ! -t 0 ] && [ "$APPROVED_IN_CHAT" != "1" ]; then
    if [ "$PROTOCOL_VERBOSE" = "1" ] && [ -n "${RECORDED:-}" ] \
       && git -C "$TOOLKIT_DIR" cat-file -e "${RECORDED}^{commit}" 2>/dev/null; then
      # The agent asked to SEE it. Show it, record nothing, and say what to do next.
      echo "What changed in the shared toolkit since this project last checked:"
      echo ""
      # shellcheck disable=SC2086 — PROTOCOL_PATHS is a deliberate multi-pathspec list.
      git -C "$TOOLKIT_DIR" --no-pager diff --stat "$RECORDED" "$TOOLKIT_REF" -- $PROTOCOL_PATHS
      echo ""
      # shellcheck disable=SC2086
      git -C "$TOOLKIT_DIR" --no-pager log --oneline "$RECORDED..$TOOLKIT_REF" -- $PROTOCOL_PATHS
      echo ""
      echo "NOTHING HAS BEEN RECORDED. This was a read-only preview."
      echo "Agent: summarise the above for the user in plain language — what changed and what it"
      echo "means for what they are building — then ask whether to take the update. Only if they"
      echo "say yes, re-run:  $0 $PROJECT_DIR --ack-protocol --approved-in-chat"
      exit 0
    fi
    echo "Refusing to record this without a human having been asked." >&2
    echo "An ack asserts a person was told what changed; nothing here can make that true." >&2
    echo "  A) Agent: preview it, ask the user, then record their answer:" >&2
    echo "       $0 $PROJECT_DIR --ack-protocol --verbose            (shows it, records nothing)" >&2
    echo "       $0 $PROJECT_DIR --ack-protocol --approved-in-chat   (after they say yes)" >&2
    echo "  B) Human at a terminal: $0 $PROJECT_DIR --ack-protocol" >&2
    echo "  C) Proceed anyway:  $0 --force-stale $PROJECT_DIR ${REQUESTED_STAGE:-<stage>}" >&2
    echo "     — that works, and records a PROTOCOL-BYPASS line in docs/BUILD-LOG.md." >&2
    if [ "$STRICT_PROTOCOL" != "1" ]; then
      echo "     Note: without --strict-protocol nothing is blocked anyway — this run can" >&2
      echo "     simply proceed, and the notice repeats until someone answers it." >&2
    fi
    exit 1
  fi
  echo ""
  if [ -n "${RECORDED:-}" ] && git -C "$TOOLKIT_DIR" cat-file -e "${RECORDED}^{commit}" 2>/dev/null; then
    echo "Changed protocol files since $RECORDED:"
    # --no-pager on the SUMMARY specifically. This branch only runs with a TTY, so git would
    # otherwise open a pager over the diffstat and hide the prompt printed immediately below it
    # — the command appears to hang. The full diff below keeps its pager on purpose: that one is
    # meant to be read, and paging a 600-line skill diff is the point.
    # shellcheck disable=SC2086 — PROTOCOL_PATHS is a deliberate multi-pathspec list.
    git -C "$TOOLKIT_DIR" --no-pager diff --stat "$RECORDED" "$TOOLKIT_REF" -- $PROTOCOL_PATHS
    echo ""
    if [ "$APPROVED_IN_CHAT" = "1" ]; then reply=y; else
    printf "Print the full diff before acknowledging? [d=diff / y=ack / n=abort] "
    read -r reply
    fi
    case "$reply" in
      d|D) # shellcheck disable=SC2086
           git -C "$TOOLKIT_DIR" diff "$RECORDED" "$TOOLKIT_REF" -- $PROTOCOL_PATHS
           printf "Acknowledge? [y/N] "; read -r reply ;;
    esac
    case "$reply" in y|Y) ;; *) echo "Aborted — Toolkit commit line unchanged."; exit 1 ;; esac
    # shellcheck disable=SC2086
    ACK_STAT="$(git -C "$TOOLKIT_DIR" diff --shortstat "$RECORDED" "$TOOLKIT_REF" -- $PROTOCOL_PATHS | sed 's/^ *//')"
    # shellcheck disable=SC2086
    ACK_FILES="$(git -C "$TOOLKIT_DIR" diff --name-only "$RECORDED" "$TOOLKIT_REF" -- $PROTOCOL_PATHS | tr '\n' ' ')"
    ACK_FROM="$RECORDED"
  else
    # No usable prior ack (a fresh scaffold, or a sha this clone has never seen). There is no
    # diff to show, so there is nothing to pretend was read — stamp it and say so in the log.
    echo "$REGISTER records no toolkit commit this clone can diff from."
    if [ "$APPROVED_IN_CHAT" = "1" ]; then reply=y; else
    printf "Record the current protocol commit %s as this project's baseline? [y/N] " "$TOOLKIT_REF"
    read -r reply
    fi
    case "$reply" in y|Y) ;; *) echo "Aborted — Toolkit commit line unchanged."; exit 1 ;; esac
    ACK_STAT="no prior ack to diff from — recorded as a baseline"
    ACK_FILES="(baseline)"
    ACK_FROM="${RECORDED:-none}"
  fi
  if register_stamp_commit "$TOOLKIT_REF"; then
    ACK_HOW="read at a terminal"
  [ "$APPROVED_IN_CHAT" = "1" ] && ACK_HOW="approved in chat after the agent summarised it"
  build_log_append "PROTOCOL-ACK $ACK_FROM -> $TOOLKIT_REF [$ACK_HOW] ($ACK_STAT) files: $ACK_FILES"
    echo "Update taken — $REGISTER now records $TOOLKIT_REF, logged in $BUILD_LOG ($ACK_HOW)."
    exit 0
  fi
  echo "Could not find a 'Toolkit commit:' line in $REGISTER — add one reading:" >&2
  echo "  Toolkit commit: $TOOLKIT_REF" >&2
  exit 1
fi

# ── --force-stale / MXTK_ACK_STALE=1: an escape hatch with a cost ────────────
# RE-SCOPED once staleness stopped blocking: this now applies only under --strict-protocol,
# because that is the only mode left in which anything needs forcing. It is kept rather than
# dropped precisely because strict mode reintroduces the hazard that justified it — a bypass
# that is impossible gets worked around invisibly. The precedent is in this very repo: a
# false-positive {{DOUBLE_BRACE}} check had no hatch, so the "refuse to proceed" sentence was
# DELETED from all five agent templates to make the gate pass. A false positive destroyed a real
# safety net. A logged bypass keeps the workaround honest and countable instead: if
# PROTOCOL-BYPASS starts appearing weekly, that is data saying strict mode is miscalibrated.
if [ "$SYNC_BLOCKING" = "1" ] && [ "$FORCE_STALE" = "1" ]; then
  build_log_append "PROTOCOL-BYPASS gate=${REQUESTED_STAGE:-all} ack=${RECORDED:-none} ref=$TOOLKIT_REF note: $SYNC_NOTE"
  echo "Sync: BYPASSED via --force-stale/MXTK_ACK_STALE — recorded in $BUILD_LOG"
  SYNC_STATUS="BYPASSED"
  SYNC_BLOCKING=0
fi

# BRD drift-sync check: when a Stage-3+ decision changes something a BRD/wireframe already
# asserts, the confirming agent appends a marker to that decision's Notes cell in PROJECT.md —
# "[sync: <files> UNSYNCED]" — which ba-agent flips to "[sync: <files> synced <date>]" once the
# BRD/wireframe is actually re-synced. No gate passes while any marker is still UNSYNCED: a
# downstream agent (mdl-agent, gate-agent, a module brief) reading that BRD would otherwise
# inherit a stale assertion. See conversion-runbook.md "Requirements drift-sync" + the detection
# mechanics in iterative-build-loop.md. Projects that never adopt the convention have no markers
# → PASS, so this is inert for them.
#
# Two ways this gate used to be inert, both closed here (bug02):
#   1. It read "$PROJECT_DIR/PROJECT.md". On a project whose live register is nested, the
#      UNSYNCED markers live in a file the gate never opened. Measured: the unpatched script
#      exits 0 on `<such a project> 4` over a live "[sync: … UNSYNCED]" row.
#   2. DRIFT_STATUS initialised to PASS and the whole block was guarded by `[ -f … ]`, so a
#      MISSING register produced a green "no unsynced markers" verdict — inert by absence,
#      and stated as a positive finding. Absence of the register is now a FAIL: the gate could
#      not be evaluated, and "could not evaluate" is not "passed". (No real project on this
#      machine lacks a register, and SYNC already FAILs in that case, so this blocks nothing
#      that was not already blocked.)
UNSYNCED_ROWS=""
if [ "$REG_AMBIGUOUS" = "1" ]; then
  # Two registers exist and neither was named. "Cannot evaluate" is not "FAIL": a FAIL here would
  # block every gate over a condition that is one wiring row away, which is the behaviour this
  # wave removed everywhere else. MANUAL keeps it visibly not-a-pass without stopping anyone.
  DRIFT_STATUS="MANUAL"
  DRIFT_NOTE="cannot evaluate: $REG_COUNT differing decision registers exist and none is named — see the ⚠ notice above"
elif [ -z "$REGISTER" ] || [ ! -f "$REGISTER" ]; then
  # WAS FAIL until 2026-08-20, and FAIL here BLOCKS every `--stage N` query (see the "Gate
  # BLOCKED by unsynced BRD drift" bail-out below). So a project with no PROJECT.md could not ask
  # about any stage at all — including Stage P, whose entire job is to produce the PROJECT.md
  # being demanded. The gate held the door shut against the key.
  #
  # The branch immediately above states the rule this violated: "'cannot evaluate' is not 'FAIL':
  # a FAIL here would block every gate over a condition that is one wiring row away." A missing
  # register is exactly that, and the justification for treating it differently — "no real project
  # on this machine lacks a register" — described the author's machine, not a customer's first
  # hour. Reported from a customer round where several people never got a project scaffolded.
  DRIFT_STATUS="MANUAL"
  DRIFT_NOTE="no decision register (PROJECT.md) found under $PROJECT_DIR — nothing to read, which is not the same as nothing to report. Scaffold one with bin/init-project.sh $PROJECT_DIR"
else
  DRIFT_STATUS="PASS"
  DRIFT_NOTE="no unsynced BRD-drift markers in $REGISTER"
  UNSYNCED_ROWS="$(grep -nE '\[sync:[^]]*UNSYNCED' "$REGISTER" 2>/dev/null || true)"
  if [ -n "$UNSYNCED_ROWS" ]; then
    DRIFT_STATUS="FAIL"
    DRIFT_COUNT="$(printf '%s\n' "$UNSYNCED_ROWS" | grep -c . | tr -d ' ')"
    DRIFT_NOTE="$DRIFT_COUNT decision(s) touch a BRD/wireframe not yet re-synced (see '[sync: … UNSYNCED]' in $REGISTER) — ba-agent must update the BRD/wireframe, then flip the marker to 'synced <date>', before this gate passes"
  fi
fi
printf "Drift (BRD sync): %s — %s\n" "$DRIFT_STATUS" "$DRIFT_NOTE"

# ---------------------------------------------------------------------------
# Open questions — has the project actually ASKED what it wrote down?
#
# The pipeline has always generated questions (BRD `openQuestions`, analysis/sme-questions.md)
# and never checked that any reached the user. Measured on one real project: 46 rows in
# sme-questions.md against 7 mentions of an answer, and BRD statuses like "ASSUMED drafting
# position (a), hardcode … NOT a settled product decision" — real product decisions taken
# unilaterally. Stage 2 already required BRDs to HAVE open questions; nothing required anyone
# to answer them.
#
# The user's ruling: batch per gate, raising is mandatory, assuming is permitted only AFTER
# raising. So the blocking condition is NOT "unanswered" — it is "never raised". A question
# the user saw and delegated back ("you decide") is ASSUMED-with-consent and passes.
#
# This one BLOCKS. Protocol staleness notifies because it is toolkit hygiene; unraised
# questions are the project's own state, and shipping an architecture built on decisions the
# customer never saw is the failure the whole interview protocol exists to prevent.
OQ_STATUS="PASS"
OQ_NOTE="no unraised questions"
OQ_BLOCKING=0
OQ_JSON=""
OQ_SCRIPT="$TOOLKIT_DIR/bin/open-questions.sh"
if [ ! -x "$OQ_SCRIPT" ]; then
  OQ_STATUS="MANUAL"
  OQ_NOTE="bin/open-questions.sh not found or not executable at $OQ_SCRIPT — cannot evaluate, which is not a pass"
elif ! command -v jq >/dev/null 2>&1; then
  OQ_STATUS="MANUAL"
  OQ_NOTE="jq not installed — the open-questions collector cannot run; cannot evaluate, which is not a pass"
else
  OQ_JSON="$("$OQ_SCRIPT" "$PROJECT_DIR" --json 2>/dev/null || true)"
  if [ -z "$OQ_JSON" ]; then
    OQ_STATUS="MANUAL"
    OQ_NOTE="open-questions collector produced no output — cannot evaluate, which is not a pass"
  elif [ "$(printf '%s' "$OQ_JSON" | jq -r '.examined.nothingExamined')" = "true" ]; then
    # Zero questions because zero sources. Never render as clean.
    OQ_STATUS="MANUAL"
    OQ_NOTE="NOTHING EXAMINED — no *.brd.json and no analysis/sme-questions.md exist; zero questions found because zero sources were read"
  else
    OQ_BLOCKING="$(printf '%s' "$OQ_JSON" | jq -r '.blocking')"
    oq_examined="$(printf '%s' "$OQ_JSON" | jq -r '"\(.examined.brdFiles) BRD file(s), \(.examined.smeQuestionFiles) sme-questions file(s), \(.examined.duplicatesCollapsed) duplicate(s) collapsed"')"
    oq_counts="$(printf '%s' "$OQ_JSON" | jq -r '.counts | "UNRAISED=\(.UNRAISED) RAISED=\(.RAISED) ANSWERED=\(.ANSWERED) ASSUMED=\(.ASSUMED) MOOT=\(.MOOT) UNRECOGNISED=\(.UNRECOGNISED)"')"
    if [ "${OQ_BLOCKING:-0}" -gt 0 ]; then
      OQ_STATUS="FAIL"
      OQ_NOTE="$OQ_BLOCKING question(s) never put to the user [$oq_counts; examined $oq_examined]"
    else
      OQ_NOTE="every question has been raised [$oq_counts; examined $oq_examined]"
    fi
  fi
fi
printf "Open questions (raised?): %s — %s\n" "$OQ_STATUS" "$OQ_NOTE"

# ---------------------------------------------------------------------------
# Obligations — did the passes that owe a mark actually leave one?
#
# This started as one hand-rolled block for module LOOK coverage. It generalised the moment a
# second pass needed the same treatment: the LOOK was skipped on a real end-to-end run
# (2026-08-20) and so was wiring-sweep.md, for the identical reason — no row anywhere, and an
# absent row renders green. The declarative form lives in bin/lib/obligations.tsv; read its
# header for why, and bin/lib/install-manifest.sh's for the pattern it copies.
#
# INFORMATIONAL here, not blocking: the verify loop is optional on small projects, a module can
# legitimately have no pages (an integration module), and a project that joined at Stage 5 owes
# nothing below its adoption point. What must not happen is silence. Stage 6 still blocks.
if [ -r "$TOOLKIT_DIR/bin/lib/obligation-check.sh" ]; then
  # shellcheck source=lib/obligation-check.sh
  . "$TOOLKIT_DIR/bin/lib/obligation-check.sh"
  mxtk_obligations_report "$PROJECT_DIR" "$REGISTER"
  mxtk_obligations_reverse_check
else
  # Same discipline the table itself enforces: the checker failing is not the project passing.
  printf 'Obligations: FAULT — bin/lib/obligation-check.sh missing from %s; no pass was checked\n' "$TOOLKIT_DIR"
fi

# ---------------------------------------------------------------------------
# Artifacts — did the stages that promise a file actually leave one?
#
# The obligation check above is the mirror rule for PASSES; this is the same mirror for
# per-stage ARTIFACTS, and it exists because the pattern recurred one layer up: consumers were
# shipped with no producer anywhere (the coverage ledger had eleven executable readers and no
# spine producer; page-scope.json had two readers and a documented phantom; check_stage_6
# demanded a report nothing generated). Each was found by a human reading a failed project.
# The declarative form lives in bin/lib/artifact-manifest.tsv; read its header for why, and
# every row's consumers column for who is left waiting when it reports PENDING.
#
# INFORMATIONAL here, not blocking, same stance as the obligations block: Decision 1 of
# process/improvement-plan-e2e-reporting.md stands (nothing blocks), adoption/waivers/entry
# mode excuse what the register says they excuse, and stages the register shows not begun
# report quietly. What must not happen is silence.
if [ -r "$TOOLKIT_DIR/bin/lib/artifact-check.sh" ]; then
  # shellcheck source=lib/artifact-check.sh
  . "$TOOLKIT_DIR/bin/lib/artifact-check.sh"
  mxtk_artifacts_report "$PROJECT_DIR" "$REGISTER"
else
  # Same discipline again: the checker failing is not the project passing.
  printf 'Artifacts: FAULT — bin/lib/artifact-check.sh missing from %s; no artifact was checked\n' "$TOOLKIT_DIR"
fi

# ---------------------------------------------------------------------------
# Source sufficiency — was the source actually characterised, or did Stage 0
# pass on nobody having looked?
#
# bin/source-sufficiency.sh exists to force exactly this: open every source file, rate each
# dimension, band the verdict. Before this check, nothing ever confirmed it ran — Stage 0 passed
# on a triage.md sign-off alone, the same "instrument built, never wired to a gate" gap Open
# Questions used to have.
#
# A thin source is not a failure — the instrument's own design note says so: exit 0 for a thin
# source, the verdict is information, not a refusal. Only "nobody ran it" (no rubric, or pass
# 1/pass 2 left incomplete) fails here.
#
# BLOCKS Stage 0 only (enforced below, where the requested stage is known) — this is the
# project's own state, not toolkit hygiene, same reasoning as Open Questions.
SUFF_STATUS="PASS"
SUFF_NOTE="source sufficiency assessed"
SUFF_SCRIPT="$TOOLKIT_DIR/bin/source-sufficiency.sh"
if [ ! -x "$SUFF_SCRIPT" ]; then
  SUFF_STATUS="MANUAL"
  SUFF_NOTE="bin/source-sufficiency.sh not found or not executable at $SUFF_SCRIPT — cannot evaluate, which is not a pass"
elif ! command -v jq >/dev/null 2>&1; then
  SUFF_STATUS="MANUAL"
  SUFF_NOTE="jq not installed — cannot read the source-sufficiency report; cannot evaluate, which is not a pass"
else
  SUFF_OUT="$("$SUFF_SCRIPT" report "$PROJECT_DIR" --json --quiet 2>&1)"; SUFF_RC=$?
  case "$SUFF_RC" in
    0)
      suff_band="$(printf '%s' "$SUFF_OUT" | jq -r '.band // "unknown"' 2>/dev/null || echo unknown)"
      suff_pct="$(printf '%s' "$SUFF_OUT" | jq -r '.pct // "?"' 2>/dev/null || echo '?')"
      SUFF_NOTE="assessed: band=$suff_band pct=$suff_pct — a thin verdict is information, not a refusal"
      ;;
    3)
      SUFF_STATUS="FAIL"
      SUFF_NOTE="source was never characterised, or the assessment is incomplete — run: $SUFF_SCRIPT init $PROJECT_DIR (then fill in pass 1/pass 2), then $SUFF_SCRIPT report $PROJECT_DIR. $(printf '%s' "$SUFF_OUT" | grep -v '^source-sufficiency: this rubric predates' | tail -3 | tr '\n' ' ')"
      ;;
    4)
      SUFF_STATUS="FAIL"
      SUFF_NOTE="source-sufficiency rubric is invalid: $(printf '%s' "$SUFF_OUT" | tail -3 | tr '\n' ' ')"
      ;;
    2)
      SUFF_STATUS="MANUAL"
      SUFF_NOTE="source-sufficiency.sh usage error — cannot evaluate, which is not a pass: $(printf '%s' "$SUFF_OUT" | tail -3 | tr '\n' ' ')"
      ;;
    *)
      SUFF_STATUS="MANUAL"
      SUFF_NOTE="source-sufficiency.sh report exited $SUFF_RC (unexpected) — cannot evaluate, which is not a pass"
      ;;
  esac
fi
printf "Source sufficiency (assessed?): %s — %s\n" "$SUFF_STATUS" "$SUFF_NOTE"

# ---------------------------------------------------------------------------
# Skill routing — do the rendered surfaces still match the table?
#
# Every routing surface (README's two tables, the runbook's baseline block, each agent
# template, the stage map above, and the block sync-project.sh writes into a project's
# CLAUDE.local.md) is rendered from bin/lib/skill-routing.tsv. Hand-editing inside the markers
# reintroduces exactly the drift the table replaced — and drift here is invisible: nothing
# fails, a skill simply stops reaching anyone.
#
# NOTIFIES, never blocks. Same class as protocol staleness: this is TOOLKIT hygiene, not the
# project's own state, and a project is not broken because a routing surface in a shared repo
# needs a re-render. (Open questions block; that is the project's own state.) Run
# `bin/render-routing.sh` to fix, then re-run this gate.
ROUTING_STATUS="PASS"
ROUTING_NOTE="rendered surfaces match bin/lib/skill-routing.tsv"
RR_SCRIPT="$TOOLKIT_DIR/bin/render-routing.sh"
# Only meaningful when gate-check is run against the TOOLKIT ITSELF. It re-renders every routing
# surface in this repo and diffs them against bin/lib/skill-routing.tsv — an authoring check, and
# a 15-second one (measured 2026-08-20, ~70% of a whole gate-check run).
#
# On a customer's project it was 15 seconds spent auditing a repo they did not write, to report
# drift they cannot fix and should never have been shown. Skip it there and say why, so the row
# still appears and nobody concludes the check was quietly dropped.
if [ "$(cd "$PROJECT_DIR" 2>/dev/null && pwd -P)" != "$(cd "$TOOLKIT_DIR" 2>/dev/null && pwd -P)" ]; then
  # "SKIPPED", not "N/A": these statuses are interpolated straight into a CSS class name in the
  # dashboard, and `.N/A` is not one.
  ROUTING_STATUS="SKIPPED"
  ROUTING_NOTE="toolkit-authoring check — only runs when gate-check targets the toolkit repo itself"
elif [ ! -x "$RR_SCRIPT" ]; then
  ROUTING_STATUS="MANUAL"
  ROUTING_NOTE="bin/render-routing.sh not found or not executable at $RR_SCRIPT — cannot evaluate, which is not a pass"
else
  RR_OUT="$("$RR_SCRIPT" --check 2>&1)"; RR_RC=$?
  if [ "$RR_RC" -eq 2 ]; then
    ROUTING_STATUS="DRIFT"
    ROUTING_NOTE="$(printf '%s' "$RR_OUT" | grep -E '^(drifted|unwired):' | tr '\n' ' ')fix with: $RR_SCRIPT"
  elif [ "$RR_RC" -ne 0 ]; then
    ROUTING_STATUS="MANUAL"
    ROUTING_NOTE="render-routing.sh --check exited $RR_RC (structural error) — cannot evaluate, which is not a pass: $(printf '%s' "$RR_OUT" | tail -3 | tr '\n' ' ')"
  fi
fi
printf "Skill routing (surfaces vs table): %s — %s\n" "$ROUTING_STATUS" "$ROUTING_NOTE"

# ---------------------------------------------------------------------------
# Report disposition — did the newest test/review report's own findings get filed?
#
# skills/finding-disposition.md requires every report-producing run (module-review.md,
# existing-app-assurance.md, e2e-evidence-report.md) to route its findings through
# close-the-loop.md into docs/improvement-register.md before the run is called done — the same
# "a rule that is only read when someone remembers to read it changes nothing" gap
# bin/lib/obligations.tsv exists to close for the LOOK and the sweep. This is that same closing
# for report disposition specifically: project-bin/report-disposition-check.sh reads the newest
# report, greps it for the verdict vocabulary those skills already use, and checks whether the
# register picked up a matching entry the same day. It is an INSTRUMENT (skills-over-scripts.md):
# it never judges whether a finding matters, only whether the paper trail exists.
#
# BLOCKS Stages 5 and 6 only (enforced below, where the requested stage is known) — the same two
# stages finding-disposition.md and existing-app-assurance.md apply to. Exit 2 (FAULT — no report
# and no register exist at all) is NOT a block: early in a project there is genuinely nothing yet
# to have filed, same reasoning as source-sufficiency's Stage-0-only scope above.
DISP_STATUS="PASS"
DISP_NOTE="no un-filed report findings"
DISP_SCRIPT="$TOOLKIT_DIR/project-bin/report-disposition-check.sh"
if [ ! -x "$DISP_SCRIPT" ]; then
  DISP_STATUS="MANUAL"
  DISP_NOTE="project-bin/report-disposition-check.sh not found or not executable at $DISP_SCRIPT — cannot evaluate, which is not a pass"
else
  DISP_OUT="$("$DISP_SCRIPT" "$PROJECT_DIR" 2>&1)"; DISP_RC=$?
  case "$DISP_RC" in
    0) DISP_NOTE="$(printf '%s' "$DISP_OUT" | grep -E '^  (CLEAN|newest report)' | tr '\n' ' ' | sed 's/  */ /g')" ;;
    1) DISP_STATUS="FAIL"
       DISP_NOTE="a report shows findings/gaps with no matching $PROJECT_DIR/docs/improvement-register.md row — $(printf '%s' "$DISP_OUT" | grep -E '^  FINDING' | tr '\n' ' ' | sed 's/  */ /g')" ;;
    2) DISP_STATUS="MANUAL"
       DISP_NOTE="cannot evaluate, which is not a pass — $(printf '%s' "$DISP_OUT" | tail -3 | tr '\n' ' ')" ;;
    *) DISP_STATUS="MANUAL"
       DISP_NOTE="report-disposition-check.sh exited $DISP_RC (unexpected) — cannot evaluate, which is not a pass" ;;
  esac
fi
printf "Report disposition (findings filed?): %s — %s\n" "$DISP_STATUS" "$DISP_NOTE"

# Stage P is checked outside the numeric loop (bash 3.2 arrays need integer indices).
N_PASS=0; N_PENDING=0; N_WAIVED=0; N_FAIL=0; N_MANUAL=0; NEXT_UP=""; NEXT_UP_STATUS=""; ATTENTION=""
P_RESULT="$(check_stage_P)"
P_STATUS="${P_RESULT%%|*}"
P_NOTE="${P_RESULT#*|}"
if P_WAIVER="$(stage_waiver P)" \
   && waiver_applies "${P_WAIVER%%|*}" "$P_STATUS" "$P_NOTE"; then
  P_NOTE="${P_WAIVER#*|} · underlying check: $P_STATUS"
  P_STATUS="WAIVED"
fi
case "$P_STATUS" in
  PASS)    N_PASS=$((N_PASS+1)) ;;
  PENDING) N_PENDING=$((N_PENDING+1)); NEXT_UP="P"; NEXT_UP_STATUS=PENDING ;;
  WAIVED)  N_WAIVED=$((N_WAIVED+1)) ;;
  FAIL)    N_FAIL=$((N_FAIL+1)); NEXT_UP="P"; NEXT_UP_STATUS=FAIL
           ATTENTION="$ATTENTION
  Stage P — $P_NOTE" ;;
  *)       N_MANUAL=$((N_MANUAL+1)) ;;
esac
printf "Stage P (Kickoff): %s%s — %s\n" "$P_STATUS" "$(stage_surface_suffix P)" "$P_NOTE"

# NOT-STARTED IS NOT FAILED — done (2026-08-20). The history is kept because the obvious fix
# is WRONG and someone will propose it again.
#
# The problem: a freshly scaffolded project printed twelve consecutive red FAILs, because every
# stage checker asks "is your artifact here?" and on day one nothing is. Twelve FAILs is
# unreadable, so the one actionable line was buried in eleven that were not, and readers
# correctly learned the output did not reward reading. Raised after a customer round:
# "we need to be careful our gates are not too hard — they create more damage than good."
#
# THE ATTEMPTED FIX, AND WHY IT WAS REVERTED THE SAME DAY. Treat the first non-PASS stage as the
# frontier; relabel every later FAIL as PENDING "not started". It reads beautifully on a bare
# project and it lies on a real one. `tests/wave2/test-bug03-gates.sh` caught it immediately: a
# Stage 2 validation report reading *"NOT clean, 14 findings outstanding"* was reported as "not
# started", because Stage P happened to be incomplete too. Stage order is not artifact order —
# people scaffold BRDs before finishing intake all the time — so "downstream of the frontier"
# does not imply "has no artifacts", and the softening cannot tell a stage with nothing in it
# from a stage with something broken in it.
#
# WHAT SHIPPED INSTEAD: the discrimination comes from the checkers, never from position in the
# list. Each check_stage_N knew all along whether it bailed on "artifact absent" or on "artifact
# present and wrong" — it just collapsed both into FAIL. Absent is now PENDING; FAIL kept its
# older, narrower meaning of "I looked at something and it was wrong". Nothing here reads the
# neighbouring stages, so the Stage 2 report above still FAILs however incomplete Stage P is.
#
# The second half of the same problem — a stage that will NEVER start, because the project
# joined the toolkit later or its entry mode does not run that stage — is WAIVED, and is
# declared in the register rather than inferred. See the block above stage_waiver().
for stage in "${STAGE_NAMES[@]}"; do
  case "$stage" in
    0) result="$(check_stage_0)" ;;
    1) result="$(check_stage_1)" ;;
    2) result="$(check_stage_2)" ;;
    3) result="$(check_stage_3)" ;;
    4) result="$(check_stage_4)" ;;
    6) result="$(check_stage_6)" ;;
    7) result="$(check_stage_7)" ;;
    *) result="$(check_stage_manual)" ;;
  esac
  status="${result%%|*}"
  note="${result#*|}"

  if waiver="$(stage_waiver "$stage")" \
     && waiver_applies "${waiver%%|*}" "$status" "$note"; then
    note="${waiver#*|} · underlying check: $status"
    status="WAIVED"
  fi
  case "$status" in
    PASS)    N_PASS=$((N_PASS+1)) ;;
    PENDING) N_PENDING=$((N_PENDING+1)); [ -z "$NEXT_UP" ] && { NEXT_UP="$stage"; NEXT_UP_STATUS=PENDING; } ;;
    WAIVED)  N_WAIVED=$((N_WAIVED+1)) ;;
    FAIL)    N_FAIL=$((N_FAIL+1)); [ -z "$NEXT_UP" ] && { NEXT_UP="$stage"; NEXT_UP_STATUS=FAIL; }
             ATTENTION="$ATTENTION
  Stage $stage — $note" ;;
    *)       N_MANUAL=$((N_MANUAL+1)) ;;
  esac

  tbl_add RESULTS_TBL "$stage" "$status"
  tbl_add NOTES_TBL "$stage" "$note"
  tbl_get "$stage" "$STAGE_TITLES_TBL" || TBL_VALUE="(untitled stage)"
  printf "Stage %s (%s): %s%s — %s\n" "$stage" "$TBL_VALUE" "$status" "$(stage_surface_suffix "$stage")" "$note"
done
# Said once, after the list, because it calibrates every line above it. A reader who
# does not know that a missing Surface left the exit code alone will read the first one
# they see as a failure the gate somehow let through.
echo "Surface = the artifact a human READS to judge the stage (runbook §2). A missing one is"
echo "not a gate failure and does not affect the exit code — it is a stage nobody can review."

# ── The summary. Twelve rows is a data dump; the reader needs to know which one is theirs. ──
# Deliberately AFTER the rows, not before: the rows are the evidence and the summary is the
# claim, and a claim printed above its evidence is what people quote without checking.
echo ""
printf "Summary: %d passed · %d not started · %d waived · %d need attention · %d manual\n" \
  "$N_PASS" "$N_PENDING" "$N_WAIVED" "$N_FAIL" "$N_MANUAL"
if [ "$N_FAIL" -gt 0 ]; then
  echo "Needs attention — something is there and it is wrong:$ATTENTION"
fi
# The FIRST stage that is neither passed nor waived — whether it is empty or wrong. Skipping
# over a FAIL to name the first empty stage further down would point the reader past the thing
# actually in their way.
if [ -n "$NEXT_UP" ]; then
  tbl_get "$NEXT_UP" "$STAGE_TITLES_TBL" || TBL_VALUE="Kickoff"
  if [ "$NEXT_UP_STATUS" = "FAIL" ]; then
    printf "Next up: Stage %s (%s) — listed under 'needs attention' above.\n" "$NEXT_UP" "$TBL_VALUE"
  else
    printf "Next up: Stage %s (%s) — nothing there yet, which is not a failure.\n" "$NEXT_UP" "$TBL_VALUE"
  fi
fi
if [ "$N_WAIVED" = "0" ] && { [ "$N_PENDING" -ge 4 ] || [ "$N_FAIL" -ge 3 ]; }; then
  # Said once, and only where it could actually apply: a project with several empty stages is
  # either young (in which case this is noise it can ignore) or joined late (in which case it is
  # the whole answer, and nothing else in the output would ever tell it).
  echo ""
  echo "Already past some of these — build underway, analysis done your own way, artifacts you"
  echo "do not intend to produce? Say so once and they stop being counted against you:"
  echo "  $0 --adopt <stage> --reason \"...\" $PROJECT_DIR    (every earlier stage → WAIVED)"
  echo "  $0 --waive <stage> --reason \"...\" $PROJECT_DIR    (one stage → WAIVED)"
  echo "  $0 --waive look/<Module> --reason \"...\" $PROJECT_DIR (one PASS on one module → WAIVED)"
fi

# Regenerate index.html from these exact results — subject to three conditions, all of which
# exist because this write has destroyed a real file:
#   1. Only on a full informational run, unless --html says otherwise. A stage query is a
#      read-only question and must not dirty a working tree to answer it.
#   2. Never over a file lacking our sentinel. `> "$INDEX"` truncates before it writes, so on a
#      project whose root index.html is a real page, that page is gone — at exit 0, no warning.
#      README.md promises re-running never overwrites; this is what made that false.
#   3. Not at all when a stage request is about to be BLOCKED — a board must not be published by
#      a run that was never authorised to reach a verdict.
#
# Precedence, because these can disagree: an explicit --html overrides 1 and 3 (you asked, and
# the board shows the Sync/Drift FAIL rows, so it does not lie). Nothing overrides 2. A flag
# must not be able to destroy a file this script did not write.
INDEX="$PROJECT_DIR/index.html"
PROJECT_NAME="$(basename "$PROJECT_DIR")"
GC_SENTINEL="<!-- generated-by: mxcli-project-toolkit/bin/gate-check.sh -->"

WRITE_HTML=1
case "$HTML_MODE" in
  never)  WRITE_HTML=0 ;;
  always) WRITE_HTML=1 ;;
  auto)   [ -n "$REQUESTED_STAGE" ] && WRITE_HTML=0 ;;
esac
if [ "$WRITE_HTML" = "1" ] && [ "$HTML_MODE" != "always" ] && [ -n "$REQUESTED_STAGE" ] \
   && { [ "$SYNC_BLOCKING" = "1" ] || [ "$DRIFT_STATUS" = "FAIL" ]; }; then
  WRITE_HTML=0
fi
if [ "$WRITE_HTML" = "1" ] && [ -f "$INDEX" ] && ! grep -qF "$GC_SENTINEL" "$INDEX"; then
  # Every board written before the sentinel existed lacks it. Without this adoption step the
  # guard would refuse to touch any board already on disk — 8 of 9 wired repos on this machine —
  # so every project would warn on every run and never see its board update again. A fix whose
  # first act is to break every existing installation is not a fix.
  if grep -qF 'Conversion Dashboard' "$INDEX" && grep -qF 'Re-run bin/gate-check.sh' "$INDEX"; then
    : # legacy board from this script, pre-sentinel — adopt it; the rewrite stamps the sentinel
  else
    echo "" >&2
    echo "Refusing to overwrite $INDEX — it was not generated by this script." >&2
    echo "Move it aside, or pass --no-html to silence this. Verdicts above are unaffected." >&2
    WRITE_HTML=0
  fi
fi

if [ "$WRITE_HTML" = "1" ]; then
{
  cat <<HTML_HEAD
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
${GC_SENTINEL}
<title>${PROJECT_NAME} — Conversion Dashboard</title>
<style>
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: #f8fafc; color: #1e293b; padding: 32px 40px; }
  h1 { font-size: 22px; margin-bottom: 4px; }
  .subtitle { color: #64748b; font-size: 13px; margin-bottom: 24px; }
  table { border-collapse: collapse; width: 100%; max-width: 900px; background: #fff; border: 1px solid #e2e8f0; border-radius: 8px; overflow: hidden; }
  th, td { text-align: left; padding: 10px 14px; font-size: 13px; border-bottom: 1px solid #e2e8f0; }
  th { background: #1e293b; color: #e2e8f0; font-weight: 600; }
  tr:last-child td { border-bottom: none; }
  .status { font-weight: 700; padding: 2px 10px; border-radius: 999px; font-size: 11px; display: inline-block; }
  .PASS { background: #dcfce7; color: #166534; }
  .FAIL { background: #fee2e2; color: #991b1b; }
  .MANUAL { background: #fef3c7; color: #92400e; }
  .WARN { background: #ffedd5; color: #9a3412; }
  .NOTICE { background: #dbeafe; color: #1e40af; }
  .BYPASSED { background: #e2e8f0; color: #475569; }
  /* PENDING = downstream of work not yet done. Deliberately calm: a new project is not a broken
     one, and a board of red on day one is the reason nobody reads the board by week two. */
  .PENDING { background: #f1f5f9; color: #64748b; }
  .SKIPPED { background: #f1f5f9; color: #64748b; }
  /* WAIVED = declared out of scope for this project, in the register, with a reason. Blue-grey
     rather than green: it is settled, not achieved, and the board must not read as credit. */
  .WAIVED { background: #e0e7ff; color: #3730a3; }
  .footer { margin-top: 20px; font-size: 11px; color: #94a3b8; }
</style>
</head>
<body>
<h1>${PROJECT_NAME} — Conversion Dashboard</h1>
<div class="subtitle">Generated by bin/gate-check.sh — derived from real project files, not hand-maintained.</div>
<table>
<tr><th>Stage</th><th>Title</th><th>Status</th><th>Detail</th></tr>
HTML_HEAD

  printf '<tr><td>⟳</td><td>Protocol freshness</td><td><span class="status %s">%s</span></td><td>%s</td></tr>\n' \
    "$SYNC_STATUS" "$SYNC_STATUS" "$SYNC_NOTE"
  printf '<tr><td>⇄</td><td>BRD drift-sync</td><td><span class="status %s">%s</span></td><td>%s</td></tr>\n' \
    "$DRIFT_STATUS" "$DRIFT_STATUS" "$DRIFT_NOTE"
  printf '<tr><td>?</td><td>Open questions raised</td><td><span class="status %s">%s</span></td><td>%s</td></tr>\n' \
    "$OQ_STATUS" "$OQ_STATUS" "$(printf '%s' "$OQ_NOTE" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')"
  printf '<tr><td>~</td><td>Source sufficiency assessed</td><td><span class="status %s">%s</span></td><td>%s</td></tr>\n' \
    "$SUFF_STATUS" "$SUFF_STATUS" "$(printf '%s' "$SUFF_NOTE" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')"
  printf '<tr><td>⚑</td><td>Report disposition (Stage 5/6)</td><td><span class="status %s">%s</span></td><td>%s</td></tr>\n' \
    "$DISP_STATUS" "$DISP_STATUS" "$(printf '%s' "$DISP_NOTE" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')"
  printf '<tr><td>P</td><td>Kickoff</td><td><span class="status %s">%s</span></td><td>%s</td></tr>\n' \
    "$P_STATUS" "$P_STATUS" "$P_NOTE"
  for stage in "${STAGE_NAMES[@]}"; do
    tbl_get "$stage" "$STAGE_TITLES_TBL" || TBL_VALUE="(untitled stage)";  row_title="$TBL_VALUE"
    tbl_get "$stage" "$RESULTS_TBL"      || TBL_VALUE="FAIL";              row_status="$TBL_VALUE"
    tbl_get "$stage" "$NOTES_TBL"        || TBL_VALUE="no result recorded"; row_note="$TBL_VALUE"
    printf '<tr><td>%s</td><td>%s</td><td><span class="status %s">%s</span></td><td>%s</td></tr>\n' \
      "$stage" "$row_title" "$row_status" "$row_status" "$row_note"
  done

  cat <<HTML_TAIL
</table>
<div class="footer">
  <!-- generated-at: $(date -u '+%Y-%m-%dT%H:%M:%SZ') -->
  Board for root <code>$PROJECT_DIR</code>. A board carries no date in its body on purpose —
  see the comment above, which is excluded from change detection.
  Re-run bin/gate-check.sh $PROJECT_DIR to refresh.
</div>
</body>
</html>
HTML_TAIL
} > "$INDEX.tmp.$$"

  # Announce the path only when the board actually moved. The old unconditional "regenerated"
  # line printed on every run and so carried no information at all.
  #
  # The generated-at comment changes every run, so a naive cmp would report every board as
  # changed and defeat this entirely. Compare with that one line filtered out.
  if [ -f "$INDEX" ] \
     && grep -v 'generated-at:' "$INDEX.tmp.$$" > "$INDEX.cmp.$$" 2>/dev/null \
     && grep -v 'generated-at:' "$INDEX"        > "$INDEX.old.$$" 2>/dev/null \
     && cmp -s "$INDEX.cmp.$$" "$INDEX.old.$$"; then
    rm -f "$INDEX.tmp.$$" "$INDEX.cmp.$$" "$INDEX.old.$$"
  else
    rm -f "$INDEX.cmp.$$" "$INDEX.old.$$"
    mv -f "$INDEX.tmp.$$" "$INDEX"
    echo ""
    echo "index.html updated at $INDEX"
  fi
fi

if [ -n "$REQUESTED_STAGE" ]; then
  # Protocol staleness does NOT gate anything unless --strict-protocol was asked for. The
  # notice has already been printed above, with its lettered options; the stage verdict below
  # stands on its own merits either way.
  if [ "$SYNC_BLOCKING" = "1" ]; then
    echo "" >&2
    echo "Gate BLOCKED by protocol staleness (--strict-protocol): $SYNC_NOTE" >&2
    echo "Ack it, or re-run with --force-stale to proceed and log a PROTOCOL-BYPASS." >&2
    exit 1
  fi
  # No gate passes while a decision has drifted a BRD that was never re-synced.
  if [ "$DRIFT_STATUS" = "FAIL" ]; then
    echo "" >&2
    echo "Gate BLOCKED by unsynced BRD drift: $DRIFT_NOTE" >&2
    printf '%s\n' "$UNSYNCED_ROWS" >&2
    exit 1
  fi
  # Stage 0 does not pass while the source was never characterised. Scoped to Stage 0 only —
  # later stages do not re-check it, same as Open Questions is not re-derived per stage beyond
  # its own scoping — this is the one place the toolkit already knows the source should have
  # been graded before anything gets built on top of it.
  # WARNS, does not block (2026-08-20). Stage 0's own verdict already fails when triage.md is
  # unsigned, so blocking here added no safety — it just meant a Stage 0 query printed a refusal
  # instead of an answer, on exactly the projects least able to interpret one: brand-new ones.
  # Same shape as the drift gate two blocks up, loosened the same day and for the same reason.
  if [ "$REQUESTED_STAGE" = "0" ] && [ "$SUFF_STATUS" = "FAIL" ]; then
    advise "source-sufficiency" "Source sufficiency not established: $SUFF_NOTE"
  fi
  # No Stage-5/6 gate passes while the newest test/review report has un-filed findings.
  # finding-disposition.md and existing-app-assurance.md both apply at exactly these two
  # stages; report-disposition-check.sh is their mechanical backstop (see above). Unlike
  # source-sufficiency this BLOCKS rather than advises: an un-filed report is the exact failure
  # skills/close-the-loop.md was written to retire, and a warning shown once per key
  # (advise()'s own semantics) is too easy to have already been shown and forgotten by the time
  # a report goes un-filed again.
  if { [ "$REQUESTED_STAGE" = "5" ] || [ "$REQUESTED_STAGE" = "6" ]; } && [ "$DISP_STATUS" = "FAIL" ]; then
    echo "" >&2
    echo "Gate BLOCKED by report-disposition-check: $DISP_NOTE" >&2
    echo "Route the findings via skills/close-the-loop.md into docs/improvement-register.md" >&2
    echo "(skills/finding-disposition.md), then re-run this gate." >&2
    exit 1
  fi
  # No gate passes while questions this stage owns were never put to the user.
  #
  # Deliberately invoked LAST, only on a gate that would otherwise PASS. An earlier draft ran
  # it up here, ahead of the stage's own verdict, and its "nothing examined" MANUAL then
  # hijacked stages that were already FAILing for their own reasons — turning 8 exit-1
  # verdicts into exit 2 across two existing fixtures. A stage that fails on its own evidence
  # must keep saying so; this check exists to stop a PASS, not to relabel a failure.
  enforce_open_questions() { # enforce_open_questions <stage-id>
    local st="$1" arg="" j blk counts QR_SCRIPT QR_OUT
    case "$st" in P|p) return 0 ;; esac
    case "$st" in [0-7]) arg="--stage $st" ;; esac
    # Nothing examined: only meaningful from Stage 2, when BRDs are supposed to exist.
    # Before that there is genuinely nothing to have raised, and Stage 2's own check already
    # FAILs a project with no BRDs — escalating here would just duplicate it one stage early.
    if [ "$OQ_STATUS" = "MANUAL" ]; then
      case "$st" in
        0|1) echo "" >&2; echo "Note: open questions not evaluated — $OQ_NOTE" >&2; return 0 ;;
        *)   echo "" >&2
             echo "Gate NOT EVALUATED for open questions: $OQ_NOTE" >&2
             echo "This is not a pass. Fix the collector or the project layout, then re-run." >&2
             exit 2 ;;
      esac
    fi
    j="$("$OQ_SCRIPT" "$PROJECT_DIR" $arg --json 2>/dev/null || true)"
    blk="$(printf '%s' "$j" | jq -r '.blocking // 0' 2>/dev/null || echo 0)"
    [ "${blk:-0}" -gt 0 ] || return 0
    counts="$(printf '%s' "$j" | jq -r '.counts | "UNRAISED=\(.UNRAISED) UNRECOGNISED=\(.UNRECOGNISED) (of \(.total) examined)"')"
    echo "" >&2
    echo "Gate BLOCKED: $blk question(s) at stage $st have never been raised with the user." >&2
    echo "  $counts" >&2
    # Write the triage report the user reads, alongside the batch the agent reads.
    # A terminal dump scrolls away and only the agent ever sees it; the HTML is the artefact
    # a human can open, sort by state, and hand to someone else. --no-html suppresses it for
    # the same reason it suppresses the board: a read-only query must not dirty a tree.
    QR_SCRIPT="$TOOLKIT_DIR/bin/questions-report.sh"
    QR_OUT="$PROJECT_DIR/docs/open-questions.html"
    if [ "$HTML_MODE" != "never" ] && [ -x "$QR_SCRIPT" ]; then
      "$QR_SCRIPT" "$PROJECT_DIR" $arg -o "$QR_OUT" --quiet >/dev/null 2>&1
      [ -f "$QR_OUT" ] || QR_OUT=""
    else
      QR_OUT=""
    fi

    echo "" >&2
    echo "  See them, as a chat-ready batch:" >&2
    echo "    $OQ_SCRIPT $PROJECT_DIR${arg:+ $arg}" >&2
    [ -n "$QR_OUT" ] && echo "  Triage report (open this, and give the user the path): $QR_OUT" >&2
    echo "" >&2
    echo "  Raising is mandatory; assuming is not forbidden. Anything the user hands back" >&2
    echo "  ('you decide') is recorded ASSUMED with consentBy/consentAt and stops blocking." >&2
    echo "  An assumption they never saw does not." >&2
    echo "" >&2
    echo "  HOW to raise is not free-form — read skills/interview-protocol.md. In short:" >&2
    echo "  ask in chat, in batches, every question carrying two named options and your" >&2
    echo "  recommendation. A bare question hands your analysis back to the user." >&2
    exit 1
  }
  # Pre-build readiness: a wiring preflight, not a numeric stage.
  if [ "$REQUESTED_STAGE" = "build-ready" ]; then
    echo ""
    if check_build_ready; then
      enforce_open_questions build-ready
      exit 0
    else
      exit 1
    fi
  fi
  if [ "$REQUESTED_STAGE" = "P" ] || [ "$REQUESTED_STAGE" = "p" ]; then
    if [ "$P_STATUS" = "WAIVED" ]; then
      echo ""
      echo "Stage P is WAIVED for this project: $P_NOTE"
      exit 0
    fi
    if [ "$P_STATUS" = "PENDING" ]; then
      echo "" >&2
      echo "Stage P NOT STARTED: $P_NOTE" >&2
      exit 3
    fi
    if [ "$P_STATUS" = "FAIL" ]; then
      echo "" >&2
      echo "Stage P gate FAILED: $P_NOTE" >&2
      exit 1
    fi
    exit 0
  fi
  if tbl_get "$REQUESTED_STAGE" "$RESULTS_TBL"; then
    requested_status="$TBL_VALUE"
  else
    requested_status=""
  fi
  if tbl_get "$REQUESTED_STAGE" "$NOTES_TBL"; then
    requested_note="$TBL_VALUE"
  else
    requested_note="no result recorded"
  fi
  if [ -z "$requested_status" ]; then
    echo "Error: unknown stage number: $REQUESTED_STAGE" >&2
    exit 1
  fi
  # STAGES 0 AND 1 ARE ADVISORY. They do not block and do not exit non-zero (2026-08-20).
  #
  # They produce INPUTS — a sufficiency grade, a signed triage sheet, an extraction. Nothing is
  # generated from them yet, so a hard gate there cannot protect anything; it can only stop
  # someone early, which on this customer round is precisely what it did. Value starts at the
  # BRDs: from Stage 2 on, everything downstream is built out of whatever the gate let through,
  # and that is where blocking earns its place. Soft until BRDs, hard from BRDs.
  #
  # NO EXCEPTIONS. A scope-confirmation exception lived here for part of 2026-08-20 and came out
  # with the gate it served — see the long note in check_stage_1 for why a string-presence test
  # could not do that job.
  # A declared waiver is an answer, and an answer is a pass for exit-code purposes. This is the
  # branch the whole adoption mechanism exists for: a project that joined at Stage 5 can ask
  # about Stage 3 all day and get a calm 0 with the reason, instead of a red it cannot ever clear.
  if [ "$requested_status" = "WAIVED" ]; then
    echo ""
    echo "Stage $REQUESTED_STAGE is WAIVED for this project: $requested_note"
    exit 0
  fi
  case "$REQUESTED_STAGE" in
    0|1)
      if [ "$requested_status" = "FAIL" ]; then
        advise "stage$REQUESTED_STAGE" "Stage $REQUESTED_STAGE not complete: $requested_note"
        exit 0
      fi
      if [ "$requested_status" = "PENDING" ]; then
        echo ""
        echo "Stage $REQUESTED_STAGE not started: $requested_note"
        echo "Stages 0 and 1 are advisory — this does not block anything."
        exit 0
      fi
      ;;
  esac
  # NOT STARTED gets its own exit code, and the wording is not a telling-off. The stage you
  # ASKED about still does not pass — you asked, and the honest answer is no — but a caller can
  # now tell "nothing has been done here" (3) from "something is wrong here" (1), which is the
  # difference between a project that is early and a project that is broken.
  if [ "$requested_status" = "PENDING" ]; then
    echo "" >&2
    echo "Stage $REQUESTED_STAGE NOT STARTED: $requested_note" >&2
    echo "Nothing is wrong — there is just nothing here yet. If this project is never going to" >&2
    echo "produce it, say so once and it stops being counted:" >&2
    echo "  $0 --waive $REQUESTED_STAGE --reason \"...\" $PROJECT_DIR" >&2
    exit 3
  fi
  if [ "$requested_status" = "FAIL" ]; then
    echo "" >&2
    echo "Stage $REQUESTED_STAGE gate FAILED: $requested_note" >&2
    exit 1
  fi
  # MANUAL is not PASS. Only FAIL used to exit non-zero, so every manual stage —
  # including Stage 5 (Build), the stage with the most work in it — returned 0
  # against an empty directory. "The checker said 0" then reads as a passed gate.
  # Exit 2 keeps it distinguishable from both a pass (0) and a real failure (1).
  if [ "$requested_status" = "MANUAL" ]; then
    echo "" >&2
    echo "Stage $REQUESTED_STAGE is NOT machine-checkable: $requested_note" >&2
    echo "This is not a pass. Paste the stage's own evidence (for Stage 5: the" >&2
    echo "per-module coverage checklists and each script's gate result)." >&2
    exit 2
  fi
  # The stage passes on its own evidence. Last question: was anything decided behind the
  # user's back? This is the project's own state, so unlike protocol staleness it BLOCKS.
  enforce_open_questions "$REQUESTED_STAGE"
fi

exit 0
