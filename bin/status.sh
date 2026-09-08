#!/usr/bin/env bash
# status.sh — one screen: where this project is, what is done, what is overdue, and the ONE next
# action. Facts only, condensed from the instruments that already exist (gate-check.sh, the
# obligation check, coherence-cadence.sh, the doctor receipt, docs/BUILD-LOG.md, PROJECT.md).
#
#   bin/status.sh <project-root>          # the screen
#   bin/status.sh <project-root> --brief  # the three lines an agent posts in chat
#
# WHY. gate-check.sh answers "may stage N close?" in ~75 lines, and on a greenfield project at
# Stage 5 it asked for source-sufficiency and a cutover row (greenfield pilot, 2026-09-04).
# A person or agent arriving mid-project asks a different question — "where am I and what do
# I do next?" — and nothing answered it in one place, so sessions re-derived it from memory,
# which the register on a real project (2026-07-24) shows being wrong twice in one day.
#
# JUDGEMENT STAYS IN THE SKILLS (skills-over-scripts.md). The NEXT line is an ordered lookup
# over facts the instruments already emit, listed in next_action() with the skill that owns
# each rule; it never invents a verdict. If two rules fire, the earlier one wins, because it
# is the one that blocks the later.
#
# Exit 0 always — status is read, never gated on. POSIX shell + coreutils; runs gate-check
# once (≈5 s on a small project) to get obligations, artifacts and stage verdicts.
set -u
TOOLKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="${1:-}"; BRIEF=0
for a in "$@"; do case "$a" in --brief) BRIEF=1 ;; esac; done
case "$PROJECT_DIR" in ""|--*) echo "usage: bin/status.sh <project-root> [--brief]" >&2; exit 1 ;; esac
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)" || { echo "not a directory: $1" >&2; exit 1; }
REG="$PROJECT_DIR/PROJECT.md"
[ -f "$REG" ] || { echo "no PROJECT.md in $PROJECT_DIR — run bin/init-project.sh first" >&2; exit 1; }
NAME="$(basename "$PROJECT_DIR")"

# --- register facts -------------------------------------------------------------------------
STAGE_LINE="$(awk '/^## Current stage/{f=1;next} f && /^\*\*Stage/{print;exit}' "$REG" | sed -E 's/\*\*//g; s/,? *(in progress)?\.?$//')"
[ -n "$STAGE_LINE" ] || STAGE_LINE="(no Current stage line in PROJECT.md)"
ENTRY="$(grep -m1 -oE '^Entry mode: *[a-z-]+' "$REG" | sed 's/^Entry mode: *//')"
ADOPTED="$(grep -m1 -oE '^Adopted at stage: *[0-9P]+' "$REG" | sed 's/^Adopted at stage: *//')"
SKELETON="$(grep -m1 -oE '^Skeleton proven [0-9-]+' "$REG" | sed 's/^Skeleton proven //')"
UNSYNCED="$(grep -c 'UNSYNCED' "$REG" 2>/dev/null)"; UNSYNCED="${UNSYNCED:-0}"
OPEN_Q="$(awk '/^## Open questions/{f=1;next} /^## /{f=0} f && /^\| *[^|#-]/ && $0 !~ /Question *\|/ {print}' "$REG" | grep -ciE '\| *(OPEN|RAISED|PENDING)')"; OPEN_Q="${OPEN_Q:-0}"
TK_COMMIT_REG="$(grep -m1 -oE '^Toolkit commit: *[0-9a-f]+' "$REG" | sed 's/^Toolkit commit: *//')"
TK_COMMIT_NOW="$(git -C "$TOOLKIT_ROOT" rev-parse --short HEAD 2>/dev/null || echo '?')"

# --- scripts and gates ----------------------------------------------------------------------
MDL_DIR="$PROJECT_DIR/mdlsource"
N_SCRIPTS=0; N_DONE=0
if [ -d "$MDL_DIR" ]; then
  N_SCRIPTS="$(find "$MDL_DIR" -name '*.mdl' -not -path '*/gallery/*' | wc -l | tr -d ' ')"
  N_DONE="$(find "$MDL_DIR" -name 'done-*.mdl' | wc -l | tr -d ' ')"
fi
BUILD_LOG="$PROJECT_DIR/docs/BUILD-LOG.md"
LAST_FAIL=""; N_PASS=0
if [ -f "$BUILD_LOG" ]; then
  # latest row per script: `| when | `script` | gate | result | detail |`
  LATEST="$(grep -E '^\| *[0-9]{4}-' "$BUILD_LOG" | awk -F'|' '{gsub(/[` ]/,"",$3); gsub(/ /,"",$4); last[$3]=$4} END{for (s in last) print s, last[s]}')"
  N_PASS="$(printf '%s\n' "$LATEST" | grep -c ' pass$')"; N_PASS="${N_PASS:-0}"
  LAST_FAIL="$(printf '%s\n' "$LATEST" | grep -vE ' pass$' | awk '{print $1}' | head -3 | tr '\n' ' ')"
fi
NOT_DONE_PASS="$( [ -f "$BUILD_LOG" ] && printf '%s\n' "$LATEST" | awk '$2=="pass" && $1 !~ /^done-/ {print $1}' | head -3 | tr '\n' ' ' )"

# --- doctor receipt -------------------------------------------------------------------------
DR="$PROJECT_DIR/.claude/.doctor-receipt"
if [ -f "$DR" ]; then
  DR_VERDICT="$(awk 'NR==1{print $3}' "$DR")"
  DR_MTIME="$(stat -c %Y "$DR" 2>/dev/null)"; [ -n "$DR_MTIME" ] || DR_MTIME="$(stat -f %m "$DR" 2>/dev/null)"
  DR_AGE_MIN=$(( ( $(date +%s) - ${DR_MTIME:-0} ) / 60 )); [ "$DR_AGE_MIN" -lt 0 ] && DR_AGE_MIN=0   # clock skew reads as "just now", never as "days ago"
  if [ "$DR_AGE_MIN" -lt 90 ]; then DR_AGE="${DR_AGE_MIN} min ago"; elif [ "$DR_AGE_MIN" -lt 2880 ]; then DR_AGE="$((DR_AGE_MIN/60)) h ago"; else DR_AGE="$((DR_AGE_MIN/1440)) days ago"; fi
  DOCTOR="doctor $DR_VERDICT, $DR_AGE"
else
  DOCTOR="doctor never run here"
fi

# --- instruments: gate-check (once), coherence cadence --------------------------------------
# --no-html: a status READ must not rewrite the project dashboard (merge review 2026-09-08 — a
# probe on a wired project left index.html modified, the same clean-tree trip as doctor receipts).
GC="$("$TOOLKIT_ROOT/bin/gate-check.sh" --no-html "$PROJECT_DIR" 2>/dev/null)"
NEED_ATTN="$(printf '%s\n' "$GC" | awk '/^Needs attention/{f=1;next} /^Next up:/{f=0} f' | sed -E 's/^ +//' | cut -c1-140)"
N_ATTN="$(printf '%s\n' "$GC" | grep -oE '[0-9]+ need attention' | grep -oE '^[0-9]+' || echo 0)"
OB_PENDING="$(printf '%s\n' "$GC" | grep -E '^Obligation ' | grep -E ' (PENDING|FAULT) ' | awk '{print $2": "$3}' | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
MOD_OPENED="$(printf '%s\n' "$GC" | grep -m1 -E '^Obligation look ' | grep -q 'no module has been opened' && echo 0 || echo '≥1')"
GC_NEXT="$(printf '%s\n' "$GC" | grep -m1 '^Next up:' | sed 's/^Next up: *//')"
TK_UPD="$(printf '%s\n' "$GC" | grep -m1 '^Toolkit updates:' | sed 's/^Toolkit updates: *//; s/\..*$//')"
COH=""
if [ -x "$PROJECT_DIR/bin/coherence-cadence.sh" ]; then
  COH_OUT="$(cd "$PROJECT_DIR" && bash bin/coherence-cadence.sh 2>/dev/null | tail -1 | sed -E 's/^ +//')"
  COH="coherence $COH_OUT"
fi

# --- NEXT: ordered lookup, earliest wins. Owner skill in the right-hand comment. -------------
next_action() {
  if [ "$N_ATTN" -gt 0 ]; then echo "fix what gate-check flags: $(printf '%s\n' "$NEED_ATTN" | head -1)"; return; fi   # conversion-runbook.md §2
  case "$STAGE_LINE" in *"Stage 5"*|*"Stage 6"*|*"Stage 7"*)
    if [ -z "$SKELETON" ]; then echo "run the walking skeleton before the first module (skills/walking-skeleton.md)"; return; fi ;;  # walking-skeleton.md
  esac
  if [ "$UNSYNCED" -gt 0 ]; then echo "ba-agent flushes $UNSYNCED UNSYNCED marker(s) in PROJECT.md — every gate is blocked until then (conversion-runbook.md §3b)"; return; fi
  case "$COH" in *"DUE"*) echo "run process-coherence-pass.md — the cross-module seam check is due"; return ;; esac   # process-coherence-pass.md
  if [ -n "$LAST_FAIL" ]; then echo "last gate FAILED for: $LAST_FAIL— fix and re-exec (docs/BUILD-LOG.md, .mpr-snapshots/last-mxbuild-errors.json)"; return; fi   # iterative-build-loop.md Gate: BUILD
  if [ -n "$NOT_DONE_PASS" ]; then echo "gate-passed but not done-: $NOT_DONE_PASS— walk the happy path + coverage checklist, then git mv to done- (iterative-build-loop.md step 13-15)"; return; fi
  if [ -n "$OB_PENDING" ]; then echo "discharge: $OB_PENDING (bin/lib/obligations.tsv names the artifact each owes)"; return; fi
  [ -n "$GC_NEXT" ] && { echo "$GC_NEXT"; return; }
  echo "nothing overdue — take the next script in architecture/build-plan.md"
}
NEXT="$(next_action)"

# --- print ----------------------------------------------------------------------------------
TK="toolkit $TK_COMMIT_NOW"; [ -n "$TK_COMMIT_REG" ] && [ "$TK_COMMIT_REG" != "$TK_COMMIT_NOW" ] && TK="$TK (register says $TK_COMMIT_REG)"
[ -n "$TK_UPD" ] && TK="$TK · updates: $TK_UPD"
if [ "$BRIEF" = 1 ]; then
  echo "WHERE   $NAME · $STAGE_LINE${ENTRY:+ · $ENTRY}${ADOPTED:+ · joined at $ADOPTED}"
  echo "STATE   scripts $N_SCRIPTS written / $N_PASS gate-pass / $N_DONE done- · modules opened $MOD_OPENED${SKELETON:+ · skeleton $SKELETON} · UNSYNCED $UNSYNCED · open questions $OPEN_Q"
  echo "NEXT    $NEXT"
  exit 0
fi
printf '\n%s — %s%s%s\n' "$NAME" "$STAGE_LINE" "${ENTRY:+ · $ENTRY}" "${ADOPTED:+ · joined at stage $ADOPTED}"
printf '%s\n\n' "$TK"
printf 'DONE      scripts: %s written, %s gate-pass, %s done-  ·  modules opened: %s%s\n' "$N_SCRIPTS" "$N_PASS" "$N_DONE" "$MOD_OPENED" "${SKELETON:+  ·  skeleton proven $SKELETON}"
printf 'OVERDUE   %s  ·  %s  ·  UNSYNCED markers: %s  ·  open questions: %s\n' "$DOCTOR" "${COH:-coherence: cadence script not installed}" "$UNSYNCED" "$OPEN_Q"
[ -n "$OB_PENDING" ] && printf '          obligations pending: %s\n' "$OB_PENDING"
[ -n "$LAST_FAIL" ] && printf '          last gate FAILED: %s\n' "$LAST_FAIL"
if [ "$N_ATTN" -gt 0 ]; then printf 'ATTENTION %s\n' "$(printf '%s\n' "$NEED_ATTN" | head -3 | sed '2,$s/^/          /')"; else printf 'ATTENTION none — gate-check: %s\n' "$(printf '%s\n' "$GC" | grep -m1 '^Summary:' | sed 's/^Summary: *//')"; fi
printf '\nNEXT  →   %s\n\n' "$NEXT"
printf '(full detail: bin/gate-check.sh %s · this screen never blocks anything)\n' "$PROJECT_DIR"
