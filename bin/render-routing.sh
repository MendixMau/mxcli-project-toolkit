#!/usr/bin/env bash
# Renders every skill-routing surface in this repo FROM bin/lib/skill-routing.tsv.
#
# Routing a skill used to take six coordinated edits and a seventh copy inside each project
# that no script could reach. Now there is one table and this renderer. A surface participates
# by carrying a marked block:
#
#     <!-- ROUTING:BEGIN readme-baseline -->
#     ...generated, do not hand-edit...
#     <!-- ROUTING:END -->
#
# (In shell files the same markers live inside a `#` comment, so the file still parses.)
#
# Usage:
#   bin/render-routing.sh              rewrite every surface in place (idempotent)
#   bin/render-routing.sh --only F...  rewrite ONLY these surfaces — for when another session has
#                                      the others open. Narrows the WRITE, never the audit.
#   bin/render-routing.sh --check      write nothing; exit 2 if ANY surface has drifted
#   bin/render-routing.sh --list       list the surfaces and the views each carries
#
# Exit codes:  0 in sync / rendered · 1 usage or structural error (missing markers, bad view)
#              2 drift detected under --check
#
# `--check` is wired into bin/gate-check.sh, so a hand-edited surface is caught rather than
# remembered.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/lib/skill-routing.sh"

# The surfaces. Anything listed here MUST carry at least one ROUTING:BEGIN marker; a surface
# that has lost its markers is a structural error (exit 1), not silence — that silent-drop is
# precisely how the old six-copy arrangement lost track of a table.
SURFACES="
ROUTING.md
README.md
skills/conversion-runbook.md
agents/ba-agent.md
agents/architect-agent.md
agents/mdl-agent.md
agents/gate-agent.md
agents/test-agent.md
agents/review-agent.md
bin/gate-check.sh
"

MODE="render"
ONLY=""
case "${1:-}" in
  --check) MODE="check" ;;
  --list)  MODE="list" ;;
  # --only exists because this repo is worked by more than one session at a time. Without it the
  # renderer is all-or-nothing: closing drift on ONE surface means rewriting all nine, and if a
  # concurrent session has any of the other eight open and dirty, you either clobber their work or
  # you leave the table unrendered indefinitely. Measured 2026-08-18: six of nine surfaces were
  # dirty in another session and Wave 1 had been blocked on exactly this for days.
  #
  # It is deliberately NOT a way to keep a surface permanently out of sync — `--check` still audits
  # every surface, and gate-check.sh still calls the unfiltered `--check`. This narrows the WRITE,
  # never the audit.
  --only)
    shift
    [ "$#" -gt 0 ] || { echo "--only needs at least one surface path (see --list)" >&2; exit 1; }
    # SURFACES is newline-separated, so a `case " $SURFACES " in *" $f "*)` membership test never
    # matches — the separators are newlines, not spaces, and every path is silently rejected.
    # Word-split it instead. (Caught by the control below, which is why the control exists.)
    for f in "$@"; do
      _hit=0
      for s in $SURFACES; do [ "$s" = "$f" ] && _hit=1 && break; done
      [ "$_hit" -eq 1 ] || { echo "not a routing surface: $f (see --list)" >&2; exit 1; }
      ONLY="$ONLY $f"
    done
    ;;
  -h|--help) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  "") ;;
  *) echo "unknown option: $1" >&2; exit 1 ;;
esac
[ -n "$ONLY" ] && SURFACES="$ONLY"

# The group column decides render ORDER and the sub-headings. An unknown value would silently
# render as its own extra group with one row under it — invisible until someone notices a skill
# nobody loads. Validate before writing anything, on every mode including --check.
routing_validate_groups || exit 1

# Rewrite $1 into $2, replacing each marked block with freshly rendered content.
# Everything outside the markers is copied byte-for-byte.
render_file() {
  local src="$1" dst="$2" line view in_block=0 found=0
  : > "$dst"
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$in_block" -eq 1 ]; then
      case "$line" in
        *ROUTING:END*) in_block=0; printf '%s\n' "$line" >> "$dst" ;;
        *) : ;;   # old generated content — dropped, about to be re-emitted
      esac
      continue
    fi
    printf '%s\n' "$line" >> "$dst"
    case "$line" in
      *ROUTING:BEGIN*)
        view="$(printf '%s\n' "$line" | sed -n 's/.*ROUTING:BEGIN[[:space:]]\{1,\}\([A-Za-z0-9:_-]\{1,\}\).*/\1/p')"
        if [ -z "$view" ]; then
          echo "ERROR: $src: ROUTING:BEGIN with no view name: $line" >&2
          return 1
        fi
        in_block=1; found=$((found + 1))
        routing_render "$view" >> "$dst" || return 1
        ;;
    esac
  done < "$src"
  if [ "$in_block" -eq 1 ]; then
    echo "ERROR: $src: ROUTING:BEGIN without a matching ROUTING:END" >&2
    return 1
  fi
  # No markers at all: the surface exists but the table cannot reach it. Distinguished from a
  # broken block (return 1) because it is the normal state of a surface that has not been
  # wired YET, and the caller reports it rather than aborting the whole render.
  [ "$found" -eq 0 ] && return 3
  return 0
}

if [ "$MODE" = "list" ]; then
  for f in $SURFACES; do
    [ -f "$ROOT/$f" ] || { printf '%-34s MISSING\n' "$f"; continue; }
    printf '%-34s %s\n' "$f" \
      "$(grep -o 'ROUTING:BEGIN[[:space:]]\{1,\}[A-Za-z0-9:_-]\{1,\}' "$ROOT/$f" | sed 's/.*BEGIN[[:space:]]*//' | tr '\n' ' ')"
  done
  echo
  echo "table: $MXTK_ROUTING_TSV ($(routing_rows | wc -l | tr -d ' ') rows)"
  exit 0
fi

DRIFTED=""
MISSING=""
UNWIRED=""
RENDERED=0
for f in $SURFACES; do
  if [ ! -f "$ROOT/$f" ]; then MISSING="$MISSING $f"; continue; fi
  TMP="$(mktemp "${TMPDIR:-/tmp}/routing.XXXXXX")"
  rc=0; render_file "$ROOT/$f" "$TMP" || rc=$?
  if [ "$rc" -eq 3 ]; then
    rm -f "$TMP"
    UNWIRED="$UNWIRED $f"
    echo "UNWIRED: $f carries no ROUTING:BEGIN block — the table cannot reach it."
    continue
  elif [ "$rc" -ne 0 ]; then
    rm -f "$TMP"; exit 1
  fi
  if cmp -s "$ROOT/$f" "$TMP"; then
    rm -f "$TMP"
    continue
  fi
  if [ "$MODE" = "check" ]; then
    DRIFTED="$DRIFTED $f"
    echo "DRIFT: $f"
    diff -u --label "a/$f (on disk)" "$ROOT/$f" --label "b/$f (from the table)" "$TMP" | sed 's/^/    /' || true
  else
    cat "$TMP" > "$ROOT/$f"
    echo "Rendered: $f"
    RENDERED=$((RENDERED + 1))
  fi
  rm -f "$TMP"
done

if [ -n "$MISSING" ]; then
  echo "ERROR: routing surface(s) not found:$MISSING" >&2
  exit 1
fi

# A row whose file does not exist yet is a warning, not a failure — the row is what makes a
# newly promoted skill reachable, and it may legitimately land first.
GHOSTS="$(routing_missing_paths "$ROOT" | tr '\n' ' ')"
[ -n "${GHOSTS// /}" ] && echo "NOTE: routed but not on disk yet:$( echo " $GHOSTS" | sed 's/ *$//')"

# Coverage audit: every skills/**/*.md is routed or exempted (bin/lib/routing-exempt.tsv).
# Fails --check — an unrouted skill is unreachable by anything that scans the tables, and the
# first run of this audit found 6 such files, two with zero inbound references anywhere.
# In render mode it warns but still renders: rendering the surfaces you CAN reach is the
# remedy path, and a guard must never block the action that resolves it.
ORPHANS="$(routing_unrouted_skills "$ROOT")"
if [ -n "$ORPHANS" ]; then
  echo "UNROUTED: skill(s) on disk with no routing row and no exemption:"
  printf '%s\n' "$ORPHANS" | sed 's/^/    /'
  echo "    → add a row to bin/lib/skill-routing.tsv (then re-render), or an exemption with a reason to bin/lib/routing-exempt.tsv"
fi
# Tier audit: a row whose `tier` is not one this renderer knows is routed NOWHERE, silently.
# The coverage audit above cannot see it — the skill HAS a row, so it is not an orphan — and
# every surface renders "in sync" because none of them was ever asked to include it. That is
# the "a skill can be perfect and unreachable" failure this repo's own authoring rule 8 names,
# reached by a single typo in one column.
#
# Found 2026-09-01, contributing a skill from a dashboard-publishing migration: the row said
# `situational` where the renderer reads `ondemand`. `--check` printed "all skills routed or
# exempted" over a skill that appeared in zero tables. One word of validation retires it.
BAD_TIER="$(awk -F'\t' '
  /^#/ || NF < 6 { next }
  $6 != "baseline" && $6 != "ondemand" && $6 != "experimental" { printf "%s (tier: %s)\n", $1, $6 }
' "$MXTK_ROUTING_TSV")"
if [ -n "$BAD_TIER" ]; then
  echo "UNKNOWN TIER: routing row(s) whose tier no surface renders — the skill is routed nowhere:"
  printf '%s\n' "$BAD_TIER" | sed 's/^/    /'
  echo "    → tier must be one of: baseline | ondemand | experimental"
fi

# Baseline budget: the baseline tier is read by EVERY session of EVERY project before it
# writes anything, so its size is a cost paid thousands of times. Measured 2026-09-04: 29 rows,
# 118,783 words, a third of it the bug ledger — against ROUTING.md's own "keep baseline short".
# Nothing enforced it. This does: the sum of `wc -w` over baseline paths must stay under
# MXTK_BASELINE_BUDGET_WORDS. The budget is a RATCHET — set just above the current total and
# lowered as rows move to on-demand or shrink — never raised to admit growth. To add a
# baseline row, take words out elsewhere. Scripts count too: an agent told to read a script
# reads it.
BASELINE_BUDGET="${MXTK_BASELINE_BUDGET_WORDS:-90000}"
BASELINE_WORDS="$(awk -F'\t' '/^#/ || NF < 6 { next } $6 == "baseline" { print $2 }' "$MXTK_ROUTING_TSV" \
  | while IFS= read -r f; do [ -f "$ROOT/$f" ] && wc -w < "$ROOT/$f"; done | awk '{ s += $1 } END { print s + 0 }')"
OVER_BUDGET=""
if [ "$BASELINE_WORDS" -gt "$BASELINE_BUDGET" ]; then
  OVER_BUDGET="$BASELINE_WORDS words in the baseline tier, budget $BASELINE_BUDGET"
  echo "BASELINE OVER BUDGET: $OVER_BUDGET"
  echo "    → move a row to ondemand, shorten a baseline file, or point the row at a lookup script (bin/bug-lookup.sh is the pattern)"
  awk -F'\t' '/^#/ || NF < 6 { next } $6 == "baseline" { print $2 }' "$MXTK_ROUTING_TSV" \
    | while IFS= read -r f; do [ -f "$ROOT/$f" ] && printf '%8d  %s\n' "$(wc -w < "$ROOT/$f")" "$f"; done | sort -rn | head -5 | sed 's/^/    /'
fi

STALE_EXEMPT="$(routing_stale_exemptions "$ROOT")"
if [ -n "$STALE_EXEMPT" ]; then
  echo "STALE EXEMPTION(s) in bin/lib/routing-exempt.tsv (a dead exemption can silently swallow a future orphan):"
  printf '%s\n' "$STALE_EXEMPT" | sed 's/^/    /'
fi

if [ "$MODE" = "check" ]; then
  if [ -n "$DRIFTED" ] || [ -n "$UNWIRED" ] || [ -n "$ORPHANS" ] || [ -n "$STALE_EXEMPT" ] || [ -n "$BAD_TIER" ] || [ -n "$OVER_BUDGET" ]; then
    echo ""
    [ -n "$DRIFTED" ] && echo "drifted:$DRIFTED — hand-edited inside the markers, or the table moved."
    [ -n "$UNWIRED" ] && echo "unwired:$UNWIRED — add a <!-- ROUTING:BEGIN <view> --> block."
    [ -n "$ORPHANS" ] && echo "unrouted skill(s) — see UNROUTED above."
    [ -n "$STALE_EXEMPT" ] && echo "stale exemption(s) — see above."
    [ -n "$BAD_TIER" ] && echo "unknown tier(s) — see UNKNOWN TIER above; the skill renders into no surface at all."
    [ -n "$OVER_BUDGET" ] && echo "baseline over budget — $OVER_BUDGET; see BASELINE OVER BUDGET above."
    echo "Fix the TABLE, then run: $0    (never hand-edit inside the markers)"
    exit 2
  fi
  echo "Routing surfaces in sync with the table; all skills routed or exempted. Baseline: $BASELINE_WORDS words (budget $BASELINE_BUDGET)."
  exit 0
fi

if [ "$RENDERED" -eq 0 ]; then
  echo "All routing surfaces already in sync — nothing written."
fi
exit 0
