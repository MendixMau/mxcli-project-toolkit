#!/usr/bin/env bash
# Stage P scaffold — creates intake.md / PROJECT.md skeletons for a new conversion project
# and renders the initial index.html dashboard via gate-check.sh.
#
# Idempotent: never overwrites a file that already exists. Safe to re-run.
#
# Usage: bin/init-project.sh <project-dir>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <project-dir>" >&2
  exit 1
fi

PROJECT_DIR="$1"

if [ ! -d "$PROJECT_DIR" ]; then
  echo "Error: project directory does not exist: $PROJECT_DIR" >&2
  exit 1
fi

INTAKE="$PROJECT_DIR/intake.md"
PROJECT_MD="$PROJECT_DIR/PROJECT.md"

if [ -f "$INTAKE" ]; then
  echo "Skip: intake.md already exists — not overwritten."
else
  cat > "$INTAKE" <<'EOF'
# intake.md — Stage P Kickoff Interview

Answer each question either "Answered (verified by inspection): ..." or
"Unverified — how to verify: ...". Per conversion-runbook.md's interview protocol, unknowns
default and get recorded as ASSUMED in PROJECT.md rather than blocking Stage P.

## 1. Which source folder(s) hold the legacy application?

Unverified — how to verify: inspect the workspace root for source clones/submodules.

## 2. Are there licence/security constraints on storing this client's source in this workspace?

Unverified — how to verify: ask the human; not inferable from the code.

## 3. Is an SME available, and who?

Unverified — how to verify: ask the human.

## 4. Are there documents outside the source folders (specs, manuals, screenshots) not yet accounted for?

Unverified — how to verify: search the workspace for spec/doc directories outside the source tree.

## 5. Is this a fresh migration or a continuation/re-run of prior work?

Unverified — how to verify: check for an existing PROJECT.md / analysis/ directory.

## 6. Target Mendix version / mxbuild setup?

Unverified — how to verify: check `~/.mxcli/mxbuild` and the project's .mpr version.

## 7. Deployment target / environment (DTAP)?

Unverified — how to verify: ask the human; not inferable from the source.

## 8. Single Mendix app, or does scale suggest a multiple-app split?

Unverified — how to verify: assess source module count/size during Stage 0 triage.
EOF
  echo "Created: intake.md"
fi

if [ -f "$PROJECT_MD" ]; then
  echo "Skip: PROJECT.md already exists — not overwritten."
else
  PROJECT_NAME="$(basename "$PROJECT_DIR")"
  cat > "$PROJECT_MD" <<EOF
# PROJECT.md — ${PROJECT_NAME} Decision Register

Every gate decision lands here as \`CONFIRMED\` or \`ASSUMED\`, never silently decided. See
\`conversion-runbook.md\` §1 for the interview protocol this file supports.

## Current stage

**Stage P — Kickoff**, in progress.

## Decisions

| Stage | Decision | Status | Notes |
|---|---|---|---|

## Open questions

| # | Question | Raised at | Status |
|---|---|---|---|

## Assumptions (ASSUMED, unresolved)

None yet.
EOF
  echo "Created: PROJECT.md"
fi

echo ""
echo "Next steps (not done by this script):"
echo "  - Stage 0 triage: choose/reuse an extraction pipeline (needs triage first, see source-triage.md)."
echo "  - Generate project-specific subagents (ba-agent, architect-agent, mdl-agent, gate-agent, test-agent)"
echo "    via skills/agent-roles.md — this requires an LLM reading the actual project, not a bash guess."
echo ""

"$SCRIPT_DIR/gate-check.sh" "$PROJECT_DIR" || true

echo "Done. index.html dashboard rendered at $PROJECT_DIR/index.html"
