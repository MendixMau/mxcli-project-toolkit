#!/usr/bin/env bash
# task-rules.sh — the rules a helper needs for ONE build step, by the step's kind, inlined.
#
# EXPERIMENT (task-routed rules, process/task-routed-rules-proposal-2026-10-23.md). Today the
# mdl role reads every Stage 5 rule file as baseline, whatever the step builds: a microflow step
# carries ~20k words of page rules, a page step ~5k of microflow rules. This library prints the
# rules for the step's kind(s) only, so the context pack (project-bin/context-pack.sh) can be the
# way kind-specific rules reach a helper, and those rows can go on demand for mdl ("mdl?").
#
#   . bin/lib/task-rules.sh
#   task_rules_pack <toolkit-root> "<kinds>" [<text-file>...]
#
# <kinds>: space-separated subset of page|logic|domain (context-pack.sh's step classification).
#   Empty or unknown → every kind (fail open: an unclassified step gets today's full set).
# <text-file>s: what the step is about (the pack's Builds/Reads/DESCRIBE text, or a drafted
#   script); bin/rule-lookup.sh matches trigger-only rules against them (part B).
#
# Prints Markdown:
#   1. learned-mdl-preflight.md with its STOP table filtered to the kinds (bin/lib/stop-row-kinds.tsv;
#      rows marked `retired` left out; a row missing from the map is kept)
#   2. each kind file from bin/lib/task-kinds.tsv — a skill in full, a script as its header
#      comment only (the usage contract; the code is not something a drafting helper applies)
#   3. trigger-only rules whose trigger matches the text files (bin/rule-lookup.sh)
#
# PRODUCER FOR EVERY CONSUMER. Called by project-bin/context-pack.sh (per dispatch) and
# tests/behaviour/build-packs.sh --kind (the A/B). Bash 3.2: no mapfile, no associative arrays.

# kinds normalised: unknown/empty → all three
_task_kinds() {
  local out="" k
  for k in $1; do
    case "$k" in page|logic|domain) case " $out " in *" $k "*) ;; *) out="$out $k" ;; esac ;; esac
  done
  [ -n "$out" ] || out=" page logic domain"
  printf '%s' "${out# }"
}

# learned-mdl-preflight.md, STOP rows outside <kinds> dropped
task_rules_preflight() {
  local root="$1" kinds="$2"
  awk -F'\t' -v kinds=" $kinds " '
    FNR == NR { if ($0 !~ /^#/ && NF >= 2) kind[$1] = $2; next }
    /^\| *[0-9]+[a-z]?( *🔎)? *\|/ {
      id = $0; sub(/^\| */, "", id); sub(/[ |].*/, "", id)
      if (id in kind) {
        k = kind[id]
        if (k == "retired") { dropped++; next }
        if (k != "any" && index(kinds, " " k " ") == 0) { dropped++; next }
      }
    }
    { print }
    END { if (dropped) printf "\n_%d STOP rows for other step kinds or retired are left out of this pack (full table: skills/learned-mdl-preflight.md)._\n", dropped }
  ' "$root/bin/lib/stop-row-kinds.tsv" FS='\n' "$root/skills/learned-mdl-preflight.md"
}

# a script's leading comment block (after the shebang), comment markers kept
_task_script_header() {
  awk 'NR == 1 && /^#!/ { next }
       /^(#|\/\/)/ { print; seen = 1; next }
       /^\/\*/ { inblk = 1 }
       inblk { print; if (/\*\//) inblk = 0; seen = 1; next }
       seen { exit }' "$1"
}

task_rules_pack() {
  local root="$1" kinds; kinds="$(_task_kinds "$2")"; shift 2
  local k p
  printf '## Rules for this step (inlined for: %s)\n\n' "$kinds"
  printf '### skills/learned-mdl-preflight.md (STOP table filtered to this step)\n\n'
  task_rules_preflight "$root" "$kinds"
  for k in $kinds; do
    grep -v '^#' "$root/bin/lib/task-kinds.tsv" | awk -F'\t' -v k="$k" '$1 == k { print $2 }' |
    while IFS= read -r p; do
      [ -f "$root/$p" ] || { printf '\n_(%s missing at this toolkit ref)_\n' "$p"; continue; }
      case "$p" in
        *.sh|*.js|*.py) printf '\n### %s (header: how to use it)\n\n```\n' "$p"; _task_script_header "$root/$p"; printf '```\n' ;;
        *) printf '\n### %s\n\n' "$p"; cat "$root/$p" ;;
      esac
    done
  done
  if [ $# -gt 0 ] && [ -x "$root/bin/rule-lookup.sh" ]; then
    local hits; hits="$("$root/bin/rule-lookup.sh" --root "$root" "$@" 2>/dev/null || true)"
    if [ -n "$hits" ]; then printf '\n### Triggered rules (bin/rule-lookup.sh matched this step)\n\n%s\n' "$hits"; fi
  fi
  return 0   # callers run under set -e (tests/behaviour/build-packs.sh); "no hits" is not a failure
}
