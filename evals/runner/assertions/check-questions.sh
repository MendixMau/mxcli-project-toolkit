#!/usr/bin/env bash
# check-questions.sh — verify a session transcript contains expected gate questions
# Usage: bash check-questions.sh --transcript <path> --expected <expected/questions.md>
# Looks for lines starting with > "..." in the expected file and checks each appears in transcript.

set -euo pipefail

TRANSCRIPT=""
EXPECTED=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --transcript) TRANSCRIPT="$2"; shift 2;;
    --expected)   EXPECTED="$2";   shift 2;;
    *) echo "Unknown arg: $1"; exit 1;;
  esac
done

[[ -f "$TRANSCRIPT" ]] || { echo "FAIL: transcript not found: $TRANSCRIPT"; exit 1; }
[[ -f "$EXPECTED" ]]   || { echo "FAIL: expected questions file not found: $EXPECTED"; exit 1; }

FAILS=0
while IFS= read -r line; do
  # Lines starting with > " are question-shape strings to find in the transcript
  if [[ "$line" =~ ^\>\ \"(.+)\" ]]; then
    pattern="${BASH_REMATCH[1]}"
    # Fuzzy: check for first 40 chars of the pattern (handles minor wording variation)
    short="${pattern:0:40}"
    if grep -qiF "$short" "$TRANSCRIPT"; then
      echo "PASS: found question pattern '${short}...'"
    else
      echo "FAIL: question pattern not found: '${short}...' (full: '$pattern')"
      ((FAILS++))
    fi
  fi
done < "$EXPECTED"

if [[ $FAILS -gt 0 ]]; then
  echo "--- $FAILS question check(s) failed ---"
  exit 1
else
  echo "--- All question checks passed ---"
  exit 0
fi
