#!/usr/bin/env bash
# wire-agents.sh — give every AI coding agent the same entry point into a project.
#
# WHY THIS EXISTS. init-project.sh wrote CLAUDE.local.md and nothing else, so a scaffolded
# project was Claude-only. A colleague opening it in Copilot, Cursor or Windsurf got no
# routing at all: they found PROJECT.md (a 60k decision register), read it as an orientation
# doc, and started guessing at next steps. Measured on WMS-Demo-main, 2026-08-18.
#
# `mxcli init --tool X` already emits a decent pointer file for eight tools. Two problems kept
# it from being usable as-is, and this script exists to fix exactly those two:
#
#   1. IT CLOBBERS HAND-WRITTEN INSTRUCTIONS. `mxcli init` overwrites AGENTS.md *and* CLAUDE.md
#      with a 649-line generated file — byte-identical to each other — with no prompt, no
#      backup and no diff. WMS-Demo-main's AGENTS.md was a hand-written 11-line pointer that
#      existed *because* someone had already deleted a 650-line generated copy; the next
#      `mxcli init` would have silently restored the very thing they removed. So: this script
#      never lets init destroy a file that was already there. Pre-existing content always wins.
#
#   2. IT CANNOT KNOW THE PROJECT-SPECIFIC BITS. mxcli emits generic MDL guidance. It has no
#      idea this project has a RESUME.md, a no-artifacts-in-root rule, or an approval gate on
#      `exec`. Those are stamped in afterwards, inside a marker block, so re-running is safe
#      and a regenerated file is repaired rather than hand-patched again.
#
# Idempotent. Safe to re-run after every mxcli upgrade — that is the intended use.
#
# Usage:
#   bin/wire-agents.sh <project-dir>                      # default tool set
#   bin/wire-agents.sh <project-dir> --with-skill-copies  # + opencode, vibe (see below)
#   bin/wire-agents.sh <project-dir> --check              # verify only, write nothing
#   bin/wire-agents.sh <project-dir> --dry-run            # show what would change
#
# TOOL SETS. The default six cost ~240 lines in total, because each is a pointer file:
#   claude copilot cursor continue windsurf aider
# opencode and vibe are behind --with-skill-copies because they do NOT support a pointer file.
# Each wants its own skills/<name>/SKILL.md tree, so mxcli materialises the whole ~70-skill
# corpus per tool: .opencode/ is 27,147 lines and .vibe/ is 26,667. Enabling both puts three
# copies of the same skills in one repo, and `mxcli init --sync-skills` documents itself as
# refreshing .ai-context/skills/ ONLY — so on the next upgrade the other two silently go stale.
# That is the exact two-copies-drift failure this whole file is trying to prevent. Opt in only
# if someone on the project actually uses those tools.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DEFAULT_TOOLS="claude copilot cursor continue windsurf aider"
OPTIN_TOOLS="opencode vibe"

# Files that carry a stamped block. Markdown and freeform-text rule files only: .continue's
# config is JSON (no comment syntax) and opencode.json likewise, so they are left to mxcli and
# reported as unstamped rather than corrupted with a comment their parser rejects.
STAMP_MD="AGENTS.md CLAUDE.md .github/copilot-instructions.md .cursorrules .windsurfrules"
STAMP_HASH=".aider.conf.yml"

MARK_START="mxtk:wiring:start"
MARK_END="mxtk:wiring:end"

PROJECT_DIR=""
MXCLI_HINT='`./mxcli`, not `mxcli`.** The binary is in the project root, never on PATH.'
WITH_COPIES=""
CHECK_ONLY=""
DRY=""

while [ $# -gt 0 ]; do
  case "$1" in
    --with-skill-copies) WITH_COPIES=1 ;;
    --check)             CHECK_ONLY=1 ;;
    --dry-run)           DRY="[dry-run] " ;;
    -h|--help)           sed -n '2,40p' "$0"; exit 0 ;;
    -*)                  echo "wire-agents.sh: unknown flag: $1" >&2; exit 2 ;;
    *)                   [ -n "$PROJECT_DIR" ] && { echo "wire-agents.sh: too many arguments" >&2; exit 2; }
                         PROJECT_DIR="$1" ;;
  esac
  shift
done

[ -n "$PROJECT_DIR" ] || { echo "Usage: bin/wire-agents.sh <project-dir> [--with-skill-copies] [--check] [--dry-run]" >&2; exit 2; }
[ -d "$PROJECT_DIR" ] || { echo "wire-agents.sh: not a directory: $PROJECT_DIR" >&2; exit 2; }
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"

# --- the stamp ------------------------------------------------------------------------------
# Everything mxcli cannot know. Kept SHORT on purpose: an agent that has to read 200 lines to
# find the entry point is in the same position as one that read nothing. Five facts, no prose.
emit_stamp() {
  cat <<STAMP_END
<!-- $MARK_START — written by mxcli-project-toolkit/bin/wire-agents.sh.
     Edit that script, not this block: it is replaced wholesale on every re-run. -->

## Start here (all AI agents, every session)

1. **Read \`docs/progress/RESUME.md\` first, and nothing else yet.** Where we are, the next
   actions, and a table saying which larger file to open for the task at hand. Do NOT read
   \`PROJECT.md\` to get oriented — it is a decision register, not a resume doc.
2. **\`CLAUDE.md\` is the canonical project instruction file** regardless of which agent you
   are. Every other instruction file in this repo, including this one, is a pointer to it.
3. **Never run \`./mxcli exec\`, \`./bin/exec.sh\`, \`mxcli test\`, \`mxcli docker check\`, or any
   \`--mcp\` write against the real \`.mpr\` without asking the user first — every time.** All of
   those mutate the model; the last two mutate it despite sounding read-only.
4. **$MXCLI_HINT
5. **No new \`.md\`/\`.html\` in the project root.** Use docs/ architecture/ analysis/ design/.
   \`bin/check-root-clean.sh\` fails the build on strays.

Skill guides live in \`.ai-context/skills/\` — read the relevant one before writing MDL.

<!-- $MARK_END -->
STAMP_END
}

# Same five facts as '#' comments, for a YAML config where a markdown block would not parse.
emit_stamp_hash() {
  emit_stamp | sed 's/^/# /' | sed 's/[[:space:]]*$//'
}

has_mark() { [ -f "$1" ] && grep -q "$MARK_START" "$1" 2>/dev/null; }

# Strip our marker block and any trailing blank lines. Used on BOTH sides of the divergence
# diff so the comparison is about mxcli's content, never about our own formatting.
normalize_for_diff() {
  awk -v s="$MARK_START" -v e="$MARK_END" '
    index($0,s) { skip=1 }
    !skip       { print }
    index($0,e) { skip=0; next }
  ' | awk '
    { lines[NR] = $0 }
    END {
      last = NR
      while (last > 0 && lines[last] ~ /^[[:space:]]*$/) last--
      for (i = 1; i <= last; i++) print lines[i]
    }'
}

# Replace an existing marker block, or append a new one. Never `sed -i` — GNU and BSD disagree
# on whether the next argument is a backup suffix or the script, and the BSD form is rejected
# by check-portability.sh for exactly that reason.
stamp_file() {
  f="$1"; style="$2"
  [ -f "$f" ] || return 0
  tmp="$(mktemp "${TMPDIR:-/tmp}/wireagents.XXXXXX")" || return 1
  if has_mark "$f"; then
    awk -v s="$MARK_START" -v e="$MARK_END" '
      index($0,s) { skip=1 }
      !skip       { print }
      index($0,e) { skip=0; next }
    ' "$f" > "$tmp"
    # Collapse the blank run the excision leaves behind, so re-runs do not grow the file.
    awk 'BEGIN{b=0} /^[[:space:]]*$/{b++; next} {while(b>0){print ""; b--} print} END{print ""}' "$tmp" > "$tmp.2"
    mv "$tmp.2" "$tmp"
  else
    cat "$f" > "$tmp"
    printf '\n' >> "$tmp"
  fi
  if [ "$style" = hash ]; then emit_stamp_hash >> "$tmp"; else emit_stamp >> "$tmp"; fi
  if [ -n "$DRY" ]; then rm -f "$tmp"; echo "${DRY}Would stamp: $f"; return 0; fi
  mv "$tmp" "$f"
  echo "Stamped: $f"
}

# --- verify mode ----------------------------------------------------------------------------
verify() {
  missing=0
  for rel in $STAMP_MD $STAMP_HASH; do
    f="$PROJECT_DIR/$rel"
    if [ ! -f "$f" ]; then
      echo "  MISSING  $rel — never generated. Re-run bin/wire-agents.sh $PROJECT_DIR"
      missing=$((missing + 1))
    elif ! has_mark "$f"; then
      echo "  UNSTAMPED $rel — regenerated by mxcli and lost its wiring block."
      echo "            Agents reading it get generic MDL help and no route to RESUME.md."
      missing=$((missing + 1))
    fi
  done
  if [ "$missing" -gt 0 ]; then
    echo ""
    echo "$missing agent entry point(s) not wired. Fix: bin/wire-agents.sh $PROJECT_DIR"
    return 1
  fi
  echo "  All agent entry points carry the wiring block."
  return 0
}

echo "=== Agent wiring for $PROJECT_NAME ==="

if [ -n "$CHECK_ONLY" ]; then
  verify
  exit $?
fi

# --- run mxcli init -------------------------------------------------------------------------
TOOLS="$DEFAULT_TOOLS"
if [ -n "$WITH_COPIES" ]; then
  TOOLS="$TOOLS $OPTIN_TOOLS"
  echo "Including opt-in tools ($OPTIN_TOOLS): adds ~54k lines of duplicated skill copies."
fi

# Find mxcli. A project-local binary wins, because that is what the project's own docs and the
# guard-chain scripts call — but plenty of developers install it once and put it on PATH, and
# the first version of this script simply gave up on them: zero files wired, plus a message
# telling them to copy a binary they already had. Reported 2026-08-18.
if [ -x "$PROJECT_DIR/mxcli" ]; then
  MXCLI="$PROJECT_DIR/mxcli"
  MXCLI_HOW="project-local"
elif command -v mxcli >/dev/null 2>&1 && mxcli --help >/dev/null 2>&1; then
  # Probed by EXECUTING, per bin/lib/portable.sh: a name on PATH is not necessarily a runnable
  # program (on Windows it is routinely a Store alias stub that opens a shop instead).
  MXCLI="$(command -v mxcli)"
  MXCLI_HOW="on PATH"
else
  # Not fatal: init-project.sh scaffolds docs before the binary is necessarily in place, and
  # failing the whole scaffold over a missing optional step is worse than saying so plainly.
  echo "mxcli not found — not in $PROJECT_DIR and not runnable on PATH. Skipping generation."
  echo "Install it, or drop the binary in the project root, then re-run:"
  echo "  bin/wire-agents.sh $PROJECT_DIR"
  exit 0
fi
echo "Using mxcli ($MXCLI_HOW): $MXCLI"

# The stamp must tell the truth about THIS project. Telling a PATH user "the binary is in the
# project root, never on PATH" is not a harmless inaccuracy — it is a wrong instruction copied
# into six files, and it contradicts what they can see in their own shell.
if [ "$MXCLI_HOW" = "project-local" ]; then
  MXCLI_HINT='`./mxcli`, not `mxcli`.** The binary is in the project root, never on PATH.'
else
  MXCLI_HINT='`mxcli` is on your PATH.** This project has no local copy; plain `mxcli` is correct here.'
fi

# Preserve anything that already exists. `mxcli init` overwrites AGENTS.md and CLAUDE.md
# unconditionally, and a project's hand-tuned CLAUDE.md is the single most expensive file in
# the repo to lose. Backups go somewhere the user can find without being told twice.
BACKUP_DIR="$PROJECT_DIR/.mxtk-backup"
STAMP_TS="$(date -u '+%Y%m%dT%H%M%SZ')"
PRESERVE="AGENTS.md CLAUDE.md .github/copilot-instructions.md .cursorrules .windsurfrules .aider.conf.yml"

if [ -z "$DRY" ]; then mkdir -p "$BACKUP_DIR"; fi
for rel in $PRESERVE; do
  src="$PROJECT_DIR/$rel"
  [ -f "$src" ] || continue
  if [ -z "$DRY" ]; then
    dst="$BACKUP_DIR/$(echo "$rel" | tr '/' '_').$STAMP_TS"
    cp "$src" "$dst"
  fi
done

TOOL_ARGS=""
for t in $TOOLS; do TOOL_ARGS="$TOOL_ARGS --tool $t"; done

if [ -n "$DRY" ]; then
  echo "${DRY}Would run: $MXCLI init$TOOL_ARGS"
else
  echo "Running: ./mxcli init$TOOL_ARGS"
  ( cd "$PROJECT_DIR" && "$MXCLI" init $TOOL_ARGS >/dev/null 2>&1 ) || {
    echo "wire-agents.sh: mxcli init failed. Nothing was stamped; your backups are in .mxtk-backup/." >&2
    exit 1
  }
fi

# Restore anything init overwrote. A file that existed before this script ran is the user's,
# full stop — we do not get to decide their 11k CLAUDE.md was worth less than a 649-line stub.
#
# But restoring SILENTLY would be its own trap: a future mxcli might fix a wrong flag in one of
# these files and we would suppress the correction forever, invisibly. So this follows the same
# idiom sync-project.sh already uses for completed agents — restore, then REPORT what was
# suppressed and keep the generated copy on disk. Nothing is auto-adopted; nothing is silently
# lost; a human decides. The report is the whole point, so it prints even when it is boring.
RESTORED=0
DIVERGED=""
if [ -z "$DRY" ]; then
  for rel in $PRESERVE; do
    bak="$BACKUP_DIR/$(echo "$rel" | tr '/' '_').$STAMP_TS"
    cur="$PROJECT_DIR/$rel"
    [ -f "$bak" ] || continue
    [ -f "$cur" ] || continue
    cmp -s "$bak" "$cur" && continue

    # Keep what mxcli produced, next to the backup, so the diff below can be acted on later.
    gen="$BACKUP_DIR/$(echo "$rel" | tr '/' '_').generated.$STAMP_TS"
    cp "$cur" "$gen"
    cp "$bak" "$cur"
    RESTORED=$((RESTORED + 1))

    # Compare like with like. Our stamp is not a divergence, it is ours — and neither is the
    # blank line stamping leaves behind. Normalising only one side made every file report a
    # phantom "1 line only in yours" on a run where nothing had been edited, which trains the
    # reader to ignore the report. Both sides go through the same filter.
    a="$(mktemp "${TMPDIR:-/tmp}/wireagents.XXXXXX")" || continue
    b="$(mktemp "${TMPDIR:-/tmp}/wireagents.XXXXXX")" || { rm -f "$a"; continue; }
    normalize_for_diff < "$bak" > "$a"
    normalize_for_diff < "$gen" > "$b"

    gonly=$(diff "$a" "$b" 2>/dev/null | grep -c '^>' || true)
    ponly=$(diff "$a" "$b" 2>/dev/null | grep -c '^<' || true)
    rm -f "$a" "$b"
    if [ "$gonly" -gt 0 ] || [ "$ponly" -gt 0 ]; then
      DIVERGED="$DIVERGED$rel|$gonly|$ponly
"
    fi
  done
fi

# --- stamp ------------------------------------------------------------------------------------
for rel in $STAMP_MD;   do stamp_file "$PROJECT_DIR/$rel" md;   done
for rel in $STAMP_HASH; do stamp_file "$PROJECT_DIR/$rel" hash; done

echo ""
if [ -n "$DRY" ]; then
  echo "${DRY}No files were changed."
  exit 0
fi

verify || true

echo ""
echo "Not stamped (no comment syntax — left as mxcli generated them):"
echo "  .continue/config.json, opencode.json"
echo ""
echo "Re-run this after every mxcli upgrade: an upgrade regenerates these files and drops the"
echo "wiring block. 'bin/wire-agents.sh <dir> --check' is the cheap way to notice."
# --- divergence report ------------------------------------------------------------------------
# Report-only, like sync-project.sh's completed-agent path. Nothing here is written.
if [ -n "$DIVERGED" ]; then
  echo ""
  echo "=== What mxcli would have changed (suppressed to protect your files) ==="
  echo "Report-only. Your versions are in place; mxcli's are kept alongside them."
  echo ""
  printf '%s' "$DIVERGED" | while IFS='|' read -r rel gonly ponly; do
    [ -n "$rel" ] || continue
    echo "--- $rel"
    echo "    $gonly line(s) only in mxcli's version  -> may be an upstream improvement you want"
    echo "    $ponly line(s) only in yours            -> your local edits, kept"
  done
  echo ""
  echo "To see one in full:"
  echo "  diff <project>/<file> $BACKUP_DIR/<file>.generated.$STAMP_TS"
  echo ""
  echo "Adopt a change by editing your file by hand. Nothing is copied over automatically:"
  echo "an mxcli upgrade must never be able to silently rewrite a project's instructions."
fi

[ "$RESTORED" -gt 0 ] && echo "Backups of the ${RESTORED} preserved file(s): .mxtk-backup/"
exit 0
