#!/usr/bin/env bash
# Reader for bin/lib/skill-routing.tsv — the one skill-routing table.
#
# Every routing surface in this repo is a VIEW of that table, rendered by this library:
#   ROUTING.md                     full           (human-readable index)
#   README.md                      readme-baseline + readme-situational
#   skills/conversion-runbook.md   readme-baseline
#   agents/<x>-agent.md            agent:<x>
#   bin/gate-check.sh              stage-map      (shell case arms)
#   <project>/CLAUDE.local.md      baseline       (written by init-project.sh / sync-project.sh)
#
# Source it; do not execute it. Callers: bin/render-routing.sh, bin/init-project.sh,
# bin/sync-project.sh.
#
# bash 3.2 (stock macOS) — no associative arrays, no mapfile, no `local -n`.

# shellcheck disable=SC2034
MXTK_ROUTING_LIB_LOADED=1

_routing_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MXTK_ROUTING_TSV="${MXTK_ROUTING_TSV:-$_routing_lib_dir/skill-routing.tsv}"

# Escape the markdown table separator. Several "when" strings legitimately contain "|"
# (e.g. "CLI vs MCP+MDL"); unescaped, one of them silently splits a row into three cells.
_routing_md_escape() { printf '%s' "$1" | sed 's/|/\\|/g'; }

# Emit the data lines (comments and blanks stripped).
routing_rows() {
  [ -f "$MXTK_ROUTING_TSV" ] || { echo "skill-routing: table not found: $MXTK_ROUTING_TSV" >&2; return 1; }
  grep -v '^[[:space:]]*#' "$MXTK_ROUTING_TSV" | grep -v '^[[:space:]]*$'
}

# Does a comma list contain an exact item? ("5" must not match "15", "ba" must not match "bar".)
_routing_has() {
  case ",$1," in *",$2,"*) return 0 ;; esac
  return 1
}

# ── Groups ─────────────────────────────────────────────────────────────────────────────────
#
# Column 7. The order here is the RENDER order — it follows the arc of a project (what am I
# doing → read the source → what to build → how it is shaped → how it looks → build it → does
# it work → it is broken), NOT the alphabet. Alphabetical would put `verify` before `build`.
#
# Empty groups are listed on purpose and render as nothing. build/workflow, build/integration
# and build/security are declared and empty: that is the finding, not an oversight.
_routing_group_order() {
  printf '%s\n' spine source requirements architecture design \
                build build/mdl build/pages build/workflow build/integration build/security \
                verify diagnose reference
}

# One-line label per group, used as the sub-heading in rendered views.
_routing_group_label() {
  case "$1" in
    spine)             echo "Spine — what am I doing, who decides, how do I ask" ;;
    source)            echo "Source — reading a legacy system (migration entry mode)" ;;
    requirements)      echo "Requirements — what must be built" ;;
    architecture)      echo "Architecture — how it is shaped" ;;
    design)            echo "Design — how it looks, before any MDL" ;;
    build)             echo "Build — the loop itself" ;;
    build/mdl)         echo "Build · MDL — the language and tool reference" ;;
    build/pages)       echo "Build · Pages — page-building patterns" ;;
    build/workflow)    echo "Build · Workflow" ;;
    build/integration) echo "Build · Integration" ;;
    build/security)    echo "Build · Security" ;;
    verify)            echo "Verify — does it work" ;;
    diagnose)          echo "Diagnose — something is broken and it may be the tooling" ;;
    reference)         echo "Reference — lookup tables, not method" ;;
    *)                 echo "$1" ;;
  esac
}

# The group set is CLOSED. A typo ("verfiy") would otherwise render as a real extra group with
# one row in it and nobody would notice — the same silent-drift failure the whole table exists
# to end. Called by render-routing.sh before it writes anything.
# Exit 0 clean; 1 with the offending rows on stderr.
routing_validate_groups() {
  local bad
  bad="$(routing_rows | awk -F'\t' -v ok="$(_routing_group_order | tr '\n' ' ')" '
    { n = split(ok, a, " "); hit = 0
      for (i = 1; i <= n; i++) if (a[i] == $7) { hit = 1; break }
      if (NF < 7 || $7 == "") printf "  %s: no group (column 7 is required)\n", $1
      else if (!hit)          printf "  %s: unknown group %s\n", $1, $7
    }')"
  if [ -n "$bad" ]; then
    echo "skill-routing: invalid group column in $MXTK_ROUTING_TSV:" >&2
    printf '%s\n' "$bad" >&2
    echo "  valid: $(_routing_group_order | tr '\n' ' ')" >&2
    return 1
  fi
  return 0
}

# Emit rows of one tier and one group, already tab-separated. Empty output == render nothing.
# `tier` of "*" means every tier.
_routing_group_rows() {
  routing_rows | awk -F'\t' -v g="$1" -v t="$2" '$7 == g && (t == "*" || $6 == t)'
}

# The skills/ paths mapped to one stage, space-separated. Only skills/ paths: PROTOCOL_PATHS
# decides whether a toolkit change invalidates a project's protocol ack, and widening it to
# bin/ would make every script edit block every gate. Rows already covered by gate-check's
# PROTOCOL_ALWAYS (the runbook, query-the-model) are skipped as redundant.
_routing_stage_arm() {
  local st="$1" out=""
  out="$(routing_rows | awk -F'\t' -v st="$st" '
    $2 !~ /^skills\// { next }
    $2 == "skills/conversion-runbook.md" || $2 == "skills/query-the-model.md" { next }
    $6 == "experimental" { next }   # a trial skill must never be able to block a gate
    { n = split($5, a, ","); for (i = 1; i <= n; i++) if (a[i] == st) { printf "%s ", $2; break } }
  ')"
  printf '%s' "${out% }"
}

# routing_render <view> [prefix]
#   full               | When | Load this | Agents | Stage | Tier |
#   readme-baseline    | Always relevant for | Reference this |          (tier=baseline)
#   readme-situational | Task | Skill to load |                          (tier=ondemand)
#   readme-experimental| Under trial | Skill |                            (tier=experimental)
#   baseline <prefix>  same as readme-baseline, paths shown under <prefix>/ (for CLAUDE.local.md)
#   agent:<name>       | When | Load this |   rows for that agent, baseline first
#   stage-map          shell `case` arms for gate-check.sh's stage_protocol_paths()
routing_render() {
  local view="$1" prefix="${2:-}"
  case "$view" in
    full)
      # Grouped: one sub-heading and one table per non-empty group, in _routing_group_order.
      # A reader looking for "how do I build a page" scans 14 headings, not 74 rows.
      local g rows
      _routing_group_order | while IFS= read -r g; do
        rows="$(_routing_group_rows "$g" '*')"
        [ -n "$rows" ] || continue
        printf '\n#### %s\n\n' "$(_routing_group_label "$g")"
        echo "| Always relevant for | Load this | Agent(s) | Stage(s) | Tier |"
        echo "|---|---|---|---|---|"
        printf '%s\n' "$rows" | while IFS=$'\t' read -r name path when agents stages tier group; do
          printf '| %s | `%s` | %s | %s | %s |\n' \
            "$(_routing_md_escape "$when")" "$path" "$agents" "$stages" "$tier"
        done
      done
      ;;
    readme-baseline|baseline)
      if [ "$view" = "baseline" ]; then
        echo "| Always relevant for | Reference this (under \`${prefix%/}/\`) |"
      else
        echo "| Always relevant for | Reference this |"
      fi
      echo "|---|---|"
      routing_rows | while IFS=$'\t' read -r name path when agents stages tier group; do
        [ "$tier" = "baseline" ] || continue
        printf '| %s | `%s` |\n' "$(_routing_md_escape "$when")" "$path"
      done
      ;;
    readme-experimental)
      echo "| Under trial — NEVER cite in a gate | Skill |"
      echo "|---|---|"
      routing_rows | while IFS=$'\t' read -r name path when agents stages tier group; do
        [ "$tier" = "experimental" ] || continue
        printf '| %s | `%s` |\n' "$(_routing_md_escape "$when")" "$path"
      done
      ;;
    readme-situational)
      # Grouped — this is the view the grouping was added for. 50 ondemand rows in one flat
      # alphabetical-ish list is the surface an agent actually scans to decide what to load.
      local g rows
      _routing_group_order | while IFS= read -r g; do
        rows="$(_routing_group_rows "$g" ondemand)"
        [ -n "$rows" ] || continue
        printf '\n**%s**\n\n' "$(_routing_group_label "$g")"
        echo "| Task | Skill to load |"
        echo "|---|---|"
        printf '%s\n' "$rows" | while IFS=$'\t' read -r name path when agents stages tier group; do
          printf '| %s | `%s` |\n' "$(_routing_md_escape "$when")" "$path"
        done
      done
      ;;
    agent:*)
      local who="${view#agent:}"
      echo "| Load this | When |"
      echo "|---|---|"
      local t
      for t in baseline ondemand experimental; do
        routing_rows | while IFS=$'\t' read -r name path when agents stages tier group; do
          [ "$tier" = "$t" ] || continue
          if [ "$agents" != "all" ]; then _routing_has "$agents" "$who" || continue; fi
          printf '| `%s` | %s |\n' "$path" "$(_routing_md_escape "$when")"
        done
      done
      ;;
    stage-map)
      # gate-check.sh's protocol-freshness map. Only skills/ paths: PROTOCOL_PATHS decides
      # whether a toolkit change invalidates a project's protocol ack, and widening it to
      # bin/ would make every script edit block every gate. Rows already covered by
      # PROTOCOL_ALWAYS (the runbook, query-the-model) are skipped as redundant.
      local st arm
      for st in P 0 1 2 3 4 5 6 7; do
        # NOTE: the filtering lives in _routing_stage_arm, not inline here. A `case`
        # statement nested inside a `$( ... )` inside a `case` arm is mis-parsed by bash 3.2
        # ("syntax error near unexpected token newline"), which is the shell this has to run on.
        arm="$(_routing_stage_arm "$st")"
        if [ "$st" = "5" ]; then
          printf '    5|build-ready) echo "%s" ;;\n' "$arm"
        else
          printf '    %s)  echo "%s" ;;\n' "$st" "$arm"
        fi
      done
      printf '    *)  echo "" ;;\n'
      ;;
    *)
      echo "skill-routing: unknown view '$view'" >&2
      return 1
      ;;
  esac
}

# ── The project-side surface: <project>/CLAUDE.local.md ────────────────────────────────────
#
# This is the copy no script could reach. It lives inside each project, it is the ONLY routing
# a project's agents auto-load, and it is the reason `facts-lock.sh` reached 1 of 6 projects
# while `agent-roles.md` and `source-triage.md` reached 1 each: the toolkit could ship a new
# skill, but the seventh copy of the routing table sat in six repos that `git pull` never
# touched and no sync script dared rewrite.
#
# It is rewritten IN PLACE, between markers, and nothing outside the markers is read or
# altered — a project's CLAUDE.local.md carries hand-written wiring (real paths, local
# conventions, session rituals) that must survive byte-identically.
#
# routing_claude_local_block <toolkit-root-prefix>   — the block, markers included
routing_claude_local_block() {
  local prefix="$1"
  cat <<EOF
## Baseline routing (always-on)

GENERATED between the markers from \`$prefix/bin/lib/skill-routing.tsv\`. Refresh after a
toolkit pull with \`$prefix/bin/sync-project.sh <project-root>\`. Do not hand-edit inside the
markers — the edit is silently reverted on the next sync, and the drift is invisible until a
skill stops reaching anyone. Everything outside the markers in this file is yours and is never
touched.

<!-- ROUTING:BEGIN baseline -->
$(routing_render baseline "$prefix")
<!-- ROUTING:END -->
EOF
}

# routing_sync_claude_local <file> <toolkit-root-prefix> [dry_run]
# Exit codes:  0 already current (nothing written)
#             10 block rewritten in place
#             11 block appended (project predates the markers)
#             12 REFUSED — an unmarked hand-written "## Baseline routing" section is present
#              1 error
routing_sync_claude_local() {
  local file="$1" prefix="$2" dry="${3:-0}" tmp new
  [ -f "$file" ] || { echo "routing: no such file: $file" >&2; return 1; }

  if grep -q 'ROUTING:BEGIN[[:space:]]\{1,\}baseline' "$file"; then
    tmp="$(mktemp "${TMPDIR:-/tmp}/cl.XXXXXX")" || return 1
    new="$(mktemp "${TMPDIR:-/tmp}/clnew.XXXXXX")" || return 1
    routing_render baseline "$prefix" > "$new"
    # Replace only between the markers. Everything else is copied byte-for-byte.
    awk -v repl="$new" '
      /ROUTING:BEGIN[ \t]+baseline/ {
        print; insec = 1
        while ((getline l < repl) > 0) print l
        close(repl); next
      }
      insec && /ROUTING:END/ { insec = 0; print; next }
      insec { next }
      { print }' "$file" > "$tmp"
    rm -f "$new"
    if cmp -s "$file" "$tmp"; then rm -f "$tmp"; return 0; fi
    if [ "$dry" -eq 1 ]; then rm -f "$tmp"; return 10; fi
    cat "$tmp" > "$file"; rm -f "$tmp"
    return 10
  fi

  # No markers. A hand-written baseline table is real content — appending a second one would
  # leave two disagreeing tables in the file an agent reads first. Refuse and say so.
  if grep -q '^##.*[Bb]aseline routing' "$file"; then
    return 12
  fi

  [ "$dry" -eq 1 ] && return 11
  { printf '\n'; routing_claude_local_block "$prefix"; } >> "$file"
  return 11
}

# routing_adopt_claude_local <file> <prefix> — replace an UNMARKED "## Baseline routing"
# section (to the next "## " heading) with the generated block. Backs the file up first.
# Only ever called on an explicit --adopt-routing; never as part of a plain sync.
routing_adopt_claude_local() {
  local file="$1" prefix="$2" tmp blk bak
  blk="$(mktemp "${TMPDIR:-/tmp}/clblk.XXXXXX")" || return 1
  tmp="$(mktemp "${TMPDIR:-/tmp}/cladopt.XXXXXX")" || return 1
  routing_claude_local_block "$prefix" > "$blk"
  awk -v repl="$blk" '
    /^##.*[Bb]aseline routing/ && !done {
      insec = 1; done = 1
      while ((getline l < repl) > 0) print l
      close(repl); next
    }
    insec && /^## / { insec = 0 }
    insec { next }
    { print }' "$file" > "$tmp"
  rm -f "$blk"
  bak="$file.pre-routing-$(date +%Y%m%d%H%M%S)"
  cp "$file" "$bak"
  cat "$tmp" > "$file"; rm -f "$tmp"
  echo "$bak"
}

# Paths named in the table that do not exist on disk. A warning, never a failure: a row is
# allowed to land a moment before the file it routes to (that is the point of having one
# table — the row is what makes the new skill reachable at all).
routing_missing_paths() {
  local root="${1:-$(cd "$_routing_lib_dir/../.." && pwd)}"
  routing_rows | while IFS=$'\t' read -r name path when agents stages tier group; do
    [ -e "$root/$path" ] || echo "$path"
  done
}
