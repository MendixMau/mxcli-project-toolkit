#!/usr/bin/env bash
# wire-company-brain.sh — point a project at a company brain with ONE short block.
#
#   bin/wire-company-brain.sh <project-root> <company-brain-dir>
#
# Writes (or rewrites in place, between markers) a "## Company brain" section in the project's
# CLAUDE.local.md. The block is a POINTER, ~50 words: it names the company brain's root and its
# ROUTING.md and says when to read it. The company's routing table itself is never copied into
# the project — it loads on demand, so the project's session-start budget is untouched. Also
# appends the project to the company brain's projects.tsv registry (once).
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
CL="$PROJECT/CLAUDE.local.md"
[ -f "$CL" ] || { echo "No CLAUDE.local.md in $PROJECT — run bin/init-project.sh first" >&2; exit 1; }

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
tmp="$(mktemp)"
if grep -q "$BEGIN" "$CL"; then
  grep -q "$END" "$CL" || { echo "CLAUDE.local.md has a BEGIN marker but no END — fix by hand" >&2; rm -f "$tmp"; exit 1; }
  awk -v b="$BEGIN" -v e="$END" -v blk="$block" '
    index($0,b)==1 { print blk; skip=1; next }
    index($0,e)==1 { skip=0; next }
    !skip { print }' "$CL" > "$tmp" && mv "$tmp" "$CL"
  echo "Updated: CLAUDE.local.md — company brain block rewritten in place."
else
  { cat "$CL"; printf '\n%s\n' "$block"; } > "$tmp" && mv "$tmp" "$CL"
  echo "Updated: CLAUDE.local.md — company brain block appended."
fi
rm -f "$tmp"

# Registry: one row per project, path is the key.
REG="$BRAIN/projects.tsv"
if [ -f "$REG" ] && ! grep -qF "$PROJECT	" "$REG"; then
  printf '%s\t%s\tactive\t%s\n' "$PROJECT" "$(basename "$PROJECT")" "$(date +%F)" >> "$REG"
  echo "Registered: $PROJECT in $REG"
fi
