#!/usr/bin/env bash
# check-artifact.sh — verify an artifact file contains required fields
# Usage: bash check-artifact.sh --artifact <path> --schema <schema.md>
# Schema format: each line starting with a backtick-quoted string is a required substring.
# Exit 0 = all required strings found; exit 1 = failures reported.

set -euo pipefail

ARTIFACT=""
SCHEMA=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --artifact) ARTIFACT="$2"; shift 2;;
    --schema)   SCHEMA="$2";   shift 2;;
    *) echo "Unknown arg: $1"; exit 1;;
  esac
done

[[ -f "$ARTIFACT" ]] || { echo "FAIL: artifact not found: $ARTIFACT"; exit 1; }
[[ -f "$SCHEMA" ]]   || { echo "FAIL: schema not found: $SCHEMA";   exit 1; }

FAILS=0
while IFS= read -r line; do
  # Lines starting with ` (backtick) are required substrings
  if [[ "$line" =~ ^\`(.+)\`$ ]]; then
    pattern="${BASH_REMATCH[1]}"
    if grep -qF "$pattern" "$ARTIFACT"; then
      echo "PASS: found '$pattern'"
    else
      echo "FAIL: missing '$pattern' in $ARTIFACT"
      ((FAILS++))
    fi
  fi
done < "$SCHEMA"

if [[ $FAILS -gt 0 ]]; then
  echo "--- $FAILS check(s) failed ---"
  exit 1
else
  echo "--- All checks passed ---"
  exit 0
fi
