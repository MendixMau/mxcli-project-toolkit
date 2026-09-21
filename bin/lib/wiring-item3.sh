#!/usr/bin/env bash
# wiring-item3.sh — item 3 of wire-agents.sh's "Start here" stamp, in ONE place.
#
# WHY A SEPARATE FILE (2026-09-15). wire-agents.sh writes this item fresh on every run, but
# bin/sync-project.sh has to patch it IN PLACE on projects wired before the text last changed —
# its refresh gate (`wire-agents.sh --check`) only tests whether the marker block EXISTS, never
# whether the text inside it is current, so a project wired under an old wording never sees the
# new one again on its own. Two writers needing the same sentence is exactly the shape that
# already drifted once in this repo (see the header of bin/lib/discover-brds.sh: "that is what
# duplication costs: the fix does not travel") — so it is sourced from here instead of typed
# twice.
#
# Sourced by bin/wire-agents.sh (fresh stamps) and bin/sync-project.sh (in-place repair of stale
# ones). Not executable on its own. Bash 3.2 compatible: no arrays, no ${var,,}.
#
# wiring_item3_md <toolkit-root>    item 3, markdown numbered-list form (AGENTS.md, CLAUDE.md,
#                                   .github/copilot-instructions.md, .cursorrules, .windsurfrules)
# wiring_item3_hash <toolkit-root>  the same text, "# "-prefixed (.aider.conf.yml, no comment
#                                   syntax for markdown)
#
# <toolkit-root> is an absolute path with no trailing slash, exactly what wire-agents.sh's own
# $TOOLKIT_ROOT and sync-project.sh's own $TOOLKIT_ROOT already resolve to — bin/exec-approval.sh
# is not copied per-project (same as bin/interview-mode.sh), so the stamped instruction has to
# name where it actually lives.

wiring_item3_md() {
  local tk="$1"
  cat <<EOF
3. **Exec approval defaults to \`auto\` (2026-09-16).** State the resolved mode once, at session
   start: "Exec approval: auto — I run scripts through bin/exec.sh and log them; say 'ask before
   exec' to switch." Before any \`./mxcli exec\`, \`./bin/exec.sh\`, \`mxcli test\`, \`mxcli docker
   check\`, or any \`--mcp\` write against the real \`.mpr\` — all of those mutate the model, the
   last two despite sounding read-only — check \`$tk/bin/exec-approval.sh <project-root>\`. Under
   \`auto\`, run it without asking and say in chat what ran; under \`ask\`, ask first, every time.
   The user switches either way by saying so — only then run
   \`bin/exec-approval.sh <project-root> --set auto\` / \`--set ask\`, never on your own judgement.
   Even on \`auto\`, SAY in chat (don't ask) before a STOP-table operation — drops on entities
   with data, \`ALTER SETTINGS\`, security level changes, cross-module moves — see
   \`skills/learned-mdl-preflight.md\`'s STOP table.
EOF
}

wiring_item3_hash() {
  wiring_item3_md "$1" | sed 's/^/# /' | sed 's/[[:space:]]*$//'
}
