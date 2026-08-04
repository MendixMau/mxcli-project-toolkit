#!/usr/bin/env bash
# Mechanical stage-gate checker — replaces "remember to self-check" with file-existence/grep checks.
#
# Always evaluates all stages (0-7) and regenerates index.html in the project directory from the
# real results, so the dashboard can never silently drift from actual project state.
#
# Usage: bin/gate-check.sh <project-dir> [stage-number]
#   - With a stage-number, additionally exits non-zero if that specific stage's check fails.
#   - Without one, evaluates and reports all stages, exits 0 regardless (informational run).

set -uo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <project-dir> [stage-number]" >&2
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

check_stage_P() {
  local f="$PROJECT_DIR/intake.md"
  if [ ! -f "$f" ]; then
    echo "FAIL|intake.md not found"
    return
  fi
  # Every "## " question section must contain an "Answered" or "Unverified — how to verify" line.
  local blanks
  blanks=$(awk '
    /^## /{ if (insec && !ok) bad++; insec=1; ok=0; next }
    insec && (/Answered/ || /Unverified/) { ok=1 }
    END { if (insec && !ok) bad++; print bad+0 }' "$f")
  local total
  total=$(grep -c '^## ' "$f")
  if [ "$total" -eq 0 ]; then
    echo "FAIL|intake.md has no question sections"
  elif [ "$blanks" -eq 0 ]; then
    echo "PASS|all $total intake questions answered or explicitly Unverified"
  else
    echo "FAIL|$blanks of $total intake questions have no answer and no 'Unverified — how to verify' line"
  fi
}

check_stage_0() {
  local f="$PROJECT_DIR/triage.md"
  if [ ! -f "$f" ]; then
    echo "FAIL|triage.md not found"
    return
  fi
  if grep -q "^## Sign-off" "$f" && grep -q "Confirmed by:" "$f"; then
    echo "PASS|triage.md has a signed-off ## Sign-off section"
  else
    echo "FAIL|triage.md exists but missing a ## Sign-off section with Confirmed by:"
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
  if grep -A2 "^## Stop condition" "$validation" | grep -qi "clean"; then
    echo "PASS|brd/*.brd.json present, validation-report.md Stop condition is Clean"
  else
    echo "FAIL|validation-report.md exists but Stop condition is not Clean"
  fi
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
  local f="$PROJECT_DIR/PROJECT.md"
  [ -f "$f" ] || return 1
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
    echo "PASS|fit-gap, blueprint render, design system, wireframes present and a Stage-3 CONFIRMED decision is in PROJECT.md"
  else
    echo "FAIL|artifacts exist but PROJECT.md has no Stage-3 CONFIRMED decision — ✋ gate: artifacts without an interview don't pass"
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
    echo "PASS|build-plan.md present and a Stage-4 CONFIRMED decision is in PROJECT.md"
  else
    echo "FAIL|build-plan.md exists but PROJECT.md has no Stage-4 CONFIRMED decision — ✋ gate: a plan nobody approved doesn't pass"
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
  local f="$PROJECT_DIR/PROJECT.md"
  if [ ! -f "$f" ]; then
    echo "FAIL|PROJECT.md not found"
    return
  fi
  # Field-exact, for the same reason as has_confirmed_decision: the old
  # `grep -i cutover | grep -q CONFIRMED` passed on a row reading UNCONFIRMED.
  if awk -F'|' '
       /^\|/ && tolower($0) ~ /cutover/ {
         for (i = 2; i <= NF; i++) {
           f = toupper($i)
           gsub(/^[ \t]+|[ \t]+$/, "", f)
           if (f == "CONFIRMED") found = 1
         }
       }
       END { exit !found }
     ' "$f"; then
    echo "PASS|CONFIRMED cutover decision found in PROJECT.md"
  else
    echo "FAIL|no CONFIRMED cutover decision in PROJECT.md (✋ gate — ASSUMED does not pass)"
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
    echo "  ✗ no module brief (architecture/modules/<Module>-brief.md) — ba-agent translation mode (module-brief.md)"
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
if [ -f "$PROJECT_DIR/PROJECT.md" ]; then
  RECORDED="$(grep -o 'Toolkit commit: [a-f0-9]*' "$PROJECT_DIR/PROJECT.md" | head -1 | awk '{print $3}')"
  if [ -n "${RECORDED:-}" ]; then
    if [ "$RECORDED" = "$TOOLKIT_REF" ]; then
      SYNC_STATUS="PASS"
      SYNC_NOTE="session acknowledged toolkit commit $TOOLKIT_REF ($SYNC_REF_LABEL)"
    elif ! git -C "$TOOLKIT_DIR" cat-file -e "${RECORDED}^{commit}" 2>/dev/null; then
      SYNC_NOTE="PROJECT.md acknowledges toolkit commit $RECORDED, which does not exist in the toolkit clone — fetch the toolkit and re-run the session-start ritual against a real commit"
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
DRIFT_STATUS="PASS"
DRIFT_NOTE="no unsynced BRD-drift markers in PROJECT.md"
if [ -f "$PROJECT_DIR/PROJECT.md" ]; then
  UNSYNCED_ROWS="$(grep -nE '\[sync:[^]]*UNSYNCED' "$PROJECT_DIR/PROJECT.md" 2>/dev/null || true)"
  if [ -n "$UNSYNCED_ROWS" ]; then
    DRIFT_STATUS="FAIL"
    DRIFT_COUNT="$(printf '%s\n' "$UNSYNCED_ROWS" | grep -c . | tr -d ' ')"
    DRIFT_NOTE="$DRIFT_COUNT decision(s) touch a BRD/wireframe not yet re-synced (see '[sync: … UNSYNCED]' in PROJECT.md) — ba-agent must update the BRD/wireframe, then flip the marker to 'synced <date>', before this gate passes"
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

# Regenerate index.html from these exact results.
INDEX="$PROJECT_DIR/index.html"
PROJECT_NAME="$(basename "$PROJECT_DIR")"

{
  cat <<HTML_HEAD
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
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
<div class="footer">Re-run bin/gate-check.sh $PROJECT_DIR to refresh.</div>
</body>
</html>
HTML_TAIL
} > "$INDEX"

echo ""
echo "index.html regenerated at $INDEX"

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
