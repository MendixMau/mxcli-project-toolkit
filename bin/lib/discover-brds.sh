# discover-brds.sh — the one place that knows where a project's BRDs live. Source, don't copy.
#
# WHY THIS EXISTS. On 2026-08-12 this logic existed in three places — open-questions.sh,
# gate-check.sh and facts-lock.sh — and one of them was wrong. facts-lock.sh matched only the
# FIRST knowledge-base directory, so on a project with `analysis/source/` (2 BRDs) and
# `analysis/usi-source/` (18) it read two files and reported "0 contested, 2 BRD(s) read".
# A clean result over 10% of the corpus.
#
# The comment on the correct copy said "ALL matches, not the first". It was right there, in a
# sibling file, and got re-derived wrong anyway. That is what duplication costs: the fix does
# not travel. Adding a fourth consumer without this file would have been a coin flip.
#
# Usage:
#   . "$(dirname "$0")/lib/discover-brds.sh"
#   BRD_FILES=$(discover_brds "$PROJECT_DIR")     # newline-separated, may be empty
#   BRD_COUNT=$(count_lines "$BRD_FILES")
#
# CONVENTION (do not change in one consumer). BRDs are `*.brd.json` under a `brd/` directory
# inside a knowledge base, and a knowledge base is any of:
#   <project>/analysis/*/knowledge-base    the normal layout, one per source
#   <project>/analysis/knowledge-base      single-source projects
#   <project>/knowledge-base               legacy / hand-made
# Every match is read. A project legitimately has several.

# discover_brds <project-dir> -> newline-separated paths on stdout
discover_brds() {
  _dbrd_dir="${1:-}"
  [ -n "$_dbrd_dir" ] || return 0
  for _dbrd_kb in "$_dbrd_dir"/analysis/*/knowledge-base \
                  "$_dbrd_dir"/analysis/knowledge-base \
                  "$_dbrd_dir"/knowledge-base; do
    [ -d "$_dbrd_kb/brd" ] || continue
    for _dbrd_f in "$_dbrd_kb"/brd/*.brd.json; do
      [ -f "$_dbrd_f" ] || continue
      printf '%s\n' "$_dbrd_f"
    done
  done
}

# discover_sme <project-dir> -> newline-separated paths on stdout
discover_sme() {
  _dsme_dir="${1:-}"
  [ -n "$_dsme_dir" ] || return 0
  for _dsme_f in "$_dsme_dir"/analysis/sme-questions.md "$_dsme_dir"/analysis/*/sme-questions.md; do
    [ -f "$_dsme_f" ] && printf '%s\n' "$_dsme_f"
  done
  return 0
}

# count_lines <newline-separated-string> -> integer on stdout
#
# NOT `grep -c . || echo 0`: grep prints 0 AND exits 1 on no match, so the fallback fires too
# and the result is "0\n0", which compares equal to nothing and silently defeats any
# empty-corpus check downstream. That exact bug shipped in source-sufficiency.sh and was caught
# only by a test asserting the empty case.
count_lines() {
  if [ -z "${1:-}" ]; then printf '0'; else printf '%s\n' "$1" | grep -c . | tr -d '[:space:]'; fi
}
