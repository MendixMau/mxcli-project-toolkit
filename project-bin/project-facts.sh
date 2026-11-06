#!/usr/bin/env bash
# project-facts.sh: print the facts every fresh helper otherwise re-discovers, from the repo.
#
#   bin/project-facts.sh [--out FILE]      # markdown to stdout, or to FILE (never committed)
#
# WHY (#701 item 4). A UX helper spent most of a 12 minute, 212k token run finding the app port,
# which port serves which role, the reset and restart scripts, the existing e2e helper libraries
# and the older screenshot folders. Each dispatched helper repeated that. This prints them once,
# mechanically, so the dispatch brief carries one line: "read <path> first".
#
# NEVER PRINTS A VALUE THAT COULD BE A SECRET. Env files and the run record are read for key
# NAMES and port numbers only. Where the credential lives is named; the credential never is.
# Read-only. Regenerate per dispatch (it is fast); a copy goes stale the moment a port moves.
# Bash 3.2 compatible.
set -u
ROOT="${PROJECT_ROOT:-$(pwd)}"; OUT=""
[ "${1:-}" = "--out" ] && OUT="${2:-}"
cd "$ROOT" || exit 2
emit() {
  echo "# Project facts (generated, read-only, do not commit)"
  echo "Generated $(date '+%Y-%m-%d %H:%M') from $(basename "$ROOT"). Values are never printed for env files or the run record."
  echo; echo "## Running app"
  rec=""; for f in .mxcli/run-local.json */.mxcli/run-local.json; do [ -f "$f" ] && rec="$rec $f"; done
  if [ -z "$rec" ]; then echo "- no run record found: the app is not running (start it, then regenerate)"; fi
  for f in $rec; do
    ap=$(sed -n 's/.*"appPort": *\([0-9]*\).*/\1/p' "$f" | head -1)
    ad=$(sed -n 's/.*"adminPort": *\([0-9]*\).*/\1/p' "$f" | head -1)
    pr=$(sed -n 's/.*"project": *"\([^"]*\)".*/\1/p' "$f" | head -1)
    echo "- $(basename "${pr:-$f}"): app http://localhost:${ap:-?}  admin port ${ad:-?}  (record $f; admin credential is in that file, read it only if needed)"
  done
  echo "- Several runtimes or roles on different ports: list them in PROJECT.md under a 'Roles and ports' heading; this script prints that section below if present."
  if [ -f PROJECT.md ]; then
    awk 'tolower($0) ~ /^#+ .*(roles and ports|ports|environments)/{f=1;print;next} f&&/^#+ /{exit} f{print}' PROJECT.md
  fi
  echo; echo "## Accounts and secrets (names only)"
  for f in .env .env.local CLAUDE.local.md tests/e2e/.env; do
    [ -f "$f" ] || continue
    k=$(grep -oE '^(export )?[A-Z][A-Z0-9_]*=' "$f" | sed 's/^export //; s/=$//' | tr '\n' ' ')
    [ -n "$k" ] && echo "- $f defines: $k"
  done
  g=$(grep -rhoE "process\.env\.[A-Z_]*(USER|PASS|PWD|TOKEN|ACCOUNT)[A-Z_]*" tests project-tests 2>/dev/null | sort -u | sed 's/process.env.//' | tr '\n' ' ')
  [ -n "$g" ] && echo "- e2e code reads: $g"
  echo; echo "## Scripts (first comment line)"
  for d in bin scripts tests/e2e; do
    [ -d "$d" ] || continue
    for f in "$d"/*reset* "$d"/*restart* "$d"/*cockpit* "$d"/*seed* "$d"/*demo*; do
      [ -f "$f" ] || continue
      echo "- $f: $(grep -m1 -E '^(#|//) *[A-Za-z]' "$f" | sed -E 's/^(#|\/\/) *//' | cut -c1-110)"
    done
  done
  echo; echo "## Existing e2e helper libraries (reuse, do not rewrite)"
  for f in tests/e2e/*lib*.js tests/e2e/helpers.js tests/e2e/config.js tests/e2e/project.config.js; do
    [ -f "$f" ] && echo "- $f: $(grep -m1 -E '^(//|#|\*) *[A-Za-z]' "$f" | sed -E 's/^(\/\/|#|\*) *//' | cut -c1-100)"
  done
  echo; echo "## Screenshot and artifact folders (most images first; run results folded)"
  find . -type f \( -name '*.png' -o -name '*.webp' \) -not -path './node_modules/*' -not -path './.git/*' \
    -not -path './.mxcli/*' -not -path './deployment/*' -not -path '*/results/*' 2>/dev/null | sed 's|/[^/]*$||' | sort | uniq -c | sort -rn | head -8 | \
    while read n d; do echo "- $d ($n images)"; done
  echo; echo "## Cockpit and demo runners"
  for d in $(find docs tests -maxdepth 3 -type d \( -iname '*cockpit*' -o -iname 'demo' \) 2>/dev/null | head -4); do
    echo "- $d (newest run: $(ls -1t "$d"/results 2>/dev/null | head -1))"
  done
  echo; echo "## Design tokens and wireframes"
  for f in $(find . -maxdepth 3 \( -iname 'design-tokens*' -o -iname 'tokens.css' -o -iname 'theme.scss' -o -name 'wireframes' \) -not -path './node_modules/*' 2>/dev/null | head -5); do echo "- $f"; done
  echo; echo "## Gates and state"
  [ -x bin/status.sh ] && echo "- bin/status.sh . --brief : where the project is and the next action"
  [ -f docs/BUILD-LOG.md ] && echo "- docs/BUILD-LOG.md : what was built and when"
}
if [ -n "$OUT" ]; then emit > "$OUT"; echo "wrote $OUT" >&2; else emit; fi
