#!/usr/bin/env bash
# check-root-clean.sh — fail if stray .md/.html appear in the project root.
#
# WHY THIS EXISTS. Working artifacts belong in docs/ analysis/ architecture/ design/ bug-logs/.
# The root is reserved for the handful of files tools open by exact path. Agents scatter files
# into the root by default — it is the working directory, so it is the path of least resistance —
# and once a report lands there nobody moves it. This is the backstop. Run it from the gate or a
# pre-commit hook.
#
# Usage:
#   bin/check-root-clean.sh              # check the project root
#   ROOT_ALLOWED="A.md B.md" bin/...     # override the allowlist wholesale
#   ROOT_ALLOWED_EXTRA="NOTES.md" bin/.. # add to it (the normal case)
#
# Exit: 0 clean · 1 strays found

set -u
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$PROJECT_ROOT" || { echo "cannot cd to project root" >&2; exit 1; }

# index.html is allowed because bin/gate-check.sh regenerates it at the project root on every run,
# by design. Two scripts disagreed once: gate-check wrote it, this script failed on it. Allowlisting
# is the pragmatic resolution — it is gitignored, so it never lands in a commit.
#
# AGENTS.md is allowed as a POINTER to CLAUDE.md, never as a copy: two copies of the instructions
# drift, and the one the agent reads is whichever its harness happens to prefer.
ALLOWED="${ROOT_ALLOWED:-AGENTS.md CLAUDE.md CLAUDE.local.md PROJECT.md README.md index.html} ${ROOT_ALLOWED_EXTRA:-}"

STRAY=""
for f in *.md *.html; do
  [ -e "$f" ] || continue
  case " $ALLOWED " in *" $f "*) continue ;; esac
  STRAY="$STRAY $f"
done

if [ -n "$STRAY" ]; then
  echo "✗ Stray docs in project root:"
  for f in $STRAY; do echo "    $f"; done
  echo ""
  echo "  Root is reserved for: $ALLOWED"
  echo "  Move these into the structure:"
  echo "    docs/            progress, generated dashboards"
  echo "    docs/handoffs/   per-workstream briefs"
  echo "    architecture/    blueprints, build plans, module design"
  echo "    analysis/        source analysis, intake, ledgers"
  echo "    design/          wireframes, design system"
  echo "    bug-logs/        confirmed tool bugs"
  echo ""
  echo "  Use 'git mv' so history follows, and fix any cross-references —"
  echo "  several of these documents cite each other by path."
  exit 1
fi

echo "✓ Project root clean (only: $ALLOWED)"
