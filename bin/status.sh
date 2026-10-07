#!/usr/bin/env bash
# status.sh — one screen: where this project is, what is done, what is overdue, and the ONE next
# action. Facts only, condensed from the instruments that already exist (gate-check.sh, the
# obligation check, coherence-cadence.sh, the doctor receipt, docs/BUILD-LOG.md, PROJECT.md).
#
#   bin/status.sh <project-root>          # the screen
#   bin/status.sh <project-root> --brief  # the three lines an agent posts in chat, plus
#                                         # "Tokens this stage:" from bin/token-burn.sh, plus a
#                                         # WATCH line only when something below is wrong
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
# Shared tokeniser (see bin/lib/entry-mode.sh) — this screen used to run its own
# anchored regex, which happened to read entry mode correctly while gate-check.sh's
# old unanchored globs did not: the screen and the verdict disagreed and only the
# screen was read, which is why the verdict bug went unnoticed for as long as it did.
# One parser now, so a display fix and a gating fix can never diverge again.
. "$TOOLKIT_ROOT/bin/lib/entry-mode.sh"
. "$TOOLKIT_ROOT/bin/lib/placeholders.sh"
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
ENTRY_RAW="$(awk '
  { line = $0
    gsub(/^[ \t>*_-]+/, "", line)
    i = index(line, ":"); if (i == 0) next
    key = tolower(substr(line, 1, i - 1)); gsub(/^[ \t]+|[ \t]+$/, "", key)
    if (key ~ /^\*\*[^*\/ \t]/) key = substr(key, 3)
    if (key ~ /[^*\/ \t]\*\*$/) key = substr(key, 1, length(key) - 2)
    if (key != "entry mode") next
    v = substr(line, i + 1); gsub(/\*/, "", v); gsub(/^[ \t]+|[ \t]+$/, "", v)
    if (v != "") { print v; exit }
  }
' "$REG")"
ENTRY="$(entry_mode_token "$ENTRY_RAW" 2>/dev/null)"
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
# Gate-passed scripts still on disk WITHOUT done- (#210). Joined against the files, not read off
# the log alone: a script renamed to done- keeps its old name in the log, and counting those made
# the list point at files that no longer exist.
STALL_LIST=""
if [ -f "$BUILD_LOG" ] && [ -d "$MDL_DIR" ]; then
  STALL_LIST="$( { find "$MDL_DIR" -name '*.mdl' -not -name 'done-*' -not -path '*/gallery/*' | sed 's#.*/##; s/^/F /'
                   printf '%s\n' "$LATEST" | awk '$2=="pass" {print "P " $1}'; } \
                 | awk '$1=="F"{f[$2]=1; next} $1=="P"{p[$2]=1} END{for (k in p) if (k in f) print k}' | sort )"
fi
N_STALL="$(printf '%s' "$STALL_LIST" | grep -c .)"; N_STALL="${N_STALL:-0}"
NOT_DONE_PASS="$(printf '%s\n' "$STALL_LIST" | sed '/^$/d' | head -3 | tr '\n' ' ')"
# done- is gated on the coverage checklist (iterative-build-loop.md). Field case 2026-10-06: 47
# scripts built, 0 done-, build-plan.html empty — the checklist could never pass and nothing said
# so. Several gate-passes and ZERO done- is a stall, not a backlog.
DONE_STALL=""
[ "$N_DONE" -eq 0 ] && [ "$N_STALL" -ge 3 ] && DONE_STALL="done- stalled: $N_STALL gate-pass, 0 done-"
# build-plan.html older than the newest mdlsource/ change reads as a plan nobody is building.
BP_STALE=""
BP_HTML="$PROJECT_DIR/architecture/build-plan.html"
if [ -f "$BP_HTML" ] && [ -d "$MDL_DIR" ] && git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  _mdl_ts="$(git -C "$PROJECT_DIR" log -1 --format=%ct -- mdlsource 2>/dev/null)"
  # Commit time when the page is tracked (a fresh clone resets every mtime); mtime only for an
  # untracked, locally generated page.
  _bp_ts="$(git -C "$PROJECT_DIR" log -1 --format=%ct -- architecture/build-plan.html 2>/dev/null)"
  [ -n "$_bp_ts" ] || _bp_ts="$(stat -c %Y "$BP_HTML" 2>/dev/null || stat -f %m "$BP_HTML" 2>/dev/null)"
  case "$_mdl_ts$_bp_ts" in ''|*[!0-9]*) : ;; *)
    [ "$_bp_ts" -lt "$_mdl_ts" ] && BP_STALE="build-plan.html STALE (older than the newest mdlsource/ commit — bin/build-plan-status.sh --html)" ;;
  esac
fi
# Agent slots still unfilled (#211) — by design until each agent's stage starts, never invisible.
PH_TOTAL="$(mxtk_placeholder_total "$PROJECT_DIR"/.claude/agents/*.md "$PROJECT_DIR/CLAUDE.local.md")"
PH_FILES="$(mxtk_placeholders "$PROJECT_DIR"/.claude/agents/*.md "$PROJECT_DIR/CLAUDE.local.md" | grep -c .)"

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

# --- lint gate's last recorded run (project-bin/lint-gate.sh writes this every invocation that
# reaches a verdict; never docs/BUILD-LOG.md's exec table) -----------------------------------
LINT_LAST="$PROJECT_DIR/.claude/loop/lint-last.json"
if [ -f "$LINT_LAST" ]; then
  LINT_VERDICT="$(grep -m1 '"verdict"' "$LINT_LAST" | sed -E 's/.*"verdict": *"([^"]+)".*/\1/')"
  LINT_TS="$(grep -m1 '"timestamp"' "$LINT_LAST" | sed -E 's/.*"timestamp": *"([^"]+)".*/\1/')"
  LINT="lint ${LINT_VERDICT:-?} (${LINT_TS:-unknown time})"
else
  LINT="lint gate never recorded here"
fi

# --- instruments: gate-check (once), coherence cadence --------------------------------------
# --no-html: a status READ must not rewrite the project dashboard (merge review 2026-09-08 — a
# probe on a wired project left index.html modified, the same clean-tree trip as doctor receipts).
GC="$("$TOOLKIT_ROOT/bin/gate-check.sh" --no-html "$PROJECT_DIR" 2>/dev/null)"
NEED_ATTN="$(printf '%s\n' "$GC" | awk '/^Needs attention/{f=1;next} /^Next up:|^Approved over a failing gate:/{f=0} f' | sed -E 's/^ +//' | cut -c1-140)"
# #207: a CONFIRMED approval sitting on a red gate. gate-check names it; this repeats it, because
# the approval row is what everyone reads afterwards and the gate is read by nobody.
APPROVED_OVER="$(printf '%s\n' "$GC" | grep -m1 '^Approved over a failing gate:' | sed -E 's/^Approved over a failing gate: *//; s/ — .*$//')"
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
  if [ -n "$APPROVED_OVER" ]; then echo "$APPROVED_OVER is approved in PROJECT.md but its gate FAILS — fix the gate, or re-open the approval with the user (bin/gate-check.sh)"; return; fi   # conversion-runbook.md §2
  if [ "$N_ATTN" -gt 0 ]; then echo "fix what gate-check flags: $(printf '%s\n' "$NEED_ATTN" | head -1)"; return; fi   # conversion-runbook.md §2
  case "$STAGE_LINE" in *"Stage 5"*|*"Stage 6"*|*"Stage 7"*)
    if [ -z "$SKELETON" ]; then echo "run the walking skeleton before the first module (skills/walking-skeleton.md)"; return; fi ;;  # walking-skeleton.md
  esac
  case "$STAGE_LINE" in *"Stage 5"*|*"Stage 6"*|*"Stage 7"*)
    if [ "${PH_TOTAL:-0}" -gt 0 ]; then echo "complete the agent stubs: $PH_TOTAL unfilled {{...}} slot(s) in $PH_FILES file(s) — bin/sync-project.sh lists them (agent-roles.md)"; return; fi ;;
  esac
  if [ "$UNSYNCED" -gt 0 ]; then echo "ba-agent flushes $UNSYNCED UNSYNCED marker(s) in PROJECT.md — every gate is blocked until then (conversion-runbook.md §3b)"; return; fi
  case "$COH" in *"DUE"*) echo "run process-coherence-pass.md — the cross-module seam check is due"; return ;; esac   # process-coherence-pass.md
  if [ -n "$LAST_FAIL" ]; then echo "last gate FAILED for: $LAST_FAIL— fix and re-exec (docs/BUILD-LOG.md, .mpr-snapshots/last-mxbuild-errors.json)"; return; fi   # iterative-build-loop.md Gate: BUILD
  if [ -n "$DONE_STALL" ]; then echo "$DONE_STALL — done- needs the coverage checklist; run bin/coverage-preflight.sh to see what blocks it (iterative-build-loop.md)"; return; fi
  if [ -n "$NOT_DONE_PASS" ]; then echo "gate-passed but not done-: $NOT_DONE_PASS— walk the happy path + coverage checklist, then git mv to done- (iterative-build-loop.md step 13-15)"; return; fi
  if [ -n "$OB_PENDING" ]; then echo "discharge: $OB_PENDING (bin/lib/obligations.tsv names the artifact each owes)"; return; fi
  [ -n "$GC_NEXT" ] && { echo "$GC_NEXT"; return; }
  echo "nothing overdue — take the next script in architecture/build-plan.md"
}
NEXT="$(next_action)"

# --- context packs reachable? -------------------------------------------------------------
# A brief with no "### Build steps" table makes context-pack.sh exit 3, and the helper is handed
# the whole reading list instead of one file for its step. Silent by design (old briefs must keep
# working), which is why nobody noticed: two field builds (2026-10-07) ran with packs on and no
# pack ever written, while long-lived build helpers grew to 200k tokens of context.
PACK_GAP=""
case "$STAGE_LINE" in *"Stage 5"*|*"Stage 6"*)
  _pk="$(sed -nE 's/^[*_ -]*Context packs:[*_ ]*[`]?([A-Za-z-]+).*/\1/p' "$REG" 2>/dev/null | head -1 | tr 'A-Z' 'a-z')"
  if [ "${MXTK_CONTEXT_PACKS:-$_pk}" != "off" ]; then
    _nb=0; _nm=0
    for _b in "$PROJECT_DIR"/architecture/modules/*/module-brief.md "$PROJECT_DIR"/architecture/modules/*-brief.md; do
      [ -f "$_b" ] || continue
      _nb=$((_nb + 1)); grep -q '^### Build steps' "$_b" || _nm=$((_nm + 1))
    done
    [ "$_nm" -gt 0 ] && PACK_GAP="context packs unused: $_nm of $_nb brief(s) have no '### Build steps' table, so helpers get the full reading list (module-brief.md)"
  fi ;;
esac

# --- print ----------------------------------------------------------------------------------
TK="toolkit $TK_COMMIT_NOW"; [ -n "$TK_COMMIT_REG" ] && [ "$TK_COMMIT_REG" != "$TK_COMMIT_NOW" ] && TK="$TK (register says $TK_COMMIT_REG)"
[ -n "$TK_UPD" ] && TK="$TK · updates: $TK_UPD"
WATCH=""
for _w in "${APPROVED_OVER:+APPROVED OVER A FAILING GATE: $APPROVED_OVER}" "$DONE_STALL" "${BP_STALE%% (*}" \
          "$( [ "${PH_TOTAL:-0}" -gt 0 ] && echo "agent slots unfilled: $PH_TOTAL in $PH_FILES file(s)" )" "$PACK_GAP"; do
  [ -n "$_w" ] && WATCH="${WATCH:+$WATCH · }$_w"
done
if [ "$BRIEF" = 1 ]; then
  echo "WHERE   $NAME · $STAGE_LINE${ENTRY:+ · $ENTRY}${ADOPTED:+ · joined at $ADOPTED}"
  echo "STATE   scripts $N_SCRIPTS written / $N_PASS gate-pass / $N_DONE done- · modules opened $MOD_OPENED${SKELETON:+ · skeleton $SKELETON} · UNSYNCED $UNSYNCED · open questions $OPEN_Q"
  [ -n "$WATCH" ] && echo "WATCH   $WATCH"
  echo "NEXT    $NEXT"
  "$TOOLKIT_ROOT/bin/token-burn.sh" "$PROJECT_DIR" --brief 2>/dev/null
  exit 0
fi
printf '\n%s — %s%s%s\n' "$NAME" "$STAGE_LINE" "${ENTRY:+ · $ENTRY}" "${ADOPTED:+ · joined at stage $ADOPTED}"
printf '%s\n\n' "$TK"
printf 'DONE      scripts: %s written, %s gate-pass, %s done-  ·  modules opened: %s%s\n' "$N_SCRIPTS" "$N_PASS" "$N_DONE" "$MOD_OPENED" "${SKELETON:+  ·  skeleton proven $SKELETON}"
printf 'OVERDUE   %s  ·  %s  ·  %s  ·  UNSYNCED markers: %s  ·  open questions: %s\n' "$DOCTOR" "$LINT" "${COH:-coherence: cadence script not installed}" "$UNSYNCED" "$OPEN_Q"
[ -n "$OB_PENDING" ] && printf '          obligations pending: %s\n' "$OB_PENDING"
[ -n "$LAST_FAIL" ] && printf '          last gate FAILED: %s\n' "$LAST_FAIL"
[ -n "$WATCH" ] && printf 'WATCH     %s\n' "$WATCH"
[ -n "$BP_STALE" ] && printf '          %s\n' "$BP_STALE"
if [ "$N_ATTN" -gt 0 ]; then printf 'ATTENTION %s\n' "$(printf '%s\n' "$NEED_ATTN" | head -3 | sed '2,$s/^/          /')"; else printf 'ATTENTION none — gate-check: %s\n' "$(printf '%s\n' "$GC" | grep -m1 '^Summary:' | sed 's/^Summary: *//')"; fi
printf '\nNEXT  →   %s\n\n' "$NEXT"
printf '(full detail: bin/gate-check.sh %s · this screen never blocks anything)\n' "$PROJECT_DIR"
