#!/usr/bin/env bash
# build-lead-packs.sh — build one context pack for the propose-before-build trial (HOW-TO-RUN.md).
#
#   build-lead-packs.sh A <ref>                       # arm A: current lead pack + register excerpt
#   build-lead-packs.sh B <ref> --draft <skill.md>    # arm B: arm A + draft skill + "Proposals: batch"
#   [--toolkit DIR] (default $TOOLKIT, else <toolkit clone>) [--stage 5] [--out DIR]
#
# Same conventions as tests/behaviour/build-packs.sh: the pack is every baseline file that
# routing_baseline_pack (bin/lib/skill-routing.sh) lists for <stage> and the role, at <ref>, with
# bin/runbook-slice.sh expanded, and it ends with a PACK-END line. Two differences, both because
# the actor here is the LEAD: (1) the lead has no agents/*.md stub, so none is prepended (that is
# why build-packs.sh cannot be used as-is: it cats agents/<role>-agent.md); (2) the ref is
# extracted with `git archive`, so the toolkit clone (index, worktrees, files) is never touched.
# Both arms carry the same PROJECT.md excerpt; only arm B's has the `Proposals: batch` line.
set -eu
KIT="$(cd "$(dirname "$0")" && pwd)"
usage() { sed -n '4,7p' "$0" >&2; exit 2; }
ARM="${1:-}"; REF="${2:-}"; [ -n "$ARM" ] && [ -n "$REF" ] || usage; shift 2
case "$ARM" in A|B) : ;; *) usage ;; esac
TK="${TOOLKIT:-<toolkit clone>}"; STAGE=5; DRAFT=""; OUTD="$KIT/work"
while [ $# -gt 0 ]; do
  case "$1" in
    --draft) DRAFT="${2:-}" ;; --toolkit) TK="${2:-}" ;; --stage) STAGE="${2:-}" ;; --out) OUTD="${2:-}" ;;
    *) usage ;;
  esac
  shift 2 || usage
done
[ "$ARM" = A ] || [ -f "$DRAFT" ] || { echo "arm B needs --draft <skill.md>" >&2; exit 2; }
mkdir -p "$OUTD"
TMPD="$(mktemp -d "${TMPDIR:-/tmp}/lead-pack.XXXXXX")"; trap 'rm -rf "$TMPD"' EXIT
git -C "$TK" archive "$REF" | tar -x -C "$TMPD"
sha="$(git -C "$TK" rev-parse --short "$REF")"
line="$(cd "$TMPD" && bash -c '. bin/lib/skill-routing.sh; routing_baseline_pack "$1" "$PWD" lead' _ "$STAGE")"
IFS=$'\t' read -r words files paths _ <<< "$line"
OUT="$OUTD/pack-$ARM.txt"; BODY="$OUTD/.pack-$ARM.body"
{
  echo "##### CONTEXT PACK — lead session, Stage $STAGE (toolkit @ $sha)"
  echo "##### This is everything you (the lead session) have preloaded. Toolkit root is referred to as <toolkit>/."
  for p in $paths; do
    echo
    if [ "$p" = "bin/runbook-slice.sh" ]; then
      echo "===== OUTPUT OF: bin/runbook-slice.sh $STAGE ====="; (cd "$TMPD" && bash bin/runbook-slice.sh "$STAGE")
    else
      echo "===== FILE: $p ====="; cat "$TMPD/$p"
    fi
  done
  if [ "$ARM" = B ]; then
    echo; echo "===== FILE: skills/propose-before-build.md (routed: lead, stages 3,5, experimental) ====="
    cat "$DRAFT"
  fi
  echo; echo "===== FILE: PROJECT.md (this project's register, excerpt) ====="
  if [ "$ARM" = B ]; then sed 's/^@@PROPOSALS@@$/Proposals: batch/' "$KIT/project-excerpt.md"
  else sed '/^@@PROPOSALS@@$/d' "$KIT/project-excerpt.md"; fi
} > "$BODY"
{ cat "$BODY"; echo; echo "===== END OF CONTEXT PACK ====="
  printf 'PACK-END: %s-%s\n' "$ARM" "$(cksum < "$BODY" | cut -d' ' -f1)"; } > "$OUT"
rm -f "$BODY"
printf '%s\t%s@%s\trouted=%s words/%s files\tpack=%s words, %s lines\t%s\n' "$ARM" "$REF" "$sha" "$words" "$files" \
  "$(LC_ALL=C wc -w < "$OUT" | tr -d ' ')" "$(wc -l < "$OUT" | tr -d ' ')" "$OUT"
