#!/usr/bin/env bash
# context-pack.sh — one file with everything a helper needs for ONE build step.
#
# WHAT THIS IS. A dispatched helper (mdl-agent) used to assemble its own context: read the
# brief, grep the BRD, DESCRIBE the entities one call at a time, hunt for an example, guess the
# folder. Every one of those reads is a round trip that re-sends the whole conversation, and
# the guesses are where folder drift and wrong association names came from. This script does
# the assembly once, mechanically, from three sources that each own one kind of fact:
#
#   the module brief's "Build steps" row   WHAT this step builds, reads, copies (the plan)
#   mxcli brain brief                       WHY — decisions and the slice's requirements
#   mxcli DESCRIBE, run now                 WHAT IS — the model as it stands, never a copy
#
# Nothing in the pack is written down twice: the brief names elements, the model describes
# them, the brain explains them. A pack is regenerated per dispatch and never committed.
#
# PRODUCER FOR EVERY CONSUMER. Reads the "### Build steps" table in
# architecture/modules/<Module>-brief.md, which architect-agent writes at Stage 4 per
# skills/module-brief.md (Ready-check: "Build steps covers every document to be built"). Reads
# docs/brain/ if `mxcli brain init` has run (iterative-build-loop.md, build start); without it
# the pack says so and carries on — the brain section is the only optional one.
#
# Read-only. Runs `mxcli -c "DESCRIBE ..."` and `mxcli brain brief`, never exec.
#
# Usage:
#   bin/context-pack.sh <Module> <step>                 # pack to stdout, size line to stderr
#   bin/context-pack.sh <Module> <step> --out FILE
#   bin/context-pack.sh <Module> <step> --brief PATH    # brief somewhere else
#
# Exit: 0 pack complete · 1 pack written, but an element it names is not in the model
#       (listed under "Not found" — a typo in the brief, or a Reads element not built yet)
#       · 2 instrument fault (no brief, no row for <step>, no mxcli, no .mpr)
#
# Bash 3.2 compatible: no mapfile, no associative arrays.

. "$(dirname "$0")/_common.sh"

MODULE="" STEP="" OUT="" BRIEF=""
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT="$2"; shift 2 ;;
    --brief) BRIEF="$2"; shift 2 ;;
    -h|--help) sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "context-pack: unknown flag $1" >&2; exit 2 ;;
    *) if [ -z "$MODULE" ]; then MODULE="$1"; elif [ -z "$STEP" ]; then STEP="$1"; else echo "context-pack: extra argument $1" >&2; exit 2; fi; shift ;;
  esac
done
[ -n "$MODULE" ] && [ -n "$STEP" ] || { echo "usage: context-pack.sh <Module> <step> [--out FILE] [--brief PATH]" >&2; exit 2; }

[ -n "$BRIEF" ] || BRIEF="$PROJECT_ROOT/architecture/modules/$MODULE-brief.md"
[ -f "$BRIEF" ] || { echo "context-pack: no brief at $BRIEF" >&2; exit 2; }
MPR="$(find_mpr)" || exit 2
MODEL_DIR="$(cd "$(dirname "$MPR")" && pwd)"
MPR_BASE="$(basename "$MPR")"

MXCLI="${MXCLI:-}"
if [ -z "$MXCLI" ]; then
  if [ -x "$MODEL_DIR/mxcli" ]; then MXCLI="$MODEL_DIR/mxcli"
  elif [ -x "$PROJECT_ROOT/mxcli" ]; then MXCLI="$PROJECT_ROOT/mxcli"
  elif command -v mxcli >/dev/null 2>&1; then MXCLI="mxcli"
  else echo "context-pack: mxcli not found (./mxcli or on PATH); set MXCLI=/path/to/mxcli" >&2; exit 2; fi
fi

# --- the brief: one table row, two sections -------------------------------------------------
# section <heading-prefix> — the body under a "### <heading-prefix>..." heading, up to the next
# heading. Prefix match, because briefs add a parenthetical after the name.
section() {
  awk -v h="### $1" 'index($0,h)==1 {on=1; next} on && /^##/ {exit} on {print}' "$BRIEF"
}
# cells of the Build steps row whose first cell is $STEP: "builds|reads|example|slice"
ROW="$(section "Build steps" | awk -F'|' -v s="$STEP" '
  function t(x) { gsub(/`/,"",x); gsub(/^[ \t]+|[ \t]+$/,"",x); return x }
  NF>=6 && t($2)==s { print t($3) "|" t($4) "|" t($5) "|" t($6); exit }')"
[ -n "$ROW" ] || { echo "context-pack: no row '$STEP' in the '### Build steps' table of $BRIEF" >&2; exit 2; }
BUILDS="$(printf '%s' "$ROW" | cut -d'|' -f1)"
READS="$(printf '%s' "$ROW" | cut -d'|' -f2)"
EXAMPLE="$(printf '%s' "$ROW" | cut -d'|' -f3)"
SLICE="$(printf '%s' "$ROW" | cut -d'|' -f4)"
case "$SLICE" in -|—|none) SLICE="" ;; esac

# a cell is a comma-separated list of qualified names; "—" or "-" means none
names() { printf '%s\n' "$1" | tr ',' '\n' | sed 's/^[ \t]*//; s/[ \t]*$//' | grep -vE '^(-|—|none)?$'; }

# folder for a document: its row in the "Document folder plan" table, by full or short name
folder_of() {
  section "Document folder plan" | awk -F'|' -v full="$1" '
    function t(x) { gsub(/`/,"",x); gsub(/^[ \t]+|[ \t]+$/,"",x); return x }
    BEGIN { short=full; sub(/^[^.]*\./,"",short) }
    NF>=4 { d=t($2); sub(/ *\(.*$/,"",d); if (d==full || d==short) { print t($3); exit } }'
}

# --- the model ------------------------------------------------------------------------------
MISSING=""
# describe <Qualified.Name> — try each document kind; mxcli says "not found" for the wrong one
describe() {
  local kind out
  for kind in ENTITY ASSOCIATION ENUMERATION MICROFLOW NANOFLOW PAGE SNIPPET CONSTANT "JAVA ACTION" WORKFLOW; do
    if out="$(cd "$MODEL_DIR" && "$MXCLI" -p "$MPR_BASE" -c "DESCRIBE $kind $1" 2>/dev/null)"; then
      printf '### %s (%s)\n```\n%s\n```\n\n' "$1" "$(printf '%s' "$kind" | tr 'A-Z' 'a-z')" "$out"
      return 0
    fi
  done
  return 1
}

pack() {
  local n f out
  printf '# Context pack — %s step %s\n\n' "$MODULE" "$STEP"
  printf 'Generated %s from `%s`. Regenerate, never edit: the model sections are live.\n\n' \
    "$(date '+%Y-%m-%d %H:%M')" "${BRIEF#$PROJECT_ROOT/}"

  printf '## This step builds\n\n| Document | Folder |\n|---|---|\n'
  names "$BUILDS" | while IFS= read -r n; do
    f="$(folder_of "$n")"
    printf '| %s | %s |\n' "$n" "${f:-NOT IN FOLDER PLAN — escalate, do not invent one}"
  done
  printf '\n'

  printf '## Why (mxcli brain brief)\n\n'
  if [ -d "$MODEL_DIR/docs/brain" ]; then
    if [ -n "$SLICE" ]; then
      (cd "$MODEL_DIR" && "$MXCLI" brain brief --slice "$SLICE" -p "$MPR_BASE" 2>/dev/null) || printf '_brain brief --slice %s failed_\n' "$SLICE"
    else
      (cd "$MODEL_DIR" && "$MXCLI" brain brief --module "$MODULE" -p "$MPR_BASE" 2>/dev/null) || printf '_brain brief --module %s failed_\n' "$MODULE"
    fi
  else
    printf '_No docs/brain/ yet — `mxcli brain init` at build start (iterative-build-loop.md)._\n'
  fi
  printf '\n'

  n="$(section "Arch constraints")"
  [ -n "$n" ] && printf '## Arch constraints (module brief)\n%s\n\n' "$n"

  printf '## Model now — what this step reads (live DESCRIBE)\n\n'
  for n in $(names "$READS"); do describe "$n" || MISSING="$MISSING $n"; done

  if [ -n "$(names "$BUILDS")" ]; then
    for n in $(names "$BUILDS"); do
      out="$(describe "$n")" && printf '## Already in the model — you are changing this, not creating it\n\n%s\n' "$out"
    done
  fi

  if [ -n "$(names "$EXAMPLE")" ]; then
    printf '## Example to copy — the app'"'"'s own way of doing this\n\n'
    for n in $(names "$EXAMPLE"); do describe "$n" || MISSING="$MISSING $n"; done
  fi

  if [ -n "$MISSING" ]; then
    printf '## Not found in the model\n\n'
    for n in $MISSING; do printf -- '- %s — typo in the brief, or not built yet. Ask; do not guess its shape.\n' "$n"; done
    printf '\n'
  fi
  # the MISSING list is built in this function's shell; hand it to the caller via a file
  printf '%s' "$MISSING" > "$TMP_MISSING"
}

TMP_MISSING="$(mktemp "${TMPDIR:-/tmp}/ctxpack.XXXXXX")" || exit 2
trap 'rm -f "$TMP_MISSING"' EXIT
if [ -n "$OUT" ]; then
  mkdir -p "$(dirname "$OUT")" || exit 2
  pack > "$OUT" || exit 2
  echo "context-pack: $(wc -l < "$OUT" | tr -d ' ') lines, $(wc -c < "$OUT" | tr -d ' ') bytes -> $OUT" >&2
else
  pack
fi
[ -s "$TMP_MISSING" ] && { echo "context-pack: not found in the model:$(cat "$TMP_MISSING")" >&2; exit 1; }
exit 0
