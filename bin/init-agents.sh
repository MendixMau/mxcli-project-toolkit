#!/usr/bin/env bash
# Scaffolds the toolkit's dev-process agent stubs into a project's .claude/agents/,
# so agent setup can't be skipped or mistyped. Stage-aware, idempotent, never overwrites.
#
# The stubs are SAFE BY CONSTRUCTION: each one refuses to run while {{PLACEHOLDER}}s
# remain, so a copied-but-unconfigured agent fails loudly instead of verifying nothing.
# Complete them per skills/agent-roles.md (an LLM reading the actual project).
#
# Usage: bin/init-agents.sh <project-root> [all|p|build]
#   <project-root>  where your agent sessions run (the dir whose .claude/agents/ is loaded)
#   all    every agent in bin/lib/install-manifest.sh  [default — stubs are inert until
#          completed, so scaffold everything up front; complete each agent's placeholders
#          when its stage actually starts]
#   p      ba-agent + architect-agent                        (Stage P — discovery/architecture)
#   build  mdl-agent + gate-agent + test-agent + review-agent (Stage 5+ — build/verify/test)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/../agents"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <project-root> [p|build|all]" >&2
  exit 1
fi

TARGET="$1"
STAGE="${2:-all}"

# The agent list is NOT hardcoded here. It used to be, and it drifted from
# sync-project.sh's copy: this script installed 5 agents while sync installed 6, so
# review-agent.md never reached a freshly scaffolded project. One manifest, three readers.
. "$SCRIPT_DIR/lib/install-manifest.sh"

case "$STAGE" in
  p)     AGENTS="$MXTK_AGENTS_STAGE_P" ;;
  build) AGENTS="$MXTK_AGENTS_STAGE_BUILD" ;;
  all)   AGENTS="$MXTK_AGENTS" ;;
  *) echo "Error: unknown stage '$STAGE' (use p, build, or all)" >&2; exit 1 ;;
esac
# The manifest names files (foo.md); this loop works in bare agent names.
AGENTS="$(printf '%s\n' $AGENTS | sed 's/\.md$//' | tr '\n' ' ')"

mkdir -p "$TARGET/.claude/agents"
PROJECT_NAME="$(basename "$(cd "$TARGET" && pwd)")"

created=0
for a in $AGENTS; do
  src="$TEMPLATE_DIR/$a.md"
  dst="$TARGET/.claude/agents/$a.md"
  if [ ! -f "$src" ]; then
    echo "Error: template missing: $src" >&2
    exit 1
  fi
  if [ -f "$dst" ]; then
    echo "Skip: $a.md already exists — not overwritten."
    continue
  fi
  sed "s/{{PROJECT}}/$PROJECT_NAME/g" "$src" > "$dst"
  echo "Created: .claude/agents/$a.md"
  created=$((created + 1))
done

if [ "$created" -gt 0 ]; then
  echo ""
  echo "⚠️  These are stubs — inert until completed. Fill each agent's {{PLACEHOLDER}}s per"
  echo "   skills/agent-roles.md WHEN ITS STAGE STARTS (ba/architect at Stage P kickoff;"
  echo "   mdl/gate/test at Stage 5 kickoff). Until completed each agent refuses to run,"
  echo "   by design — so having all five scaffolded up front is safe."
fi
