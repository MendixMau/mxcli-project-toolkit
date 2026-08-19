#!/bin/bash
# question-kinds.sh — split the question backlog by WHO CAN ANSWER IT, not by whether it is open.
#
# WHY THIS EXISTS. open-questions.sh answers "has the user seen this?" — a status axis, and the
# right one for consent. It cannot answer the question that actually governs pace: "does this
# need a human at all?" Without that second axis every question is equally blocking, so a thin
# source produces a wall (127 on WMS-Demo) at the interview gate and the user is asked to
# adjudicate field lengths alongside the multi-tenancy decision. Nobody reads item 90.
#
# THE FOUR KINDS. Deliberately about the ANSWERER, not about difficulty or size.
#
#   gap        The source is silent. Nobody's stated position is being overridden, because
#              nobody stated one. An agent may take a position and record it. "How long is the
#              member name field?" Asking a human is theatre.
#
#   conflict   The source says two things that cannot both be true. Resolving it means
#              overruling somebody, and that somebody is a real person who turns up at UAT.
#              An agent must never do this, however obvious the right answer looks. Human.
#
#   choice     The source is clear on the what and silent on a fork that costs real money or is
#              expensive to undo. An agent COULD pick; the point is that it shouldn't, because
#              the person who eats the cost should be the one choosing. Human.
#
#   user-only  The answer is not in the source and not derivable from it, because it is not a
#              property of the source at all. It is a fact about the user's organisation, and
#              it exists only in their head or in a document the agent has never been shown.
#              "Does a brand guideline exist?" "What accessibility standard applies?" "How many
#              concurrent users?" "Who signs off?" Human — and unlike the other three, an agent
#              has NO BASIS on which to recommend. Saying one anyway is invention with a
#              default attached. See the incident note below.
#
# The routing rule is the whole value: gaps go to agents, everything else goes to the user.
# On the BJJ reference source that is 4 questions to a human instead of nine dimensions of
# silence — not because anything was skipped, but because the gaps went somewhere else.
#
# WHY `user-only` IS SEPARATE FROM `gap`, AND WHY IT IS THE EASIEST ONE TO GET WRONG.
# Both begin "the source is silent", and they route in opposite directions. A `gap` is silence
# an agent is entitled to fill, because the answer was never anywhere. A `user-only` is silence
# that only means the agent was not given the document — the answer very much exists, on the
# user's side, and filling it is not a drafting position but a guess presented as analysis.
#
# Real incident, 2026-08-19 (USI-RoutingModule). "Are there branding inputs?" was folded into
# one line of a seven-item Stage 3 gate batch, carrying the recommended default "no branding
# assets provided — use Atlas defaults". The user approved the batch. There was, in fact, a
# real art direction — top-bar layout, industrial look, grey background, cool colours, the USI
# wordmark in the shell — and a WCAG 2.1 AA target. Neither had ever been asked for. Both were
# discovered only when the user challenged the finished design system. The question was tagged
# and treated as a `gap`; it was `user-only`, and the recommendation was the whole defect.
#
# Hence the two constraints this kind carries, enforced in interview-protocol.md rather than
# here (a counter cannot see the shape of a question you put in chat):
#   1. A `user-only` question never carries a recommendation. "I have no basis for this; you do"
#      is the honest form. State what you will assume ONLY if the user declines to answer.
#   2. A `user-only` question is never batch-approvable. It cannot be one line of an
#      approve-all-as-recommended batch, because there is no recommendation to approve.
#
# UNCLASSIFIED DEFAULTS TO `choice`, i.e. to the human. Same failure-direction discipline as
# interview-mode.sh: the direction a mistake resolves in must be "asked too much". An
# unclassified question that defaulted to `gap` would be silently absorbed by an agent, which
# is precisely the "the agent didn't interview, just continued" complaint this toolkit exists
# to answer. It is reported as UNCLASSIFIED so the count of un-triaged work stays visible
# rather than hiding inside the choice column.
#
# Usage:
#   question-kinds.sh <project-dir> [--json] [--quiet] [--strict]
#
# exit 0 assessed   2 usage   3 nothing examined (no BRDs)   1 --strict and something needs a human

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib/discover-brds.sh"

PROJECT_DIR="${1:-}"
shift 2>/dev/null || true
AS_JSON=0; QUIET=0; STRICT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --json)   AS_JSON=1 ;;
    --quiet)  QUIET=1 ;;
    --strict) STRICT=1 ;;
    -h|--help) PROJECT_DIR="" ;;
    *) echo "question-kinds: unknown option: $1" >&2; PROJECT_DIR="" ;;
  esac
  shift
done

[ -n "$PROJECT_DIR" ] || {
  echo "usage: question-kinds.sh <project-dir> [--json] [--quiet] [--strict]" >&2
  exit 2
}
[ -d "$PROJECT_DIR" ] || { echo "question-kinds: not a directory: $PROJECT_DIR" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "question-kinds: jq is required." >&2; exit 2; }

BRD_FILES=$(discover_brds "$PROJECT_DIR")
BRD_COUNT=$(count_lines "$BRD_FILES")

if [ "$BRD_COUNT" = "0" ]; then
  # Not a clean result. Distinct exit code so a caller cannot mistake "found nothing" for
  # "nothing to find" — the false-green shape this toolkit keeps producing.
  echo "question-kinds: no BRDs found under $PROJECT_DIR — nothing examined." >&2
  echo "  looked in: analysis/*/knowledge-base/brd, analysis/knowledge-base/brd, knowledge-base/brd" >&2
  exit 3
fi

# Records: kind \t id \t source \t question
RECORDS=$(printf '%s\n' "$BRD_FILES" | while IFS= read -r f; do
  [ -n "$f" ] || continue
  jq -r --arg src "$(basename "$f")" '
    def clean: (. // "") | tostring | gsub("[\t\n\r]"; " ") | gsub("  +"; " ");
    def kindof:
      ((.kind // .questionKind // "") | tostring | ascii_downcase) as $k
      | if   $k == "gap"       then "gap"
        elif $k == "conflict"  then "conflict"
        elif $k == "choice"    then "choice"
        # Spelling tolerance, deliberately narrow. These four are the forms that turn up when a
        # human or an LLM writes the tag by hand; anything else stays UNCLASSIFIED rather than
        # being guessed at, because a mis-absorbed user-only is the exact failure this kind exists
        # to stop.
        elif $k == "user-only" or $k == "useronly" or $k == "user_only" or $k == "user only"
                               then "user-only"
        else "UNCLASSIFIED" end;
    (.openQuestions // [])[] |
    [ kindof, (.id | clean), $src, (.question | clean) ] | @tsv
  ' "$f" 2>/dev/null
done)

TOTAL=$(count_lines "$RECORDS")

count_kind() {
  [ -n "$RECORDS" ] || { printf '0'; return; }
  printf '%s\n' "$RECORDS" | awk -F'\t' -v k="$1" '$1==k{n++} END{printf "%d", n+0}'
}

N_GAP=$(count_kind gap)
N_CONFLICT=$(count_kind conflict)
N_CHOICE=$(count_kind choice)
N_USERONLY=$(count_kind user-only)
N_UNCLASSIFIED=$(count_kind UNCLASSIFIED)

# The human's list. UNCLASSIFIED is in it by the failure-direction rule above.
N_HUMAN=$((N_CONFLICT + N_CHOICE + N_USERONLY + N_UNCLASSIFIED))

if [ "$AS_JSON" = "1" ]; then
  printf '{"brdCount":%s,"total":%s,"gap":%s,"conflict":%s,"choice":%s,"userOnly":%s,"unclassified":%s,"human":%s}\n' \
    "$BRD_COUNT" "$TOTAL" "$N_GAP" "$N_CONFLICT" "$N_CHOICE" "$N_USERONLY" "$N_UNCLASSIFIED" "$N_HUMAN"
elif [ "$QUIET" != "1" ]; then
  # Every count carries what it was counted against. A bare "0 conflicts" is indistinguishable
  # from a scanner that read nothing, and this toolkit has shipped that bug four times.
  echo "Question kinds: $TOTAL open question(s) across $BRD_COUNT BRD(s)"
  echo "  gap          $N_GAP  — source is silent; an agent may take a position and record it"
  echo "  conflict     $N_CONFLICT  — source contradicts itself; only a human may overrule"
  echo "  choice       $N_CHOICE  — a fork with real cost; the person who pays it decides"
  echo "  user-only    $N_USERONLY  — not in the source at all; ask plainly, offer NO recommendation"
  echo "  unclassified $N_UNCLASSIFIED  — not triaged; counted as needing a human"
  echo
  if [ "$TOTAL" = "0" ]; then
    echo "  No open questions recorded in any BRD. If the source was thin, that is a reporting"
    echo "  failure rather than good news — check bin/source-sufficiency.sh."
  else
    echo "  → $N_HUMAN question(s) need a human; $N_GAP can be absorbed by BA agents."
  fi
  if [ "$N_USERONLY" != "0" ]; then
    echo
    echo "  $N_USERONLY question(s) are 'user-only'. Ask each one SEPARATELY and with NO recommendation."
    echo "  They must not appear as lines in an approve-all-as-recommended batch: there is nothing"
    echo "  to recommend, and a default offered here is invention. See skills/interview-protocol.md."
  fi
  if [ "$N_UNCLASSIFIED" != "0" ]; then
    echo
    echo "  $N_UNCLASSIFIED question(s) have no 'kind'. Add \"kind\": \"gap\"|\"conflict\"|\"choice\"|\"user-only\"" >&2
    echo "  to each BRD openQuestion. Until then they are routed to the user, which is the safe" >&2
    echo "  direction but not the fast one." >&2
  fi
fi

if [ "$STRICT" = "1" ] && [ "$N_HUMAN" != "0" ]; then
  exit 1
fi
exit 0
