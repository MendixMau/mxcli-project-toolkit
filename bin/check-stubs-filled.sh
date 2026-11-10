#!/usr/bin/env bash
# check-stubs-filled.sh <project-root> [agent ...] — before dispatching a helper, say whether its
# stub still has unfilled {{PLACEHOLDER}} slots. Default agent: mdl-agent.
#
#   exit 0  every named stub is filled (or absent: then the harness runs a general agent — said out loud)
#   exit 3  at least one stub has unfilled slots; prints "<file>: <n> — <NAMES>" and the remedy
#
# ADVISORY by design (CLAUDE.md guard rule 7): it only reads, so the remedy — filling the stub
# per skills/agent-roles.md — is never blocked by it. The lead runs it before the first dispatch
# of each agent (skills/dispatching.md).
#
# WHY. Speed-night experiment C (2026-11-09): a synced project kept unfilled slots in
# .claude/agents/mdl-agent.md; the first row was dispatched anyway and the agent refused it
# after 125k tokens. init/sync/status already COUNT unfilled slots; nothing said so at dispatch.
# PRODUCER of the input: bin/init-agents.sh (the stub), filled by the lead at Stage 5 kickoff.
# Slot test is bin/lib/placeholders.sh (excludes the {{DOUBLE_BRACE}} prose). Bash 3.2.
set -u
D="$(cd "$(dirname "$0")" && pwd)"
[ $# -ge 1 ] || { echo "usage: bin/check-stubs-filled.sh <project-root> [agent ...]" >&2; exit 2; }
P="$1"; shift
[ -d "$P" ] || { echo "not a directory: $P" >&2; exit 2; }
. "$D/lib/placeholders.sh"
[ $# -gt 0 ] || set -- mdl-agent
rc=0
for a in "$@"; do
  f="$P/.claude/agents/$a.md"
  if [ ! -f "$f" ]; then echo "$a: no stub at .claude/agents/$a.md — a general-purpose agent would run (bin/init-agents.sh $P)"; continue; fi
  ph="$(mxtk_placeholders "$f")"
  if [ -n "$ph" ]; then
    printf '%s\n' "$ph" | while IFS="$(printf '\t')" read -r _f _n _names; do
      _u="$(printf '%s\n' "$_names" | wc -w | tr -d ' ')"
      echo "UNFILLED $a: $_n occurrence(s) of $_u slot(s) — $_names"
    done
    echo "  It will refuse its first row. Fill the stub per skills/agent-roles.md Step 1 before dispatching."
    rc=3
  else
    echo "$a: filled"
  fi
done
exit $rc
