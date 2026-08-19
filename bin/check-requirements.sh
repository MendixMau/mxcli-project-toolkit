#!/usr/bin/env bash
# check-requirements.sh — can this project run the verification loop?
#
# Answers one question per requirement and, with --fix, installs the ones that can be
# installed. Run it before the loop; verify-module.sh's rung 0 only checks the stack.
#
# WHY MOST THINGS DO NOT NEED INSTALLING
# Skills are read in place from $MXTK_ROOT and never copied. Shell helpers resolve through
# _common.sh tier 3 (walk up from $PWD for the .mpr) plus verify-module.sh's _tool search
# (project bin -> script dir -> toolkit), so the shared copy works from inside any wired
# project. That leaves exactly one thing that must physically exist in the repo: the
# tests/e2e engine, because node resolves require() paths relative to the file.
#
# So this script mostly REPORTS WHERE EACH REQUIREMENT RESOLVES FROM rather than copying.
# A requirement satisfied by pointing is not a lesser pass — it is the better one, because
# there is then only one copy to keep correct. Silent divergence between a project's stale
# copy and the toolkit's current one is the failure this avoids.
#
# Exit: 0 all present · 1 something missing (fixable) · 2 cannot even tell (no project)
set -uo pipefail

FIX=0
for a in "$@"; do case "$a" in
  --fix) FIX=1 ;;
  -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
esac; done

# --- where are we, and where is the toolkit? ------------------------------------------
ROOT=""
d=$(pwd)
while [ "$d" != "/" ]; do
  if ls "$d"/*.mpr >/dev/null 2>&1; then ROOT="$d"; break; fi
  d=$(dirname "$d")
done
if [ -z "$ROOT" ]; then
  echo "✗ no .mpr found walking up from $(pwd) — not inside a Mendix project" >&2
  exit 2
fi

if [ -z "${MXTK_ROOT:-}" ] && [ -f "$ROOT/CLAUDE.local.md" ]; then
  MXTK_ROOT=$(sed -n 's/^|[[:space:]]*Toolkit root[[:space:]]*|[[:space:]]*`\([^`]*\)`.*/\1/p' \
              "$ROOT/CLAUDE.local.md" | head -1)
fi
[ -z "${MXTK_ROOT:-}" ] && MXTK_ROOT=$(cd "$(dirname "$0")/.." && pwd)

miss=0; fixed=0
ok()   { printf "  \033[32m✓\033[0m %-26s %s\n" "$1" "$2"; }
gone() { printf "  \033[31m✗\033[0m %-26s %s\n" "$1" "$2"; miss=$((miss+1)); }
note() { printf "    %s\n" "$1"; }

echo "── requirements: $(basename "$ROOT") ──"
ok "project root" "$ROOT"
if [ -d "$MXTK_ROOT/skills" ]; then
  ok "toolkit" "$MXTK_ROOT ($(ls "$MXTK_ROOT"/skills/*.md 2>/dev/null | wc -l | tr -d ' ') skills, read in place)"
else
  gone "toolkit" "not found at $MXTK_ROOT — set MXTK_ROOT or fix CLAUDE.local.md's Wiring block"
  echo; echo "Cannot check anything else without the toolkit."; exit 1
fi

# --- shell helpers: resolved, not necessarily installed --------------------------------
. "$MXTK_ROOT/bin/lib/install-manifest.sh" 2>/dev/null || true
local_n=0; point_n=0; missing_scripts=""
for f in ${MXTK_PROJECT_BIN:-}; do
  if [ -x "$ROOT/bin/$f" ]; then local_n=$((local_n+1))
  elif [ -x "$MXTK_ROOT/project-bin/$f" ]; then point_n=$((point_n+1))
  else missing_scripts="$missing_scripts $f"; fi
done
if [ -n "$missing_scripts" ]; then
  gone "shell helpers" "missing:$missing_scripts"
else
  ok "shell helpers" "$local_n local, $point_n via toolkit — all resolvable"
fi

# --- the engine: the one thing that must be in the repo --------------------------------
E="$ROOT/tests/e2e"; eng_missing=""
for f in ${MXTK_PROJECT_TESTS:-}; do
  [ -f "$E/$f" ] || eng_missing="$eng_missing $f"
done
if [ -n "$eng_missing" ]; then
  if [ "$FIX" -eq 1 ]; then
    "$MXTK_ROOT/bin/install-tests.sh" "$ROOT" >/dev/null 2>&1 \
      && { ok "e2e engine" "INSTALLED into tests/e2e/"; fixed=$((fixed+1)); } \
      || gone "e2e engine" "install-tests.sh failed"
  else
    gone "e2e engine" "missing:$eng_missing"
    note "fix: $0 --fix   (or $MXTK_ROOT/bin/install-tests.sh $ROOT)"
  fi
else
  ok "e2e engine" "$(echo ${MXTK_PROJECT_TESTS:-} | wc -w | tr -d ' ') files in tests/e2e/"
fi

# project.config.js is the project's own and is never overwritten — absence is a real gap
if [ -f "$E/project.config.js" ]; then
  ok "project.config.js" "present"
else
  gone "project.config.js" "absent — the engine cannot know which project this is"
  note "fix: $MXTK_ROOT/bin/install-tests.sh $ROOT   (installs it from the template)"
fi

# --- runtime deps -----------------------------------------------------------------------
command -v node >/dev/null 2>&1 && ok "node" "$(node --version)" || gone "node" "not on PATH"
if node -e "require('playwright')" >/dev/null 2>&1 || [ -d "$ROOT/node_modules/playwright" ]; then
  ok "playwright" "resolvable"
else
  gone "playwright" "not installed — every browser rung will fault (rc 2)"
  note "fix: (cd $ROOT && npm i -D playwright && npx playwright install chromium)"
fi
command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 \
  && ok "docker" "responding" || gone "docker" "not responding — no app, no DB, no Jaeger"

# --- the work itself ---------------------------------------------------------------------
jn=$(ls "$ROOT"/journeys/*.journey.json 2>/dev/null | wc -l | tr -d ' ')
[ "$jn" -gt 0 ] && ok "journeys" "$jn defined" \
  || gone "journeys" "none in journeys/ — nothing for the runtime rungs to walk"

echo
if [ "$miss" -eq 0 ]; then
  echo "READY — $fixed fixed. Run: $MXTK_ROOT/project-bin/verify-module.sh <Module>"
  exit 0
fi
echo "NOT READY — $miss requirement(s) missing${FIX:+ after --fix}."
echo "Missing requirements are ABSENT, not degraded: an instrument that cannot run"
echo "reports fault, and a report full of faults is not a report about your app."
exit 1
