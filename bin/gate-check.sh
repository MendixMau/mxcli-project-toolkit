#!/usr/bin/env bash
# Mechanical stage-gate checker — replaces "remember to self-check" with file-existence/grep checks.
#
# Always evaluates all stages (0-7). On a full informational run it also regenerates index.html in
# the project directory from the real results, so the dashboard can never silently drift from
# actual project state. A stage-specific run answers one question and writes nothing: that is the
# invocation used in agent loops and hooks, and a read-only query must leave no trace.
#
# Usage: bin/gate-check.sh [--html|--no-html] <project-dir> [stage-number]
#   - With a stage-number, additionally exits non-zero if that specific stage's check fails.
#   - Without one, evaluates and reports all stages, exits 0 regardless (informational run).
#   - --html forces the dashboard write; --no-html suppresses it. Neither changes any verdict.

set -uo pipefail

# Options are collected before positionals so a project path containing spaces survives.
# The obvious `set -- $POSITIONAL` form word-splits the path and was rejected for that reason.
HTML_MODE="auto"
declare -a GC_ARGS
GC_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --html)    HTML_MODE="always" ;;
    --no-html) HTML_MODE="never" ;;
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
# workstream. Observed in WMS-Demo-main: a dead 3-BRD workstream sorted ahead of
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
# is a hand-maintained document that gets forked and abandoned: on WMS-App-main the root holds
# a July-era scaffold with one unanswered question while analysis/WMS-App/intake.md holds eight
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
# the root, it lands on exactly the same blank file. Observed on WMS-App-main: root register =
# 7 CONFIRMED rows, ack 11eafdf (16 Jul); live register at analysis/WMS-App/PROJECT.md = 42
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
for candidate in "$PROJECT_DIR/PROJECT.md" "$PROJECT_DIR"/analysis/*/PROJECT.md; do
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
  echo "Error: $REG_COUNT differing decision registers (PROJECT.md) found under $PROJECT_DIR:" >&2
  printf '%s' "$REG_MATCHES" >&2
  echo "The ✋ decision gates and the BRD drift-sync gate each grade exactly one register;" >&2
  echo "with two present, whichever one is graded is a coin flip and a green board proves" >&2
  echo "nothing. Name the live one and re-run:" >&2
  echo "  GATE_REGISTER=<path-relative-to-project-dir> $0 $*" >&2
  echo "or add a row to CLAUDE.local.md ## Wiring:" >&2
  echo "  | Decision register | analysis/<name>/PROJECT.md | the live one; the other is superseded |" >&2
  exit 2
fi

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
    echo "FAIL|intake.md not found (looked in $PROJECT_DIR/ and $ANALYSIS_BASE/)"
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
  # The qualifier branch is NOT cosmetic: VB-USI-main and TFC-TCXGraphPOC-main both write
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
    echo "FAIL|triage.md not found (looked in $PROJECT_DIR/ and $ANALYSIS_BASE/)"
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
    echo "FAIL|no non-empty 'Confirmed by:' line inside the '## Sign-off' section of $f"
  elif printf '%s' "$signer" | grep -q '\['; then
    echo "FAIL|'Confirmed by:' still holds template placeholders: \"$signer\" — replace [user]/[date] with a literal name and date ($f, ## Sign-off)"
  else
    echo "PASS|triage.md signed off by \"$signer\" [$f]"
  fi
}

check_stage_1() {
  if [ -z "$KB_DIR" ]; then
    echo "FAIL|no knowledge-base directory found"
    return
  fi
  local report="$KB_DIR/extraction-report.html"
  if [ ! -s "$report" ]; then
    echo "FAIL|$report missing or empty"
    return
  fi
  local kb_md="$KB_DIR/share/KB.md"
  if [ -f "$kb_md" ] && [ ! -s "$kb_md" ]; then
    echo "FAIL|share/KB.md exists but is empty"
    return
  fi
  echo "PASS|extraction-report.html present and non-empty$( [ -f "$kb_md" ] && echo ", KB.md present and non-empty")"
}

check_stage_2() {
  if [ -z "$KB_DIR" ]; then
    echo "FAIL|no knowledge-base directory found"
    return
  fi
  local brd_dir="$KB_DIR/brd"
  if [ ! -d "$brd_dir" ] || [ -z "$(find "$brd_dir" -maxdepth 1 -name '*.brd.json' -print -quit 2>/dev/null)" ]; then
    echo "FAIL|no brd/*.brd.json scaffolds found"
    return
  fi
  local validation="$KB_DIR/reports/validation-report.md"
  if [ ! -f "$validation" ]; then
    echo "FAIL|reports/validation-report.md not found"
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
        if (f == "CONFIRMED") found = 1
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
    echo "FAIL|missing $( [ -z "$fit_gap" ] && echo "architecture/fit-gap.md ")$( [ -z "$design_system" ] && echo "design/design-system.html")"
    return
  fi
  # Wireframes are load-bearing: ui-preflight-pages.md starts from them and the build
  # loop verifies built pages against them. A design system without wireframes is half
  # the Stage-3 deliverable (design-artifacts.md Step 3, one per screen).
  local wireframes_dir
  wireframes_dir="$(resolve_artifact "design/wireframes")"
  if [ -z "$wireframes_dir" ] || [ -z "$(find "$wireframes_dir" -maxdepth 1 -name '*.html' -print -quit 2>/dev/null)" ]; then
    echo "FAIL|design/wireframes/*.html missing — design system exists but no wireframes (design-artifacts.md Step 3); the mdl-agent's UI pre-flight cannot run without them"
    return
  fi
  # The architecture track must arrive at the ✋ gate as HTML too (architecture-blueprint.md
  # Step 7): blueprint.html is the generated checkpoint render — markdown stays canonical,
  # but a missing or stale render means the gate reviews raw Mermaid or an outdated picture.
  local blueprint_html
  blueprint_html="$(resolve_artifact "architecture/blueprint.html")"
  if [ -z "$blueprint_html" ]; then
    echo "FAIL|architecture/blueprint.html missing — the Stage-3 checkpoint render (architecture-blueprint.md Step 7); regenerate it from blueprint.md"
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
    echo "FAIL|architecture/build-plan.md not found"
    return
  fi
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
  # UI review loop report (ui-review-loop.md) — any non-empty dated report under a ui-reviews/ dir
  if [ -n "$(find "$PROJECT_DIR" -path '*/ui-reviews/ui-review-*.html' -size +0c -print -quit 2>/dev/null)" ]; then
    review_ok=1
  fi
  if [ -z "$test_ok" ]; then
    echo "FAIL|no test-report.html found (project root or reports/)"
    return
  fi
  if [ -z "$review_ok" ]; then
    echo "FAIL|test-report.html present but no UI review loop report (ui-review-*.html under a ui-reviews/ dir) — Stage 6 requires the full-app UI review (ui-review-loop.md), zero open P1"
    return
  fi
  echo "PASS|test-report.html + UI review loop report both present"
}

check_stage_7() {
  # MERGE NOTE: bug02 changes WHICH register is read, bug03 changes WHICH ROWS in it count.
  # Orthogonal; both applied.
  local f="$REGISTER"
  if [ -z "$f" ] || [ ! -f "$f" ]; then
    echo "FAIL|no decision register (PROJECT.md) found under $PROJECT_DIR"
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
    echo "FAIL|no cutover decision row in $f — add a Decisions row whose Stage field is 7 (or whose Decision names the cutover) with Status exactly CONFIRMED"
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
  if grep -q "ui-review-loop.md" "$PROJECT_DIR/CLAUDE.local.md" 2>/dev/null; then
    echo "  ✓ baseline routing references the UI review loop"
  else
    echo "  ✗ baseline routing missing UI-quality rows (ui-review-loop.md) — run bin/sync-project.sh"
    fails=$((fails+1))
  fi

  # 3. All 5 agents present with no unfilled placeholders
  local agents_dir="$PROJECT_DIR/.claude/agents" missing_agents="" a
  for a in ba-agent architect-agent mdl-agent gate-agent test-agent; do
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
    echo "  ✓ all 5 agents present, no unfilled placeholders"
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
  if find "$PROJECT_DIR" -path '*/architecture/modules/*-brief.md' -print -quit 2>/dev/null | grep -q .; then
    echo "  ✓ at least one module brief exists (architecture/modules/)"
  else
    echo "  ✗ no module brief (architecture/modules/<Module>/module-brief.md) — ba-agent translation mode (module-brief.md)"
    fails=$((fails+1))
  fi

  # 5. Design assets: wireframes + a design system file
  if find "$PROJECT_DIR" -path '*/wireframes/*.html' -print -quit 2>/dev/null | grep -q .; then
    echo "  ✓ wireframes present"
  else
    echo "  ✗ no wireframes (design/wireframes/*.html) — design-artifacts.md"
    fails=$((fails+1))
  fi
  if find "$PROJECT_DIR" \( -name 'ds.css' -o -name 'design-system.html' \) -print -quit 2>/dev/null | grep -q .; then
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
STAGE_TITLES=(
  "Triage"
  "Analysis"
  "Requirements"
  "Architecture & Design"
  "Build Plan"
  "Build"
  "Test"
  "Cutover"
)

declare -a RESULTS
declare -a NOTES

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
# form was tried: landing §1.6 turned WMS-Demo red claiming "the protocol changed" when only
# bin/ had moved. A gate that cries wolf teaches people to rubber-stamp the SHA without opening
# the runbook, which costs more than the bug it closes. See TOOLKIT-UPGRADE-PLAN.md §1.9.
TOOLKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROTOCOL_PATHS="skills agents"
TOOLKIT_HEAD="$(git -C "$TOOLKIT_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")"

# Resolve the reference tip. Fetch failure must not silently degrade to the old self-comparison:
# fall back to local HEAD so offline work isn't stranded, but label the verdict UNVERIFIED so a
# pass that proved nothing cannot read as a pass that did.
SYNC_REF_LABEL="origin"
if git -C "$TOOLKIT_DIR" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1 \
   && git -C "$TOOLKIT_DIR" fetch --quiet 2>/dev/null; then
  TOOLKIT_REF="$(git -C "$TOOLKIT_DIR" rev-parse --short '@{u}' 2>/dev/null || echo "unknown")"
else
  TOOLKIT_REF="$TOOLKIT_HEAD"
  SYNC_REF_LABEL="local HEAD — UNVERIFIED, could not reach origin"
fi

SYNC_STATUS="FAIL"
SYNC_NOTE="PROJECT.md has no 'Toolkit commit:' line — run the session-start ritual (CLAUDE.local.md): pull the toolkit, re-read the runbook, record the commit"
if [ -z "$REGISTER" ] || [ ! -f "$REGISTER" ]; then
  SYNC_NOTE="no decision register (PROJECT.md) found under $PROJECT_DIR — the session-start ritual records 'Toolkit commit: <sha>' there; without one, freshness cannot be established"
fi
# Reads $REGISTER, not "$PROJECT_DIR/PROJECT.md" (bug02): on WMS-App-main the root stub acked
# 11eafdf while the live nested register acked 13b5445, so the freshness verdict described a
# register nobody had touched since 16 July.
if [ -n "$REGISTER" ] && [ -f "$REGISTER" ]; then
  RECORDED="$(grep -o 'Toolkit commit: [a-f0-9]*' "$REGISTER" | head -1 | awk '{print $3}')"
  if [ -n "${RECORDED:-}" ]; then
    if [ "$RECORDED" = "$TOOLKIT_REF" ]; then
      SYNC_STATUS="PASS"
      SYNC_NOTE="session acknowledged toolkit commit $TOOLKIT_REF ($SYNC_REF_LABEL)"
    elif ! git -C "$TOOLKIT_DIR" cat-file -e "${RECORDED}^{commit}" 2>/dev/null; then
      SYNC_NOTE="$REGISTER acknowledges toolkit commit $RECORDED, which does not exist in the toolkit clone — fetch the toolkit and re-run the session-start ritual against a real commit"
    elif git -C "$TOOLKIT_DIR" merge-base --is-ancestor "$TOOLKIT_REF" "$RECORDED" 2>/dev/null; then
      SYNC_STATUS="PASS"
      SYNC_NOTE="ack $RECORDED is ahead of $TOOLKIT_REF ($SYNC_REF_LABEL) — unpushed toolkit work, acknowledgement is current"
    else
      # shellcheck disable=SC2086 — PROTOCOL_PATHS is a deliberate multi-pathspec list.
      SYNC_CHANGED="$(git -C "$TOOLKIT_DIR" diff --name-only "$RECORDED" "$TOOLKIT_REF" -- $PROTOCOL_PATHS 2>/dev/null || true)"
      if [ -n "$SYNC_CHANGED" ]; then
        SYNC_N="$(printf '%s\n' "$SYNC_CHANGED" | wc -l | tr -d ' ')"
        SYNC_NOTE="protocol changed since this session's ack ($RECORDED → $TOOLKIT_REF, $SYNC_REF_LABEL) — $SYNC_N file(s): $(printf '%s' "$SYNC_CHANGED" | tr '\n' ' ')— re-read them, then update the Toolkit commit line"
      else
        SYNC_STATUS="PASS"
        SYNC_NOTE="ack $RECORDED is behind $TOOLKIT_REF ($SYNC_REF_LABEL) but no protocol path (${PROTOCOL_PATHS// /, }) changed — acknowledgement still valid"
      fi
    fi
  fi
fi
printf "Sync (Protocol freshness): %s — %s\n" "$SYNC_STATUS" "$SYNC_NOTE"

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
if [ -z "$REGISTER" ] || [ ! -f "$REGISTER" ]; then
  DRIFT_STATUS="FAIL"
  DRIFT_NOTE="no decision register (PROJECT.md) found under $PROJECT_DIR — the BRD drift-sync gate has nothing to read, which is not the same as nothing to report"
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

# Stage P is checked outside the numeric loop (bash 3.2 arrays need integer indices).
P_RESULT="$(check_stage_P)"
P_STATUS="${P_RESULT%%|*}"
P_NOTE="${P_RESULT#*|}"
printf "Stage P (Kickoff): %s — %s\n" "$P_STATUS" "$P_NOTE"

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
  RESULTS[$stage]="$status"
  NOTES[$stage]="$note"
  printf "Stage %s (%s): %s — %s\n" "$stage" "${STAGE_TITLES[$stage]}" "$status" "$note"
done

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
   && { [ "$SYNC_STATUS" = "FAIL" ] || [ "$DRIFT_STATUS" = "FAIL" ]; }; then
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
  printf '<tr><td>P</td><td>Kickoff</td><td><span class="status %s">%s</span></td><td>%s</td></tr>\n' \
    "$P_STATUS" "$P_STATUS" "$P_NOTE"
  for stage in "${STAGE_NAMES[@]}"; do
    printf '<tr><td>%s</td><td>%s</td><td><span class="status %s">%s</span></td><td>%s</td></tr>\n' \
      "$stage" "${STAGE_TITLES[$stage]}" "${RESULTS[$stage]}" "${RESULTS[$stage]}" "${NOTES[$stage]}"
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
  # No gate passes from a stale protocol read — freshness gates everything.
  if [ "$SYNC_STATUS" = "FAIL" ]; then
    echo "" >&2
    echo "Gate BLOCKED by protocol staleness: $SYNC_NOTE" >&2
    exit 1
  fi
  # No gate passes while a decision has drifted a BRD that was never re-synced.
  if [ "$DRIFT_STATUS" = "FAIL" ]; then
    echo "" >&2
    echo "Gate BLOCKED by unsynced BRD drift: $DRIFT_NOTE" >&2
    printf '%s\n' "$UNSYNCED_ROWS" >&2
    exit 1
  fi
  # Pre-build readiness: a wiring preflight, not a numeric stage.
  if [ "$REQUESTED_STAGE" = "build-ready" ]; then
    echo ""
    if check_build_ready; then
      exit 0
    else
      exit 1
    fi
  fi
  if [ "$REQUESTED_STAGE" = "P" ] || [ "$REQUESTED_STAGE" = "p" ]; then
    if [ "$P_STATUS" = "FAIL" ]; then
      echo "" >&2
      echo "Stage P gate FAILED: $P_NOTE" >&2
      exit 1
    fi
    exit 0
  fi
  requested_status="${RESULTS[$REQUESTED_STAGE]:-}"
  if [ -z "$requested_status" ]; then
    echo "Error: unknown stage number: $REQUESTED_STAGE" >&2
    exit 1
  fi
  if [ "$requested_status" = "FAIL" ]; then
    echo "" >&2
    echo "Stage $REQUESTED_STAGE gate FAILED: ${NOTES[$REQUESTED_STAGE]}" >&2
    exit 1
  fi
  # MANUAL is not PASS. Only FAIL used to exit non-zero, so every manual stage —
  # including Stage 5 (Build), the stage with the most work in it — returned 0
  # against an empty directory. "The checker said 0" then reads as a passed gate.
  # Exit 2 keeps it distinguishable from both a pass (0) and a real failure (1).
  if [ "$requested_status" = "MANUAL" ]; then
    echo "" >&2
    echo "Stage $REQUESTED_STAGE is NOT machine-checkable: ${NOTES[$REQUESTED_STAGE]}" >&2
    echo "This is not a pass. Paste the stage's own evidence (for Stage 5: the" >&2
    echo "per-module coverage checklists and each script's gate result)." >&2
    exit 2
  fi
fi

exit 0
