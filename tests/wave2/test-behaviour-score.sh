#!/usr/bin/env bash
# test-behaviour-score.sh — the behaviour-suite scorer reproduces its committed field results.
#
# Usage: bash tests/wave2/test-behaviour-score.sh tests/behaviour/score.sh
#
# Golden input: four real agent outputs from the 2026-10-15 runs (tests/behaviour/fixtures/,
# captured verbatim, one page and one mf draft from a pack arm and from the no-pack arm). Each
# is scored and every scored column must equal its row in tests/behaviour/results/. `check`
# needs an mxcli binary: with none (CI) it must read NA and is not compared; with $MXCLI set
# it is compared too. The recorded columns (read_all, tool_calls, tokens) are not scores.
set -u
SUBJ="${1:-}"; [ -n "$SUBJ" ] && [ -f "$SUBJ" ] || { echo "usage: $0 /path/to/score.sh" >&2; exit 2; }
DIR="$(cd "$(dirname "$SUBJ")" && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok    $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL  $1"; }
# scored columns only: drop the recorded ones, and check when it is NA
cols() { tr '\t' '\n' | grep -v -E '^(read_all|tool_calls|tokens)=' | { if [ "$2" = NA ]; then grep -v '^check='; else cat; fi; } | tr '\n' ' '; }
for f in M-page-r5 T-mf-r5 N-page-r1 N-mf-r1; do
  want="$(cat "$DIR"/results/*.tsv | grep -v '^#' | awk -F'\t' -v n="$f" '$1 == n' | head -1)"
  [ -n "$want" ] || { bad "$f: no committed results row"; continue; }
  got="$(MXCLI="${MXCLI:-/nonexistent/mxcli}" bash "$SUBJ" "$DIR/fixtures/$f.md")"
  chk="$(printf '%s\n' "$got" | tr '\t' '\n' | sed -n 's/^check=//p')"
  if [ -z "${MXCLI:-}" ] && [ "$chk" != NA ]; then bad "$f: check=$chk without mxcli, want NA"; fi
  a="$(printf '%s' "$got" | cols x "$chk")"; b="$(printf '%s' "$want" | cols x "$chk")"
  if [ "$a" = "$b" ]; then ok "$f: $(printf '%s' "$a" | wc -w | tr -d ' ') columns match"; else bad "$f: got [$a] want [$b]"; fi
done
# the scorer discriminates: the no-pack drafts fail the planted trap / commit inside the loop
printf '%s' "$(bash "$SUBJ" "$DIR/fixtures/N-page-r1.md")" | grep -q 'planted=0' && ok "N page: planted=0" || bad "N page: planted trap not scored 0"
printf '%s' "$(bash "$SUBJ" "$DIR/fixtures/N-mf-r1.md")" | grep -q 'cinloop=1' && ok "N mf: cinloop=1" || bad "N mf: commit-in-loop not counted"
bash "$SUBJ" "$DIR/fixtures/M-page-r5.md" --tool-calls 19 --tokens 245000 | grep -q 'read_all=NA	tool_calls=19	tokens=245000$' \
  && ok "recorded columns appended" || bad "recorded columns not appended"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
