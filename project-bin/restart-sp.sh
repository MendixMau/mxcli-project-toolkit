#!/usr/bin/env bash
# restart-sp.sh — kill this project's Studio Pro instance + runtime, reopen cleanly.
#
# Targets ONLY the SP process holding this project's .mpr, found via lsof — not
# every SP on the machine. Two projects open at once is normal; killing the
# wrong one loses unsaved work.
#
# macOS only (lsof/open/sample). See restart-sp.ps1 for the Windows port
# (added 2026-08-04, far less proven — no `sample`-equivalent hang check).
#
# AUTO_SP=1 skips BOTH the reopen confirmation below and the post-launch hang
# warning's retry gate. Default is interactive: a stray invocation should not
# force-quit someone's live session, or silently loop retries unattended.
set -euo pipefail
# PLATFORM GUARD. macOS only: this drives the Studio Pro GUI through AppleScript
# (`osascript`), which exists on no other platform. Without this guard a Windows or Linux
# user gets a force-quit prompt followed by a silent no-op (there is no `lsof`) — a message about a directory their machine does not have, from a script
# whose real problem is that it can never work there. Say it plainly and stop.
case "$(uname -s)" in
  Darwin) ;;
  *) echo "restart-sp.sh: macOS only — it drives Studio Pro through AppleScript." >&2
     echo "   On $(uname -s), do this by hand instead: close Studio Pro, stop the running app, and reopen the project yourself." >&2
     echo "   See the Platform support section of the toolkit README." >&2
     exit 2 ;;
esac

. "$(dirname "$0")/_common.sh"

MPR="$(find_mpr)" || exit 1
NAME="$(basename "$MPR" .mpr)"
DEPLOYMENT="$PROJECT_ROOT/deployment"
HEALTH_CHECK="$(dirname "$0")/check-sp-health.sh"

if [ "${AUTO_SP:-0}" != "1" ]; then
  read -r -p "This will force-quit and reopen Studio Pro (any unsaved work is lost). Continue? [y/N] " REPLY
  case "$REPLY" in
    [Yy]*) ;;
    *) echo "Aborted — nothing was touched. (Override: AUTO_SP=1 ./bin/restart-sp.sh)"; exit 0 ;;
  esac
fi

# Ports: Mendix's own native runtime port defaults to 8080, but at least one
# project's Docker-mode logs referenced 8081 for the same deployment — confirmed
# 2026-08-04 against a Docker-mode deployment.
# Kill both unconditionally; MENDIX_RUNTIME_PORT adds a third if this project
# uses something else entirely.
EXTRA_PORT="${MENDIX_RUNTIME_PORT:-}"
PORTS="8080,8081${EXTRA_PORT:+,$EXTRA_PORT}"
echo "→ Killing Mendix runtime (ports $PORTS + deployment-path processes)..."
lsof -ti :"$PORTS" 2>/dev/null | xargs kill -9 2>/dev/null || true
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
# NOT `open -a "Mendix Version Selector" "$MPR"`: confirmed 2026-08-04 that this
# fails silently on macOS. `open -a` without --args delivers the file path via
# an "open documents" Apple Event, and the unified log shows tccd denying it —
# Mendix Version Selector.app is missing the com.apple.security.automation.
# apple-events entitlement in its own code signature. The process launches,
# never receives the project path, and quits within seconds with no window.
# That's a bug in Mendix's app bundle, not fixable via a permission toggle.
#
# Fix: skip Version Selector and launch the resolved Studio Pro app directly
# with --args, which passes the path as a plain argv argument — no Apple Events
# involved. find_sp_app already exists for exactly this (used by find_mxbuild);
# it picks the newest installed version, same tradeoff mxbuild already accepts
# — if this project needs an older version, set MENDIX_APP to pin it.
SP_APP="$(find_sp_app)" || exit 1
open -a "$SP_APP" --args "$MPR"

if [ -x "$HEALTH_CHECK" ]; then
  echo "→ Waiting for the new instance to claim the lock file..."
  NEW_PID=""
  for _ in $(seq 1 30); do
    if [ -f "$MPR.lock" ]; then
      NEW_PID=$(grep -oE '"ProcessId":[0-9]+' "$MPR.lock" 2>/dev/null | grep -oE '[0-9]+' || true)
      [ -n "$NEW_PID" ] && break
    fi
    sleep 1
  done

  if [ -z "$NEW_PID" ]; then
    echo "✓ Done — couldn't confirm the new PID (lock file never appeared); click Run Locally when it finishes loading."
    exit 0
  fi

  echo "✓ Opened (PID $NEW_PID). Giving it 60s to finish loading before a health check..."
  sleep 60
  HEALTH_OUTPUT=$("$HEALTH_CHECK" "$NEW_PID" 0 2>&1) && HEALTH_STATUS=0 || HEALTH_STATUS=$?
  echo "$HEALTH_OUTPUT"

  if [ "$HEALTH_STATUS" -eq 1 ]; then
    echo "⚠ Studio Pro looks hung."
    if [ "${AUTO_SP:-0}" = "1" ] && [ "${_SP_RETRIED:-0}" != "1" ]; then
      echo "  AUTO_SP=1 — retrying the reopen once automatically..."
      _SP_RETRIED=1 AUTO_SP=1 exec "$0"
    else
      echo "  Run this script again to force-kill and relaunch it, or check manually."
    fi
  else
    echo "✓ Done — click Run Locally in Studio Pro when it finishes loading."
  fi
else
  echo "✓ Done — click Run Locally in Studio Pro once it finishes loading."
fi
