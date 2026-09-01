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
# loses a bug. Drift detection is direction-blind: a diff may mean the project is stale
# (run sync-project.sh) OR carries a local fix — the file says so and triage decides.
#
# Usage: bin/harvest-learnings.sh <project-root>
# Exit: 0 ran (summary says how many files written, possibly zero) · 2 bad invocation

set -uo pipefail

TOOLKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="${1:-}"
[ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR" ] || {
  echo "usage: bin/harvest-learnings.sh <project-root>" >&2; exit 2; }
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"
STAMP="$(date +%Y-%m-%d)"
INBOX="$TOOLKIT_ROOT/contrib/inbox"
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
if [ -d "$PROJECT_DIR/bin" ]; then
  for f in "$PROJECT_DIR"/bin/*.sh "$PROJECT_DIR"/bin/*.js; do
    [ -f "$f" ] || continue
    base="$(basename "$f")"
    shipped=""
    for cand in "$TOOLKIT_ROOT/project-bin/$base" "$TOOLKIT_ROOT/bin/$base"; do
      [ -f "$cand" ] && { shipped="$cand"; break; }
    done
    [ -n "$shipped" ] || continue
    if ! cmp -s "$shipped" "$f"; then
      {
        printf '## bin/%s differs from shipped %s\n\n' "$base" "${shipped#$TOOLKIT_ROOT/}"
        printf 'Direction is undetermined: stale install (fix: sync-project.sh --upgrade-bin) OR a local fix that never traveled. Diff (shipped -> project), truncated at 120 lines:\n\n```diff\n'
        # -L labels, not raw paths: the default header embeds absolute local paths, which
        # must never be committed. -L is supported by GNU and BSD diff alike.
        diff -u -L "shipped/${shipped#$TOOLKIT_ROOT/}" -L "project/bin/$base" "$shipped" "$f" | head -120
        printf '```\n\n'
      } >> "$TMP"
    fi
  done
fi
if [ -s "$TMP" ]; then
  { front_matter "fix" "installed toolkit scripts in $PROJECT_NAME/bin that differ from the shipped copy — a local patch here is a fix that never traveled (how graph-sweep's stat bug got patched twice)"
    cat "$TMP"; } > "$PATCH_OUT"
  WROTE=$((WROTE + 1))
  echo "  wrote ${PATCH_OUT#$TOOLKIT_ROOT/}"
else
  echo "  bin drift: installed scripts match shipped copies (or no bin/)"
fi
rm -f "$TMP"

echo ""
if [ "$WROTE" -gt 0 ]; then
  echo "$WROTE inbox file(s) drafted in contrib/inbox/."
  echo "REVIEW EACH FOR CLIENT DATA (names, codenames, real paths — genericize), then:"
  echo "  cd $TOOLKIT_ROOT && git add contrib/inbox && git commit -- contrib/inbox && open a PR"
else
  echo "Nothing to harvest — either everything already traveled, or this project stores its"
  echo "learnings somewhere this script does not look (tell triage; see CONTRIBUTING.md lane 1)."
fi
exit 0
