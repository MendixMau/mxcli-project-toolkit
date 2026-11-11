#!/usr/bin/env bash
# Steps 6 to 9 for one topic: compact -> keywords -> gate -> fix -> re-gate -> index.
# Usage: bin/build-topic.sh <topic> [--merge|--force]     (BRAINKIT_CONFIG=path/to/brain.yaml, BRAINKIT_BUDGET=usd per step)
# Stops on the first failing step. A failing gate after one repair round is reported, not looped: read _gate.md and decide.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"; py="${PYTHON:-python3}"
topic="${1:?usage: build-topic.sh <topic> [--merge|--force]}"; shift || true
"$py" "$here/compact.py" --topic "$topic" "$@"
"$py" "$here/keywords.py" --topic "$topic"
set +e; "$py" "$here/gate.py" --topic "$topic"; rc=$?; set -e
if [ $rc -eq 2 ]; then echo "find harness broke: fix the harness, not the notes (see _gate.md)"; exit 2; fi
if [ $rc -ne 0 ]; then
  "$py" "$here/fix.py" --topic "$topic"
  set +e; "$py" "$here/gate.py" --topic "$topic" --checks lint,faith,find; rc=$?; set -e
fi
"$py" "$here/index.py"
[ $rc -eq 0 ] && echo "$topic: PASS" || echo "$topic: gate still failing after one repair round; read brain/internal/$topic/_gate.md"
exit $rc
