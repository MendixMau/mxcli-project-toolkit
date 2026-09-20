#!/usr/bin/env bash
# wire-company-brain.sh — point a project at a company brain with ONE short block.
#
#   bin/wire-company-brain.sh <project-root> <company-brain-dir>
#
# Writes (or rewrites in place, between markers) a "## Company brain" section into EVERY
# instruction surface the project has: CLAUDE.md, CLAUDE.local.md, AGENTS.md, .cursorrules,
# .windsurfrules, .github/copilot-instructions.md. The block is a POINTER, ~50 words: it names
# the company brain's root and its ROUTING.md and says when to read it. The company's routing
# table itself is never copied into the project — it loads on demand, so the project's
# session-start budget is untouched. Also appends the project to projects.tsv (once).
#
# WHY EVERY SURFACE, not just CLAUDE.local.md (field run 2026-09-20, eval run 2): one of three
# wired sessions read AGENTS.md, CLAUDE.md, PROJECT.md and intake.md, never opened
# CLAUDE.local.md, and therefore never saw the company brain at all. It proposed stock Atlas and
# was perfectly reasonable about it — the brain was invisible, not ignored. A pointer in one
# file that a session may skip is a single point of failure; the toolkit's own rule is that a
# citation is not a read. Retrieval went 2/3 → 3/3 once the block reached CLAUDE.md too.
#
# Idempotent: markers present → rewrite between them; absent → append. Refuses a company-brain
# dir that lacks README.md and ROUTING.md (an unshaped folder is not a brain). Called by
# init-project.sh --company; safe to run by hand on any existing project.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="${1:?usage: wire-company-brain.sh <project-root> <company-brain-dir>}"
BRAIN="${2:?usage: wire-company-brain.sh <project-root> <company-brain-dir>}"
[ -d "$PROJECT" ] || { echo "No such project dir: $PROJECT" >&2; exit 1; }
[ -d "$BRAIN" ] || { echo "No such company-brain dir: $BRAIN" >&2; exit 1; }
PROJECT="$(cd "$PROJECT" && pwd)"; BRAIN="$(cd "$BRAIN" && pwd)"
for f in README.md ROUTING.md; do
  [ -f "$BRAIN/$f" ] || { echo "Not a company brain (missing $f): $BRAIN — run bin/init-company-brain.sh first" >&2; exit 1; }
done
# Every instruction surface that exists. CLAUDE.local.md must exist (it proves the project was
# scaffolded); the rest are written only where already present — this script never creates a
# tool's rules file that the project did not choose to have.
PRIMARY="$PROJECT/CLAUDE.local.md"
[ -f "$PRIMARY" ] || { echo "No CLAUDE.local.md in $PROJECT — run bin/init-project.sh first" >&2; exit 1; }
SURFACES="$PRIMARY"
for extra in "$PROJECT/CLAUDE.md" "$PROJECT/AGENTS.md" "$PROJECT/.cursorrules" \
             "$PROJECT/.windsurfrules" "$PROJECT/.github/copilot-instructions.md"; do
  [ -f "$extra" ] && SURFACES="$SURFACES
$extra"
done

BEGIN='<!-- COMPANY-BRAIN:BEGIN -->'; END='<!-- COMPANY-BRAIN:END -->'
block="$(cat <<BLK
$BEGIN
## Company brain

A company brain is wired at \`$BRAIN\` — this company's private tier: own skills, conventions,
lint rules, MDL snippets and approved components. **Before building any page, microflow or
integration, and before choosing a component, read \`$BRAIN/ROUTING.md\`** and follow the row
that fires. It loads on demand; nothing from it is copied here.
$END
BLK
)"
written=0
while IFS= read -r CL; do
  [ -n "$CL" ] || continue
  tmp="$(mktemp)"
  if grep -q "$BEGIN" "$CL"; then
    grep -q "$END" "$CL" || { echo "$(basename "$CL") has a BEGIN marker but no END — fix by hand" >&2; rm -f "$tmp"; continue; }
    awk -v b="$BEGIN" -v e="$END" -v blk="$block" '
      index($0,b)==1 { print blk; skip=1; next }
      index($0,e)==1 { skip=0; next }
      !skip { print }' "$CL" > "$tmp" && mv "$tmp" "$CL"
    echo "Updated: ${CL#$PROJECT/} — company brain block rewritten in place."
  else
    { cat "$CL"; printf '\n%s\n' "$block"; } > "$tmp" && mv "$tmp" "$CL"
    echo "Updated: ${CL#$PROJECT/} — company brain block appended."
  fi
  rm -f "$tmp"
  written=$((written+1))
done <<SURF
$SURFACES
SURF
echo "Company brain pointer written to $written instruction surface(s)."

# Registry: one row per project, path is the key.
REG="$BRAIN/projects.tsv"
if [ -f "$REG" ] && ! grep -qF "$PROJECT	" "$REG"; then
  printf '%s\t%s\tactive\t%s\n' "$PROJECT" "$(basename "$PROJECT")" "$(date +%F)" >> "$REG"
  echo "Registered: $PROJECT in $REG"
fi
