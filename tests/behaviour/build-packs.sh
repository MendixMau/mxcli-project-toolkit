#!/usr/bin/env bash
# build-packs.sh — build one behaviour-suite context pack (RUNBOOK.md) from any toolkit ref.
#
#   tests/behaviour/build-packs.sh M <ref>                     # base, e.g. origin/master
#   tests/behaviour/build-packs.sh T <ref>                     # candidate, e.g. a PR head
#   tests/behaviour/build-packs.sh T <ref> --without <path>    # ablation: <ref>'s pack minus one file
#   tests/behaviour/build-packs.sh N                           # no pack: preamble only
#   [--role mdl] [--stage 5]                                   # the pack's role and stage
#
# Writes work/pack-<arm>.txt (work/ ignores itself). An M/T pack is the role stub
# agents/<role>-agent.md plus every baseline file routing_baseline_pack (bin/lib/skill-routing.sh)
# lists for <stage> and <role> at <ref>, with bin/runbook-slice.sh expanded to its output, so the
# file list is the counted one. The ref is checked out in a temporary detached worktree, never in
# the caller's tree. Every pack ends with a PACK-END line; an agent that quotes it back read to
# the end (score.sh --reply). Prints arm, ref, routed words/files, and pack words.
set -eu
AB="$(cd "$(dirname "$0")" && pwd)"; REPO="$(cd "$AB/../.." && pwd)"
usage() { sed -n '4,8p' "$0" >&2; exit 2; }
ARM="${1:-}"; [ $# -gt 0 ] && shift
case "$ARM" in M|T) REF="${1:-}"; [ -n "$REF" ] || usage; shift ;; N) REF="" ;; *) usage ;; esac
ROLE=mdl; STAGE=5; DROP=""
while [ $# -gt 0 ]; do
  case "$1" in
    --without) DROP="${2:-}"; [ -n "$DROP" ] || usage ;;
    --role) ROLE="${2:-}" ;; --stage) STAGE="${2:-}" ;;
    *) usage ;;
  esac
  shift 2 || usage
done
mkdir -p "$AB/work"; [ -f "$AB/work/.gitignore" ] || printf '*\n' > "$AB/work/.gitignore"
OUT="$AB/work/pack-$ARM.txt"; BODY="$AB/work/.pack-$ARM.body"

if [ "$ARM" = N ]; then
  echo "You are an agent that writes Mendix models with mxcli, using MDL (Mendix Definition Language) scripts. You have general knowledge of Mendix and MDL. There are no project-specific rules or skills loaded for this session." > "$BODY"
  info="N	no pack (preamble only)"
else
  TMPD="$(mktemp -d "${TMPDIR:-/tmp}/behaviour-pack.XXXXXX")"; WT="$TMPD/wt"
  trap 'git -C "$REPO" worktree remove --force "$WT" >/dev/null 2>&1 || true; rm -rf "$TMPD"' EXIT
  git -C "$REPO" worktree add --detach --quiet "$WT" "$REF"
  line="$(cd "$WT" && bash -c '. bin/lib/skill-routing.sh; routing_baseline_pack "$1" "$PWD" "$2"' _ "$STAGE" "$ROLE")"
  IFS=$'\t' read -r words files paths _ <<< "$line"
  if [ -n "$DROP" ]; then
    case " $paths " in *" $DROP "*) : ;; *) echo "build-packs: '$DROP' is not in the $ROLE Stage $STAGE pack at $REF" >&2; exit 2 ;; esac
  fi
  sha="$(git -C "$WT" rev-parse --short HEAD)"
  {
    echo "##### CONTEXT PACK — $ROLE role, Stage $STAGE (toolkit @ $sha)"
    echo "##### This is everything you (the $ROLE agent) have preloaded. Toolkit root is referred to as <toolkit>/."
    echo
    echo "===== FILE: agents/$ROLE-agent.md (your role stub) ====="
    cat "$WT/agents/$ROLE-agent.md"
    for p in $paths; do
      [ "$p" = "$DROP" ] && continue
      echo
      if [ "$p" = "bin/runbook-slice.sh" ]; then
        echo "===== OUTPUT OF: bin/runbook-slice.sh $STAGE ====="
        (cd "$WT" && bash bin/runbook-slice.sh "$STAGE")
      else
        echo "===== FILE: $p ====="
        cat "$WT/$p"
      fi
    done
  } > "$BODY"
  info="$ARM	$REF@$sha	routing_baseline_pack=$words words/$files files"
  [ -z "$DROP" ] || info="$info, without $DROP: $((words - $(LC_ALL=C wc -w < "$WT/$DROP"))) words/$((files - 1)) files"
fi
{ cat "$BODY"; echo; echo "===== END OF CONTEXT PACK ====="
  printf 'PACK-END: %s-%s\n' "$ARM" "$(cksum < "$BODY" | cut -d' ' -f1)"; } > "$OUT"
rm -f "$BODY"
printf '%s\tpack=%s words, %s lines\n' "$info" "$(LC_ALL=C wc -w < "$OUT" | tr -d ' ')" "$(wc -l < "$OUT" | tr -d ' ')"
