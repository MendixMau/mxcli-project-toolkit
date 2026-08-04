#!/usr/bin/env bash
# restart-sp.sh — kill this project's Studio Pro instance + runtime, reopen cleanly.
#
# Targets ONLY the SP process holding this project's .mpr, found via lsof — not
# every SP on the machine. Two projects open at once is normal; killing the
# wrong one loses unsaved work.
#
# macOS only (lsof/open/Version Selector).
set -euo pipefail
. "$(dirname "$0")/_common.sh"

MPR="$(find_mpr)" || exit 1
NAME="$(basename "$MPR" .mpr)"
DEPLOYMENT="$PROJECT_ROOT/deployment"
RUNTIME_PORT="${MENDIX_RUNTIME_PORT:-8081}"

echo "→ Killing Mendix runtime (port $RUNTIME_PORT + deployment-path processes)..."
lsof -ti :"$RUNTIME_PORT" 2>/dev/null | xargs kill -9 2>/dev/null || true
[ -d "$DEPLOYMENT" ] && { lsof -t "$DEPLOYMENT" 2>/dev/null | xargs kill -9 2>/dev/null || true; }

echo "→ Killing the SP instance holding $NAME..."
# Graceful TERM, then poll for exit — a blind `sleep 5` either wastes time or
# force-kills a process that was still flushing.
SP_PID=$(lsof -t "$MPR" 2>/dev/null || true)
if [ -n "$SP_PID" ]; then
  kill -TERM $SP_PID 2>/dev/null || true
  for _ in $(seq 1 25); do
    kill -0 $SP_PID 2>/dev/null || break
    sleep 1
  done
  kill -9 $SP_PID 2>/dev/null || true
fi

echo "→ Killing child processes (mxcli + orphaned modeler helpers)..."
[ -d "$DEPLOYMENT" ] && { lsof -t "$DEPLOYMENT" 2>/dev/null | xargs kill -9 2>/dev/null || true; }
pkill -9 -f "mxcli" 2>/dev/null || true
# The modeler spawns a deno helper per live-preview session that is not reliably
# cleaned up on close; they accumulate across restarts. Safe to kill here since
# we are already force-restarting SP.
pkill -9 -f "Mendix Studio Pro.*tools/deno" 2>/dev/null || true

echo "→ Waiting for SP to release $NAME..."
for _ in $(seq 1 20); do
  lsof -t "$MPR" >/dev/null 2>&1 || break
  sleep 1
done

echo "→ Checking $(basename "$MPR").lock..."
if [ -f "$MPR.lock" ]; then
  LOCK_PID=$(grep -oE '"ProcessId":[0-9]+' "$MPR.lock" 2>/dev/null | grep -oE '[0-9]+' || true)
  if [ -n "$LOCK_PID" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
    echo "  (lock PID $LOCK_PID still alive — force-killing before removing lock)"
    kill -9 "$LOCK_PID" 2>/dev/null || true
  elif [ -n "$LOCK_PID" ]; then
    echo "  (stale lock from dead PID $LOCK_PID — safe to remove)"
  fi
  chmod 644 "$MPR.lock" 2>/dev/null || true
  rm -f "$MPR.lock"
fi

echo "→ Waiting for the MPR to be fully released..."
for _ in $(seq 1 15); do
  lsof "$MPR" >/dev/null 2>&1 || break
  sleep 1
done

echo "→ Reopening $NAME..."
open -a "Mendix Version Selector" "$MPR"

echo "✓ Done — click Run Locally in Studio Pro once it finishes loading."
