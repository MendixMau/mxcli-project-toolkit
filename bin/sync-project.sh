#!/usr/bin/env bash
# Refreshes the toolkit artifacts that were COPIED into a project (everything referenced
# from the toolkit clone updates by git pull alone — this handles only the copies).
#
# Safe by construction:
#   - intake.md: appends questions that exist in the current template but not in the file.
#     Never rewrites existing answers.
#   - agent stubs: refreshes only PURE stubs (still carry the STUB marker and at least one
#     {{PLACEHOLDER}} — i.e. nobody completed them). Completed agents are never touched;
#     they get a "review against current template" note instead.
#   - CLAUDE.md baseline routing: report-only (merging prose is an LLM job — see
#     bootstrap-project.md audit mode).
#
# Run after every `git pull` of the toolkit:  bin/sync-project.sh <project-root>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/../agents"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <project-root>" >&2
  exit 1
fi

PROJECT_DIR="$1"
if [ ! -d "$PROJECT_DIR" ]; then
  echo "Error: project directory does not exist: $PROJECT_DIR" >&2
  exit 1
fi

echo "=== Toolkit sync for $PROJECT_DIR ==="
CHANGES=0

# --- 1. intake.md: append questions the current template has and this file lacks -------
INTAKE="$PROJECT_DIR/intake.md"
if [ -f "$INTAKE" ]; then
  if ! grep -q "^## 9\." "$INTAKE"; then
    cat >> "$INTAKE" <<'EOF'

## 9. Interview mode: attended (default) or unattended?

Attended unless the user explicitly says otherwise. Attended = every gate question is asked
in chat and the agent waits for the answer. Unattended (opt-in only) = recommended options
are applied as ASSUMED and questions are logged in PROJECT.md for later reconciliation.
EOF
    echo "Updated: intake.md — appended Q9 (interview mode). Answer it this session."
    CHANGES=$((CHANGES + 1))
  fi
else
  echo "Note: no intake.md — run bin/init-project.sh first if this project uses the pipeline."
fi

# --- 2. Agent stubs: refresh pure stubs, report completed ones --------------------------
AGENT_DIR="$PROJECT_DIR/.claude/agents"
if [ -d "$AGENT_DIR" ]; then
  PROJECT_NAME="$(basename "$(cd "$PROJECT_DIR" && pwd)")"
  for src in "$TEMPLATE_DIR"/*.md; do
    a="$(basename "$src")"
    dst="$AGENT_DIR/$a"
    if [ ! -f "$dst" ]; then
      sed "s/{{PROJECT}}/$PROJECT_NAME/g" "$src" > "$dst"
      echo "Created: .claude/agents/$a (new since this project was scaffolded)"
      CHANGES=$((CHANGES + 1))
    elif grep -q "STUB GENERATED" "$dst" && grep -q "{{[A-Z_]*[^}]*}}" "$dst"; then
      # Pure stub, never completed — safe to refresh with the current template.
      if ! sed "s/{{PROJECT}}/$PROJECT_NAME/g" "$src" | cmp -s - "$dst"; then
        sed "s/{{PROJECT}}/$PROJECT_NAME/g" "$src" > "$dst"
        echo "Refreshed: .claude/agents/$a (was an untouched stub; template has changed)"
        CHANGES=$((CHANGES + 1))
      fi
    else
      echo "Kept: .claude/agents/$a is completed — review it against agents/$a manually if the template changed."
    fi
  done
else
  echo "Note: no .claude/agents/ here — run bin/init-agents.sh $PROJECT_DIR if sessions run from this directory."
fi

# --- 3. Baseline routing / runbook-first wiring -----------------------------------------
if [ ! -f "$PROJECT_DIR/CLAUDE.local.md" ] && { [ ! -f "$PROJECT_DIR/CLAUDE.md" ] || ! grep -q "conversion-runbook" "$PROJECT_DIR/CLAUDE.md"; }; then
  echo "⚠️  No runbook-first wiring found (no CLAUDE.local.md, and CLAUDE.md doesn't reference"
  echo "   conversion-runbook.md). Run: $SCRIPT_DIR/init-project.sh $PROJECT_DIR"
  echo "   (idempotent — it will only add the missing CLAUDE.local.md, never overwrite files)."
fi
for cm in "$PROJECT_DIR/CLAUDE.md" "$PROJECT_DIR/CLAUDE.local.md"; do
  if [ -f "$cm" ] && ! grep -q "query-the-model" "$cm"; then
    echo "⚠️  $(basename "$cm") does not reference the Baseline routing set — audit it per bootstrap-project.md."
  fi
done

echo ""
if [ "$CHANGES" -gt 0 ]; then
  echo "$CHANGES artifact(s) updated. Also tell the active session: 'the toolkit changed —"
  echo "re-read README.md and skills/conversion-runbook.md before acting.'"
else
  echo "All copied artifacts up to date. Referenced skills update via git pull alone —"
  echo "just have the session re-read the runbook if it started before the pull."
fi
