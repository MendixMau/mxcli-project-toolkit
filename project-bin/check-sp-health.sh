#!/usr/bin/env bash
# check-sp-health.sh — is a Studio Pro process actually alive, or hung?
#
# Usage: bin/check-sp-health.sh <pid> [grace_seconds]
# Exit codes: 0 healthy/still-loading  1 hung  2 dead  3 unknown (couldn't tell)
#
# Why not just check CPU%: a healthy, fully-loaded, idle Studio Pro settles to
# ~0% CPU exactly like a hung one does (confirmed 2026-08-04 — a normal launch
# went 102.7% -> 93.9% -> 0.2% CPU as it finished loading; a separate, genuinely
# hung instance also sat near 0%). CPU alone can't tell "done and idle" apart
# from "stuck" — it produced the same number for both.
#
# What actually distinguishes them (also confirmed 2026-08-04, via `sample`):
# an idle, healthy process is parked in a small set of system wait calls
# (event loop / mach_msg / kevent — genuinely nothing to do) that dominate the
# sampling window because they recur every time it's asked "what are you
# doing?". A hung process is ALSO stuck on one unchanging call path the whole
# window — but that path is mid-operation, not one of those known "waiting
# for work" primitives. That's the actual signal: does a single non-idle call
# path account for ~all of the sampling window?
set -euo pipefail

# PLATFORM GUARD. macOS only: this drives the Studio Pro GUI through AppleScript
# (`osascript`), which exists on no other platform. Without this guard a Windows or Linux
# user gets a health verdict derived from tools that are not installed — a message about a directory their machine does not have, from a script
# whose real problem is that it can never work there. Say it plainly and stop.
case "$(uname -s)" in
  Darwin) ;;
  *) echo "check-sp-health.sh: macOS only — it drives Studio Pro through AppleScript." >&2
     echo "   On $(uname -s), do this by hand instead: look at the Studio Pro window: if it responds to a click, it is alive." >&2
     echo "   See the Platform support section of the toolkit README." >&2
     exit 2 ;;
esac

PID="${1:?usage: check-sp-health.sh <pid> [grace_seconds]}"
GRACE="${2:-60}"

if ! kill -0 "$PID" 2>/dev/null; then
  echo "dead: process $PID is not running"
  exit 2
fi

to_seconds() {
  local t="$1" days=0 rest="$1"
  if [[ "$t" == *-* ]]; then days="${t%%-*}"; rest="${t#*-}"; fi
  local IFS=:
  read -ra parts <<< "$rest"
  local secs=0
  for p in "${parts[@]}"; do secs=$((secs * 60 + 10#$p)); done
  echo $((days * 86400 + secs))
}

ELAPSED_RAW=$(ps -o etime= -p "$PID" 2>/dev/null | tr -d ' ')
ELAPSED=$(to_seconds "${ELAPSED_RAW:-0}")

if [[ "$ELAPSED" -lt "$GRACE" ]]; then
  echo "loading: ${ELAPSED}s old, still inside the ${GRACE}s grace window — too early to judge"
  exit 0
fi

CPU=$(ps -o %cpu= -p "$PID" 2>/dev/null | tr -d ' ')
if awk "BEGIN{exit !($CPU > 2)}"; then
  echo "active: ${CPU}% CPU — clearly doing work"
  exit 0
fi

echo "→ Low CPU (${CPU}%) past the grace window — sampling the stack to check for real..."
SAMPLE_FILE=$(mktemp /tmp/sp-health-sample.XXXXXX)
if ! sample "$PID" 3 -file "$SAMPLE_FILE" >/dev/null 2>&1; then
  echo "unknown: couldn't sample PID $PID (process gone mid-check?)"
  rm -f "$SAMPLE_FILE"
  exit 3
fi

# Known "waiting for work" primitives a healthy idle process parks in.
IDLE_PATTERN='_BlockUntilNextEventMatchingListInMode|ReceiveNextEventCommon|mach_msg_trap|mach_msg2_trap|kevent|__psynch|__semwait|__select|__workq_kernreturn|start_wqthread'

# Heaviest single call-tree line (highest leading sample count) — the call
# path that accounted for the largest share of the sampling window.
HEAVY_LINE=$(grep -oE '^ *[0-9]+ .*' "$SAMPLE_FILE" | sort -rn | head -1)

if [[ -z "$HEAVY_LINE" ]]; then
  echo "unknown: couldn't parse sample output ($SAMPLE_FILE) — inspect manually"
  exit 3
fi

if echo "$HEAVY_LINE" | grep -qE "$IDLE_PATTERN"; then
  echo "healthy: idle, parked in a normal wait call — not hung"
  echo "  $HEAVY_LINE"
  rm -f "$SAMPLE_FILE"
  exit 0
else
  echo "HUNG: stuck on one non-idle call path for the whole sampling window"
  echo "  $HEAVY_LINE"
  echo "  full trace: $SAMPLE_FILE"
  exit 1
fi
