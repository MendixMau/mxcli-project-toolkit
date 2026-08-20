#!/usr/bin/env bash
# The docs/progress/RESUME.md starter. ONE copy, for the same reason bin/lib/intake-template.sh
# and bin/lib/triage-template.sh exist: init-project.sh writes it and sync-project.sh backfills
# it into projects scaffolded before it existed, and two hand-kept copies of a template in this
# repo have already drifted twice.
#
# WHY A STARTER FILE EXISTS AT ALL
# bin/wire-agents.sh stamps the same first instruction into all six generated entry points
# (CLAUDE.md, AGENTS.md, .github/copilot-instructions.md, .cursorrules, .windsurfrules,
# .aider.conf.yml): "Read docs/progress/RESUME.md first, and nothing else yet." Nothing in the
# init path created docs/ — the only writers are project-bin/close-task.sh and
# claude-hooks/bin/checkpoint.sh, both of which fire at close-the-loop time, i.e. AFTER the first
# session ends. And the same instruction block explicitly closes off the obvious fallback ("Do
# NOT read PROJECT.md to get oriented"). So every new project's very first instruction, in every
# tool, pointed at a file that did not exist, and the agent was left to guess. Found 2026-08-20.
#
# The fix is both halves, because either alone still fails somewhere:
#   - this starter, so the instruction is TRUE from second zero in a freshly scaffolded project;
#   - a named fallback in the stamp itself (wire-agents.sh), because the file is project-owned
#     and a project can legitimately delete it, and because thousands of projects were scaffolded
#     before this file existed.
#
# WHAT IT MUST NOT DO: pretend a session has happened. skills/close-the-loop.md is explicit that
# RESUME.md is OVERWRITTEN by the closing session and is the only file read after /clear. A
# starter that invented a plausible "where we are" would be the same class of defect as the
# intake scaffold that manufactured its own gate's pass condition (see init-project.sh's long
# comment on "_Not yet asked._"). So it says, in its own words, that no session has closed the
# loop here yet, and it routes rather than narrates.
#
# Sourced, never executed. Callers are `set -euo pipefail`, so keep this side-effect free.

# Usage: mxtk_resume_template <toolkit-root>
mxtk_resume_template() {
  local toolkit="${1:-<toolkit-root>}"
  cat <<EOF
# RESUME.md

**Overwritten, never appended. Hard cap ~60 lines.** The one file a session reads first, and for
a while the only one. Append-only history lives in \`checkpoints.md\` next to this file — read
that to audit a past claim, never to resume.

## Where we are

**No session has closed the loop in this project yet** — this file is the toolkit's starter
scaffold (\`bin/init-project.sh\`, or \`bin/sync-project.sh\` backfilling a project that predates
it). The first session to finish work overwrites it wholesale per
\`$toolkit/skills/close-the-loop.md\`.

**So the stage is not stated here, on purpose.** A scaffold that guessed "Stage P" would be
confidently wrong on any project that was already mid-flight when this file appeared, and a wrong
resume doc is worse than none. Step 1 below is how to find out.

## Next actions, in order

1. Run \`$toolkit/bin/gate-check.sh .\` — it reports the current stage from the files on disk.
   That verdict, not this file, is the answer to "where are we".
2. **If it reports Stage P:** run the kickoff interview against \`intake.md\`. Question 1 is the
   entry mode (migration / requirements-driven / greenfield) and it decides everything after.
   Every question is asked in chat and the turn then ENDS and waits —
   \`$toolkit/skills/interview-protocol.md\` §3. Record each answer in \`PROJECT.md\` as
   \`CONFIRMED\` or \`ASSUMED\`.
   **If it reports anything later:** the stage's owning skill lists what that stage owes — find it
   in \`CLAUDE.local.md\`'s baseline routing, or in the runbook's stage matrix.
3. Overwrite this file before the session ends (\`bin/close-task.sh\` prints the checklist), so
   the next one does not have to repeat step 1.

## Do not lose

Nothing recorded yet. This section is where a closing session puts the thing that would be
expensive to rediscover — not a summary, only what would otherwise be lost.

## Read this larger file only if you are doing that specific thing

| Doing | Read |
|---|---|
| Anything at all in the pipeline | \`CLAUDE.local.md\` — wiring, session-start ritual, baseline routing |
| Working out what stage anything is in | \`$toolkit/skills/conversion-runbook.md\` |
| The kickoff interview | \`intake.md\`, then \`PROJECT.md\` |
| Auditing why a past decision was made | \`PROJECT.md\` (decision register — not an orientation doc) |
| Rewriting this file at the end of a session | \`$toolkit/skills/close-the-loop.md\` |
EOF
}
