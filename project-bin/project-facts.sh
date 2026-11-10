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
# Exit: 0 ok, 1 --out could not be written, 2 bad usage. PROJECT.md's ports section prints role
# names and port numbers only, never its text.
#
# NEVER PRINTS A VALUE THAT COULD BE A SECRET. Env files and the run record are read for key
# NAMES and port numbers only. Where the credential lives is named; the credential never is.
# Read-only. Regenerate per dispatch (it is fast); a copy goes stale the moment a port moves.
# Bash 3.2 compatible.
set -u
ROOT="${PROJECT_ROOT:-$(pwd)}"; OUT=""
if [ "${1:-}" = "--out" ]; then OUT="${2:-}"; [ -n "$OUT" ] || { echo "project-facts: --out needs a file" >&2; exit 2; }; fi
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
    pid=$(sed -n 's/.*"pid": *\([0-9][0-9]*\).*/\1/p' "$f" | head -1)
    nm=$(basename "${pr:-$f}")
    # The record outlives the process: trust it only while its pid is alive (as app-restart.sh does).
    if [ -z "$pid" ]; then
      echo "- $nm: record $f has no pid, running state unknown (app http://localhost:${ap:-?}, admin port ${ad:-?})"
    elif kill -0 "$pid" 2>/dev/null; then
      echo "- $nm: RUNNING app http://localhost:${ap:-?}  admin port ${ad:-?}  (pid $pid, record $f; admin credential is in that file, read it only if needed)"
    else
      echo "- $nm: not running (record $f is stale: pid $pid is gone). Start the app, then regenerate."
    fi
  done
  echo "- Several runtimes or roles on different ports: list them in PROJECT.md under a 'Roles and ports' heading; this script prints role names and ports from that section below if present."
  if [ -f PROJECT.md ]; then
    # Role names and port numbers ONLY. The section's text is never copied: role tables carry demo
    # credentials. Anything before the first port that looks secret-ish prints as [redacted].
    awk 'tolower($0) ~ /^#+ +(roles and ports|ports|environments)([^a-z0-9]|$)/{f=1;next} f&&/^#+ /{exit} f{print}' PROJECT.md | \
    while IFS= read -r ln; do
      ports=$(printf '%s\n' "$ln" | grep -oE '(^|[^0-9])[0-9]{4,5}([^0-9]|$)' | grep -oE '[0-9]{4,5}' | tr '\n' ' ')
      [ -n "$ports" ] || continue
      role=$(printf '%s\n' "$ln" | sed -E 's/[0-9]{4,5}.*$//; s/[^A-Za-z0-9_ .-]+/ /g; s/^[ -]+//; s/[ -]+$//' | cut -c1-40)
      if printf '%s\n' "$role" | grep -qiE 'pass|pwd|secret|token|key|cred'; then role="[redacted]"; fi
      echo "- role ${role:-?}: port $ports"
    done
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
  if [ -f docs/BUILD-LOG.md ]; then echo "- docs/BUILD-LOG.md : what was built and when"; fi
  return 0
}
if [ -n "$OUT" ]; then
  if mkdir -p "$(dirname "$OUT")" 2>/dev/null && emit > "$OUT" 2>/dev/null; then echo "wrote $OUT" >&2
  else echo "project-facts: ERROR could not write $OUT" >&2; exit 1; fi
else emit; fi
exit 0
