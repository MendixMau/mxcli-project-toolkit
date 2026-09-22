#!/usr/bin/env bash
# harvest-learnings.sh — draft contrib/inbox/ entries from a project's stored learnings.
#
# WHY THIS EXISTS. The 2026-08-31 cross-project sweep found the same toolkit bug patched
# locally in two different projects (graph-sweep's GNU-stat defect), four toolkit defects
# fixed in a project and never escalated, and whole skills trapped in project trees — because
# upstreaming was a chore performed from memory at wrap-up, i.e. never. This makes the chore
# one command: scan the project for what evaporates otherwise, write ready-to-PR inbox files.
#
# WHAT IT SCANS (all inputs are produced by mandatory chain steps — init-project.sh scaffolds
# PROJECT.md/CLAUDE.local.md/bin/, and the bug-log convention is baseline-routed):
#   1. bug-logs/**.md            — entries whose headings the toolkit's bug-logs/mxcli-bugs.md
#                                  does not carry (candidate new bugs)
#   2. PROJECT.md, CLAUDE.local.md — sections whose heading mentions toolkit promotion,
#                                  toolkit defects, or toolkit feedback (TD-table pattern)
#   3. bin/*.sh, bin/*.js        — installed toolkit scripts that differ from the toolkit's
#                                  shipped copy (a local patch that never traveled)
#
# WHAT IT WRITES. contrib/inbox/<date>-<project>-{bugs,promotions,patches}.md in the TOOLKIT
# clone this script runs from. It never commits — REVIEW EVERY GENERATED FILE FOR CLIENT DATA
# before committing (the inbox is tracked, so check-no-client-data.sh scans it, but the
# denylist cannot know your client's name).
#
# Heading matching is a heuristic (case-insensitive substring of the heading's distinctive
# text). It errs toward flagging: a false "candidate" costs triage a minute; a false "known"
# loses a bug. Drift direction (installed script differs from the shipped copy) IS determined
# mechanically: the toolkit's own git history of the shipped file is walked for a byte-identical
# past version (STALE — a stale install, nothing to harvest) before anything is diffed. Field run
# 2026-09-14 across 10 projects: 115 differing scripts, 84 STALE (68k of 79k words written were
# stale diffs nobody needed to read) and 31 genuine LOCAL-FIX. No match anywhere in history means
# a real local fix — that diff is kept, headed LOCAL-FIX, naming the closest historical base. A
# toolkit worktree with no .git (no history to walk) falls back to the old undetermined wording
# for every item rather than guessing or crashing.
#
# Usage: bin/harvest-learnings.sh <project-root>
# Exit: 0 ran (summary says how many files written, possibly zero) · 2 bad invocation

set -uo pipefail

TOOLKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR=""; INBOX_OVERRIDE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --to) INBOX_OVERRIDE="${2:-}"; shift ;;   # a company brain's inbox/ instead of the toolkit's
    -*) echo "usage: bin/harvest-learnings.sh <project-root> [--to <inbox-dir>]" >&2; exit 2 ;;
    *) PROJECT_DIR="$1" ;;
  esac
  shift
done
[ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR" ] || {
  echo "usage: bin/harvest-learnings.sh <project-root> [--to <inbox-dir>]" >&2; exit 2; }
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"
STAMP="$(date +%Y-%m-%d)"
# --to <dir>: drafts land in a COMPANY BRAIN's inbox (templates/company-brain/) instead of the
# toolkit's contrib/inbox/ — the lower-bar destination for learnings that name a client or a
# house convention (skills/company-brain.md). Same drafts, different triage desk.
INBOX="${INBOX_OVERRIDE:-$TOOLKIT_ROOT/contrib/inbox}"
mkdir -p "$INBOX"
TOOLKIT_BUGLOG="$TOOLKIT_ROOT/bug-logs/mxcli-bugs.md"
WROTE=0

front_matter() { # front_matter KIND EVIDENCE
  printf '**From:** %s\n**Date:** %s\n**Kind:** %s\n**Field evidence:** %s\n**Proposed target:** see per-item notes below\n\n---\n\n' \
    "$PROJECT_NAME" "$STAMP" "$1" "$2"
}

# ---- 1. Bug-log entries the toolkit does not carry -----------------------------------------
BUGS_OUT="$INBOX/$STAMP-$PROJECT_NAME-bugs.md"
FOUND_BUGS=0
if [ -d "$PROJECT_DIR/bug-logs" ]; then
  TMP="$(mktemp)"
  find "$PROJECT_DIR/bug-logs" -name '*.md' -type f | sort | while IFS= read -r f; do
    # Split the file on '## ' headings; test each heading's distinctive text against the
    # toolkit log. awk emits candidate sections whole, delimited for the outer loop.
    awk '
      /^## /   { if (buf != "") print buf "\x01"; buf = "" ; head = 1 }
                { if (head) buf = buf $0 "\n" }
      END      { if (buf != "") print buf "\x01" }
    ' "$f" | while IFS= read -r -d $'\x01' section; do
      heading="$(printf '%s' "$section" | head -1 | sed 's/^## *//; s/[~*`]//g')"
      # Distinctive slice: strip a leading BUG-nnn tag (numbering diverges across repos —
      # measured: personal-toolkit and the toolkit disagree from 82 up), then take 30 chars.
      slice="$(printf '%s' "$heading" | sed -E 's/^BUG-[0-9]+[: ]*//' | cut -c1-30)"
      [ -n "$slice" ] || continue
      if ! grep -qiF "$slice" "$TOOLKIT_BUGLOG" 2>/dev/null; then
        { printf '## [candidate — from %s] %s\n' "${f#$PROJECT_DIR/}" "$heading"
          printf '%s' "$section" | tail -n +2
          printf '\n'; } >> "$TMP"
      fi
    done
  done
  if [ -s "$TMP" ]; then
    { front_matter "bug" "bug-log entries in $PROJECT_NAME not found (by heading) in bug-logs/mxcli-bugs.md — verify each against the toolkit log before filing; heading match is a heuristic"
      cat "$TMP"; } > "$BUGS_OUT"
    FOUND_BUGS=1; WROTE=$((WROTE + 1))
    echo "  wrote ${BUGS_OUT#$TOOLKIT_ROOT/}"
  fi
  rm -f "$TMP"
fi
[ "$FOUND_BUGS" -eq 1 ] || echo "  bug-logs: nothing the toolkit log doesn't already carry (or no bug-logs/)"

# ---- 2. Promotion / toolkit-defect sections in the registers -------------------------------
PROMO_OUT="$INBOX/$STAMP-$PROJECT_NAME-promotions.md"
TMP="$(mktemp)"
for reg in "$PROJECT_DIR/PROJECT.md" "$PROJECT_DIR/CLAUDE.local.md"; do
  [ -f "$reg" ] || continue
  awk -v src="${reg#$PROJECT_DIR/}" '
    BEGIN { on = 0 }
    # tolower(), not IGNORECASE: IGNORECASE is gawk-only and is silently ignored by mawk and
    # BSD awk — this matched nothing on the first field run for exactly that reason.
    /^#{2,3} / {
      on = (tolower($0) ~ /toolkit (promotion|defect|feedback)|promotion (changelog|queue)|promote to (the )?toolkit/) ? 1 : 0
      if (on) printf "## [from %s] %s\n", src, substr($0, index($0, " ") + 1)
      next
    }
    on { print }
  ' "$reg" >> "$TMP"
done
if [ -s "$TMP" ]; then
  { front_matter "learning" "promotion/defect sections found in $PROJECT_NAME's decision registers — each row was already reviewed in-project; triage into the named target files"
    cat "$TMP"; } > "$PROMO_OUT"
  WROTE=$((WROTE + 1))
  echo "  wrote ${PROMO_OUT#$TOOLKIT_ROOT/}"
else
  echo "  registers: no toolkit-promotion/defect sections found"
fi
rm -f "$TMP"

# ---- 3. Local patches to installed toolkit scripts -----------------------------------------
PATCH_OUT="$INBOX/$STAMP-$PROJECT_NAME-patches.md"
TMP="$(mktemp)"
STALE_N=0
DIFF_N=0

# Direction check walks the TOOLKIT's own git history (not the project's — the project may not
# even be a git repo). A worktree with no .git (a tarball drop, an export with no history) has
# nothing to walk: checked once, up front, so every item can fall back to the old undetermined
# wording instead of guessing or crashing.
GIT_OK=0
git -C "$TOOLKIT_ROOT" rev-parse --git-dir >/dev/null 2>&1 && GIT_OK=1

if [ -d "$PROJECT_DIR/bin" ]; then
  for f in "$PROJECT_DIR"/bin/*.sh "$PROJECT_DIR"/bin/*.js; do
    [ -f "$f" ] || continue
    base="$(basename "$f")"
    shipped=""
    for cand in "$TOOLKIT_ROOT/project-bin/$base" "$TOOLKIT_ROOT/bin/$base"; do
      [ -f "$cand" ] && { shipped="$cand"; break; }
    done
    [ -n "$shipped" ] || continue
    cmp -s "$shipped" "$f" && continue

    # VERDICT stays empty ("") for the no-git case and for the rare item with no history under
    # either path (a script added to this worktree but never committed) — both render with the
    # original, direction-blind wording rather than a guess.
    VERDICT=""
    MATCH_SHORT=""; MATCH_DATE=""
    BEST_SHORT=""; BEST_DATE=""; BEST_LINES=""
    if [ "$GIT_OK" -eq 1 ]; then
      # Try the current shipped location's history first; project-bin/X may have been bin/X
      # before the project-bin split, so a file moved there has its earlier history at bin/X.
      hist_path="project-bin/$base"
      [ -n "$(git -C "$TOOLKIT_ROOT" log --format=%H -- "$hist_path" 2>/dev/null)" ] || hist_path="bin/$base"
      COMMITS="$(git -C "$TOOLKIT_ROOT" log --format='%H %h %ad' --date=short -- "$hist_path" 2>/dev/null)"
      if [ -n "$COMMITS" ]; then
        HIST_TMP="$(mktemp)"
        while IFS=' ' read -r c_full c_short c_date; do
          [ -n "$c_full" ] || continue
          git -C "$TOOLKIT_ROOT" show "$c_full:$hist_path" > "$HIST_TMP" 2>/dev/null || continue
          if cmp -s "$HIST_TMP" "$f"; then
            MATCH_SHORT="$c_short"; MATCH_DATE="$c_date"
            break
          fi
          dl="$(diff "$HIST_TMP" "$f" 2>/dev/null | wc -l | tr -d ' ')"
          if [ -z "$BEST_LINES" ] || [ "$dl" -lt "$BEST_LINES" ]; then
            BEST_LINES="$dl"; BEST_SHORT="$c_short"; BEST_DATE="$c_date"
          fi
        done <<COMMITSEOF
$COMMITS
COMMITSEOF
        rm -f "$HIST_TMP"
        if [ -n "$MATCH_SHORT" ]; then VERDICT="STALE"; else VERDICT="LOCAL-FIX"; fi
      fi
    fi

    if [ "$VERDICT" = "STALE" ]; then
      # The harvest IS this one line: "this project never synced." No diff — there is nothing
      # to read, the project copy is byte-for-byte a past shipped version.
      STALE_N=$((STALE_N + 1))
      # <project-root>, never $PROJECT_DIR: the draft is destined for the public inbox and an
      # absolute path is a home-directory leak the pre-commit guard refuses (caught 2026-09-14).
      printf -- '- bin/%s — STALE: identical to shipped %s (%s); fix: bin/sync-project.sh <project-root> --upgrade-bin %s\n\n' \
        "$base" "$MATCH_SHORT" "$MATCH_DATE" "$base" >> "$TMP"
      continue
    fi

    DIFF_N=$((DIFF_N + 1))
    {
      if [ "$VERDICT" = "LOCAL-FIX" ] && [ -n "$BEST_SHORT" ]; then
        printf '## bin/%s differs from shipped %s — LOCAL-FIX\n\n' "$base" "${shipped#$TOOLKIT_ROOT/}"
        printf 'Not byte-identical to any shipped version in toolkit history — a real local fix. Closest historical base: %s (%s), %s diff line(s) from this project'"'"'s copy. Diff (shipped -> project), truncated at 120 lines:\n\n```diff\n' \
          "$BEST_SHORT" "$BEST_DATE" "$BEST_LINES"
      else
        printf '## bin/%s differs from shipped %s\n\n' "$base" "${shipped#$TOOLKIT_ROOT/}"
        printf 'Direction is undetermined: stale install (fix: sync-project.sh --upgrade-bin) OR a local fix that never traveled. Diff (shipped -> project), truncated at 120 lines:\n\n```diff\n'
      fi
      # -L labels, not raw paths: the default header embeds absolute local paths, which
      # must never be committed. -L is supported by GNU and BSD diff alike.
      # Home-directory paths inside a project's own edits are masked for the same reason.
      diff -u -L "shipped/${shipped#$TOOLKIT_ROOT/}" -L "project/bin/$base" "$shipped" "$f" | head -120 \
        | sed -e 's#/Users/[^/ ]*#/Users/<user>#g' -e 's#/home/[^/ ]*#/home/<user>#g'
      printf '```\n\n'
    } >> "$TMP"
  done
fi
if [ -s "$TMP" ]; then
  { front_matter "fix" "installed toolkit scripts in $PROJECT_NAME/bin that differ from the shipped copy — a local patch here is a fix that never traveled (how graph-sweep's stat bug got patched twice)"
    cat "$TMP"
    [ "$GIT_OK" -eq 1 ] && printf '%s stale (one line each) · %s local fix(es) (diffs above)\n' "$STALE_N" "$DIFF_N"
  } > "$PATCH_OUT"
  WROTE=$((WROTE + 1))
  echo "  wrote ${PATCH_OUT#$TOOLKIT_ROOT/}"
else
  echo "  bin drift: installed scripts match shipped copies (or no bin/)"
fi
rm -f "$TMP"

echo ""
if [ "$WROTE" -gt 0 ]; then
  echo "$WROTE inbox file(s) drafted in $INBOX."
  echo "REVIEW EACH FOR CLIENT DATA (names, codenames, real paths — genericize), then:"
  echo "  cd $TOOLKIT_ROOT && git add contrib/inbox && git commit -- contrib/inbox && open a PR"
else
  echo "Nothing to harvest — either everything already traveled, or this project stores its"
  echo "learnings somewhere this script does not look (tell triage; see CONTRIBUTING.md lane 1)."
fi
exit 0
