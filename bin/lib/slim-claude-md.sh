# shellcheck shell=bash
# bin/lib/slim-claude-md.sh — move the reference sections of a pre-v0.22 `mxcli init` CLAUDE.md
# out of the always-loaded context. Sourced by bin/init-project.sh and bin/sync-project.sh.
#
# WHY. `mxcli init` up to v0.21 wrote a ~30k-character CLAUDE.md: every MDL command table, the
# lint rule list, slash commands, a skills index and worked examples. v0.22 (2026-09-14) cut its
# own template to ~6k ("ask the tool, not this file"). But wire-agents.sh PRESERVES an existing
# CLAUDE.md, so a project scaffolded before v0.22 keeps the 30k file on every call of every
# session forever, whatever mxcli it runs today. A field run (2026-10-07, requirements-driven
# build) sat at a fixed 60k-token floor per call; the 2x2 bench (2026-10-01) ran the same five
# build steps with these sections removed: 0 failures against 2, peak context 35k against 55k,
# cost 0.56 against 0.93.
#
# WHAT. Only a file carrying the pre-v0.22 signature heading "## MDL Commands by Domain" and no
# `<!-- mxcli:begin` marker is touched. The h2 sections named in SLIM_CLAUDE_MD_MOVE (exact
# heading match, fenced code skipped) are MOVED — not deleted — to docs/mxcli-reference.md,
# and one short section pointing there takes the place of the first. Everything else stays
# byte-for-byte: Communication Style, the mxcli location, the skills-before-MDL table, script
# validation, the syntax quick reference, and any section the project or bootstrap-project.md
# added. The original is copied to .mxtk-backup/CLAUDE.md.pre-slim first. A second run finds
# no signature heading and does nothing. Off switch: MXTK_SLIM_CLAUDE_MD=off.
#
# Golden input: tests/wave2/fixtures/slim-claude-md/mxcli-v0.21.0-init.CLAUDE.md, a verbatim
# `mxcli init` capture from v0.21.0 built from its tag.

SLIM_CLAUDE_MD_SIGNATURE='## MDL Commands by Domain'
SLIM_CLAUDE_MD_MOVE='## Mendix Validation Tool (mx)|## Quick Start|## MDL Commands by Domain|## Linting|## Best Practices Report|## Slash Commands|## Skills Reference|## MDL Script Files|## Example: Create an Entity|## Example: Create a Microflow|## MDL Reference'

# slim_claude_md_needed <project-dir> — 0 when CLAUDE.md is a pre-v0.22 init file to slim.
slim_claude_md_needed() {
  _sc_f="$1/CLAUDE.md"
  [ "${MXTK_SLIM_CLAUDE_MD:-on}" = "off" ] && return 1
  [ -f "$_sc_f" ] || return 1
  grep -qF -- '<!-- mxcli:begin' "$_sc_f" && return 1
  grep -qxF -- "$SLIM_CLAUDE_MD_SIGNATURE" "$_sc_f"
}

# slim_claude_md <project-dir> — do it. Prints one line; returns 0 on a rewrite, 1 otherwise.
slim_claude_md() {
  _sc_dir="$1"; _sc_f="$_sc_dir/CLAUDE.md"
  slim_claude_md_needed "$_sc_dir" || return 1
  _sc_keep="$(mktemp "${TMPDIR:-/tmp}/slimkeep.XXXXXX")" || return 1
  _sc_move="$(mktemp "${TMPDIR:-/tmp}/slimmove.XXXXXX")" || { rm -f "$_sc_keep"; return 1; }
  awk -v list="$SLIM_CLAUDE_MD_MOVE" -v movefile="$_sc_move" '
    BEGIN { n = split(list, h, "|"); for (i = 1; i <= n; i++) want[h[i]] = 1; drop = 0; placed = 0; fence = 0 }
    {
      if (substr($0, 1, 3) == "```") fence = !fence
      if (!fence && substr($0, 1, 3) == "## ") {
        drop = ($0 in want)
        if (drop && !placed) {
          print "## Reference moved out of the always-loaded context"
          print ""
          print "The MDL command tables, lint rules, slash commands, skills index and examples that"
          print "`mxcli init` (before v0.22) wrote here are in `docs/mxcli-reference.md` — read it only"
          print "when you need one. Usually faster: `./mxcli help <topic>`, or the skill in `.ai-context/skills/`."
          print ""
          placed = 1
        }
      }
      if (drop) print > movefile; else print
    }' "$_sc_f" > "$_sc_keep" || { rm -f "$_sc_keep" "$_sc_move"; return 1; }
  mkdir -p "$_sc_dir/.mxtk-backup" "$_sc_dir/docs"
  cp "$_sc_f" "$_sc_dir/.mxtk-backup/CLAUDE.md.pre-slim"
  {
    echo "# mxcli reference (moved from CLAUDE.md)"
    echo ""
    echo "Moved here by the toolkit's slim-claude-md step so it is not loaded on every call."
    echo "Written by \`mxcli init\` before v0.22 — when it disagrees with \`./mxcli help\`, the tool wins."
    echo ""
    cat "$_sc_move"
  } > "$_sc_dir/docs/mxcli-reference.md"
  _sc_before="$(wc -c < "$_sc_f" | tr -d ' ')"
  cat "$_sc_keep" > "$_sc_f"
  _sc_after="$(wc -c < "$_sc_f" | tr -d ' ')"
  rm -f "$_sc_keep" "$_sc_move"
  echo "Slimmed: CLAUDE.md $_sc_before → $_sc_after bytes — pre-v0.22 mxcli reference sections moved to docs/mxcli-reference.md (original in .mxtk-backup/CLAUDE.md.pre-slim)."
  return 0
}
