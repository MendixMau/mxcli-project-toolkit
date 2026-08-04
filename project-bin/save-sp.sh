#!/usr/bin/env bash
# save-sp.sh — trigger Cmd+S in Studio Pro, flushing the in-memory model to disk.
#
# Run after any MCP write. SP holds the model in memory; until it saves, the
# .mpr on disk does not contain your change, and anything reading the file
# (mxbuild, mxcli, git) sees the older state.
#
# macOS only — it drives the GUI via AppleScript. Requires Accessibility
# permission for the terminal app, or the keystroke is silently dropped.
set -euo pipefail
. "$(dirname "$0")/_common.sh"

APP_PATH="$(find_sp_app)" || exit 1
APP_NAME="$(basename "$APP_PATH" .app)"

osascript -e "tell application \"$APP_NAME\" to activate" 2>/dev/null || {
  echo "✗ Could not activate '$APP_NAME' — is Studio Pro running?" >&2
  exit 1
}
sleep 0.5
osascript -e 'tell application "System Events" to keystroke "s" using command down' 2>/dev/null || {
  echo "✗ Keystroke refused. Grant Accessibility permission to your terminal:" >&2
  echo "  System Settings → Privacy & Security → Accessibility" >&2
  exit 1
}
echo "✓ SP save triggered ($APP_NAME) — MPR flushed to disk."
