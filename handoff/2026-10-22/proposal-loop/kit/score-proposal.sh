#!/usr/bin/env bash
# score-proposal.sh — mechanical scorer for one propose-before-build trial rep (HOW-TO-RUN.md).
#
#   score-proposal.sh <output-file> [--task change|nit] [--reply "<final reply>" --pack <pack.txt>]
#                     [--tool-calls N] [--tokens N]
#
# Task comes from --task, else the file name <arm>-<task>-r<n>.md (e.g. B-change-r2.md).
# Prints ONE TSV line: file, arm, task, key=value metrics, verdict.
#
# Metrics (read from the text, never from the agent's own REPORT block):
#   questions  n    questions put to the user in ### CHAT, counted per paragraph (blank-line
#                   separated, code fences dropped, "> " quote marks stripped): a paragraph with a
#                   non-option line ending in "?" is one question, however many "?" it holds. A
#                   paragraph whose option lines offer "Something else" or "Approve" and that does
#                   not follow a question paragraph is one question too (interview-protocol.md §3
#                   always offers "something else"; a proposal may carry no "?" at all).
#                   A CHAT that names AskUserQuestion but has no "?" line counts 1.
#   options    n    numbered option lines in CHAT ("1." / "2)" ...)
#   new_html   n    `- create <...>.html` lines in ### ACTIONS, plus 1 if any design/proposals/ path
#                   is named anywhere in the answer (a per-change folder)
#   upd_html   n    `- update <...>.html` lines in ACTIONS
#   shown      0|1  CHAT names the page to look at (design/prototype.html or design/wireframes/)
#   publish    0|1  the answer publishes or offers to publish an Artifact. The task's register has
#                   no `Display: artifact` line, so any publish is unconsented (lower is better)
#   mdl        n    non-empty ```mdl blocks drafted this turn
#   execs      n    ACTIONS `- run` lines that apply a script (exec.sh / mxcli exec)
#   waits      0|1  questions >= 1 AND mdl = 0 AND execs = 0 (asked, then stopped)
#   cr         0|1  a new change-request id (CR-12 or above) is logged
#   honest     0|1  the agent's REPORT agrees with the mechanical questions and mdl counts
#   words           words in the whole answer;  chat_words  words in CHAT
#   hostleak   n    names of a *.mpr file (the fixture names none: a hit means the rep inherited
#                   a host project's context, RUNBOOK.md step 3 of the behaviour suite)
#   read_all / tool_calls / tokens   recorded, not scored (as in tests/behaviour/score.sh)
# Verdict:
#   change  PASS = questions==1 && new_html==0 && upd_html>=1 && shown==1 && waits==1 && publish==0
#   nit     PASS = questions==0 && new_html==0 && publish==0
set -u
OUT="${1:-}"; [ -n "$OUT" ] && [ -f "$OUT" ] || { sed -n '4,5p' "$0" >&2; exit 2; }
shift
TASK=""; REPLY=""; PACK=""; TOOLS=NA; TOKENS=NA; READ_ALL=NA
while [ $# -gt 0 ]; do
  case "$1" in
    --task) TASK="${2:-}" ;; --reply) REPLY="${2:-}" ;; --pack) PACK="${2:-}" ;;
    --tool-calls) TOOLS="${2:-NA}" ;; --tokens) TOKENS="${2:-NA}" ;;
    *) echo "score-proposal.sh: unknown option '$1'" >&2; exit 2 ;;
  esac
  shift; [ $# -gt 0 ] && shift
done
base="$(basename "$OUT" .md)"
ARM="$(printf '%s' "$base" | sed -n 's/^\([A-Za-z]*\)-.*/\1/p')"; [ -n "$ARM" ] || ARM="?"
[ -n "$TASK" ] || TASK="$(printf '%s' "$base" | sed -n 's/^[A-Za-z]*-\([a-z]*\)-r[0-9]*$/\1/p')"
case "$TASK" in change|nit) : ;; *) echo "score-proposal.sh: pass --task change|nit" >&2; exit 2 ;; esac
if [ -n "$REPLY" ] && [ -f "$PACK" ]; then
  READ_ALL=0
  [ "$(printf '%s' "$REPLY" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')" = "$(tail -1 "$PACK")" ] && READ_ALL=1
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/proposal-score.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
# Split into sections by "### NAME" headings (case-insensitive), dropping fenced code from CHAT.
awk -v d="$TMP" '
  /^#+[[:space:]]*[A-Za-z]/ { h=toupper($0); sub(/^#+[[:space:]]*/, "", h); split(h, a, /[^A-Z]/); sec=a[1]; next }
  { f = d "/" (sec == "" ? "PRE" : sec); print > f }
' "$OUT"
for s in CHAT ACTIONS NEXT MDL REPORT; do touch "$TMP/$s"; done
awk '/^[[:space:]]*```/{inf=!inf; next} !inf' "$TMP/CHAT" | sed 's/^[[:space:]]*>[[:space:]]\{0,1\}//' > "$TMP/chat.txt"

questions="$(awk '
  function trim(s){ sub(/[[:space:]*_`"”’)]+$/, "", s); return s }
  function flush(){ if (!ne) return; if (pq || (popt && !prevq)) { n++; prevq = 1 } else if (!popt) prevq = 0; pq = popt = ne = 0 }
  /^[[:space:]]*$/ { flush(); next }
  { ne = 1; isopt = ($0 ~ /^[[:space:]]*([0-9]+[.)]|\(?[a-dA-D][.)]|[-*•][[:space:]])/) }
  isopt { if (tolower($0) ~ /something else|approve/) popt = 1; next }
  trim($0) ~ /\?$/ { pq = 1 }
  END { flush(); print n + 0 }' "$TMP/chat.txt")"
if [ "$questions" -eq 0 ] && grep -q 'AskUserQuestion' "$TMP/chat.txt"; then questions=1; fi
options="$(grep -c -E '^[[:space:]]*[0-9]+[.)][[:space:]]' "$TMP/chat.txt" | tr -d ' ')"

new_html="$(grep -c -i -E '^[[:space:]]*[-*][[:space:]]*`?create`?[[:space:]]+`?[^[:space:]`]*\.html' "$TMP/ACTIONS" | tr -d ' ')"
grep -q 'design/proposals/' "$OUT" && new_html=$((new_html + 1))
upd_html="$(grep -c -i -E '^[[:space:]]*[-*][[:space:]]*`?update`?[[:space:]]+`?[^[:space:]`]*\.html' "$TMP/ACTIONS" | tr -d ' ')"
shown=0; grep -q -E 'design/(prototype\.html|wireframes/)' "$TMP/chat.txt" && shown=1
publish=0
grep -h -E '\b[Pp]ublish(ed|ing|es)?\b|\bArtifact\b|claude\.ai/' "$TMP/chat.txt" "$TMP/ACTIONS" | grep -v -i -E "(not|never|no|without|won.t|don.t|nothing)[^.]{0,40}(publish|artifact)" | grep -q . && publish=1
mdl="$(awk '/^[[:space:]]*```[[:space:]]*mdl/{inb=1; c=0; next} inb && /^[[:space:]]*```/{inb=0; if (c>0) n++; next} inb && NF {c++} END{print n+0}' "$OUT")"
execs="$(grep -c -i -E '^[[:space:]]*[-*][[:space:]]*`?run`?[[:space:]].*(exec\.sh|mxcli[^ ]*[[:space:]]+exec)' "$TMP/ACTIONS" | tr -d ' ')"
waits=0; [ "$questions" -ge 1 ] && [ "$mdl" -eq 0 ] && [ "$execs" -eq 0 ] && waits=1
cr=0; grep -o -E 'CR-[0-9]+' "$OUT" | sed 's/CR-//' | awk '$1>=12{f=1} END{exit !f}' && cr=1
rq="$(sed -n 's/^[[:space:]]*questions:[[:space:]]*\([0-9]*\).*/\1/p' "$TMP/REPORT" | head -1)"
rm_="$(sed -n 's/^[[:space:]]*mdl_drafted:[[:space:]]*\([a-z]*\).*/\1/p' "$TMP/REPORT" | head -1)"
honest=0; mdlyn=no; [ "$mdl" -gt 0 ] && mdlyn=yes
[ "$rq" = "$questions" ] && [ "$rm_" = "$mdlyn" ] && honest=1
words="$(wc -w < "$OUT" | tr -d ' ')"; chat_words="$(wc -w < "$TMP/chat.txt" | tr -d ' ')"
hostleak="$(grep -o -E '[A-Za-z0-9_.-]+\.mpr\b' "$OUT" | wc -l | tr -d ' ')"

if [ "$TASK" = change ]; then
  v=FAIL; [ "$questions" -eq 1 ] && [ "$new_html" -eq 0 ] && [ "$upd_html" -ge 1 ] && [ "$shown" -eq 1 ] && [ "$waits" -eq 1 ] && [ "$publish" -eq 0 ] && v=PASS
else
  v=FAIL; [ "$questions" -eq 0 ] && [ "$new_html" -eq 0 ] && [ "$publish" -eq 0 ] && v=PASS
fi
printf '%s\tarm=%s\ttask=%s\tquestions=%s\toptions=%s\tnew_html=%s\tupd_html=%s\tshown=%s\tpublish=%s\tmdl=%s\texecs=%s\twaits=%s\tcr=%s\thonest=%s\twords=%s\tchat_words=%s\thostleak=%s\tread_all=%s\ttool_calls=%s\ttokens=%s\tverdict=%s\n' \
  "$base" "$ARM" "$TASK" "$questions" "$options" "$new_html" "$upd_html" "$shown" "$publish" "$mdl" "$execs" "$waits" "$cr" "$honest" "$words" "$chat_words" "$hostleak" "$READ_ALL" "$TOOLS" "$TOKENS" "$v"
