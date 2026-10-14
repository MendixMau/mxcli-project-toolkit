#!/usr/bin/env bash
# baseline-approve.sh — a PERSON approves a ratchet baseline move. Run it in a separate terminal
# window of your own — not through the agent, and not via Claude Code's `!` prefix (no TTY there,
# so it is refused).
#
#   bin/baseline-approve.sh lint               # approve the proposal lint-gate.sh just refused
#   bin/baseline-approve.sh conformance        # same, for conformance-check.sh
#   bin/baseline-approve.sh <kind> --current   # approve the baseline file as it is on disk
#                                              # (what gate-check asks for after a hand edit)
#
# It shows the proposed baseline against the current one, asks you to type `approve`, and
# appends one row to .claude/baseline-approvals.tsv: the sha256 of exactly what you saw. The
# instrument then writes that content and nothing else — if the counts change before it re-runs,
# the hash no longer matches and it asks again. Commit the approvals file with the baseline.
#
# WHY A SEPARATE COMMAND (#348): the agent could type `--approved-in-chat` itself. This script
# is denied to the agent in Claude Code (bin/install-claude-permissions.sh), and it refuses
# without a terminal on stdin, which an agent's tool call does not have. See baseline-lock.sh
# for what that does and does not protect against.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK="$(dirname "${BASH_SOURCE[0]}")/baseline-lock.sh"
[ -f "$LOCK" ] || { echo "baseline-approve: $LOCK missing — run the toolkit's bin/sync-project.sh" >&2; exit 2; }

KIND="${1:-}"; CURRENT=0
[ "${2:-}" = "--current" ] && CURRENT=1
case "$KIND" in lint|conformance) ;; *) sed -n '2,10p' "$0"; exit 2 ;; esac

if [ ! -t 0 ]; then
  echo "baseline-approve: REFUSED — no terminal. This is a person's decision: run it yourself, in a" >&2
  echo "separate terminal window — not through an agent, and not via Claude Code's ! prefix." >&2
  exit 2
fi

BASE="$ROOT/$(bash "$LOCK" file "$KIND")"
if [ "$CURRENT" -eq 1 ]; then
  SRC="$BASE"; [ -f "$SRC" ] || { echo "baseline-approve: no $KIND baseline at $SRC" >&2; exit 2; }
  echo "Approving the $KIND baseline AS IT IS ON DISK: $SRC"
  head -60 "$SRC"
else
  SRC="$ROOT/.claude/baseline-pending/$KIND"
  [ -f "$SRC" ] || { echo "baseline-approve: nothing pending for $KIND — run the instrument's --update-baseline first" >&2; exit 2; }
  echo "Proposed $KIND baseline:"
  [ -f "$SRC.summary" ] && sed 's/^/  /' "$SRC.summary"
  echo ""
  if [ -f "$BASE" ]; then diff -u "$BASE" "$SRC" | head -80; else head -60 "$SRC"; fi
fi
SHA="$(bash "$LOCK" sha "$SRC")"
echo ""
printf "Type 'approve' to accept this %s baseline (anything else cancels): " "$KIND"
read -r ANSWER
[ "$ANSWER" = "approve" ] || { echo "Not approved. Nothing written."; exit 1; }

BY="$(git -C "$ROOT" config user.name 2>/dev/null || true)"; BY="${BY:-${USER:-unknown}}"
NOTE="$( [ "$CURRENT" -eq 1 ] && echo "current file" || head -1 "$SRC.summary" 2>/dev/null)"
F="$ROOT/.claude/baseline-approvals.tsv"
[ -f "$F" ] || printf 'ts\tkind\tsha256\tby\tnote\n' > "$F"
printf '%s\t%s\t%s\t%s\t%s\n' "$(bash "$LOCK" now)" "$KIND" "$SHA" "$BY" \
  "$(printf '%s' "$NOTE" | tr '\t\n' '  ')" >> "$F"
if [ "$CURRENT" -eq 1 ]; then
  # The file on disk is now the accepted state: log it, so later writes are checked against it.
  bash "$LOCK" record "$ROOT" "$KIND" approved
  echo "Approved ($(printf '%s' "$SHA" | cut -c1-12)): the $KIND baseline on disk is now the accepted state."
else
  echo "Approved ($(printf '%s' "$SHA" | cut -c1-12)). The agent can now re-run its --update-baseline command."
fi
