#!/usr/bin/env bash
# init-company-brain.sh — instantiate templates/company-brain/ as a company's private tier.
#
#   bin/init-company-brain.sh <company-brain-dir> [--name "<Company>"]
#
# A company brain is the private repo between this toolkit (public process) and each project
# (one app): own skills, conventions, lint rules, MDL snippets, approved MPKs, and the patches
# and proposals the company holds against the toolkit. Governance is one line, written into the
# README it creates: reviewed weekly, promoted to the toolkit only by explicit decision.
#
# Idempotent, skip-never-overwrite: a company that has hardened its README keeps it. Safe to
# re-run after a toolkit pull to pick up template files added since. Substitutes {{COMPANY}} and
# {{TOOLKIT_ROOT}}; touches nothing outside <company-brain-dir>; does not git init — that is the
# company's call (skills/toolkit-distribution-design: the toolkit does not act uninvited).
#
# Shape extracted 2026-09-19 from a private repo that had run this model for a month (weekly
# review, promotion by decision, pointer stubs after promotion, proposals/, patches/, widgets/,
# field-runs/, handoffs/). Wire a project to it with bin/wire-company-brain.sh.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE="$TOOLKIT_ROOT/templates/company-brain"

DEST=""; NAME=""
while [ $# -gt 0 ]; do
  case "$1" in
    --name) NAME="${2:-}"; shift ;;
    -h|--help) echo "Usage: $0 <company-brain-dir> [--name \"<Company>\"]"; exit 0 ;;
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *) [ -n "$DEST" ] && { echo "Unexpected extra argument: $1" >&2; exit 1; }; DEST="$1" ;;
  esac
  shift
done
[ -n "$DEST" ] || { echo "Usage: $0 <company-brain-dir> [--name \"<Company>\"]" >&2; exit 1; }
[ -d "$TEMPLATE" ] || { echo "Template missing: $TEMPLATE" >&2; exit 2; }
[ -n "$NAME" ] || NAME="$(basename "$DEST")"

mkdir -p "$DEST"
DEST="$(cd "$DEST" && pwd)"
created=0; kept=0
# Every file in the template, including dotfiles; directories are created as encountered.
while IFS= read -r rel; do
  src="$TEMPLATE/$rel"; dst="$DEST/$rel"
  mkdir -p "$(dirname "$dst")"
  if [ -e "$dst" ]; then
    kept=$((kept+1)); continue
  fi
  sed -e "s|{{COMPANY}}|$NAME|g" -e "s|{{TOOLKIT_ROOT}}|$TOOLKIT_ROOT|g" "$src" > "$dst"
  [ -x "$src" ] && chmod +x "$dst"
  created=$((created+1))
  echo "Created: $rel"
done < <(cd "$TEMPLATE" && find . -type f | sed 's|^\./||' | sort)

echo "Company brain: $DEST — $created created, $kept kept (already present, not overwritten)."
echo "Next: read $DEST/README.md; wire a project with"
echo "  $TOOLKIT_ROOT/bin/wire-company-brain.sh <project-root> $DEST"
