#!/usr/bin/env bash
# checkpoint.sh — snapshot durable project state so the session can be cleared safely.
#
# THE POINT: /clear is only safe when the state you'd lose is already on disk.
# This gathers the mechanical half of that (git, stage, build-plan position,
# gate status, dirty scripts) so the agent only has to write the narrative half.
#
# Run at work boundaries — a build-plan step done, a gate passed, a module
# finished — not on a timer. The context-watch hook nudges you if you forget.
#
# USAGE
#   checkpoint.sh                 # print the checkpoint block to stdout
#   checkpoint.sh --write         # also append to docs/progress/checkpoints.md
#                                 #   and stamp .claude/.last-checkpoint
#
# The agent fills the "Narrative" section before committing. Everything above
# it is generated and needs no editing.

set -uo pipefail

WRITE=0
TITLE=""
for a in "$@"; do
  case "$a" in
    --write) WRITE=1 ;;
    --*)     ;;
    *)       [ -z "$TITLE" ] && TITLE="$a" ;;
  esac
done

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || ROOT=$(pwd)
cd "$ROOT" || exit 1
NOW=$(date '+%Y-%m-%d %H:%M')

# A handle makes a past checkpoint referenceable: "resume 2026-07-31-cost-tooling".
# Without one, blocks are distinguishable only by timestamp, which nobody remembers.
if [ -n "$TITLE" ]; then
  SLUG=$(printf '%s' "$TITLE" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-' | cut -c1-40)
  HANDLE="$(date '+%Y-%m-%d')-$SLUG"
else
  HANDLE="$(date '+%Y-%m-%d-%H%M')"
fi

emit() {
printf '## Checkpoint — %s · `%s`\n\n' "$NOW" "$HANDLE"

# ---- git ---------------------------------------------------------------
printf '### Repo\n\n'
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "(not a git repo)")
printf -- '- Branch: `%s`\n' "$branch"
if git rev-parse --git-dir >/dev/null 2>&1; then
  dirty=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  staged=$(git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
  printf -- '- Working tree: %s changed file(s), %s staged\n' "$dirty" "$staged"
  printf -- '- Last commits:\n'
  git log --oneline -3 2>/dev/null | sed 's/^/    - /'
  changed=$(git status --porcelain 2>/dev/null | awk '{print $NF}' | head -12)
  if [ -n "$changed" ]; then
    printf -- '- Changed:\n'
    printf '%s\n' "$changed" | sed 's/^/    - `/;s/$/`/'
    [ "$dirty" -gt 12 ] && printf -- '    - …and %s more\n' "$(( dirty - 12 ))"
  fi
fi
printf '\n'

# ---- pipeline position -------------------------------------------------
printf '### Pipeline\n\n'
if [ -f PROJECT.md ]; then
  grep -iE '^ *(\*\*)?(stage|current stage|toolkit commit) *:' PROJECT.md 2>/dev/null \
    | head -4 | sed 's/^ *//;s/^/- /' || true
fi
plan=$(ls architecture/build-plan.md 2>/dev/null | head -1)
if [ -n "$plan" ]; then
  # grep -c prints 0 AND exits 1 on no-match; a `|| echo 0` fallback would
  # append a second zero. Capture bare, then default.
  done_n=$(grep -cE '^\s*[-*]+ *\[[xX]\]' "$plan" 2>/dev/null); done_n=${done_n:-0}
  open_n=$(grep -cE '^\s*[-*]+ *\[ *\]' "$plan" 2>/dev/null); open_n=${open_n:-0}
  if [ "$(( done_n + open_n ))" -gt 0 ]; then
    printf -- '- Build plan: %s done / %s open (`%s`)\n' "$done_n" "$open_n" "$plan"
    nextup=$(grep -E '^\s*[-*]+ *\[ *\]' "$plan" 2>/dev/null | head -3 | sed 's/^ *//')
    [ -n "$nextup" ] && { printf -- '- Next open items:\n'; printf '%s\n' "$nextup" | sed 's/^/    /'; }
  else
    # No checkbox tracking in this plan — fall back to its section headings so
    # the checkpoint still says where in the plan we are.
    secs=$(grep -E '^#{2,3} ' "$plan" 2>/dev/null | sed 's/^#* *//')
    n=$(printf '%s\n' "$secs" | grep -c . 2>/dev/null); n=${n:-0}
    printf -- '- Build plan: `%s` — %s sections, no checkbox tracking\n' "$plan" "$n"
    printf -- '- Sections:\n'
    printf '%s\n' "$secs" | head -8 | sed 's/^/    - /'
    [ "$n" -gt 8 ] && printf -- '    - …and %s more\n' "$(( n - 8 ))"
    printf -- '  > Which section is current? State it in the Narrative — nothing on disk records it.\n'
  fi
fi
printf '\n'

# ---- model / gate state ------------------------------------------------
printf '### Model & gates\n\n'
mpr=$(ls -1 *.mpr 2>/dev/null | head -1)
[ -n "$mpr" ] && printf -- '- MPR: `%s` (mtime %s)\n' "$mpr" "$(date -r "$mpr" '+%Y-%m-%d %H:%M' 2>/dev/null)"
mdl=$(git status --porcelain mdlsource 2>/dev/null | awk '{print $NF}' | head -8)
if [ -n "$mdl" ]; then
  printf -- '- Uncommitted MDL scripts (a committed script is NOT an executed script):\n'
  printf '%s\n' "$mdl" | sed 's/^/    - `/;s/$/`/'
fi
if [ -f .claude/.last-gate ]; then
  printf -- '- Last recorded gate: %s\n' "$(cat .claude/.last-gate 2>/dev/null | head -1)"
else
  printf -- '- Last recorded gate: (none recorded)\n'
fi
printf '\n'

# ---- narrative ---------------------------------------------------------
cat <<'TEMPLATE'
### Narrative — agent fills this in before clearing

**Done since last checkpoint:**
-

**In flight (exact next action, enough to resume cold):**
-

**Decisions made (and why) — promote anything durable to PROJECT.md:**
-

**Traps hit — promote anything reusable to __TOOLKIT_ROOT__/skills/:**
-

**Do NOT lose:**
-

TEMPLATE
}

out=$(emit)
printf '%s\n' "$out"

if [ "$WRITE" = "1" ]; then
  mkdir -p docs/progress .claude 2>/dev/null
  printf '%s\n\n---\n\n' "$out" >> docs/progress/checkpoints.md
  date +%s > .claude/.last-checkpoint
  printf '%s' "$HANDLE" > .claude/.last-handle
  echo "→ appended to docs/progress/checkpoints.md; stamped .claude/.last-checkpoint" >&2
  echo "→ handle: $HANDLE   (put this at the top of docs/progress/RESUME.md)" >&2
  [ -n "$TITLE" ] || echo "   tip: pass a title — checkpoint.sh --write 'cost tooling split'" >&2
fi
